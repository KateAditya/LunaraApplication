import { Request, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { Op } from 'sequelize';
import Plan, { PlanStatus, PlanPaymentOption } from '../models/Plan';
import PlanTimeLockConfig from '../models/PlanTimeLockConfig';
import PlanTimeLockConfigHistory from '../models/PlanTimeLockConfigHistory';
import { PlanEligibilityService } from '../services/PlanEligibilityService';
import PlanJoinRequest, { JoinRequestStatus, JoinPaymentStatus } from '../models/PlanJoinRequest';
import BookingTablePackage, { TablePackageName } from '../models/BookingTablePackage';
import Booking, { BookingStatus, PaymentStatus, GoingMode, BookingPaymentMode } from '../models/Booking';
import Payment, { PaymentMethod, PaymentStatus as TxnStatus } from '../models/Payment';
import User from '../models/User';
import Venue from '../models/Venue';
import VenueImage from '../models/VenueImage';
import UserProfile from '../models/UserProfile';
import PartyPlan, { PartyPlanStatus } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus } from '../models/PartyPlanRequest';
import UserPhoto from '../models/UserPhoto';
import StrangersMeetRequest from '../models/StrangersMeetRequest';
import StrangersMeetJoiner from '../models/StrangersMeetJoiner';
import GroupParty from '../models/GroupParty';
import SocialConnection, { ConnectionStatus } from '../models/SocialConnection';
import UserMatch from '../models/UserMatch';
import { logger } from '../config/logger';
import Conversation from '../models/Conversation';
import ChatSubscription, { ChatSubscriptionStatus, ChatSubscriptionType } from '../models/ChatSubscription';
import { getChatSettings } from './chatSubscriptionController';

async function autoOpenChat(hostId: string, joinerId: string) {
    try {
        let conv = await Conversation.findOne({
            where: {
                [Op.or]: [
                    { participantOne: hostId, participantTwo: joinerId },
                    { participantOne: joinerId, participantTwo: hostId }
                ]
            }
        });
        if (!conv) {
            conv = await Conversation.create({
                participantOne: hostId,
                participantTwo: joinerId
            });
        }

        // Prevent duplicate chat unlocking
        const existingSub = await ChatSubscription.findOne({
            where: {
                conversationId: conv.id,
                status: ChatSubscriptionStatus.ACTIVE,
                validUntil: { [Op.gt]: new Date() }
            }
        });
        if (existingSub) {
            logger.info(`Active chat subscription already exists for conversation ${conv.id}, skipping creation.`);
            return;
        }

        const freeDays = getChatSettings().freeDays;
        const validUntil = new Date();
        validUntil.setDate(validUntil.getDate() + freeDays);

        await ChatSubscription.create({
            conversationId: conv.id,
            paidById: hostId, // system granted
            amount: 0,
            daysGranted: freeDays,
            validUntil,
            status: ChatSubscriptionStatus.ACTIVE,
            subscriptionType: ChatSubscriptionType.FREE,
        });
    } catch (err: any) {
        logger.error('autoOpenChat error:', err);
    }
}

// Default packages (same as bookingController, auto-seeded per venue)
const DEFAULT_PACKAGES = [
    { name: TablePackageName.SILVER, label: 'Silver', description: 'Up to 5 People • 1 Bottle', price: 500, maxGuests: 5, bottlesIncluded: 1 },
    { name: TablePackageName.GOLD, label: 'Gold', description: 'Up to 8 People • 2 Bottles', price: 900, maxGuests: 8, bottlesIncluded: 2 },
    { name: TablePackageName.PLATINUM, label: 'Platinum', description: 'VIP Table • Unlimited Mixers', price: 1500, maxGuests: 20, bottlesIncluded: 0 },
];

// Simple deterministic match score for testing (replace with preference engine later)
function calcMatchScore(viewerId: string, hostId: string): number {
    const hash = [...(viewerId + hostId)].reduce((acc, c) => acc + c.charCodeAt(0), 0);
    return 50 + (hash % 46); // 50–95%
}

async function seedPackages(venueId: string) {
    const existing = await BookingTablePackage.count({ where: { venueId } });
    if (existing === 0) {
        await BookingTablePackage.bulkCreate(DEFAULT_PACKAGES.map(p => ({ ...p, venueId })));
    }
}

// ─── POST / — Post a Plan to Live Feed ───────────────────────────────────────
export const postPlan = async (req: Request, res: Response) => {
    try {
        const {
            venueId,
            planDate,
            startTime,
            tablePackage: packageName,
            paymentOption = PlanPaymentOption.SPLIT,
            description,
        } = req.body;
        const userId = req.user!.id;

        if (!userId || !venueId || !planDate || !startTime || !packageName) {
            return res.status(400).json({
                success: false,
                message: 'Required: userId, venueId, planDate, startTime, tablePackage',
            });
        }

        // Fetch / seed package
        await seedPackages(venueId);
        const pkg = await BookingTablePackage.findOne({ where: { venueId, name: packageName, isActive: true } });
        if (!pkg) return res.status(400).json({ success: false, message: `Package "${packageName}" not found` });

        const totalAmount = Number(pkg.price);

        // For full payment mode → simulate host pays full now (dummy)
        let hostPaymentStatus = 'pending';
        let hostTransactionId: string | undefined;

        if (paymentOption === PlanPaymentOption.FULL) {
            const ts = Date.now().toString(36).toUpperCase();
            hostTransactionId = `PLAN${ts}${Math.random().toString(36).substring(2, 6).toUpperCase()}`;
            hostPaymentStatus = 'paid';
            // Actual Payment record will be created on secure-reservation
        }

        // Combined start datetime of the plan
        const planStartDateTime = new Date(`${planDate}T${startTime}:00`);
        if (isNaN(planStartDateTime.getTime())) {
            return res.status(400).json({ success: false, message: 'Invalid planDate or startTime format' });
        }

        const plan = await PlanEligibilityService.runAtomicCheckAndCreate(
            userId,
            'upcoming_night',
            planStartDateTime,
            async (transaction) => {
                return await Plan.create({
                    userId,
                    venueId,
                    planDate: new Date(planDate),
                    startTime,
                    tablePackage: packageName,
                    paymentOption,
                    totalAmount,
                    maxJoiners: pkg.maxGuests - 1, // host occupies 1 slot
                    description,
                    hostPaymentStatus,
                    hostTransactionId,
                }, { transaction });
            }
        );

        // Check usage & calculate warning if approaching monthly/cycle limit
        let usageWarning: any = null;
        try {
            const { SubscriptionService } = await import('../services/subscriptionService');
            const now = new Date();
            const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
            const userPlansThisMonth = await Plan.count({
                where: {
                    userId,
                    createdAt: { [Op.gte]: startOfMonth }
                }
            });

            const status = await SubscriptionService.getFullStatus(userId);
            const tier = status.tier || 'FREE';
            let monthlyLimit = 1;
            if (tier === 'CORE') monthlyLimit = 3;
            else if (tier === 'PLUS') monthlyLimit = 5;
            else if (tier === 'PRO') monthlyLimit = 10;
            else if (tier === 'ELITE') monthlyLimit = 9999; // Unlimited

            if (monthlyLimit < 9999) {
                const remaining = Math.max(0, monthlyLimit - userPlansThisMonth);
                const percentage = Math.round((userPlansThisMonth / monthlyLimit) * 100);

                if (percentage >= 75 || remaining <= 1) {
                    usageWarning = {
                        triggered: true,
                        feature: 'party_creation',
                        used: userPlansThisMonth,
                        limit: monthlyLimit,
                        remaining,
                        percentage,
                        message: `You've used ${userPlansThisMonth} of ${monthlyLimit} Party Plans for this month. ${remaining > 0 ? `Only ${remaining} remaining!` : 'Limit reached for this month.'}`,
                    };

                    const NotificationModel = (await import('../models/Notification')).default;
                    const idempotencyKey = `limit_warn_plan_${userId}_${now.getFullYear()}_${now.getMonth()}_${userPlansThisMonth}`;
                    await NotificationModel.findOrCreate({
                        where: { idempotencyKey },
                        defaults: {
                            recipientUserId: userId,
                            eventType: 'LIMIT_WARNING',
                            category: 'system' as any,
                            title: '🎉 Party Plan Creation Alert',
                            body: `You've used ${userPlansThisMonth} of ${monthlyLimit} Party Plans this month. Upgrade to VIP to host unlimited parties!`,
                            actionType: 'open_vip_upgrade',
                            deepLink: '/vip-membership',
                            isRead: false,
                            priority: 'NORMAL' as any,
                            idempotencyKey,
                        }
                    });
                }
            }
        } catch (planWarnErr) {
            logger.warn('Failed to calculate party plan warning:', planWarnErr);
        }

        const venue = await Venue.findByPk(venueId, { attributes: ['id', 'name', 'addressLine1', 'area', 'city'] });

        return res.status(201).json({
            success: true,
            message: 'Plan posted to Live Feed!',
            data: {
                planId: plan.id,
                venue,
                planDate,
                startTime,
                tablePackage: packageName,
                paymentOption,
                totalAmount,
                maxJoiners: plan.maxJoiners,
                status: plan.status,
                hostPaymentStatus,
                usageWarning,
            },
        });
    } catch (err: any) {
        logger.error('postPlan:', err);
        if (err.code && err.code.startsWith('PLAN_')) {
            return res.status(409).json({
                success: false,
                code: err.code,
                message: err.message,
                lock: err.details
            });
        }
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── GET /live-feed — List active plans ──────────────────────────────────────
export const getLiveFeed = async (req: Request, res: Response) => {
    try {
        const { viewerId: requestedViewerId, venueId, date } = req.query;
        const authenticatedUserId = req.user?.id;

        // Public browsing is allowed without a viewer identity. Any request for
        // personalised records must be bound to the authenticated account,
        // never to a caller-controlled query parameter.
        if (requestedViewerId && !authenticatedUserId) {
            return res.status(401).json({ success: false, message: 'Authentication is required for a personalised Live Feed.' });
        }
        if (requestedViewerId && authenticatedUserId && requestedViewerId !== authenticatedUserId) {
            return res.status(403).json({ success: false, message: 'You cannot access another user\'s Live Feed.' });
        }
        const viewerId = authenticatedUserId || undefined;

        const now = new Date();
        const serverTime = now.toISOString();
        const today = new Date();
        today.setHours(0, 0, 0, 0);

        // Query standard Table Plans
        const tablePlansWhere: any = { status: PlanStatus.ACTIVE };
        if (venueId) tablePlansWhere.venueId = venueId;
        if (date) {
            tablePlansWhere.planDate = date;
        } else {
            tablePlansWhere.planDate = { [Op.gte]: today };
        }

        // Find users who have Super Liked viewerId (excluding blocked relationships)
        let superLikedUserIds: string[] = [];
        // Users the viewer has superliked (reverse direction — see below)
        let mySuperlikedUserIds: string[] = [];
        if (viewerId) {
            try {
                const blockedConnections = await SocialConnection.findAll({
                    where: {
                        [Op.or]: [
                            { requesterId: viewerId as string, status: ConnectionStatus.BLOCKED },
                            { receiverId: viewerId as string, status: ConnectionStatus.BLOCKED },
                        ]
                    }
                });
                const blockedIds = new Set<string>();
                for (const bc of blockedConnections) {
                    if (bc.requesterId === viewerId) blockedIds.add(bc.receiverId);
                    if (bc.receiverId === viewerId) blockedIds.add(bc.requesterId);
                }

                const superLikes = await UserMatch.findAll({
                    where: {
                        user2Id: viewerId as string,
                        matchReason: 'superlike',
                    },
                    attributes: ['user1Id']
                });
                superLikedUserIds = superLikes
                    .map(m => m.user1Id)
                    .filter(id => id && !blockedIds.has(id));

                // The reverse relationship: users the VIEWER has superliked.
                // When one of them later posts a party plan, it should be
                // surfaced in the viewer's feed and visually distinguished
                // from the "they superliked you" case above.
                const mySuperlikes = await UserMatch.findAll({
                    where: {
                        user1Id: viewerId as string,
                        matchReason: 'superlike',
                    },
                    attributes: ['user2Id']
                });
                mySuperlikedUserIds = mySuperlikes
                    .map(m => m.user2Id)
                    .filter(id => id && !blockedIds.has(id));
            } catch (slErr) {
                logger.warn('[getLiveFeed] Error fetching superliked users:', slErr);
            }
        }

        // Party Plans are personal workflow cards, not public Live Feed posts.
        const partyPlansWhere: any = viewerId
            ? {
                status: PartyPlanStatus.ACTIVE,
                isLive: true,
                [Op.or]: [
                    { userId: viewerId as string },
                    ...(superLikedUserIds.length > 0
                        ? [{ userId: { [Op.in]: superLikedUserIds }, visibility: 'public' }]
                        : []),
                    ...(mySuperlikedUserIds.length > 0
                        ? [{ userId: { [Op.in]: mySuperlikedUserIds }, visibility: 'public' }]
                        : [])
                ]
            }
            : { id: { [Op.eq]: null } };
        if (venueId) partyPlansWhere.venueId = venueId;
        if (date) {
            const startDate = new Date(date as string);
            startDate.setHours(0, 0, 0, 0);
            const endDate = new Date(date as string);
            endDate.setHours(23, 59, 59, 999);
            partyPlansWhere.planDateTime = {
                [Op.between]: [startDate, endDate]
            };
        } else {
            partyPlansWhere.planDateTime = { [Op.gte]: now };
        }

        const [
            tablePlans,
            partyPlans,
            myTableReqs,
            myPartyReqs,
            myBookings,
            myHostPartyPlans,
            myGroupParties,
            myStrangersMeetReqs,
            myJoinMeets,
            incomingTableReqs,
            incomingPartyReqs,
            incomingStrangerReqs
        ] = await Promise.all([
            // 1. Table Plans
            Plan.findAll({
                where: tablePlansWhere,
                include: [
                    {
                        model: User,
                        as: 'host',
                        attributes: ['id', 'firstName', 'lastName', 'dateOfBirth', 'profileImageUrl'],
                        include: [
                            {
                                model: UserProfile,
                                as: 'profile',
                                attributes: ['occupation', 'bio'],
                            },
                            {
                                model: UserPhoto,
                                as: 'photos',
                                required: false,
                                attributes: ['id', 'filePath', 'isPrimary', 'displayOrder']
                            }
                        ],
                    },
                    {
                        model: Venue,
                        as: 'venue',
                        attributes: ['id', 'name', 'addressLine1', 'area', 'city'],
                        include: [{
                            model: VenueImage,
                            as: 'images',
                            attributes: ['filePath', 'imageType', 'isPrimary', 'displayOrder'],
                            required: false,
                        }],
                    },
                ],
                order: [['createdAt', 'DESC']],
                limit: 50,
            }),

            // 2. Party Plans
            PartyPlan.findAll({
                where: partyPlansWhere,
                include: [
                    {
                        model: User,
                        as: 'creator',
                        attributes: ['id', 'firstName', 'lastName', 'dateOfBirth', 'profileImageUrl'],
                        include: [
                            {
                                model: UserProfile,
                                as: 'profile',
                                attributes: ['occupation', 'bio'],
                            },
                            {
                                model: UserPhoto,
                                as: 'photos',
                                required: false,
                                attributes: ['id', 'filePath', 'isPrimary', 'displayOrder']
                            }
                        ],
                    },
                    {
                        model: Venue,
                        as: 'venue',
                        attributes: ['id', 'name', 'addressLine1', 'area', 'city'],
                    },
                ],
                order: [['createdAt', 'DESC']],
                limit: 50,
            }),

            // 3. My outgoing requests for Table Plans
            viewerId
                ? PlanJoinRequest.findAll({
                    where: { requesterId: viewerId as string, status: { [Op.ne]: JoinRequestStatus.CANCELLED } },
                    include: [
                        {
                            model: Plan, as: 'plan',
                            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }]
                        }
                    ],
                    limit: 30,
                })
                : Promise.resolve([]),

            // 4. My outgoing requests for Party Plans
            viewerId
                ? PartyPlanRequest.findAll({
                    where: { requesterId: viewerId as string, status: { [Op.ne]: PartyPlanRequestStatus.CANCELLED } },
                    include: [
                        {
                            model: PartyPlan, as: 'plan',
                            attributes: ['id', 'userId', 'message', 'planDateTime', 'hostPaymentStatus', 'hostRazorpayOrderId', 'depositAmount', 'status', 'isLive', 'paymentStatus', 'visibility', 'selectedUsers', 'paymentType'],
                            include: [
                                { model: User, as: 'creator', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] },
                                { model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }
                            ]
                        }
                    ],
                    limit: 30,
                })
                : Promise.resolve([]),

            // 5. My Bookings (Solo, Party Request, Large Party, Event Bookings)
            viewerId
                ? Booking.findAll({
                    where: {
                        userId: viewerId as string,
                        status: { [Op.ne]: 'cancelled' },
                    },
                    include: [
                        { model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }
                    ],
                    order: [['createdAt', 'DESC']],
                    limit: 30,
                })
                : Promise.resolve([]),

            // 6. My Host Party Plans (including unpaid deposits)
            viewerId
                ? PartyPlan.findAll({
                    where: {
                        userId: viewerId as string,
                        status: { [Op.ne]: PartyPlanStatus.CANCELLED },
                    },
                    include: [
                        { model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }
                    ],
                    order: [['createdAt', 'DESC']],
                    limit: 20,
                })
                : Promise.resolve([]),

            // 7. My Group Parties (<= 20 friends)
            viewerId
                ? GroupParty.findAll({
                    where: { userId: viewerId as string },
                    include: [
                        { model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }
                    ],
                    limit: 20,
                })
                : Promise.resolve([]),

            // 8. My Strangers Meet Requests
            viewerId
                ? StrangersMeetRequest.findAll({
                    where: { userId: viewerId as string },
                    include: [
                        { model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }
                    ],
                    limit: 20,
                })
                : Promise.resolve([]),

            // 9. My requests to join other Strangers Meets
            viewerId
                ? StrangersMeetJoiner.findAll({
                    where: { userId: viewerId as string },
                    include: [
                        {
                            model: StrangersMeetRequest,
                            as: 'strangersMeetRequest',
                            include: [
                                { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] },
                                { model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }
                            ]
                        }
                    ],
                    limit: 20,
                })
                : Promise.resolve([]),

            // 9. Incoming Table Requests — single JOIN query (no pre-fetch needed)
            viewerId
                ? PlanJoinRequest.findAll({
                    where: { status: JoinRequestStatus.PENDING },
                    include: [
                        {
                            model: Plan, as: 'plan',
                            where: { userId: viewerId as string },
                            attributes: ['id', 'planDate', 'startTime'],
                            required: true,
                        },
                        {
                            model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                            include: [{ model: UserPhoto, as: 'photos', where: { isPrimary: true }, required: false, attributes: ['filePath'] }]
                        }
                    ],
                    limit: 20,
                })
                : Promise.resolve([]),

            // 10. Incoming Party Requests — single JOIN query
            viewerId
                ? PartyPlanRequest.findAll({
                    where: { status: { [Op.in]: [PartyPlanRequestStatus.PENDING, PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.ACCEPTED] } },
                    include: [
                        {
                            model: PartyPlan, as: 'plan',
                            where: { userId: viewerId as string },
                            attributes: ['id', 'userId', 'message', 'planDateTime', 'depositAmount', 'status'],
                            required: true,
                        },
                        {
                            model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                            include: [{ model: UserPhoto, as: 'photos', where: { isPrimary: true }, required: false, attributes: ['filePath'] }]
                        }
                    ],
                    limit: 20,
                })
                : Promise.resolve([]),

            // 11. Incoming Stranger Requests — single JOIN query
            viewerId
                ? StrangersMeetJoiner.findAll({
                    include: [
                        {
                            model: StrangersMeetRequest,
                            as: 'strangersMeetRequest',
                            where: { userId: viewerId as string },
                            required: true,
                        },
                        {
                            model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                            include: [{ model: UserPhoto, as: 'photos', where: { isPrimary: true }, required: false, attributes: ['filePath'] }]
                        }
                    ],
                    limit: 20,
                })
                : Promise.resolve([])
        ]);

        // Map Table Plans
        const tableFeed = tablePlans.map(p => {
            const host = (p as any).host;
            const matchScore = viewerId
                ? calcMatchScore(viewerId as string, p.userId)
                : Math.floor(Math.random() * 46) + 50;

            let hostPhoto = host?.profileImageUrl || null;
            if (!hostPhoto && host?.photos && host.photos.length > 0) {
                const prim = host.photos.find((ph: any) => ph.isPrimary) || host.photos[0];
                if (prim?.filePath) hostPhoto = prim.filePath;
            }
            if (hostPhoto && typeof hostPhoto === 'string' && !hostPhoto.startsWith('http') && !hostPhoto.startsWith('assets/')) {
                const cl = hostPhoto.replace(/\\/g, '/');
                hostPhoto = cl.startsWith('/') ? cl : '/' + cl;
            }

            return {
                planId: p.id,
                type: 'table_plan',
                host: {
                    id: host?.id,
                    name: host ? `${host.firstName} ${host.lastName?.charAt(0) ?? ''}.` : 'Unknown',
                    firstName: host?.firstName,
                    lastName: host?.lastName,
                    age: host?.dateOfBirth ? Math.floor((Date.now() - new Date(host.dateOfBirth).getTime()) / (365.25 * 24 * 60 * 60 * 1000)) : null,
                    occupation: host?.profile?.occupation,
                    bio: host?.profile?.bio,
                    profileImageUrl: hostPhoto,
                    profilePhotoUrl: hostPhoto,
                    photos: host?.photos || [],
                },
                creator: {
                    id: host?.id,
                    name: host ? `${host.firstName} ${host.lastName?.charAt(0) ?? ''}.` : 'Unknown',
                    firstName: host?.firstName,
                    lastName: host?.lastName,
                    profileImageUrl: hostPhoto,
                    profilePhotoUrl: hostPhoto,
                    photos: host?.photos || [],
                },
                hostName: host ? `${host.firstName} ${host.lastName ?? ''}`.trim() : 'Party Host',
                hostProfilePhotoUrl: hostPhoto,
                hostPhotoUrl: hostPhoto,
                profileImageUrl: hostPhoto,
                profilePhotoUrl: hostPhoto,
                venue: (p as any).venue,
                venueImageUrl: (p as any).venue?.images?.[0]?.filePath ?? null,
                planDate: p.planDate,
                startTime: p.startTime,
                tablePackage: p.tablePackage,
                paymentOption: p.paymentOption,
                totalAmount: Number(p.totalAmount),
                currentJoiners: p.currentJoiners,
                maxJoiners: p.maxJoiners,
                spotsLeft: p.maxJoiners - p.currentJoiners,
                matchScore,
                postedAt: p.createdAt,
            };
        });

        // Map Party Plans
        const partyFeed = partyPlans.map(p => {
            const creator = (p as any).creator;
            const isSuperLiked = superLikedUserIds.includes(p.userId) && p.userId !== viewerId;
            const iSuperlikedThem = mySuperlikedUserIds.includes(p.userId) && p.userId !== viewerId;
            const matchScore = viewerId
                ? calcMatchScore(viewerId as string, p.userId)
                : Math.floor(Math.random() * 46) + 50;

            const planDateTime = new Date(p.planDateTime);
            const planTimeStr = planDateTime.toTimeString().substring(0, 5);

            let hostPhoto = creator?.profileImageUrl || null;
            if (!hostPhoto && creator?.photos && creator.photos.length > 0) {
                const prim = creator.photos.find((ph: any) => ph.isPrimary) || creator.photos[0];
                if (prim?.filePath) hostPhoto = prim.filePath;
            }
            if (hostPhoto && typeof hostPhoto === 'string' && !hostPhoto.startsWith('http') && !hostPhoto.startsWith('assets/')) {
                const cl = hostPhoto.replace(/\\/g, '/');
                hostPhoto = cl.startsWith('/') ? cl : '/' + cl;
            }

            const hostObj = {
                id: creator?.id,
                name: creator ? `${creator.firstName} ${creator.lastName?.charAt(0) ?? ''}.` : 'Unknown',
                firstName: creator?.firstName,
                lastName: creator?.lastName,
                age: creator?.dateOfBirth ? Math.floor((Date.now() - new Date(creator.dateOfBirth).getTime()) / (365.25 * 24 * 60 * 60 * 1000)) : null,
                occupation: creator?.profile?.occupation,
                bio: creator?.profile?.bio,
                profileImageUrl: hostPhoto,
                profilePhotoUrl: hostPhoto,
                photos: creator?.photos || [],
            };

            return {
                planId: p.id,
                id: p.id,
                type: 'party_plan',
                userId: p.userId,
                role: viewerId && p.userId === viewerId ? 'host' : 'viewer',
                superLikedYou: isSuperLiked,
                iSuperlikedThem,
                host: hostObj,
                creator: hostObj,
                user: hostObj,
                hostName: creator ? `${creator.firstName} ${creator.lastName ?? ''}`.trim() : 'Party Host',
                hostProfilePhotoUrl: hostPhoto,
                hostPhotoUrl: hostPhoto,
                profileImageUrl: hostPhoto,
                profilePhotoUrl: hostPhoto,
                partyImage: hostPhoto,
                venue: (p as any).venue,
                planDate: p.planDateTime,
                planDateTime: p.planDateTime,
                startTime: planTimeStr,
                description: p.message,
                visibility: p.visibility,
                paymentType: p.paymentType,
                selectedUsers: p.selectedUsers,
                status: p.status,
                paymentStatus: p.paymentStatus,
                hostPaymentStatus: p.hostPaymentStatus,
                hostRazorpayOrderId: p.hostRazorpayOrderId,
                depositAmount: p.depositAmount,
                currentJoiners: 0,
                maxJoiners: 1,
                spotsLeft: 1,
                matchScore,
                postedAt: p.createdAt,
            };
        });

        // Plans from people the viewer superliked are boosted to the top of
        // the feed (above the "they superliked you" case, which is a passive
        // signal rather than something the viewer actively acted on), then
        // everything else falls back to plain recency.
        const combinedFeed = [...tableFeed, ...partyFeed].sort((a, b) => {
            const aBoost = (a as any).iSuperlikedThem ? 1 : 0;
            const bBoost = (b as any).iSuperlikedThem ? 1 : 0;
            if (aBoost !== bBoost) return bBoost - aBoost;
            return new Date(b.postedAt).getTime() - new Date(a.postedAt).getTime();
        });

        let myRequests: any[] = [];
        let incomingRequests: any[] = [];
        let pendingPayments: any[] = [];

        if (viewerId) {
            // Build pending payments list
            const pendingPaymentItems: any[] = [];

            // 1. Pending Bookings (Solo, Event, Large Party, Group)
            myBookings.forEach((b: any) => {
                const isPaid = (b.paymentStatus || '').toLowerCase() === 'paid';
                if (!isPaid && b.status !== 'cancelled' && b.status !== 'rejected') {
                    const dueAmt = Number(b.totalAmount) || Number(b.depositAmount) || 0;
                    pendingPaymentItems.push({
                        id: `pending_bk_${b.id}`,
                        bookingId: b.id,
                        type: 'pending_payment',
                        requestType: 'booking_payment',
                        category: 'booking',
                        paymentCategory: b.isLargePartyRequest ? 'large_party' : (b.goingMode === 'party_request' ? 'group_party' : 'booking'),
                        status: 'payment_pending',
                        paymentStatus: b.paymentStatus || 'pending',
                        amountDue: dueAmt,
                        title: '💳 Booking Payment Pending',
                        body: `Your reservation at ${b.venue?.name || 'Venue'} is awaiting payment (₹${dueAmt}). Tap to complete now.`,
                        venueName: b.venue?.name || 'Venue',
                        venue: b.venue,
                        actionRequired: true,
                        hasPendingPayment: true,
                        createdAt: b.createdAt,
                        bookingDate: b.bookingDate,
                        startTime: b.startTime,
                        numberOfGuests: b.numberOfGuests,
                        payActionPayload: {
                            type: 'booking',
                            bookingId: b.id,
                            venueId: b.venueId,
                            venueName: b.venue?.name,
                            amount: dueAmt,
                            isLargeParty: b.isLargePartyRequest,
                            goingMode: b.goingMode
                        }
                    });
                }
            });

            // 2. Pending Party Plans (Host Deposit)
            myHostPartyPlans.forEach((p: any) => {
                const hostPaid = (p.hostPaymentStatus || '').toLowerCase() === 'paid';
                if (!hostPaid && p.status !== 'cancelled') {
                    const depositAmt = Number(p.depositAmount) || 1999;
                    pendingPaymentItems.push({
                        id: `pending_pp_${p.id}`,
                        planId: p.id,
                        type: 'pending_payment',
                        requestType: 'party_plan_host_deposit',
                        category: 'party_plan',
                        paymentCategory: 'party_plan',
                        status: 'payment_pending',
                        paymentStatus: p.hostPaymentStatus || 'unpaid',
                        amountDue: depositAmt,
                        title: '⚡ Party Plan Deposit Required',
                        body: `Pay ₹${depositAmt} host deposit for your plan at ${p.venue?.name || 'Venue'} to make it live!`,
                        venueName: p.venue?.name || 'Venue',
                        venue: p.venue,
                        actionRequired: true,
                        hasPendingPayment: true,
                        createdAt: p.createdAt,
                        planDateTime: p.planDateTime,
                        payActionPayload: {
                            type: 'party_plan',
                            planId: p.id,
                            venueId: p.venueId,
                            venueName: p.venue?.name,
                            amount: depositAmt,
                            isHost: true
                        }
                    });
                }
            });

            // 3. Pending Party Plan Joiner Requests
            myPartyReqs.forEach((r: any) => {
                const joinerPaid = (r.joinerPaymentStatus || '').toLowerCase() === 'paid';
                if (!joinerPaid && (r.status === 'accepted' || r.status === 'payment_pending')) {
                    const shareAmt = Number(r.plan?.depositAmount) || 1999;
                    pendingPaymentItems.push({
                        id: `pending_pp_join_${r.id}`,
                        requestId: r.id,
                        planId: r.planId,
                        type: 'pending_payment',
                        requestType: 'party_plan_joiner_share',
                        category: 'party_plan',
                        paymentCategory: 'party_plan',
                        status: 'payment_pending',
                        paymentStatus: r.joinerPaymentStatus || 'unpaid',
                        amountDue: shareAmt,
                        title: '🤝 Party Plan Share Payment',
                        body: `Your request was accepted! Pay ₹${shareAmt} to secure your spot at ${r.plan?.venue?.name || 'Venue'}.`,
                        venueName: r.plan?.venue?.name || 'Venue',
                        venue: r.plan?.venue,
                        actionRequired: true,
                        hasPendingPayment: true,
                        createdAt: r.createdAt,
                        paymentTimeoutAt: r.paymentTimeoutAt,
                        payActionPayload: {
                            type: 'party_plan_join',
                            requestId: r.id,
                            planId: r.planId,
                            venueId: r.plan?.venueId,
                            amount: shareAmt,
                            isJoiner: true
                        }
                    });
                }
            });

            // 4. Pending Group Parties
            myGroupParties.forEach((gp: any) => {
                const gpPaid = (gp.paymentStatus || '').toLowerCase() === 'paid';
                if (!gpPaid && gp.status !== 'cancelled') {
                    const gpAmt = Number(gp.totalAmount) || 0;
                    pendingPaymentItems.push({
                        id: `pending_gp_${gp.id}`,
                        groupPartyId: gp.id,
                        type: 'pending_payment',
                        requestType: 'group_party_payment',
                        category: 'group_party',
                        paymentCategory: 'group_party',
                        status: 'payment_pending',
                        paymentStatus: gp.paymentStatus || 'pending',
                        amountDue: gpAmt,
                        title: '👥 Group Party Deposit Pending',
                        body: `Complete payment of ₹${gpAmt} for your group of ${gp.numberOfFriends} friends at ${gp.venue?.name || 'Venue'}.`,
                        venueName: gp.venue?.name || 'Venue',
                        venue: gp.venue,
                        actionRequired: true,
                        hasPendingPayment: true,
                        createdAt: gp.createdAt,
                        partyDate: gp.partyDate,
                        payActionPayload: {
                            type: 'group_party',
                            groupPartyId: gp.id,
                            bookingId: gp.id,
                            venueId: gp.venueId,
                            venueName: gp.venue?.name,
                            amount: gpAmt
                        }
                    });
                }
            });

            // 5. Pending Strangers Meets
            myStrangersMeetReqs.forEach((sm: any) => {
                const smPaid = (sm.paymentStatus || '').toLowerCase() === 'paid';
                if (!smPaid && sm.status !== 'cancelled') {
                    const smAmt = Number(sm.paymentAmount) || 0;
                    pendingPaymentItems.push({
                        id: `pending_sm_${sm.id}`,
                        meetId: sm.id,
                        type: 'pending_payment',
                        requestType: 'stranger_meet_payment',
                        category: 'stranger_meet',
                        paymentCategory: 'stranger_meet',
                        status: 'payment_pending',
                        paymentStatus: sm.paymentStatus || 'pending',
                        amountDue: smAmt,
                        title: '🎭 Stranger Meet Deposit Pending',
                        body: `Pay ₹${smAmt} deposit to host your Stranger Meetup at ${sm.venue?.name || 'Venue'}.`,
                        venueName: sm.venue?.name || 'Venue',
                        venue: sm.venue,
                        actionRequired: true,
                        hasPendingPayment: true,
                        createdAt: sm.createdAt,
                        eventDateTime: sm.eventDateTime,
                        payActionPayload: {
                            type: 'stranger_meet',
                            meetId: sm.id,
                            venueId: sm.venueId,
                            amount: smAmt
                        }
                    });
                }
            });

            pendingPayments = pendingPaymentItems;

            myRequests = [
                ...myTableReqs.map((r: any) => ({
                    id: r.id,
                    type: 'my_request',
                    requestType: 'table_plan',
                    status: r.status,
                    createdAt: r.createdAt,
                    plan: (r as any).plan
                })),
                ...myPartyReqs.map((r: any) => ({
                    id: r.id,
                    type: 'my_request',
                    requestType: 'party_plan',
                    status: r.status,
                    createdAt: r.createdAt,
                    paymentTimeoutAt: r.paymentTimeoutAt,
                    paymentDeadlineAt: r.paymentTimeoutAt,
                    serverTime,
                    joinerPaymentStatus: r.joinerPaymentStatus,
                    joinerRazorpayOrderId: r.joinerRazorpayOrderId,
                    plan: r.plan ? {
                        id: r.plan.id,
                        userId: r.plan.userId,
                        message: r.plan.message,
                        planDateTime: r.plan.planDateTime,
                        hostPaymentStatus: r.plan.hostPaymentStatus,
                        hostRazorpayOrderId: r.plan.hostRazorpayOrderId,
                        depositAmount: r.plan.depositAmount,
                        status: r.plan.status,
                        isLive: r.plan.isLive,
                        paymentStatus: r.plan.paymentStatus,
                        visibility: r.plan.visibility,
                        selectedUsers: r.plan.selectedUsers,
                        paymentType: r.plan.paymentType,
                        venue: (r.plan as any).venue,
                        creator: (r.plan as any).creator,
                    } : null,
                })),

                ...pendingPaymentItems,
                ...myBookings.map((b: any) => ({
                    id: b.id,
                    type: 'my_request',
                    requestType: b.isLargePartyRequest ? 'large_party_request' : (b.goingMode === 'party_request' ? 'group_booking' : 'booking'),
                    status: b.status || 'pending',
                    paymentStatus: b.paymentStatus || 'pending',
                    createdAt: b.createdAt,
                    booking: {
                        id: b.id,
                        bookingId: b.id,
                        venue: b.venue,
                        venueName: b.venue?.name,
                        venueAddress: b.venue?.addressLine1 ?? b.venue?.city ?? '',
                        status: b.status || 'pending',
                        paymentStatus: b.paymentStatus || 'pending',
                        numberOfGuests: b.numberOfGuests,
                        partySubject: b.partySubject || (b.goingMode === 'party_request' ? 'Group Party' : 'Table Booking'),
                        bookingDate: b.bookingDate,
                        startTime: b.startTime,
                        totalAmount: b.totalAmount,
                        depositAmount: b.depositAmount,
                        approvedAmount: b.totalAmount,
                        charges: b.totalAmount,
                        createdAt: b.createdAt,
                        mobileNumber: b.mobileNumber,
                        goingMode: b.goingMode,
                        isLargePartyRequest: b.isLargePartyRequest,
                    }
                })),
                ...myHostPartyPlans.map((p: any) => ({
                    id: p.id,
                    type: 'my_request',
                    requestType: 'party_plan_host',
                    status: p.status || 'active',
                    paymentStatus: p.hostPaymentStatus || 'unpaid',
                    hostPaymentStatus: p.hostPaymentStatus || 'unpaid',
                    depositAmount: p.depositAmount,
                    createdAt: p.createdAt,
                    plan: {
                        id: p.id,
                        userId: p.userId,
                        message: p.message,
                        planDateTime: p.planDateTime,
                        hostPaymentStatus: p.hostPaymentStatus,
                        depositAmount: p.depositAmount,
                        status: p.status,
                        isLive: p.isLive,
                        paymentStatus: p.paymentStatus,
                        venue: p.venue,
                    }
                })),
                ...myGroupParties.map((gp: any) => ({
                    id: gp.id,
                    type: 'my_request',
                    requestType: 'large_party_request',
                    status: gp.status || 'pending',
                    paymentStatus: gp.paymentStatus || 'pending',
                    createdAt: gp.createdAt,
                    booking: {
                        id: gp.id,
                        bookingId: gp.id,
                        venue: gp.venue,
                        venueName: gp.venue?.name,
                        venueAddress: gp.venue?.addressLine1 ?? gp.venue?.city ?? '',
                        status: gp.status || 'pending',
                        paymentStatus: gp.paymentStatus || 'pending',
                        bookingStatus: gp.status || 'pending',
                        numberOfGuests: gp.numberOfFriends,
                        partySubject: 'Group Party',
                        bookingDate: gp.partyDate,
                        startTime: '08:00 PM',
                        approvedAmount: gp.totalAmount,
                        charges: gp.totalAmount,
                        createdAt: gp.createdAt,
                        mobileNumber: gp.mobileNumber,
                        optionalMobileNumber: gp.optionalMobileNumber,
                        goingMode: 'party_request'
                    }
                })),
                ...myStrangersMeetReqs.map((r: any) => ({
                    id: r.id,
                    type: 'my_request',
                    requestType: 'stranger_meet',
                    status: r.status,
                    paymentStatus: r.paymentStatus,
                    paymentAmount: r.paymentAmount,
                    chargesPerHead: r.chargesPerHead,
                    numberOfPersons: r.numberOfPersons,
                    subject: r.subject,
                    tagline: r.tagline,
                    eventDateTime: r.eventDateTime,
                    createdAt: r.createdAt,
                    venue: r.venue,
                })),
                ...myJoinMeets.map((j: any) => {
                    const req = j.strangersMeetRequest;
                    return {
                        id: j.id,
                        type: 'my_request',
                        requestType: 'stranger_meet_join',
                        status: j.status,
                        createdAt: j.createdAt,
                        joinerPaymentStatus: j.paymentStatus,
                        joinerRazorpayOrderId: j.razorpayOrderId,
                        chargesPerHead: req ? Number(req.chargesPerHead) : 0,
                        plan: req ? {
                            id: req.id,
                            subject: req.subject,
                            tagline: req.tagline,
                            eventDateTime: req.eventDateTime,
                            numberOfPersons: req.numberOfPersons,
                            chargesPerHead: Number(req.chargesPerHead),
                            paymentAmount: req.paymentAmount,
                            paymentStatus: req.paymentStatus,
                            status: req.status,
                            user: (req as any).user,
                            venue: (req as any).venue,
                            ticketId: j.paymentStatus === 'paid' ? req.ticketId : null,
                        } : null,
                    };
                })
            ].sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

            // Build incoming requests
            const incomingTableMapped = incomingTableReqs.map((r: any) => {
                const reqUser = r.requester;
                const profileImageUrl = reqUser?.profileImageUrl ?? (reqUser?.photos?.[0]?.filePath ? '/' + reqUser.photos[0].filePath.replace(/\\/g, '/') : null);
                return {
                    id: r.id,
                    type: 'incoming_request',
                    requestType: 'table_plan',
                    planId: r.planId,
                    status: r.status,
                    createdAt: r.createdAt,
                    requester: { ...reqUser?.toJSON(), profileImageUrl },
                };
            });

            const incomingPartyMapped = incomingPartyReqs.map((r: any) => {
                const reqUser = r.requester;
                const profileImageUrl = reqUser?.profileImageUrl ?? (reqUser?.photos?.[0]?.filePath ? '/' + reqUser.photos[0].filePath.replace(/\\/g, '/') : null);
                return {
                    id: r.id,
                    type: 'incoming_request',
                    requestType: 'party_plan',
                    planId: r.planId,
                    status: r.status,
                    createdAt: r.createdAt,
                    paymentTimeoutAt: r.paymentTimeoutAt,
                    paymentDeadlineAt: r.paymentTimeoutAt,
                    serverTime,
                    joinerPaymentStatus: r.joinerPaymentStatus,
                    joinerRazorpayOrderId: r.joinerRazorpayOrderId,
                    requester: { ...reqUser?.toJSON(), profileImageUrl },
                };
            });

            const incomingStrangerMapped = incomingStrangerReqs.map((r: any) => {
                const reqUser = r.user;
                const profileImageUrl = reqUser?.profileImageUrl ?? (reqUser?.photos?.[0]?.filePath ? '/' + reqUser.photos[0].filePath.replace(/\\/g, '/') : null);
                return {
                    id: r.id,
                    type: 'incoming_request',
                    requestType: 'stranger_meet',
                    planId: r.strangersMeetRequestId,
                    status: r.status,
                    createdAt: r.createdAt,
                    joinerPaymentStatus: r.paymentStatus,
                    requester: {
                        id: reqUser?.id,
                        firstName: reqUser?.firstName,
                        lastName: reqUser?.lastName,
                        profileImageUrl,
                    },
                };
            });

            incomingRequests = [...incomingTableMapped, ...incomingPartyMapped, ...incomingStrangerMapped]
                .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
        }

        return res.json({
            success: true,
            count: combinedFeed.length,
            data: combinedFeed,
            myRequests,
            incomingRequests,
            pendingPayments
        });
    } catch (err: any) {
        logger.error('getLiveFeed:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── GET /:id — Plan detail (See Details screen) ─────────────────────────────
export const getPlanDetail = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const { viewerId } = req.query;

        const plan = await Plan.findByPk(id, {
            include: [
                {
                    model: User,
                    as: 'host',
                    attributes: ['id', 'firstName', 'lastName', 'dateOfBirth'],
                    include: [
                        { model: UserProfile, as: 'profile', attributes: ['occupation', 'bio', 'education', 'gender', 'city'] },
                    ],
                },
                { model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] },
                {
                    model: PlanJoinRequest,
                    as: 'joinRequests',
                    where: { status: { [Op.ne]: JoinRequestStatus.CANCELLED } },
                    required: false,
                    attributes: ['id', 'requesterId', 'status', 'paymentStatus', 'shareAmount'],
                },
            ],
        });

        if (!plan) return res.status(404).json({ success: false, message: 'Plan not found' });

        const host = (plan as any).host;
        const matchScore = viewerId ? calcMatchScore(viewerId as string, plan.userId) : 75;
        const spotsLeft = plan.maxJoiners - plan.currentJoiners;

        return res.json({
            success: true,
            data: {
                planId: plan.id,
                status: plan.status,
                matchScore,
                spotsLeft,
                host: {
                    id: host?.id,
                    name: host ? `${host.firstName} ${host.lastName?.charAt(0) ?? ''}.` : 'Unknown',
                    age: host?.dateOfBirth ? Math.floor((Date.now() - new Date(host.dateOfBirth).getTime()) / (365.25 * 24 * 60 * 60 * 1000)) : null,
                    gender: host?.profile?.gender,
                    occupation: host?.profile?.occupation,
                    bio: host?.profile?.bio,
                    education: host?.profile?.education,
                    city: host?.profile?.city,
                },
                venue: (plan as any).venue,
                planDate: plan.planDate,
                startTime: plan.startTime,
                tablePackage: plan.tablePackage,
                paymentOption: plan.paymentOption,
                totalAmount: Number(plan.totalAmount),
                joinRequests: (plan as any).joinRequests ?? [],
                description: plan.description,
            },
        });
    } catch (err: any) {
        logger.error('getPlanDetail:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── POST /:id/join — Send join request (+ simulate payment) ─────────────────
export const joinPlan = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const { message } = req.body;
        const requesterId = req.user!.id;

        const plan = await Plan.findByPk(id);
        if (!plan) return res.status(404).json({ success: false, message: 'Plan not found' });
        if (plan.status !== PlanStatus.ACTIVE) {
            return res.status(400).json({ success: false, message: `Plan is ${plan.status} and not accepting joiners` });
        }
        if (plan.userId === requesterId) {
            return res.status(400).json({ success: false, message: 'You cannot join your own plan' });
        }
        if (plan.currentJoiners >= plan.maxJoiners) {
            return res.status(400).json({ success: false, message: 'This plan is full' });
        }

        // Check if already joined
        const existing = await PlanJoinRequest.findOne({
            where: { planId: id, requesterId, status: { [Op.ne]: JoinRequestStatus.CANCELLED } },
        });
        if (existing) {
            return res.status(400).json({ success: false, message: 'You have already sent a join request for this plan' });
        }

        // Calculate share: totalAmount / (1 host + currentJoiners + 1 new joiner)
        const participants = 1 + plan.currentJoiners + 1;
        const shareAmount = Math.round((Number(plan.totalAmount) / participants) * 100) / 100;

        // Create join request + simulate payment immediately (dummy)
        const ts = Date.now().toString(36).toUpperCase();
        const transactionId = `JOIN${ts}${Math.random().toString(36).substring(2, 6).toUpperCase()}`;

        const joinRequest = await PlanJoinRequest.create({
            planId: id,
            requesterId,
            status: JoinRequestStatus.ACCEPTED, // Auto-accept for dummy flow
            paymentStatus: JoinPaymentStatus.PAID,
            shareAmount,
            transactionId,
            paidAt: new Date(),
            message,
        });

        // Update plan joiner count; mark full if needed
        const newCount = plan.currentJoiners + 1;
        await (plan as any).update({
            currentJoiners: newCount,
            status: newCount >= plan.maxJoiners ? PlanStatus.FULL : PlanStatus.ACTIVE,
        });

        // Open chat for the joiner and the host
        await autoOpenChat(plan.userId, requesterId);

        // Build split summary for payment screen
        const allRequests = await PlanJoinRequest.findAll({
            where: { planId: id, status: { [Op.ne]: JoinRequestStatus.CANCELLED } },
        });
        const totalCollected = allRequests
            .filter(r => r.paymentStatus === JoinPaymentStatus.PAID)
            .reduce((s, r) => s + Number(r.shareAmount), 0);

        const hostShare = Math.round((Number(plan.totalAmount) / participants) * 100) / 100;

        return res.status(201).json({
            success: true,
            message: 'Join request sent and payment simulated. Tap Secure Reservation to get your ticket.',
            data: {
                joinRequestId: joinRequest.id,
                planId: id,
                shareAmount,
                transactionId,
                paymentStatus: JoinPaymentStatus.PAID,
                // Split screen data
                splitSummary: {
                    totalAmount: Number(plan.totalAmount),
                    totalCollected: totalCollected + hostShare,
                    participants,
                    paidParticipants: allRequests.filter(r => r.paymentStatus === JoinPaymentStatus.PAID).length + 1, // +1 host
                },
            },
        });
    } catch (err: any) {
        logger.error('joinPlan:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── GET /:id/split-status — Split payment screen data ───────────────────────
// A plan's private data (split status, ticket, wallet state) may only be viewed
// by its host or one of its (non-cancelled) joiners.
async function isPlanMember(planId: string, planHostId: string, userId: string): Promise<boolean> {
    if (planHostId === userId) return true;
    const joinRequest = await PlanJoinRequest.findOne({
        where: { planId, requesterId: userId, status: { [Op.ne]: JoinRequestStatus.CANCELLED } },
        attributes: ['id'],
    });
    return !!joinRequest;
}

export const getSplitStatus = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;

        const plan = await Plan.findByPk(id, {
            include: [
                { model: Venue, as: 'venue', attributes: ['id', 'name'] },
                {
                    model: PlanJoinRequest,
                    as: 'joinRequests',
                    where: { status: { [Op.ne]: JoinRequestStatus.CANCELLED } },
                    required: false,
                    include: [{ model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName'] }],
                },
            ],
        });
        if (!plan) return res.status(404).json({ success: false, message: 'Plan not found' });
        if (!(await isPlanMember(id, plan.userId, req.user!.id))) {
            return res.status(403).json({ success: false, message: 'You can only view split status for a plan you are part of' });
        }

        const joinRequests = (plan as any).joinRequests ?? [];
        const participants = 1 + joinRequests.length; // host + joiners
        const sharePerPerson = Math.round((Number(plan.totalAmount) / participants) * 100) / 100;
        const paidJoiners = joinRequests.filter((r: any) => r.paymentStatus === JoinPaymentStatus.PAID).length;
        const hostPaid = plan.hostPaymentStatus === 'paid';
        const totalPaid = (hostPaid ? 1 : 0) + paidJoiners;
        const totalCollected = totalPaid * sharePerPerson;

        const memberList = [
            { role: 'host', paymentStatus: plan.hostPaymentStatus, shareAmount: sharePerPerson },
            ...joinRequests.map((r: any) => ({
                role: 'joiner',
                joinRequestId: r.id,
                name: r.requester ? `${r.requester.firstName} ${r.requester.lastName?.charAt(0)}.` : 'Guest',
                shareAmount: Number(r.shareAmount),
                paymentStatus: r.paymentStatus,
            })),
        ];

        return res.json({
            success: true,
            data: {
                planId: plan.id,
                venue: (plan as any).venue,
                planDate: plan.planDate,
                startTime: plan.startTime,
                totalAmount: Number(plan.totalAmount),
                totalCollected,
                participants,
                paidCount: totalPaid,
                pendingCount: participants - totalPaid,
                members: memberList,
            },
        });
    } catch (err: any) {
        logger.error('getSplitStatus:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── POST /:id/secure-reservation — Generate ticket ──────────────────────────
export const securePlanReservation = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const userId = req.user!.id; // the user clicking (host or joiner)

        const plan = await Plan.findByPk(id, {
            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }],
        });
        if (!plan) return res.status(404).json({ success: false, message: 'Plan not found' });
        if (!(await isPlanMember(id, plan.userId, userId))) {
            return res.status(403).json({ success: false, message: 'You can only secure a reservation for a plan you are part of' });
        }
        if (plan.status === PlanStatus.SECURED) {
            // Already secured — just return ticket
            if (plan.bookingId) {
                const booking = await Booking.findByPk(plan.bookingId);
                if (booking) {
                    return res.json({
                        success: true,
                        message: 'Reservation already secured.',
                        data: buildPlanTicket(booking, (plan as any).venue),
                    });
                }
            }
        }

        // Create the Booking record
        const commissionAmount = Math.round(Number(plan.totalAmount) * 0.1 * 100) / 100;
        const ticketCode = uuidv4();

        const booking = await Booking.create({
            bookingNumber: `BKG-PLN-${Math.random().toString(36).substring(2, 8).toUpperCase()}`,
            userId: plan.userId, // host owns the booking
            venueId: plan.venueId,
            bookingDate: plan.planDate,
            startTime: plan.startTime,
            numberOfGuests: plan.currentJoiners + 1,
            totalAmount: plan.totalAmount,
            depositAmount: 0,
            commissionAmount,
            goingMode: GoingMode.PLAN,
            tablePackage: plan.tablePackage,
            paymentMode: plan.paymentOption === PlanPaymentOption.FULL
                ? BookingPaymentMode.PAY_NOW
                : BookingPaymentMode.SPLIT_BILL,
            ticketCode,
            status: BookingStatus.CONFIRMED,
            paymentStatus: PaymentStatus.PAID,
        } as any);

        // Simulate a consolidated payment record
        await Payment.create({
            bookingId: booking.id,
            userId: userId || plan.userId,
            amount: plan.totalAmount,
            paymentMethod: PaymentMethod.CARD,
            paymentGateway: 'DUMMY_PLAN',
            status: TxnStatus.SUCCESSFUL,
            gatewayResponse: { mode: 'test', planId: id, simulatedAt: new Date().toISOString() },
        } as any);

        // Update plan
        await (plan as any).update({ status: PlanStatus.SECURED, bookingId: booking.id });

        return res.json({
            success: true,
            message: 'Reservation secured! Your digital ticket is ready.',
            data: buildPlanTicket(booking, (plan as any).venue),
        });
    } catch (err: any) {
        logger.error('securePlanReservation:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── GET /:id/ticket — Digital ticket for plan booking ───────────────────────
export const getPlanTicket = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;

        const plan = await Plan.findByPk(id, {
            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }],
        });
        if (!plan) return res.status(404).json({ success: false, message: 'Plan not found' });
        if (!(await isPlanMember(id, plan.userId, req.user!.id))) {
            return res.status(403).json({ success: false, message: 'You can only view a ticket for a plan you are part of' });
        }
        if (!plan.bookingId) {
            return res.status(400).json({ success: false, message: 'Ticket not yet generated. Secure reservation first.' });
        }

        const booking = await Booking.findByPk(plan.bookingId);
        if (!booking) return res.status(404).json({ success: false, message: 'Booking not found' });

        return res.json({ success: true, data: buildPlanTicket(booking, (plan as any).venue) });
    } catch (err: any) {
        logger.error('getPlanTicket:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── POST /:id/add-to-wallet ──────────────────────────────────────────────────
export const addPlanToWallet = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;

        const plan = await Plan.findByPk(id);
        if (!plan) return res.status(404).json({ success: false, message: 'Plan not found' });
        if (!(await isPlanMember(id, plan.userId, req.user!.id))) {
            return res.status(403).json({ success: false, message: 'You can only add your own plan to wallet' });
        }
        if (!plan.bookingId) {
            return res.status(400).json({ success: false, message: 'Secure reservation before adding to wallet' });
        }

        const booking = await Booking.findByPk(plan.bookingId);
        if (booking) {
            await (booking as any).update({ addedToWallet: true, status: BookingStatus.COMPLETED });
        }

        return res.json({
            success: true,
            message: 'Added to wallet. Your plan is confirmed!',
            data: { planId: id, bookingId: plan.bookingId, addedToWallet: true },
        });
    } catch (err: any) {
        logger.error('addPlanToWallet:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── GET /my-plans — User's posted plans ─────────────────────────────────────
export const getMyPlans = async (req: Request, res: Response) => {
    try {
        const userId = req.user!.id;

        const plans = await Plan.findAll({
            where: { userId },
            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
            order: [['createdAt', 'DESC']],
        });

        return res.json({ success: true, data: plans });
    } catch (err: any) {
        logger.error('getMyPlans:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── GET /my-joins — Plans the user has joined ───────────────────────────────
export const getMyJoins = async (req: Request, res: Response) => {
    try {
        const requesterId = req.user!.id;

        const joinRequests = await PlanJoinRequest.findAll({
            where: { requesterId, status: { [Op.ne]: JoinRequestStatus.CANCELLED } },
            include: [
                {
                    model: Plan,
                    as: 'plan',
                    include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                },
            ],
            order: [['createdAt', 'DESC']],
        });

        return res.json({ success: true, data: joinRequests });
    } catch (err: any) {
        logger.error('getMyJoins:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── Helper ───────────────────────────────────────────────────────────────────
function buildPlanTicket(booking: Booking, venue: any) {
    return {
        bookingId: booking.id,
        bookingNumber: booking.bookingNumber,
        ticketCode: (booking as any).ticketCode,
        venue,
        bookingDate: booking.bookingDate,
        startTime: booking.startTime,
        tablePackage: booking.tablePackage,
        numberOfGuests: booking.numberOfGuests,
        status: booking.status,
        paymentStatus: booking.paymentStatus,
        goingMode: booking.goingMode,
        addedToWallet: (booking as any).addedToWallet ?? false,
    };
}

export const checkEligibility = async (req: Request, res: Response) => {
    try {
        const { userId, planType, startTime } = req.query;
        if (!userId || !planType || !startTime) {
            return res.status(400).json({
                success: false,
                message: 'Required query params: userId, planType, startTime'
            });
        }
        const result = await PlanEligibilityService.checkEligibility(
            userId as string,
            planType as string,
            new Date(startTime as string)
        );
        return res.json({ success: true, ...result });
    } catch (err: any) {
        logger.error('checkEligibility error:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

export const getAdminTimeLockSettings = async (req: Request, res: Response) => {
    try {
        const { scope = 'global' } = req.query;
        const config = await PlanTimeLockConfig.findOne({ where: { scope: scope as string } });
        if (!config) {
            return res.status(404).json({ success: false, message: `Configuration scope "${scope}" not found.` });
        }
        return res.json({ success: true, data: config });
    } catch (err: any) {
        logger.error('getAdminTimeLockSettings error:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

export const updateAdminTimeLockSettings = async (req: Request, res: Response) => {
    try {
        const {
            adminUserId,
            scope = 'global',
            timeLockEnabled,
            defaultCooldownHours,
            maxActivePlans,
            maxDailyPlans,
            maxWeeklyPlans,
            allowOverlappingPlans,
            allowSameVenue,
            allowDifferentVenue,
            allowFuturePlans,
            allowEmergencyOverride,
            overlapPolicy,
            changeReason
        } = req.body;

        if (!adminUserId) {
            return res.status(400).json({ success: false, message: 'adminUserId is required for audit logs.' });
        }

        const config = await PlanTimeLockConfig.findOne({ where: { scope } });
        if (!config) {
            return res.status(404).json({ success: false, message: `Configuration scope "${scope}" not found.` });
        }

        const previousValue = config.toJSON();

        // Update fields
        if (timeLockEnabled !== undefined) config.timeLockEnabled = timeLockEnabled;
        if (defaultCooldownHours !== undefined) config.defaultCooldownHours = defaultCooldownHours;
        if (maxActivePlans !== undefined) config.maxActivePlans = maxActivePlans;
        if (maxDailyPlans !== undefined) config.maxDailyPlans = maxDailyPlans;
        if (maxWeeklyPlans !== undefined) config.maxWeeklyPlans = maxWeeklyPlans;
        if (allowOverlappingPlans !== undefined) config.allowOverlappingPlans = allowOverlappingPlans;
        if (allowSameVenue !== undefined) config.allowSameVenue = allowSameVenue;
        if (allowDifferentVenue !== undefined) config.allowDifferentVenue = allowDifferentVenue;
        if (allowFuturePlans !== undefined) config.allowFuturePlans = allowFuturePlans;
        if (allowEmergencyOverride !== undefined) config.allowEmergencyOverride = allowEmergencyOverride;
        if (overlapPolicy !== undefined) config.overlapPolicy = overlapPolicy;

        await config.save();

        // Write history/audit trail
        await PlanTimeLockConfigHistory.create({
            configId: config.id,
            adminUserId,
            scope,
            previousValue,
            newValue: config.toJSON(),
            changeReason: changeReason || 'Admin settings update'
        });

        return res.json({ success: true, message: 'Time Lock settings updated successfully.', data: config });
    } catch (err: any) {
        logger.error('updateAdminTimeLockSettings error:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

export default {
    postPlan,
    getLiveFeed,
    getPlanDetail,
    joinPlan,
    getSplitStatus,
    securePlanReservation,
    getPlanTicket,
    addPlanToWallet,
    getMyPlans,
    getMyJoins,
    checkEligibility,
};
