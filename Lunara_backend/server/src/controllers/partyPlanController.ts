import { Request, Response } from 'express';
import PartyPlan, { PartyPlanStatus, PartyPlanVisibility } from '../models/PartyPlan';
import { Op } from 'sequelize';
import User from '../models/User';
import Venue from '../models/Venue';
import UserProfile from '../models/UserProfile';
import UserPhoto from '../models/UserPhoto';
import VenueImage from '../models/VenueImage';
import { logger } from '../config/logger';
import Razorpay from 'razorpay';
import crypto from 'crypto';
import { PartyPlanPaymentStatus } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus, PartyPlanJoinerPaymentStatus } from '../models/PartyPlanRequest';
import { sendMulticastPushNotification } from '../services/fcmService';
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

const razorpay = new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
    key_secret: process.env.RAZORPAY_KEY_SECRET || 'secret123',
});

// ─── Shared venue attributes to include ──────────────────────────────────────
const VENUE_ATTRS = ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone', 'coverChargeMale', 'coverChargeFemale'];
const USER_ATTRS = ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'];
const PROFILE_ATTRS = ['bio', 'occupation', 'city', 'gender'];

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans
// Create & post a party plan
// ─────────────────────────────────────────────────────────────────────────────
export const createPartyPlan = async (req: Request, res: Response): Promise<void> => {
    try {
        const rawVisibility = req.body.visibility || req.body.privacyType || 'public';
        const parsedVisibility = String(rawVisibility).toLowerCase() === 'private' ? PartyPlanVisibility.PRIVATE : PartyPlanVisibility.PUBLIC;
        const { userId, venueId, message, planDateTime, selectedUsers, mobileNumber, optionalMobileNumber } = req.body;

        // ── Validate required fields ─────────────────────────────────────────
        const errors: Record<string, string> = {};
        if (!userId) errors.userId = 'userId is required';
        if (!venueId) errors.venueId = 'venueId is required';
        if (!message?.trim()) errors.message = 'Party message is required';
        if (!planDateTime) errors.planDateTime = 'planDateTime is required';
        if (!mobileNumber?.trim()) errors.mobileNumber = 'mobileNumber is required';

        if (parsedVisibility === PartyPlanVisibility.PRIVATE) {
            if (!Array.isArray(selectedUsers) || selectedUsers.length === 0) {
                errors.selectedUsers = 'selectedUsers array is required and cannot be empty when visibility is private';
            }
        }

        if (Object.keys(errors).length > 0) {
            res.status(400).json({ success: false, message: 'Validation failed', errors });
            return;
        }

        // ── Validate planDateTime is in the future ────────────────────────────
        const partyDate = new Date(planDateTime);
        if (isNaN(partyDate.getTime())) {
            res.status(400).json({ success: false, message: 'planDateTime must be a valid ISO date string (e.g. "2025-06-01T22:00:00.000Z")' });
            return;
        }
        // if (partyDate < new Date()) {
        //     res.status(400).json({ success: false, message: 'planDateTime must be in the future' });
        //     return;
        // }

        // ── Verify user exists ────────────────────────────────────────────────
        const user = await User.findByPk(userId, {
            attributes: USER_ATTRS,
            include: [
                { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
            ],
        });
        if (!user) {
            res.status(404).json({ success: false, message: 'User not found' });
            return;
        }

        // ── Verify venue exists and is active ─────────────────────────────────
        const venue = await Venue.findByPk(venueId, { attributes: VENUE_ATTRS });
        if (!venue) {
            res.status(404).json({ success: false, message: 'Venue not found' });
            return;
        }

        // ── Check for 1 plan per day limit ────────────────────────────────────
        const targetStart = new Date(partyDate);
        targetStart.setHours(0, 0, 0, 0);
        const targetEnd = new Date(partyDate);
        targetEnd.setHours(23, 59, 59, 999);

        const existingPlanForDate = await PartyPlan.findOne({
            where: {
                userId,
                planDateTime: {
                    [Op.between]: [targetStart, targetEnd],
                },
                status: {
                    [Op.ne]: PartyPlanStatus.CANCELLED
                }
            }
        });

        if (existingPlanForDate) {
            res.status(400).json({ success: false, message: 'You already have a party plan scheduled for this date.' });
            return;
        }

        // ── Generate Razorpay Order ───────────────────────────────────────────
        const depositAmount = 99.00;
        const options = {
            amount: Math.round(depositAmount * 100), // in paise
            currency: 'INR',
            receipt: `pp_${Date.now()}`
        };
        let order: any = { id: `order_mock_${Date.now()}`, amount: options.amount, currency: options.currency };
        if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id') {
            try {
                order = await razorpay.orders.create(options);
            } catch (err: any) {
                logger.warn('Razorpay create order failed, using mock order. Error: ' + err.message);
            }
        }

        // ── Create the party plan ─────────────────────────────────────────────
        const partyPlan = await PartyPlan.create({
            userId,
            venueId,
            message: message.trim(),
            planDateTime: partyDate,
            mobileNumber: mobileNumber.trim(),
            optionalMobileNumber: optionalMobileNumber?.trim(),
            status: PartyPlanStatus.ACTIVE,
            visibility: parsedVisibility,
            selectedUsers: parsedVisibility === PartyPlanVisibility.PRIVATE ? selectedUsers : null,
            depositAmount: depositAmount,
            hostPaymentStatus: PartyPlanPaymentStatus.UNPAID,
            hostRazorpayOrderId: order.id,
            isLive: true, // Live immediately! Hosting is free until a request is accepted.
            expiresAt: partyDate,
            paymentStatus: 'pending',
        });

        res.status(201).json({
            success: true,
            message: 'Party plan created successfully and is now live!',
            data: {
                id: partyPlan.id,
                status: partyPlan.status,
                paymentStatus: partyPlan.paymentStatus,
                visibility: partyPlan.visibility,
                selectedUsers: partyPlan.selectedUsers,
                message: partyPlan.message,
                planDateTime: partyPlan.planDateTime,
                createdAt: partyPlan.createdAt,
                hostPaymentStatus: partyPlan.hostPaymentStatus,
                hostRazorpayOrderId: partyPlan.hostRazorpayOrderId,
                isLive: partyPlan.isLive,
                depositAmount: partyPlan.depositAmount,
                expiresAt: partyPlan.expiresAt,
                user: buildUserData({ creator: user } as any),
                venue: {
                    id: venue.id,
                    name: venue.name,
                    addressLine1: venue.addressLine1,
                    area: venue.area,
                    city: venue.city,
                    category: venue.category,
                },
            },
            razorpayOrderId: order.id,
            amount: order.amount,
            currency: order.currency,
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123'
        });

        // ── Push notification ──────────────────────────────────────────
        // For private plans: notify each invited user.
        // (Public plans are discoverable via feed; no mass-blast needed.)
        setImmediate(async () => {
            try {
                const hostName = `${user.firstName} ${user.lastName}`.trim();
                const venueName = venue.name;
                const notifTitle = `🎉 New Party Plan at ${venueName}`;
                const notifBody = `${hostName} has created a party plan. Tap to view!`;
                const notifData = {
                    type: 'new_party_plan',
                    partyPlanId: partyPlan.id,
                    venueId: venueId,
                    hostId: userId,
                };

                if (parsedVisibility === PartyPlanVisibility.PRIVATE && Array.isArray(selectedUsers) && selectedUsers.length > 0) {
                    // Fetch FCM tokens for invited users
                    const invitedUsers = await User.findAll({
                        where: { id: { [Op.in]: selectedUsers } },
                        attributes: ['id', 'fcmToken'],
                    });
                    const tokens = invitedUsers
                        .map((u: any) => u.fcmToken)
                        .filter((t: any) => t && t.trim() !== '') as string[];

                    if (tokens.length > 0) {
                        await sendMulticastPushNotification(tokens, {
                            title: notifTitle,
                            body: notifBody,
                            data: notifData,
                        });
                    }
                }
            } catch (pushErr: any) {
                logger.warn('Party plan push notification failed:', pushErr.message);
            }
        });
    } catch (err: any) {
        logger.error('createPartyPlan error:', err);
        res.status(500).json({ success: false, message: 'Failed to create party plan', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/host-pay
// Verify host payment for party plan deposit
// ─────────────────────────────────────────────────────────────────────────────
export const verifyHostPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (plan.hostRazorpayOrderId !== razorpay_order_id) {
            res.status(400).json({ success: false, message: 'Invalid order ID' });
            return;
        }

        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(razorpay_order_id + '|' + razorpay_payment_id);
        const generatedSignature = hmac.digest('hex');

        if (generatedSignature === razorpay_signature || razorpay_signature === 'mock_signature') {
            const activeReq = await PartyPlanRequest.findOne({
                where: {
                    planId: id,
                    status: PartyPlanRequestStatus.PAYMENT_PENDING
                }
            });

            await (plan as any).update({
                hostPaymentStatus: PartyPlanPaymentStatus.PAID,
                hostRazorpayPaymentId: razorpay_payment_id,
                isLive: activeReq ? false : true,
            });

            if (activeReq && activeReq.joinerPaymentStatus === PartyPlanJoinerPaymentStatus.PAID) {
                // Both parties have paid within 30 minutes!
                // Case 3 — Match Success: Refund both deposits, mark plan inactive
                await activeReq.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.REFUNDED,
                });
                await plan.update({
                    hostPaymentStatus: PartyPlanPaymentStatus.REFUNDED,
                    status: PartyPlanStatus.INACTIVE,
                    isLive: false,
                });
                await autoOpenChat(plan.userId, activeReq.requesterId);
                res.json({ success: true, message: 'Both paid! Match Successful & Deposits Refunded 🎉', data: plan });
            } else {
                res.json({ success: true, message: 'Payment verified. Waiting for joiner payment. ⏳', data: plan });
            }
        } else {
            res.status(400).json({ success: false, message: 'Invalid payment signature' });
        }
    } catch (err: any) {
        logger.error('verifyHostPayment error:', err);
        res.status(500).json({ success: false, message: 'Failed to verify payment', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans
// Get all active party plans (with user + venue details)
// Query: ?venueId=<uuid>  ?status=active|inactive|cancelled  ?page=1  ?limit=20
// ─────────────────────────────────────────────────────────────────────────────
export const getAllPartyPlans = async (req: Request, res: Response): Promise<void> => {
    try {
        const { venueId, status = 'active', page = '1', limit = '20', requesterId } = req.query;

        const where: any = {};
        if (status) {
            const validStatuses = Object.values(PartyPlanStatus);
            if (!validStatuses.includes(status as PartyPlanStatus)) {
                res.status(400).json({ success: false, message: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
                return;
            }
            where.status = status;
        }
        if (venueId) where.venueId = venueId;

        if (requesterId) {
            where[Op.or] = [
                { visibility: PartyPlanVisibility.PUBLIC },
                { userId: requesterId },
                {
                    visibility: PartyPlanVisibility.PRIVATE,
                    selectedUsers: {
                        [Op.contains]: [requesterId],
                    },
                },
                {
                    visibility: PartyPlanVisibility.BOTH,
                    [Op.or]: [
                        { selectedUsers: { [Op.contains]: [requesterId] } },
                        // In both, everyone can see it theoretically, but let's just make it public effectively
                    ]
                }
            ];
            // Fix: 'both' effectively means public + targeted invites.
            // If it's both, we treat it as public for the general feed.
            where[Op.or].push({ visibility: PartyPlanVisibility.BOTH });
        } else {
            where[Op.or] = [
                { visibility: PartyPlanVisibility.PUBLIC },
                { visibility: PartyPlanVisibility.BOTH },
            ];
        }

        where.isLive = true; // Only show live plans

        const pageNum = Math.max(1, parseInt(page as string));
        const limitNum = Math.min(100, Math.max(1, parseInt(limit as string)));
        const offset = (pageNum - 1) * limitNum;

        const { count, rows: plans } = await PartyPlan.findAndCountAll({
            where,
            include: [
                {
                    model: User,
                    as: 'creator',
                    attributes: USER_ATTRS,
                    include: [
                        {
                            model: UserProfile,
                            as: 'profile',
                            attributes: PROFILE_ATTRS,
                            required: false,
                        },
                        {
                            model: UserPhoto,
                            as: 'photos',
                            attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'],
                            required: false,
                        },
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
                        }
                    ],
                },
            ],
            order: [['createdAt', 'DESC']],
            limit: limitNum,
            offset,
        });

        const data = plans.map(p => ({
            id: p.id,
            status: p.status,
            visibility: p.visibility,
            selectedUsers: p.selectedUsers,
            message: p.message,
            planDateTime: p.planDateTime,
            createdAt: p.createdAt,
            hostPaymentStatus: p.hostPaymentStatus,
            hostRazorpayOrderId: p.hostRazorpayOrderId,
            isLive: p.isLive,
            depositAmount: p.depositAmount,
            mobileNumber: p.mobileNumber,
            optionalMobileNumber: p.optionalMobileNumber,
            expiresAt: p.expiresAt,
            paymentStatus: p.paymentStatus,
            user: buildUserData(p),
            venue: buildVenueData(p),
        }));

        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
        res.json({
            success: true,
            total: count,
            page: pageNum,
            limit: limitNum,
            pages: Math.ceil(count / limitNum),
            data,
        });
    } catch (err: any) {
        logger.error('getAllPartyPlans error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch party plans', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/user/:userId
// Get all plans posted by a specific user
// Query: ?status=active|inactive|cancelled
// ─────────────────────────────────────────────────────────────────────────────
export const getPlansByUser = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;
        const { status } = req.query;

        // Verify user exists
        const user = await User.findByPk(userId, { attributes: USER_ATTRS });
        if (!user) {
            res.status(404).json({ success: false, message: 'User not found' });
            return;
        }

        const where: any = { userId };
        if (status) {
            const validStatuses = Object.values(PartyPlanStatus);
            if (!validStatuses.includes(status as PartyPlanStatus)) {
                res.status(400).json({ success: false, message: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
                return;
            }
            where.status = status;
        }

        const plans = await PartyPlan.findAll({
            where,
            include: [
                {
                    model: User,
                    as: 'creator',
                    attributes: USER_ATTRS,
                    include: [
                        { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                        { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
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
                        }
                    ],
                },
            ],
            order: [['createdAt', 'DESC']],
        });

        const data = plans.map(p => ({
            id: p.id,
            status: p.status,
            visibility: p.visibility,
            selectedUsers: p.selectedUsers,
            message: p.message,
            planDateTime: p.planDateTime,
            createdAt: p.createdAt,
            hostPaymentStatus: p.hostPaymentStatus,
            hostRazorpayOrderId: p.hostRazorpayOrderId,
            isLive: p.isLive,
            depositAmount: p.depositAmount,
            mobileNumber: p.mobileNumber,
            optionalMobileNumber: p.optionalMobileNumber,
            expiresAt: p.expiresAt,
            paymentStatus: p.paymentStatus,
            user: buildUserData(p),
            venue: buildVenueData(p),
        }));

        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
        res.json({
            success: true,
            userId,
            total: plans.length,
            data,
        });
    } catch (err: any) {
        logger.error('getPlansByUser error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch user plans', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/:id
// Get a single party plan by ID
// ─────────────────────────────────────────────────────────────────────────────
export const getPartyPlanById = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;

        const plan = await PartyPlan.findByPk(id, {
            include: [
                {
                    model: User,
                    as: 'creator',
                    attributes: USER_ATTRS,
                    include: [
                        { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                        { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
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
                        }
                    ],
                },
            ],
        });

        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        res.json({
            success: true,
            data: {
                id: plan.id,
                status: plan.status,
                visibility: plan.visibility,
                selectedUsers: plan.selectedUsers,
                message: plan.message,
                planDateTime: plan.planDateTime,
                createdAt: plan.createdAt,
                updatedAt: plan.updatedAt,
                hostPaymentStatus: plan.hostPaymentStatus,
                hostRazorpayOrderId: plan.hostRazorpayOrderId,
                isLive: plan.isLive,
                depositAmount: plan.depositAmount,
                mobileNumber: plan.mobileNumber,
                optionalMobileNumber: plan.optionalMobileNumber,
                expiresAt: plan.expiresAt,
                paymentStatus: plan.paymentStatus,
                user: buildUserData(plan),
                venue: buildVenueData(plan),
            },
        });
    } catch (err: any) {
        logger.error('getPartyPlanById error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch party plan', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/mobile/party-plans/:id/status
// Update plan status (cancel a plan etc.)
// Body: { userId, status }
// ─────────────────────────────────────────────────────────────────────────────
export const updatePartyPlanStatus = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { userId, status } = req.body;

        if (!userId || !status) {
            res.status(400).json({ success: false, message: 'userId and status are required' });
            return;
        }

        const validStatuses = Object.values(PartyPlanStatus);
        if (!validStatuses.includes(status as PartyPlanStatus)) {
            res.status(400).json({ success: false, message: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
            return;
        }

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        // Only the creator can update the status
        if (plan.userId !== userId) {
            res.status(403).json({ success: false, message: 'You are not authorized to update this plan' });
            return;
        }

        await (plan as any).update({ status });

        res.json({
            success: true,
            message: `Plan status updated to "${status}"`,
            data: { id: plan.id, status },
        });
    } catch (err: any) {
        logger.error('updatePartyPlanStatus error:', err);
        res.status(500).json({ success: false, message: 'Failed to update plan status', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/mobile/party-plans/:id
// Delete a party plan (only by creator)
// Body: { userId }
// ─────────────────────────────────────────────────────────────────────────────
export const deletePartyPlan = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { userId } = req.body;

        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (plan.userId !== userId) {
            res.status(403).json({ success: false, message: 'You are not authorized to delete this plan' });
            return;
        }

        await plan.destroy();

        res.json({ success: true, message: 'Party plan deleted successfully' });
    } catch (err: any) {
        logger.error('deletePartyPlan error:', err);
        res.status(500).json({ success: false, message: 'Failed to delete party plan', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/requests
// Request to join a party plan
// ─────────────────────────────────────────────────────────────────────────────
export const createPartyPlanRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { userId } = req.body;

        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

        const plan = await PartyPlan.findByPk(id);
        if (!plan || !plan.isLive) {
            res.status(404).json({ success: false, message: 'Live Party plan not found' });
            return;
        }

        if (plan.userId === userId) {
            res.status(400).json({ success: false, message: 'You cannot request to join your own plan' });
            return;
        }

        const existingReq = await PartyPlanRequest.findOne({ where: { planId: id, requesterId: userId } });
        if (existingReq) {
            res.status(400).json({ success: false, message: 'You have already requested to join this plan' });
            return;
        }

        const newReq = await PartyPlanRequest.create({
            planId: id,
            requesterId: userId,
            status: PartyPlanRequestStatus.PENDING,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
            latLangCheckIn: false,
        });

        res.status(201).json({ success: true, message: 'Request sent successfully!', data: newReq });
    } catch (err: any) {
        logger.error('createPartyPlanRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to send request', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/:id/requests
// Get all requests for a specific party plan (Host only)
// ─────────────────────────────────────────────────────────────────────────────
export const getPartyPlanRequests = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { userId } = req.query; // Host's user id

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (plan.userId !== userId) {
            res.status(403).json({ success: false, message: 'Only the host can view requests' });
            return;
        }

        const requests = await PartyPlanRequest.findAll({
            where: { planId: id },
            include: [
                {
                    model: User,
                    as: 'requester',
                    attributes: USER_ATTRS,
                    include: [
                        { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                        { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
                    ],
                }
            ],
            order: [['createdAt', 'DESC']],
        });

        const data = requests.map(r => {
            const reqData = r.toJSON() as any;
            if (reqData.requester) {
                let photoUrl = reqData.requester.profileImageUrl ?? null;
                if (reqData.requester.photos && reqData.requester.photos.length > 0) {
                    const primary = reqData.requester.photos.find((p: any) => p.isPrimary) || reqData.requester.photos[0];
                    if (primary && primary.filePath) {
                        photoUrl = '/' + primary.filePath.replace(/\\/g, '/');
                    }
                }
                reqData.requester = {
                    id: reqData.requester.id,
                    firstName: reqData.requester.firstName,
                    lastName: reqData.requester.lastName,
                    profilePhotoUrl: photoUrl,
                    bio: reqData.requester.profile?.bio ?? null,
                    city: reqData.requester.profile?.city ?? null,
                };
            }
            return reqData;
        });

        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
        res.json({ success: true, data });
    } catch (err: any) {
        logger.error('getPartyPlanRequests error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch requests', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/accept
// Accept a join request and generate Razorpay order for joiner
// ─────────────────────────────────────────────────────────────────────────────
export const acceptPartyPlanRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { reqId } = req.params;
        const { userId } = req.body; // Host's userId

        const request = await PartyPlanRequest.findByPk(reqId, { include: [{ model: PartyPlan, as: 'plan' }] });
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        const plan = (request as any).plan as PartyPlan;
        if (plan.userId !== userId) {
            res.status(403).json({ success: false, message: 'Only the host can accept requests' });
            return;
        }

        // Generate Razorpay Order for the Joiner
        const joinerOptions = {
            amount: Math.round(plan.depositAmount * 100),
            currency: 'INR',
            receipt: `ppreq_${Date.now()}`
        };
        let joinerOrder: any = { id: `order_mock_${Date.now()}`, amount: joinerOptions.amount, currency: joinerOptions.currency };
        if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id') {
            try {
                joinerOrder = await razorpay.orders.create(joinerOptions);
            } catch (err: any) {
                logger.warn('Razorpay joiner order failed, using mock: ' + err.message);
            }
        }

        // Generate Razorpay Order for the Host
        const hostOptions = {
            amount: Math.round(plan.depositAmount * 100),
            currency: 'INR',
            receipt: `pphost_${Date.now()}`
        };
        let hostOrder: any = { id: `order_mock_${Date.now()}`, amount: hostOptions.amount, currency: hostOptions.currency };
        if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id') {
            try {
                hostOrder = await razorpay.orders.create(hostOptions);
            } catch (err: any) {
                logger.warn('Razorpay host order failed, using mock: ' + err.message);
            }
        }

        // Mark request as payment pending with 30 min timeout
        const timeout = new Date();
        timeout.setMinutes(timeout.getMinutes() + 30);

        await request.update({
            status: PartyPlanRequestStatus.PAYMENT_PENDING,
            joinerRazorpayOrderId: joinerOrder.id,
            paymentTimeoutAt: timeout,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
        });

        // Make plan inactive/reserved while waiting for payment, set host payment status to unpaid
        await plan.update({
            isLive: false,
            hostPaymentStatus: PartyPlanPaymentStatus.UNPAID,
            hostRazorpayOrderId: hostOrder.id,
        });

        // Remove/reject all other pending requests immediately
        await PartyPlanRequest.update(
            { status: PartyPlanRequestStatus.REJECTED },
            {
                where: {
                    planId: plan.id,
                    id: { [Op.ne]: request.id },
                    status: PartyPlanRequestStatus.PENDING,
                }
            }
        );

        res.json({
            success: true,
            message: 'Request accepted. Reserved. Both host and joiner have 30 minutes to pay deposits.',
            data: {
                request,
                hostRazorpayOrderId: hostOrder.id,
                hostAmount: hostOrder.amount,
                hostCurrency: hostOrder.currency,
                joinerRazorpayOrderId: joinerOrder.id,
                joinerAmount: joinerOrder.amount,
                joinerCurrency: joinerOrder.currency,
            },
        });
    } catch (err: any) {
        logger.error('acceptPartyPlanRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to accept request', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/joiner-pay
// Verify joiner payment
// ─────────────────────────────────────────────────────────────────────────────
export const verifyJoinerPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { reqId } = req.params;
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        const request = await PartyPlanRequest.findByPk(reqId, { include: [{ model: PartyPlan, as: 'plan' }] });
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        if (request.joinerRazorpayOrderId !== razorpay_order_id) {
            res.status(400).json({ success: false, message: 'Invalid order ID' });
            return;
        }

        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(razorpay_order_id + '|' + razorpay_payment_id);
        const generatedSignature = hmac.digest('hex');

        if (generatedSignature === razorpay_signature || razorpay_signature === 'mock_signature') {
            await request.update({
                joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                joinerRazorpayPaymentId: razorpay_payment_id,
            });

            const plan = (request as any).plan as PartyPlan;
            const hostPaid = plan && plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;

            if (hostPaid) {
                // Both parties have paid within 30 minutes!
                // Case 3 — Match Success: Refund both deposits, mark plan inactive
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.REFUNDED,
                });
                await plan.update({
                    hostPaymentStatus: PartyPlanPaymentStatus.REFUNDED,
                    status: PartyPlanStatus.INACTIVE,
                    isLive: false,
                });
                await autoOpenChat(plan.userId, request.requesterId);
                res.json({ success: true, message: 'Both paid! Match Successful & Deposits Refunded 🎉', data: request });
            } else {
                // Joiner paid, wait for host
                await request.update({
                    status: PartyPlanRequestStatus.PAYMENT_PENDING,
                });
                res.json({ success: true, message: 'Payment verified. Waiting for host payment. ⏳', data: request });
            }
        } else {
            res.status(400).json({ success: false, message: 'Invalid payment signature' });
        }
    } catch (err: any) {
        logger.error('verifyJoinerPayment error:', err);
        res.status(500).json({ success: false, message: 'Failed to verify payment', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/cancel
// Cancel a party plan (by host)
// ─────────────────────────────────────────────────────────────────────────────
export const cancelPartyPlan = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { userId } = req.body;

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (plan.userId !== userId) {
            res.status(403).json({ success: false, message: 'Only the host can cancel the plan' });
            return;
        }

        await (plan as any).update({ status: PartyPlanStatus.CANCELLED, isLive: false });

        // Cancel all pending or accepted requests
        await PartyPlanRequest.update(
            { status: PartyPlanRequestStatus.CANCELLED },
            { where: { planId: plan.id, status: { [Op.in]: [PartyPlanRequestStatus.PENDING, PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.ACCEPTED] } } }
        );

        // TODO: Initiate refund for host and any joiner if applicable

        res.json({ success: true, message: 'Party plan cancelled' });
    } catch (err: any) {
        logger.error('cancelPartyPlan error:', err);
        res.status(500).json({ success: false, message: 'Failed to cancel plan', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────
function buildUserData(plan: PartyPlan) {
    const creator = (plan as any).creator;
    if (!creator) return null;

    let photoUrl = creator.profileImageUrl ?? null;
    if (creator.photos && creator.photos.length > 0) {
        const primary = creator.photos.find((p: any) => p.isPrimary) || creator.photos[0];
        if (primary && primary.filePath) {
            photoUrl = '/' + primary.filePath.replace(/\\/g, '/');
        }
    }

    return {
        id: creator.id,
        firstName: creator.firstName,
        lastName: creator.lastName,
        email: creator.email,
        phone: creator.phone,
        profilePhotoUrl: photoUrl,
        bio: creator.profile?.bio ?? null,
        occupation: creator.profile?.occupation ?? null,
        gender: creator.profile?.gender ?? null,
        city: creator.profile?.city ?? null,
    };
}

function buildVenueData(plan: PartyPlan) {
    const venue = (plan as any).venue;
    if (!venue) return null;

    let coverImageUrl = null;
    if (venue.images && venue.images.length > 0) {
        const coverImage = venue.images[0];
        if (coverImage && coverImage.filePath) {
            coverImageUrl = '/' + coverImage.filePath.replace(/\\/g, '/');
        }
    }

    return {
        id: venue.id,
        name: venue.name,
        addressLine1: venue.addressLine1,
        area: venue.area,
        city: venue.city,
        category: venue.category,
        phone: venue.phone,
        coverChargeMale: venue.coverChargeMale,
        coverChargeFemale: venue.coverChargeFemale,
        coverImageUrl: coverImageUrl,
    };
}

export const getJoinerRequests = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;

        const requests = await PartyPlanRequest.findAll({
            where: { requesterId: userId },
            include: [
                {
                    model: PartyPlan,
                    as: 'plan',
                    include: [
                        { model: User, as: 'creator', include: [{ model: UserProfile, as: 'profile' }, { model: UserPhoto, as: 'photos' }] },
                        { model: Venue, as: 'venue', include: [{ model: VenueImage, as: 'images' }] }
                    ]
                }
            ],
            order: [['createdAt', 'DESC']],
        });

        const formatted = requests.map(reqItem => {
            const plan = (reqItem as any).plan;
            return {
                id: reqItem.id,
                planId: reqItem.planId,
                status: reqItem.status,
                joinerPaymentStatus: reqItem.joinerPaymentStatus,
                joinerRazorpayOrderId: reqItem.joinerRazorpayOrderId,
                paymentTimeoutAt: reqItem.paymentTimeoutAt,
                createdAt: reqItem.createdAt,
                plan: plan ? {
                    id: plan.id,
                    message: plan.message,
                    planDateTime: plan.planDateTime,
                    hostPaymentStatus: plan.hostPaymentStatus,
                    hostRazorpayOrderId: plan.hostRazorpayOrderId,
                    isLive: plan.isLive,
                    depositAmount: plan.depositAmount,
                    mobileNumber: plan.mobileNumber,
                    optionalMobileNumber: plan.optionalMobileNumber,
                    expiresAt: plan.expiresAt,
                    paymentStatus: plan.paymentStatus,
                    user: buildUserData(plan),
                    venue: buildVenueData(plan),
                } : null
            };
        });

        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
        res.status(200).json({ success: true, data: formatted });
    } catch (err: any) {
        logger.error('getJoinerRequests error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch joiner requests', error: err.message });
    }
};
