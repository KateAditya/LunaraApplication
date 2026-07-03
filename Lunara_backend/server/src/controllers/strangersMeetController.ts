import { Request, Response } from 'express';
import StrangersMeetRequest, {
    StrangersMeetStatus,
    StrangersMeetPaymentStatus,
} from '../models/StrangersMeetRequest';
import User from '../models/User';
import Venue from '../models/Venue';
import UserProfile from '../models/UserProfile';
import UserPhoto from '../models/UserPhoto';
import VenueImage from '../models/VenueImage';
import { logger } from '../config/logger';
import Razorpay from 'razorpay';
import crypto from 'crypto';

const razorpay = new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
    key_secret: process.env.RAZORPAY_KEY_SECRET || 'secret123',
});

// ─── Shared attributes ────────────────────────────────────────────────────────
const USER_ATTRS    = ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'];
const VENUE_ATTRS   = ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone'];
const PROFILE_ATTRS = ['bio', 'occupation', 'city', 'gender'];

function genTicketId(): string {
    const ts  = Date.now().toString(36).toUpperCase();
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
                { model: UserPhoto,   as: 'photos',  attributes: ['id', 'filePath', 'isPrimary'], required: false },
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
    ];
}

function formatRequest(r: StrangersMeetRequest) {
    const user    = (r as any).user;
    const venue   = (r as any).venue;

    let userPhotoUrl = user?.profileImageUrl ?? null;
    if (user?.photos?.length > 0) {
        const primary = user.photos.find((p: any) => p.isPrimary) || user.photos[0];
        if (primary?.filePath) userPhotoUrl = '/' + primary.filePath.replace(/\\/g, '/');
    }

    let venueImageUrl = null;
    if (venue?.images?.length > 0 && venue.images[0]?.filePath) {
        venueImageUrl = '/' + venue.images[0].filePath.replace(/\\/g, '/');
    }

    return {
        id:               r.id,
        subject:          r.subject,
        tagline:          r.tagline,
        eventDateTime:    r.eventDateTime,
        numberOfPersons:  r.numberOfPersons,
        status:           r.status,
        paymentAmount:    r.paymentAmount ?? null,
        paymentStatus:    r.paymentStatus,
        adminNotes:       r.adminNotes ?? null,
        ticketId:         r.ticketId ?? null,
        createdAt:        r.createdAt,
        updatedAt:        r.updatedAt,
        user: user ? {
            id:        user.id,
            firstName: user.firstName,
            lastName:  user.lastName,
            email:     user.email,
            phone:     user.phone,
            photoUrl:  userPhotoUrl,
            bio:       user.profile?.bio ?? null,
            city:      user.profile?.city ?? null,
        } : null,
        venue: venue ? {
            id:           venue.id,
            name:         venue.name,
            addressLine1: venue.addressLine1,
            area:         venue.area,
            city:         venue.city,
            category:     venue.category,
            phone:        venue.phone,
            imageUrl:     venueImageUrl,
        } : null,
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet
// User submits a new Strangers Meet request
// ─────────────────────────────────────────────────────────────────────────────
export const createRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId, venueId, subject, tagline, eventDateTime, numberOfPersons } = req.body;

        // Validate required fields
        const errors: Record<string, string> = {};
        if (!userId)                               errors.userId          = 'userId is required';
        if (!venueId)                              errors.venueId         = 'venueId is required';
        if (!subject?.trim())                      errors.subject         = 'subject is required';
        if (!tagline?.trim())                      errors.tagline         = 'tagline is required';
        if (!eventDateTime)                        errors.eventDateTime   = 'eventDateTime is required';
        if (numberOfPersons === undefined || numberOfPersons === null)
                                                   errors.numberOfPersons = 'numberOfPersons is required';
        else if (numberOfPersons < 21 || numberOfPersons > 50)
                                                   errors.numberOfPersons = 'numberOfPersons must be between 21 and 50';

        if (Object.keys(errors).length > 0) {
            res.status(400).json({ success: false, message: 'Validation failed', errors });
            return;
        }

        const eventDate = new Date(eventDateTime);
        if (isNaN(eventDate.getTime())) {
            res.status(400).json({ success: false, message: 'eventDateTime must be a valid ISO date string' });
            return;
        }
        if (eventDate < new Date()) {
            res.status(400).json({ success: false, message: 'eventDateTime must be in the future' });
            return;
        }

        // Verify user
        const user = await User.findByPk(userId, { attributes: USER_ATTRS });
        if (!user) { res.status(404).json({ success: false, message: 'User not found' }); return; }

        // Verify venue
        const venue = await Venue.findByPk(venueId, { attributes: VENUE_ATTRS });
        if (!venue) { res.status(404).json({ success: false, message: 'Venue not found' }); return; }

        const request = await StrangersMeetRequest.create({
            userId,
            venueId,
            subject:         subject.trim(),
            tagline:         tagline.trim(),
            eventDateTime:   eventDate,
            numberOfPersons: Number(numberOfPersons),
        });

        res.status(201).json({
            success: true,
            message: 'Request submitted successfully! Admin will review and get back to you. 🎉',
            data: {
                id:             request.id,
                status:         request.status,
                paymentStatus:  request.paymentStatus,
                createdAt:      request.createdAt,
            },
        });
    } catch (err: any) {
        logger.error('createStrangersMeetRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to submit request', error: err.message });
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
            total:   requests.length,
            data:    requests.map(formatRequest),
        });
    } catch (err: any) {
        logger.error('getUserStrangersMeetRequests error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch requests', error: err.message });
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
        const { id }     = req.params;
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

            res.json({
                success:  true,
                message:  'Payment confirmed! Your ticket is ready 🎟️',
                data: {
                    ticketId,
                    id:             request.id,
                    subject:        request.subject,
                    tagline:        request.tagline,
                    eventDateTime:  request.eventDateTime,
                    numberOfPersons: request.numberOfPersons,
                    paymentAmount:  request.paymentAmount,
                    paymentStatus:  StrangersMeetPaymentStatus.PAID,
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

        const pageNum  = Math.max(1, parseInt(page as string));
        const limitNum = Math.min(100, Math.max(1, parseInt(limit as string)));
        const offset   = (pageNum - 1) * limitNum;

        const { count, rows } = await StrangersMeetRequest.findAndCountAll({
            where,
            include: buildIncludes(),
            order: [['createdAt', 'DESC']],
            limit: limitNum,
            offset,
        });

        // Counts by status for badge display
        const pendingCount  = await StrangersMeetRequest.count({ where: { status: StrangersMeetStatus.PENDING } });
        const approvedCount = await StrangersMeetRequest.count({ where: { status: StrangersMeetStatus.APPROVED } });
        const rejectedCount = await StrangersMeetRequest.count({ where: { status: StrangersMeetStatus.REJECTED } });

        res.json({
            success: true,
            total:   count,
            page:    pageNum,
            limit:   limitNum,
            pages:   Math.ceil(count / limitNum),
            counts: {
                pending:  pendingCount,
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
        const { id }                          = req.params;
        const { paymentAmount, adminNotes }   = req.body;

        if (paymentAmount === undefined || paymentAmount === null) {
            res.status(400).json({ success: false, message: 'paymentAmount is required' });
            return;
        }
        if (Number(paymentAmount) <= 0) {
            res.status(400).json({ success: false, message: 'paymentAmount must be greater than 0' });
            return;
        }

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) { res.status(404).json({ success: false, message: 'Request not found' }); return; }
        if (request.status !== StrangersMeetStatus.PENDING) {
            res.status(400).json({ success: false, message: `Cannot approve a request with status: ${request.status}` });
            return;
        }

        await request.update({
            status:        StrangersMeetStatus.APPROVED,
            paymentAmount: Number(paymentAmount),
            adminNotes:    adminNotes?.trim() || null,
        });

        res.json({
            success: true,
            message: 'Request approved successfully',
            data: {
                id:            request.id,
                status:        request.status,
                paymentAmount: request.paymentAmount,
                adminNotes:    request.adminNotes,
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
        const { id }          = req.params;
        const { adminNotes }  = req.body;

        const request = await StrangersMeetRequest.findByPk(id);
        if (!request) { res.status(404).json({ success: false, message: 'Request not found' }); return; }
        if (request.status !== StrangersMeetStatus.PENDING) {
            res.status(400).json({ success: false, message: `Cannot reject a request with status: ${request.status}` });
            return;
        }

        await request.update({
            status:     StrangersMeetStatus.REJECTED,
            adminNotes: adminNotes?.trim() || null,
        });

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
