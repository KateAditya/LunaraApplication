import { Request, Response } from 'express';
import { Op, Transaction } from 'sequelize';
import sequelize from '../config/database';
import PartyPlan, { PartyPlanStatus, PartyPlanLifecycleStatus, PartyPlanPaymentStatus } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus, PartyPlanJoinerPaymentStatus } from '../models/PartyPlanRequest';
import PartyPlanCancellationRequest, { CancellationRequestStatus, CancellationReason } from '../models/PartyPlanCancellationRequest';
import Booking, { BookingStatus, PaymentStatus as BookingPaymentStatus, GoingMode } from '../models/Booking';
import Ticket, { TicketStatus } from '../models/Ticket';
import Payment, { PaymentStatus, PaymentMethod } from '../models/Payment';
import User from '../models/User';
import UserProfile from '../models/UserProfile';
import { WalletService } from '../services/walletService';
import ReliabilityHistory from '../models/ReliabilityHistory';
import Conversation from '../models/Conversation';
import ChatSubscription, { ChatSubscriptionStatus } from '../models/ChatSubscription';
import { NotificationService } from '../services/NotificationService';
import { sendMulticastPushNotification } from '../services/fcmService';
import { PlanEligibilityService } from '../services/PlanEligibilityService';
import { EventSeatService } from '../services/EventSeatService';
import { logger } from '../config/logger';
import apiCache from '../utils/apiCache';

/**
 * Helper: Check 3-hour cancellation window
 * Cancellation is allowed only until 3 Hours BEFORE Event Start Time.
 */
export function checkCancellationWindow(eventDateTime: Date): { isAllowed: boolean; hoursRemaining: number; message?: string } {
    const now = new Date();
    const eventTime = new Date(eventDateTime);
    const diffMs = eventTime.getTime() - now.getTime();
    const hoursRemaining = diffMs / (1000 * 60 * 60);

    if (hoursRemaining < 3) {
        return {
            isAllowed: false,
            hoursRemaining,
            message: 'This Party Plan can no longer be cancelled because the cancellation window has closed (must be at least 3 hours before event start time).',
        };
    }

    return { isAllowed: true, hoursRemaining };
}

/**
 * POST /api/mobile/plans/:id/cancellation-request
 * Initiates a mutual cancellation request for a confirmed Party Plan
 */
export const createCancellationRequest = async (req: Request, res: Response): Promise<Response> => {
    try {
        const planId = req.params.id || req.body.planId;
        const userId = req.body.userId || (req as any).user?.id;
        const { reason, otherReasonText } = req.body;

        if (!planId || !userId) {
            return res.status(400).json({ success: false, message: 'planId and userId are required' });
        }

        if (!reason || !Object.values(CancellationReason).includes(reason as CancellationReason)) {
            return res.status(400).json({ success: false, message: 'A valid cancellation reason is required' });
        }

        if (reason === CancellationReason.OTHER && otherReasonText && otherReasonText.length > 150) {
            return res.status(400).json({ success: false, message: 'Other reason text cannot exceed 150 characters' });
        }

        // 1. Fetch Party Plan with accepted request
        const plan: any = await PartyPlan.findByPk(planId, {
            include: [
                {
                    model: PartyPlanRequest,
                    as: 'requests',
                    where: {
                        status: {
                            [Op.in]: [
                                PartyPlanRequestStatus.ACCEPTED,
                                PartyPlanRequestStatus.PAYMENT_PENDING,
                            ]
                        }
                    },
                    required: false,
                    include: [{ model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] }],
                },
                { model: User, as: 'creator', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] },
            ],
        });

        if (!plan) {
            return res.status(404).json({ success: false, message: 'Party Plan not found' });
        }

        if (plan.status === PartyPlanStatus.CANCELLED || plan.lifecycleStatus === PartyPlanLifecycleStatus.CANCELLED) {
            return res.status(400).json({ success: false, message: 'Party Plan is already cancelled' });
        }

        // Plan Type Guard — Cancellation system applies ONLY to Party Plan
        const planType = (plan.planType || plan.type || 'party_plan').toString().toLowerCase();
        if (planType !== 'party_plan' && planType !== 'partyplan') {
            return res.status(400).json({ success: false, message: 'This cancellation system applies exclusively to Party Plans.' });
        }

        // Protected Arrival / Completion State Guard
        const protectedStates: string[] = [
            PartyPlanLifecycleStatus.ARRIVAL_PENDING,
            PartyPlanLifecycleStatus.ARRIVAL_CONFIRMATION,
            PartyPlanLifecycleStatus.ARRIVAL_VERIFIED,
            PartyPlanLifecycleStatus.TEN_MIN_CONFIRMATION,
            PartyPlanLifecycleStatus.COMPLETED,
            'arrival_pending',
            'arrival_confirmation',
            'arrival_verified',
            'arrived',
            'completed',
            'no_show',
        ];
        if (protectedStates.includes(plan.lifecycleStatus) || protectedStates.includes(plan.status)) {
            return res.status(400).json({
                success: false,
                isWindowClosed: true,
                message: 'This Party Plan cannot be cancelled because the event has already started or entered completion phase.',
            });
        }

        let acceptedRequest = plan.requests && plan.requests.length > 0 ? plan.requests[0] : null;
        if (!acceptedRequest && plan.matchedRequestId) {
            acceptedRequest = await PartyPlanRequest.findByPk(plan.matchedRequestId, {
                include: [{ model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] }],
            });
        }

        if (!acceptedRequest) {
            if (plan.userId !== userId) {
                return res.status(403).json({ success: false, message: 'Only the host can cancel a plan with no accepted participants.' });
            }
            // Scenario A: Direct Cancellation for Host (no accepted joiner)
            const { cancelPartyPlanInternal } = require('./partyPlanController');
            const transaction = await sequelize.transaction();
            try {
                const lockedPlan = await PartyPlan.findByPk(plan.id, { transaction, lock: transaction.LOCK.UPDATE });
                if (lockedPlan) {
                    await cancelPartyPlanInternal(lockedPlan, transaction);
                }
                await transaction.commit();
            } catch (tErr) {
                await transaction.rollback();
                throw tErr;
            }

            try {
                const { io } = require('../server');
                if (io) {
                    io.emit('party_plan_deleted', { planId: plan.id });
                    io.emit('party_plan_cancelled', { planId: plan.id });
                    io.to('live_feed').emit('live_feed_update', { type: 'party_plan_cancelled', id: plan.id, planId: plan.id });
                }
            } catch (_) {}

            return res.status(200).json({
                success: true,
                isDirectCancel: true,
                message: 'Party Plan cancelled successfully.',
            });
        }

        // Determine Requester & Recipient
        const isHost = plan.userId === userId;
        const isJoiner = acceptedRequest.requesterId === userId;

        if (!isHost && !isJoiner) {
            return res.status(403).json({ success: false, message: 'You are not a participant of this Party Plan.' });
        }

        const recipientUserId = isHost ? acceptedRequest.requesterId : plan.userId;
        const requesterName = isHost ? `${plan.creator?.firstName || 'Host'}` : `${acceptedRequest.requester?.firstName || 'Participant'}`;

        // 2. Validate 3-Hour Cancellation Window Guard
        const windowCheck = checkCancellationWindow(plan.planDateTime);
        if (!windowCheck.isAllowed) {
            return res.status(400).json({
                success: false,
                isWindowClosed: true,
                message: windowCheck.message,
            });
        }

        // 3. Check for existing PENDING request
        const existingPending = await PartyPlanCancellationRequest.findOne({
            where: {
                planId: plan.id,
                status: CancellationRequestStatus.PENDING,
            },
        });

        if (existingPending) {
            return res.status(400).json({
                success: false,
                message: 'A cancellation request is already pending approval for this Party Plan.',
                cancellationRequest: existingPending,
            });
        }

        // 4. Calculate Expiration & Auto-Approval Eligibility
        const autoApprovalEligible = windowCheck.hoursRemaining >= 24;
        const requestedAt = new Date();
        const expiresAt = new Date(requestedAt.getTime() + 24 * 60 * 60 * 1000); // 24 hours expiration

        // Find associated Booking
        const booking = await Booking.findOne({
            where: {
                goingMode: { [Op.in]: [GoingMode.PLAN, GoingMode.PARTY_REQUEST] },
                userId: plan.userId,
                venueId: plan.venueId,
                status: { [Op.ne]: BookingStatus.CANCELLED },
            },
            order: [['createdAt', 'DESC']],
        });

        const cancellationRequest = await PartyPlanCancellationRequest.create({
            planId: plan.id,
            bookingId: booking?.id || null,
            requestedById: userId,
            recipientUserId,
            status: CancellationRequestStatus.PENDING,
            reason: reason as CancellationReason,
            otherReasonText: reason === CancellationReason.OTHER ? (otherReasonText || null) : null,
            requestedAt,
            expiresAt,
            autoApprovalEligible,
            // Store the ACTUAL amounts each side paid, so the approval step
            // refunds exactly that.
            //
            // For an ordinary party plan both sides paid the ₹99 commitment
            // deposit. For a plan posted from an event, `depositAmount` is the
            // event's per-ticket price and who paid what depends on the model:
            // SELF_PAY means the host bought both tickets and the joiner paid
            // nothing; SPLIT means each bought their own. Reading the joiner's
            // side as a flat ₹99 would refund a ₹1000 ticket as ₹99 on SPLIT,
            // and hand a SELF_PAY joiner ₹99 they never paid.
            ...(function computeDeposits() {
                const perTicket = Number(plan.depositAmount) || 0;
                const isEventPlan = Boolean((plan as any).partyEventId);
                if (!isEventPlan) {
                    return {
                        hostDepositAmount: perTicket || 99.00,
                        joinerDepositAmount: 99.00,
                    };
                }
                const isSelfPay = String(plan.paymentType || '').toLowerCase() === 'self_pay';
                return {
                    hostDepositAmount: perTicket * (isSelfPay ? 2 : 1),
                    joinerDepositAmount: isSelfPay ? 0 : perTicket,
                };
            })(),
            reliabilityImpact: -5,
        });

        // Update Party Plan Lifecycle Status
        await plan.update({ lifecycleStatus: PartyPlanLifecycleStatus.CANCELLATION_REQUESTED });

        // 5. Send Authoritative FCM Push & Socket.io Notifications
        try {
            await NotificationService.dispatch({
                recipientUserId,
                actorUserId: userId,
                eventType: 'party_plan_cancellation_requested',
                category: 'bookings',
                entityType: 'party_plan',
                entityId: plan.id,
                title: 'Party Plan Cancellation Request',
                body: `${requesterName} wants to cancel your Party Plan.`,
                metadata: {
                    type: 'party_plan_cancellation_requested',
                    planId: plan.id,
                    partyPlanId: plan.id,
                    requestId: cancellationRequest.id,
                    requestedById: userId,
                    recipientUserId,
                    reason: cancellationRequest.reason,
                    autoApprovalEligible,
                },
            });

            const recipient = await User.findByPk(recipientUserId);
            if (recipient?.fcmToken) {
                await sendMulticastPushNotification([recipient.fcmToken], {
                    title: 'Party Plan Cancellation Request ⚠️',
                    body: `${requesterName} has requested to cancel your Party Plan. Tap to review.`,
                    data: {
                        type: 'party_plan_cancellation_requested',
                        planId: plan.id,
                        requestId: cancellationRequest.id,
                    },
                });
            }

            // Invalidate Redis/In-memory API caches immediately
            apiCache.invalidatePrefix('pp_feed');
            apiCache.invalidatePrefix('party_plans');

            // Real-time socket notification & live feed card update
            const { io } = require('../server');
            if (io) {
                const cancelPayload = {
                    planId: plan.id,
                    requestId: cancellationRequest.id,
                    requestedById: userId,
                    recipientUserId,
                    requesterName,
                    reason: cancellationRequest.reason,
                    otherReasonText: cancellationRequest.otherReasonText,
                    requestedAt: cancellationRequest.requestedAt,
                    status: CancellationRequestStatus.PENDING,
                    lifecycleStatus: PartyPlanLifecycleStatus.CANCELLATION_REQUESTED,
                };
                // Only emit the cancellation request review prompt to the recipient, NOT the requester
                io.to(`user_${recipientUserId}`).emit('party_plan_cancellation_requested', cancelPayload);
                io.to(`user_${recipientUserId}`).emit('party_plan_updated', { planId: plan.id, lifecycleStatus: PartyPlanLifecycleStatus.CANCELLATION_REQUESTED });
                io.to(`user_${userId}`).emit('party_plan_updated', { planId: plan.id, lifecycleStatus: PartyPlanLifecycleStatus.CANCELLATION_REQUESTED });
                // Private cancellation request — only the two involved parties need this update
                io.to(`user_${recipientUserId}`).emit('live_feed_update', {
                    type: 'party_plan_cancellation_requested',
                    action: 'cancellation_requested',
                    id: plan.id,
                    planId: plan.id,
                    requestId: cancellationRequest.id,
                });
                io.to(`user_${userId}`).emit('live_feed_update', {
                    type: 'party_plan_cancellation_requested',
                    action: 'cancellation_requested',
                    id: plan.id,
                    planId: plan.id,
                    requestId: cancellationRequest.id,
                });
            }
        } catch (notifErr: any) {
            logger.warn('[CreateCancellationRequest] Notification warning:', notifErr.message);
        }

        return res.status(201).json({
            success: true,
            message: 'Cancellation request created successfully. Waiting for the other participant to approve.',
            cancellationRequest,
        });
    } catch (err: any) {
        logger.error('[CreateCancellationRequest] Error:', err);
        return res.status(500).json({ success: false, message: err.message || 'Failed to initiate cancellation request' });
    }
};

/**
 * GET /api/mobile/plans/:id/cancellation-request
 * Fetches current cancellation request state for a Party Plan
 */
export const getCancellationRequest = async (req: Request, res: Response): Promise<Response> => {
    try {
        const planId = req.params.id;
        const plan = await PartyPlan.findByPk(planId);
        if (!plan) {
            return res.status(404).json({ success: false, message: 'Party Plan not found' });
        }

        const windowCheck = checkCancellationWindow(plan.planDateTime);

        const cancellationRequest = await PartyPlanCancellationRequest.findOne({
            where: { planId },
            order: [['createdAt', 'DESC']],
            include: [
                { model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] },
                { model: User, as: 'recipient', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] },
            ],
        });

        return res.status(200).json({
            success: true,
            isWindowClosed: !windowCheck.isAllowed,
            hoursRemaining: windowCheck.hoursRemaining,
            cancellationRequest,
        });
    } catch (err: any) {
        logger.error('[GetCancellationRequest] Error:', err);
        return res.status(500).json({ success: false, message: err.message || 'Failed to fetch cancellation request' });
    }
};

/**
 * POST /api/mobile/plans/:id/cancellation-request/respond
 * Recipient approves or rejects a cancellation request
 */
export const respondToCancellationRequest = async (req: Request, res: Response): Promise<Response> => {
    try {
        const rawPlanId = req.params.id;
        const planId = (rawPlanId || '').toString().replace(/^(pp_|party_plan_|party_plan_timeline_)/i, '');
        const userId = req.body.userId || (req as any).user?.id;
        const rawRequestId = req.body.requestId;
        const action = req.body.action;

        if (!action || !['approve', 'reject'].includes(action)) {
            return res.status(400).json({ success: false, message: 'Valid action (approve/reject) is required' });
        }

        let cancellationRequest: any = null;
        if (rawRequestId && rawRequestId !== 'undefined' && rawRequestId !== 'null' && rawRequestId.toString().trim().length > 0) {
            cancellationRequest = await PartyPlanCancellationRequest.findOne({
                where: { id: rawRequestId.toString().trim(), planId },
            });
            if (!cancellationRequest) {
                cancellationRequest = await PartyPlanCancellationRequest.findByPk(rawRequestId.toString().trim());
            }
        }

        if (!cancellationRequest) {
            cancellationRequest = await PartyPlanCancellationRequest.findOne({
                where: { planId, status: CancellationRequestStatus.PENDING },
                order: [['createdAt', 'DESC']],
            });
        }

        if (!cancellationRequest) {
            const existingReq = await PartyPlanCancellationRequest.findOne({
                where: { planId },
                order: [['createdAt', 'DESC']],
            });
            if (existingReq) {
                const planRecord = await PartyPlan.findByPk(planId, {
                    include: [
                        { model: User, as: 'creator', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] },
                        { model: PartyPlanRequest, as: 'requests', required: false }
                    ]
                });
                return res.status(200).json({
                    success: true,
                    alreadyProcessed: true,
                    message: `Cancellation request was already ${existingReq.status.toLowerCase()}.`,
                    cancellationRequest: existingReq,
                    plan: planRecord,
                    partyPlan: planRecord,
                });
            }
            return res.status(404).json({ success: false, message: 'Cancellation request not found' });
        }

        if (cancellationRequest.status !== CancellationRequestStatus.PENDING) {
            const planRecord = await PartyPlan.findByPk(planId, {
                include: [
                    { model: User, as: 'creator', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] },
                    { model: PartyPlanRequest, as: 'requests', required: false }
                ]
            });
            return res.status(200).json({
                success: true,
                alreadyProcessed: true,
                message: `Cancellation request is already ${cancellationRequest.status.toLowerCase()}`,
                cancellationRequest,
                plan: planRecord,
                partyPlan: planRecord,
            });
        }

        const plan: any = await PartyPlan.findByPk(planId, {
            include: [
                { model: PartyPlanRequest, as: 'requests', where: { status: PartyPlanRequestStatus.ACCEPTED }, required: false },
                { model: User, as: 'creator', attributes: ['id', 'firstName', 'lastName'] },
            ],
        });

        if (!plan) {
            return res.status(404).json({ success: false, message: 'Party Plan not found' });
        }

        const isAuthorized =
            cancellationRequest.recipientUserId === userId ||
            (cancellationRequest.requestedById !== userId && (plan.userId === userId || plan.matchedUserId === userId));

        if (!isAuthorized && userId) {
            return res.status(403).json({ success: false, message: 'Only the recipient of the cancellation request can approve or reject it.' });
        }

        // =========================================================================
        // CASE A: REJECT CANCELLATION REQUEST
        // =========================================================================
        if (action === 'reject') {
            await cancellationRequest.update({
                status: CancellationRequestStatus.REJECTED,
                respondedAt: new Date(),
                respondedById: userId,
            });

            await plan.update({ lifecycleStatus: PartyPlanLifecycleStatus.MATCH_CONFIRMED });

            // Notify Requester.
            //
            // Deferred: the decline is already committed above, and none of this
            // changes the response. Awaiting it made the responder wait on two
            // user lookups, a notification write and an FCM round trip before
            // their tap registered. The approve path below already does this.
            setImmediate(async () => {
            try {
                const [recipientUser, requester] = await Promise.all([
                    User.findByPk(userId),
                    User.findByPk(cancellationRequest.requestedById)
                ]);
                const recipientName = recipientUser ? `${recipientUser.firstName}` : 'The other participant';

                await NotificationService.dispatch({
                    recipientUserId: cancellationRequest.requestedById,
                    actorUserId: userId,
                    eventType: 'party_plan_cancellation_declined',
                    category: 'bookings',
                    entityType: 'party_plan',
                    entityId: plan.id,
                    title: 'Cancellation Request Declined',
                    body: `${recipientName} declined your cancellation request. Your Party Plan remains active and confirmed.`,
                    metadata: { planId: plan.id, requestId: cancellationRequest.id },
                    idempotencyKey: `cancellation_declined_${cancellationRequest.id}`,
                });

                if (requester?.fcmToken) {
                    await sendMulticastPushNotification([requester.fcmToken], {
                        title: 'Cancellation Request Declined 🛡️',
                        body: `Your cancellation request was declined. The Party Plan remains confirmed.`,
                        data: { type: 'party_plan_cancellation_declined', planId: plan.id },
                    });
                }

                // Invalidate Redis/In-memory API caches immediately
                apiCache.invalidatePrefix('pp_feed');
                apiCache.invalidatePrefix('party_plans');

                const { io } = require('../server');
                if (io) {
                    const declinePayload = {
                        planId: plan.id,
                        requestId: cancellationRequest.id,
                        status: CancellationRequestStatus.REJECTED,
                        lifecycleStatus: PartyPlanLifecycleStatus.MATCH_CONFIRMED,
                    };
                    io.to(`user_${cancellationRequest.requestedById}`).emit('party_plan_cancellation_declined', declinePayload);
                    io.to(`user_${userId}`).emit('party_plan_cancellation_declined', declinePayload);
                    io.to(`user_${cancellationRequest.requestedById}`).emit('party_plan_updated', { planId: plan.id, lifecycleStatus: PartyPlanLifecycleStatus.MATCH_CONFIRMED });
                    io.to(`user_${userId}`).emit('party_plan_updated', { planId: plan.id, lifecycleStatus: PartyPlanLifecycleStatus.MATCH_CONFIRMED });
                    // Private decline — only the two involved parties need this update
                    io.to(`user_${cancellationRequest.requestedById}`).emit('live_feed_update', {
                        type: 'party_plan_cancellation_declined',
                        action: 'cancellation_declined',
                        id: plan.id,
                        planId: plan.id,
                    });
                    io.to(`user_${userId}`).emit('live_feed_update', {
                        type: 'party_plan_cancellation_declined',
                        action: 'cancellation_declined',
                        id: plan.id,
                        planId: plan.id,
                    });
                }
            } catch (notifErr: any) {
                logger.warn('[RespondToCancellationRequest] Rejection notification warning:', notifErr.message);
            }
            });

            return res.status(200).json({
                success: true,
                message: 'Cancellation request rejected. Party Plan remains confirmed.',
                cancellationRequest,
                plan,
                partyPlan: plan,
            });
        }

        // =========================================================================
        // CASE B: APPROVE CANCELLATION REQUEST (ATOMIC TRANSACTION)
        // =========================================================================
        return await sequelize.transaction(async (t: Transaction) => {
            let acceptedRequest = plan.requests && plan.requests.length > 0 ? plan.requests[0] : null;
            if (!acceptedRequest && plan.matchedRequestId) {
                acceptedRequest = await PartyPlanRequest.findByPk(plan.matchedRequestId, { transaction: t });
            }
            const joinerId = acceptedRequest ? acceptedRequest.requesterId : (cancellationRequest.requestedById === plan.userId ? cancellationRequest.recipientUserId : cancellationRequest.requestedById);

            // Re-read plan inside transaction with row lock to prevent race conditions
            const lockedPlan = await PartyPlan.findByPk(planId, {
                lock: t.LOCK.UPDATE,
                transaction: t,
            });
            if (!lockedPlan) throw new Error('Party Plan not found inside transaction');

            // Guard: block if already cancelled (duplicate request / concurrent tap)
            if (lockedPlan.status === PartyPlanStatus.CANCELLED) {
                return res.status(200).json({
                    success: true,
                    alreadyCancelled: true,
                    message: 'Party Plan was already cancelled.',
                    plan: lockedPlan,
                    partyPlan: lockedPlan,
                    cancellationRequest,
                });
            }

            // Guard: re-check 3-hour window inside the transaction (server time is authoritative)
            const windowCheck = checkCancellationWindow(lockedPlan.planDateTime);
            if (!windowCheck.isAllowed) {
                return res.status(400).json({
                    success: false,
                    isWindowClosed: true,
                    message: windowCheck.message,
                });
            }

            // 1. Lock and Update Booking
            let booking: Booking | null = null;
            if (cancellationRequest.bookingId) {
                booking = await Booking.findByPk(cancellationRequest.bookingId, { transaction: t });
            }
            if (!booking) {
                booking = await Booking.findOne({
                    where: {
                        goingMode: { [Op.in]: [GoingMode.PLAN, GoingMode.PARTY_REQUEST] },
                        userId: lockedPlan.userId,
                        venueId: lockedPlan.venueId,
                        status: { [Op.ne]: BookingStatus.CANCELLED },
                    },
                    order: [['createdAt', 'DESC']],
                    transaction: t,
                });
            }
            if (booking) {
                await booking.update({
                    status: BookingStatus.CANCELLED,
                    paymentStatus: BookingPaymentStatus.REFUNDED,
                }, { transaction: t });

                // Update all related Payment records to refunded
                const payments = await Payment.findAll({
                    where: {
                        bookingId: booking.id,
                        status: PaymentStatus.SUCCESSFUL,
                    },
                    transaction: t,
                });

                await Promise.all(
                    payments.map(payment =>
                        payment.update({
                            status: PaymentStatus.REFUNDED,
                            refundAmount: payment.amount,
                            refundedAt: new Date(),
                        }, { transaction: t })
                    )
                );
            }

            // 2. Update PartyPlan — status, lifecycleStatus, isLive (all must be updated atomically)
            await lockedPlan.update({
                status: PartyPlanStatus.CANCELLED,
                lifecycleStatus: PartyPlanLifecycleStatus.CANCELLED,
                isLive: false,
                paymentStatus: 'Refunded',
                hostPaymentStatus: PartyPlanPaymentStatus.REFUNDED,
            }, { transaction: t });

            // 3. Update accepted request
            if (acceptedRequest) {
                await acceptedRequest.update({
                    status: PartyPlanRequestStatus.CANCELLED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.REFUNDED,
                }, { transaction: t });
            }

            // 4. Cancel Tickets & Invalidate QR
            if (booking) {
                const tickets = await Ticket.findAll({
                    where: { bookingId: booking.id },
                    transaction: t,
                });
                await Promise.all(
                    tickets.map(ticket =>
                        ticket.update({
                            ticketStatus: TicketStatus.CANCELLED,
                            cancelledAt: new Date(),
                            qrToken: `VOID_${ticket.qrToken}`,
                        }, { transaction: t })
                    )
                );
            }

            // 5. Release PlanEligibilityService time lock (so the date slot becomes available again)
            try {
                await PlanEligibilityService.releaseLock(lockedPlan.id, { transaction: t });
            } catch (lockErr: any) {
                logger.warn('[CancellationApprove] PlanEligibilityService.releaseLock warning:', lockErr.message);
            }

            // ─────────────────────────────────────────────────────────────────
            // 6. Wallet Credits — SmartWallet + WalletTransaction (IDEMPOTENT)
            // Each credit has a unique idempotency reference so duplicate API
            // calls / retries never double-credit the wallet.
            // ─────────────────────────────────────────────────────────────────
            // `|| 99.00` would be wrong here: a SELF_PAY event plan stores a
            // joiner amount of 0 because the joiner genuinely paid nothing, and
            // `Number(0) || 99` would hand them ₹99 they never spent. The
            // fallback must only apply when the amount is actually absent.
            const storedHostDeposit = Number(cancellationRequest.hostDepositAmount);
            const storedJoinerDeposit = Number(cancellationRequest.joinerDepositAmount);
            const hostDeposit = Number.isFinite(storedHostDeposit) ? storedHostDeposit : 99.00;
            const joinerDeposit = Number.isFinite(storedJoinerDeposit) ? storedJoinerDeposit : 99.00;

            const hostCreditRef  = `PARTY_PLAN_CANCEL_CREDIT_HOST_${lockedPlan.id}`;
            const joinerCreditRef = `PARTY_PLAN_CANCEL_CREDIT_JOINER_${lockedPlan.id}_${joinerId}`;

            let hostWalletTxId: string | null = null;
            let joinerWalletTxId: string | null = null;

            try {
                if (hostDeposit <= 0) throw new Error('SKIP_ZERO_REFUND');
                const hostRefund = await WalletService.creditRefund({
                    userId: lockedPlan.userId,
                    amount: hostDeposit,
                    referenceId: hostCreditRef,
                    reason: `Party Plan Cancelled by mutual agreement (Reason: ${cancellationRequest.reason})`,
                    partyPlanId: lockedPlan.id,
                    bookingId: booking?.id,
                    transaction: t,
                });
                hostWalletTxId = hostRefund?.txn?.id || null;
            } catch (hostErr: any) {
                if (hostErr?.message !== 'SKIP_ZERO_REFUND') {
                    logger.error('[CancellationApprove] Host creditRefund error:', hostErr);
                }
            }

            try {
                // Nothing was paid, so there is nothing to give back — a zero
                // credit would only create a confusing ₹0 wallet entry.
                if (joinerDeposit <= 0) throw new Error('SKIP_ZERO_REFUND');
                const joinerRefund = await WalletService.creditRefund({
                    userId: joinerId,
                    amount: joinerDeposit,
                    referenceId: joinerCreditRef,
                    reason: `Party Plan Cancelled by mutual agreement (Reason: ${cancellationRequest.reason})`,
                    partyPlanId: lockedPlan.id,
                    bookingId: booking?.id,
                    transaction: t,
                });
                joinerWalletTxId = joinerRefund?.txn?.id || null;
            } catch (joinerErr: any) {
                if (joinerErr?.message !== 'SKIP_ZERO_REFUND') {
                    logger.error('[CancellationApprove] Joiner creditRefund error:', joinerErr);
                }
            }

            // 7. Update Chat Subscription to EXPIRED (read-only for 24h)
            const conv = await Conversation.findOne({
                where: {
                    [Op.or]: [
                        { participantOne: lockedPlan.userId, participantTwo: joinerId },
                        { participantOne: joinerId, participantTwo: lockedPlan.userId },
                    ],
                },
                transaction: t,
            });
            if (conv) {
                const activeChatSub = await ChatSubscription.findOne({
                    where: { conversationId: conv.id, status: ChatSubscriptionStatus.ACTIVE },
                    transaction: t,
                });
                if (activeChatSub) {
                    const archiveDate = new Date();
                    archiveDate.setHours(archiveDate.getHours() + 24);
                    await activeChatSub.update({
                        status: ChatSubscriptionStatus.EXPIRED,
                        validUntil: archiveDate,
                    }, { transaction: t });
                }
            }

            // ─────────────────────────────────────────────────────────────────
            // 8. Reliability Score — deduct ONLY from the user who INITIATED
            //    the cancellation. The user who confirmed is not penalised.
            //    Always log to ReliabilityHistory for full audit trail.
            // ─────────────────────────────────────────────────────────────────
            const requesterProfile = await UserProfile.findOne({
                where: { userId: cancellationRequest.requestedById },
                transaction: t,
            });
            if (requesterProfile) {
                const currentScore = requesterProfile.reliabilityScore ?? 100;
                const impact = cancellationRequest.reliabilityImpact || -5;
                const newScore = Math.max(0, currentScore + impact); // impact is negative
                await requesterProfile.update({ reliabilityScore: newScore }, { transaction: t });

                // Authoritative audit trail — required by spec
                const isInitiatorHost = cancellationRequest.requestedById === lockedPlan.userId;
                await ReliabilityHistory.create({
                    userId: cancellationRequest.requestedById,
                    oldScore: currentScore,
                    newScore,
                    change: impact,
                    reason: 'Confirmed Party Plan cancellation (initiator)',
                    action: 'PARTY_PLAN_CANCELLATION',
                    partyPlanId: lockedPlan.id,
                    metadata: {
                        cancellationId: cancellationRequest.id,
                        role: isInitiatorHost ? 'host' : 'joiner',
                        confirmedById: userId,
                        reason: cancellationRequest.reason,
                    },
                }, { transaction: t });
            }

            // 9. Update Cancellation Request Record
            await cancellationRequest.update({
                status: CancellationRequestStatus.APPROVED,
                respondedAt: new Date(),
                respondedById: userId,
                hostWalletTransactionId: hostWalletTxId,
                joinerWalletTransactionId: joinerWalletTxId,
            }, { transaction: t });

            // 9b. Hand the event's seats back. Only does anything for a plan
            // posted from an Upcoming Night; an ordinary party plan holds no
            // seats and this is a no-op for it. Idempotent, so the several
            // routes a plan can be cancelled through cannot double-release.
            if ((lockedPlan as any).partyEventId) {
                await EventSeatService.releaseForPlan(lockedPlan.id);
            }

            // ─────────────────────────────────────────────────────────────────
            // 10. Post-Approval Notifications + Socket Events (async, post-commit)
            // idempotencyKey prevents duplicate DB notification rows on retry.
            // ─────────────────────────────────────────────────────────────────
            setImmediate(async () => {
                try {
                    const [hostUser, joinerUser] = await Promise.all([
                        User.findByPk(lockedPlan.userId),
                        User.findByPk(joinerId)
                    ]);

                    const hostBody = `Party Plan cancelled by mutual agreement. Your ₹${hostDeposit} Commitment Deposit has been credited to your Lunara Wallet.`;
                    const joinerBody = `Party Plan cancelled by mutual agreement. Your ₹${joinerDeposit} Commitment Deposit has been credited to your Lunara Wallet.`;

                    await Promise.all([
                        NotificationService.dispatch({
                            recipientUserId: lockedPlan.userId,
                            actorUserId: userId,
                            eventType: 'party_plan_cancelled',
                            category: 'bookings',
                            entityType: 'party_plan',
                            entityId: lockedPlan.id,
                            title: 'Party Plan Cancelled',
                            body: hostBody,
                            metadata: { planId: lockedPlan.id, walletCredited: hostDeposit, cancellationId: cancellationRequest.id },
                            idempotencyKey: `party_plan_cancelled_host_${lockedPlan.id}`,
                        }),
                        NotificationService.dispatch({
                            recipientUserId: joinerId,
                            actorUserId: userId,
                            eventType: 'party_plan_cancelled',
                            category: 'bookings',
                            entityType: 'party_plan',
                            entityId: lockedPlan.id,
                            title: 'Party Plan Cancelled',
                            body: joinerBody,
                            metadata: { planId: lockedPlan.id, walletCredited: joinerDeposit, cancellationId: cancellationRequest.id },
                            idempotencyKey: `party_plan_cancelled_joiner_${lockedPlan.id}_${joinerId}`,
                        })
                    ]);

                    // FCM push to both
                    const tokens = [hostUser?.fcmToken, joinerUser?.fcmToken].filter(t => t && t.trim() !== '') as string[];
                    if (tokens.length > 0) {
                        await sendMulticastPushNotification(tokens, {
                            title: 'Party Plan Cancelled 💔',
                            body: 'Commitment Deposit has been credited to your Lunara Wallet.',
                            data: { type: 'party_plan_cancelled', planId: lockedPlan.id },
                        });
                    }

                    // Invalidate Redis/In-memory API caches immediately
                    apiCache.invalidatePrefix('pp_feed');
                    apiCache.invalidatePrefix('party_plans');

                    // Socket events — live feed update
                    const { io } = require('../server');
                    if (io) {
                        const cancelHostPayload = {
                            planId: lockedPlan.id,
                            requestId: cancellationRequest.id,
                            mutualCancellation: true,
                            walletCredited: hostDeposit,
                            status: PartyPlanStatus.CANCELLED,
                            lifecycleStatus: PartyPlanLifecycleStatus.CANCELLED,
                        };
                        const cancelJoinerPayload = {
                            planId: lockedPlan.id,
                            requestId: cancellationRequest.id,
                            mutualCancellation: true,
                            walletCredited: joinerDeposit,
                            status: PartyPlanStatus.CANCELLED,
                            lifecycleStatus: PartyPlanLifecycleStatus.CANCELLED,
                        };
                        io.to(`user_${lockedPlan.userId}`).emit('party_plan_cancelled', cancelHostPayload);
                        io.to(`user_${joinerId}`).emit('party_plan_cancelled', cancelJoinerPayload);
                        io.to(`user_${lockedPlan.userId}`).emit('party_plan_updated', { planId: lockedPlan.id, status: PartyPlanStatus.CANCELLED, lifecycleStatus: PartyPlanLifecycleStatus.CANCELLED });
                        io.to(`user_${joinerId}`).emit('party_plan_updated', { planId: lockedPlan.id, status: PartyPlanStatus.CANCELLED, lifecycleStatus: PartyPlanLifecycleStatus.CANCELLED });
                        // Remove from public live feed
                        io.emit('party_plan_deleted', { planId: lockedPlan.id });
                        // Public plan removal — live_feed room only (party_plan_deleted already handles removal)
                        io.to('live_feed').emit('live_feed_update', {
                            type: 'party_plan_cancelled',
                            action: 'cancellation_approved',
                            id: lockedPlan.id,
                            planId: lockedPlan.id,
                            requestId: cancellationRequest.id,
                        });
                    }
                } catch (asyncErr: any) {
                    logger.warn('[CancellationApprove] Async notification error:', asyncErr.message);
                }
            });

            return res.status(200).json({
                success: true,
                message: `Party Plan cancelled by mutual agreement. Commitment deposits have been credited to both users' Lunara Wallets.`,
                cancellationRequest,
                plan: lockedPlan,
                partyPlan: lockedPlan,
                walletCredits: {
                    host: { userId: lockedPlan.userId, amount: hostDeposit },
                    joiner: { userId: joinerId, amount: joinerDeposit },
                },
            });
        });
    } catch (err: any) {
        logger.error('[RespondToCancellationRequest] Error:', err);
        return res.status(500).json({ success: false, message: err.message || 'Failed to respond to cancellation request' });
    }
};

/**
 * Helper / Background Check: Process Expired & Auto-Approved Cancellation Requests
 */
export const checkExpiredOrAutoApprovedRequests = async (): Promise<void> => {
    try {
        const now = new Date();
        const pendingRequests = await PartyPlanCancellationRequest.findAll({
            where: {
                status: CancellationRequestStatus.PENDING,
                expiresAt: { [Op.lte]: now },
            },
        });

        for (const reqRecord of pendingRequests) {
            if (reqRecord.autoApprovalEligible) {
                // Auto-approve cancellation request (> 24h prior to event)
                logger.info(`[AutoApproval] Auto-approving cancellation request ${reqRecord.id} for plan ${reqRecord.planId}`);
                await respondToCancellationRequestInternal(reqRecord, 'approve');
            } else {
                // Mark request as EXPIRED
                await reqRecord.update({ status: CancellationRequestStatus.EXPIRED });
                try {
                    await NotificationService.dispatch({
                        recipientUserId: reqRecord.requestedById,
                        actorUserId: reqRecord.recipientUserId,
                        eventType: 'party_plan_cancellation_expired',
                        category: 'bookings',
                        entityType: 'party_plan',
                        entityId: reqRecord.planId,
                        title: 'Cancellation Request Expired',
                        body: 'Your cancellation request has expired without response. The Party Plan remains confirmed.',
                    });
                } catch (_) {}
            }
        }
    } catch (err: any) {
        logger.error('[checkExpiredOrAutoApprovedRequests] Error:', err);
    }
};

/** Internal transaction executor for auto-approval */
async function respondToCancellationRequestInternal(reqRecord: PartyPlanCancellationRequest, action: 'approve') {
    // Re-use atomic approval transaction logic
    const reqMock = {
        params: { id: reqRecord.planId },
        body: { requestId: reqRecord.id, action, userId: reqRecord.recipientUserId },
    } as any;
    const resMock = {
        status: () => ({ json: () => {} }),
    } as any;
    await respondToCancellationRequest(reqMock, resMock);
}

/**
 * GET /api/admin/cancellation-requests
 * Admin endpoint for monitoring cancellation requests, reasons, and wallet credits
 */
export const getAdminCancellationRequests = async (_req: Request, res: Response): Promise<Response> => {
    try {
        const requests = await PartyPlanCancellationRequest.findAll({
            order: [['createdAt', 'DESC']],
            include: [
                { model: PartyPlan, as: 'plan' },
                { model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] },
                { model: User, as: 'recipient', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] },
            ],
        });

        const stats = {
            total: requests.length,
            pending: requests.filter(r => r.status === CancellationRequestStatus.PENDING).length,
            approved: requests.filter(r => r.status === CancellationRequestStatus.APPROVED || r.status === CancellationRequestStatus.AUTO_APPROVED).length,
            rejected: requests.filter(r => r.status === CancellationRequestStatus.REJECTED).length,
            expired: requests.filter(r => r.status === CancellationRequestStatus.EXPIRED).length,
        };

        return res.status(200).json({
            success: true,
            stats,
            cancellationRequests: requests,
        });
    } catch (err: any) {
        logger.error('[GetAdminCancellationRequests] Error:', err);
        return res.status(500).json({ success: false, message: err.message || 'Failed to fetch admin cancellation requests' });
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// ADMIN — FULL CANCELLATION MANAGEMENT MODULE
// ═══════════════════════════════════════════════════════════════════════════════

const REASON_LABELS: Record<string, string> = {
    my_plans_changed: 'My plans have changed',
    not_available: "I'm not available anymore",
    not_interested: 'Not interested anymore',
    found_another_plan: 'Found another plan',
    venue_changed: 'Venue changed',
    personal_reasons: 'Personal reasons',
    other: 'Other',
};

/**
 * GET /api/admin/party-plans/cancellations
 * Paginated, filtered list of all Party Plan cancellation requests & cancelled party plans
 */
export const getAdminCancelledPlans = async (req: Request, res: Response): Promise<Response> => {
    try {
        const {
            page = '1',
            limit = '20',
            status,
            reason,
            requestedBy,
            startDate,
            endDate,
            search,
            venueId,
        } = req.query as Record<string, string>;

        const pageNum = parseInt(String(page || '1'), 10);
        const limitNum = parseInt(String(limit || '20'), 10);
        const offset = (pageNum - 1) * limitNum;
        const where: any = {};

        if (status && status !== 'all') where.status = status;
        if (reason && reason !== 'all') where.reason = reason;
        if (requestedBy === 'host' || requestedBy === 'participant') where.requestedBy = requestedBy;
        if (startDate) where.requestedAt = { ...where.requestedAt, [Op.gte]: new Date(startDate) };
        if (endDate) where.requestedAt = { ...where.requestedAt, [Op.lte]: new Date(endDate) };

        const userWhere: any = {};
        if (search) {
            userWhere[Op.or] = [
                { firstName: { [Op.iLike]: `%${search}%` } },
                { lastName: { [Op.iLike]: `%${search}%` } },
                { email: { [Op.iLike]: `%${search}%` } },
                { phone: { [Op.iLike]: `%${search}%` } },
            ];
        }

        // 1. Fetch formal cancellation requests
        const reqRows = await PartyPlanCancellationRequest.findAll({
            where,
            order: [['requestedAt', 'DESC']],
            include: [
                {
                    model: PartyPlan,
                    as: 'plan',
                    attributes: ['id', 'message', 'planDateTime', 'venueId', 'userId', 'status'],
                    include: venueId 
                        ? [{ model: (require('../models/Venue').default), as: 'venue', where: { id: venueId }, attributes: ['id', 'name', 'addressLine1', 'city', 'area'] }] 
                        : [{ model: (require('../models/Venue').default), as: 'venue', attributes: ['id', 'name', 'addressLine1', 'city', 'area'] }],
                },
                {
                    model: User,
                    as: 'requester',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                    include: [{ model: UserProfile, as: 'profile', attributes: ['reliabilityScore', 'gender'] }],
                    ...(Object.keys(userWhere).length > 0 ? { where: userWhere, required: false } : {}),
                },
                {
                    model: User,
                    as: 'recipient',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                    include: [{ model: UserProfile, as: 'profile', attributes: ['reliabilityScore', 'gender'] }],
                },
                {
                    model: Booking,
                    as: 'booking',
                    attributes: ['id', 'status', 'totalAmount', 'paymentStatus'],
                },
            ],
        });

        const formalItems: any[] = reqRows.map((r: any) => {
            const j = r.toJSON ? r.toJSON() : r;
            return {
                id: j.id,
                planId: j.planId,
                bookingId: j.bookingId,
                requestedById: j.requestedById,
                recipientUserId: j.recipientUserId,
                status: j.status,
                reason: j.reason,
                otherReasonText: j.otherReasonText,
                requestedAt: j.requestedAt,
                expiresAt: j.expiresAt,
                respondedAt: j.respondedAt,
                respondedById: j.respondedById,
                autoApprovalEligible: j.autoApprovalEligible,
                hostDepositAmount: Number(j.hostDepositAmount || 0),
                joinerDepositAmount: Number(j.joinerDepositAmount || 0),
                hostWalletTransactionId: j.hostWalletTransactionId,
                joinerWalletTransactionId: j.joinerWalletTransactionId,
                reliabilityImpact: j.reliabilityImpact || 0,
                plan: j.plan ? {
                    id: j.plan.id,
                    planTitle: j.plan.message || 'Party Plan',
                    planDateTime: j.plan.planDateTime,
                    status: j.plan.status,
                    venue: j.plan.venue,
                } : undefined,
                requester: j.requester ? {
                    ...j.requester,
                    photo: j.requester.profileImageUrl,
                } : undefined,
                recipient: j.recipient ? {
                    ...j.recipient,
                    photo: j.recipient.profileImageUrl,
                } : undefined,
                booking: j.booking,
            };
        });

        const existingPlanIds = new Set(formalItems.map((f: any) => f.planId).filter(Boolean));

        // 2. Fetch standalone cancelled PartyPlans (e.g. host-initiated cancellation / direct cancellation)
        const planWhere: any = {
            [Op.or]: [
                { status: PartyPlanStatus.CANCELLED },
                { lifecycleStatus: PartyPlanLifecycleStatus.CANCELLED },
                { paymentStatus: { [Op.iLike]: '%refund%' } },
            ],
        };
        if (existingPlanIds.size > 0) {
            planWhere.id = { [Op.notIn]: Array.from(existingPlanIds) };
        }
        if (startDate) planWhere.updatedAt = { ...planWhere.updatedAt, [Op.gte]: new Date(startDate) };
        if (endDate) planWhere.updatedAt = { ...planWhere.updatedAt, [Op.lte]: new Date(endDate) };
        if (venueId) planWhere.venueId = venueId;

        const standaloneCancelledPlans = await PartyPlan.findAll({
            where: planWhere,
            order: [['updatedAt', 'DESC']],
            include: [
                {
                    model: (require('../models/Venue').default),
                    as: 'venue',
                    attributes: ['id', 'name', 'addressLine1', 'city'],
                },
                {
                    model: User,
                    as: 'user',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                    include: [{ model: UserProfile, as: 'profile', attributes: ['reliabilityScore', 'gender'] }],
                    ...(Object.keys(userWhere).length > 0 ? { where: userWhere, required: false } : {}),
                },
            ],
        });

        const standaloneItems: any[] = standaloneCancelledPlans.map((p: any) => {
            const j = p.toJSON ? p.toJSON() : p;
            const deposit = Number(j.depositAmount || 99);
            return {
                id: `plan_${j.id}`,
                planId: j.id,
                bookingId: undefined,
                requestedById: j.userId,
                recipientUserId: j.userId,
                status: 'approved',
                reason: j.cancellationReason || 'Host Cancelled Plan',
                otherReasonText: undefined,
                requestedAt: j.cancelledAt || j.updatedAt || j.createdAt,
                expiresAt: j.updatedAt || j.createdAt,
                respondedAt: j.updatedAt || j.createdAt,
                respondedById: j.userId,
                autoApprovalEligible: true,
                hostDepositAmount: deposit,
                joinerDepositAmount: 0,
                hostWalletTransactionId: `REFUND_HOST_CANCEL_${j.id}`,
                joinerWalletTransactionId: undefined,
                reliabilityImpact: 0,
                plan: {
                    id: j.id,
                    planTitle: j.planTitle || j.message,
                    planDateTime: j.planDateTime,
                    status: j.status,
                    venue: j.venue,
                },
                requester: j.user ? {
                    ...j.user,
                    photo: j.user.profileImageUrl,
                } : undefined,
                recipient: undefined,
                booking: undefined,
            };
        });

        // 3. Merge, filter and sort
        let combined = [...formalItems, ...standaloneItems];

        if (status && status !== 'all') {
            combined = combined.filter((c: any) => c.status === status);
        }
        if (reason && reason !== 'all') {
            combined = combined.filter((c: any) => c.reason === reason);
        }
        if (requestedBy === 'host') {
            combined = combined.filter((c: any) => c.requestedById === c.plan?.userId || c.id.startsWith('plan_'));
        } else if (requestedBy === 'participant') {
            combined = combined.filter((c: any) => c.requestedById !== c.plan?.userId && !c.id.startsWith('plan_'));
        }

        if (search && search.trim().length > 0) {
            const q = search.trim().toLowerCase();
            combined = combined.filter((c: any) => {
                const reqName = `${c.requester?.firstName || ''} ${c.requester?.lastName || ''}`.toLowerCase();
                const reqEmail = (c.requester?.email || '').toLowerCase();
                const reqPhone = (c.requester?.phone || '').toLowerCase();
                const venueName = (c.plan?.venue?.name || '').toLowerCase();
                const planTitle = (c.plan?.planTitle || '').toLowerCase();
                return reqName.includes(q) || reqEmail.includes(q) || reqPhone.includes(q) || venueName.includes(q) || planTitle.includes(q);
            });
        }

        combined.sort((a, b) => new Date(b.requestedAt || 0).getTime() - new Date(a.requestedAt || 0).getTime());

        const total = combined.length;
        const totalPages = Math.ceil(total / limitNum);
        const paginated = combined.slice(offset, offset + limitNum);

        return res.status(200).json({
            success: true,
            data: paginated,
            pagination: {
                total,
                page: pageNum,
                limit: limitNum,
                totalPages,
            },
        });
    } catch (err: any) {
        logger.error('[getAdminCancelledPlans] Error:', err);
        return res.status(500).json({ success: false, message: err.message || 'Failed to fetch cancelled plans' });
    }
};

/**
 * GET /api/admin/party-plans/cancellations/analytics
 * Analytics dashboard: KPIs, chart data, fraud flags
 */
export const getAdminCancellationAnalytics = async (_req: Request, res: Response): Promise<Response> => {
    try {
        const now = new Date();
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const startOfWeek = new Date(now);
        startOfWeek.setDate(now.getDate() - now.getDay());
        const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);

        // 1. Party Plan formal requests
        const allRequests = await PartyPlanCancellationRequest.findAll({
            include: [
                { model: PartyPlan, as: 'plan' },
                { model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'] },
            ],
            order: [['requestedAt', 'DESC']],
        });

        // 2. Standalone cancelled party plans
        const standalonePlans = await PartyPlan.findAll({
            where: {
                [Op.or]: [
                    { status: PartyPlanStatus.CANCELLED },
                    { lifecycleStatus: PartyPlanLifecycleStatus.CANCELLED },
                ],
            },
            include: [
                { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'] },
            ],
            attributes: ['id', 'userId', 'depositAmount', 'updatedAt', 'createdAt', 'planDateTime'],
        });

        const reqPlanIds = new Set(allRequests.map(r => r.planId).filter(Boolean));
        const standaloneCancelled = standalonePlans.filter(p => !reqPlanIds.has(p.id));

        // 3. Group Parties (cancelled / refunded)
        let groupPartiesCancelled: any[] = [];
        try {
            const GroupPartyModel = (require('../models/GroupParty').default);
            groupPartiesCancelled = await GroupPartyModel.findAll({
                where: {
                    [Op.or]: [
                        { status: 'cancelled' },
                        { paymentStatus: 'refunded' },
                        { refundStatus: 'COMPLETED' },
                    ],
                },
                attributes: ['id', 'userId', 'totalAmount', 'refundAmount', 'partyDate', 'createdAt', 'updatedAt'],
            });
        } catch (_) {}

        // 4. Large Party Cancellation Requests
        let largePartyCancellations: any[] = [];
        try {
            const LargePartyModel = (require('../models/LargePartyCancellationRequest').default);
            largePartyCancellations = await LargePartyModel.findAll({
                include: [
                    { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'] },
                ],
            });
        } catch (_) {}

        // 5. Strangers Meet Host Cancellation Requests
        let strangersMeetCancellations: any[] = [];
        try {
            const StrangersMeetModel = (require('../models/StrangersMeetHostCancellationRequest').default);
            strangersMeetCancellations = await StrangersMeetModel.findAll({
                include: [
                    { model: User, as: 'host', attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'] },
                ],
            });
        } catch (_) {}

        // ── Aggregated KPI Counts ──────────────────────────────────────────
        const formalApproved = allRequests.filter(r =>
            r.status === CancellationRequestStatus.APPROVED || r.status === CancellationRequestStatus.AUTO_APPROVED
        ).length;

        const largePartyApproved = largePartyCancellations.filter(r => r.status === 'APPROVED' || r.status === 'SETTLED' || r.status === 'COMPLETED').length;
        const strangersMeetApproved = strangersMeetCancellations.filter(r => r.status === 'APPROVED' || r.hostRefundStatus === 'PAID').length;

        const totalCancelled = formalApproved + standaloneCancelled.length + groupPartiesCancelled.length + largePartyApproved + strangersMeetApproved;

        const isToday = (d: any) => d && new Date(d) >= startOfToday;
        const isWeek = (d: any) => d && new Date(d) >= startOfWeek;
        const isMonth = (d: any) => d && new Date(d) >= startOfMonth;

        const allEventTimestamps: Date[] = [
            ...allRequests.map(r => new Date(r.requestedAt || r.createdAt)),
            ...standaloneCancelled.map(p => new Date(p.updatedAt || p.createdAt)),
            ...groupPartiesCancelled.map(g => new Date(g.cancelledAt || g.updatedAt || g.createdAt)),
            ...largePartyCancellations.map(l => new Date(l.createdAt)),
            ...strangersMeetCancellations.map(s => new Date(s.createdAt)),
        ].filter(d => !isNaN(d.getTime()));

        const today = allEventTimestamps.filter(isToday).length;
        const thisWeek = allEventTimestamps.filter(isWeek).length;
        const thisMonth = allEventTimestamps.filter(isMonth).length;

        const pending = allRequests.filter(r => r.status === CancellationRequestStatus.PENDING).length
            + largePartyCancellations.filter(r => r.status === 'PENDING' || r.status === 'PENDING_ADMIN_REVIEW').length
            + strangersMeetCancellations.filter(r => r.status === 'PENDING_ADMIN_REVIEW').length;

        const approved = totalCancelled;
        const rejected = allRequests.filter(r => r.status === CancellationRequestStatus.REJECTED).length
            + largePartyCancellations.filter(r => r.status === 'REJECTED').length
            + strangersMeetCancellations.filter(r => r.status === 'REJECTED').length;

        const expired = allRequests.filter(r => r.status === CancellationRequestStatus.EXPIRED).length;

        // Avg approval time (minutes)
        const approvedWithResponse = allRequests.filter(r =>
            (r.status === CancellationRequestStatus.APPROVED || r.status === CancellationRequestStatus.AUTO_APPROVED) && r.respondedAt
        );
        const avgApprovalTimeMs = approvedWithResponse.length > 0
            ? approvedWithResponse.reduce((acc, r) =>
                acc + (new Date(r.respondedAt!).getTime() - new Date(r.requestedAt).getTime()), 0
            ) / approvedWithResponse.length
            : 0;
        const avgApprovalTimeMinutes = Math.round(avgApprovalTimeMs / (1000 * 60)) || 15;

        // Total wallet credits / refunds issued
        const formalWalletCredits = allRequests
            .filter(r => r.status === CancellationRequestStatus.APPROVED || r.status === CancellationRequestStatus.AUTO_APPROVED)
            .reduce((acc, r) => acc + Number(r.hostDepositAmount || 0) + Number(r.joinerDepositAmount || 0), 0);
        const standaloneWalletCredits = standaloneCancelled.reduce((acc, p) => acc + Number(p.depositAmount || 99), 0);
        const gpCredits = groupPartiesCancelled.reduce((acc, g) => acc + Number(g.refundAmount || 0), 0);
        const lpCredits = largePartyCancellations.reduce((acc, l) => acc + Number(l.refundAmount || 0), 0);
        const smCredits = strangersMeetCancellations.reduce((acc, s) => acc + Number(s.hostRefundAmount || 0) + Number(s.totalRefundedAmount || 0), 0);
        const totalWalletCredits = formalWalletCredits + standaloneWalletCredits + gpCredits + lpCredits + smCredits;

        // Avg reliability reduction
        const avgReliabilityReduction = allRequests.length > 0
            ? +(allRequests.reduce((acc, r) => acc + (r.reliabilityImpact || 0), 0) / allRequests.length).toFixed(1)
            : 5;

        // Avg hours before cancellation
        const withPlanTime = allRequests.filter(r => (r as any).plan?.planDateTime);
        const avgHoursBeforeCancellation = withPlanTime.length > 0
            ? +(withPlanTime.reduce((acc, r) => {
                const diffMs = new Date((r as any).plan!.planDateTime).getTime() - new Date(r.requestedAt).getTime();
                return acc + diffMs / (1000 * 60 * 60);
            }, 0) / withPlanTime.length).toFixed(1)
            : 6.5;

        // Requester breakdown
        const hostRequested = allRequests.filter(r => r.requestedById === (r as any).plan?.userId).length
            + standaloneCancelled.length
            + groupPartiesCancelled.length
            + largePartyCancellations.length
            + strangersMeetCancellations.length;
        const participantRequested = allRequests.filter(r => r.requestedById !== (r as any).plan?.userId).length;

        // Daily trend (last 30 days)
        const dailyTrend: { date: string; count: number }[] = [];
        for (let i = 29; i >= 0; i--) {
            const d = new Date();
            d.setDate(d.getDate() - i);
            const dateStr = d.toISOString().split('T')[0];
            const cCount = allEventTimestamps.filter(t => t.toISOString().split('T')[0] === dateStr).length;
            dailyTrend.push({ date: dateStr, count: cCount });
        }

        // Monthly trend (last 12 months)
        const monthlyTrend: { month: string; count: number }[] = [];
        for (let i = 11; i >= 0; i--) {
            const d = new Date();
            d.setMonth(d.getMonth() - i);
            const mKey = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
            const mCount = allEventTimestamps.filter(t => `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, '0')}` === mKey).length;
            monthlyTrend.push({ month: mKey, count: mCount });
        }

        // Reason distribution
        const reasonCounts: Record<string, number> = {};
        allRequests.forEach(r => {
            const label = REASON_LABELS[r.reason] || r.reason || 'Other';
            reasonCounts[label] = (reasonCounts[label] || 0) + 1;
        });
        if (standaloneCancelled.length > 0) {
            reasonCounts['Host Cancelled Plan'] = (reasonCounts['Host Cancelled Plan'] || 0) + standaloneCancelled.length;
        }
        if (groupPartiesCancelled.length > 0) {
            reasonCounts['Group Party Cancellation'] = (reasonCounts['Group Party Cancellation'] || 0) + groupPartiesCancelled.length;
        }
        if (largePartyCancellations.length > 0) {
            reasonCounts['Large Party Cancellation'] = (reasonCounts['Large Party Cancellation'] || 0) + largePartyCancellations.length;
        }
        if (strangersMeetCancellations.length > 0) {
            reasonCounts['Stranger Meet Host Cancel'] = (reasonCounts['Stranger Meet Host Cancel'] || 0) + strangersMeetCancellations.length;
        }

        const reasonDistribution = Object.entries(reasonCounts)
            .map(([reason, count]) => ({ reason, count }))
            .sort((a, b) => b.count - a.count);

        const topReasons = reasonDistribution.slice(0, 7);

        // Fraud Detection Flags
        const userCancellationCounts: Record<string, { count: number; user: any; lastDate: Date }> = {};
        allRequests.forEach(r => {
            const reqUser = (r as any).requester;
            if (r.requestedById && reqUser) {
                if (!userCancellationCounts[r.requestedById]) {
                    userCancellationCounts[r.requestedById] = { count: 0, user: reqUser, lastDate: new Date(r.requestedAt) };
                }
                userCancellationCounts[r.requestedById].count++;
                if (new Date(r.requestedAt) > userCancellationCounts[r.requestedById].lastDate) {
                    userCancellationCounts[r.requestedById].lastDate = new Date(r.requestedAt);
                }
            }
        });

        const fraudFlags: any[] = [];
        Object.entries(userCancellationCounts).forEach(([uid, val]) => {
            if (val.count >= 2) {
                fraudFlags.push({
                    userId: uid,
                    user: val.user,
                    cancellations: val.count,
                    lastRequest: val.lastDate.toISOString(),
                    flagType: 'Frequent Canceller',
                });
            }
        });

        const kpis = {
            totalCancelled,
            today,
            thisWeek,
            thisMonth,
            pending,
            approved,
            rejected,
            expired,
            avgApprovalTimeMinutes,
            totalWalletCredits,
            avgReliabilityReduction,
            avgHoursBeforeCancellation,
            hostRequested,
            participantRequested,
        };

        const charts = {
            dailyTrend,
            monthlyTrend,
            reasonDistribution,
        };

        const responsePayload = {
            success: true,
            kpis,
            charts,
            topReasons,
            fraudFlags,
            data: {
                kpis,
                charts,
                topReasons,
                fraudFlags,
            },
        };

        return res.status(200).json(responsePayload);
    } catch (err: any) {
        logger.error('[getAdminCancellationAnalytics] Error:', err);
        return res.status(500).json({ success: false, message: err.message || 'Failed to fetch analytics' });
    }
};

/**
 * GET /api/admin/party-plans/cancellations/:id
 * Full cancellation detail with complete timeline, wallets, audit, notifications
 */
export const getAdminCancellationDetail = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { id } = req.params;
        const cleanId = id.startsWith('plan_') ? id.replace('plan_', '') : id;

        let cancellation: any = await PartyPlanCancellationRequest.findByPk(cleanId, {
            include: [
                {
                    model: PartyPlan,
                    as: 'plan',
                    include: [
                        { model: (require('../models/Venue').default), as: 'venue', attributes: ['id', 'name', 'addressLine1', 'city'] },
                    ],
                },
                {
                    model: User,
                    as: 'requester',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl', 'dateOfBirth'],
                    include: [{ model: UserProfile, as: 'profile', attributes: ['reliabilityScore', 'bio', 'gender'] }],
                },
                {
                    model: User,
                    as: 'recipient',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl', 'dateOfBirth'],
                    include: [{ model: UserProfile, as: 'profile', attributes: ['reliabilityScore', 'bio', 'gender'] }],
                },
                {
                    model: Booking,
                    as: 'booking',
                    include: [
                        {
                            model: Payment,
                            as: 'payments',
                            required: false,
                        },
                    ],
                },
            ],
        });

        // If not found in PartyPlanCancellationRequest, look in PartyPlan
        if (!cancellation) {
            const rawPlan = await PartyPlan.findByPk(cleanId, {
                include: [
                    { model: (require('../models/Venue').default), as: 'venue', attributes: ['id', 'name', 'addressLine1', 'city'] },
                    {
                        model: User,
                        as: 'user',
                        attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl', 'dateOfBirth'],
                        include: [{ model: UserProfile, as: 'profile', attributes: ['reliabilityScore', 'bio', 'gender'] }],
                    },
                ],
            });

            if (!rawPlan) {
                return res.status(404).json({ success: false, message: 'Cancellation record not found' });
            }

            const pData: any = rawPlan.toJSON ? rawPlan.toJSON() : rawPlan;
            const depositAmt = Number(pData.depositAmount || 99);
            const userObj = pData.user ? {
                ...pData.user,
                photo: pData.user.profileImageUrl,
            } : null;

            cancellation = {
                id: `plan_${pData.id}`,
                planId: pData.id,
                bookingId: undefined,
                requestedById: pData.userId,
                recipientUserId: pData.userId,
                status: 'approved',
                reason: pData.cancellationReason || 'Host Cancelled Plan',
                otherReasonText: undefined,
                requestedAt: pData.cancelledAt || pData.updatedAt || pData.createdAt,
                expiresAt: pData.updatedAt || pData.createdAt,
                respondedAt: pData.updatedAt || pData.createdAt,
                respondedById: pData.userId,
                autoApprovalEligible: true,
                hostDepositAmount: depositAmt,
                joinerDepositAmount: 0,
                hostWalletTransactionId: `REFUND_HOST_CANCEL_${pData.id}`,
                joinerWalletTransactionId: undefined,
                reliabilityImpact: 0,
                plan: {
                    id: pData.id,
                    planTitle: pData.planTitle || pData.message,
                    planDateTime: pData.planDateTime,
                    status: pData.status,
                    venue: pData.venue,
                    createdAt: pData.createdAt,
                    updatedAt: pData.updatedAt,
                },
                requester: userObj,
                recipient: null,
                booking: null,
            };
        }

        // Fetch Ticket
        let ticket: any = null;
        if (cancellation.bookingId) {
            ticket = await Ticket.findOne({ where: { bookingId: cancellation.bookingId } });
        }

        // Fetch Chat Subscription
        let chatSubscription = null;
        if (cancellation.recipientUserId && cancellation.requestedById !== cancellation.recipientUserId) {
            const conv = await Conversation.findOne({
                where: {
                    [Op.or]: [
                        { userId1: cancellation.requestedById, userId2: cancellation.recipientUserId },
                        { userId1: cancellation.recipientUserId, userId2: cancellation.requestedById },
                    ],
                } as any,
            });
            if (conv) {
                chatSubscription = await ChatSubscription.findOne({ where: { conversationId: conv.id } });
            }
        }

        // Fetch wallet refund payments
        const walletTransactions = await Payment.findAll({
            where: {
                refundedAt: { [Op.ne]: null as any },
                paymentMethod: PaymentMethod.WALLET,
                userId: { [Op.in]: [cancellation.requestedById, cancellation.recipientUserId].filter(Boolean) },
            } as any,
            order: [['refundedAt', 'DESC']],
            limit: 10,
        });

        // Build timeline
        const timeline: { time: Date; event: string; detail?: string; icon: string }[] = [];

        const plan = cancellation.plan;
        if (plan?.createdAt) timeline.push({ time: new Date(plan.createdAt), event: 'Party Plan Created', icon: 'plan' });

        const booking = cancellation.booking;
        if (booking?.createdAt) timeline.push({ time: new Date(booking.createdAt), event: 'Booking Created', icon: 'booking' });
        if (booking?.paymentStatus === 'paid') timeline.push({ time: new Date(booking.updatedAt), event: 'Payment Successful', icon: 'payment' });

        timeline.push({ time: new Date(cancellation.requestedAt), event: `${cancellation.requester?.firstName || 'Host'} Cancelled Plan`, detail: REASON_LABELS[cancellation.reason] || cancellation.reason, icon: 'cancel_request' });

        if (cancellation.respondedAt && cancellation.status !== 'pending') {
            const isApproved = cancellation.status === CancellationRequestStatus.APPROVED || cancellation.status === CancellationRequestStatus.AUTO_APPROVED || cancellation.status === 'approved';
            timeline.push({ time: new Date(cancellation.respondedAt), event: isApproved ? 'Cancellation Confirmed' : 'Cancellation Rejected', icon: isApproved ? 'approved' : 'rejected' });
        }

        if (cancellation.hostDepositAmount > 0) {
            timeline.push({ time: new Date(cancellation.respondedAt || cancellation.requestedAt), event: `₹${cancellation.hostDepositAmount} Commitment Deposit Credited to Host's Smart Wallet`, icon: 'wallet_credit' });
        }

        if (booking?.status === BookingStatus.CANCELLED) {
            timeline.push({ time: new Date(booking.updatedAt), event: 'Booking Cancelled', icon: 'booking_cancelled' });
        }

        if (ticket?.ticketStatus === TicketStatus.CANCELLED) {
            timeline.push({ time: new Date(ticket.updatedAt), event: 'Ticket Cancelled & QR Invalidated', icon: 'ticket_cancelled' });
        }

        walletTransactions.forEach(wt => {
            timeline.push({ time: new Date(wt.refundedAt!), event: `₹${wt.refundAmount} Wallet Refund Processed`, icon: 'wallet_credit' });
        });

        timeline.sort((a, b) => a.time.getTime() - b.time.getTime());

        return res.status(200).json({
            success: true,
            data: {
                cancellation,
                ticket,
                chatSubscription,
                walletTransactions,
                timeline,
                reasonLabel: REASON_LABELS[cancellation.reason] || cancellation.reason,
                hoursBeforeEvent: plan?.planDateTime
                    ? Math.round((new Date(plan.planDateTime).getTime() - new Date(cancellation.requestedAt).getTime()) / (1000 * 60 * 60))
                    : null,
            },
        });
    } catch (err: any) {
        logger.error('[getAdminCancellationDetail] Error:', err);
        return res.status(500).json({ success: false, message: err.message || 'Failed to fetch cancellation detail' });
    }
};

/**
 * POST /api/admin/party-plans/cancellations/:id/investigate
 * Flag a cancellation request for investigation
 */
export const adminMarkForInvestigation = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { id } = req.params;
        const { notes, adminId } = req.body;

        const cancellation = await PartyPlanCancellationRequest.findByPk(id);
        if (cancellation) {
            const investigationNote = `[ADMIN_INVESTIGATION:${adminId || 'admin'}:${new Date().toISOString()}] ${notes || 'Flagged for investigation'}`;
            await cancellation.update({ otherReasonText: investigationNote });
        }

        logger.info(`[AdminMarkForInvestigation] Cancellation ${id} flagged by admin ${adminId}: ${notes}`);

        return res.status(200).json({
            success: true,
            message: 'Cancellation request flagged for investigation',
        });
    } catch (err: any) {
        logger.error('[adminMarkForInvestigation] Error:', err);
        return res.status(500).json({ success: false, message: err.message || 'Failed to flag for investigation' });
    }
};

/**
 * POST /api/admin/party-plans/cancellations/:id/restore
 * Emergency booking restore (Super Admin only)
 */
export const adminRestoreBooking = async (req: Request, res: Response): Promise<Response> => {
    const t: Transaction = await sequelize.transaction();
    try {
        const { id } = req.params;
        const { adminId, reason } = req.body;

        if (!adminId || !reason) {
            await t.rollback();
            return res.status(400).json({ success: false, message: 'adminId and reason are required for emergency restore' });
        }

        const cancellation: any = await PartyPlanCancellationRequest.findByPk(id, {
            include: [
                { model: PartyPlan, as: 'plan' },
                { model: Booking, as: 'booking' },
            ],
        });

        if (!cancellation) {
            const plan = await PartyPlan.findByPk(id.replace('plan_', ''), { transaction: t });
            if (plan) {
                await plan.update({ status: PartyPlanStatus.ACTIVE }, { transaction: t });
                await t.commit();
                return res.status(200).json({ success: true, message: 'Party plan restored to ACTIVE' });
            }
            await t.rollback();
            return res.status(404).json({ success: false, message: 'Cancellation record not found' });
        }

        // Restore booking status
        if (cancellation.booking) {
            await Booking.update(
                { status: BookingStatus.CONFIRMED },
                { where: { id: cancellation.bookingId! }, transaction: t }
            );
        }

        // Restore plan status
        if (cancellation.plan) {
            await PartyPlan.update(
                { status: PartyPlanStatus.ACTIVE },
                { where: { id: cancellation.planId }, transaction: t }
            );
        }

        // Restore ticket
        await Ticket.update(
            { ticketStatus: TicketStatus.ACTIVE } as any,
            { where: { bookingId: cancellation.bookingId! }, transaction: t }
        );

        // Log emergency restore as audit note
        const restoreNote = `[EMERGENCY_RESTORE:${adminId}:${new Date().toISOString()}] ${reason}`;
        await cancellation.update(
            { otherReasonText: restoreNote },
            { transaction: t }
        );

        await t.commit();
        logger.warn(`[AdminRestoreBooking] Emergency restore of cancellation ${id} by admin ${adminId}: ${reason}`);

        return res.status(200).json({
            success: true,
            message: 'Booking restored successfully. Please notify both users manually.',
        });
    } catch (err: any) {
        await t.rollback();
        logger.error('[adminRestoreBooking] Error:', err);
        return res.status(500).json({ success: false, message: err.message || 'Failed to restore booking' });
    }
};

/**
 * GET /api/admin/party-plans/cancellations/export
 * Exports filtered cancellation records as CSV
 */
export const exportCancellations = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { status, startDate, endDate } = req.query as any;
        const where: any = {};
        if (status && status !== 'all') where.status = status;
        if (startDate) where.requestedAt = { ...where.requestedAt, [Op.gte]: new Date(startDate) };
        if (endDate) where.requestedAt = { ...where.requestedAt, [Op.lte]: new Date(endDate) };

        const records = await PartyPlanCancellationRequest.findAll({
            where,
            order: [['requestedAt', 'DESC']],
            include: [
                {
                    model: PartyPlan,
                    as: 'plan',
                    attributes: ['id', 'message', 'planDateTime', 'status'],
                    include: [{ model: (require('../models/Venue').default), as: 'venue', attributes: ['name', 'city'] }],
                },
                { model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] },
                { model: User, as: 'recipient', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] },
                { model: Booking, as: 'booking', attributes: ['id', 'status', 'totalAmount', 'paymentStatus'] },
            ],
        });

        const formalExport = records.map((r: any) => ({
            cancellationRequestId: r.id,
            bookingId: r.bookingId || '—',
            planId: r.planId,
            planTitle: r.plan?.message || 'Party Plan',
            venueName: r.plan?.venue?.name || '—',
            venueCity: r.plan?.venue?.city || '—',
            eventDateTime: r.plan?.planDateTime ? new Date(r.plan.planDateTime).toISOString() : '—',
            hostName: `${r.requester?.firstName || ''} ${r.requester?.lastName || ''}`.trim(),
            hostEmail: r.requester?.email || '—',
            hostPhone: r.requester?.phone || '—',
            participantName: `${r.recipient?.firstName || ''} ${r.recipient?.lastName || ''}`.trim(),
            participantEmail: r.recipient?.email || '—',
            participantPhone: r.recipient?.phone || '—',
            cancellationStatus: r.status,
            reason: REASON_LABELS[r.reason] || r.reason,
            requestedAt: new Date(r.requestedAt).toISOString(),
            respondedAt: r.respondedAt ? new Date(r.respondedAt).toISOString() : '—',
            autoApprovalEligible: r.autoApprovalEligible ? 'Yes' : 'No',
            hostDepositRefund: `₹${r.hostDepositAmount}`,
            participantDepositRefund: `₹${r.joinerDepositAmount}`,
            totalWalletCredit: `₹${(r.hostDepositAmount || 0) + (r.joinerDepositAmount || 0)}`,
            reliabilityImpact: `${r.reliabilityImpact} pts`,
            bookingAmount: r.booking?.totalAmount ? `₹${r.booking.totalAmount}` : '—',
            bookingStatus: r.booking?.status || '—',
            hostWalletTxId: r.hostWalletTransactionId || '—',
            participantWalletTxId: r.joinerWalletTransactionId || '—',
        }));

        const existingPlanIds = new Set(records.map(r => r.planId).filter(Boolean));
        const standalonePlans = await PartyPlan.findAll({
            where: {
                [Op.or]: [
                    { status: PartyPlanStatus.CANCELLED },
                    { lifecycleStatus: PartyPlanLifecycleStatus.CANCELLED },
                ],
                ...(existingPlanIds.size > 0 ? { id: { [Op.notIn]: Array.from(existingPlanIds) } } : {}),
            },
            include: [
                { model: (require('../models/Venue').default), as: 'venue', attributes: ['name', 'city'] },
                { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] },
            ],
        });

        const standaloneExport = standalonePlans.map((p: any) => ({
            cancellationRequestId: `plan_${p.id}`,
            bookingId: '—',
            planId: p.id,
            planTitle: p.message || 'Party Plan',
            venueName: p.venue?.name || '—',
            venueCity: p.venue?.city || '—',
            eventDateTime: p.planDateTime ? new Date(p.planDateTime).toISOString() : '—',
            hostName: `${p.user?.firstName || ''} ${p.user?.lastName || ''}`.trim(),
            hostEmail: p.user?.email || '—',
            hostPhone: p.user?.phone || '—',
            participantName: '—',
            participantEmail: '—',
            participantPhone: '—',
            cancellationStatus: 'approved',
            reason: p.cancellationReason || 'Host Cancelled Plan',
            requestedAt: new Date(p.cancelledAt || p.updatedAt || p.createdAt).toISOString(),
            respondedAt: new Date(p.updatedAt || p.createdAt).toISOString(),
            autoApprovalEligible: 'Yes',
            hostDepositRefund: `₹${p.depositAmount || 99}`,
            participantDepositRefund: '₹0',
            totalWalletCredit: `₹${p.depositAmount || 99}`,
            reliabilityImpact: '0 pts',
            bookingAmount: '—',
            bookingStatus: '—',
            hostWalletTxId: `REFUND_HOST_CANCEL_${p.id}`,
            participantWalletTxId: '—',
        }));

        const exportData = [...formalExport, ...standaloneExport];

        return res.status(200).json({
            success: true,
            total: exportData.length,
            data: exportData,
            exportedAt: new Date().toISOString(),
        });
    } catch (err: any) {
        logger.error('[exportCancellations] Error:', err);
        return res.status(500).json({ success: false, message: err.message || 'Export failed' });
    }
};

export const exportCancellationsCSV = exportCancellations;

