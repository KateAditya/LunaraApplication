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
import { logger } from '../config/logger';

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
                    io.emit('live_feed_update', { type: 'party_plan_cancelled', planId: plan.id });
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
            // Store the ACTUAL commitment deposit amounts, not a hardcoded fallback
            hostDepositAmount: Number(plan.depositAmount) || 99.00,
            joinerDepositAmount: 99.00,   // Joiner commitment deposit is always ₹99
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
                    planId: plan.id,
                    requestId: cancellationRequest.id,
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

            // Real-time socket notification & live feed card update
            const { io } = require('../server');
            if (io) {
                io.to(`user_${recipientUserId}`).emit('party_plan_cancellation_requested', {
                    planId: plan.id,
                    requestId: cancellationRequest.id,
                    requestedById: userId,
                    recipientUserId,
                    requesterName,
                    reason: cancellationRequest.reason,
                    otherReasonText: cancellationRequest.otherReasonText,
                    requestedAt: cancellationRequest.requestedAt,
                });
                io.emit('live_feed_update', {
                    type: 'party_plan_cancellation_requested',
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
        const planId = req.params.id;
        const userId = req.body.userId || (req as any).user?.id;
        const { requestId, action } = req.body;

        if (!requestId || !action || !['approve', 'reject'].includes(action)) {
            return res.status(400).json({ success: false, message: 'requestId and valid action (approve/reject) are required' });
        }

        const cancellationRequest = await PartyPlanCancellationRequest.findOne({
            where: { id: requestId, planId },
        });

        if (!cancellationRequest) {
            return res.status(404).json({ success: false, message: 'Cancellation request not found' });
        }

        if (cancellationRequest.status !== CancellationRequestStatus.PENDING) {
            return res.status(400).json({ success: false, message: `Cancellation request is already ${cancellationRequest.status}` });
        }

        if (cancellationRequest.recipientUserId !== userId) {
            return res.status(403).json({ success: false, message: 'Only the recipient of the cancellation request can approve or reject it.' });
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

            // Notify Requester
            try {
                const recipientUser = await User.findByPk(userId);
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

                const requester = await User.findByPk(cancellationRequest.requestedById);
                if (requester?.fcmToken) {
                    await sendMulticastPushNotification([requester.fcmToken], {
                        title: 'Cancellation Request Declined 🛡️',
                        body: `Your cancellation request was declined. The Party Plan remains confirmed.`,
                        data: { type: 'party_plan_cancellation_declined', planId: plan.id },
                    });
                }

                const { io } = require('../server');
                if (io) {
                    io.to(`user_${cancellationRequest.requestedById}`).emit('party_plan_cancellation_declined', {
                        planId: plan.id,
                        requestId: cancellationRequest.id,
                    });
                    io.emit('live_feed_update', {
                        type: 'party_plan_cancellation_declined',
                        planId: plan.id,
                    });
                }
            } catch (notifErr: any) {
                logger.warn('[RespondToCancellationRequest] Rejection notification warning:', notifErr.message);
            }

            return res.status(200).json({
                success: true,
                message: 'Cancellation request rejected. Party Plan remains confirmed.',
                cancellationRequest,
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

                for (const payment of payments) {
                    await payment.update({
                        status: PaymentStatus.REFUNDED,
                        refundAmount: payment.amount,
                        refundedAt: new Date(),
                    }, { transaction: t });
                }
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
                for (const ticket of tickets) {
                    await ticket.update({
                        ticketStatus: TicketStatus.CANCELLED,
                        cancelledAt: new Date(),
                        qrToken: `VOID_${ticket.qrToken}`,
                    }, { transaction: t });
                }
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
            const hostDeposit = Number(cancellationRequest.hostDepositAmount) || 99.00;
            const joinerDeposit = Number(cancellationRequest.joinerDepositAmount) || 99.00;

            const hostCreditRef  = `PARTY_PLAN_CANCEL_CREDIT_HOST_${lockedPlan.id}`;
            const joinerCreditRef = `PARTY_PLAN_CANCEL_CREDIT_JOINER_${lockedPlan.id}_${joinerId}`;

            let hostWalletTxId: string | null = null;
            let joinerWalletTxId: string | null = null;

            try {
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
                logger.error('[CancellationApprove] Host creditRefund error:', hostErr);
            }

            try {
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
                logger.error('[CancellationApprove] Joiner creditRefund error:', joinerErr);
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

            // ─────────────────────────────────────────────────────────────────
            // 10. Post-Approval Notifications + Socket Events (async, post-commit)
            // idempotencyKey prevents duplicate DB notification rows on retry.
            // ─────────────────────────────────────────────────────────────────
            setImmediate(async () => {
                try {
                    const hostUser = await User.findByPk(lockedPlan.userId);
                    const joinerUser = await User.findByPk(joinerId);

                    const hostBody = `Party Plan cancelled by mutual agreement. Your ₹${hostDeposit} Commitment Deposit has been credited to your Lunara Wallet.`;
                    const joinerBody = `Party Plan cancelled by mutual agreement. Your ₹${joinerDeposit} Commitment Deposit has been credited to your Lunara Wallet.`;

                    await NotificationService.dispatch({
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
                    });

                    await NotificationService.dispatch({
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
                    });

                    // FCM push to both
                    const tokens = [hostUser?.fcmToken, joinerUser?.fcmToken].filter(t => t && t.trim() !== '') as string[];
                    if (tokens.length > 0) {
                        await sendMulticastPushNotification(tokens, {
                            title: 'Party Plan Cancelled 💔',
                            body: 'Commitment Deposit has been credited to your Lunara Wallet.',
                            data: { type: 'party_plan_cancelled', planId: lockedPlan.id },
                        });
                    }

                    // Socket events — live feed update
                    const { io } = require('../server');
                    io.to(`user_${lockedPlan.userId}`).emit('party_plan_cancelled', {
                        planId: lockedPlan.id,
                        mutualCancellation: true,
                        walletCredited: hostDeposit,
                    });
                    io.to(`user_${joinerId}`).emit('party_plan_cancelled', {
                        planId: lockedPlan.id,
                        mutualCancellation: true,
                        walletCredited: joinerDeposit,
                    });
                    // Remove from public live feed
                    io.emit('party_plan_deleted', { planId: lockedPlan.id });
                } catch (asyncErr: any) {
                    logger.warn('[CancellationApprove] Async notification error:', asyncErr.message);
                }
            });

            return res.status(200).json({
                success: true,
                message: `Party Plan cancelled by mutual agreement. Commitment deposits have been credited to both users' Lunara Wallets.`,
                cancellationRequest,
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
 * Paginated, filtered list of all Party Plan cancellation requests
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

        const { count, rows } = await PartyPlanCancellationRequest.findAndCountAll({
            where,
            order: [['requestedAt', 'DESC']],
            limit: limitNum,
            offset,
            include: [
                {
                    model: PartyPlan,
                    as: 'plan',
                    attributes: ['id', 'planTitle', 'planDateTime', 'venueId', 'userId', 'status'],
                    include: venueId ? [{ model: (require('../models/Venue').default), as: 'venue', where: { id: venueId } }] : [],
                },
                {
                    model: User,
                    as: 'requester',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                    include: [{ model: UserProfile, as: 'profile', attributes: ['reliabilityScore'] }],
                    ...(Object.keys(userWhere).length > 0 ? { where: userWhere, required: false } : {}),
                },
                {
                    model: User,
                    as: 'recipient',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                    include: [{ model: UserProfile, as: 'profile', attributes: ['reliabilityScore'] }],
                },
                {
                    model: Booking,
                    as: 'booking',
                    attributes: ['id', 'status', 'totalAmount', 'paymentStatus'],
                },
            ],
            distinct: true,
        });

        const totalPages = Math.ceil(count / limitNum);

        return res.status(200).json({
            success: true,
            data: rows,
            pagination: {
                total: count,
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

        const allRequests = await PartyPlanCancellationRequest.findAll({
            include: [
                {
                    model: User,
                    as: 'requester',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                },
                {
                    model: User,
                    as: 'recipient',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                },
                {
                    model: PartyPlan,
                    as: 'plan',
                    attributes: ['id', 'planTitle', 'planDateTime', 'venueId'],
                },
            ],
            order: [['requestedAt', 'DESC']],
        });

        const totalCancelled = allRequests.filter(r =>
            r.status === CancellationRequestStatus.APPROVED || r.status === CancellationRequestStatus.AUTO_APPROVED
        ).length;

        const today = allRequests.filter(r => new Date(r.requestedAt) >= startOfToday).length;
        const thisWeek = allRequests.filter(r => new Date(r.requestedAt) >= startOfWeek).length;
        const thisMonth = allRequests.filter(r => new Date(r.requestedAt) >= startOfMonth).length;
        const pending = allRequests.filter(r => r.status === CancellationRequestStatus.PENDING).length;
        const approved = allRequests.filter(r =>
            r.status === CancellationRequestStatus.APPROVED || r.status === CancellationRequestStatus.AUTO_APPROVED
        ).length;
        const rejected = allRequests.filter(r => r.status === CancellationRequestStatus.REJECTED).length;
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
        const avgApprovalTimeMinutes = Math.round(avgApprovalTimeMs / (1000 * 60));

        // Total wallet credits issued
        const totalWalletCredits = allRequests
            .filter(r => r.status === CancellationRequestStatus.APPROVED || r.status === CancellationRequestStatus.AUTO_APPROVED)
            .reduce((acc, r) => acc + (r.hostDepositAmount || 0) + (r.joinerDepositAmount || 0), 0);

        // Avg reliability deduction
        const avgReliabilityReduction = allRequests
            .filter(r => r.status === CancellationRequestStatus.APPROVED || r.status === CancellationRequestStatus.AUTO_APPROVED)
            .reduce((acc, r) => acc + Math.abs(r.reliabilityImpact || 0), 0) / Math.max(approved, 1);

        // Reason distribution
        const reasonCounts: Record<string, number> = {};
        allRequests.forEach(r => {
            const label = REASON_LABELS[r.reason] || r.reason;
            reasonCounts[label] = (reasonCounts[label] || 0) + 1;
        });
        const reasonDistribution = Object.entries(reasonCounts).map(([reason, count]) => ({ reason, count })).sort((a, b) => b.count - a.count);

        // Daily trend (last 30 days)
        const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
        const recentRequests = allRequests.filter(r => new Date(r.requestedAt) >= thirtyDaysAgo);
        const dailyTrend: Record<string, number> = {};
        recentRequests.forEach(r => {
            const dateKey = new Date(r.requestedAt).toISOString().split('T')[0];
            dailyTrend[dateKey] = (dailyTrend[dateKey] || 0) + 1;
        });
        const dailyTrendArr = Object.entries(dailyTrend).map(([date, count]) => ({ date, count })).sort((a, b) => a.date.localeCompare(b.date));

        // Monthly trend (last 12 months)
        const monthlyTrend: Record<string, number> = {};
        allRequests.forEach(r => {
            const d = new Date(r.requestedAt);
            const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
            monthlyTrend[key] = (monthlyTrend[key] || 0) + 1;
        });
        const monthlyTrendArr = Object.entries(monthlyTrend).map(([month, count]) => ({ month, count })).sort((a, b) => a.month.localeCompare(b.month)).slice(-12);

        // Host vs participant ratio
        const hostRequested = allRequests.filter(r => (r as any).requestedByHost === true).length;
        const participantRequested = allRequests.length - hostRequested;

        // Avg hours before cancellation (difference between requestedAt and planDateTime)
        const avgHoursBeforeCancellation = (() => {
            const withPlan = allRequests.filter(r => (r as any).plan?.planDateTime);
            if (withPlan.length === 0) return 0;
            const total = withPlan.reduce((acc, r) => {
                const planDt = new Date((r as any).plan.planDateTime).getTime();
                const reqDt = new Date(r.requestedAt).getTime();
                return acc + Math.max(0, (planDt - reqDt) / (1000 * 60 * 60));
            }, 0);
            return Math.round(total / withPlan.length);
        })();

        // ── Fraud Detection ──────────────────────────────────────────────────
        // Users with >2 cancellations in last 30 days
        const requestorCounts: Record<string, { count: number; user: any; lastRequest: Date }> = {};
        recentRequests.forEach(r => {
            const uid = r.requestedById;
            if (!requestorCounts[uid]) {
                requestorCounts[uid] = { count: 0, user: (r as any).requester, lastRequest: new Date(r.requestedAt) };
            }
            requestorCounts[uid].count++;
            if (new Date(r.requestedAt) > requestorCounts[uid].lastRequest) {
                requestorCounts[uid].lastRequest = new Date(r.requestedAt);
            }
        });
        const frequentCancellers = Object.entries(requestorCounts)
            .filter(([, v]) => v.count >= 3)
            .map(([userId, v]) => ({ userId, cancellations: v.count, user: v.user, lastRequest: v.lastRequest, flagType: 'Frequent Canceller' }));

        // Last-minute cancellations (< 6 hours before event) among recent
        const lastMinuteCancellers: any[] = [];
        recentRequests.forEach(r => {
            const plan = (r as any).plan;
            if (!plan?.planDateTime) return;
            const hoursRemaining = (new Date(plan.planDateTime).getTime() - new Date(r.requestedAt).getTime()) / (1000 * 60 * 60);
            if (hoursRemaining < 6) {
                lastMinuteCancellers.push({
                    userId: r.requestedById,
                    user: (r as any).requester,
                    requestId: r.id,
                    hoursRemaining: Math.round(hoursRemaining),
                    flagType: 'Last-Minute Cancellation',
                });
            }
        });

        const fraudFlags = [...frequentCancellers, ...lastMinuteCancellers].slice(0, 30);

        return res.status(200).json({
            success: true,
            kpis: {
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
                avgReliabilityReduction: Math.round(avgReliabilityReduction * 10) / 10,
                avgHoursBeforeCancellation,
                hostRequested,
                participantRequested,
            },
            charts: {
                dailyTrend: dailyTrendArr,
                monthlyTrend: monthlyTrendArr,
                reasonDistribution,
            },
            topReasons: reasonDistribution.slice(0, 7),
            fraudFlags,
        });
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

        const cancellation: any = await PartyPlanCancellationRequest.findByPk(id, {
            include: [
                {
                    model: PartyPlan,
                    as: 'plan',
                    include: [
                        { model: (require('../models/Venue').default), as: 'venue', attributes: ['id', 'name', 'addressLine1', 'city', 'imageUrl'] },
                    ],
                },
                {
                    model: User,
                    as: 'requester',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl', 'dateOfBirth', 'gender'],
                    include: [{ model: UserProfile, as: 'profile', attributes: ['reliabilityScore', 'bio'] }],
                },
                {
                    model: User,
                    as: 'recipient',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl', 'dateOfBirth', 'gender'],
                    include: [{ model: UserProfile, as: 'profile', attributes: ['reliabilityScore', 'bio'] }],
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

        if (!cancellation) {
            return res.status(404).json({ success: false, message: 'Cancellation request not found' });
        }

        // Fetch Ticket
        let ticket: any = null;
        if (cancellation.bookingId) {
            ticket = await Ticket.findOne({ where: { bookingId: cancellation.bookingId } });
        }

        // Fetch Chat Subscription
        let chatSubscription = null;
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

        // Fetch wallet refund payments
        const walletTransactions = await Payment.findAll({
            where: {
                refundedAt: { [Op.ne]: null as any },
                paymentMethod: PaymentMethod.WALLET,
                userId: { [Op.in]: [cancellation.requestedById, cancellation.recipientUserId] },
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

        if (plan?.status !== PartyPlanStatus.CANCELLED) {
            timeline.push({ time: new Date(plan?.updatedAt || cancellation.requestedAt), event: 'Party Plan Confirmed', icon: 'confirmed' });
        }

        timeline.push({ time: new Date(cancellation.requestedAt), event: `${cancellation.requester?.firstName || 'User'} Requested Cancellation`, detail: REASON_LABELS[cancellation.reason] || cancellation.reason, icon: 'cancel_request' });

        if (cancellation.respondedAt) {
            const isApproved = cancellation.status === CancellationRequestStatus.APPROVED || cancellation.status === CancellationRequestStatus.AUTO_APPROVED;
            timeline.push({ time: new Date(cancellation.respondedAt), event: isApproved ? 'Cancellation Approved' : 'Cancellation Rejected', icon: isApproved ? 'approved' : 'rejected' });
        }

        if (cancellation.status === CancellationRequestStatus.AUTO_APPROVED) {
            timeline.push({ time: new Date(cancellation.respondedAt || cancellation.expiresAt), event: 'Auto-Approved (24h Rule)', icon: 'auto_approved' });
        }

        if (booking?.status === BookingStatus.CANCELLED) {
            timeline.push({ time: new Date(booking.updatedAt), event: 'Booking Cancelled', icon: 'booking_cancelled' });
        }

        if (ticket?.ticketStatus === TicketStatus.CANCELLED) {
            timeline.push({ time: new Date(ticket.updatedAt), event: 'Ticket Cancelled & QR Invalidated', icon: 'ticket_cancelled' });
        }

        walletTransactions.forEach(wt => {
            timeline.push({ time: new Date(wt.refundedAt!), event: `₹${wt.refundAmount} Commitment Deposit Credited to ${wt.userId === cancellation.requestedById ? cancellation.requester?.firstName : cancellation.recipient?.firstName}'s Wallet`, icon: 'wallet_credit' });
        });

        if (chatSubscription?.status === ChatSubscriptionStatus.EXPIRED) {
            timeline.push({ time: new Date(chatSubscription.updatedAt), event: 'Chat Locked (Read-Only)', icon: 'chat_locked' });
        }

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
        if (!cancellation) {
            return res.status(404).json({ success: false, message: 'Cancellation request not found' });
        }

        // Store investigation flag in otherReasonText as a prefixed audit note
        const investigationNote = `[ADMIN_INVESTIGATION:${adminId || 'admin'}:${new Date().toISOString()}] ${notes || 'Flagged for investigation'}`;
        await cancellation.update({
            otherReasonText: investigationNote,
        });

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
            await t.rollback();
            return res.status(404).json({ success: false, message: 'Cancellation request not found' });
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
 * Export cancellation data as JSON (suitable for CSV/Excel conversion client-side)
 */
export const exportCancellations = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { startDate, endDate, status } = req.query as Record<string, string>;

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
                    attributes: ['id', 'planTitle', 'planDateTime', 'status'],
                    include: [{ model: (require('../models/Venue').default), as: 'venue', attributes: ['name', 'city'] }],
                },
                { model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] },
                { model: User, as: 'recipient', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] },
                { model: Booking, as: 'booking', attributes: ['id', 'status', 'totalAmount', 'paymentStatus'] },
            ],
        });

        const exportData = records.map((r: any) => ({
            cancellationRequestId: r.id,
            bookingId: r.bookingId || '—',
            planId: r.planId,
            planTitle: r.plan?.planTitle || '—',
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

