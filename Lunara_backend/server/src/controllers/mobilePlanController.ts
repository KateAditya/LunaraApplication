import { Request, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { Op } from 'sequelize';
import Plan, { PlanStatus, PlanPaymentOption } from '../models/Plan';
import PlanJoinRequest, { JoinRequestStatus, JoinPaymentStatus } from '../models/PlanJoinRequest';
import BookingTablePackage, { TablePackageName } from '../models/BookingTablePackage';
import Booking, { BookingStatus, PaymentStatus, GoingMode, BookingPaymentMode } from '../models/Booking';
import Payment, { PaymentMethod, PaymentStatus as TxnStatus } from '../models/Payment';
import User from '../models/User';
import Venue from '../models/Venue';
import UserProfile from '../models/UserProfile';
import PartyPlan, { PartyPlanStatus, PartyPlanVisibility } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus } from '../models/PartyPlanRequest';
import UserPhoto from '../models/UserPhoto';
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
            userId,
            venueId,
            planDate,
            startTime,
            tablePackage: packageName,
            paymentOption = PlanPaymentOption.SPLIT,
            description,
        } = req.body;

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

        const plan = await Plan.create({
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
        });

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
            },
        });
    } catch (err: any) {
        logger.error('postPlan:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── GET /live-feed — List active plans ──────────────────────────────────────
export const getLiveFeed = async (req: Request, res: Response) => {
    try {
        const { viewerId, venueId, date } = req.query;

        let myRequests: any[] = [];
        let incomingRequests: any[] = [];

        const now = new Date();
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

        const tablePlans = await Plan.findAll({
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
                            where: { isPrimary: true },
                            required: false,
                            attributes: ['filePath']
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
        });

        // Query active Party Plans (public, plus user's own private plans)
        const partyPlansWhere: any = {
            status: PartyPlanStatus.ACTIVE,
            isLive: true,
        };
        if (viewerId) {
            partyPlansWhere[Op.or] = [
                { visibility: PartyPlanVisibility.PUBLIC },
                { userId: viewerId as string }
            ];
        } else {
            partyPlansWhere.visibility = PartyPlanVisibility.PUBLIC;
        }
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

        const partyPlans = await PartyPlan.findAll({
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
                            where: { isPrimary: true },
                            required: false,
                            attributes: ['filePath']
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
        });

        // Map Table Plans to consistent payload structure
        const tableFeed = tablePlans.map(p => {
            const host = (p as any).host;
            const matchScore = viewerId
                ? calcMatchScore(viewerId as string, p.userId)
                : Math.floor(Math.random() * 46) + 50;

            return {
                planId: p.id,
                type: 'table_plan',
                host: {
                    id: host?.id,
                    name: host ? `${host.firstName} ${host.lastName?.charAt(0) ?? ''}.` : 'Unknown',
                    age: host?.dateOfBirth ? Math.floor((Date.now() - new Date(host.dateOfBirth).getTime()) / (365.25 * 24 * 60 * 60 * 1000)) : null,
                    occupation: host?.profile?.occupation,
                    bio: host?.profile?.bio,
                    profileImageUrl: host?.profileImageUrl ?? (host?.photos?.[0]?.filePath ? '/' + host.photos[0].filePath.replace(/\\/g, '/') : null),
                },
                venue: (p as any).venue,
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

        // Map Party Plans to consistent payload structure
        const partyFeed = partyPlans.map(p => {
            const creator = (p as any).creator;
            const matchScore = viewerId
                ? calcMatchScore(viewerId as string, p.userId)
                : Math.floor(Math.random() * 46) + 50;

            // Format startTime from planDateTime
            const planDateTime = new Date(p.planDateTime);
            const planTimeStr = planDateTime.toTimeString().substring(0, 5); // "hh:mm"

            return {
                planId: p.id,
                type: 'party_plan',
                host: {
                    id: creator?.id,
                    name: creator ? `${creator.firstName} ${creator.lastName?.charAt(0) ?? ''}.` : 'Unknown',
                    age: creator?.dateOfBirth ? Math.floor((Date.now() - new Date(creator.dateOfBirth).getTime()) / (365.25 * 24 * 60 * 60 * 1000)) : null,
                    occupation: creator?.profile?.occupation,
                    bio: creator?.profile?.bio,
                    profileImageUrl: creator?.profileImageUrl ?? (creator?.photos?.[0]?.filePath ? '/' + creator.photos[0].filePath.replace(/\\/g, '/') : null),
                },
                venue: (p as any).venue,
                planDate: p.planDateTime,
                startTime: planTimeStr,
                description: p.message,
                visibility: p.visibility,
                status: p.status,
                paymentStatus: p.paymentStatus,
                currentJoiners: 0,
                maxJoiners: 1,
                spotsLeft: 1,
                matchScore,
                postedAt: p.createdAt,
            };
        });

        // Merge and sort combined list by postedAt descending
        const combinedFeed = [...tableFeed, ...partyFeed].sort((a, b) => {
            return new Date(b.postedAt).getTime() - new Date(a.postedAt).getTime();
        });

        if (viewerId) {
            // Fetch my outgoing requests for Table Plans
            const myTableReqs = await PlanJoinRequest.findAll({
                where: { requesterId: viewerId as string, status: { [Op.ne]: JoinRequestStatus.CANCELLED } },
                include: [
                    {
                        model: Plan, as: 'plan',
                        include: [{ model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }]
                    }
                ]
            });

            // Fetch my outgoing requests for Party Plans
            const myPartyReqs = await PartyPlanRequest.findAll({
                where: { requesterId: viewerId as string, status: { [Op.ne]: PartyPlanRequestStatus.CANCELLED } },
                include: [
                    {
                        model: PartyPlan, as: 'plan',
                        include: [{ model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }]
                    }
                ]
            });

            // Fetch my Large Party Requests
            const myLargePartyBookings = await Booking.findAll({
                where: {
                    userId: viewerId as string,
                    isLargePartyRequest: true,
                },
                include: [
                    { model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }
                ]
            });

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
                    joinerPaymentStatus: r.joinerPaymentStatus,
                    joinerRazorpayOrderId: r.joinerRazorpayOrderId,
                    plan: r.plan
                })),
                ...myLargePartyBookings.map((b: any) => ({
                    id: b.id,
                    type: 'my_request',
                    requestType: 'large_party_request',
                    status: b.adminApprovalStatus || 'pending',
                    createdAt: b.createdAt,
                    booking: b
                }))
            ].sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

            // Fetch incoming requests for my Table Plans
            const myTablePlans = await Plan.findAll({ where: { userId: viewerId as string }, attributes: ['id', 'planDate', 'startTime'] });
            if (myTablePlans.length > 0) {
                const incomingTableReqs = await PlanJoinRequest.findAll({
                    where: {
                        planId: { [Op.in]: myTablePlans.map(p => p.id) },
                        status: JoinRequestStatus.PENDING
                    },
                    include: [{
                        model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                        include: [{ model: UserPhoto, as: 'photos', where: { isPrimary: true }, required: false, attributes: ['filePath'] }]
                    }]
                });
                incomingRequests.push(...incomingTableReqs.map((r: any) => {
                    const plan = myTablePlans.find(p => p.id === r.planId);
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
                        planDetails: plan,
                        plan: plan
                    };
                }));
            }

            // Fetch incoming requests for my Party Plans
            const myPartyPlans = await PartyPlan.findAll({
                where: { userId: viewerId as string },
                include: [{ model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }]
            });
            if (myPartyPlans.length > 0) {
                const incomingPartyReqs = await PartyPlanRequest.findAll({
                    where: {
                        planId: { [Op.in]: myPartyPlans.map(p => p.id) },
                        status: { [Op.in]: [PartyPlanRequestStatus.PENDING, PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.ACCEPTED] }
                    },
                    include: [{
                        model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                        include: [{ model: UserPhoto, as: 'photos', where: { isPrimary: true }, required: false, attributes: ['filePath'] }]
                    }]
                });
                incomingRequests.push(...incomingPartyReqs.map((r: any) => {
                    const plan = myPartyPlans.find(p => p.id === r.planId);
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
                        joinerPaymentStatus: r.joinerPaymentStatus,
                        joinerRazorpayOrderId: r.joinerRazorpayOrderId,
                        requester: { ...reqUser?.toJSON(), profileImageUrl },
                        planDetails: plan,
                        plan: plan
                    };
                }));
            }

            incomingRequests.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
        }

        return res.json({
            success: true,
            count: combinedFeed.length,
            data: combinedFeed,
            myRequests,
            incomingRequests
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
        const { requesterId, message } = req.body;

        if (!requesterId) return res.status(400).json({ success: false, message: 'requesterId is required' });

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
        const { userId } = req.body; // the user clicking (host or joiner)

        const plan = await Plan.findByPk(id, {
            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }],
        });
        if (!plan) return res.status(404).json({ success: false, message: 'Plan not found' });
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
        const userId = (req.query.userId || req.body.userId) as string;
        if (!userId) return res.status(400).json({ success: false, message: 'userId is required' });

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
        const requesterId = (req.query.userId || req.body.userId) as string;
        if (!requesterId) return res.status(400).json({ success: false, message: 'userId is required' });

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
};
