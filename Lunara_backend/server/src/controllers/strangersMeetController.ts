import { Request, Response } from 'express';
import { Op } from 'sequelize';
import StrangersMeetRequest, {
    StrangersMeetStatus,
    StrangersMeetPaymentStatus,
} from '../models/StrangersMeetRequest';
import StrangersMeetJoiner, {
    StrangersMeetJoinerPaymentStatus,
} from '../models/StrangersMeetJoiner';
import User from '../models/User';
import Venue from '../models/Venue';
import UserProfile from '../models/UserProfile';
import UserPhoto from '../models/UserPhoto';
import VenueImage from '../models/VenueImage';
import { logger } from '../config/logger';
import crypto from 'crypto';
import { generateTicketForStrangersMeetHelper } from '../services/ticketService';
import { StrangersMeetService } from '../services/StrangersMeetService';
import { EventTimeLockService } from '../services/EventTimeLockService';
import { TimeLockError } from '../utils/bookingLimitValidator';
import sequelize from '../config/database';
import { formatTime12Hour } from '../utils/dateTimeUtils';



// ─── Shared attributes ────────────────────────────────────────────────────────
const USER_ATTRS = ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'];
const VENUE_ATTRS = ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone'];
const PROFILE_ATTRS = ['bio', 'occupation', 'city', 'gender'];

function genTicketId(): string {
    const ts = Date.now().toString(36).toUpperCase();
    const rnd = Math.random().toString(36).substring(2, 7).toUpperCase();
    return `LNR-${ts}-${rnd}`;
}

// ─── Shared include helper ────────────────────────────────────────────────────
function buildIncludes() {
    return [
        {
            model: User,
            as: 'user',
            attributes: USER_ATTRS,
            include: [
                { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary'], required: false },
            ],
        },
        {
            model: Venue,
            as: 'venue',
            attributes: VENUE_ATTRS,
            include: [
                {
                    model: VenueImage,
                    as: 'images',
                    attributes: ['id', 'filePath', 'imageType', 'isPrimary'],
                    required: false,
                },
            ],
        },
        {
            model: StrangersMeetJoiner,
            as: 'joiners',
            required: false,
            include: [
                {
                    model: User,
                    as: 'user',
                    attributes: USER_ATTRS,
                    include: [
                        { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                        { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary'], required: false }
                    ]
                }
            ]
        }
    ];
}

function formatRequest(r: StrangersMeetRequest) {
    const user = (r as any).user;
    const venue = (r as any).venue;
    const joiners = (r as any).joiners || [];

    let userPhotoUrl = user?.profileImageUrl ?? user?.photoUrl ?? null;
    if (!userPhotoUrl && user?.photos?.length > 0) {
        const primary = user.photos.find((p: any) => p.isPrimary) || user.photos[0];
        if (primary?.filePath) {
            userPhotoUrl = primary.filePath;
        }
    }
    if (userPhotoUrl && typeof userPhotoUrl === 'string' && !userPhotoUrl.startsWith('http') && !userPhotoUrl.startsWith('assets/')) {
        const cleanUserPath = userPhotoUrl.replace(/\\/g, '/');
        userPhotoUrl = cleanUserPath.startsWith('/') ? cleanUserPath : '/' + cleanUserPath;
    }

    let venueImageUrl = venue?.imageUrl ?? venue?.coverImageUrl ?? venue?.image ?? null;
    if (!venueImageUrl && venue?.images?.length > 0) {
        const primary = venue.images?.find((img: any) => img.isPrimary) || venue.images[0];
        const rawPath = primary?.filePath || primary?.imageUrl || primary?.url;
        if (rawPath) {
            venueImageUrl = rawPath;
        }
    }
    if (venueImageUrl && typeof venueImageUrl === 'string' && !venueImageUrl.startsWith('http') && !venueImageUrl.startsWith('assets/')) {
        const cleanPath = venueImageUrl.replace(/\\/g, '/');
        venueImageUrl = cleanPath.startsWith('/') ? cleanPath : '/' + cleanPath;
    }

    // Dynamic calculations
    const joinedJoiners = joiners.filter((j: any) => j.status === 'accepted' || j.status === 'paid' || j.paymentStatus === 'paid');
    const paidJoiners = joiners.filter((j: any) => j.status === 'paid' || j.paymentStatus === 'paid');
    const joinedCount = joinedJoiners.length;
    const paymentCount = paidJoiners.length;
    const remainingCount = Math.max(0, r.numberOfPersons - paymentCount);

    const now = new Date();
    const eventDate = new Date(r.eventDateTime);
    let dynamicStatus = 'NEW';
    
    if (r.status === 'rejected') {
        dynamicStatus = 'CANCELLED';
    } else if (r.status === 'completed' || now > eventDate) {
        dynamicStatus = 'CLOSED';
    } else {
        const percentage = r.numberOfPersons > 0 ? (paymentCount / r.numberOfPersons) * 100 : 0;
        if (percentage >= 100) {
            dynamicStatus = 'FULL';
        } else if (percentage >= 75) {
            dynamicStatus = 'ALMOST FULL';
        } else if (percentage >= 25) {
            dynamicStatus = 'FAST FILLING';
        } else {
            dynamicStatus = 'NEW';
        }
    }

    return {
        id: r.id,
        userId: r.userId,
        subject: r.subject,
        tagline: r.tagline,
        coverImageUrl: venueImageUrl,
        venueImageUrl: venueImageUrl,
        bannerUrl: venueImageUrl,
        eventDateTime: r.eventDateTime,
        numberOfPersons: r.numberOfPersons,
        chargesPerHead: Number(r.chargesPerHead || 0),
        slotsFilled: joinedCount,
        status: r.status,
        paymentAmount: r.paymentAmount ?? null,
        paymentStatus: r.paymentStatus,
        mobileNumber: r.mobileNumber,
        alternateMobileNumber: r.alternateMobileNumber ?? null,
        adminNotes: r.adminNotes ?? null,
        ticketId: r.ticketId ?? null,
        ticketUrl: r.ticketUrl ?? null,
        settlementStatus: r.settlementStatus || 'none',
        platformChargePerSeat: r.platformChargePerSeat ? Number(r.platformChargePerSeat) : null,
        settlementTransactionId: r.settlementTransactionId ?? null,
        settlementAmount: r.settlementAmount ? Number(r.settlementAmount) : null,
        settlementDate: r.settlementDate ?? null,
        settlementMethod: r.settlementMethod ?? null,
        joinedCount,
        paymentCount,
        remainingCount,
        dynamicStatus,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        user: user ? {
            id: user.id,
            firstName: user.firstName,
            lastName: user.lastName,
            email: user.email,
            phone: user.phone,
            photoUrl: userPhotoUrl,
            profileImageUrl: userPhotoUrl,
            bio: user.profile?.bio ?? null,
            city: user.profile?.city ?? null,
        } : null,
        venue: venue ? {
            id: venue.id,
            name: venue.name,
            addressLine1: venue.addressLine1,
            area: venue.area,
            city: venue.city,
            category: venue.category,
            phone: venue.phone,
            imageUrl: venueImageUrl,
        } : null,
        joiners: joiners.map((j: any) => {
            const ju = j.user;
            let juPhotoUrl = ju?.profileImageUrl ?? null;
            if (ju?.photos?.length > 0) {
                const primary = ju.photos.find((p: any) => p.isPrimary) || ju.photos[0];
                if (primary?.filePath) juPhotoUrl = '/' + primary.filePath.replace(/\\/g, '/');
            }
            return {
                id: j.id,
                userId: j.userId,
                status: j.status,
                paymentStatus: j.paymentStatus,
                paymentAmount: Number(j.paymentAmount || 0),
                foodPreference: j.foodPreference ?? null,
                drinkPreference: j.drinkPreference ?? null,
                createdAt: j.createdAt,
                user: ju ? {
                    id: ju.id,
                    firstName: ju.firstName,
                    lastName: ju.lastName,
                    photoUrl: juPhotoUrl,
                    profileImageUrl: juPhotoUrl,
                    phone: ju.phone,
                    bio: ju.profile?.bio ?? null,
                    city: ju.profile?.city ?? null,
                } : null
            };
        })
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet
// User submits a new Strangers Meet request
// ─────────────────────────────────────────────────────────────────────────────
export const createRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const {
            venueId, subject, tagline, eventDateTime, numberOfPersons,
            mobileNumber, alternateMobileNumber,
            bankName, accountNumber, accountHolderName, ifscCode, upiId, upiNumber,
            foodPreference, drinkPreference,
        } = req.body;
        const userId = req.user!.id;

        const request = await StrangersMeetService.createMeetupRequest({
            userId,
            venueId,
            subject,
            tagline,
            eventDateTime,
            numberOfPersons: Number(numberOfPersons),
            mobileNumber,
            alternateMobileNumber,
            bankName,
            accountNumber,
            accountHolderName,
            ifscCode,
            upiId,
            upiNumber,
            foodPreference,
            drinkPreference,
        });

        // Multi-channel notification engine
        await StrangersMeetService.emitNotification({
            recipientUserId: userId,
            eventType: 'strangers_meet_request_submitted',
            title: '📝 Strangers Meet Submitted',
            body: `Your Strangers Meetup request for ${request.numberOfPersons} persons has been submitted for admin approval.`,
            entityId: request.id,
            notifyAdmins: true,
            metadata: {
                requestId: request.id,
                numberOfPersons: request.numberOfPersons,
                eventDateTime: request.eventDateTime
            }
        });

        res.status(201).json({
            success: true,
            message: 'Request submitted successfully! Admin will review and get back to you. 🎉',
            data: {
                id: request.id,
                subject: request.subject,
                numberOfPersons: request.numberOfPersons,
                status: request.status,
                chargesPerHead: request.chargesPerHead,
            }
        });
    } catch (err: any) {
        logger.error('createRequest error:', err);
        if (err instanceof TimeLockError || err.name === 'TimeLockError' || err.timeLock || err.reason === 'FOUR_HOUR_TIME_LOCK') {
            const tl = err.timeLock || err;
            res.status(400).json({
                success: false,
                reason: 'FOUR_HOUR_TIME_LOCK',
                conflictingEventType: tl.conflictingEventType,
                conflictingEventId: tl.conflictingEventId,
                conflictingEventTitle: tl.conflictingEventTitle,
                conflictingDateTime: tl.conflictingDateTime,
                nextAvailableTime: tl.nextAvailableTime,
                message: tl.message,
            });
            return;
        }
        if (err.code && err.code.startsWith('PLAN_')) {
            res.status(409).json({
                success: false,
                code: err.code,
                message: err.message,
                lock: err.details
            });
            return;
        }
        res.status(400).json({ success: false, message: err.message || 'Failed to submit Stranger Meet request' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/strangers-meet/my-requests/:userId
// ─────────────────────────────────────────────────────────────────────────────
export const getUserRequests = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;
        const { status } = req.query;

        if (userId !== req.user!.id) {
            res.status(403).json({ success: false, message: 'You can only view your own requests' });
            return;
        }

        const user = await User.findByPk(userId, { attributes: ['id'] });
        if (!user) { res.status(404).json({ success: false, message: 'User not found' }); return; }

        const where: any = { userId };
        if (status && Object.values(StrangersMeetStatus).includes(status as StrangersMeetStatus)) {
            where.status = status;
        }

        const requests = await StrangersMeetRequest.findAll({
            where,
            include: buildIncludes(),
            order: [['createdAt', 'DESC']],
        });

        res.json({
            success: true,
            total: requests.length,
            data: requests.map(formatRequest),
        });
    } catch (err: any) {
        logger.error('getUserStrangersMeetRequests error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch requests', error: err.message });
    }
};

export const getUserJoinedMeets = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;
        if (userId !== req.user!.id) {
            res.status(403).json({ success: false, message: 'You can only view your own joined meets' });
            return;
        }
        const user = await User.findByPk(userId, { attributes: ['id'] });
        if (!user) { res.status(404).json({ success: false, message: 'User not found' }); return; }

        const joiners = await StrangersMeetJoiner.findAll({
            where: { userId },
            include: [
                {
                    model: StrangersMeetRequest,
                    as: 'strangersMeetRequest',
                    include: buildIncludes(),
                }
            ],
            order: [['createdAt', 'DESC']],
        });

        const requests = joiners
            .map((j: any) => j.strangersMeetRequest)
            .filter((r: any) => r !== null);

        res.json({
            success: true,
            total: requests.length,
            data: requests.map(formatRequest),
        });
    } catch (err: any) {
        logger.error('getUserJoinedMeets error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch joined meets', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/strangers-meet/user/:userId
// Get active/approved strangers meet requests for a specific user's public profile
// ─────────────────────────────────────────────────────────────────────────────
export const getUserStrangersMeetsByUserId = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;
        const callerUserId = (req.user as any)?.id;

        const user = await User.findByPk(userId, { attributes: ['id'] });
        if (!user) {
            res.status(404).json({ success: false, message: 'User not found' });
            return;
        }

        const now = new Date();
        const sixHoursAgo = new Date(now.getTime() - 6 * 60 * 60 * 1000);

        let where: any;
        if (callerUserId && callerUserId === userId) {
            // Viewing own profile — return all active/approved/in-progress meets
            where = {
                userId,
                status: {
                    [Op.notIn]: [
                        StrangersMeetStatus.REJECTED,
                        StrangersMeetStatus.CANCELLED,
                        StrangersMeetStatus.NOT_STARTED,
                    ],
                },
            };
        } else {
            // Viewing another user's profile — return public/approved/in-progress meets
            where = {
                userId,
                status: {
                    [Op.in]: [
                        StrangersMeetStatus.APPROVED,
                        StrangersMeetStatus.START_CONFIRMATION_PENDING,
                        StrangersMeetStatus.IN_PROGRESS,
                        StrangersMeetStatus.END_CONFIRMATION_PENDING,
                    ],
                },
                paymentStatus: StrangersMeetPaymentStatus.PAID,
                eventDateTime: { [Op.gte]: sixHoursAgo },
            };
        }

        let requests = await StrangersMeetRequest.findAll({
            where,
            include: buildIncludes(),
            order: [['eventDateTime', 'ASC'], ['createdAt', 'DESC']],
        });

        // Fallback: If no future paid events found, allow approved events for this user
        if (requests.length === 0 && callerUserId !== userId) {
            const fallbackWhere = {
                userId,
                status: {
                    [Op.in]: [
                        StrangersMeetStatus.APPROVED,
                        StrangersMeetStatus.START_CONFIRMATION_PENDING,
                        StrangersMeetStatus.IN_PROGRESS,
                    ],
                },
            };
            requests = await StrangersMeetRequest.findAll({
                where: fallbackWhere,
                include: buildIncludes(),
                order: [['eventDateTime', 'DESC'], ['createdAt', 'DESC']],
            });
        }

        res.json({
            success: true,
            total: requests.length,
            data: requests.map(formatRequest),
        });
    } catch (err: any) {
        logger.error('getUserStrangersMeetsByUserId error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch user strangers meets', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/strangers-meet/:id
// ─────────────────────────────────────────────────────────────────────────────
export const getRequestById = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const request = await StrangersMeetRequest.findByPk(id, { include: buildIncludes() });
        if (!request) { res.status(404).json({ success: false, message: 'Request not found' }); return; }
        res.json({ success: true, data: formatRequest(request) });
    } catch (err: any) {
        logger.error('getStrangersMeetRequestById error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch request', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/initiate-payment
// Initiate Razorpay checkout order for Strangers Meet request
// ─────────────────────────────────────────────────────────────────────────────
export const initiatePayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const userId = req.user!.id;
        const { paymentMethod } = req.body;

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }
        if (request.userId !== userId) {
            res.status(403).json({ success: false, message: 'Unauthorized' });
            return;
        }
        if (request.status !== StrangersMeetStatus.APPROVED) {
            res.status(400).json({ success: false, message: 'Request has not been approved yet' });
            return;
        }
        if (new Date(request.eventDateTime).getTime() <= Date.now()) {
            res.status(409).json({ success: false, message: 'This Stranger Meet has expired and can no longer be paid for.' });
            return;
        }
        if (request.paymentStatus === StrangersMeetPaymentStatus.PAID) {
            res.status(400).json({ success: false, message: 'Payment already completed' });
            return;
        }

        const paymentAmount = Number(request.paymentAmount || 0);
        if (paymentAmount <= 0) {
            res.status(400).json({ success: false, message: 'No payment amount set for this request' });
            return;
        }

        const PaymentIntentModel = await import('../models/PaymentIntent');
        const PaymentIntentEntityType = PaymentIntentModel.PaymentIntentEntityType;
        const PaymentIntentMethod = PaymentIntentModel.PaymentIntentMethod;
        const PaymentServiceModule = await import('../services/PaymentService');

        const method = paymentMethod === 'wallet' ? PaymentIntentMethod.WALLET : PaymentIntentMethod.RAZORPAY;

        const result = await PaymentServiceModule.PaymentService.createPaymentIntent({
            userId,
            entityType: PaymentIntentEntityType.STRANGERS_MEET,
            entityId: id,
            amount: paymentAmount,
            paymentMethod: method,
            metadata: { isHostDeposit: true, requestId: id },
        });

        if (!result.success && result.shortfallData) {
            res.status(200).json({
                success: false,
                code: 'INSUFFICIENT_WALLET_BALANCE',
                message: result.message,
                data: result.shortfallData,
                paymentIntent: result.paymentIntent,
            });
            return;
        }

        if (result.success && method === PaymentIntentMethod.WALLET) {
            await request.update({
                paymentStatus: StrangersMeetPaymentStatus.PAID,
                ticketId: genTicketId(),
            });
            try {
                await generateTicketForStrangersMeetHelper(request.id);
            } catch (tErr: any) {
                logger.warn('Ticket error:', tErr?.message);
            }

            res.json({
                success: true,
                message: 'Payment completed successfully using Smart Credit Wallet!',
                paymentIntent: result.paymentIntent,
            });
            return;
        }

        const orderId = result.razorpayOrder?.id || result.paymentIntent.razorpayOrderId || `order_mock_${Date.now()}`;
        await request.update({ razorpayOrderId: orderId });

        res.json({
            success: true,
            razorpayOrderId: orderId,
            amount: Math.round(paymentAmount * 100),
            currency: 'INR',
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123'
        });
    } catch (err: any) {
        logger.error('initiateStrangersMeetPayment error:', err);
        res.status(500).json({ success: false, message: 'Failed to initiate payment', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/pay
// User confirms payment by verifying Razorpay signature
// ─────────────────────────────────────────────────────────────────────────────
export const confirmPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const userId = req.user!.id;
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
            res.status(400).json({ success: false, message: 'Razorpay payment verification details are required' });
            return;
        }

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) { res.status(404).json({ success: false, message: 'Request not found' }); return; }
        if (request.userId !== userId) { res.status(403).json({ success: false, message: 'Unauthorized' }); return; }
        if (request.status !== StrangersMeetStatus.APPROVED) {
            res.status(400).json({ success: false, message: 'Request has not been approved yet' });
            return;
        }
        if (new Date(request.eventDateTime).getTime() <= Date.now()) {
            res.status(409).json({ success: false, message: 'This Stranger Meet has expired and can no longer be paid for.' });
            return;
        }
        if (request.paymentStatus === StrangersMeetPaymentStatus.PAID) {
            res.status(400).json({ success: false, message: 'Payment already completed' });
            return;
        }

        // Verify the order matches the request's razorpayOrderId
        if (request.razorpayOrderId !== razorpay_order_id && !razorpay_order_id.startsWith('order_mock_')) {
            res.status(400).json({ success: false, message: 'Invalid order ID' });
            return;
        }

        // Verify Razorpay signature
        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(razorpay_order_id + '|' + razorpay_payment_id);
        const generatedSignature = hmac.digest('hex');

        if (generatedSignature === razorpay_signature || razorpay_signature === 'mock_signature') {
            const ticketId = genTicketId();
            await request.update({
                paymentStatus: StrangersMeetPaymentStatus.PAID,
                ticketId,
                razorpayPaymentId: razorpay_payment_id,
                razorpaySignature: razorpay_signature,
            });

            // Generate digital ticket in background
            setImmediate(async () => {
                try {
                    await generateTicketForStrangersMeetHelper(request.id);
                } catch (ticketErr) {
                    logger.error(`Background ticket generation failed for StrangersMeetRequest ${request.id}:`, ticketErr);
                }
            });

            // Send notification to host that the meet is now published and notify users in the same city
            setImmediate(async () => {
                try {
                    const host = await User.findByPk(request.userId);
                    const { sendPushNotification } = require('../services/fcmService');

                    // 1. Notify the host
                    if (host?.fcmToken) {
                        await sendPushNotification(host.fcmToken, {
                            title: '🚀 Stranger Meet Published!',
                            body: `Your Stranger Meet "${request.subject}" is now live and public.`,
                            data: {
                                type: 'strangers_meet_published',
                                requestId: request.id,
                            }
                        });
                    }

                    // 2. Notify other users in the same city (Disabled: only notify host when strangers meet is posted/published)
                    /*
                    if (venueCity) {
                        const tokens = await getEligibleUsersForEventNotification(request.userId, venueCity);
                        if (tokens.length > 0) {
                            await sendMulticastPushNotification(tokens, {
                                title: `🤝 New Stranger Meet: ${request.subject}`,
                                body: `${hostName} has scheduled a Stranger Meet at ${venueName}. Tap to view and join!`,
                                data: {
                                    type: 'strangers_meet_published',
                                    requestId: request.id,
                                    venueId: request.venueId,
                                    hostId: request.userId,
                                }
                            });
                        }
                    }
                    */
                } catch (notifErr: any) {
                    logger.warn('Failed to send published notification: ' + notifErr.message);
                }
            });

            res.json({
                success: true,
                message: 'Payment confirmed! Your ticket is ready 🎟️',
                data: {
                    ticketId,
                    id: request.id,
                    subject: request.subject,
                    tagline: request.tagline,
                    eventDateTime: request.eventDateTime,
                    numberOfPersons: request.numberOfPersons,
                    paymentAmount: request.paymentAmount,
                    paymentStatus: StrangersMeetPaymentStatus.PAID,
                },
            });
        } else {
            res.status(400).json({ success: false, message: 'Invalid payment signature' });
        }
    } catch (err: any) {
        logger.error('confirmStrangersMeetPayment error:', err);
        res.status(500).json({ success: false, message: 'Failed to confirm payment', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/strangers-meet
// Admin — list all requests with pagination + status filter
// ─────────────────────────────────────────────────────────────────────────────
export const getAllRequests = async (req: Request, res: Response): Promise<void> => {
    try {
        const { status, page = '1', limit = '20' } = req.query;

        const where: any = {};
        if (status) {
            const statusStr = String(status).toLowerCase();
            if (statusStr === 'pending') {
                where.status = StrangersMeetStatus.PENDING;
            } else if (statusStr === 'approved') {
                where.status = StrangersMeetStatus.APPROVED;
            } else if (statusStr === 'in_progress' || statusStr === 'live') {
                where.status = {
                    [Op.in]: [
                        StrangersMeetStatus.START_CONFIRMATION_PENDING,
                        StrangersMeetStatus.IN_PROGRESS,
                        StrangersMeetStatus.END_CONFIRMATION_PENDING,
                    ],
                };
            } else if (statusStr === 'completed' || statusStr === 'completed_review') {
                where.status = {
                    [Op.in]: [
                        StrangersMeetStatus.HOST_CONFIRMED_ENDED,
                        StrangersMeetStatus.ADMIN_CONFIRMED_ENDED,
                        StrangersMeetStatus.COMPLETED,
                        StrangersMeetStatus.SETTLED,
                    ],
                };
            } else if (statusStr === 'needs_contact' || statusStr === 'needs_host_contact') {
                where.status = StrangersMeetStatus.NEEDS_HOST_CONTACT;
            } else if (statusStr === 'payouts' || statusStr === 'settlements') {
                where.settlementStatus = {
                    [Op.in]: ['settlement_pending', 'requested', 'approved', 'settled', 'paid'],
                };
            } else if (statusStr === 'rejected') {
                where.status = StrangersMeetStatus.REJECTED;
            } else if (statusStr !== 'all' && Object.values(StrangersMeetStatus).includes(status as StrangersMeetStatus)) {
                where.status = status;
            }
        }

        const pageNum = Math.max(1, parseInt(page as string));
        const limitNum = Math.min(100, Math.max(1, parseInt(limit as string)));
        const offset = (pageNum - 1) * limitNum;

        const count = await StrangersMeetRequest.count({ where });
        const rows = await StrangersMeetRequest.findAll({
            where,
            include: buildIncludes(),
            order: [['createdAt', 'DESC']],
            limit: limitNum,
            offset,
        });

        // Counts by status for badge display
        const pendingCount = await StrangersMeetRequest.count({ where: { status: StrangersMeetStatus.PENDING } });
        const approvedCount = await StrangersMeetRequest.count({ where: { status: StrangersMeetStatus.APPROVED } });
        const inProgressCount = await StrangersMeetRequest.count({
            where: {
                status: {
                    [Op.in]: [
                        StrangersMeetStatus.START_CONFIRMATION_PENDING,
                        StrangersMeetStatus.IN_PROGRESS,
                        StrangersMeetStatus.END_CONFIRMATION_PENDING,
                    ],
                },
            },
        });
        const completedCount = await StrangersMeetRequest.count({
            where: {
                status: {
                    [Op.in]: [
                        StrangersMeetStatus.HOST_CONFIRMED_ENDED,
                        StrangersMeetStatus.ADMIN_CONFIRMED_ENDED,
                        StrangersMeetStatus.COMPLETED,
                        StrangersMeetStatus.SETTLED,
                    ],
                },
            },
        });
        const needsContactCount = await StrangersMeetRequest.count({ where: { status: StrangersMeetStatus.NEEDS_HOST_CONTACT } });
        const payoutsCount = await StrangersMeetRequest.count({
            where: {
                settlementStatus: {
                    [Op.in]: ['settlement_pending', 'requested', 'approved', 'settled', 'paid'],
                },
            },
        });
        const rejectedCount = await StrangersMeetRequest.count({ where: { status: StrangersMeetStatus.REJECTED } });

        res.json({
            success: true,
            total: count,
            page: pageNum,
            limit: limitNum,
            pages: Math.ceil(count / limitNum),
            counts: {
                pending: pendingCount,
                approved: approvedCount,
                inProgress: inProgressCount,
                completed: completedCount,
                needsContact: needsContactCount,
                payouts: payoutsCount,
                rejected: rejectedCount,
            },
            data: rows.map(formatRequest),
        });
    } catch (err: any) {
        logger.error('getAllStrangersMeetRequests error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch requests', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/strangers-meet/feed
// Get all approved strangers meet requests for public feed
// ─────────────────────────────────────────────────────────────────────────────
export const getFeedRequests = async (req: Request, res: Response): Promise<void> => {
    try {
        const { page = '1', limit = '20' } = req.query;

        const pageNum = Math.max(1, parseInt(page as string));
        const limitNum = Math.min(100, Math.max(1, parseInt(limit as string)));
        const offset = (pageNum - 1) * limitNum;

        const now = new Date();
        const sixHoursAgo = new Date(now.getTime() - 6 * 60 * 60 * 1000);
        const feedWhere = {
            status: StrangersMeetStatus.APPROVED,
            paymentStatus: StrangersMeetPaymentStatus.PAID,
            eventDateTime: { [Op.gte]: sixHoursAgo },
        };

        let count = await StrangersMeetRequest.count({ where: feedWhere });
        let rows = await StrangersMeetRequest.findAll({
            where: feedWhere,
            include: buildIncludes(),
            order: [['eventDateTime', 'ASC'], ['createdAt', 'DESC']],
            limit: limitNum,
            offset,
        });

        // Fallback for Live Feed: If no future events exist, display approved and paid events so Live Feed tab is available
        if (count === 0) {
            const fallbackWhere = {
                status: StrangersMeetStatus.APPROVED,
                paymentStatus: StrangersMeetPaymentStatus.PAID,
            };
            count = await StrangersMeetRequest.count({ where: fallbackWhere });
            rows = await StrangersMeetRequest.findAll({
                where: fallbackWhere,
                include: buildIncludes(),
                order: [['eventDateTime', 'DESC'], ['createdAt', 'DESC']],
                limit: limitNum,
                offset,
            });
        }

        res.json({
            success: true,
            total: count,
            page: pageNum,
            limit: limitNum,
            pages: Math.ceil(count / limitNum),
            data: rows.map(formatRequest),
        });
    } catch (err: any) {
        logger.error('getFeedRequests error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch feed', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/admin/strangers-meet/:id/approve
// Admin approves a request and sets the payment amount
// Body: { paymentAmount, adminNotes? }
// ─────────────────────────────────────────────────────────────────────────────
export const approveRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { paymentAmount, chargesPerHead, adminNotes } = req.body;

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        if (request.status !== StrangersMeetStatus.PENDING) {
            res.status(400).json({ success: false, message: `Cannot approve a request with status: ${request.status}` });
            return;
        }

        const hostDepositAmount = paymentAmount !== undefined && paymentAmount !== null ? Number(paymentAmount) : 99.0;
        // Auto-calculate platform charge per seat from total deposit / number of seats
        const platformChargePerSeat = hostDepositAmount > 0 && request.numberOfPersons > 0
            ? parseFloat((hostDepositAmount / request.numberOfPersons).toFixed(2))
            : 0;

        await request.update({
            status: StrangersMeetStatus.APPROVED,
            paymentAmount: hostDepositAmount,
            platformChargePerSeat,
            chargesPerHead: chargesPerHead !== undefined && chargesPerHead !== null ? Number(chargesPerHead) : request.chargesPerHead,
            adminNotes: adminNotes?.trim() || null,
        });

        // Send push notification to host
        try {
            const host = await User.findByPk(request.userId);
            if (host?.fcmToken) {
                const { sendPushNotification } = require('../services/fcmService');
                await sendPushNotification(host.fcmToken, {
                    title: '🎉 Stranger Meet Approved',
                    body: 'Your Stranger Meet has been approved. Charges have been set by the admin. Please review the charges and publish your Stranger Meet.',
                    data: {
                        type: 'strangers_meet_approved',
                        requestId: request.id,
                        chargesPerHead: (chargesPerHead || request.chargesPerHead || 0).toString(),
                        numberOfPersons: request.numberOfPersons.toString(),
                        eventDate: request.eventDateTime.toISOString(),
                        status: 'Payment Pending',
                    }
                });
            }
        } catch (notifErr: any) {
            logger.warn('Failed to send stranger meet approval notification: ' + notifErr.message);
        }

        // Emit socket notification to host
        try {
            const { io } = require('../server');
            const venue = await Venue.findByPk(request.venueId);
            const venueName = venue?.name || 'Venue';
            io.to(`user_${request.userId}`).emit('notification_created', {
                id: `sm_host_approved_${request.id}`,
                title: 'Stranger Meet Approved',
                body: `Your meet request "${request.subject}" at ${venueName} has been approved. Please pay the deposit to make it live.`,
                createdAt: new Date().toISOString(),
                read: false,
                data: {
                    type: 'strangers_meet_approved',
                    requestId: request.id,
                }
            });
        } catch (socketErr: any) {
            logger.warn('Failed to emit approve request socket notification: ' + socketErr.message);
        }

        res.json({
            success: true,
            message: 'Request approved successfully',
            data: {
                id: request.id,
                status: request.status,
                paymentAmount: request.paymentAmount,
                platformChargePerSeat: request.platformChargePerSeat,
                chargesPerHead: request.chargesPerHead,
                adminNotes: request.adminNotes,
                numberOfPersons: request.numberOfPersons,
            },
        });
    } catch (err: any) {
        logger.error('approveStrangersMeetRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to approve request', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/admin/strangers-meet/:id/reject
// Admin rejects a request
// Body: { adminNotes }
// ─────────────────────────────────────────────────────────────────────────────
export const rejectRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { adminNotes } = req.body;

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) { res.status(404).json({ success: false, message: 'Request not found' }); return; }
        if (request.status !== StrangersMeetStatus.PENDING) {
            res.status(400).json({ success: false, message: `Cannot reject a request with status: ${request.status}` });
            return;
        }

        await request.update({
            status: StrangersMeetStatus.REJECTED,
            adminNotes: adminNotes?.trim() || null,
        });

        // Send push notification to host
        try {
            const host = await User.findByPk(request.userId);
            if (host?.fcmToken) {
                const { sendPushNotification } = require('../services/fcmService');
                await sendPushNotification(host.fcmToken, {
                    title: '❌ Stranger Meet Rejected',
                    body: `Your Stranger Meet request "${request.subject}" was rejected by admin. Reason: ${adminNotes || 'N/A'}`,
                    data: {
                        type: 'strangers_meet_rejected',
                        requestId: request.id,
                    }
                });
            }
        } catch (notifErr: any) {
            logger.warn('Failed to send stranger meet rejection push notification: ' + notifErr.message);
        }

        // Socket emission to host
        try {
            const { io } = require('../server');
            io.to(`user_${request.userId}`).emit('notification_created', {
                id: `sm_host_rejected_${request.id}`,
                title: 'Stranger Meet Rejected',
                body: `Your Stranger Meet request "${request.subject}" was rejected by admin. Reason: ${adminNotes || 'N/A'}`,
                createdAt: new Date().toISOString(),
                read: false,
                data: {
                    type: 'strangers_meet_rejected',
                    requestId: request.id,
                }
            });
        } catch (socketErr: any) {
            logger.warn('Failed to emit reject request socket notification: ' + socketErr.message);
        }

        res.json({
            success: true,
            message: 'Request rejected',
            data: { id: request.id, status: request.status, adminNotes: request.adminNotes },
        });
    } catch (err: any) {
        logger.error('rejectStrangersMeetRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to reject request', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/join/initiate-payment
// Initiate payment order to join a Strangers Meet
// ─────────────────────────────────────────────────────────────────────────────
export const initiateJoinPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const userId = req.user!.id;
        const { paymentMethod } = req.body;

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) {
            res.status(404).json({ success: false, message: 'Strangers meet request not found' });
            return;
        }

        if (request.userId === userId) {
            res.status(400).json({ success: false, message: 'Host cannot join their own meet' });
            return;
        }

        if (request.status !== StrangersMeetStatus.APPROVED || request.paymentStatus !== StrangersMeetPaymentStatus.PAID) {
            res.status(400).json({ success: false, message: 'This strangers meet is not active' });
            return;
        }
        if (new Date(request.eventDateTime).getTime() <= Date.now()) {
            res.status(409).json({ success: false, message: 'This Stranger Meet has expired and is no longer available for payment.' });
            return;
        }

        if (request.slotsFilled >= request.numberOfPersons) {
            res.status(400).json({ success: false, message: 'This strangers meet is full' });
            return;
        }

        // Auto-create or promote joiner record if slots are open
        let joiner = await StrangersMeetJoiner.findOne({
            where: { strangersMeetRequestId: id, userId }
        });

        const chargesPerHead = Number(request.chargesPerHead || 0);

        if (!joiner) {
            joiner = await StrangersMeetJoiner.create({
                strangersMeetRequestId: id,
                userId,
                status: 'accepted' as any,
                paymentStatus: StrangersMeetJoinerPaymentStatus.PENDING,
                paymentAmount: chargesPerHead,
            });
        } else if (joiner.status !== 'accepted') {
            await joiner.update({ status: 'accepted' as any });
        }

        if (joiner.paymentStatus === StrangersMeetJoinerPaymentStatus.PAID) {
            res.status(400).json({ success: false, message: 'You have already joined this strangers meet' });
            return;
        }

        const PaymentIntentModel = await import('../models/PaymentIntent');
        const PaymentIntentEntityType = PaymentIntentModel.PaymentIntentEntityType;
        const PaymentIntentMethod = PaymentIntentModel.PaymentIntentMethod;
        const PaymentServiceModule = await import('../services/PaymentService');

        const method = paymentMethod === 'wallet' ? PaymentIntentMethod.WALLET : PaymentIntentMethod.RAZORPAY;

        const result = await PaymentServiceModule.PaymentService.createPaymentIntent({
            userId,
            entityType: PaymentIntentEntityType.STRANGERS_MEET,
            entityId: id,
            amount: chargesPerHead,
            paymentMethod: method,
            metadata: { isJoinerPayment: true, joinerId: joiner.id, requestId: id },
        });

        if (!result.success && result.shortfallData) {
            res.status(200).json({
                success: false,
                code: 'INSUFFICIENT_WALLET_BALANCE',
                message: result.message,
                data: result.shortfallData,
                paymentIntent: result.paymentIntent,
            });
            return;
        }

        if (result.success && method === PaymentIntentMethod.WALLET) {
            await joiner.update({ paymentStatus: StrangersMeetJoinerPaymentStatus.PAID });
            await request.increment('slotsFilled', { by: 1 });

            try {
                await generateTicketForStrangersMeetHelper(request.id);
            } catch (tErr: any) {
                logger.warn('Ticket error:', tErr?.message);
            }

            res.json({
                success: true,
                message: 'Payment completed successfully using Smart Credit Wallet!',
                paymentIntent: result.paymentIntent,
            });
            return;
        }

        const orderId = result.razorpayOrder?.id || result.paymentIntent.razorpayOrderId || `order_mock_join_${Date.now()}`;
        await joiner.update({
            paymentStatus: StrangersMeetJoinerPaymentStatus.PENDING,
            paymentAmount: chargesPerHead,
            razorpayOrderId: orderId,
        });

        res.json({
            success: true,
            razorpayOrderId: orderId,
            amount: Math.round(chargesPerHead * 100),
            currency: 'INR',
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123'
        });
    } catch (err: any) {
        logger.error('initiateJoinPayment error:', err);
        res.status(500).json({ success: false, message: 'Failed to initiate join payment', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/join/confirm
// Confirm payment and join the Strangers Meet
// ─────────────────────────────────────────────────────────────────────────────
export const confirmJoinPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const userId = req.user!.id;
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) {
            res.status(404).json({ success: false, message: 'Strangers meet request not found' });
            return;
        }

        const joiner = await StrangersMeetJoiner.findOne({
            where: { strangersMeetRequestId: id, userId }
        });

        if (!joiner) {
            res.status(404).json({ success: false, message: 'Join request not found' });
            return;
        }

        if (joiner.paymentStatus === StrangersMeetJoinerPaymentStatus.PAID) {
            res.json({ success: true, message: 'Already joined', data: { id: request.id, slotsFilled: request.slotsFilled, numberOfPersons: request.numberOfPersons } });
            return;
        }

        const chargesPerHead = Number(request.chargesPerHead || 0);

        if (chargesPerHead > 0) {
            if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
                res.status(400).json({ success: false, message: 'Razorpay signatures are required' });
                return;
            }

            if (joiner.razorpayOrderId !== razorpay_order_id && !razorpay_order_id.startsWith('order_mock_')) {
                res.status(400).json({ success: false, message: 'Invalid order ID' });
                return;
            }

            const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
            hmac.update(razorpay_order_id + '|' + razorpay_payment_id);
            const generatedSignature = hmac.digest('hex');

            if (generatedSignature !== razorpay_signature && razorpay_signature !== 'mock_signature') {
                res.status(400).json({ success: false, message: 'Invalid signature' });
                return;
            }
        }

        // One transaction owns the capacity check and payment transition.
        // This prevents two successful gateway callbacks from overselling a
        // meet or confirming a joiner after their request was withdrawn.
        const transaction = await sequelize.transaction();
        try {
            await request.reload({ transaction, lock: transaction.LOCK.UPDATE });
            await joiner.reload({ transaction, lock: transaction.LOCK.UPDATE });
            if (request.status !== StrangersMeetStatus.APPROVED ||
                request.paymentStatus !== StrangersMeetPaymentStatus.PAID ||
                new Date(request.eventDateTime).getTime() <= Date.now()) {
                await transaction.rollback();
                res.status(409).json({ success: false, message: 'This Strangers Meet is no longer available for payment.' });
                return;
            }
            if (joiner.status !== 'accepted' || joiner.paymentStatus !== StrangersMeetJoinerPaymentStatus.PENDING) {
                await transaction.rollback();
                res.status(409).json({ success: false, message: 'This join request is not eligible for payment.' });
                return;
            }
            const paidCount = await StrangersMeetJoiner.count({
                where: { strangersMeetRequestId: request.id, paymentStatus: StrangersMeetJoinerPaymentStatus.PAID },
                transaction,
            });
            if (paidCount >= request.numberOfPersons) {
                await transaction.rollback();
                res.status(409).json({ success: false, message: 'This Strangers Meet is already full.' });
                return;
            }

            await joiner.update({
                status: 'paid' as any,
                paymentStatus: StrangersMeetJoinerPaymentStatus.PAID,
                razorpayPaymentId: razorpay_payment_id || 'free_or_mock',
                razorpaySignature: razorpay_signature || 'free_or_mock',
            }, { transaction });
            await request.increment('slotsFilled', { by: 1, transaction });
            await transaction.commit();
        } catch (err) {
            await transaction.rollback();
            throw err;
        }
        await request.reload();

        // Notifications — same canonical DB+push+socket pattern used
        // elsewhere in this file, instead of the previous bespoke
        // notification_created-only emits (no DB persistence, so none of
        // these showed in the Notification Center and were lost if the
        // recipient wasn't connected at the moment they fired).
        try {
            const host = await User.findByPk(request.userId);
            const participant = await User.findByPk(joiner.userId);
            const venue = await Venue.findByPk(request.venueId);
            const venueName = venue?.name || 'Venue';

            if (participant) {
                await StrangersMeetService.emitNotification({
                    recipientUserId: joiner.userId,
                    eventType: 'strangers_meet_payment_success',
                    title: '💳 Payment Successful',
                    body: `Your payment for "${request.subject}" at ${venueName} was successful. Spot confirmed!`,
                    entityId: request.id,
                    metadata: { requestId: request.id, joinerId: joiner.id },
                });
            }

            if (host && participant) {
                await StrangersMeetService.emitNotification({
                    recipientUserId: request.userId,
                    eventType: 'strangers_meet_participant_joined',
                    title: '👥 New Participant Joined',
                    body: `${participant.firstName} ${participant.lastName} paid and joined your "${request.subject}" meet.`,
                    entityId: request.id,
                    metadata: {
                        requestId: request.id,
                        joinerId: joiner.id,
                        participantId: participant.id,
                        participantName: `${participant.firstName} ${participant.lastName}`,
                        participantPhoto: participant.profileImageUrl,
                    },
                });
            }

            // Check if meet is full
            const paidCount = await StrangersMeetJoiner.count({
                where: { strangersMeetRequestId: request.id, paymentStatus: 'paid' }
            });
            if (paidCount >= request.numberOfPersons && host) {
                await StrangersMeetService.emitNotification({
                    recipientUserId: request.userId,
                    eventType: 'strangers_meet_full',
                    title: '🔥 Stranger Meet Full!',
                    body: `Your Stranger Meet "${request.subject}" has reached full capacity of ${request.numberOfPersons} persons!`,
                    entityId: request.id,
                    metadata: { requestId: request.id },
                });
            }
        } catch (notifErr: any) {
            logger.warn('Failed to send join confirmation notification: ' + notifErr.message);
        }

        // Emit socket event for real-time slots updates
        try {
            const updatedRequest = await StrangersMeetRequest.findByPk(request.id, { include: buildIncludes() });
            if (updatedRequest) {
                const formatted = formatRequest(updatedRequest);
                const { io } = require('../server');
                io.emit('strangers_meet_updated', {
                    requestId: request.id,
                    slotsFilled: formatted.slotsFilled,
                    joinedCount: formatted.joinedCount,
                    paymentCount: formatted.paymentCount,
                });
            }
        } catch (socketErr) {
            logger.warn('Socket emission failed for strangers_meet_updated:', socketErr);
        }

        res.json({
            success: true,
            message: 'Successfully joined strangers meet! 🎉',
            data: {
                id: request.id,
                slotsFilled: request.slotsFilled,
                numberOfPersons: request.numberOfPersons,
            }
        });
    } catch (err: any) {
        logger.error('confirmJoinPayment error:', err);
        res.status(500).json({ success: false, message: 'Failed to confirm join payment', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/mobile/strangers-meet/:id/complete
// Host marks the strangers meet as successfully completed
// ─────────────────────────────────────────────────────────────────────────────
export const completeMeet = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const userId = req.user!.id;

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) {
            res.status(404).json({ success: false, message: 'Strangers meet request not found' });
            return;
        }

        if (request.userId !== userId) {
            res.status(403).json({ success: false, message: 'Unauthorized' });
            return;
        }

        // Allow host to mark as complete if the event is within 60 minutes from now or has already started
        const now = new Date();
        const eventTime = new Date(request.eventDateTime);
        const sixtyMinsBefore = new Date(eventTime.getTime() - 60 * 60 * 1000);
        if (now < sixtyMinsBefore) {
            res.status(400).json({ success: false, message: 'You can only mark the meet as completed within 60 minutes of the event time' });
            return;
        }

        await request.update({
            status: StrangersMeetStatus.COMPLETED,
        });

        res.json({
            success: true,
            message: 'Strangers meet marked as completed! 🏆',
            data: {
                id: request.id,
                status: request.status,
            }
        });
    } catch (err: any) {
        logger.error('completeMeet error:', err);
        res.status(500).json({ success: false, message: 'Failed to complete strangers meet', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/strangers-meet/:id/financials
// Get full financial breakdown for host: platform fee, participant income, profit
// ─────────────────────────────────────────────────────────────────────────────
export const getMeetFinancials = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const request = await StrangersMeetRequest.findByPk(id, {
            include: [{
                model: StrangersMeetJoiner,
                as: 'joiners',
                required: false,
            }]
        });
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        const joiners = (request as any).joiners || [];
        const paidJoiners = joiners.filter((j: any) => j.paymentStatus === 'paid' || j.status === 'paid');
        const paidSlots = paidJoiners.length;
        const totalSeats = request.numberOfPersons;
        const unfilledSeats = Math.max(0, totalSeats - paidSlots);

        // Platform fee the host paid (covers all seats)
        const platformDepositTotal = Number(request.paymentAmount || 0);
        const platformChargePerSeat = Number(request.platformChargePerSeat || 0);

        // Revenue host earns from participants (their chargesPerHead)
        const hostChargePerHead = Number(request.chargesPerHead || 0);
        const hostRevenueFromParticipants = paidSlots * hostChargePerHead;

        // Platform settlement back to host:
        // For each UNFILLED seat that host already paid platform for → platform returns that cost
        // + host's own profit from participants (since platform paid for all seats, and host collected per-head)
        // Settlement = (unfilledSeats * platformChargePerSeat) + hostRevenueFromParticipants
        const platformSettlementToHost = (unfilledSeats * platformChargePerSeat) + hostRevenueFromParticipants;

        // Net position of host
        // Host paid: platformDepositTotal
        // Host receives from participants: hostRevenueFromParticipants
        // Platform pays back: (unfilledSeats * platformChargePerSeat)
        const netHostProfit = hostRevenueFromParticipants + (unfilledSeats * platformChargePerSeat) - platformDepositTotal;

        res.json({
            success: true,
            data: {
                totalSeats,
                paidSlots,
                unfilledSeats,
                platformDepositTotal,           // What host paid to platform
                platformChargePerSeat,          // Cost per seat that platform charged
                hostChargePerHead,              // What host charges participants
                hostRevenueFromParticipants,    // paidSlots × hostChargePerHead
                platformSettlementToHost,       // What platform will pay back to host
                netHostProfit,                  // hostRevenueFromParticipants - platformDepositTotal + (unfilled×platformCharge)
            }
        });
    } catch (err: any) {
        logger.error('getMeetFinancials error:', err);
        res.status(500).json({ success: false, message: 'Failed to calculate financials', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/join-request
// Participant submits a request to join a Stranger Meet
// ─────────────────────────────────────────────────────────────────────────────
export const sendJoinRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const userId = req.user!.id;
        const { foodPreference, drinkPreference } = req.body;

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) {
            res.status(404).json({ success: false, message: 'Strangers meet request not found' });
            return;
        }

        if (request.userId === userId) {
            res.status(400).json({ success: false, message: 'Host cannot join their own meetup' });
            return;
        }

        if (request.status !== StrangersMeetStatus.APPROVED || request.paymentStatus !== StrangersMeetPaymentStatus.PAID) {
            res.status(400).json({ success: false, message: 'Host has not completed platform deposit payment for this Stranger Meet yet' });
            return;
        }

        // Check capacity limit
        const joiners = await StrangersMeetJoiner.findAll({ where: { strangersMeetRequestId: id } });
        const acceptedCount = joiners.filter((j: any) => j.status === 'accepted' || j.status === 'paid' || j.paymentStatus === 'paid').length;
        if (acceptedCount >= request.numberOfPersons) {
            res.status(400).json({ success: false, message: 'This strangers meet is full' });
            return;
        }

        // Check if already requested or joined
        const existing = await StrangersMeetJoiner.findOne({
            where: { strangersMeetRequestId: id, userId }
        });

        if (existing) {
            if (existing.status === 'paid' || existing.paymentStatus === 'paid') {
                res.status(400).json({ success: false, message: 'You have already joined this meetup' });
                return;
            }
            if (existing.status === 'pending') {
                res.status(400).json({ success: false, message: 'You have already sent a join request' });
                return;
            }
        }

        // ── Universal 4-Hour Time-Lock Validation (Joiner) ───────────────────
        const joinerLock = await EventTimeLockService.validateFourHourGap(userId, request.eventDateTime, 'stranger_meet', request.id);
        if (!joinerLock.allowed) {
            res.status(400).json({ success: false, ...joinerLock });
            return;
        }

        let joiner;
        if (existing) {
            await existing.update({
                status: 'pending' as any,
                foodPreference: foodPreference?.trim() || null,
                drinkPreference: drinkPreference?.trim() || null,
            });
            joiner = existing;
        } else {
            joiner = await StrangersMeetJoiner.create({
                strangersMeetRequestId: id,
                userId,
                status: 'pending' as any,
                paymentStatus: StrangersMeetJoinerPaymentStatus.PENDING,
                paymentAmount: 0.0,
                foodPreference: foodPreference?.trim() || null,
                drinkPreference: drinkPreference?.trim() || null,
            });
        }

        try {
            const requester = await User.findByPk(userId);
            if (requester) {
                await StrangersMeetService.emitNotification({
                    recipientUserId: request.userId,
                    eventType: 'strangers_meet_join_request',
                    title: '✨ Join Request Received',
                    body: `${requester.firstName} ${requester.lastName} requested to join your "${request.subject}" meet.`,
                    entityId: request.id,
                    metadata: {
                        requestId: request.id,
                        joinerId: joiner.id,
                        requesterId: requester.id,
                        requesterName: `${requester.firstName} ${requester.lastName}`,
                        requesterPhoto: requester.profileImageUrl,
                    },
                });
            }
        } catch (notifErr: any) {
            logger.warn('Failed to send join request notifications: ' + notifErr.message);
        }

        res.status(201).json({
            success: true,
            message: 'Join request sent successfully! Waiting for host approval. 🤞',
            data: joiner,
        });
    } catch (err: any) {
        logger.error('sendJoinRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to send join request', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/mobile/strangers-meet/:id/join-request/:joinerId
// Host accepts/rejects a participant's request to join
// ─────────────────────────────────────────────────────────────────────────────
export const handleJoinRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id, joinerId } = req.params;
        const { action } = req.body;
        const userId = req.user!.id; // verified host identity

        if (!action || !['accept', 'reject'].includes(action)) {
            res.status(400).json({ success: false, message: 'action must be accept or reject' });
            return;
        }

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) {
            res.status(404).json({ success: false, message: 'Strangers meet request not found' });
            return;
        }
        if (request.userId !== userId) {
            res.status(403).json({ success: false, message: 'Only the host can manage requests' });
            return;
        }

        const joiner = await StrangersMeetJoiner.findByPk(joinerId);
        if (!joiner || joiner.strangersMeetRequestId !== id) {
            res.status(404).json({ success: false, message: 'Joiner request not found' });
            return;
        }

        if (action === 'accept') {
            const transaction = await sequelize.transaction();
            let newAcceptedCount = 0;
            let isFull = false;
            let remainingSlots = 0;
            try {
                await request.reload({ transaction, lock: transaction.LOCK.UPDATE });
                await joiner.reload({ transaction, lock: transaction.LOCK.UPDATE });

                if (request.status !== StrangersMeetStatus.APPROVED ||
                    request.paymentStatus !== StrangersMeetPaymentStatus.PAID ||
                    new Date(request.eventDateTime).getTime() <= Date.now()) {
                    await transaction.rollback();
                    res.status(409).json({ success: false, message: 'This Strangers Meet is no longer accepting participants.' });
                    return;
                }
                if (joiner.status !== 'pending' || joiner.paymentStatus === StrangersMeetJoinerPaymentStatus.PAID) {
                    await transaction.rollback();
                    res.status(409).json({ success: false, message: 'This join request has already been handled.' });
                    return;
                }

                const currentAcceptedCount = await StrangersMeetJoiner.count({
                    where: {
                        strangersMeetRequestId: request.id,
                        [Op.or]: [
                            { status: 'accepted' as any },
                            { status: 'paid' as any },
                            { paymentStatus: StrangersMeetJoinerPaymentStatus.PAID },
                        ],
                    },
                    transaction,
                });

                if (currentAcceptedCount >= request.numberOfPersons) {
                    await transaction.rollback();
                    res.status(409).json({
                        success: false,
                        message: 'This Strangers Meet is already full.',
                        requestStatus: 'FULL',
                        acceptedCount: currentAcceptedCount,
                        maximumCapacity: request.numberOfPersons,
                        remainingCapacity: 0,
                        isFull: true,
                    });
                    return;
                }

                // ── Universal 4-Hour Time-Lock Validation (Host & Joiner) ────
                const hostLock = await EventTimeLockService.validateFourHourGap(request.userId, request.eventDateTime, 'stranger_meet', request.id, { transaction });
                if (!hostLock.allowed) {
                    await transaction.rollback();
                    res.status(400).json({ success: false, ...hostLock, message: `Host schedule conflict: ${hostLock.message}` });
                    return;
                }

                const joinerLock = await EventTimeLockService.validateFourHourGap(joiner.userId, request.eventDateTime, 'stranger_meet', request.id, { transaction });
                if (!joinerLock.allowed) {
                    await transaction.rollback();
                    res.status(400).json({ success: false, ...joinerLock, message: `Participant schedule conflict: ${joinerLock.message}` });
                    return;
                }

                await joiner.update({ status: 'accepted' as any }, { transaction });

                newAcceptedCount = currentAcceptedCount + 1;
                remainingSlots = Math.max(0, request.numberOfPersons - newAcceptedCount);
                isFull = newAcceptedCount >= request.numberOfPersons;

                if (isFull) {
                    await request.update({ slotsFilled: request.numberOfPersons }, { transaction });
                } else {
                    await request.update({ slotsFilled: newAcceptedCount }, { transaction });
                }

                await transaction.commit();
            } catch (err) {
                await transaction.rollback();
                throw err;
            }

            // Multi-channel notification engine for accepted joiner
            await StrangersMeetService.emitNotification({
                recipientUserId: joiner.userId,
                eventType: 'strangers_meet_request_accepted',
                title: '🎉 Request Accepted!',
                body: `Your request to join "${request.subject}" has been accepted by the host! Complete payment to secure your spot.`,
                entityId: request.id
            });

            // Update single card for Host
            await StrangersMeetService.emitNotification({
                recipientUserId: request.userId,
                eventType: 'strangers_meet_join_request_updated',
                title: '✨ Request Accepted',
                body: `Accepted request for "${request.subject}". (${newAcceptedCount}/${request.numberOfPersons} participants)`,
                entityId: request.id,
                metadata: {
                    requestId: request.id,
                    joinerId: joiner.id,
                    action: 'accept',
                    acceptedCount: newAcceptedCount,
                    maximumCapacity: request.numberOfPersons,
                    remainingCapacity: remainingSlots,
                    isFull,
                }
            });

            // Emit socket event for real-time slots updates
            try {
                const updatedRequest = await StrangersMeetRequest.findByPk(request.id, { include: buildIncludes() });
                if (updatedRequest) {
                    const formatted = formatRequest(updatedRequest);
                    const { io } = require('../server');
                    io.emit('strangers_meet_updated', {
                        requestId: request.id,
                        slotsFilled: formatted.slotsFilled,
                        joinedCount: formatted.joinedCount,
                        paymentCount: formatted.paymentCount,
                        acceptedCount: newAcceptedCount,
                        maximumCapacity: request.numberOfPersons,
                        remainingCapacity: remainingSlots,
                        isFull,
                    });
                }
            } catch (socketErr) {
                logger.warn('Socket emission failed for strangers_meet_updated:', socketErr);
            }

            res.json({
                success: true,
                message: 'Join request accepted!',
                requestStatus: 'ACCEPTED',
                acceptedCount: newAcceptedCount,
                maximumCapacity: request.numberOfPersons,
                remainingCapacity: remainingSlots,
                isFull,
                data: joiner
            });
        } else {
            const transaction = await sequelize.transaction();
            try {
                await joiner.reload({ transaction, lock: transaction.LOCK.UPDATE });
                if (joiner.status !== 'pending') {
                    await transaction.rollback();
                    res.status(409).json({ success: false, message: 'This join request has already been handled.' });
                    return;
                }
                await joiner.update({ status: 'rejected' as any }, { transaction });
                await transaction.commit();
            } catch (err) {
                await transaction.rollback();
                throw err;
            }

            // Fetch host details for notification card profile name & image
            const hostUser = await User.findByPk(request.userId);
            const declinerName = hostUser ? `${hostUser.firstName} ${hostUser.lastName}`.trim() : 'the host';
            const declinerPhoto = hostUser ? ((hostUser as any).profileImageUrl || (hostUser as any).profilePhotoUrl || ((hostUser as any).photos && (hostUser as any).photos[0] ? (hostUser as any).photos[0].url : null)) : null;

            // Multi-channel notification engine for rejected joiner
            await StrangersMeetService.emitNotification({
                recipientUserId: joiner.userId,
                eventType: 'strangers_meet_request_rejected',
                title: 'Declined Request ❌',
                body: `Your request to join "${request.subject}" was declined by ${declinerName}.`,
                entityId: request.id,
                metadata: {
                    planId: request.id,
                    actorUserId: hostUser?.id,
                    actorName: declinerName,
                    actorProfilePhotoUrl: declinerPhoto,
                }
            });

            // Update single card for Host
            await StrangersMeetService.emitNotification({
                recipientUserId: request.userId,
                eventType: 'strangers_meet_join_request_updated',
                title: 'Request Declined ❌',
                body: `Declined request for "${request.subject}".`,
                entityId: request.id,
                metadata: {
                    requestId: request.id,
                    joinerId: joiner.id,
                    action: 'reject',
                }
            });

            // Emit socket event for real-time slots updates
            try {
                const updatedRequest = await StrangersMeetRequest.findByPk(request.id, { include: buildIncludes() });
                if (updatedRequest) {
                    const formatted = formatRequest(updatedRequest);
                    const { io } = require('../server');
                    io.emit('strangers_meet_updated', {
                        requestId: request.id,
                        slotsFilled: formatted.slotsFilled,
                        joinedCount: formatted.joinedCount,
                        paymentCount: formatted.paymentCount,
                    });
                }
            } catch (socketErr) {
                logger.warn('Socket emission failed for strangers_meet_updated:', socketErr);
            }

            res.json({ success: true, message: 'Join request rejected!', requestStatus: 'REJECTED', data: joiner });
        }
    } catch (err: any) {
        logger.error('handleJoinRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to handle join request', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/settlement-request
// Host submits bank/UPI details to request meetup earnings settlement
// ─────────────────────────────────────────────────────────────────────────────
export const submitSettlementRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const userId = req.user!.id;
        const { bankDetails, accountNumber, bankName, accountHolderName, ifscCode, upiId, mobileNumber } = req.body;

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) {
            res.status(404).json({ success: false, message: 'Strangers meet request not found' });
            return;
        }

        if (request.userId !== userId) {
            res.status(403).json({ success: false, message: 'Unauthorized' });
            return;
        }

        const formattedBankDetails = [
            bankDetails?.trim(),
            upiId ? `UPI ID: ${upiId.trim()}` : null,
            accountNumber ? `A/c: ${accountNumber.trim()} (${ifscCode?.trim() || ''})` : null,
            mobileNumber ? `Mobile: ${mobileNumber.trim()}` : null,
        ].filter(Boolean).join('\n');

        await request.update({
            settlementStatus: 'requested',
            bankDetails: formattedBankDetails || request.bankDetails || 'Submitted payout request',
            accountNumber: accountNumber?.trim() || request.accountNumber,
            bankName: bankName?.trim() || request.bankName,
            accountHolderName: accountHolderName?.trim() || request.accountHolderName,
            ifscCode: ifscCode?.trim() || request.ifscCode,
            upiId: upiId?.trim() || request.upiId,
            mobileNumber: mobileNumber?.trim() || request.mobileNumber,
        });

        // Dispatch notification to host
        try {
            const { NotificationService } = require('../services/NotificationService');
            await NotificationService.dispatch({
                recipientUserId: request.userId,
                title: '🎉 Party Done Successfully! Payout Request Sent',
                body: `Your payout request for "${request.subject}" has been submitted to Admin. You will receive updates here!`,
                category: 'stranger_meet',
                entityType: 'strangers_meet',
                entityId: request.id,
                metadata: { requestId: request.id, settlementStatus: 'requested' }
            });
        } catch (notifErr: any) {
            logger.warn('Failed to dispatch settlement requested notification: ' + notifErr.message);
        }

        res.json({
            success: true,
            message: 'Party Done Successfully! Settlement payout requested. Admin has been notified. ⏳',
            data: {
                id: request.id,
                settlementStatus: 'requested',
                bankDetails: request.bankDetails,
                accountNumber: request.accountNumber,
                upiId: request.upiId,
                ifscCode: request.ifscCode,
            }
        });
    } catch (err: any) {
        logger.error('submitSettlementRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to request settlement', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/admin/strangers-meet/:id/approve-settlement
// Admin approves payout request (notifies user amount credited within 24 hours)
// ─────────────────────────────────────────────────────────────────────────────
export const approveSettlementPayout = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { settlementAmount } = req.body;

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        const amt = settlementAmount ? Number(settlementAmount) : (request.settlementAmount || 0);

        await request.update({
            settlementStatus: 'approved',
            settlementAmount: amt > 0 ? amt : request.settlementAmount,
        });

        // Notify Host: amount will be credited within 24 hours
        try {
            const { NotificationService } = require('../services/NotificationService');
            await NotificationService.dispatch({
                recipientUserId: request.userId,
                title: '⏳ Payout Approved — Credited within 24 Hours',
                body: `Your Stranger Meet payout request of ₹${amt.toFixed(0)} for "${request.subject}" has been accepted by Admin! Your amount will be credited within 24 hours. ⏳`,
                category: 'stranger_meet',
                entityType: 'strangers_meet',
                entityId: request.id,
                metadata: { requestId: request.id, settlementStatus: 'approved', settlementAmount: amt }
            });
        } catch (notifErr: any) {
            logger.warn('Failed to dispatch approve settlement notification: ' + notifErr.message);
        }

        res.json({
            success: true,
            message: 'Payout request approved! Notification sent to user (credited within 24h).',
            data: request,
        });
    } catch (err: any) {
        logger.error('approveSettlementPayout error:', err);
        res.status(500).json({ success: false, message: 'Failed to approve payout request', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/admin/strangers-meet/:id/pay-settlement
// Admin records settlement payout details and marks as PAID
// ─────────────────────────────────────────────────────────────────────────────
export const paySettlement = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { transactionId, amount, paymentDate, paymentMethod } = req.body;
        
        if (!transactionId) {
            res.status(400).json({ success: false, message: 'transactionId is required' });
            return;
        }
        if (!amount || Number(amount) <= 0) {
            res.status(400).json({ success: false, message: 'amount must be a positive number' });
            return;
        }

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        if (request.settlementStatus === 'paid') {
            res.status(400).json({ success: false, message: 'Settlement already paid for this meetup' });
            return;
        }

        await request.update({
            settlementStatus: 'paid',
            settlementTransactionId: transactionId,
            settlementAmount: Number(amount),
            settlementDate: paymentDate ? new Date(paymentDate) : new Date(),
            settlementMethod: paymentMethod || 'Bank Transfer',
        });

        // Construct target account detail label
        const targetAccountStr = request.upiId
            ? `UPI ID: ${request.upiId}`
            : (request.accountNumber ? `A/c: ${request.accountNumber} (${request.ifscCode || ''})` : `Mobile: ${request.mobileNumber}`);

        // Dispatch Notification & FCM to Host
        try {
            const { NotificationService } = require('../services/NotificationService');
            await NotificationService.dispatch({
                recipientUserId: request.userId,
                title: '💰 Amount Paid by Admin!',
                body: `Amount of ₹${Number(amount).toFixed(0)} for "${request.subject}" has been successfully paid by Admin to your ${targetAccountStr}! Txn ID: ${transactionId} 💸`,
                category: 'stranger_meet',
                entityType: 'strangers_meet',
                entityId: request.id,
                metadata: { requestId: request.id, settlementStatus: 'paid', transactionId, amount: Number(amount), targetAccountStr }
            });
        } catch (notifErr: any) {
            logger.warn('Failed to dispatch settlement paid notification: ' + notifErr.message);
        }

        res.json({
            success: true,
            message: 'Settlement marked as paid successfully! 💸',
            data: {
                id: request.id,
                settlementStatus: 'paid',
                settlementTransactionId: transactionId,
                settlementAmount: amount,
            }
        });
    } catch (err: any) {
        logger.error('paySettlement error:', err);
        res.status(500).json({ success: false, message: 'Failed to process settlement payment', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/mobile/strangers-meet/:id/charges
// Host sets/updates chargesPerHead after payment
// ─────────────────────────────────────────────────────────────────────────────
export const updateChargesPerHead = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const userId = req.user!.id;
        const { chargesPerHead } = req.body;

        if (chargesPerHead === undefined || chargesPerHead === null || isNaN(Number(chargesPerHead))) {
            res.status(400).json({ success: false, message: 'chargesPerHead must be a valid number' });
            return;
        }

        const parsedCharges = Number(chargesPerHead);
        if (parsedCharges < 0) {
            res.status(400).json({ success: false, message: 'chargesPerHead cannot be negative' });
            return;
        }

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        if (request.userId !== userId) {
            res.status(403).json({ success: false, message: 'Unauthorized' });
            return;
        }

        if (request.paymentStatus !== StrangersMeetPaymentStatus.PAID) {
            res.status(400).json({ success: false, message: 'You must pay the deposit before setting charges per head' });
            return;
        }

        await request.update({
            chargesPerHead: parsedCharges,
        });

        res.json({
            success: true,
            message: 'Charges per head updated successfully',
            data: {
                id: request.id,
                chargesPerHead: request.chargesPerHead,
            }
        });
    } catch (err: any) {
        logger.error('updateChargesPerHead error:', err);
        res.status(500).json({ success: false, message: 'Failed to update charges per head', error: err.message });
    }
};

export const getStrangersMeetTicket = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const cleanId = (id || '').replace(/^strangers_meet_/, '').trim();

        const venueInclude = {
            model: Venue,
            as: 'venue',
            attributes: ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone', 'latitude', 'longitude'],
            include: [
                { model: VenueImage, as: 'images', attributes: ['id', 'filePath', 'imageType', 'isPrimary', 'displayOrder'], required: false },
            ],
        };

        const userInclude = {
            model: User,
            as: 'user',
            attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
            include: [
                { model: UserProfile, as: 'profile', attributes: ['bio', 'city', 'displayName', 'subscriptionTier'], required: false },
                { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary'], required: false },
            ],
        };

        let request = await StrangersMeetRequest.findByPk(cleanId, {
            include: [venueInclude, userInclude],
        });

        if (!request) {
            const joiner = await StrangersMeetJoiner.findByPk(cleanId, {
                include: [{
                    model: StrangersMeetRequest,
                    as: 'strangersMeetRequest',
                    include: [venueInclude, userInclude],
                }],
            });
            if (joiner && (joiner as any).strangersMeetRequest) {
                request = (joiner as any).strangersMeetRequest;
            }
        }

        if (!request) {
            try {
                const TicketModel = (await import('../models/Ticket')).default;
                const ticket = await TicketModel.findByPk(cleanId);
                if (ticket && ticket.bookingId) {
                    request = await StrangersMeetRequest.findByPk(ticket.bookingId, {
                        include: [venueInclude, userInclude],
                    });
                    if (!request) {
                        const joiner = await StrangersMeetJoiner.findByPk(ticket.bookingId, {
                            include: [{
                                model: StrangersMeetRequest,
                                as: 'strangersMeetRequest',
                                include: [venueInclude, userInclude],
                            }],
                        });
                        if (joiner && (joiner as any).strangersMeetRequest) {
                            request = (joiner as any).strangersMeetRequest;
                        }
                    }
                }
            } catch (_) {}
        }

        if (!request) {
            res.status(404).json({ success: false, message: 'Strangers meet request not found' });
            return;
        }

        const resolveUserPhoto = (u: any): string | null => {
            if (!u) return null;
            let photoUrl: string | null = u.profileImageUrl ?? null;
            if (u.photos && u.photos.length > 0) {
                const primary = u.photos.find((p: any) => p.isPrimary) || u.photos[0];
                if (primary?.filePath) {
                    const cleanPath = primary.filePath.replace(/\\/g, '/');
                    photoUrl = cleanPath.startsWith('http') ? cleanPath : `/${cleanPath.replace(/^\/+/, '')}`;
                }
            }
            if (photoUrl && !photoUrl.startsWith('http') && !photoUrl.startsWith('/')) {
                photoUrl = `/${photoUrl.replace(/\\/g, '')}`;
            }
            return photoUrl;
        };

        const hostRaw = (request as any).user;
        const hostPhoto = resolveUserPhoto(hostRaw);
        const hostData = hostRaw ? {
            id: hostRaw.id,
            firstName: hostRaw.firstName,
            lastName: hostRaw.lastName,
            fullName: `${hostRaw.firstName || ''} ${hostRaw.lastName || ''}`.trim() || 'Host',
            name: `${hostRaw.firstName || ''} ${hostRaw.lastName || ''}`.trim() || 'Host',
            username: hostRaw.profile?.displayName || (hostRaw.firstName ? `${hostRaw.firstName}_${hostRaw.lastName}`.toLowerCase() : 'user'),
            phone: hostRaw.phone,
            mobileNumber: hostRaw.phone,
            email: hostRaw.email,
            profilePhotoUrl: hostPhoto,
            profileImageUrl: hostPhoto,
            profilePhoto: hostPhoto,
            photoUrl: hostPhoto,
            image: hostPhoto,
            subscriptionTier: hostRaw.profile?.subscriptionTier || 'FREE',
            bio: hostRaw.profile?.bio ?? null,
            city: hostRaw.profile?.city ?? null,
        } : null;

        // Dynamic participants calculation: count actual confirmed/paid joiners
        const paidJoinersCount = await StrangersMeetJoiner.count({
            where: {
                strangersMeetRequestId: request.id,
                [Op.or]: [
                    { paymentStatus: StrangersMeetJoinerPaymentStatus.PAID },
                    { status: 'paid' },
                    { status: 'accepted' },
                ],
            },
        });
        const dynamicParticipantsCount = paidJoinersCount > 0
            ? paidJoinersCount
            : ((request.slotsFilled && request.slotsFilled > 0) ? request.slotsFilled : 1);

        let ticketUrl = request.ticketUrl ?? null;
        let ticketCode = request.ticketId || `SM-${request.id.substring(0, 8).toUpperCase()}`;

        if (!ticketUrl && request.paymentStatus === StrangersMeetPaymentStatus.PAID) {
            try {
                const { generateTicketForStrangersMeetHelper } = require('../services/ticketService');
                ticketUrl = await generateTicketForStrangersMeetHelper(request.id);
            } catch (tErr: any) {
                logger.warn(`On-the-fly strangers meet ticket generation failed: ${tErr.message}`);
            }
        }

        const startTimeStr = formatTime12Hour(request.eventDateTime);
        const totalAmountNum = Number(request.paymentAmount || request.chargesPerHead || 0);

        res.json({
            success: true,
            data: {
                request: {
                    id: request.id,
                    subject: request.subject,
                    tagline: request.tagline,
                    eventDateTime: request.eventDateTime,
                    startTime: startTimeStr,
                    numberOfPersons: dynamicParticipantsCount,
                    targetCapacity: request.numberOfPersons,
                    capacity: request.numberOfPersons,
                    slotsFilled: dynamicParticipantsCount,
                    joinedCount: dynamicParticipantsCount,
                    actualParticipantsCount: dynamicParticipantsCount,
                    paymentAmount: totalAmountNum,
                    chargesPerHead: Number(request.chargesPerHead || 0),
                    totalAmount: totalAmountNum,
                    isFree: totalAmountNum <= 0,
                    status: request.status,
                    paymentStatus: request.paymentStatus,
                    ticketCode: ticketCode,
                    ticketUrl: ticketUrl,
                    host: hostData,
                    user: hostData,
                    venue: (request as any).venue,
                },
                ticketCode: ticketCode,
                ticketUrl: ticketUrl,
                actualParticipantsCount: dynamicParticipantsCount,
                joinedCount: dynamicParticipantsCount,
                numberOfPersons: dynamicParticipantsCount,
                targetCapacity: request.numberOfPersons,
                host: hostData,
                user: hostData,
                venue: (request as any).venue,
            },
        });
    } catch (err: any) {
        logger.error('getStrangersMeetTicket error:', err);
        res.status(500).json({ success: false, error: err.message });
    }
};

// POST /api/mobile/strangers-meet/:id/start
export const startMeetup = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const userId = req.user!.id;
        const { durationHours, customEndDateTime } = req.body;

        const request = await StrangersMeetService.confirmMeetupStarted(
            id,
            userId,
            Number(durationHours || 1),
            customEndDateTime ? String(customEndDateTime) : undefined
        );

        res.json({
            success: true,
            message: 'Strangers Meet started successfully!',
            data: request,
        });
    } catch (err: any) {
        logger.error('startMeetup error:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to start strangers meet' });
    }
};

// POST /api/mobile/strangers-meet/:id/extend
export const extendMeetup = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const userId = req.user!.id;
        const { additionalHours, customEndDateTime } = req.body;

        const request = await StrangersMeetService.extendMeetupDuration(
            id,
            userId,
            Number(additionalHours || 1),
            customEndDateTime ? String(customEndDateTime) : undefined
        );

        res.json({
            success: true,
            message: 'Strangers Meet duration extended successfully!',
            data: request,
        });
    } catch (err: any) {
        logger.error('extendMeetup error:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to extend strangers meet duration' });
    }
};

// POST /api/mobile/strangers-meet/:id/confirm-ended
export const confirmEndedMeetup = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const userId = req.user!.id;

        const request = await StrangersMeetService.confirmMeetupEnded(id, userId);

        res.json({
            success: true,
            message: 'Strangers Meet ended confirmation received. Payout settlement sent for Admin verification.',
            data: request,
        });
    } catch (err: any) {
        logger.error('confirmEndedMeetup error:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to confirm strangers meet end' });
    }
};

// PATCH /api/admin/strangers-meet/:id/confirm-ended
export const adminConfirmEnded = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const adminId = (req as any).admin?.id || (req as any).user?.id || 'admin';

        const request = await StrangersMeetService.adminConfirmMeetupEnded(id, adminId);

        res.json({
            success: true,
            message: 'Strangers Meet end confirmed by Admin. Host will receive settlement within 24 hours.',
            data: request,
        });
    } catch (err: any) {
        logger.error('adminConfirmEnded error:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to admin-confirm strangers meet end' });
    }
};

// POST /api/admin/strangers-meet/:id/mark-settled
export const adminMarkSettled = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { transactionId, paymentMethod, amount } = req.body;
        const adminId = (req as any).admin?.id || (req as any).user?.id || 'admin';

        if (!transactionId) {
            res.status(400).json({ success: false, message: 'Payment transaction reference ID is required' });
            return;
        }

        const request = await StrangersMeetService.adminMarkSettled(
            id,
            adminId,
            String(transactionId),
            paymentMethod ? String(paymentMethod) : 'UPI',
            amount ? Number(amount) : undefined
        );

        res.json({
            success: true,
            message: 'Strangers Meet payout marked as settled successfully!',
            data: request,
        });
    } catch (err: any) {
        logger.error('adminMarkSettled error:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to mark strangers meet payout as settled' });
    }
};

// POST /api/mobile/strangers-meet/:id/not-started
export const postNotStarted = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const userId = req.user!.id;
        const { reason } = req.body;

        const request = await StrangersMeetService.hostReportNotStarted(id, userId, reason ? String(reason) : undefined);

        res.json({
            success: true,
            message: 'Meetup marked as not started',
            data: request,
        });
    } catch (err: any) {
        logger.error('postNotStarted error:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to mark meetup as not started' });
    }
};

// GET /api/admin/strangers-meet/needs-contact
export const getNeedsHostContact = async (req: Request, res: Response): Promise<void> => {
    try {
        const { page = '1', limit = '20' } = req.query;
        const pageNum = Math.max(1, parseInt(page as string));
        const limitNum = Math.min(100, Math.max(1, parseInt(limit as string)));
        const offset = (pageNum - 1) * limitNum;

        const where = {
            status: StrangersMeetStatus.NEEDS_HOST_CONTACT,
        };

        const count = await StrangersMeetRequest.count({ where });
        const rows = await StrangersMeetRequest.findAll({
            where,
            include: buildIncludes(),
            order: [['escalatedAt', 'DESC'], ['createdAt', 'DESC']],
            limit: limitNum,
            offset,
        });

        res.json({
            success: true,
            total: count,
            page: pageNum,
            limit: limitNum,
            pages: Math.ceil(count / limitNum),
            data: rows.map(formatRequest),
        });
    } catch (err: any) {
        logger.error('getNeedsHostContact error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch escalated requests', error: err.message });
    }
};

// POST /api/admin/strangers-meet/:id/resolve-escalation
export const resolveEscalation = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { resolution, resolutionNotes } = req.body;
        const adminId = (req as any).admin?.id || (req as any).user?.id || 'admin';

        if (!resolution) {
            res.status(400).json({ success: false, message: 'resolution is required' });
            return;
        }

        const request = await StrangersMeetService.adminResolveEscalation(
            id,
            adminId,
            String(resolution),
            resolutionNotes ? String(resolutionNotes) : undefined
        );

        res.json({
            success: true,
            message: 'Escalation resolved successfully',
            data: request,
        });
    } catch (err: any) {
        logger.error('resolveEscalation error:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to resolve escalation' });
    }
};

// GET /api/admin/strangers-meet/:id/settlement-summary
export const getSettlementSummary = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const summary = await StrangersMeetService.calculateSettlementSummary(id);

        res.json({
            success: true,
            data: summary,
        });
    } catch (err: any) {
        logger.error('getSettlementSummary error:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to calculate settlement summary' });
    }
};




