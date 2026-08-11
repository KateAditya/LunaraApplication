import { Request, Response } from 'express';
import PartyPlan, { PartyPlanStatus, PartyPlanVisibility, PartyPlanPaymentType } from '../models/PartyPlan';
import { PlanEligibilityService } from '../services/PlanEligibilityService';
import { Op, Transaction } from 'sequelize';
import User from '../models/User';
import Venue from '../models/Venue';
import UserProfile from '../models/UserProfile';
import UserPhoto from '../models/UserPhoto';
import VenueImage from '../models/VenueImage';
import { logger } from '../config/logger';
import Razorpay from 'razorpay';
import crypto from 'crypto';
import sequelize from '../config/database';
import { PartyPlanPaymentStatus, PartyPlanLifecycleStatus } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus, PartyPlanJoinerPaymentStatus } from '../models/PartyPlanRequest';
import { sendMulticastPushNotification } from '../services/fcmService';
import Conversation from '../models/Conversation';
import ChatSubscription, { ChatSubscriptionStatus, ChatSubscriptionType } from '../models/ChatSubscription';
import { getChatSettings } from './chatSubscriptionController';
import { validateVenueTimingAndHolidays } from '../utils/venueValidator';
import { checkExistingBookingForDate } from '../utils/bookingLimitValidator';
import Booking, { BookingStatus, GoingMode, PaymentStatus as BookingPaymentStatus } from '../models/Booking';
import Payment, { PaymentMethod, PaymentStatus } from '../models/Payment';
import { generateTicketForBookingHelper } from '../services/ticketService';
import { NotificationService } from '../services/NotificationService';

// ─────────────────────────────────────────────────────────────────────────────
// autoOpenChat — ONLY called after MATCH_CONFIRMED. Guarded by lifecycleStatus.
// ─────────────────────────────────────────────────────────────────────────────
async function autoOpenChat(hostId: string, joinerId: string, planId: string) {
    try {
        // Safety gate: verify plan is in MATCH_CONFIRMED or CHAT_ENABLED state
        const plan = await PartyPlan.findByPk(planId);
        if (!plan || (
            plan.lifecycleStatus !== PartyPlanLifecycleStatus.MATCH_CONFIRMED &&
            plan.lifecycleStatus !== PartyPlanLifecycleStatus.CHAT_ENABLED
        )) {
            logger.warn(`[autoOpenChat] Blocked — plan ${planId} not in MATCH_CONFIRMED state (current: ${plan?.lifecycleStatus})`);
            return;
        }

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
            paidById: hostId,
            amount: 0,
            daysGranted: freeDays,
            validUntil,
            status: ChatSubscriptionStatus.ACTIVE,
            subscriptionType: ChatSubscriptionType.FREE,
        });

        // Update plan lifecycle to CHAT_ENABLED
        await plan.update({ lifecycleStatus: PartyPlanLifecycleStatus.CHAT_ENABLED });

        // Notify both users via NotificationService (single source, no duplication)
        await NotificationService.dispatch({
            recipientUserId: hostId,
            actorUserId: joinerId,
            eventType: 'chat_unlocked',
            category: 'messages',
            entityType: 'party_plan',
            entityId: planId,
            title: '💬 Chat Unlocked!',
            body: 'Your match is confirmed and private chat is now active.',
            metadata: { planId, conversationId: conv.id },
            idempotencyKey: `chat_unlocked_host_${planId}`,
        });
        await NotificationService.dispatch({
            recipientUserId: joinerId,
            actorUserId: hostId,
            eventType: 'chat_unlocked',
            category: 'messages',
            entityType: 'party_plan',
            entityId: planId,
            title: '💬 Chat Unlocked!',
            body: 'Your match is confirmed and private chat is now active.',
            metadata: { planId, conversationId: conv.id },
            idempotencyKey: `chat_unlocked_joiner_${planId}`,
        });

        // FCM push
        setImmediate(async () => {
            try {
                const host = await User.findByPk(hostId);
                const joiner = await User.findByPk(joinerId);
                const tokens = [host?.fcmToken, joiner?.fcmToken].filter(t => t && t.trim() !== '') as string[];
                if (tokens.length > 0) {
                    await sendMulticastPushNotification(tokens, {
                        title: '💬 Chat Unlocked!',
                        body: 'Your match is confirmed and private chat is now active for 7 days.',
                        data: { type: 'chat_unlocked', conversationId: conv!.id },
                    });
                }
            } catch (err: any) {
                logger.warn('Failed to send chat unlocked FCM push:', err.message);
            }
        });
    } catch (err: any) {
        logger.error('autoOpenChat error:', err);
    }
}

async function createBookingAndPayments(plan: PartyPlan, request: PartyPlanRequest, transaction?: Transaction) {
    try {
        const existingBooking = await Booking.findOne({
            where: {
                goingMode: GoingMode.PARTY_REQUEST,
                userId: plan.userId,
                venueId: plan.venueId,
                bookingDate: plan.planDateTime,
            },
            transaction
        });
        if (existingBooking) {
            logger.info(`Booking already exists for plan ${plan.id}, skipping creation.`);
            // Still emit ticket_generated with existing data so late-arriving clients get it
            try {
                const { io } = require('../server');
                const ticketData = {
                    bookingId: existingBooking.id,
                    ticketCode: existingBooking.ticketCode,
                    planId: plan.id,
                    requestId: request.id,
                    expiresAt: plan.planDateTime.toISOString(),
                };
                io.to(`user_${plan.userId}`).emit('party_plan_ticket_generated', ticketData);
                io.to(`user_${request.requesterId}`).emit('party_plan_ticket_generated', ticketData);
            } catch (_) {}
            return;
        }

        const dateObj = new Date(plan.planDateTime);
        const bookingDate = dateObj.toISOString().split('T')[0];
        const startTime = dateObj.toTimeString().split(' ')[0];

        // Ticket code format: PP-XXXXXX (uppercase alphanumeric)
        const ticketCode = 'PP-' + Math.random().toString(36).substring(2, 8).toUpperCase();

        // Persist structured ticket metadata in specialRequests (JSON)
        const ticketMetadata = JSON.stringify({
            planId: plan.id,
            requestId: request.id,
            hostId: plan.userId,
            joinerId: request.requesterId,
            ticketCode,
            expiresAt: plan.planDateTime.toISOString(),  // Ticket is valid until party starts
            paymentType: plan.paymentType,
            totalDeposit: Number(plan.depositAmount || 99) + 99, // host deposit + joiner deposit
            generatedAt: new Date().toISOString(),
        });

        const hostDeposit = Number(plan.depositAmount || 99);
        const joinerDeposit = 99.00; // Joiner commitment deposit is always ₹99
        const totalDeposits = hostDeposit + joinerDeposit;

        const booking = await Booking.create({
            userId: plan.userId,
            venueId: plan.venueId,
            bookingDate: bookingDate as any,
            startTime,
            numberOfGuests: 2,
            totalAmount: totalDeposits,
            depositAmount: totalDeposits,
            commissionAmount: 0,
            status: BookingStatus.CONFIRMED,
            paymentStatus: BookingPaymentStatus.PAID,
            isGroupBooking: false,
            goingMode: GoingMode.PARTY_REQUEST,
            ticketCode,
            specialRequests: ticketMetadata,
        }, { transaction });

        // Generate digital ticket in background
        setImmediate(async () => {
            try {
                await generateTicketForBookingHelper(booking.id);
            } catch (ticketErr) {
                logger.error(`Background ticket generation failed for matched party booking ${booking.id}:`, ticketErr);
            }
        });

        // Create Payment record for Host
        await Payment.create({
            transactionId: plan.hostRazorpayPaymentId || `TXN_HOST_${plan.id}`,
            bookingId: booking.id,
            userId: plan.userId,
            amount: plan.depositAmount ? Number(plan.depositAmount) : 99.00,
            currency: 'INR',
            paymentMethod: PaymentMethod.RAZORPAY,
            paymentGateway: 'razorpay',
            status: PaymentStatus.SUCCESSFUL,
            refundAmount: 0,
        }, { transaction });

        // Create Payment record for Joiner
        await Payment.create({
            transactionId: request.joinerRazorpayPaymentId || `TXN_JOINER_${request.id}`,
            bookingId: booking.id,
            userId: request.requesterId,
            amount: plan.paymentType === 'self_pay' ? 0.00 : 99.00,
            currency: 'INR',
            paymentMethod: PaymentMethod.RAZORPAY,
            paymentGateway: 'razorpay',
            status: PaymentStatus.SUCCESSFUL,
            refundAmount: 0,
        }, { transaction });

        // Emit party_plan_ticket_generated so the client can refresh the ticket screen
        // with the canonical ticketCode and expiresAt
        try {
            const { io } = require('../server');
            const ticketData = {
                bookingId: booking.id,
                ticketCode,
                planId: plan.id,
                requestId: request.id,
                expiresAt: plan.planDateTime.toISOString(),
            };
            io.to(`user_${plan.userId}`).emit('party_plan_ticket_generated', ticketData);
            io.to(`user_${request.requesterId}`).emit('party_plan_ticket_generated', ticketData);
        } catch (socketErr) {
            logger.warn('Socket emission failed for party_plan_ticket_generated:', socketErr);
        }

        // Unlock Chat!
        await autoOpenChat(plan.userId, request.requesterId, plan.id);

        logger.info(`Successfully created Booking ${booking.id} (ticket: ${ticketCode}) for plan ${plan.id}`);
    } catch (err) {
        logger.error('Error in createBookingAndPayments:', err);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// markRequestsAsWaiting — called on accept: puts all other PENDING requests
// into WAITING state so they can be re-activated if accepted user fails.
// ─────────────────────────────────────────────────────────────────────────────
async function markRequestsAsWaiting(plan: PartyPlan, acceptedRequestId: string, transaction?: Transaction) {
    try {
        const otherRequests = await PartyPlanRequest.findAll({
            where: {
                planId: plan.id,
                id: { [Op.ne]: acceptedRequestId },
                status: PartyPlanRequestStatus.PENDING,
            },
            transaction
        });
        for (const req of otherRequests) {
            await req.update({ status: PartyPlanRequestStatus.WAITING }, { transaction });
        }
        logger.info(`[markRequestsAsWaiting] Marked ${otherRequests.length} requests as WAITING for plan ${plan.id}`);
    } catch (err: any) {
        logger.error('Error in markRequestsAsWaiting:', err);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// rejectAndNotifyConfirmedWinners — called on MATCH_CONFIRMED: REJECT all
// remaining WAITING requests and notify them the plan is taken.
// ─────────────────────────────────────────────────────────────────────────────
async function rejectAndNotifyStaleRequests(plan: PartyPlan, acceptedRequestId: string, transaction?: Transaction) {
    try {
        const otherRequests = await PartyPlanRequest.findAll({
            where: {
                planId: plan.id,
                id: { [Op.ne]: acceptedRequestId },
                status: { [Op.in]: [
                    PartyPlanRequestStatus.PENDING,
                    PartyPlanRequestStatus.WAITING,
                    PartyPlanRequestStatus.PAYMENT_PENDING,
                ]},
            },
            transaction
        });

        let venueName = 'Venue';
        if (plan.venueId) {
            const venue = await Venue.findByPk(plan.venueId, { transaction });
            if (venue && venue.name) venueName = venue.name;
        }

        for (const req of otherRequests) {
            await req.update({ status: PartyPlanRequestStatus.REJECTED }, { transaction });

            // Single authoritative notification — NotificationService handles DB + socket + FCM
            setImmediate(async () => {
                try {
                    await NotificationService.dispatch({
                        recipientUserId: req.requesterId,
                        actorUserId: plan.userId,
                        eventType: 'plan_unavailable',
                        category: 'requests',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: '🔒 Plan Unavailable',
                        body: `The Party Plan at ${venueName} has been confirmed with another partner.`,
                        metadata: { partyPlanId: plan.id, requestId: req.id },
                        idempotencyKey: `plan_unavailable_${req.id}`,
                    });

                    const { io } = require('../server');
                    io.to(`user_${req.requesterId}`).emit('plan_unavailable', {
                        planId: plan.id, requestId: req.id,
                    });
                } catch (err: any) {
                    logger.warn(`Failed to notify stale request ${req.id}:`, err.message);
                }
            });
        }
    } catch (err: any) {
        logger.error('Error in rejectAndNotifyStaleRequests:', err);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// confirmMatch — atomic helper: both parties paid → MATCH_CONFIRMED
// Creates booking, opens chat, notifies both parties.
// Must be called AFTER transaction is committed or within one.
// ─────────────────────────────────────────────────────────────────────────────
async function confirmMatch(plan: PartyPlan, request: PartyPlanRequest, transaction: Transaction) {
    // 1. Update plan to MATCH_CONFIRMED (single source of truth)
    await plan.update({
        lifecycleStatus: PartyPlanLifecycleStatus.MATCH_CONFIRMED,
        status: PartyPlanStatus.INACTIVE,
        isLive: false,
        paymentStatus: 'Confirmed',
        hostPaymentStatus: PartyPlanPaymentStatus.PAID,
    }, { transaction });

    // 2. Mark request as ACCEPTED
    await request.update({
        status: PartyPlanRequestStatus.ACCEPTED,
        joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
    }, { transaction });

    // 3. Create booking and payment records
    await createBookingAndPayments(plan, request, transaction);

    // 4. Reject and notify all remaining WAITING/PENDING requests
    await rejectAndNotifyStaleRequests(plan, request.id, transaction);

    // 5. Post-commit: open chat (async, gated by lifecycleStatus)
    setImmediate(async () => {
        try {
            await autoOpenChat(plan.userId, request.requesterId, plan.id);
        } catch (err: any) {
            logger.error('confirmMatch: autoOpenChat failed:', err.message);
        }
    });

    // 6. Socket events
    setImmediate(async () => {
        try {
            const { io } = require('../server');
            io.to(`user_${plan.userId}`).emit('party_plan_match_success', { planId: plan.id, requestId: request.id });
            io.to(`user_${request.requesterId}`).emit('party_plan_match_success', { planId: plan.id, requestId: request.id });
            io.emit('party_plan_deleted', { planId: plan.id });
        } catch (socketErr) {
            logger.warn('confirmMatch: Socket emission failed:', socketErr);
        }
    });

    // 7. Notifications via NotificationService (authoritative, no duplicate socket calls)
    setImmediate(async () => {
        try {
            await NotificationService.dispatch({
                recipientUserId: plan.userId,
                actorUserId: request.requesterId,
                eventType: 'match_confirmed',
                category: 'events',
                entityType: 'party_plan',
                entityId: plan.id,
                title: '🎉 Booking Confirmed!',
                body: 'Both payments are complete. Your booking is confirmed!',
                metadata: { planId: plan.id, requestId: request.id },
                idempotencyKey: `match_confirmed_host_${plan.id}`,
            });
            await NotificationService.dispatch({
                recipientUserId: request.requesterId,
                actorUserId: plan.userId,
                eventType: 'match_confirmed',
                category: 'events',
                entityType: 'party_plan',
                entityId: plan.id,
                title: '🎉 Booking Confirmed!',
                body: 'Both payments are complete. Your booking is confirmed!',
                metadata: { planId: plan.id, requestId: request.id },
                idempotencyKey: `match_confirmed_joiner_${plan.id}`,
            });

            // FCM push
            const host = await User.findByPk(plan.userId);
            const joiner = await User.findByPk(request.requesterId);
            const tokens = [host?.fcmToken, joiner?.fcmToken].filter(t => t && t.trim() !== '') as string[];
            if (tokens.length > 0) {
                await sendMulticastPushNotification(tokens, {
                    title: '🎉 Booking Confirmed!',
                    body: 'Both payments are complete. Your booking is confirmed!',
                    data: { type: 'booking_confirmed', partyPlanId: plan.id },
                });
            }
        } catch (err: any) {
            logger.warn('confirmMatch: notification dispatch failed:', err.message);
        }
    });

    logger.info(`[confirmMatch] MATCH_CONFIRMED for plan ${plan.id}, request ${request.id}`);
}

// ─────────────────────────────────────────────────────────────────────────────
// reopenPlan — resets plan to POSTED and reactivates all WAITING requests.
// Called when payment expires, accepted user cancels, or system timeout.
// ─────────────────────────────────────────────────────────────────────────────
export async function reopenPlan(plan: PartyPlan, failedRequestId: string, failReason: 'payment_failed' | 'cancelled') {
    const transaction = await sequelize.transaction();
    try {
        // Mark the failed request
        const failedReq = await PartyPlanRequest.findByPk(failedRequestId, { transaction });
        if (failedReq) {
            await failedReq.update({
                status: failReason === 'payment_failed'
                    ? PartyPlanRequestStatus.PAYMENT_FAILED
                    : PartyPlanRequestStatus.CANCELLED,
            }, { transaction });
        }

        // Reactivate all WAITING requests on this plan
        await PartyPlanRequest.update(
            { status: PartyPlanRequestStatus.PENDING },
            {
                where: { planId: plan.id, status: PartyPlanRequestStatus.WAITING },
                transaction,
            }
        );

        const pendingCount = await PartyPlanRequest.count({
            where: { planId: plan.id, status: PartyPlanRequestStatus.PENDING },
            transaction,
        });

        // Reset plan lifecycle
        const newLifecycle = pendingCount > 0
            ? PartyPlanLifecycleStatus.REQUEST_RECEIVED
            : PartyPlanLifecycleStatus.POSTED;

        await plan.update({
            lifecycleStatus: newLifecycle,
            status: PartyPlanStatus.ACTIVE,
            isLive: plan.visibility !== 'private',
            matchedRequestId: null,
            acceptedAt: null,
            paymentDeadlineAt: null,
            paymentStatus: 'pending',
        }, { transaction });

        await transaction.commit();

        logger.info(`[reopenPlan] Plan ${plan.id} reopened. ${pendingCount} waiting requests reactivated. New lifecycle: ${newLifecycle}`);

        // Notify host and emit socket relisted event
        setImmediate(async () => {
            try {
                const { io } = require('../server');
                if (plan.visibility !== 'private') {
                    io.emit('party_plan_relisted', { planId: plan.id });
                } else {
                    io.to(`user_${plan.userId}`).emit('party_plan_relisted', { planId: plan.id });
                }

                await NotificationService.dispatch({
                    recipientUserId: plan.userId,
                    actorUserId: plan.userId,
                    eventType: 'plan_relisted',
                    category: 'events',
                    entityType: 'party_plan',
                    entityId: plan.id,
                    title: '⚡ Plan Live Again',
                    body: 'The payment session expired. Your Party Plan is live again and accepting requests.',
                    metadata: { planId: plan.id },
                    idempotencyKey: `plan_relisted_${plan.id}_${failedRequestId}`,
                });
            } catch (err: any) {
                logger.warn('reopenPlan: notification failed:', err.message);
            }
        });
    } catch (err: any) {
        await transaction.rollback();
        logger.error(`[reopenPlan] Error reopening plan ${plan.id}:`, err);
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
        const rawVisibility = String(req.body.visibility || req.body.privacyType || 'public').toLowerCase();
        let parsedVisibility = PartyPlanVisibility.PUBLIC;
        if (rawVisibility === 'private') {
            parsedVisibility = PartyPlanVisibility.PRIVATE;
        } else if (rawVisibility === 'both') {
            parsedVisibility = PartyPlanVisibility.BOTH;
        }

        const rawPaymentType = String(req.body.paymentType || 'split').toLowerCase();
        let parsedPaymentType = PartyPlanPaymentType.SPLIT;
        if (rawPaymentType === 'self_pay') {
            parsedPaymentType = PartyPlanPaymentType.SELF_PAY;
        }

        const { userId, venueId, message, planDateTime, mobileNumber, optionalMobileNumber, foodPreference, drinkPreference } = req.body;
        const selectedUsers = req.body.selectedUsers || req.body.selectedUserIds;
        const showProfilePhoto = req.body.showProfilePhoto !== undefined ? Boolean(req.body.showProfilePhoto) : true;
        const showHostName = req.body.showHostName !== undefined ? Boolean(req.body.showHostName) : true;
        const showVenueDetails = req.body.showVenueDetails !== undefined ? Boolean(req.body.showVenueDetails) : true;
        const showDateDetails = req.body.showDateDetails !== undefined ? Boolean(req.body.showDateDetails) : true;

        // ── Validate required fields ─────────────────────────────────────────
        const errors: Record<string, string> = {};
        if (!userId) errors.userId = 'userId is required';
        if (!venueId) errors.venueId = 'venueId is required';
        if (!message?.trim()) errors.message = 'Party message is required';
        if (!planDateTime) errors.planDateTime = 'planDateTime is required';

        if (parsedVisibility === PartyPlanVisibility.PRIVATE || parsedVisibility === PartyPlanVisibility.BOTH) {
            if (!Array.isArray(selectedUsers) || selectedUsers.length === 0) {
                errors.selectedUsers = `selectedUsers array is required and cannot be empty when visibility is ${parsedVisibility}`;
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

        const finalMobileNumber = mobileNumber?.trim() || user.phone?.trim() || '9999999999';

        // ── Verify venue exists and is active ─────────────────────────────────
        const venue = await Venue.findByPk(venueId, { attributes: ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone', 'coverChargeMale', 'coverChargeFemale', 'openingTime', 'closingTime', 'daysOpen', 'closedDates'] });
        if (!venue) {
            res.status(404).json({ success: false, message: 'Venue not found' });
            return;
        }

        // ── Validate Venue Timings and Holidays ────────────────────────────────
        const timingValidation = validateVenueTimingAndHolidays(venue, planDateTime);
        if (!timingValidation.isValid) {
            res.status(400).json({ success: false, message: timingValidation.reason });
            return;
        }

        // ── Check for 1 plan per day limit (Stranger Meet / Party Plan / Group Party) ──
        const bookingConflictMsg = await checkExistingBookingForDate(userId, partyDate);
        if (bookingConflictMsg) {
            res.status(400).json({ success: false, message: 'You already have a plan scheduled on this day.' });
            return;
        }

        // ── Generate Razorpay Order ───────────────────────────────────────────
        // Commitment deposit is always ₹99 per person, regardless of payment model.
        // SELF_PAY only means the Host covers the party expense at the venue — it does NOT
        // change the commitment deposit amount.
        const depositAmount = 99.00;
        const options = {
            amount: Math.round(depositAmount * 100), // in paise
            currency: 'INR',
            receipt: `pp_${Date.now()}`
        };
        let order: any = { id: `order_mock_${Date.now()}`, amount: options.amount, currency: options.currency };
        if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id' && process.env.RAZORPAY_KEY_ID !== 'rzp_test_123') {
            try {
                const resOrder = await razorpay.orders.create(options);
                if (resOrder) {
                    order = resOrder;
                }
            } catch (err: any) {
                logger.warn('Razorpay create order failed, using mock order. Error: ' + err.message);
            }
        }

        // ── Create the party plan under a transaction ──
        const partyPlan = await PlanEligibilityService.runAtomicCheckAndCreate(
            userId,
            'party_plan',
            partyDate,
            async (transaction) => {
                const plan = await PartyPlan.create({
                    userId,
                    venueId,
                    message: message.trim(),
                    planDateTime: partyDate,
                    mobileNumber: finalMobileNumber,
                    optionalMobileNumber: optionalMobileNumber?.trim(),
                    status: PartyPlanStatus.ACTIVE,
                    visibility: parsedVisibility,
                    selectedUsers: (parsedVisibility === PartyPlanVisibility.PRIVATE || parsedVisibility === PartyPlanVisibility.BOTH) ? selectedUsers : null,
                    depositAmount: depositAmount,
                    hostPaymentStatus: PartyPlanPaymentStatus.UNPAID,
                    hostRazorpayOrderId: order.id,
                    isLive: parsedVisibility === PartyPlanVisibility.PRIVATE ? false : true, // Private plans are not shown in public feed, both and public are
                    expiresAt: partyDate,
                    paymentStatus: 'pending',
                    foodPreference: foodPreference || 'Both',
                    drinkPreference: drinkPreference || 'Both',
                    paymentType: parsedPaymentType,
                    showProfilePhoto,
                    showHostName,
                    showVenueDetails,
                    showDateDetails,
                    lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
                }, { transaction });


                // Auto-generate accepted requests for invited users of private or both plan
                if ((parsedVisibility === PartyPlanVisibility.PRIVATE || parsedVisibility === PartyPlanVisibility.BOTH) && Array.isArray(selectedUsers) && selectedUsers.length > 0) {
                    for (const invitedUserId of selectedUsers) {
                        // Generate a joiner order ID
                        const joinerOptions = {
                            amount: Math.round(depositAmount * 100),
                            currency: 'INR',
                            receipt: `ppreq_${Date.now()}`
                        };
                        let joinerOrder: any = { id: `order_mock_${Date.now()}` };
                        if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id') {
                            try {
                                joinerOrder = await razorpay.orders.create(joinerOptions);
                            } catch (err: any) {
                                logger.warn('Razorpay create joiner order failed for invite, using mock. Error: ' + err.message);
                            }
                        }
                        
                        await PartyPlanRequest.create({
                            planId: plan.id,
                            requesterId: invitedUserId,
                            status: PartyPlanRequestStatus.PENDING,
                            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
                            joinerRazorpayOrderId: joinerOrder.id,
                            latLangCheckIn: false,
                        }, { transaction });
                    }
                }
                return plan;
            }
        );

        const responseData = {
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
            foodPreference: partyPlan.foodPreference,
            drinkPreference: partyPlan.drinkPreference,
            showProfilePhoto: partyPlan.showProfilePhoto,
            showHostName: partyPlan.showHostName,
            showVenueDetails: partyPlan.showVenueDetails,
            user: buildUserData({ creator: user } as any),
            venue: {
                id: venue.id,
                name: venue.name,
                addressLine1: venue.addressLine1,
                area: venue.area,
                city: venue.city,
                category: venue.category,
            },
        };

        // Emit socket event for real-time feed updates
        try {
            const { io } = require('../server');
            if (parsedVisibility === PartyPlanVisibility.PRIVATE) {
                io.to(`user_${userId}`).emit('party_plan_created', responseData);
                if (Array.isArray(selectedUsers)) {
                    for (const invitedUserId of selectedUsers) {
                        io.to(`user_${invitedUserId}`).emit('party_plan_created', responseData);
                    }
                }
            } else {
                io.emit('party_plan_created', responseData);
            }
        } catch (socketErr) {
            logger.warn('Socket emission failed for party_plan_created:', socketErr);
        }

        res.status(201).json({
            success: true,
            message: 'Party plan created successfully and is now live!',
            data: responseData,
            razorpayOrderId: order.id,
            amount: order.amount,
            currency: order.currency,
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123'
        });

        // ── Notifications: host plan-posted + invited users ───────────────
        setImmediate(async () => {
            try {
                const isPrivate = parsedVisibility === PartyPlanVisibility.PRIVATE || parsedVisibility === PartyPlanVisibility.BOTH;
                const venueName = venue.name;
                const notifData = {
                    type: 'party_plan_posted',
                    partyPlanId: partyPlan.id,
                    venueId: venueId,
                    hostId: userId,
                    venueName: venue.name,
                    depositAmount: partyPlan.depositAmount,
                    hostPaymentStatus: partyPlan.hostPaymentStatus,
                    hostRazorpayOrderId: partyPlan.hostRazorpayOrderId,
                };

                // 1. Authoritative DB notification for the host (plan posted)
                await NotificationService.dispatch({
                    recipientUserId: userId,
                    actorUserId: userId,
                    eventType: 'party_plan_posted',
                    category: 'events',
                    entityType: 'party_plan',
                    entityId: partyPlan.id,
                    title: '🎉 Party Plan Posted!',
                    body: `Your party plan at ${venueName} is now live and accepting requests!`,
                    idempotencyKey: `plan_posted_${partyPlan.id}`,
                    metadata: notifData,
                });

                // 2. Notify invited users for Private / Both
                if (isPrivate && Array.isArray(selectedUsers) && selectedUsers.length > 0) {
                    const invitedUsers = await User.findAll({
                        where: { id: { [Op.in]: selectedUsers } },
                        attributes: ['id', 'fcmToken', 'firstName'],
                    });
                    const hostName = `${user.firstName} ${user.lastName}`.trim();
                    for (const invitedUser of invitedUsers) {
                        await NotificationService.dispatch({
                            recipientUserId: invitedUser.id,
                            actorUserId: userId,
                            eventType: 'party_plan_invitation',
                            category: 'requests',
                            entityType: 'party_plan',
                            entityId: partyPlan.id,
                            title: '🎉 Party Plan Invitation',
                            body: `${hostName} invited you to join a party plan at ${venueName}!`,
                            idempotencyKey: `plan_invite_${partyPlan.id}_${invitedUser.id}`,
                            metadata: notifData,
                        });
                    }
                }
            } catch (pushErr: any) {
                logger.warn('Party plan creation notification failed:', pushErr.message);
            }
        });
    } catch (err: any) {
        logger.error('createPartyPlan error:', err);
        if (err.code && err.code.startsWith('PLAN_')) {
            res.status(409).json({
                success: false,
                code: err.code,
                message: err.message,
                lock: err.details
            });
            return;
        }
        res.status(500).json({ success: false, message: 'Failed to create party plan', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/host-pay
// Verify host payment for party plan deposit
// ─────────────────────────────────────────────────────────────────────────────
export const verifyHostPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        let { id } = req.params;
        if (id && id.startsWith('party_plan_timeline_')) {
            id = id.replace('party_plan_timeline_', '');
        }
        if (id && id.startsWith('pp_')) {
            id = id.replace('pp_', '');
        }
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        const isMockPayment = razorpay_signature === 'mock_signature' ||
                              (razorpay_order_id && (razorpay_order_id as string).startsWith('mock_')) ||
                              (razorpay_order_id && (razorpay_order_id as string).startsWith('order_mock_')) ||
                              (razorpay_order_id && (razorpay_order_id as string).startsWith('pay_direct_'));

        if (!isMockPayment && plan.hostRazorpayOrderId !== razorpay_order_id) {
            res.status(400).json({ success: false, message: 'Invalid order ID' });
            return;
        }

        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(razorpay_order_id + '|' + razorpay_payment_id);
        const generatedSignature = hmac.digest('hex');

        if (isMockPayment || generatedSignature === razorpay_signature || razorpay_signature === 'mock_signature') {
            // ── Idempotency guard: if host already paid, return success ────────
            if (plan.hostRazorpayPaymentId && plan.hostRazorpayPaymentId === razorpay_payment_id) {
                res.json({ success: true, message: 'Host payment already verified (idempotent).', data: plan });
                return;
            }

            const activeRequests = await PartyPlanRequest.findAll({
                where: {
                    planId: id,
                    status: {
                        [Op.in]: [PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.ACCEPTED]
                    }
                }
            });

            const hasActiveOrAcceptedRequest = activeRequests.length > 0;
            const updatedIsLive = hasActiveOrAcceptedRequest ? false : (plan.visibility !== PartyPlanVisibility.PRIVATE);

            await (plan as any).update({
                hostPaymentStatus: PartyPlanPaymentStatus.PAID,
                hostRazorpayPaymentId: razorpay_payment_id,
                isLive: updatedIsLive,
                paymentStatus: 'Awaiting Participant Payment',
            });

            // FCM push to host confirming payment
            setImmediate(async () => {
                try {
                    const host = await User.findByPk(plan.userId);
                    if (host && host.fcmToken) {
                        await sendMulticastPushNotification([host.fcmToken], {
                            title: '💳 Host Payment Successful',
                            body: `Your ₹${plan.depositAmount || 99} deposit payment was successfully verified.`,
                            data: { type: 'host_payment_successful', partyPlanId: plan.id },
                        });
                    }
                } catch (pushErr: any) {
                    logger.warn('Failed to send host payment success push:', pushErr.message);
                }
            });

            if (activeRequests.length > 0) {
                let matchSuccessful = false;
                for (const activeReq of activeRequests) {
                    if (activeReq.joinerPaymentStatus === PartyPlanJoinerPaymentStatus.PAID) {
                        // Joiner already paid! Both paid → trigger MATCH_CONFIRMED
                        matchSuccessful = true;
                        const innerTransaction = await sequelize.transaction();
                        try {
                            await plan.reload({ lock: innerTransaction.LOCK.UPDATE, transaction: innerTransaction });
                            await confirmMatch(plan, activeReq, innerTransaction);
                            await innerTransaction.commit();
                        } catch (matchErr: any) {
                            await innerTransaction.rollback();
                            logger.error('verifyHostPayment: confirmMatch failed:', matchErr);
                        }
                    } else {
                        // Host paid, joiner hasn't yet — reset joiner's 30-min window from NOW
                        const joinerDeadline = new Date(Date.now() + 30 * 60 * 1000);
                        await activeReq.update({ paymentTimeoutAt: joinerDeadline });

                        // Update plan lifecycle to HOST_PAYMENT_COMPLETED
                        await (plan as any).update({
                            lifecycleStatus: PartyPlanLifecycleStatus.HOST_PAYMENT_COMPLETED,
                            paymentDeadlineAt: joinerDeadline,
                        });

                        // Notify joiner their window starts now
                        setImmediate(async () => {
                            try {
                                await NotificationService.dispatch({
                                    recipientUserId: activeReq.requesterId,
                                    actorUserId: plan.userId,
                                    eventType: 'participant_payment_required',
                                    category: 'requests',
                                    entityType: 'party_plan',
                                    entityId: plan.id,
                                    title: '⚡ Action Required: Pay Deposit',
                                    body: 'The host has paid. Please pay your ₹99 deposit to confirm the booking!',
                                    metadata: { planId: plan.id, requestId: activeReq.id },
                                    idempotencyKey: `participant_payment_required_${activeReq.id}`,
                                });

                                const { io } = require('../server');
                                io.to(`user_${activeReq.requesterId}`).emit('party_plan_host_paid', {
                                    planId: plan.id, requestId: activeReq.id
                                });
                            } catch (err: any) {
                                logger.warn('Failed to notify joiner of host payment:', err.message);
                            }
                        });
                    }
                }

                if (matchSuccessful) {
                    res.json({ success: true, message: 'Both paid! Match Successful & Chat Opened 🎉', data: plan });
                } else {
                    res.json({ success: true, message: 'Host payment verified. Joiner 30-minute payment window starts now. ⏳', data: plan });
                }
                return;
            } else {
                // No active request — plan is live, host paid but no one accepted yet
                await (plan as any).update({
                    lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
                });
                res.json({ success: true, message: 'Payment verified. No active join requests currently.', data: plan });
                return;
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
        if (status === 'active') {
            where.planDateTime = { [Op.gte]: new Date() };
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

        const currentUserId = (requesterId as string) || (req as any).user?.id;

        const data = plans.map(p => {
            const isSecretDate = p.showDateDetails === false && !!currentUserId && currentUserId !== p.userId;
            return {
                id: p.id,
                status: p.status,
                visibility: p.visibility,
                selectedUsers: p.selectedUsers,
                message: p.message,
                planDateTime: isSecretDate ? 'Flexible Date & Time 🔒' : p.planDateTime,
                actualPlanDateTime: p.planDateTime,
                isSecretDate,
                createdAt: p.createdAt,
                hostPaymentStatus: p.hostPaymentStatus,
                hostRazorpayOrderId: p.hostRazorpayOrderId,
                isLive: p.isLive,
                depositAmount: p.depositAmount,
                mobileNumber: p.mobileNumber,
                optionalMobileNumber: p.optionalMobileNumber,
                expiresAt: p.expiresAt,
                paymentStatus: p.paymentStatus,
                foodPreference: p.foodPreference,
                drinkPreference: p.drinkPreference,
                showProfilePhoto: p.showProfilePhoto ?? true,
                showHostName: p.showHostName ?? true,
                showVenueDetails: p.showVenueDetails ?? true,
                showDateDetails: p.showDateDetails ?? true,
                user: buildUserData(p, currentUserId),
                venue: buildVenueData(p, currentUserId),
            };
        });

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
        if (status === 'active') {
            where.planDateTime = { [Op.gte]: new Date() };
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
            foodPreference: p.foodPreference,
            drinkPreference: p.drinkPreference,
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
        let { id } = req.params;
        if (id && id.startsWith('party_plan_timeline_')) {
            id = id.replace('party_plan_timeline_', '');
        }
        if (id && id.startsWith('pp_')) {
            id = id.replace('pp_', '');
        }

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
                foodPreference: plan.foodPreference,
                drinkPreference: plan.drinkPreference,
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
    const transaction = await sequelize.transaction();
    try {
        const { id } = req.params;
        const { userId, status } = req.body;

        if (!userId || !status) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'userId and status are required' });
            return;
        }

        const validStatuses = Object.values(PartyPlanStatus);
        if (!validStatuses.includes(status as PartyPlanStatus)) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
            return;
        }

        const plan = await PartyPlan.findByPk(id, { transaction });
        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        // Only the creator can update the status
        if (plan.userId !== userId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'You are not authorized to update this plan' });
            return;
        }

        // Acquire transactional row update lock on the party plan
        await plan.reload({ lock: transaction.LOCK.UPDATE, transaction });

        // Enforce state transitions
        if (plan.status === PartyPlanStatus.CANCELLED) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'Cannot update status of a cancelled plan.' });
            return;
        }

        if (status === PartyPlanStatus.CANCELLED) {
            await cancelPartyPlanInternal(plan, transaction);
        } else {
            // Block invalid reactivation (e.g. from inactive to active)
            if (plan.status === PartyPlanStatus.INACTIVE && status === PartyPlanStatus.ACTIVE) {
                await transaction.rollback();
                res.status(400).json({ success: false, message: 'Cannot reactivate a completed/matched party plan.' });
                return;
            }
            await (plan as any).update({ status }, { transaction });
        }

        await transaction.commit();

        if (status === PartyPlanStatus.CANCELLED) {
            try {
                const { io } = require('../server');
                io.emit('party_plan_deleted', { planId: plan.id });
            } catch (_) {}
        }

        res.json({
            success: true,
            message: `Plan status updated to "${status}"`,
            data: { id: plan.id, status },
        });
    } catch (err: any) {
        await transaction.rollback();
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
        await PlanEligibilityService.releaseLock(id);

        // Emit socket event to notify other clients to remove it from feed
        try {
            const { io } = require('../server');
            io.emit('party_plan_deleted', { planId: id });
        } catch (socketErr) {
            logger.warn('Socket emission failed for party_plan_deleted on destroy:', socketErr);
        }

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

        // Reject if target plan is inactive or cancelled
        if (plan.status === PartyPlanStatus.INACTIVE || plan.status === PartyPlanStatus.CANCELLED) {
            res.status(400).json({ success: false, message: 'This party plan is no longer active.' });
            return;
        }

        // Check if there is already a request on the plan that is accepted or in active payment_pending status
        const acceptedOrPendingReq = await PartyPlanRequest.findOne({
            where: {
                planId: plan.id,
                [Op.or]: [
                    { status: PartyPlanRequestStatus.ACCEPTED },
                    {
                        status: PartyPlanRequestStatus.PAYMENT_PENDING,
                        paymentTimeoutAt: { [Op.gt]: new Date() }
                    }
                ]
            }
        });
        if (acceptedOrPendingReq) {
            res.status(400).json({
                success: false,
                message: 'This party plan already has an accepted or processing request.'
            });
            return;
        }

        if (plan.userId === userId) {
            res.status(400).json({ success: false, message: 'You cannot request to join your own plan' });
            return;
        }

        if (plan.visibility === PartyPlanVisibility.PRIVATE) {
            const isInvited = plan.selectedUsers && plan.selectedUsers.includes(userId);
            if (!isInvited) {
                res.status(403).json({ success: false, message: 'You are not invited to this private party plan' });
                return;
            }
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

        // Notify host and requester via NotificationService
        setImmediate(async () => {
            try {
                const host = await User.findByPk(plan.userId);
                const requester = await User.findByPk(userId);
                if (host && requester) {
                    const venueName = (plan as any)?.venue?.name || 'Venue';
                    const requesterName = `${requester.firstName} ${requester.lastName}`.trim();

                    // Notify Host — use request-scoped idempotencyKey so it never overwrites the plan_posted notification
                    await NotificationService.dispatch({
                        recipientUserId: plan.userId,
                        actorUserId: userId,
                        eventType: 'party_plan_request_received',
                        category: 'requests',
                        entityType: 'party_plan_request',
                        entityId: newReq.id,
                        title: '📩 New Party Plan Request!',
                        body: `${requesterName} requested to join your Party Plan at ${venueName}.`,
                        idempotencyKey: `plan_request_received_${newReq.id}`,
                        metadata: {
                            partyPlanId: plan.id,
                            requestId: newReq.id,
                            requesterName,
                            venueName,
                        },
                    });

                    // Notify Requester — scoped idempotencyKey per request
                    await NotificationService.dispatch({
                        recipientUserId: userId,
                        actorUserId: plan.userId,
                        eventType: 'party_plan_request_sent',
                        category: 'requests',
                        entityType: 'party_plan_request',
                        entityId: newReq.id,
                        title: '✅ Request Sent',
                        body: `Your request to join ${host.firstName}'s Party Plan at ${venueName} was submitted successfully!`,
                        idempotencyKey: `plan_request_sent_${newReq.id}`,
                        metadata: {
                            partyPlanId: plan.id,
                            requestId: newReq.id,
                            venueName,
                        },
                    });
                }

                // Also notify admin room via Socket.IO
                const { io } = require('../server');
                if (io) {
                    io.to('admin_notifications').to('admin').emit('admin_notification_created', {
                        type: 'party_request',
                        title: '🎉 New Party Plan Request Posted!',
                        body: `${requester?.firstName || 'User'} requested to join party plan at ${(plan as any)?.venue?.name || 'Venue'}`,
                        path: '/party-requests',
                        entityId: newReq.id,
                        createdAt: new Date().toISOString(),
                    });
                }
            } catch (notifErr: any) {
                logger.warn('Failed to dispatch party plan request notifications:', notifErr.message);
            }
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
            reqData.isInvite = !!(plan.selectedUsers && plan.selectedUsers.includes(r.requesterId));
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
    const transaction = await sequelize.transaction();
    try {
        const { reqId } = req.params;
        const { userId } = req.body; // Host's userId

        const request = await PartyPlanRequest.findByPk(reqId, {
            include: [{ model: PartyPlan, as: 'plan' }],
            transaction
        });
        if (!request) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        const plan = (request as any).plan as PartyPlan;
        if (!plan || plan.userId !== userId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'Only the host can accept requests' });
            return;
        }

        // Acquire transactional row update lock on the party plan FIRST (prevents race conditions)
        await plan.reload({ lock: transaction.LOCK.UPDATE, transaction });

        // Lifecycle-based state validation (single source of truth)
        const acceptableStates = [
            PartyPlanLifecycleStatus.POSTED,
            PartyPlanLifecycleStatus.REQUEST_RECEIVED,
            PartyPlanLifecycleStatus.HOST_REVIEWING,
        ];
        if (!acceptableStates.includes(plan.lifecycleStatus)) {
            await transaction.rollback();
            res.status(400).json({
                success: false,
                message: `This plan cannot accept requests in its current state (${plan.lifecycleStatus}). It may already have an active payment session or be completed/cancelled.`
            });
            return;
        }

        if (plan.status === PartyPlanStatus.CANCELLED) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'This plan has been cancelled.' });
            return;
        }

        // Validate that the request being accepted is still PENDING or WAITING
        if (request.status !== PartyPlanRequestStatus.PENDING && request.status !== PartyPlanRequestStatus.WAITING) {
            await transaction.rollback();
            res.status(400).json({
                success: false,
                message: `Cannot accept this request — it is already in status: ${request.status}`
            });
            return;
        }

        const hostAlreadyPaid = plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;
        const paymentDeadline = new Date(Date.now() + 30 * 60 * 1000); // 30 min from now

        if (plan.paymentType === 'self_pay') {
            if (hostAlreadyPaid) {
                // Self-pay + host already paid = instant match. confirmMatch handles everything atomically.
                await confirmMatch(plan, request, transaction);
                await transaction.commit();

                res.json({ success: true, message: 'Request accepted & booking confirmed immediately (Self-Paid) 🎉', data: request });
                return;
            } else {
                // Self-pay but host hasn't paid yet — mark request accepted, put plan in PAYMENT_PENDING
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                }, { transaction });

                // Mark other requests as WAITING
                await markRequestsAsWaiting(plan, request.id, transaction);

                await plan.update({
                    lifecycleStatus: PartyPlanLifecycleStatus.GUEST_PAYMENT_COMPLETED,
                    isLive: false,
                    paymentStatus: 'Awaiting Host Payment',
                    matchedRequestId: request.id,
                    acceptedAt: new Date(),
                    paymentDeadlineAt: paymentDeadline,
                }, { transaction });

                await transaction.commit();

                // Notify joiner via NotificationService (authoritative — no duplicate inline socket call)
                setImmediate(async () => {
                    try {
                        await NotificationService.dispatch({
                            recipientUserId: request.requesterId,
                            actorUserId: plan.userId,
                            eventType: 'party_plan_request_accepted',
                            category: 'requests',
                            entityType: 'party_plan',
                            entityId: plan.id,
                            title: '✅ Request Accepted!',
                            body: 'Your join request was accepted. Waiting for host to complete their payment.',
                            metadata: { planId: plan.id, requestId: request.id },
                            idempotencyKey: `request_accepted_${request.id}`,
                        });
                        const { io } = require('../server');
                        io.to(`user_${request.requesterId}`).emit('party_plan_request_accepted', {
                            requestId: request.id,
                            planId: plan.id,
                            hostAlreadyPaid: false,
                            hostRazorpayOrderId: plan.hostRazorpayOrderId,
                        });
                    } catch (err: any) {
                        logger.warn('Failed to send request accepted notification:', err.message);
                    }
                });

                res.json({ success: true, message: 'Request accepted. Waiting for Host to pay deposit.', data: request });
                return;
            }
        }

        // ── Split-pay flow: generate Razorpay order for Joiner ─────────────────
        const joinerOptions = {
            amount: Math.round(plan.depositAmount * 100),
            currency: 'INR',
            receipt: `ppreq_${Date.now()}`
        };
        let joinerOrder: any = { id: `order_mock_${Date.now()}`, amount: joinerOptions.amount, currency: joinerOptions.currency };
        if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id' && process.env.RAZORPAY_KEY_ID !== 'rzp_test_123') {
            try {
                const resOrder = await razorpay.orders.create(joinerOptions);
                if (resOrder) joinerOrder = resOrder;
            } catch (err: any) {
                logger.warn('Razorpay joiner order failed, using mock: ' + err.message);
            }
        }

        // Only create a new host order if the host hasn't paid yet
        let hostOrder: any = null;
        if (!hostAlreadyPaid) {
            const hostOptions = {
                amount: Math.round(plan.depositAmount * 100),
                currency: 'INR',
                receipt: `pphost_${Date.now()}`
            };
            hostOrder = { id: `order_mock_${Date.now()}`, amount: hostOptions.amount, currency: hostOptions.currency };
            if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id' && process.env.RAZORPAY_KEY_ID !== 'rzp_test_123') {
                try {
                    const resOrder = await razorpay.orders.create(hostOptions);
                    if (resOrder) hostOrder = resOrder;
                } catch (err: any) {
                    logger.warn('Razorpay host order failed, using mock: ' + err.message);
                }
            }
        }

        // Mark request PAYMENT_PENDING
        await request.update({
            status: PartyPlanRequestStatus.PAYMENT_PENDING,
            joinerRazorpayOrderId: joinerOrder.id,
            paymentTimeoutAt: paymentDeadline,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
        }, { transaction });

        // Mark other PENDING requests as WAITING (they can be re-activated if this fails)
        await markRequestsAsWaiting(plan, request.id, transaction);

        // Reserve the plan with lifecycle state
        const newLifecycle = hostAlreadyPaid
            ? PartyPlanLifecycleStatus.HOST_PAYMENT_COMPLETED
            : PartyPlanLifecycleStatus.PAYMENT_PENDING;

        await plan.update({
            lifecycleStatus: newLifecycle,
            isLive: false,
            hostPaymentStatus: hostAlreadyPaid ? PartyPlanPaymentStatus.PAID : PartyPlanPaymentStatus.UNPAID,
            hostRazorpayOrderId: hostOrder ? hostOrder.id : plan.hostRazorpayOrderId,
            paymentStatus: hostAlreadyPaid ? 'Awaiting Participant Payment' : 'Awaiting Host Payment',
            matchedRequestId: request.id,
            acceptedAt: new Date(),
            paymentDeadlineAt: paymentDeadline,
        }, { transaction });

        await transaction.commit();

        // Post-commit socket & notification dispatch (non-blocking, authoritative via NotificationService)
        setImmediate(async () => {
            try {
                const { io } = require('../server');

                // Notify joiner of acceptance + payment details
                io.to(`user_${request.requesterId}`).emit('party_plan_request_accepted', {
                    requestId: request.id,
                    planId: plan.id,
                    hostAlreadyPaid,
                    hostRazorpayOrderId: hostOrder ? hostOrder.id : null,
                    hostAmount: hostOrder ? hostOrder.amount : null,
                    hostCurrency: hostOrder ? hostOrder.currency : null,
                    joinerRazorpayOrderId: joinerOrder.id,
                    joinerAmount: joinerOrder.amount,
                    joinerCurrency: joinerOrder.currency,
                });

                // Remove from global feeds (plan is reserved)
                io.emit('party_plan_deleted', { planId: plan.id });

                // Notify joiner via NotificationService (DB + socket + FCM in one call)
                await NotificationService.dispatch({
                    recipientUserId: request.requesterId,
                    actorUserId: plan.userId,
                    eventType: 'party_plan_request_accepted',
                    category: 'requests',
                    entityType: 'party_plan',
                    entityId: plan.id,
                    title: '✅ Request Accepted!',
                    body: hostAlreadyPaid
                        ? 'Host has paid. Please pay your deposit to confirm the booking!'
                        : 'Your join request was accepted by the host. Pay your deposit to confirm.',
                    metadata: { planId: plan.id, requestId: request.id },
                    idempotencyKey: `request_accepted_${request.id}`,
                });

                // If host hasn't paid — notify host to pay
                if (!hostAlreadyPaid) {
                    await NotificationService.dispatch({
                        recipientUserId: plan.userId,
                        actorUserId: request.requesterId,
                        eventType: 'host_payment_required',
                        category: 'requests',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: '⚡ Action Required: Pay Deposit',
                        body: 'You accepted a request. Please pay your ₹99 deposit to lock this match!',
                        metadata: { planId: plan.id, requestId: request.id },
                        idempotencyKey: `host_payment_required_${plan.id}_${request.id}`,
                    });
                }
            } catch (err: any) {
                logger.warn('acceptPartyPlanRequest: post-commit notifications failed:', err.message);
            }
        });

        res.json({
            success: true,
            message: hostAlreadyPaid
                ? 'Request accepted. Plan reserved. Joiner has 30 minutes to pay deposit.'
                : 'Request accepted. Plan reserved. Host must pay deposit first within 30 minutes.',
            data: {
                request,
                hostRazorpayOrderId: hostOrder ? hostOrder.id : null,
                hostAmount: hostOrder ? hostOrder.amount : null,
                hostCurrency: hostOrder ? hostOrder.currency : null,
                joinerRazorpayOrderId: joinerOrder.id,
                joinerAmount: joinerOrder.amount,
                joinerCurrency: joinerOrder.currency,
            },
        });
    } catch (err: any) {
        await transaction.rollback();
        logger.error('acceptPartyPlanRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to accept request', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/reject
// Reject request
// ─────────────────────────────────────────────────────────────────────────────
export const rejectPartyPlanRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { reqId } = req.params;
        const { userId } = req.body; // Host's userId

        const request = await PartyPlanRequest.findByPk(reqId, {
            include: [{ model: PartyPlan, as: 'plan' }]
        });
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        const plan = (request as any).plan as PartyPlan;
        if (!plan || plan.userId !== userId) {
            res.status(403).json({ success: false, message: 'Only the host can reject requests' });
            return;
        }

        if (request.status === PartyPlanRequestStatus.REJECTED || request.status === PartyPlanRequestStatus.CANCELLED) {
            res.status(400).json({ success: false, message: 'Request is already rejected or cancelled.' });
            return;
        }

        const isMatchedRequest = plan.matchedRequestId === request.id;

        if (isMatchedRequest) {
            // Reopen the plan & reactivate WAITING requests (reopenPlan handles transaction & states)
            await reopenPlan(plan, request.id, 'cancelled');
        } else {
            // Just reject this specific request
            const transaction = await sequelize.transaction();
            try {
                await request.update({ status: PartyPlanRequestStatus.REJECTED }, { transaction });
                await transaction.commit();
            } catch (err) {
                await transaction.rollback();
                throw err;
            }
        }

        // Authoritative notification to the requester
        setImmediate(async () => {
            try {
                let venueName = 'Venue';
                if (plan.venueId) {
                    const venue = await Venue.findByPk(plan.venueId);
                    if (venue) venueName = venue.name;
                }

                await NotificationService.dispatch({
                    recipientUserId: request.requesterId,
                    actorUserId: plan.userId,
                    eventType: 'party_plan_request_rejected',
                    category: 'requests',
                    entityType: 'party_plan_request',
                    entityId: request.id,
                    title: '🔴 Request Declined',
                    body: `Your request to join the Party Plan at ${venueName} was declined.`,
                    metadata: { planId: plan.id, requestId: request.id },
                    idempotencyKey: `request_rejected_${request.id}`,
                });

                const { io } = require('../server');
                io.to(`user_${request.requesterId}`).emit('plan_unavailable', {
                    planId: plan.id, requestId: request.id,
                });
            } catch (err: any) {
                logger.warn('Failed to send rejection notifications:', err.message);
            }
        });

        res.json({ success: true, message: 'Request rejected successfully' });
    } catch (err: any) {
        logger.error('rejectPartyPlanRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to reject request', error: err.message });
    }
};


// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/joiner-pay
// Verify joiner payment
// ─────────────────────────────────────────────────────────────────────────────
export const verifyJoinerPayment = async (req: Request, res: Response): Promise<void> => {
    const transaction = await sequelize.transaction();
    try {
        const { reqId } = req.params;
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        const request = await PartyPlanRequest.findByPk(reqId, {
            include: [{ model: PartyPlan, as: 'plan' }],
            transaction
        });
        if (!request) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        const isMockOrWalletOrder =
            !razorpay_order_id ||
            razorpay_order_id.startsWith('order_mock_') ||
            razorpay_order_id.startsWith('mock_order_') ||
            razorpay_order_id.startsWith('pay_direct_') ||
            razorpay_order_id === 'order_mock_wallet' ||
            razorpay_order_id === 'order_mock_hybrid';

        if (request.joinerRazorpayOrderId && request.joinerRazorpayOrderId !== razorpay_order_id && !isMockOrWalletOrder) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'Invalid order ID' });
            return;
        }

        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(razorpay_order_id + '|' + razorpay_payment_id);
        const generatedSignature = hmac.digest('hex');

        if (generatedSignature === razorpay_signature || razorpay_signature === 'mock_signature') {
            const plan = (request as any).plan as PartyPlan;
            if (!plan) {
                await transaction.rollback();
                res.status(404).json({ success: false, message: 'Party plan not found' });
                return;
            }

            // ── Idempotency guard: if joiner already paid, return success ────────
            if (request.joinerRazorpayPaymentId && request.joinerRazorpayPaymentId === razorpay_payment_id) {
                await transaction.rollback();
                res.json({ success: true, message: 'Joiner payment already verified (idempotent).', data: request });
                return;
            }

            // Acquire transactional row update lock on the party plan FIRST
            await plan.reload({ lock: transaction.LOCK.UPDATE, transaction });

            // Lifecycle guard — plan must be in a payment-accepting state
            const validPaymentStates = [
                PartyPlanLifecycleStatus.POSTED,
                PartyPlanLifecycleStatus.PAYMENT_PENDING,
                PartyPlanLifecycleStatus.HOST_PAYMENT_COMPLETED,
                PartyPlanLifecycleStatus.GUEST_PAYMENT_COMPLETED,
            ];
            if (!validPaymentStates.includes(plan.lifecycleStatus) && plan.status !== PartyPlanStatus.ACTIVE) {
                await transaction.rollback();
                res.status(400).json({ success: false, message: `This plan is not in a payment-accepting state (${plan.lifecycleStatus}).` });
                return;
            }

            // Record joiner payment
            await request.update({
                joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                joinerRazorpayPaymentId: razorpay_payment_id,
            }, { transaction });

            const hostPaid = plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;

            if (hostPaid) {
                // Both parties have paid → MATCH_CONFIRMED
                await confirmMatch(plan, request, transaction);
                await transaction.commit();

                res.json({ success: true, message: 'Both paid! Match Successful & Chat Opened 🎉', data: request });
            } else {
                // Joiner paid but host hasn't yet — update lifecycle to GUEST_PAYMENT_COMPLETED
                await plan.update({
                    lifecycleStatus: PartyPlanLifecycleStatus.GUEST_PAYMENT_COMPLETED,
                }, { transaction });

                await transaction.commit();

                // Notify host that joiner has paid and they need to pay
                setImmediate(async () => {
                    try {
                        await NotificationService.dispatch({
                            recipientUserId: plan.userId,
                            actorUserId: request.requesterId,
                            eventType: 'joiner_payment_completed',
                            category: 'requests',
                            entityType: 'party_plan',
                            entityId: plan.id,
                            title: '💳 Participant Paid!',
                            body: 'Your party partner has paid their deposit. Please pay yours to confirm the booking!',
                            metadata: { planId: plan.id, requestId: request.id },
                            idempotencyKey: `joiner_paid_${request.id}`,
                        });

                        const { io } = require('../server');
                        io.to(`user_${plan.userId}`).emit('party_plan_joiner_paid', { planId: plan.id, requestId: request.id });
                    } catch (err: any) {
                        logger.warn('Failed to notify host of joiner payment:', err.message);
                    }
                });

                res.json({ success: true, message: 'Payment verified. Waiting for host payment. ⏳', data: request });
            }
        } else {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'Invalid payment signature' });
        }
    } catch (err: any) {
        await transaction.rollback();
        logger.error('verifyJoinerPayment error:', err);
        res.status(500).json({ success: false, message: 'Failed to verify payment', error: err.message });
    }
};


export const confirmSelfPaidJoin = async (req: Request, res: Response): Promise<void> => {
    const transaction = await sequelize.transaction();
    try {
        const { reqId } = req.params;
        const { userId } = req.body;

        const request = await PartyPlanRequest.findByPk(reqId, {
            include: [{ model: PartyPlan, as: 'plan' }],
            transaction
        });
        if (!request) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        if (request.requesterId !== userId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'Only the requesting/invited user can confirm this request' });
            return;
        }

        const plan = (request as any).plan as PartyPlan;
        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (plan.paymentType !== 'self_pay') {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'This plan is not self-paid. Payment is required.' });
            return;
        }

        // Acquire transactional row update lock on the party plan
        await plan.reload({ lock: transaction.LOCK.UPDATE, transaction });

        // Enforce state transition checks: plan status must be active
        if (plan.status !== PartyPlanStatus.ACTIVE) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'This plan is not active or has already been completed/cancelled.' });
            return;
        }

        const hostPaid = plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;

        if (hostPaid) {
            await request.update({
                status: PartyPlanRequestStatus.ACCEPTED,
                joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
            }, { transaction });

            await plan.update({
                status: PartyPlanStatus.INACTIVE,
                isLive: false,
                paymentStatus: 'Confirmed',
            }, { transaction });

            await createBookingAndPayments(plan, request, transaction);

            // Reject and notify all other requests now that match is fully confirmed
            await rejectAndNotifyStaleRequests(plan, request.id, transaction);

            await transaction.commit();

            setImmediate(async () => {
                try {
                    const joiner = await User.findByPk(request.requesterId);
                    const host = await User.findByPk(plan.userId);
                    const tokens = [host?.fcmToken, joiner?.fcmToken].filter(t => t && t.trim() !== '') as string[];
                    if (tokens.length > 0) {
                        await sendMulticastPushNotification(tokens, {
                            title: '🎉 Booking Confirmed!',
                            body: 'Your booking has been confirmed! (Paid by the Host)',
                            data: {
                                type: 'booking_confirmed',
                                partyPlanId: plan.id,
                            },
                        });
                    }
                } catch (pushErr: any) {
                    logger.warn('Failed to send booking confirmed push notifications:', pushErr.message);
                }
            });

            try {
                const { io } = require('../server');
                io.to(`user_${plan.userId}`).emit('party_plan_match_success', { planId: plan.id, requestId: request.id });
                io.to(`user_${request.requesterId}`).emit('party_plan_match_success', { planId: plan.id, requestId: request.id });
                io.emit('party_plan_deleted', { planId: plan.id });
            } catch (socketErr) {
                logger.warn('Socket emission failed for party_plan_match_success:', socketErr);
            }

            res.json({ success: true, message: 'Joined party plan successfully! (Paid by Host) 🎉', data: request });
        } else {
            await request.update({
                status: PartyPlanRequestStatus.ACCEPTED,
                joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
            }, { transaction });

            await plan.update({
                paymentStatus: 'Awaiting Host Payment',
            }, { transaction });

            await transaction.commit();

            try {
                const { io } = require('../server');
                io.to(`user_${plan.userId}`).emit('party_plan_joiner_paid', { planId: plan.id, requestId: request.id });
            } catch (socketErr) {
                logger.warn('Socket emission failed for party_plan_joiner_paid:', socketErr);
            }

            res.json({ success: true, message: 'Join confirmed. Waiting for host to complete their payment. ⏳', data: request });
        }
    } catch (err: any) {
        await transaction.rollback();
        logger.error('confirmSelfPaidJoin error:', err);
        res.status(500).json({ success: false, message: 'Failed to confirm join', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/accept-invite
// Accept an invite to a party plan
// ─────────────────────────────────────────────────────────────────────────────
export const acceptPartyPlanInvite = async (req: Request, res: Response): Promise<void> => {
    const transaction = await sequelize.transaction();
    try {
        const { reqId } = req.params;
        const { userId } = req.body;

        const request = await PartyPlanRequest.findByPk(reqId, {
            include: [{ model: PartyPlan, as: 'plan' }],
            transaction
        });
        if (!request) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        if (request.requesterId !== userId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'Only the invited user can accept this invite' });
            return;
        }

        const plan = (request as any).plan as PartyPlan;
        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        // Acquire transactional row update lock on the party plan
        await plan.reload({ lock: transaction.LOCK.UPDATE, transaction });

        // Enforce state transition checks: plan status must be active
        if (plan.status !== PartyPlanStatus.ACTIVE) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'This plan is not active or has already been completed/cancelled.' });
            return;
        }

        // Check if there is already an active unpaid request on this plan (another user took it)
        const activeReq = await PartyPlanRequest.findOne({
            where: {
                planId: plan.id,
                id: { [Op.ne]: request.id },
                status: PartyPlanRequestStatus.PAYMENT_PENDING,
                paymentTimeoutAt: { [Op.gt]: new Date() }
            },
            transaction
        });
        if (activeReq) {
            await transaction.rollback();
            res.status(400).json({
                success: false,
                message: 'This plan is currently reserved by another user. Try again later.'
            });
            return;
        }

        const hostPaid = plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;

        if (plan.paymentType === 'self_pay') {
            if (hostPaid) {
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                }, { transaction });
                await plan.update({
                    status: PartyPlanStatus.INACTIVE,
                    isLive: false,
                    paymentStatus: 'Confirmed',
                }, { transaction });
                await createBookingAndPayments(plan, request, transaction);

                // Reject and notify all other requests now that match is fully confirmed
                await rejectAndNotifyStaleRequests(plan, request.id, transaction);

                await transaction.commit();

                // Send push notification & socket events
                setImmediate(async () => {
                    try {
                        const joiner = await User.findByPk(request.requesterId);
                        const host = await User.findByPk(plan.userId);
                        const tokens = [host?.fcmToken, joiner?.fcmToken].filter(t => t && t.trim() !== '') as string[];
                        if (tokens.length > 0) {
                            const { sendMulticastPushNotification } = require('../services/fcmService');
                            await sendMulticastPushNotification(tokens, {
                                title: '🎉 Booking Confirmed!',
                                body: 'Your booking has been confirmed! (Paid by the Host)',
                                data: {
                                    type: 'booking_confirmed',
                                    partyPlanId: plan.id,
                                },
                            });
                        }
                    } catch (pushErr: any) {
                        logger.warn('Failed to send booking confirmed push notifications:', pushErr.message);
                    }
                });

                try {
                    const host = await User.findByPk(plan.userId);
                    const joiner = await User.findByPk(request.requesterId);
                    if (host && joiner) {
                        const { io } = require('../server');
                        const venueName = (plan as any)?.venue?.name || 'Club';
                        const joinerName = `${joiner.firstName} ${joiner.lastName}`;
                        
                        io.to(`user_${plan.userId}`).emit('party_plan_match_success', { planId: plan.id, requestId: request.id });
                        io.to(`user_${request.requesterId}`).emit('party_plan_match_success', { planId: plan.id, requestId: request.id });
                        io.emit('party_plan_deleted', { planId: plan.id });

                        await NotificationService.dispatch({
                            recipientUserId: plan.userId,
                            actorUserId: joiner.id,
                            eventType: 'invite_accepted',
                            category: 'requests',
                            entityType: 'party_plan',
                            entityId: plan.id,
                            title: 'Invite Accepted',
                            body: `${joinerName} accepted and confirmed your private invite to the Party Plan at ${venueName}.`,
                            metadata: { planId: plan.id, requestId: request.id },
                            idempotencyKey: `invite_accepted_${request.id}`,
                        });
                    }
                } catch (socketErr) {
                    logger.warn('Socket emission failed for acceptPartyPlanInvite:', socketErr);
                }

                res.json({ success: true, message: 'Joined party plan successfully! (Paid by Host) 🎉', data: request });
            } else {
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                }, { transaction });
                await plan.update({
                    paymentStatus: 'Awaiting Host Payment',
                    isLive: false,
                }, { transaction });

                await transaction.commit();

                // Send push notification & socket events
                setImmediate(async () => {
                    try {
                        const host = await User.findByPk(plan.userId);
                        const joiner = await User.findByPk(request.requesterId);
                        if (host && host.fcmToken && joiner) {
                            const { sendPushNotification } = require('../services/fcmService');
                            const joinerName = `${joiner.firstName} ${joiner.lastName}`;
                            await sendPushNotification(host.fcmToken, {
                                title: 'Invite Accepted ⏳',
                                body: `${joinerName} accepted your invite. Please complete your deposit payment.`,
                                data: {
                                    type: 'invite_accepted_awaiting_host_payment',
                                    partyPlanId: plan.id,
                                }
                            });
                        }
                    } catch (pushErr: any) {
                        logger.warn('Failed to send invite accepted push:', pushErr.message);
                    }
                });

                try {
                    const host = await User.findByPk(plan.userId);
                    const joiner = await User.findByPk(request.requesterId);
                    if (host && joiner) {
                        const { io } = require('../server');
                        const venueName = (plan as any)?.venue?.name || 'Club';
                        const joinerName = `${joiner.firstName} ${joiner.lastName}`;
                        
                        io.emit('party_plan_deleted', { planId: plan.id });

                        await NotificationService.dispatch({
                            recipientUserId: plan.userId,
                            actorUserId: joiner.id,
                            eventType: 'invite_accepted',
                            category: 'requests',
                            entityType: 'party_plan',
                            entityId: plan.id,
                            title: 'Invite Accepted',
                            body: `${joinerName} accepted your private invite to the Party Plan at ${venueName}. Please complete your payment.`,
                            metadata: { planId: plan.id, requestId: request.id },
                            idempotencyKey: `invite_accepted_awaiting_host_${request.id}`,
                        });
                    }
                } catch (socketErr) {
                    logger.warn('Socket emission failed for acceptPartyPlanInvite:', socketErr);
                }

                res.json({ success: true, message: 'Join confirmed. Waiting for host to complete their payment. ⏳', data: request });
            }
        } else {
            // SPLIT PAY
            const timeout = new Date();
            timeout.setMinutes(timeout.getMinutes() + 30);

            await request.update({
                status: PartyPlanRequestStatus.PAYMENT_PENDING,
                paymentTimeoutAt: timeout,
            }, { transaction });

            await plan.update({
                isLive: false, // reserved
            }, { transaction });

            await transaction.commit();

            try {
                const host = await User.findByPk(plan.userId);
                const joiner = await User.findByPk(request.requesterId);
                if (host && joiner) {
                    const { io } = require('../server');
                    const venueName = (plan as any)?.venue?.name || 'Club';
                    const joinerName = `${joiner.firstName} ${joiner.lastName}`;
                    
                    io.to(`user_${request.requesterId}`).emit('party_plan_request_accepted', {
                        requestId: request.id,
                        planId: plan.id,
                        hostAlreadyPaid: hostPaid,
                        hostRazorpayOrderId: plan.hostRazorpayOrderId,
                        hostAmount: Math.round(plan.depositAmount * 100),
                        hostCurrency: 'INR',
                        joinerRazorpayOrderId: request.joinerRazorpayOrderId,
                        joinerAmount: Math.round(plan.depositAmount * 100),
                        joinerCurrency: 'INR',
                    });

                    io.emit('party_plan_deleted', { planId: plan.id });

                        await NotificationService.dispatch({
                            recipientUserId: plan.userId,
                            actorUserId: joiner.id,
                            eventType: 'invite_accepted',
                            category: 'requests',
                            entityType: 'party_plan',
                            entityId: plan.id,
                            title: 'Invite Accepted',
                            body: `${joinerName} accepted your private invite to the Party Plan at ${venueName}. Awaiting participant payment.`,
                            metadata: { planId: plan.id, requestId: request.id },
                            idempotencyKey: `invite_accepted_awaiting_joiner_${request.id}`,
                        });
                    }
            } catch (socketErr) {
                logger.warn('Socket emission failed for acceptPartyPlanInvite:', socketErr);
            }

            res.json({ success: true, message: 'Invite accepted! You have 30 minutes to pay the deposit.', data: request });
        }
    } catch (err: any) {
        await transaction.rollback();
        logger.error('acceptPartyPlanInvite error:', err);
        res.status(500).json({ success: false, message: 'Failed to accept invite', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
async function cancelPartyPlanInternal(plan: PartyPlan, transaction: Transaction) {
    const WalletTransaction = (await import('../models/WalletTransaction')).default;
    const { WalletTransactionType } = await import('../models/WalletTransaction');

    const wasHostPaid = plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;
    
    // 1. Update plan status
    await plan.update({
        status: PartyPlanStatus.CANCELLED,
        isLive: false,
        paymentStatus: plan.paymentStatus === 'Confirmed' ? 'Refunded' : plan.paymentStatus,
        hostPaymentStatus: wasHostPaid ? PartyPlanPaymentStatus.REFUNDED : plan.hostPaymentStatus,
    }, { transaction });

    // 1.5 Refund Host if paid
    if (wasHostPaid) {
        const hostUser = await User.findByPk(plan.userId, { transaction });
        if (hostUser) {
            const hOld = Number(hostUser.walletBalance || 0);
            // Refund exactly what the host paid: their commitment deposit (always ₹99)
            const hDeposit = Number(plan.depositAmount) || 99.00;
            const hNew = hOld + hDeposit;
            await hostUser.update({ walletBalance: hNew }, { transaction });
            await WalletTransaction.logTransaction({
                userId: hostUser.id,
                partyPlanId: plan.id,
                amount: hDeposit,
                openingBalance: hOld,
                closingBalance: hNew,
                transactionType: WalletTransactionType.REFUND,
                reference: `REFUND_HOST_CANCEL_${plan.id}`,
            }, transaction);
        }
    }

    // 2. Release lock in Time Lock Engine
    await PlanEligibilityService.releaseLock(plan.id, { transaction });

    // 3. Find and update all requests
    const requests = await PartyPlanRequest.findAll({
        where: {
            planId: plan.id,
            status: { [Op.in]: [PartyPlanRequestStatus.PENDING, PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.ACCEPTED] }
        },
        transaction
    });

    for (const req of requests) {
        const wasJoinerPaid = req.joinerPaymentStatus === PartyPlanJoinerPaymentStatus.PAID;

        await req.update({
            status: PartyPlanRequestStatus.CANCELLED,
            joinerPaymentStatus: wasJoinerPaid ? PartyPlanJoinerPaymentStatus.REFUNDED : req.joinerPaymentStatus
        }, { transaction });

        // Refund Joiner if paid
        if (wasJoinerPaid) {
            const joinerUser = await User.findByPk(req.requesterId, { transaction });
            if (joinerUser) {
                const jOld = Number(joinerUser.walletBalance || 0);
                // Joiner commitment deposit is always ₹99 regardless of payment model.
                // SELF_PAY only means the host covers the venue expense — joiner still paid their deposit.
                const jDeposit = 99.00;
                if (jDeposit > 0) {
                    const jNew = jOld + jDeposit;
                    await joinerUser.update({ walletBalance: jNew }, { transaction });
                    await WalletTransaction.logTransaction({
                        userId: joinerUser.id,
                        partyPlanId: plan.id,
                        amount: jDeposit,
                        openingBalance: jOld,
                        closingBalance: jNew,
                        transactionType: WalletTransactionType.REFUND,
                        reference: `REFUND_JOINER_CANCEL_${req.id}`,
                    }, transaction);
                }
            }
        }

        // Notify joiners
        try {
            const { io } = require('../server');
            io.to(`user_${req.requesterId}`).emit('plan_unavailable', {
                planId: plan.id,
                requestId: req.id,
            });
            io.to(`user_${req.requesterId}`).emit('notification_created', {
                id: `ppr_cancelled_${req.id}`,
                title: 'Party Plan Cancelled',
                body: 'The Party Plan has been cancelled by the host. Any deposits paid will be refunded.',
                createdAt: new Date().toISOString(),
                read: false,
                type: 'plan_unavailable',
            });
        } catch (_) {}

        setImmediate(async () => {
            try {
                const joiner = await User.findByPk(req.requesterId);
                if (joiner && joiner.fcmToken) {
                    await sendMulticastPushNotification([joiner.fcmToken], {
                        title: 'Party Plan Cancelled',
                        body: 'The Party Plan has been cancelled by the host. Any deposits paid will be refunded.',
                        data: {
                            type: 'plan_unavailable',
                            partyPlanId: plan.id,
                            requestId: req.id,
                        },
                    });
                }
            } catch (_) {}
        });
    }

    // 4. Find associated Booking (goingMode = GoingMode.PARTY_REQUEST, matching host userId, venueId, planDateTime)
    const booking = await Booking.findOne({
        where: {
            goingMode: GoingMode.PARTY_REQUEST,
            userId: plan.userId,
            venueId: plan.venueId,
            bookingDate: plan.planDateTime,
            status: { [Op.ne]: BookingStatus.CANCELLED }
        },
        transaction
    });

    if (booking) {
        await booking.update({
            status: BookingStatus.CANCELLED,
            paymentStatus: BookingPaymentStatus.REFUNDED
        }, { transaction });

        // Update all related Payment records to refunded
        const payments = await Payment.findAll({
            where: {
                bookingId: booking.id,
                status: PaymentStatus.SUCCESSFUL
            },
            transaction
        });

        for (const payment of payments) {
            await payment.update({
                status: PaymentStatus.REFUNDED,
                refundAmount: payment.amount,
                refundedAt: new Date()
            }, { transaction });
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/cancel
// Cancel a party plan (by host)
// ─────────────────────────────────────────────────────────────────────────────
export const cancelPartyPlan = async (req: Request, res: Response): Promise<void> => {
    const transaction = await sequelize.transaction();
    try {
        const { id } = req.params;
        const { userId } = req.body;

        const plan = await PartyPlan.findByPk(id, { transaction });
        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (plan.userId !== userId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'Only the host can cancel the plan' });
            return;
        }

        // Row lock
        await plan.reload({ lock: transaction.LOCK.UPDATE, transaction });

        // Check if already cancelled
        if (plan.status === PartyPlanStatus.CANCELLED) {
            await transaction.rollback();
            res.json({ success: true, message: 'Party plan is already cancelled' });
            return;
        }

        await cancelPartyPlanInternal(plan, transaction);

        await transaction.commit();

        // Emit socket event to notify other clients to remove it from feed
        try {
            const { io } = require('../server');
            io.emit('party_plan_deleted', { planId: plan.id });
        } catch (socketErr) {
            logger.warn('Socket emission failed for party_plan_deleted on cancel:', socketErr);
        }

        res.json({ success: true, message: 'Party plan cancelled' });
    } catch (err: any) {
        await transaction.rollback();
        logger.error('cancelPartyPlan error:', err);
        res.status(500).json({ success: false, message: 'Failed to cancel plan', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/requests/:reqId/ticket
// Fetch a complete ticket payload (plan + both users with photos + ticketCode)
// ─────────────────────────────────────────────────────────────────────────────
const TICKET_USER_ATTRS = ['id', 'firstName', 'lastName', 'email', 'profileImageUrl'];

export const getPartyPlanTicket = async (req: Request, res: Response): Promise<void> => {
    try {
        const { reqId } = req.params;

        const request = await PartyPlanRequest.findByPk(reqId, {
            include: [
                {
                    model: PartyPlan,
                    as: 'plan',
                    include: [
                        {
                            model: User,
                            as: 'creator',
                            attributes: TICKET_USER_ATTRS,
                            include: [
                                { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                                { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
                            ],
                        },
                        {
                            model: Venue,
                            as: 'venue',
                            attributes: ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone', 'coverChargeMale', 'coverChargeFemale', 'latitude', 'longitude'],
                            include: [
                                {
                                    model: VenueImage,
                                    as: 'images',
                                    attributes: ['id', 'filePath', 'imageType', 'isPrimary'],
                                    where: { isPrimary: true },
                                    required: false,
                                }
                            ],
                        },
                    ] as any,
                },
                {
                    model: User,
                    as: 'requester',
                    attributes: TICKET_USER_ATTRS,
                    include: [
                        { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                        { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
                    ],
                },
            ],
        });

        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        const plan = (request as any).plan as PartyPlan;
        if (!plan) {
            res.status(404).json({ success: false, message: 'Plan not found for this request' });
            return;
        }

        // Helper to extract photo URL from a user record with embedded photos array
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

        const hostRaw = (plan as any).creator;
        const joinerRaw = (request as any).requester;

        const hostData = hostRaw ? {
            id: hostRaw.id,
            firstName: hostRaw.firstName,
            lastName: hostRaw.lastName,
            username: hostRaw.profile?.displayName || (hostRaw.firstName ? `${hostRaw.firstName}_${hostRaw.lastName}`.toLowerCase() : 'user'),
            profilePhotoUrl: resolveUserPhoto(hostRaw),
            subscriptionTier: 'FREE',
            bio: hostRaw.profile?.bio ?? null,
            city: hostRaw.profile?.city ?? null,
        } : null;

        const joinerData = joinerRaw ? {
            id: joinerRaw.id,
            firstName: joinerRaw.firstName,
            lastName: joinerRaw.lastName,
            username: joinerRaw.profile?.displayName || (joinerRaw.firstName ? `${joinerRaw.firstName}_${joinerRaw.lastName}`.toLowerCase() : 'user'),
            profilePhotoUrl: resolveUserPhoto(joinerRaw),
            subscriptionTier: 'FREE',
            bio: joinerRaw.profile?.bio ?? null,
            city: joinerRaw.profile?.city ?? null,
        } : null;

        // Fetch the booking record to retrieve the ticketCode and ticketUrl
        let booking = await Booking.findOne({
            where: {
                goingMode: GoingMode.PARTY_REQUEST,
                userId: plan.userId,
                venueId: plan.venueId,
                specialRequests: { [Op.like]: `%"planId":"${plan.id}"%` },
            },
            order: [['createdAt', 'DESC']],
            attributes: ['id', 'ticketCode', 'ticketUrl', 'specialRequests'],
        });

        if (!booking) {
            const dateObj = new Date(plan.planDateTime);
            const bookingDate = dateObj.toISOString().split('T')[0];
            booking = await Booking.findOne({
                where: {
                    goingMode: GoingMode.PARTY_REQUEST,
                    userId: plan.userId,
                    venueId: plan.venueId,
                    bookingDate: bookingDate as any,
                },
                order: [['createdAt', 'DESC']],
                attributes: ['id', 'ticketCode', 'ticketUrl', 'specialRequests'],
            });
        }

        let ticketUrl = (booking as any)?.ticketUrl ?? null;
        let ticketCode = booking?.ticketCode ?? null;

        if (booking && !ticketUrl) {
            try {
                const { generateTicketForBookingHelper } = require('../services/ticketService');
                ticketUrl = await generateTicketForBookingHelper(booking.id);
            } catch (ticketGenErr: any) {
                logger.warn(`On-the-fly ticket PDF generation failed for booking ${booking.id}: ${ticketGenErr.message}`);
            }
        }

        res.json({
            success: true,
            data: {
                request: {
                    id: request.id,
                    planId: request.planId,
                    status: request.status,
                    joinerPaymentStatus: request.joinerPaymentStatus,
                    createdAt: request.createdAt,
                    requester: joinerData,
                    joiner: joinerData,
                    user: joinerData,
                },
                plan: {
                    id: plan.id,
                    message: plan.message,
                    planDateTime: plan.planDateTime,
                    expiresAt: plan.planDateTime,
                    paymentType: plan.paymentType,
                    depositAmount: plan.depositAmount,
                    status: plan.status,
                    foodPreference: plan.foodPreference,
                    drinkPreference: plan.drinkPreference,
                    user: hostData,
                    creator: hostData,
                    host: hostData,
                    venue: buildVenueData(plan as any),
                },
                ticketCode: ticketCode,
                bookingId: booking?.id ?? null,
                ticketUrl: ticketUrl,
            },
        });
    } catch (err: any) {
        logger.error('getPartyPlanTicket error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch ticket data', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────
function buildUserData(plan: PartyPlan, currentUserId?: string, isAcceptedJoiner: boolean = false) {
    const creator = (plan as any).creator || (plan as any).user;
    if (!creator) return null;

    const isSecretName = plan.showHostName === false && !!currentUserId && currentUserId !== plan.userId && !isAcceptedJoiner;
    const isSecretPhoto = plan.showProfilePhoto === false && !!currentUserId && currentUserId !== plan.userId && !isAcceptedJoiner;

    let photoUrl = creator.profileImageUrl ?? creator.photoUrl ?? null;
    if (!photoUrl && creator.photos && creator.photos.length > 0) {
        const primary = creator.photos.find((p: any) => p.isPrimary) || creator.photos[0];
        if (primary && primary.filePath) {
            photoUrl = primary.filePath;
        }
    }
    if (photoUrl && typeof photoUrl === 'string' && !photoUrl.startsWith('http') && !photoUrl.startsWith('assets/')) {
        const clean = photoUrl.replace(/\\/g, '/');
        photoUrl = clean.startsWith('/') ? clean : '/' + clean;
    }

    const finalPhoto = isSecretPhoto
        ? 'https://placehold.co/400x400/2a1b38/e0a0ff.png?text=Secret+Host+%F0%9F%94%92'
        : photoUrl;

    return {
        id: creator.id,
        firstName: isSecretName ? 'Secret' : creator.firstName,
        lastName: isSecretName ? 'Host 🔒' : creator.lastName,
        email: isSecretName ? null : creator.email,
        phone: isSecretName ? null : creator.phone,
        profilePhotoUrl: finalPhoto,
        photoUrl: finalPhoto,
        bio: creator.profile?.bio ?? null,
        occupation: creator.profile?.occupation ?? null,
        gender: creator.profile?.gender ?? null,
        city: creator.profile?.city ?? null,
        isSecretHost: isSecretName || isSecretPhoto,
    };
}

function buildVenueData(plan: PartyPlan, currentUserId?: string, isAcceptedJoiner: boolean = false) {
    const venue = (plan as any).venue;
    if (!venue) return null;

    const isSecret = plan.showVenueDetails === false && !!currentUserId && currentUserId !== plan.userId && !isAcceptedJoiner;

    if (isSecret) {
        return {
            id: venue.id,
            name: 'Secret Venue 🔒',
            addressLine1: 'Revealed upon host approval',
            area: venue.area ? `${venue.area}` : 'Secret Location',
            city: venue.city,
            category: venue.category,
            phone: null,
            coverChargeMale: venue.coverChargeMale,
            coverChargeFemale: venue.coverChargeFemale,
            coverImageUrl: 'https://placehold.co/600x400/2a1b38/e0a0ff.png?text=Secret+Venue+%F0%9F%94%92',
            imageUrl: 'https://placehold.co/600x400/2a1b38/e0a0ff.png?text=Secret+Venue+%F0%9F%94%92',
            isSecret: true,
        };
    }

    let coverImageUrl = venue.coverImageUrl || venue.imageUrl || venue.image || null;
    if (!coverImageUrl && venue.images && venue.images.length > 0) {
        const coverImage = venue.images[0];
        const rawPath = coverImage?.filePath || coverImage?.url || coverImage?.imageUrl;
        if (rawPath) {
            coverImageUrl = rawPath;
        }
    }
    if (coverImageUrl && typeof coverImageUrl === 'string' && !coverImageUrl.startsWith('http') && !coverImageUrl.startsWith('assets/')) {
        const clean = coverImageUrl.replace(/\\/g, '/');
        coverImageUrl = clean.startsWith('/') ? clean : '/' + clean;
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
        imageUrl: coverImageUrl,
        isSecret: false,
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

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/initiate-host-payment
// ─────────────────────────────────────────────────────────────────────────────
export const initiateHostPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        let { id } = req.params;
        if (id && id.startsWith('party_plan_timeline_')) {
            id = id.replace('party_plan_timeline_', '');
        }
        if (id && id.startsWith('pp_')) {
            id = id.replace('pp_', '');
        }

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: `Party plan not found for ID ${id}` });
            return;
        }

        if (plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID) {
            res.status(200).json({
                success: true,
                message: 'Host payment already completed',
                alreadyPaid: true,
            });
            return;
        }

        // Commitment deposit is always ₹99, regardless of SPLIT or SELF_PAY.
        const amount = Number(plan.depositAmount) || 99; // host commitment deposit
        const shortId = plan.id.substring(0, 8);
        const options = {
            amount: amount * 100, // in paise
            currency: 'INR',
            receipt: `hp_${shortId}_${Date.now().toString().slice(-6)}`,
        };

        let order: any;
        const hasRazorpayKeys = process.env.RAZORPAY_KEY_ID && 
                                process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id' && 
                                process.env.RAZORPAY_KEY_ID !== 'rzp_test_123';
        if (hasRazorpayKeys) {
            try {
                order = await razorpay.orders.create(options);
            } catch (err: any) {
                logger.error('Razorpay host order creation failed. Error details:', err);
                res.status(500).json({ success: false, message: 'Failed to create real Razorpay order', error: err });
                return;
            }
        } else {
            order = { id: `order_mock_${Date.now()}_${Math.random().toString(36).substring(2, 10)}` };
        }

        await (plan as any).update({
            hostRazorpayOrderId: order.id,
        });

        res.status(200).json({
            success: true,
            razorpayOrderId: order.id,
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
            amount: amount,
        });
    } catch (err: any) {
        logger.error('initiateHostPayment error:', err);
        res.status(500).json({ success: false, message: 'Failed to initiate host payment', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/initiate-joiner-payment
// ─────────────────────────────────────────────────────────────────────────────
export const initiateJoinerPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { reqId } = req.params;
        const request = await PartyPlanRequest.findByPk(reqId, {
            include: [{ model: PartyPlan, as: 'plan' }]
        });
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }
        
        const plan = (request as any).plan;

        if (request.joinerPaymentStatus === PartyPlanJoinerPaymentStatus.PAID) {
            res.status(200).json({
                success: true,
                message: 'Joiner payment already completed',
                alreadyPaid: true,
            });
            return;
        }

        const amount = plan?.depositAmount ? Number(plan.depositAmount) : 99; // dynamic joiner deposit amount
        const shortReqId = request.id.toString().substring(0, 8);
        const options = {
            amount: amount * 100, // in paise
            currency: 'INR',
            receipt: `jr_${shortReqId}_${Date.now().toString().slice(-6)}`,
        };

        let order: any;
        const hasRazorpayKeys = process.env.RAZORPAY_KEY_ID && 
                                process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id' && 
                                process.env.RAZORPAY_KEY_ID !== 'rzp_test_123';
        if (hasRazorpayKeys) {
            try {
                order = await razorpay.orders.create(options);
            } catch (err: any) {
                logger.error('Razorpay joiner order creation failed. Error details:', err);
                res.status(500).json({ success: false, message: 'Failed to create real Razorpay order', error: err });
                return;
            }
        } else {
            order = { id: `order_mock_${Date.now()}_${Math.random().toString(36).substring(2, 10)}` };
        }

        await (request as any).update({
            joinerRazorpayOrderId: order.id,
        });

        res.status(200).json({
            success: true,
            razorpayOrderId: order.id,
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
            amount: amount,
        });
    } catch (err: any) {
        logger.error('initiateJoinerPayment error:', err);
        res.status(500).json({ success: false, message: 'Failed to initiate joiner payment', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/confirm-arrival
// Allows host or guest to confirm arrival independently (YES / NOT YET)
// ─────────────────────────────────────────────────────────────────────────────
export const confirmArrival = async (req: Request, res: Response): Promise<void> => {
    try {
        const id = req.params.id || req.params.planId;
        const { response, hasArrived, latitude, longitude, device, ip } = req.body;
        const userId = req.user?.id || req.body.userId || req.query.userId;

        if (!userId) {
            res.status(401).json({ success: false, message: 'Unauthorized' });
            return;
        }

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        const isHost = plan.userId === userId;
        const choice = response ? response.toString().toUpperCase() : (hasArrived === false ? 'NO' : 'YES');
        const isYes = choice === 'YES' || hasArrived === true;

        if (isHost) {
            await plan.update({
                hostArrivalConfirmed: isYes,
                hostArrivalTime: isYes ? new Date() : null,
                hostLatLangCheckIn: latitude && longitude ? true : plan.hostLatLangCheckIn
            });
        } else {
            const acceptedReq = await PartyPlanRequest.findOne({
                where: { planId: id, requesterId: userId }
            });
            if (!acceptedReq) {
                res.status(403).json({ success: false, message: 'You are not an active participant in this plan' });
                return;
            }
            await acceptedReq.update({
                guestArrivalConfirmed: isYes,
                guestArrivalTime: isYes ? new Date() : null,
                latLangCheckIn: latitude && longitude ? true : acceptedReq.latLangCheckIn
            });
        }

        const AuditLog = (await import('../models/AuditLog')).default;
        await AuditLog.logAction({
            userId,
            partyPlanId: id,
            action: `Arrival Response (${choice})`,
            metadata: { isHost, response: choice, latitude, longitude, device, ip }
        });

        res.json({
            success: true,
            message: `Arrival response (${choice}) recorded.`,
            data: { planId: id, isHost, confirmed: isYes }
        });
    } catch (err: any) {
        logger.error('confirmArrival error:', err);
        res.status(500).json({ success: false, message: 'Failed to confirm arrival', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/review
// Submit post-event review (1-5 stars & feedback)
// ─────────────────────────────────────────────────────────────────────────────
export const submitPartyReview = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { reviewerId, rating, comment, isReported, reportReason } = req.body;

        if (!reviewerId || !rating) {
            res.status(400).json({ success: false, message: 'reviewerId and rating (1-5) are required' });
            return;
        }

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        const acceptedReq = await PartyPlanRequest.findOne({
            where: { planId: id, status: PartyPlanRequestStatus.ACCEPTED }
        });

        const isHost = plan.userId === reviewerId;
        const revieweeId = isHost ? acceptedReq?.requesterId : plan.userId;

        if (!revieweeId) {
            res.status(400).json({ success: false, message: 'Invalid participant for review' });
            return;
        }

        const PartyReview = (await import('../models/PartyReview')).default;
        const review = await PartyReview.create({
            planId: id,
            reviewerId,
            revieweeId,
            rating: Number(rating),
            comment,
            isReported: Boolean(isReported),
            reportReason,
        });

        res.json({
            success: true,
            message: 'Thank you for your feedback!',
            data: review,
        });
    } catch (err: any) {
        logger.error('submitPartyReview error:', err);
        res.status(500).json({ success: false, message: 'Failed to submit review', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// Dynamic Payload Enrichment Helper for Notification Timeline
// ─────────────────────────────────────────────────────────────────────────────
export async function enrichPartyPlanNotificationCard(planId: string, recipientUserId: string) {
    try {
        const plan = await PartyPlan.findByPk(planId, {
            include: [
                { model: User, as: 'creator', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] },
                { model: Venue, as: 'venue', attributes: ['id', 'name', 'area'] },
                { 
                    model: PartyPlanRequest, 
                    as: 'requests', 
                    include: [{ model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] }] 
                }
            ]
        });

        if (!plan) return null;

        const p = plan as any;
        const isHost = plan.userId === recipientUserId;
        const matchedRequest = plan.matchedRequestId 
            ? p.requests?.find((r: any) => r.id === plan.matchedRequestId)
            : p.requests?.find((r: any) => r.status === 'accepted' || r.status === 'payment_pending');

        const counterpartUser = isHost
            ? (matchedRequest ? matchedRequest.requester : null)
            : p.creator;

        const hostName = `${p.creator?.firstName || 'Host'} ${p.creator?.lastName || ''}`.trim();
        const guestName = counterpartUser ? `${counterpartUser.firstName} ${counterpartUser.lastName}`.trim() : 'Partner';

        const partyImage = p.creator?.profileImageUrl || '';
        const planTitle = plan.message || 'Party Night Out';
        const venueArea = p.venue?.area || 'Pune';
        const distance = '1.2 km'; 
        const dateStr = plan.planDateTime.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
        const timeStr = plan.planDateTime.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' });

        const timeline: any[] = [];
        const status = plan.lifecycleStatus;

        const addStep = (title: string, completed: boolean, dateVal?: Date | null) => {
            timeline.push({
                title,
                completed,
                timestamp: dateVal ? dateVal.toISOString() : null
            });
        };

        // 1. Plan Posted
        addStep('Plan Posted', true, plan.createdAt);

        // 2. Request Sent / Received
        const hasRequests = p.requests && p.requests.length > 0;
        addStep(isHost ? 'Request Received' : 'Request Sent', hasRequests || !!matchedRequest, matchedRequest?.createdAt);

        // 3. Request Accepted
        const isAccepted = [
            PartyPlanLifecycleStatus.USER_ACCEPTED,
            PartyPlanLifecycleStatus.PAYMENT_PENDING,
            PartyPlanLifecycleStatus.HOST_PAYMENT_COMPLETED,
            PartyPlanLifecycleStatus.GUEST_PAYMENT_COMPLETED,
            PartyPlanLifecycleStatus.MATCH_CONFIRMED,
            PartyPlanLifecycleStatus.CHAT_ENABLED,
            PartyPlanLifecycleStatus.EVENT_UPCOMING,
            PartyPlanLifecycleStatus.EVENT_REMINDER,
            PartyPlanLifecycleStatus.ONE_HOUR_REMINDER,
            PartyPlanLifecycleStatus.THIRTY_MIN_REMINDER,
            PartyPlanLifecycleStatus.TEN_MIN_CONFIRMATION,
            PartyPlanLifecycleStatus.ARRIVAL_PENDING,
            PartyPlanLifecycleStatus.ARRIVAL_CONFIRMATION,
            PartyPlanLifecycleStatus.ARRIVAL_VERIFIED,
            PartyPlanLifecycleStatus.WALLET_CREDIT_PROCESSED,
            PartyPlanLifecycleStatus.PLAN_COMPLETED,
            PartyPlanLifecycleStatus.COMPLETED
        ].includes(status as any);
        addStep('Request Accepted', isAccepted, plan.acceptedAt);

        // 4. Waiting Payment
        const isWaitingPayment = isAccepted;
        addStep('Waiting Payment', isWaitingPayment, plan.acceptedAt);

        // 5. Host Paid
        const hostPaid = plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;
        addStep('Host Paid', hostPaid);

        // 6. Guest Paid
        const guestPaid = matchedRequest?.joinerPaymentStatus === 'paid' || plan.paymentType === 'self_pay';
        addStep('Guest Paid', guestPaid);

        // 7. Match Confirmed
        const isConfirmed = [
            PartyPlanLifecycleStatus.MATCH_CONFIRMED,
            PartyPlanLifecycleStatus.CHAT_ENABLED,
            PartyPlanLifecycleStatus.EVENT_UPCOMING,
            PartyPlanLifecycleStatus.EVENT_REMINDER,
            PartyPlanLifecycleStatus.ONE_HOUR_REMINDER,
            PartyPlanLifecycleStatus.THIRTY_MIN_REMINDER,
            PartyPlanLifecycleStatus.TEN_MIN_CONFIRMATION,
            PartyPlanLifecycleStatus.ARRIVAL_PENDING,
            PartyPlanLifecycleStatus.ARRIVAL_CONFIRMATION,
            PartyPlanLifecycleStatus.ARRIVAL_VERIFIED,
            PartyPlanLifecycleStatus.WALLET_CREDIT_PROCESSED,
            PartyPlanLifecycleStatus.PLAN_COMPLETED,
            PartyPlanLifecycleStatus.COMPLETED
        ].includes(status as any);
        addStep('Match Confirmed', isConfirmed);

        // 8. Chat Enabled
        const isChatEnabled = [
            PartyPlanLifecycleStatus.CHAT_ENABLED,
            PartyPlanLifecycleStatus.EVENT_UPCOMING,
            PartyPlanLifecycleStatus.EVENT_REMINDER,
            PartyPlanLifecycleStatus.ONE_HOUR_REMINDER,
            PartyPlanLifecycleStatus.THIRTY_MIN_REMINDER,
            PartyPlanLifecycleStatus.TEN_MIN_CONFIRMATION,
            PartyPlanLifecycleStatus.ARRIVAL_PENDING,
            PartyPlanLifecycleStatus.ARRIVAL_CONFIRMATION,
            PartyPlanLifecycleStatus.ARRIVAL_VERIFIED,
            PartyPlanLifecycleStatus.WALLET_CREDIT_PROCESSED,
            PartyPlanLifecycleStatus.PLAN_COMPLETED,
            PartyPlanLifecycleStatus.COMPLETED
        ].includes(status as any);
        addStep('Chat Enabled', isChatEnabled);

        // 9. Reminder Scheduled
        const now = new Date();
        const eventTime = new Date(plan.planDateTime);
        const isClose = (eventTime.getTime() - now.getTime()) <= 24 * 60 * 60 * 1000;
        addStep('Reminder Scheduled', isClose || [
            PartyPlanLifecycleStatus.ONE_HOUR_REMINDER,
            PartyPlanLifecycleStatus.THIRTY_MIN_REMINDER,
            PartyPlanLifecycleStatus.TEN_MIN_CONFIRMATION
        ].includes(status as any));

        // 10. Arrival Pending / Verified
        const isArrivalStep = [
            PartyPlanLifecycleStatus.TEN_MIN_CONFIRMATION,
            PartyPlanLifecycleStatus.ARRIVAL_PENDING,
            PartyPlanLifecycleStatus.ARRIVAL_CONFIRMATION,
            PartyPlanLifecycleStatus.ARRIVAL_VERIFIED,
            PartyPlanLifecycleStatus.WALLET_CREDIT_PROCESSED,
            PartyPlanLifecycleStatus.PLAN_COMPLETED,
            PartyPlanLifecycleStatus.COMPLETED
        ].includes(status as any);
        addStep('Arrival Verified', isArrivalStep);

        // 11. Completed
        const isCompleted = [
            PartyPlanLifecycleStatus.WALLET_CREDIT_PROCESSED,
            PartyPlanLifecycleStatus.PLAN_COMPLETED,
            PartyPlanLifecycleStatus.COMPLETED,
            PartyPlanLifecycleStatus.ARCHIVED
        ].includes(status as any);
        addStep('Completed', isCompleted);

        let primaryAction: string | null = null;
        let secondaryAction: string | null = null;
        let primaryActionUrl: string | null = null;
        let secondaryActionUrl: string | null = null;
        let currentStatusText = 'Active';

        if (status === PartyPlanLifecycleStatus.CANCELLED) {
            currentStatusText = 'Cancelled';
        } else if (status === PartyPlanLifecycleStatus.EXPIRED) {
            currentStatusText = 'Expired';
        } else if (isCompleted) {
            currentStatusText = 'Completed';
            primaryAction = 'View Summary';
            primaryActionUrl = `/party-plans/${plan.id}/summary`;
        } else if (status === PartyPlanLifecycleStatus.TEN_MIN_CONFIRMATION || status === PartyPlanLifecycleStatus.ARRIVAL_PENDING || status === PartyPlanLifecycleStatus.ARRIVAL_CONFIRMATION) {
            currentStatusText = 'Action Required: Confirm Arrival';
            primaryAction = 'Confirm Arrival';
            secondaryAction = 'Open Chat';
            primaryActionUrl = `/party-plans/${plan.id}/arrival-confirm`;
            secondaryActionUrl = `/chat/${plan.id}`;
        } else if (status === PartyPlanLifecycleStatus.ONE_HOUR_REMINDER || status === PartyPlanLifecycleStatus.THIRTY_MIN_REMINDER) {
            currentStatusText = 'Event Starting Soon';
            primaryAction = 'Open Chat';
            primaryActionUrl = `/chat/${plan.id}`;
        } else if (isChatEnabled || isConfirmed) {
            currentStatusText = 'Match Confirmed';
            primaryAction = 'Open Chat';
            primaryActionUrl = `/chat/${plan.id}`;
        } else if (isAccepted) {
            if (isHost) {
                if (!hostPaid) {
                    currentStatusText = 'Action Required: Pay Deposit';
                    primaryAction = 'Pay Now';
                    primaryActionUrl = `/party-plans/${plan.id}/pay-host`;
                } else {
                    currentStatusText = 'Waiting other user';
                    primaryAction = 'Waiting...';
                }
            } else {
                if (!guestPaid) {
                    currentStatusText = 'Action Required: Pay Deposit';
                    primaryAction = 'Pay Now';
                    primaryActionUrl = `/party-plans/${plan.id}/pay-joiner/${matchedRequest?.id}`;
                } else {
                    currentStatusText = 'Waiting other user';
                    primaryAction = 'Waiting...';
                }
            }
        } else {
            if (isHost) {
                if (!hostPaid) {
                    currentStatusText = 'Action Required: Pay Deposit';
                    primaryAction = 'Pay Deposit';
                    primaryActionUrl = `/party-plans/${plan.id}/pay-host`;
                } else if (hasRequests) {
                    currentStatusText = 'Request Received';
                    primaryAction = 'Accept';
                    secondaryAction = 'Reject';
                    primaryActionUrl = `/requests/accept`;
                    secondaryActionUrl = `/requests/reject`;
                } else {
                    currentStatusText = 'Active';
                }
            } else {
                currentStatusText = 'Request Sent';
                primaryAction = 'Pending Review';
            }
        }

        let countdownText: string | null = null;
        if (plan.paymentDeadlineAt && !isConfirmed && [PartyPlanLifecycleStatus.USER_ACCEPTED, PartyPlanLifecycleStatus.PAYMENT_PENDING, PartyPlanLifecycleStatus.HOST_PAYMENT_COMPLETED, PartyPlanLifecycleStatus.GUEST_PAYMENT_COMPLETED].includes(status as any)) {
            const deadline = new Date(plan.paymentDeadlineAt);
            const diffMs = deadline.getTime() - now.getTime();
            if (diffMs > 0) {
                const minutes = Math.floor(diffMs / 60000);
                const seconds = Math.floor((diffMs % 60000) / 1000);
                countdownText = `Payment expires in ${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
            } else {
                countdownText = 'Payment session expired';
            }
        } else if (eventTime.getTime() > now.getTime()) {
            const diffMs = eventTime.getTime() - now.getTime();
            const diffHours = Math.floor(diffMs / (3600 * 1000));
            if (diffHours >= 24) {
                const diffDays = Math.floor(diffHours / 24);
                countdownText = `Event starts in ${diffDays} Day${diffDays > 1 ? 's' : ''}`;
            } else if (diffHours >= 1) {
                countdownText = `Event starts in ${diffHours} Hour${diffHours > 1 ? 's' : ''}`;
            } else {
                const diffMins = Math.floor(diffMs / 60000);
                countdownText = `Event starts in ${diffMins} Minutes`;
            }
        }

        return {
            partyPlanId: plan.id,
            partyImage,
            hostName,
            guestName,
            planTitle,
            venueName: p.venue?.name || 'Venue',
            venueArea,
            distance,
            date: dateStr,
            time: timeStr,
            currentStatus: currentStatusText,
            progressTimeline: timeline,
            primaryAction,
            secondaryAction,
            primaryActionUrl,
            secondaryActionUrl,
            countdown: countdownText,
            lastUpdated: plan.updatedAt ? plan.updatedAt.toISOString() : plan.createdAt.toISOString(),
            matchedRequestId: plan.matchedRequestId,
            hostPaymentStatus: plan.hostPaymentStatus,
            depositAmount: plan.depositAmount,
            hostRazorpayOrderId: plan.hostRazorpayOrderId,
        };
    } catch (enrichErr: any) {
        logger.error(`Error enriching party plan notification card ${planId}:`, enrichErr);
        return null;
    }
}



/**
 * GET /api/mobile/party-plans/:planId/summary
 * Returns a comprehensive post-event summary for Host and Guest
 */
export async function getPlanSummary(req: Request, res: Response): Promise<Response> {
    try {
        const { planId } = req.params;
        const userId = (req.query.userId as string) || (req.user as any)?.id;

        const plan = await PartyPlan.findByPk(planId, {
            include: [
                { model: Venue, as: 'venue', attributes: ['name', 'area', 'addressLine1'] },
                { model: User, as: 'creator', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] },
                {
                    model: PartyPlanRequest,
                    as: 'requests',
                    include: [{ model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] }]
                }
            ]
        });

        if (!plan) {
            return res.status(404).json({ success: false, message: 'Party plan not found' });
        }

        const p = plan as any;
        const matchedRequest = plan.matchedRequestId
            ? p.requests?.find((r: any) => r.id === plan.matchedRequestId)
            : p.requests?.find((r: any) => r.status === 'accepted');

        const host = p.creator;
        const guest = matchedRequest ? matchedRequest.requester : null;

        const hostConfirmed = Boolean(plan.hostArrivalConfirmed);
        const guestConfirmed = Boolean(matchedRequest?.guestArrivalConfirmed);

        let completionStatus = 'Completed (Both Reached)';
        if (hostConfirmed && guestConfirmed) completionStatus = 'Completed (Both Reached)';
        else if (hostConfirmed && !guestConfirmed) completionStatus = 'Completed (Host Reached, Guest No-Show)';
        else if (!hostConfirmed && guestConfirmed) completionStatus = 'Completed (Guest Reached, Host No-Show)';
        else completionStatus = 'Closed (Both No-Show)';

        const walletCreditHost = plan.hostPaymentStatus === 'refunded' ? `₹${plan.depositAmount || 99}` : '₹0';
        const walletCreditGuest = matchedRequest?.joinerPaymentStatus === 'refunded' ? '₹99' : '₹0';

        const reliabilityImpactHost = hostConfirmed ? '+5 Score' : '-10 Score';
        const reliabilityImpactGuest = guestConfirmed ? '+5 Score' : '-10 Score';

        return res.json({
            success: true,
            data: {
                partyPlanId: plan.id,
                planTitle: plan.message || 'Party Night Out',
                venueName: p.venue?.name || 'Venue',
                venueArea: p.venue?.area || 'Pune',
                eventDate: plan.planDateTime ? plan.planDateTime.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : '',
                eventTime: plan.planDateTime ? plan.planDateTime.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' }) : '',
                host: host ? { id: host.id, name: `${host.firstName} ${host.lastName}`.trim(), photo: host.profileImageUrl } : null,
                guest: guest ? { id: guest.id, name: `${guest.firstName} ${guest.lastName}`.trim(), photo: guest.profileImageUrl } : null,
                completionStatus,
                walletCredit: userId === plan.userId ? walletCreditHost : walletCreditGuest,
                reliabilityImpact: userId === plan.userId ? reliabilityImpactHost : reliabilityImpactGuest,
                timeline: [
                    { step: 'Plan Created', timestamp: plan.createdAt },
                    { step: 'Request Accepted', timestamp: plan.acceptedAt },
                    { step: 'Match Confirmed', timestamp: plan.updatedAt },
                    { step: 'Arrival Verified', timestamp: plan.hostArrivalTime || matchedRequest?.guestArrivalTime },
                    { step: 'Plan Completed', timestamp: plan.updatedAt },
                ]
            }
        });
    } catch (err: any) {
        logger.error('[partyPlanController] getPlanSummary error:', err);
        return res.status(500).json({ success: false, message: 'Failed to fetch plan summary' });
    }
}
