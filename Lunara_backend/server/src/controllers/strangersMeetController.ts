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
import Razorpay from 'razorpay';
import crypto from 'crypto';
import { generateTicketForStrangersMeetHelper } from '../services/ticketService';
import { StrangersMeetService } from '../services/StrangersMeetService';

const razorpay = new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
    key_secret: process.env.RAZORPAY_KEY_SECRET || 'secret123',
});

// ─── Shared attributes ────────────────────────────────────────────────────────
const USER_ATTRS = ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'];
const VENUE_ATTRS = ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone', 'openingTime', 'closingTime', 'daysOpen', 'closedDates'];
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
                    where: { imageType: 'cover', isPrimary: true },
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

    let userPhotoUrl = user?.profileImageUrl ?? null;
    if (user?.photos?.length > 0) {
        const primary = user.photos.find((p: any) => p.isPrimary) || user.photos[0];
        if (primary?.filePath) userPhotoUrl = '/' + primary.filePath.replace(/\\/g, '/');
    }

    let venueImageUrl = venue?.imageUrl ?? null;
    if (!venueImageUrl && venue?.images?.length > 0) {
        const primary = venue.images?.find((img: any) => img.isPrimary) || venue.images[0];
        if (primary?.filePath) {
            venueImageUrl = '/' + primary.filePath.replace(/\\/g, '/');
        }
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
        subject: r.subject,
        tagline: r.tagline,
        eventDateTime: r.eventDateTime,
        numberOfPersons: r.numberOfPersons,
        chargesPerHead: Number(r.chargesPerHead || 0),
        slotsFilled: joinedCount,  // Use live-computed count, not stale DB column
        status: r.status,
        paymentAmount: r.paymentAmount ?? null,
        paymentStatus: r.paymentStatus,
        mobileNumber: r.mobileNumber,
        alternateMobileNumber: r.alternateMobileNumber ?? null,
        adminNotes: r.adminNotes ?? null,
        ticketId: r.ticketId ?? null,
        ticketUrl: r.ticketUrl ?? null,
        settlementStatus: r.settlementStatus || 'none',
        bankDetails: r.bankDetails ?? null,
        // v2 structured bank fields
        bankName: r.bankName ?? null,
        accountNumber: r.accountNumber ?? null,
        accountHolderName: r.accountHolderName ?? null,
        ifscCode: r.ifscCode ?? null,
        upiId: r.upiId ?? null,
        upiNumber: r.upiNumber ?? null,
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
                createdAt: j.createdAt,
                user: ju ? {
                    id: ju.id,
                    firstName: ju.firstName,
                    lastName: ju.lastName,
                    photoUrl: juPhotoUrl,
                    phone: ju.phone,
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
            userId, venueId, subject, tagline, eventDateTime, numberOfPersons,
            mobileNumber, alternateMobileNumber,
            bankName, accountNumber, accountHolderName, ifscCode, upiId, upiNumber,
            foodPreference, drinkPreference,
        } = req.body;

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

        // Send request submitted push notification to creator
        try {
            const creator = await User.findByPk(userId);
            if (creator?.fcmToken) {
                const { sendPushNotification } = require('../services/fcmService');
                await sendPushNotification(creator.fcmToken, {
                    title: '📝 Request Submitted',
                    body: 'Your Stranger Meet request has been submitted for admin approval.',
                    data: {
                        type: 'strangers_meet_request_submitted',
                        requestId: request.id,
                    }
                });
            }
        } catch (notifErr: any) {
            logger.warn('Failed to send request submitted notification: ' + notifErr.message);
        }

        res.status(201).json({
            success: true,
            message: 'Request submitted successfully! Admin will review and get back to you. 🎉',
            data: {
                id: request.id,
                subject: request.subject,
                numberOfPersons: request.numberOfPersons,
                status: request.status,
            }
        });
    } catch (err: any) {
        logger.error('createRequest error:', err);
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
        const { userId } = req.body;

        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
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
        if (request.status !== StrangersMeetStatus.APPROVED) {
            res.status(400).json({ success: false, message: 'Request has not been approved yet' });
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

        // Generate Razorpay Order
        const options = {
            amount: Math.round(paymentAmount * 100), // in paise
            currency: 'INR',
            receipt: `smreq_${Date.now()}`
        };

        let order: any = { id: `order_mock_${Date.now()}`, amount: options.amount, currency: options.currency };
        if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id') {
            try {
                order = await razorpay.orders.create(options);
            } catch (err: any) {
                logger.warn('Razorpay strangers meet order creation failed, using mock: ' + err.message);
            }
        }

        await request.update({
            razorpayOrderId: order.id
        });

        res.json({
            success: true,
            razorpayOrderId: order.id,
            amount: order.amount,
            currency: order.currency,
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
        const { userId, razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        if (!userId) { res.status(400).json({ success: false, message: 'userId is required' }); return; }
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
        if (status && Object.values(StrangersMeetStatus).includes(status as StrangersMeetStatus)) {
            where.status = status;
        }

        const pageNum = Math.max(1, parseInt(page as string));
        const limitNum = Math.min(100, Math.max(1, parseInt(limit as string)));
        const offset = (pageNum - 1) * limitNum;

        const { count, rows } = await StrangersMeetRequest.findAndCountAll({
            where,
            include: buildIncludes(),
            order: [['createdAt', 'DESC']],
            limit: limitNum,
            offset,
        });

        // Counts by status for badge display
        const pendingCount = await StrangersMeetRequest.count({ where: { status: StrangersMeetStatus.PENDING } });
        const approvedCount = await StrangersMeetRequest.count({ where: { status: StrangersMeetStatus.APPROVED } });
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
// Get all approved and paid strangers meet requests for public feed
// ─────────────────────────────────────────────────────────────────────────────
export const getFeedRequests = async (req: Request, res: Response): Promise<void> => {
    try {
        const { page = '1', limit = '20' } = req.query;

        const pageNum = Math.max(1, parseInt(page as string));
        const limitNum = Math.min(100, Math.max(1, parseInt(limit as string)));
        const offset = (pageNum - 1) * limitNum;

        const { count, rows } = await StrangersMeetRequest.findAndCountAll({
            where: {
                status: StrangersMeetStatus.APPROVED,
                paymentStatus: StrangersMeetPaymentStatus.PAID,
                // Hide events that start within 45 minutes from now (or have already started)
                eventDateTime: { [Op.gte]: new Date(Date.now() + 45 * 60 * 1000) },
            },
            include: buildIncludes(),
            order: [['createdAt', 'DESC']],
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
        const { userId } = req.body;

        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

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

        if (request.slotsFilled >= request.numberOfPersons) {
            res.status(400).json({ success: false, message: 'This strangers meet is full' });
            return;
        }

        // Check if already a paid joiner
        const existingJoiner = await StrangersMeetJoiner.findOne({
            where: { strangersMeetRequestId: id, userId }
        });

        if (!existingJoiner || existingJoiner.status !== 'accepted') {
            res.status(400).json({ success: false, message: 'You must have an accepted join request to make a payment' });
            return;
        }

        if (existingJoiner.paymentStatus === StrangersMeetJoinerPaymentStatus.PAID) {
            res.status(400).json({ success: false, message: 'You have already joined this strangers meet' });
            return;
        }

        const chargesPerHead = Number(request.chargesPerHead || 0);
        const orderAmount = chargesPerHead > 0 ? Math.round(chargesPerHead * 100) : 0;

        let orderId = `order_mock_join_${Date.now()}`;
        if (orderAmount > 0 && process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id') {
            try {
                const options = {
                    amount: orderAmount,
                    currency: 'INR',
                    receipt: `smjoin_${Date.now()}`
                };
                const order = await razorpay.orders.create(options);
                orderId = order.id;
            } catch (err: any) {
                logger.warn('Razorpay order failed, using mock: ' + err.message);
            }
        }

        let joiner = await StrangersMeetJoiner.findOne({
            where: { strangersMeetRequestId: id, userId }
        });

        if (joiner) {
            await joiner.update({
                paymentStatus: StrangersMeetJoinerPaymentStatus.PENDING,
                paymentAmount: chargesPerHead,
                razorpayOrderId: orderId,
            });
        } else {
            joiner = await StrangersMeetJoiner.create({
                strangersMeetRequestId: id,
                userId,
                paymentStatus: StrangersMeetJoinerPaymentStatus.PENDING,
                paymentAmount: chargesPerHead,
                razorpayOrderId: orderId,
            });
        }

        res.json({
            success: true,
            razorpayOrderId: orderId,
            amount: orderAmount,
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
        const { userId, razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

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
            res.status(400).json({ success: false, message: 'Already joined' });
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

        await joiner.update({
            status: 'paid' as any,
            paymentStatus: StrangersMeetJoinerPaymentStatus.PAID,
            razorpayPaymentId: razorpay_payment_id || 'free_or_mock',
            razorpaySignature: razorpay_signature || 'free_or_mock',
        });

        await request.increment('slotsFilled', { by: 1 });
        await request.reload();

        // Send notifications via push and socket
        try {
            const host = await User.findByPk(request.userId);
            const participant = await User.findByPk(joiner.userId);
            const venue = await Venue.findByPk(request.venueId);
            const venueName = venue?.name || 'Venue';

            if (participant) {
                if (participant.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(participant.fcmToken, {
                        title: '💳 Payment Successful',
                        body: `Your payment of ₹${request.chargesPerHead} for "${request.subject}" was successful!`,
                        data: {
                            type: 'strangers_meet_payment_success',
                            requestId: request.id,
                        }
                    });
                }

                // Emit socket event to participant
                const { io } = require('../server');
                io.to(`user_${joiner.userId}`).emit('notification_created', {
                    id: `sm_payment_success_${joiner.id}`,
                    title: 'Booking Confirmed',
                    body: `Your payment for "${request.subject}" at ${venueName} was successful. Spot confirmed!`,
                    createdAt: new Date().toISOString(),
                    read: false,
                    data: {
                        type: 'strangers_meet_payment_success',
                        requestId: request.id,
                    }
                });
            }

            if (host && participant) {
                if (host.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(host.fcmToken, {
                        title: '👥 New Participant Joined',
                        body: `${participant.firstName} paid and joined your "${request.subject}" meet.`,
                        data: {
                            type: 'strangers_meet_participant_joined',
                            requestId: request.id,
                        }
                    });
                }

                // Emit socket event to host
                const { io } = require('../server');
                io.to(`user_${request.userId}`).emit('notification_created', {
                    id: `sm_incoming_${joiner.id}`,
                    title: 'Participant Joined',
                    body: `${participant.firstName} ${participant.lastName} paid and joined your "${request.subject}" meet.`,
                    createdAt: new Date().toISOString(),
                    read: false,
                    sender: {
                        id: participant.id,
                        firstName: participant.firstName,
                        lastName: participant.lastName,
                        profileImageUrl: participant.profileImageUrl,
                    },
                    data: {
                        type: 'strangers_meet_participant_joined',
                        requestId: request.id,
                    }
                });
            }

            // Check if meet is full
            const paidCount = await StrangersMeetJoiner.count({
                where: { strangersMeetRequestId: request.id, paymentStatus: 'paid' }
            });
            if (paidCount >= request.numberOfPersons && host) {
                if (host.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(host.fcmToken, {
                        title: '🔥 Stranger Meet Full!',
                        body: `Your Stranger Meet "${request.subject}" has reached full capacity of ${request.numberOfPersons} persons!`,
                        data: {
                            type: 'strangers_meet_full',
                            requestId: request.id,
                        }
                    });
                }

                // Emit socket event for meet full
                const { io } = require('../server');
                io.to(`user_${request.userId}`).emit('notification_created', {
                    id: `sm_full_${request.id}`,
                    title: 'Stranger Meet Full!',
                    body: `Your Stranger Meet "${request.subject}" has reached full capacity of ${request.numberOfPersons} persons!`,
                    createdAt: new Date().toISOString(),
                    read: false,
                    data: {
                        type: 'strangers_meet_full',
                        requestId: request.id,
                    }
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
        const { userId } = req.body;

        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

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
        const { userId, foodPreference, drinkPreference } = req.body;

        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) {
            res.status(404).json({ success: false, message: 'Strangers meet request not found' });
            return;
        }

        if (request.userId === userId) {
            res.status(400).json({ success: false, message: 'Host cannot join their own meetup' });
            return;
        }

        // Check capacity limit
        const joiners = await StrangersMeetJoiner.findAll({ where: { strangersMeetRequestId: id } });
        const paidCount = joiners.filter((j: any) => j.status === 'paid' || j.paymentStatus === 'paid').length;
        if (paidCount >= request.numberOfPersons) {
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

        // Notify host via push and socket
        try {
            const host = await User.findByPk(request.userId);
            const requester = await User.findByPk(userId);
            if (requester) {
                if (host?.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(host.fcmToken, {
                        title: '✨ Join Request Received',
                        body: `${requester.firstName} wants to join your "${request.subject}" meet.`,
                        data: {
                            type: 'strangers_meet_join_request',
                            requestId: request.id,
                            joinerId: joiner.id,
                        }
                    });
                }

                // Emit socket event notification_created
                const { io } = require('../server');
                io.to(`user_${request.userId}`).emit('notification_created', {
                    id: `sm_incoming_${joiner.id}`,
                    title: 'New Join Request',
                    body: `${requester.firstName} ${requester.lastName} requested to join your "${request.subject}" meet.`,
                    createdAt: new Date().toISOString(),
                    read: false,
                    sender: {
                        id: requester.id,
                        firstName: requester.firstName,
                        lastName: requester.lastName,
                        profileImageUrl: requester.profileImageUrl,
                    },
                    data: {
                        type: 'strangers_meet_join_request',
                        requestId: request.id,
                    }
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
        const { action, userId } = req.body; // userId is the host user verifying authorization

        if (!userId) {
            res.status(400).json({ success: false, message: 'userId (host) is required' });
            return;
        }
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
            await joiner.update({ status: 'accepted' as any });

            // Notify participant
            try {
                const participant = await User.findByPk(joiner.userId);
                if (participant?.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(participant.fcmToken, {
                        title: '🎉 Request Accepted!',
                        body: `Your request to join "${request.subject}" has been accepted! Please complete the payment to secure your spot.`,
                        data: {
                            type: 'strangers_meet_request_accepted',
                            requestId: request.id,
                        }
                    });
                }

                // Emit socket event notification_created
                const { io } = require('../server');
                io.to(`user_${joiner.userId}`).emit('notification_created', {
                    id: `sm_req_accepted_${joiner.id}`,
                    title: 'Request Accepted',
                    body: `Your request to join "${request.subject}" was accepted by the host.`,
                    createdAt: new Date().toISOString(),
                    read: false,
                    data: {
                        type: 'strangers_meet_request_accepted',
                        requestId: request.id,
                    }
                });
            } catch (notifErr: any) {
                logger.warn('Failed to send join request accepted notifications: ' + notifErr.message);
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

            res.json({ success: true, message: 'Join request accepted!', data: joiner });
        } else {
            await joiner.update({ status: 'rejected' as any });

            // Notify participant of rejection
            try {
                const participant = await User.findByPk(joiner.userId);
                if (participant?.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(participant.fcmToken, {
                        title: 'Declined Request',
                        body: `Your request to join "${request.subject}" was declined by the host.`,
                        data: {
                            type: 'strangers_meet_request_rejected',
                            requestId: request.id,
                        }
                    });
                }

                // Emit socket event notification_created
                const { io } = require('../server');
                io.to(`user_${joiner.userId}`).emit('notification_created', {
                    id: `sm_req_rejected_${joiner.id}`,
                    title: 'Request Declined',
                    body: `Your request to join "${request.subject}" was declined by the host.`,
                    createdAt: new Date().toISOString(),
                    read: false,
                    data: {
                        type: 'strangers_meet_request_rejected',
                        requestId: request.id,
                    }
                });
            } catch (notifErr: any) {
                logger.warn('Failed to send join request rejected notifications: ' + notifErr.message);
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

            res.json({ success: true, message: 'Join request rejected.', data: joiner });
        }
    } catch (err: any) {
        logger.error('handleJoinRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to handle join request', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/settlement-request
// Host submits bank/UPI details to request meetup earnings settlement
// ─────────────────────────────────────────────────────────────────────────────
export const submitSettlementRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { userId, bankDetails } = req.body;

        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }
        if (!bankDetails?.trim()) {
            res.status(400).json({ success: false, message: 'bankDetails is required (UPI ID or Bank Account Details)' });
            return;
        }

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) {
            res.status(404).json({ success: false, message: 'Strangers meet request not found' });
            return;
        }

        if (request.userId !== userId) {
            res.status(403).json({ success: false, message: 'Unauthorized' });
            return;
        }

        // Ensure the event date has passed
        const now = new Date();
        const eventTime = new Date(request.eventDateTime);
        if (now < eventTime) {
            res.status(400).json({ success: false, message: 'Settlement can only be requested after the event date has passed' });
            return;
        }

        await request.update({
            settlementStatus: 'requested',
            bankDetails: bankDetails.trim(),
        });

        res.json({
            success: true,
            message: 'Settlement requested successfully! Admin has been notified. ⏳',
            data: {
                id: request.id,
                settlementStatus: 'requested',
                bankDetails: request.bankDetails,
            }
        });
    } catch (err: any) {
        logger.error('submitSettlementRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to request settlement', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/admin/strangers-meet/:id/pay-settlement
// Admin records settlement payout details
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

        // Send push notification to host
        try {
            const creator = await User.findByPk(request.userId);
            if (creator?.fcmToken) {
                const { sendPushNotification } = require('../services/fcmService');
                await sendPushNotification(creator.fcmToken, {
                    title: '💰 Settlement Paid',
                    body: `Your settlement of ₹${amount} for "${request.subject}" has been paid!`,
                    data: {
                        type: 'strangers_meet_settlement_paid',
                        requestId: request.id,
                    }
                });
            }
        } catch (notifErr: any) {
            logger.warn('Failed to send settlement paid push notification: ' + notifErr.message);
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
        const { userId, chargesPerHead } = req.body;

        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

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
        const request = await StrangersMeetRequest.findByPk(id, {
            include: [
                {
                    model: Venue,
                    as: 'venue',
                    attributes: ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone', 'latitude', 'longitude', 'images', 'imageUrl'],
                },
                {
                    model: User,
                    as: 'user',
                    attributes: ['id', 'firstName', 'lastName', 'username', 'profileImageUrl', 'subscriptionTier'],
                    include: [
                        { model: UserProfile, as: 'profile', attributes: ['bio', 'city'], required: false },
                        { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary'], required: false },
                    ],
                },
            ],
        });

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
                    photoUrl = '/' + primary.filePath.replace(/\\/g, '/');
                }
            }
            return photoUrl;
        };

        const hostRaw = (request as any).user;
        const hostData = hostRaw ? {
            id: hostRaw.id,
            firstName: hostRaw.firstName,
            lastName: hostRaw.lastName,
            username: hostRaw.username,
            profilePhotoUrl: resolveUserPhoto(hostRaw),
            subscriptionTier: hostRaw.subscriptionTier,
        } : null;

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

        res.json({
            success: true,
            data: {
                request: {
                    id: request.id,
                    subject: request.subject,
                    tagline: request.tagline,
                    eventDateTime: request.eventDateTime,
                    numberOfPersons: request.numberOfPersons,
                    paymentAmount: request.paymentAmount,
                    chargesPerHead: request.chargesPerHead,
                    status: request.status,
                    paymentStatus: request.paymentStatus,
                    ticketCode: ticketCode,
                    ticketUrl: ticketUrl,
                    host: hostData,
                    venue: (request as any).venue,
                },
                ticketCode: ticketCode,
                ticketUrl: ticketUrl,
            },
        });
    } catch (err: any) {
        logger.error('getStrangersMeetTicket error:', err);
        res.status(500).json({ success: false, error: err.message });
    }
};

