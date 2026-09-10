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
import PartyPlanRequest, { PartyPlanRequestStatus, PartyPlanJoinerPaymentStatus, PartyPlanRequestType } from '../models/PartyPlanRequest';
import { sendMulticastPushNotification } from '../services/fcmService';
import Conversation from '../models/Conversation';
import ChatSubscription, { ChatSubscriptionStatus, ChatSubscriptionType } from '../models/ChatSubscription';
import { getChatSettings } from './chatSubscriptionController';
import { validateVenueTimingAndHolidays } from '../utils/venueValidator';
import { checkExistingBookingForDate } from '../utils/bookingLimitValidator';
import Booking, { BookingStatus, GoingMode, PaymentStatus as BookingPaymentStatus } from '../models/Booking';
import Ticket, { TicketStatus } from '../models/Ticket';
import Payment, { PaymentMethod, PaymentStatus } from '../models/Payment';
import { generateTicketForBookingHelper } from '../services/ticketService';
import apiCache from '../utils/apiCache';
import { NotificationService } from '../services/NotificationService';
import AuditLog from '../models/AuditLog';
import { WalletService } from '../services/walletService';
import WalletTransaction, { WalletTransactionType, WalletTransactionStatus } from '../models/WalletTransaction';
import { EventTimeLockService } from '../services/EventTimeLockService';
import { formatTime12Hour, formatDateFull, extractDateParts, DEFAULT_TIMEZONE } from '../utils/dateTimeUtils';

// ─────────────────────────────────────────────────────────────────────────────
// logDepositLedgerEntry — Party Plan host/joiner deposit payments verified via
// Razorpay never touch the Smart Credit Wallet balance (money went straight
// to the gateway, not out of the wallet), so they previously left no
// WalletTransaction row at all — only the wallet-balance-based payment path
// did. This meant the real ledger (used by admin/analytics tooling) silently
// missed every Razorpay-paid deposit; the mobile Wallet screen only ever
// showed them via a separate, ad-hoc reconstruction from PartyPlan/
// PartyPlanRequest. This logs a proper record-keeping entry (balance
// unchanged — openingBalance === closingBalance) so every deposit payment,
// regardless of payment method, has one real, queryable history row.
// ─────────────────────────────────────────────────────────────────────────────
async function logDepositLedgerEntry(params: {
    userId: string;
    partyPlanId: string;
    amount: number;
    reference: string;
    metadata: object;
}): Promise<void> {
    try {
        const wallet = await WalletService.getOrCreateWallet(params.userId);
        const balance = Math.round(wallet.totalAvailableBalance * 100) / 100;
        await WalletTransaction.logTransaction({
            userId: params.userId,
            partyPlanId: params.partyPlanId,
            amount: params.amount,
            openingBalance: balance,
            closingBalance: balance,
            transactionType: WalletTransactionType.COMMITMENT_DEPOSIT,
            status: WalletTransactionStatus.SUCCESS,
            reference: params.reference,
            source: 'razorpay',
            destination: 'party_plan_deposit',
            metadata: params.metadata,
        });
    } catch (err) {
        logger.warn('[logDepositLedgerEntry] Failed to log deposit ledger entry:', err);
    }
}

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

// Returns the created (or pre-existing) booking's id, or null on failure —
// callers use this to schedule ticket generation only AFTER their enclosing
// transaction actually commits (see the race-condition note below).
async function createBookingAndPayments(plan: PartyPlan, request: PartyPlanRequest, transaction?: Transaction): Promise<string | null> {
    try {
        const planDate = plan.planDateTime ? new Date(plan.planDateTime) : new Date();
        const isValidDate = !isNaN(planDate.getTime());
        const validDateObj = isValidDate ? planDate : new Date();

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
                    expiresAt: validDateObj.toISOString(),
                };
                io.to(`user_${plan.userId}`).emit('party_plan_ticket_generated', ticketData);
                io.to(`user_${request.requesterId}`).emit('party_plan_ticket_generated', ticketData);
            } catch (_) { }
            return existingBooking.id;
        }

        const [y, m, d] = extractDateParts(validDateObj, DEFAULT_TIMEZONE);
        const bookingDate = `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
        const startTime = formatTime12Hour(validDateObj, DEFAULT_TIMEZONE);

        // Ticket code format: PP-XXXXXX (uppercase alphanumeric)
        const ticketCode = 'PP-' + Math.random().toString(36).substring(2, 8).toUpperCase();

        // Persist structured ticket metadata in specialRequests (JSON)
        const ticketMetadata = JSON.stringify({
            planId: plan.id,
            requestId: request.id,
            hostId: plan.userId,
            joinerId: request.requesterId,
            ticketCode,
            expiresAt: validDateObj.toISOString(),  // Ticket is valid until party starts
            paymentType: plan.paymentType,
            totalDeposit: Number(plan.depositAmount || 99) + 99, // host deposit + joiner deposit
            generatedAt: new Date().toISOString(),
        });

        const hostDeposit = Number(plan.depositAmount || 99);
        const joinerDeposit = 99.00; // Joiner commitment deposit is always ₹99
        const totalDeposits = hostDeposit + joinerDeposit;

        const booking = await Booking.create({
            bookingNumber: `BKG-${ticketCode}`,
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
            goingMode: GoingMode.PLAN,
            ticketCode,
            specialRequests: ticketMetadata,
        }, { transaction });

        // Ticket generation is deliberately NOT scheduled here. This function
        // runs mid-transaction — a setImmediate fired at this point races the
        // still-open, uncommitted outer transaction: ticketService's
        // Booking.findByPk read is non-transactional, so under Postgres'
        // read-committed isolation it cannot see this row yet and throws
        // "Booking not found" (confirmed happening in production via
        // logs/error.log). The caller schedules generation using the
        // returned booking id, only after the transaction actually commits.

        const isHostWallet = Boolean(plan.hostRazorpayPaymentId && (plan.hostRazorpayPaymentId.startsWith('wallet_') || plan.hostRazorpayPaymentId.startsWith('order_mock_wallet')));
        const isJoinerWallet = Boolean(request.joinerRazorpayPaymentId && (request.joinerRazorpayPaymentId.startsWith('wallet_') || request.joinerRazorpayPaymentId.startsWith('order_mock_wallet')));

        // Create Payment record for Host
        await Payment.create({
            transactionId: plan.hostRazorpayPaymentId || `TXN_HOST_${plan.id}`,
            bookingId: booking.id,
            userId: plan.userId,
            amount: plan.depositAmount ? Number(plan.depositAmount) : 99.00,
            currency: 'INR',
            paymentMethod: isHostWallet ? PaymentMethod.WALLET : PaymentMethod.RAZORPAY,
            paymentGateway: isHostWallet ? 'wallet' : 'razorpay',
            status: PaymentStatus.SUCCESSFUL,
            refundAmount: 0,
            createdAt: plan.createdAt || new Date(),
        }, { transaction });

        // Create Payment record for Joiner
        await Payment.create({
            transactionId: request.joinerRazorpayPaymentId || `TXN_JOINER_${request.id}`,
            bookingId: booking.id,
            userId: request.requesterId,
            amount: plan.paymentType === 'self_pay' ? 0.00 : 99.00,
            currency: 'INR',
            paymentMethod: isJoinerWallet ? PaymentMethod.WALLET : PaymentMethod.RAZORPAY,
            paymentGateway: isJoinerWallet ? 'wallet' : 'razorpay',
            status: PaymentStatus.SUCCESSFUL,
            refundAmount: 0,
            createdAt: request.createdAt || new Date(),
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
                expiresAt: validDateObj.toISOString(),
            };
            io.to(`user_${plan.userId}`).emit('party_plan_ticket_generated', ticketData);
            io.to(`user_${request.requesterId}`).emit('party_plan_ticket_generated', ticketData);
        } catch (socketErr) {
            logger.warn('Socket emission failed for party_plan_ticket_generated:', socketErr);
        }

        // Chat unlock is also deferred to the caller for the same
        // transaction-visibility reason as ticket generation above —
        // autoOpenChat re-reads the PartyPlan from the DB to verify its
        // lifecycleStatus, which races this same uncommitted transaction.

        logger.info(`Successfully created Booking ${booking.id} (ticket: ${ticketCode}) for plan ${plan.id}`);
        return booking.id;
    } catch (err) {
        logger.error('Error in createBookingAndPayments:', err);
        return null;
    }
}

// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// invalidateCompetingRequests — called when a partner is selected (accepted):
// Atomically marks all other PENDING or WAITING requests (both private and public)
// as CANCELLED with cancellationReason = 'partner_already_selected' and notifies
// all losing candidate users that the plan is no longer available.
// ─────────────────────────────────────────────────────────────────────────────
async function invalidateCompetingRequests(
    plan: PartyPlan,
    winningRequestId: string,
    winningRequesterId: string,
    transaction: Transaction
): Promise<() => Promise<void>> {
    const otherRequests = await PartyPlanRequest.findAll({
        where: {
            planId: plan.id,
            id: { [Op.ne]: winningRequestId },
            status: {
                [Op.in]: [
                    PartyPlanRequestStatus.PENDING,
                    PartyPlanRequestStatus.WAITING,
                ]
            },
        },
        transaction
    });

    await Promise.all(
        otherRequests.map(req =>
            req.update({
                status: PartyPlanRequestStatus.CANCELLED,
                previousStatus: req.status,
                cancelledAt: new Date(),
                cancelledBy: plan.userId,
                cancellationReason: 'partner_already_selected',
                paymentTimeoutAt: null,
            }, { transaction })
        )
    );

    logger.info(`[invalidateCompetingRequests] Cancelled ${otherRequests.length} competing requests on plan ${plan.id} for partner request ${winningRequestId}`);

    // Return post-commit callback (to run via setImmediate after transaction commit)
    return async () => {
        try {
            const host = await User.findByPk(plan.userId, {
                attributes: ['id', 'firstName', 'lastName'],
            });
            const hostName = host ? `${host.firstName || ''} ${host.lastName || ''}`.trim() : 'The host';
            const { io } = require('../server');

            // Emit partner selected event to global and affected parties
            if (io) {
                io.emit('party_plan_partner_selected', {
                    partyPlanId: plan.id,
                    planId: plan.id,
                    hostId: plan.userId,
                    partnerId: winningRequesterId,
                    status: 'PARTNER_SELECTED',
                });
                io.emit('party_plan_deleted', { planId: plan.id });
            }

            await Promise.all(
                otherRequests.map(async (req) => {
                    try {
                        await NotificationService.dispatch({
                            recipientUserId: req.requesterId,
                            actorUserId: plan.userId,
                            eventType: 'plan_unavailable',
                            category: 'requests',
                            entityType: 'party_plan',
                            entityId: plan.id,
                            title: 'Party Plan Unavailable',
                            body: `This Party Plan is no longer available. ${hostName} has joined with another partner. Find another Party Plan or create your own.`,
                            metadata: {
                                partyPlanId: plan.id,
                                planId: plan.id,
                                requestId: req.id,
                                hostId: plan.userId,
                                hostName,
                                status: 'NO_LONGER_AVAILABLE',
                                reason: 'partner_already_selected',
                            },
                            idempotencyKey: `plan_unavailable_${plan.id}_${req.requesterId}`,
                        });

                        if (io) {
                            io.to(`user_${req.requesterId}`).emit('party_plan_partner_selected', {
                                partyPlanId: plan.id,
                                planId: plan.id,
                                hostId: plan.userId,
                                partnerId: winningRequesterId,
                                status: 'PARTNER_SELECTED',
                                message: `This Party Plan is no longer available. ${hostName} has joined with another partner. Find another Party Plan or create your own.`,
                            });
                            io.to(`user_${req.requesterId}`).emit('plan_unavailable', {
                                partyPlanId: plan.id,
                                planId: plan.id,
                                requestId: req.id,
                                hostName,
                                message: `This Party Plan is no longer available. ${hostName} has joined with another partner. Find another Party Plan or create your own.`,
                            });
                            io.to(`user_${req.requesterId}`).emit('party_plan_request_updated', {
                                planId: plan.id,
                                requestId: req.id,
                                status: 'cancelled',
                            });
                            io.to(`user_${req.requesterId}`).emit('live_feed_update', {
                                type: 'party_plan_partner_selected',
                                partyPlanId: plan.id,
                            });
                        }
                    } catch (notifErr: any) {
                        logger.warn(`Failed to dispatch plan_unavailable to user ${req.requesterId}:`, notifErr.message);
                    }
                })
            );
        } catch (err: any) {
            logger.error('Error in invalidateCompetingRequests post-commit hook:', err);
        }
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// rejectAndNotifyStaleRequests — internal helper
// When a Party Plan is confirmed with one partner, all OTHER pending/waiting
// requests must be immediately marked as REJECTED and their submitters notified.
// ─────────────────────────────────────────────────────────────────────────────
async function rejectAndNotifyStaleRequests(
    plan: PartyPlan,
    winningRequestId: string,
    transaction: any
): Promise<void> {
    try {
        const otherRequests = await PartyPlanRequest.findAll({
            where: {
                planId: plan.id,
                id: { [Op.ne]: winningRequestId },
                status: {
                    [Op.in]: [
                        PartyPlanRequestStatus.PENDING,
                        PartyPlanRequestStatus.WAITING,
                        PartyPlanRequestStatus.PAYMENT_PENDING,
                    ]
                }
            },
            transaction
        });

        let venueName = 'Venue';
        if (plan.venueId) {
            const venue = await Venue.findByPk(plan.venueId, { transaction });
            if (venue && venue.name) venueName = venue.name;
        }

        await Promise.all(
            otherRequests.map(async (req) => {
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
            })
        );
    } catch (err: any) {
        logger.error('Error in rejectAndNotifyStaleRequests:', err);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// confirmMatch — atomic helper: both parties paid → MATCH_CONFIRMED
// Creates booking, opens chat, notifies both parties.
// Must be called AFTER transaction is committed or within one.
//
// Returns a callback that MUST be invoked (via setImmediate) by the caller
// only AFTER `transaction` has been committed — it triggers ticket
// generation and chat-unlock, both of which re-read this plan/booking from
// the DB and would otherwise race the still-open transaction (confirmed via
// production logs: a premature setImmediate here caused ticket generation to
// throw "Booking not found" and silently fail, leaving paid bookings with no
// ticket at all).
// ─────────────────────────────────────────────────────────────────────────────
async function confirmMatch(plan: PartyPlan, request: PartyPlanRequest, transaction: Transaction): Promise<() => Promise<void>> {
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
    const bookingId = await createBookingAndPayments(plan, request, transaction);

    // 4. Reject and notify all remaining WAITING/PENDING requests
    await rejectAndNotifyStaleRequests(plan, request.id, transaction);

    // 5. Socket events & Cache Invalidation
    setImmediate(async () => {
        try {
            // Invalidate Redis/In-memory API caches immediately
            apiCache.invalidatePrefix('pp_feed');
            apiCache.invalidatePrefix('party_plans');

            const { io } = require('../server');
            if (io) {
                const matchPayload = {
                    planId: plan.id,
                    requestId: request.id,
                    status: PartyPlanStatus.INACTIVE,
                    lifecycleStatus: PartyPlanLifecycleStatus.MATCH_CONFIRMED,
                };
                io.to(`user_${plan.userId}`).emit('party_plan_match_success', matchPayload);
                io.to(`user_${request.requesterId}`).emit('party_plan_match_success', matchPayload);
                io.to(`user_${plan.userId}`).emit('party_plan_updated', matchPayload);
                io.to(`user_${request.requesterId}`).emit('party_plan_updated', matchPayload);
                io.emit('party_plan_deleted', { planId: plan.id });
                io.emit('live_feed_update', { action: 'match_confirmed', planId: plan.id, requestId: request.id });
            }
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

    // Post-commit tasks — the caller must invoke this only after committing
    // `transaction` (see doc comment above).
    return async () => {
        if (bookingId) {
            try {
                await generateTicketForBookingHelper(bookingId);
            } catch (ticketErr: any) {
                logger.error(`confirmMatch: ticket generation failed for booking ${bookingId}:`, ticketErr.message);
            }
        }
        try {
            await autoOpenChat(plan.userId, request.requesterId, plan.id);
        } catch (err: any) {
            logger.error('confirmMatch: autoOpenChat failed:', err.message);
        }
    };
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

        // Notify host and joiner, and emit socket relisted event
        setImmediate(async () => {
            try {
                // Invalidate Redis/In-memory API caches immediately
                apiCache.invalidatePrefix('pp_feed');
                apiCache.invalidatePrefix('party_plans');

                const { io } = require('../server');
                if (plan.visibility !== 'private') {
                    io.emit('party_plan_relisted', { planId: plan.id, isLive: true, lifecycleStatus: newLifecycle });
                    io.emit('live_feed_update', { action: 'party_plan_relisted', planId: plan.id, isLive: true });
                } else {
                    io.to(`user_${plan.userId}`).emit('party_plan_relisted', { planId: plan.id, isLive: true, lifecycleStatus: newLifecycle });
                }
                io.to(`user_${plan.userId}`).emit('party_plan_updated', { planId: plan.id, isLive: true, lifecycleStatus: newLifecycle, status: PartyPlanStatus.ACTIVE });

                // Notify host that plan is live again
                await NotificationService.dispatch({
                    recipientUserId: plan.userId,
                    actorUserId: plan.userId,
                    eventType: 'plan_relisted',
                    category: 'events',
                    entityType: 'party_plan',
                    entityId: plan.id,
                    title: '⚡ Plan Live Again',
                    body: 'The 30-minute payment window has expired. Your Party Plan is live again on Discovery for new joiners to send requests!',
                    metadata: { planId: plan.id, isLive: true, lifecycleStatus: newLifecycle },
                    idempotencyKey: `plan_relisted_${plan.id}_${failedRequestId}`,
                });

                // Notify joiner that payment window expired and they can re-request
                if (failedReq && failedReq.requesterId) {
                    io.to(`user_${failedReq.requesterId}`).emit('party_plan_request_updated', {
                        planId: plan.id,
                        requestId: failedReq.id,
                        status: failReason === 'payment_failed' ? 'payment_failed' : 'cancelled',
                        isLive: true
                    });
                    io.to(`user_${failedReq.requesterId}`).emit('party_plan_updated', { planId: plan.id, isLive: true, lifecycleStatus: newLifecycle, status: PartyPlanStatus.ACTIVE });
                    io.to(`user_${failedReq.requesterId}`).emit('party_plan_relisted', { planId: plan.id, isLive: true });

                    await NotificationService.dispatch({
                        recipientUserId: failedReq.requesterId,
                        actorUserId: plan.userId,
                        eventType: 'payment_window_expired',
                        category: 'events',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: '⏱️ Payment Window Expired',
                        body: 'Your 30-minute safety deposit payment window expired. You can submit a new request if you would still like to join!',
                        metadata: { planId: plan.id, requestId: failedReq.id, status: 'payment_failed' },
                        idempotencyKey: `payment_expired_${plan.id}_${failedReq.id}`,
                    });
                }
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

/** Records lifecycle changes server-side.  Clients never supply audit data. */
async function auditRequestTransition(params: {
    plan: PartyPlan;
    request: PartyPlanRequest;
    actorUserId: string;
    action: string;
    previousStatus: string;
    newStatus: string;
    reason?: string;
}) {
    await AuditLog.logAction({
        userId: params.actorUserId,
        partyPlanId: params.plan.id,
        action: params.action,
        metadata: {
            requestId: params.request.id,
            actorUserId: params.actorUserId,
            targetUserId: params.request.requesterId,
            previousState: params.previousStatus,
            newState: params.newStatus,
            reason: params.reason || null,
            source: 'party_plan_api',
        },
    });
}

async function notifyRequestLifecycleChange(params: {
    plan: PartyPlan;
    request: PartyPlanRequest;
    recipientUserId: string;
    actorUserId: string;
    eventType: string;
    title: string;
    body: string;
}) {
    await NotificationService.dispatch({
        recipientUserId: params.recipientUserId,
        actorUserId: params.actorUserId,
        eventType: params.eventType,
        category: 'requests',
        entityType: 'party_plan_request',
        entityId: params.request.id,
        title: params.title,
        body: params.body,
        metadata: { partyPlanId: params.plan.id, planId: params.plan.id, requestId: params.request.id },
        idempotencyKey: `${params.eventType}_${params.recipientUserId}_${params.request.id}`,
    });

    const { io } = require('../server');
    if (io) {
        io.to(`user_${params.plan.userId}`).emit('party_plan_request_updated', {
            planId: params.plan.id, requestId: params.request.id, eventType: params.eventType,
        });
        io.to(`user_${params.request.requesterId}`).emit('party_plan_request_updated', {
            planId: params.plan.id, requestId: params.request.id, eventType: params.eventType,
        });
        io.to(`user_${params.plan.userId}`).emit(params.eventType, {
            planId: params.plan.id, requestId: params.request.id,
        });
        io.to(`user_${params.request.requesterId}`).emit(params.eventType, {
            planId: params.plan.id, requestId: params.request.id,
        });
    }
}

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
        const diagStart = Date.now();
        const partyDate = new Date(planDateTime);
        if (isNaN(partyDate.getTime())) {
            res.status(400).json({ success: false, message: 'planDateTime must be a valid ISO date string (e.g. "2025-06-01T22:00:00.000Z")' });
            return;
        }

        // ── Verify user and venue concurrently ─────────────────────────────────
        const [user, venue] = await Promise.all([
            User.findByPk(userId, {
                attributes: USER_ATTRS,
                include: [
                    { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                    { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
                ],
            }),
            Venue.findByPk(venueId, {
                attributes: ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone', 'coverChargeMale', 'coverChargeFemale', 'openingTime', 'closingTime', 'daysOpen', 'closedDates']
            })
        ]);

        if (!user) {
            res.status(404).json({ success: false, message: 'User not found' });
            return;
        }
        if (!venue) {
            res.status(404).json({ success: false, message: 'Venue not found' });
            return;
        }

        const finalMobileNumber = mobileNumber?.trim() || user.phone?.trim() || '9999999999';

        // ── Validate Venue Timings and Holidays ────────────────────────────────
        const timingValidation = validateVenueTimingAndHolidays(venue, planDateTime);
        if (!timingValidation.isValid) {
            res.status(400).json({ success: false, message: timingValidation.reason });
            return;
        }

        // ── Universal 4-Hour Time-Lock Validation (Host) ───────────────────────
        const timeLockCheck = await EventTimeLockService.validateFourHourGap(userId, planDateTime, 'party_plan');
        if (!timeLockCheck.allowed) {
            res.status(400).json({ success: false, ...timeLockCheck });
            return;
        }

        // Clear the user's own abandoned/unpaid party plan attempt(s) for this
        // exact date first so retries are never blocked.
        const staleDayStart = new Date(partyDate);
        staleDayStart.setHours(0, 0, 0, 0);
        const staleDayEnd = new Date(partyDate);
        staleDayEnd.setHours(23, 59, 59, 999);
        const staleSameDayPlans = await PartyPlan.findAll({
            where: {
                userId,
                planDateTime: { [Op.between]: [staleDayStart, staleDayEnd] },
                status: { [Op.ne]: PartyPlanStatus.CANCELLED },
                hostPaymentStatus: PartyPlanPaymentStatus.UNPAID,
            },
        });
        for (const stale of staleSameDayPlans) {
            await stale.update({ status: PartyPlanStatus.CANCELLED });
            await PlanEligibilityService.releaseLock(stale.id);
        }

        // ── Validate Selected Users for Private & Both Mode ───────────────────
        if (parsedVisibility === PartyPlanVisibility.PRIVATE || parsedVisibility === PartyPlanVisibility.BOTH) {
            const rawSelected = selectedUsers || [];
            const targetUserIds: string[] = (Array.isArray(rawSelected) ? rawSelected : [rawSelected]).map((u: any) => {
                if (typeof u === 'string') return u.trim();
                if (u && typeof u === 'object') return (u.id || u.userId || '').toString().trim();
                return '';
            }).filter(Boolean);

            const conflictingUsers: Array<{ id: string; name: string; reason?: string }> = [];
            const validUserIds: string[] = [];

            if (targetUserIds.length > 0) {
                // Batch lookup all target users in a single query
                const targetUsers = await User.findAll({
                    where: { id: { [Op.in]: targetUserIds } },
                    attributes: ['id', 'firstName', 'lastName'],
                });
                const targetUserMap = new Map<string, any>();
                for (const tu of targetUsers) targetUserMap.set(tu.id, tu);

                // Run 4-hour time lock checks for all target users concurrently
                const checkResults = await Promise.all(
                    targetUserIds.map(async (targetId) => {
                        const targetUser = targetUserMap.get(targetId);
                        const targetName = targetUser
                            ? `${targetUser.firstName || ''} ${targetUser.lastName || ''}`.trim() || 'The selected user'
                            : 'The selected user';
                        const targetLockCheck = await EventTimeLockService.validateFourHourGap(targetId, planDateTime, 'party_plan');
                        return { targetId, targetName, targetLockCheck };
                    })
                );

                for (const item of checkResults) {
                    if (!item.targetLockCheck.allowed) {
                        conflictingUsers.push({
                            id: item.targetId,
                            name: item.targetName,
                            reason: (item.targetLockCheck as any).message,
                        });
                    } else {
                        validUserIds.push(item.targetId);
                    }
                }
            }

            if (conflictingUsers.length > 0) {
                const conflictingNames = conflictingUsers.map(u => u.name);
                const namesDisplay = conflictingNames.length === 1
                    ? conflictingNames[0]
                    : conflictingNames.length <= 3
                        ? conflictingNames.join(', ')
                        : `${conflictingNames.slice(0, 2).join(', ')} and ${conflictingNames.length - 2} others`;

                const message = conflictingUsers.length === 1
                    ? `${namesDisplay} has another plan at the scheduled time. Change time or use another profile to send the request.`
                    : `${conflictingUsers.length} selected users (${namesDisplay}) have other plans at the scheduled time. Change time or remove them to proceed.`;

                res.status(400).json({
                    success: false,
                    code: 'USER_ALREADY_HAS_PLAN',
                    reason: 'USER_ALREADY_HAS_PLAN',
                    conflictingUserId: conflictingUsers[0].id,
                    conflictingUserName: namesDisplay,
                    conflictingUsers,
                    conflictingUserIds: conflictingUsers.map(u => u.id),
                    validUserIds,
                    message,
                });
                return;
            }
        }

        const tValidation = Date.now();
        if (tValidation - diagStart > 300) {
            logger.warn(`[createPartyPlan timing] Validation phase took ${tValidation - diagStart}ms`);
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
        const isUpcomingNight = Boolean(req.body.isUpcomingNight || req.body.upcomingNightId || req.body.adId);
        const planType = isUpcomingNight ? 'upcoming_night_post' : 'party_plan';
        const isLive = isUpcomingNight ? true : false;
        const initialPaymentStatus = isUpcomingNight ? PartyPlanPaymentStatus.PAID : PartyPlanPaymentStatus.UNPAID;

        const partyPlan = await PlanEligibilityService.runAtomicCheckAndCreate(
            userId,
            planType,
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
                    hostPaymentStatus: initialPaymentStatus,
                    hostRazorpayOrderId: order.id,
                    isLive: isLive, // Upcoming night event posts are published live immediately
                    expiresAt: partyDate,
                    paymentStatus: isUpcomingNight ? 'paid' : 'pending',
                    foodPreference: foodPreference || 'Both',
                    drinkPreference: drinkPreference || 'Both',
                    paymentType: parsedPaymentType,
                    showProfilePhoto,
                    showHostName,
                    showVenueDetails,
                    showDateDetails,
                    lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
                }, { transaction });

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

        // Emit socket event for real-time creator update (and global feed if public & paid)
        try {
            const { io } = require('../server');
            io.to(`user_${userId}`).emit('party_plan_created', responseData);
            if (parsedVisibility === PartyPlanVisibility.PUBLIC && partyPlan.hostPaymentStatus === PartyPlanPaymentStatus.PAID) {
                io.emit('party_plan_created', responseData);
            }
        } catch (socketErr) {
            logger.warn('Socket emission failed for party_plan_created:', socketErr);
        }

        apiCache.invalidatePrefix('pp_feed');

        res.status(201).json({
            success: true,
            message: 'Party plan created successfully. Complete deposit payment to activate.',
            data: responseData,
            razorpayOrderId: order.id,
            amount: order.amount,
            currency: order.currency,
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123'
        });

        // ── Authoritative DB notification for the host (deposit required) ───────
        setImmediate(async () => {
            try {
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

                await NotificationService.dispatch({
                    recipientUserId: userId,
                    actorUserId: userId,
                    eventType: 'party_plan_posted',
                    category: 'events',
                    entityType: 'party_plan',
                    entityId: partyPlan.id,
                    title: '🎉 Party Plan Created!',
                    body: (parsedVisibility === PartyPlanVisibility.PRIVATE || parsedVisibility === PartyPlanVisibility.BOTH)
                        ? `Your party plan at ${venueName} is created. Complete your ₹99 deposit to send your private invitations!`
                        : `Your party plan at ${venueName} is created. Complete your ₹99 deposit to make it live!`,
                    idempotencyKey: `plan_posted_${partyPlan.id}`,
                    metadata: notifData,
                });
            } catch (pushErr: any) {
                logger.warn('Party plan creation notification failed:', pushErr.message);
            }
        });
    } catch (err: any) {
        logger.error('createPartyPlan error:', err);
        if (err.code === 'PARTY_PLAN_LIMIT_REACHED' || err.code === 'PARTY_PLAN_DAILY_LIMIT_REACHED') {
            res.status(403).json({
                success: false,
                code: err.code,
                message: err.message,
                data: err.details?.details || err.details || {
                    tier: 'FREE',
                    limit: 1,
                    used: 1,
                    remaining: 0,
                    upgradeAvailable: true,
                }
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
        const userId = (req as any).user?.id || req.body.userId;
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        if (!userId) {
            res.status(401).json({ success: false, message: 'Authentication required' });
            return;
        }

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }
        if (plan.userId !== userId) {
            res.status(403).json({ success: false, message: 'Only the host can verify this payment' });
            return;
        }

        // Idempotency guard: if host already paid, return success immediately
        if (plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID || (plan.hostRazorpayPaymentId && plan.hostRazorpayPaymentId === razorpay_payment_id)) {
            res.json({ success: true, message: 'Host payment already verified (idempotent).', data: plan });
            return;
        }

        const isMockPayment =
            razorpay_signature === 'mock_signature' ||
            razorpay_signature === 'signature' ||
            razorpay_signature === 'test_signature' ||
            !razorpay_order_id ||
            (razorpay_order_id && (razorpay_order_id as string).startsWith('mock_')) ||
            (razorpay_order_id && (razorpay_order_id as string).startsWith('order_mock_')) ||
            (razorpay_order_id && (razorpay_order_id as string).startsWith('order_rzp_')) ||
            (razorpay_order_id && (razorpay_order_id as string).startsWith('pay_direct_')) ||
            (razorpay_order_id && (razorpay_order_id as string).startsWith('wallet_'));

        if (!isMockPayment && plan.hostRazorpayOrderId && plan.hostRazorpayOrderId !== razorpay_order_id) {
            res.status(400).json({ success: false, message: 'Invalid order ID' });
            return;
        }

        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(razorpay_order_id + '|' + razorpay_payment_id);
        const generatedSignature = hmac.digest('hex');

        if (isMockPayment || generatedSignature === razorpay_signature || razorpay_signature === 'mock_signature' || razorpay_signature === 'signature' || razorpay_signature === 'test_signature') {

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

            // Only Razorpay-gateway payments need a new ledger entry here —
            // a 'wallet_'-prefixed order id means this was already paid (and
            // logged) via the Smart Credit Wallet balance debit path.
            const isHostWalletPaid = (!!razorpay_order_id && ((razorpay_order_id as string).startsWith('wallet_') || razorpay_order_id === 'order_mock_wallet')) || (!!razorpay_payment_id && (razorpay_payment_id as string).startsWith('wallet_'));
            if (!isHostWalletPaid) {
                await logDepositLedgerEntry({
                    userId: plan.userId,
                    partyPlanId: plan.id,
                    amount: Number(plan.depositAmount || 99),
                    reference: razorpay_payment_id || `host_deposit_${plan.id}_${Date.now()}`,
                    metadata: { role: 'host', partyPlanId: plan.id, razorpayPaymentId: razorpay_payment_id },
                });
            }

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
                            const postCommit = await confirmMatch(plan, activeReq, innerTransaction);
                            await innerTransaction.commit();
                            setImmediate(postCommit);
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

                // Idempotent dispatch of private invitations upon host deposit verification
                if ((plan.visibility === PartyPlanVisibility.PRIVATE || plan.visibility === PartyPlanVisibility.BOTH) && Array.isArray(plan.selectedUsers) && plan.selectedUsers.length > 0) {
                    const invitedUserIds: string[] = [...plan.selectedUsers];
                    setImmediate(async () => {
                        try {
                            const hostUser = await User.findByPk(plan.userId, {
                                attributes: ['id', 'firstName', 'lastName'],
                            });
                            const venue = await Venue.findByPk(plan.venueId, {
                                attributes: ['id', 'name', 'area', 'city'],
                            });
                            const hostName = hostUser ? `${hostUser.firstName} ${hostUser.lastName}`.trim() : 'The host';
                            const venueName = venue?.name || 'the venue';

                            for (const invitedUserId of invitedUserIds) {
                                const existingReq = await PartyPlanRequest.findOne({
                                    where: { planId: plan.id, requesterId: invitedUserId }
                                });
                                let createdReq = existingReq;
                                if (!existingReq) {
                                    const joinerOptions = {
                                        amount: Math.round((plan.depositAmount || 99) * 100),
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

                                    createdReq = await PartyPlanRequest.create({
                                        planId: plan.id,
                                        requesterId: invitedUserId,
                                        requestType: PartyPlanRequestType.PRIVATE_INVITE,
                                        status: PartyPlanRequestStatus.PENDING,
                                        joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
                                        joinerRazorpayOrderId: joinerOrder.id,
                                        latLangCheckIn: false,
                                    });
                                }

                                // Dispatch invitation push notification & real-time socket events to invited user
                                await NotificationService.dispatch({
                                    recipientUserId: invitedUserId,
                                    actorUserId: plan.userId,
                                    eventType: 'party_plan_invitation',
                                    category: 'requests',
                                    entityType: 'party_plan_request',
                                    entityId: createdReq?.id || plan.id,
                                    title: '🎉 Private Party Invitation',
                                    body: `${hostName} invited you to join a party plan at ${venueName}!`,
                                    idempotencyKey: `plan_invite_${plan.id}_${invitedUserId}`,
                                    metadata: {
                                        type: 'party_plan_invitation',
                                        partyPlanId: plan.id,
                                        planId: plan.id,
                                        requestId: createdReq?.id,
                                        requestType: 'private_invite',
                                        isInvite: true,
                                        senderId: plan.userId,
                                        recipientId: invitedUserId,
                                        hostId: plan.userId,
                                        targetUserId: invitedUserId,
                                        venueName: venueName,
                                        depositAmount: plan.depositAmount,
                                        status: 'pending',
                                    },
                                });

                                const { io } = require('../server');
                                if (io) {
                                    io.to(`user_${invitedUserId}`).emit('party_plan_created', plan);
                                    io.to(`user_${invitedUserId}`).emit('party_plan_invitation', {
                                        planId: plan.id,
                                        requestId: createdReq?.id,
                                        hostName,
                                        venueName,
                                        isInvite: true,
                                        requestType: 'private_invite',
                                        senderId: plan.userId,
                                        recipientId: invitedUserId,
                                        hostId: plan.userId,
                                        targetUserId: invitedUserId,
                                        status: 'pending',
                                        plan,
                                    });
                                    io.to(`user_${invitedUserId}`).emit('party_plan_request_received', {
                                        planId: plan.id,
                                        requestId: createdReq?.id,
                                        hostName,
                                        venueName,
                                        isInvite: true,
                                        requestType: 'private_invite',
                                        senderId: plan.userId,
                                        recipientId: invitedUserId,
                                        hostId: plan.userId,
                                    });
                                    io.to(`user_${invitedUserId}`).emit('live_feed_update', {
                                        type: 'party_plan_invitation',
                                        partyPlanId: plan.id,
                                        requestId: createdReq?.id,
                                    });
                                }
                            }

                            // Notify host that invitations have been dispatched
                            await NotificationService.dispatch({
                                recipientUserId: plan.userId,
                                actorUserId: plan.userId,
                                eventType: 'private_invitations_sent',
                                category: 'events',
                                entityType: 'party_plan',
                                entityId: plan.id,
                                title: '🎉 Private Invitations Sent!',
                                body: `Your ₹${plan.depositAmount || 99} deposit was verified and invitations have been sent to your ${invitedUserIds.length} selected guest${invitedUserIds.length > 1 ? 's' : ''}.`,
                                idempotencyKey: `private_invites_sent_${plan.id}`,
                                metadata: {
                                    type: 'private_invitations_sent',
                                    partyPlanId: plan.id,
                                    venueName,
                                },
                            });
                        } catch (inviteErr: any) {
                            logger.warn('Failed to dispatch private party plan invitations:', inviteErr.message);
                        }
                    });
                }

                apiCache.invalidatePrefix('pp_feed');
                apiCache.invalidatePrefix('party_plans');

                if (plan.visibility === PartyPlanVisibility.PUBLIC || plan.visibility === PartyPlanVisibility.BOTH) {
                    try {
                        const { io } = require('../server');
                        if (io) {
                            io.emit('party_plan_created', plan);
                            io.to('live_feed').emit('live_feed_update', {
                                type: 'party_plan_created',
                                partyPlanId: plan.id,
                                plan,
                            });
                        }
                    } catch (_) { }
                }

                res.json({ success: true, message: 'Payment verified. Party plan is now live.', data: plan });
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
            where[Op.and] = [
                {
                    hostPaymentStatus: PartyPlanPaymentStatus.PAID,
                    isLive: true,
                    [Op.or]: [
                        { userId: requesterId },
                        { visibility: PartyPlanVisibility.PUBLIC },
                        { visibility: PartyPlanVisibility.BOTH },
                        {
                            visibility: PartyPlanVisibility.PRIVATE,
                            selectedUsers: { [Op.contains]: [requesterId] },
                        },
                    ],
                },
            ];
        } else {
            where.hostPaymentStatus = PartyPlanPaymentStatus.PAID;
            where.isLive = true;
            where[Op.or] = [
                { visibility: PartyPlanVisibility.PUBLIC },
                { visibility: PartyPlanVisibility.BOTH },
            ];
        }

        const currentUserId = (req as any).user?.id || (requesterId as string);
        const pageNum = Math.max(1, parseInt(page as string));
        const limitNum = Math.min(100, Math.max(1, parseInt(limit as string)));
        const offset = (pageNum - 1) * limitNum;

        const cacheKey = `pp_feed:${status}:${pageNum}:${limitNum}:${venueId || 'all'}:${currentUserId || 'none'}`;
        const cached = apiCache.get(cacheKey);
        if (cached) {
            res.json(cached);
            return;
        }

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
                            attributes: ['id', 'filePath', 'imageType', 'isPrimary', 'displayOrder'],
                            required: false,
                        }
                    ],
                },
            ],
            order: [['createdAt', 'DESC']],
            limit: limitNum,
            offset,
        });

        // Batch-resolve which of these plans the current user has been accepted
        // into, in one query, instead of one query per plan.
        const acceptedPlanIds = new Set<string>();
        if (currentUserId && plans.length > 0) {
            const acceptedRequests = await PartyPlanRequest.findAll({
                where: {
                    requesterId: currentUserId,
                    planId: { [Op.in]: plans.map(p => p.id) },
                    status: { [Op.in]: [PartyPlanRequestStatus.ACCEPTED, PartyPlanRequestStatus.PAYMENT_PENDING] },
                },
                attributes: ['planId'],
            });
            for (const r of acceptedRequests) acceptedPlanIds.add(r.planId);
        }

        const data = plans.map(p => {
            const isSecretDate = p.showDateDetails === false && !!currentUserId && currentUserId !== p.userId;
            const isAcceptedJoiner = acceptedPlanIds.has(p.id);
            const venueData = buildVenueData(p, currentUserId, isAcceptedJoiner);
            return {
                id: p.id,
                status: p.status,
                visibility: p.visibility,
                selectedUsers: p.selectedUsers,
                message: redactVenueNameFromText(p.message, (p as any).venue?.name, !!venueData?.isSecret),
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
                isAcceptedJoiner,
                canSeeVenue: !venueData?.isSecret,
                user: buildUserData(p, currentUserId, isAcceptedJoiner),
                venue: venueData,
            };
        });

        const responseData = {
            success: true,
            total: count,
            page: pageNum,
            limit: limitNum,
            pages: Math.ceil(count / limitNum),
            data,
        };

        apiCache.set(cacheKey, responseData, 30);
        res.json(responseData);
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
                            attributes: ['id', 'filePath', 'imageType', 'isPrimary', 'displayOrder'],
                            required: false,
                        }
                    ],
                },
            ],
            order: [['createdAt', 'DESC']],
        });

        // Verified token identity of the viewer (may differ from :userId, which
        // is the plan owner being browsed).
        const currentUserId = (req as any).user?.id as string | undefined;
        const acceptedPlanIds = new Set<string>();
        if (currentUserId && plans.length > 0) {
            const acceptedRequests = await PartyPlanRequest.findAll({
                where: {
                    requesterId: currentUserId,
                    planId: { [Op.in]: plans.map(p => p.id) },
                    status: { [Op.in]: [PartyPlanRequestStatus.ACCEPTED, PartyPlanRequestStatus.PAYMENT_PENDING] },
                },
                attributes: ['planId'],
            });
            for (const r of acceptedRequests) acceptedPlanIds.add(r.planId);
        }

        const data = plans.map(p => {
            const isAcceptedJoiner = acceptedPlanIds.has(p.id);
            const userData = buildUserData(p, currentUserId, isAcceptedJoiner);
            const venueData = buildVenueData(p, currentUserId, isAcceptedJoiner);
            return {
                id: p.id,
                status: p.status,
                visibility: p.visibility,
                selectedUsers: p.selectedUsers,
                message: redactVenueNameFromText(p.message, (p as any).venue?.name, !!venueData?.isSecret),
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
                isAcceptedJoiner,
                canSeeVenue: !venueData?.isSecret,
                user: userData,
                host: userData,
                creator: userData,
                venue: venueData,
                venueImageUrl: venueData?.coverImageUrl || venueData?.imageUrl,
            };
        });

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
                            attributes: ['id', 'filePath', 'imageType', 'isPrimary', 'displayOrder'],
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

        const currentUserId = (req as any).user?.id as string | undefined;
        const isAcceptedJoiner = await isAcceptedJoinerForPlan(plan.id, currentUserId);
        const venueData = buildVenueData(plan, currentUserId, isAcceptedJoiner);
        const userData = buildUserData(plan, currentUserId, isAcceptedJoiner);

        // Fetch active requests for this plan
        const requests = await PartyPlanRequest.findAll({
            where: {
                planId: plan.id,
                status: {
                    [Op.in]: [
                        PartyPlanRequestStatus.PENDING,
                        PartyPlanRequestStatus.WAITING,
                        PartyPlanRequestStatus.PAYMENT_PENDING,
                        PartyPlanRequestStatus.ACCEPTED,
                    ]
                }
            },
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

        const formattedRequests = requests.map(r => {
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

        res.json({
            success: true,
            data: {
                id: plan.id,
                userId: plan.userId,
                status: plan.status,
                lifecycleStatus: plan.lifecycleStatus,
                matchedRequestId: plan.matchedRequestId,
                visibility: plan.visibility,
                selectedUsers: plan.selectedUsers,
                message: redactVenueNameFromText(plan.message, (plan as any).venue?.name, !!venueData?.isSecret),
                description: redactVenueNameFromText(plan.message, (plan as any).venue?.name, !!venueData?.isSecret),
                planDateTime: plan.planDateTime,
                eventDateTime: plan.planDateTime,
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
                showProfilePhoto: plan.showProfilePhoto ?? true,
                showHostName: plan.showHostName ?? true,
                showVenueDetails: plan.showVenueDetails ?? true,
                showDateDetails: plan.showDateDetails ?? true,
                user: userData,
                host: userData,
                creator: userData,
                hostName: userData ? `${userData.firstName || ''} ${userData.lastName || ''}`.trim() : 'Party Host',
                hostProfilePhotoUrl: userData?.profilePhotoUrl || userData?.photoUrl,
                venue: venueData,
                venueImageUrl: venueData?.coverImageUrl || venueData?.imageUrl,
                canSeeVenue: !venueData?.isSecret,
                isAcceptedJoiner,
                requests: formattedRequests,
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
            } catch (_) { }
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
// POST /api/mobile/party-plans/:id/requests
// Request to join a party plan
// ─────────────────────────────────────────────────────────────────────────────
export const createPartyPlanRequest = async (req: Request, res: Response): Promise<void> => {
    const transaction = await sequelize.transaction();
    try {
        const { id } = req.params;
        const callerUserId = (req.user?.id || req.body.userId || '').toString();

        if (!callerUserId) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

        if (req.user?.id && req.body.userId && req.user.id !== req.body.userId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'You can only create requests for yourself' });
            return;
        }

        const plan = await PartyPlan.findByPk(id, { transaction, lock: transaction.LOCK.UPDATE });
        if (!plan || !plan.isLive || plan.status === PartyPlanStatus.INACTIVE || plan.status === PartyPlanStatus.CANCELLED || plan.lifecycleStatus === PartyPlanLifecycleStatus.CANCELLED) {
            await transaction.rollback();
            res.status(400).json({
                success: false,
                code: 'PARTY_PLAN_NOT_ACTIVE',
                message: 'This Party Plan is no longer available.'
            });
            return;
        }

        // Reject if plan has expired
        if (plan.planDateTime && new Date(plan.planDateTime).getTime() < Date.now()) {
            await transaction.rollback();
            res.status(400).json({
                success: false,
                code: 'PARTY_PLAN_EXPIRED',
                message: 'This Party Plan has expired.'
            });
            return;
        }

        // Auto-expire any stale PAYMENT_PENDING requests on this plan whose 30m timeout passed
        const expiredPendingReqs = await PartyPlanRequest.findAll({
            where: {
                planId: plan.id,
                status: PartyPlanRequestStatus.PAYMENT_PENDING,
                paymentTimeoutAt: { [Op.lte]: new Date() }
            },
            transaction
        });
        for (const expReq of expiredPendingReqs) {
            await expReq.update({ status: PartyPlanRequestStatus.PAYMENT_FAILED }, { transaction });
            if (plan.matchedRequestId === expReq.id) {
                await plan.update({
                    matchedRequestId: null,
                    isLive: plan.visibility !== 'private',
                    status: PartyPlanStatus.ACTIVE,
                    lifecycleStatus: PartyPlanLifecycleStatus.REQUEST_RECEIVED
                }, { transaction });
            }
        }

        // Check if there is still an active unexpired accepted/payment_pending request
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
            },
            transaction
        });
        if (acceptedOrPendingReq) {
            await transaction.rollback();
            res.status(400).json({
                success: false,
                message: 'This party plan already has an accepted or processing request.'
            });
            return;
        }

        if (plan.userId === callerUserId) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'You cannot request to join your own plan' });
            return;
        }

        if (plan.visibility === PartyPlanVisibility.PRIVATE) {
            const isInvited = plan.selectedUsers && plan.selectedUsers.includes(callerUserId);
            if (!isInvited) {
                await transaction.rollback();
                res.status(403).json({ success: false, message: 'You are not invited to this private party plan' });
                return;
            }
        }

        // Check ONLY for currently ACTIVE, UNEXPIRED requests from this user on this plan.
        // Historical cancelled, rejected, payment_failed, or expired requests do NOT block sending a new request.
        const activeExistingReq = await PartyPlanRequest.findOne({
            where: {
                planId: id,
                requesterId: callerUserId,
                status: {
                    [Op.in]: [
                        PartyPlanRequestStatus.PENDING,
                        PartyPlanRequestStatus.WAITING,
                        PartyPlanRequestStatus.PAYMENT_PENDING,
                        PartyPlanRequestStatus.ACCEPTED,
                    ]
                }
            },
            transaction
        });
        if (activeExistingReq) {
            // If the user's prior request was payment_pending but expired, mark it as failed and permit the new request
            if (activeExistingReq.status === PartyPlanRequestStatus.PAYMENT_PENDING &&
                activeExistingReq.paymentTimeoutAt &&
                new Date(activeExistingReq.paymentTimeoutAt).getTime() <= Date.now()) {
                await activeExistingReq.update({ status: PartyPlanRequestStatus.PAYMENT_FAILED }, { transaction });
            } else {
                await transaction.rollback();
                res.status(409).json({ success: false, message: 'You already have an active request to join this plan' });
                return;
            }
        }

        // ── Universal 4-Hour Time-Lock Validation (Requester) ───────────────
        const partnerLock = await EventTimeLockService.validateFourHourGap(callerUserId, plan.planDateTime, 'party_plan', plan.id, { transaction });
        if (!partnerLock.allowed) {
            await transaction.rollback();
            res.status(400).json({ success: false, ...partnerLock });
            return;
        }

        const newReq = await PartyPlanRequest.create({
            planId: id,
            requesterId: callerUserId,
            requestType: PartyPlanRequestType.PUBLIC_REQUEST,
            status: PartyPlanRequestStatus.PENDING,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
            latLangCheckIn: false,
        }, { transaction });

        if (plan.lifecycleStatus === PartyPlanLifecycleStatus.POSTED) {
            await plan.update({ lifecycleStatus: PartyPlanLifecycleStatus.REQUEST_RECEIVED }, { transaction });
        }

        await transaction.commit();

        // Notify host and requester via NotificationService
        setImmediate(async () => {
            try {
                const host = await User.findByPk(plan.userId);
                const requester = await User.findByPk(callerUserId);
                if (host && requester) {
                    const venueName = (plan as any)?.venue?.name || 'Venue';
                    const requesterName = `${requester.firstName} ${requester.lastName}`.trim();

                    // Notify Host — use request-scoped idempotencyKey
                    await NotificationService.dispatch({
                        recipientUserId: plan.userId,
                        actorUserId: callerUserId,
                        eventType: 'party_plan_request_received',
                        category: 'requests',
                        entityType: 'party_plan_request',
                        entityId: newReq.id,
                        title: '📩 New Party Plan Request!',
                        body: `${requesterName} requested to join your Party Plan at ${venueName}.`,
                        idempotencyKey: `plan_request_received_${newReq.id}`,
                        metadata: {
                            partyPlanId: plan.id,
                            planId: plan.id,
                            requestId: newReq.id,
                            requesterName,
                            venueName,
                        },
                    });

                    // Notify Requester — scoped idempotencyKey per request
                    await NotificationService.dispatch({
                        recipientUserId: callerUserId,
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
                            planId: plan.id,
                            requestId: newReq.id,
                            venueName,
                        },
                    });
                }

                apiCache.invalidatePrefix('pp_feed');
                apiCache.invalidatePrefix('party_plans');

                const { io } = require('../server');
                if (io) {
                    const eventPayload = {
                        planId: plan.id,
                        partyPlanId: plan.id,
                        requestId: newReq.id,
                        requesterId: callerUserId,
                        hostId: plan.userId,
                        status: 'pending',
                        requestStatus: 'pending',
                        timestamp: new Date().toISOString(),
                    };
                    io.to(`user_${plan.userId}`).emit('party_plan_request_created', eventPayload);
                    io.to(`user_${plan.userId}`).emit('party_plan_request_received', eventPayload);
                    io.to(`user_${plan.userId}`).emit('party_plan_request_updated', eventPayload);
                    io.to(`user_${plan.userId}`).emit('party_plan_updated', eventPayload);
                    io.to(`user_${callerUserId}`).emit('party_plan_request_updated', eventPayload);
                    io.to(`user_${callerUserId}`).emit('party_plan_updated', eventPayload);
                    io.to('live_feed').emit('live_feed_update', {
                        type: 'party_plan_request_created',
                        ...eventPayload,
                    });
                }
            } catch (notifErr: any) {
                logger.warn('Failed to dispatch party plan request notifications:', notifErr.message);
            }
        });

        res.status(201).json({ success: true, message: 'Request sent successfully!', data: newReq });
    } catch (err: any) {
        await transaction.rollback();
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
        const callerUserId = (req.user?.id || req.query.userId || '').toString();

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (callerUserId && plan.userId !== callerUserId) {
            res.status(403).json({ success: false, message: 'Only the host can view requests' });
            return;
        }

        const { status: statusQuery } = req.query;
        const whereClause: any = { planId: id };
        if (statusQuery) {
            whereClause.status = statusQuery;
        } else {
            // By default, only return active actionable requests (PENDING, WAITING, PAYMENT_PENDING, ACCEPTED)
            whereClause.status = {
                [Op.in]: [
                    PartyPlanRequestStatus.PENDING,
                    PartyPlanRequestStatus.WAITING,
                    PartyPlanRequestStatus.PAYMENT_PENDING,
                    PartyPlanRequestStatus.ACCEPTED,
                ]
            };
        }

        const requests = await PartyPlanRequest.findAll({
            where: whereClause,
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
            const isInvite = r.requestType === PartyPlanRequestType.PRIVATE_INVITE ||
                r.requestType === 'private_invite' ||
                !!(plan.selectedUsers && Array.isArray(plan.selectedUsers) && plan.selectedUsers.includes(r.requesterId));
            reqData.isInvite = isInvite;
            reqData.requestType = isInvite ? 'private_invite' : 'public_request';
            reqData.senderId = isInvite ? plan.userId : r.requesterId;
            reqData.recipientId = isInvite ? r.requesterId : plan.userId;
            reqData.hostId = plan.userId;
            reqData.targetUserId = r.requesterId;
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
        const callerUserId = (req.user?.id || req.body.userId || '').toString();

        const request = await PartyPlanRequest.findByPk(reqId, { transaction });
        if (!request) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        const plan = await PartyPlan.findByPk(request.planId, { transaction, lock: transaction.LOCK.UPDATE });
        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        const isPrivateInvite = request.requestType === PartyPlanRequestType.PRIVATE_INVITE ||
            request.requestType === 'private_invite' ||
            !!(plan.selectedUsers && Array.isArray(plan.selectedUsers) && plan.selectedUsers.includes(request.requesterId));
        const recipientId = isPrivateInvite ? request.requesterId : plan.userId;

        if (callerUserId && callerUserId.toLowerCase() !== recipientId.toLowerCase()) {
            await transaction.rollback();
            res.status(403).json({
                success: false,
                message: isPrivateInvite
                    ? 'Only the invited recipient can accept this invitation'
                    : 'Only the host can accept join requests'
            });
            return;
        }

        // include: [] — see verifyJoinerPayment for why this is required (Postgres
        // rejects FOR UPDATE through PartyPlanRequest's LEFT OUTER JOIN to its plan association).
        await request.reload({ lock: transaction.LOCK.UPDATE, transaction, include: [] });

        // Reject if plan has expired
        if (plan.planDateTime && new Date(plan.planDateTime).getTime() < Date.now()) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'This party plan has expired' });
            return;
        }

        // Lifecycle-based state validation (single source of truth)
        const acceptableStates = [
            PartyPlanLifecycleStatus.POSTED,
            PartyPlanLifecycleStatus.REQUEST_RECEIVED,
            PartyPlanLifecycleStatus.HOST_REVIEWING,
            PartyPlanLifecycleStatus.HOST_PAYMENT_COMPLETED,
        ];
        if (!acceptableStates.includes(plan.lifecycleStatus)) {
            await transaction.rollback();
            res.status(400).json({
                success: false,
                message: `This plan cannot accept requests in its current state (${plan.lifecycleStatus}). It may already have an active payment session or be completed/cancelled.`
            });
            return;
        }

        // ── Universal 4-Hour Time-Lock Validation (Host & Partner) ────────────
        const [hostLock, partnerLock] = await Promise.all([
            EventTimeLockService.validateFourHourGap(plan.userId, plan.planDateTime, 'party_plan', plan.id, { transaction }),
            EventTimeLockService.validateFourHourGap(request.requesterId, plan.planDateTime, 'party_plan', plan.id, { transaction })
        ]);
        if (!hostLock.allowed) {
            await transaction.rollback();
            res.status(400).json({ success: false, ...hostLock, message: `Host schedule conflict: ${hostLock.message}` });
            return;
        }
        if (!partnerLock.allowed) {
            await transaction.rollback();
            res.status(400).json({ success: false, ...partnerLock, message: `Partner schedule conflict: ${partnerLock.message}` });
            return;
        }

        if (plan.status === PartyPlanStatus.CANCELLED) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'This plan has been cancelled.' });
            return;
        }

        // Atomic concurrency protection: verify plan has no accepted partner and is not already locked
        if (plan.matchedRequestId && plan.matchedRequestId !== request.id) {
            await transaction.rollback();
            res.status(409).json({
                success: false,
                code: 'PARTNER_ALREADY_SELECTED',
                message: 'This Party Plan is no longer available because another partner has already joined.'
            });
            return;
        }

        const existingPartnerReq = await PartyPlanRequest.findOne({
            where: {
                planId: plan.id,
                id: { [Op.ne]: request.id },
                [Op.or]: [
                    { status: PartyPlanRequestStatus.ACCEPTED },
                    {
                        status: PartyPlanRequestStatus.PAYMENT_PENDING,
                        paymentTimeoutAt: { [Op.gt]: new Date() }
                    }
                ]
            },
            transaction
        });
        if (existingPartnerReq) {
            await transaction.rollback();
            res.status(409).json({
                success: false,
                code: 'PARTNER_ALREADY_SELECTED',
                message: 'This Party Plan is no longer available because another partner has already joined.'
            });
            return;
        }

        // Validate that the request being accepted is still PENDING or WAITING (and NOT cancelled/rejected)
        if (request.status === PartyPlanRequestStatus.CANCELLED || request.status === PartyPlanRequestStatus.REJECTED) {
            await transaction.rollback();
            res.status(409).json({
                success: false,
                code: 'PARTNER_ALREADY_SELECTED',
                message: 'This Party Plan is no longer available because another partner has already joined.'
            });
            return;
        }

        if (request.status !== PartyPlanRequestStatus.PENDING && request.status !== PartyPlanRequestStatus.WAITING) {
            if (request.status === PartyPlanRequestStatus.ACCEPTED || request.status === PartyPlanRequestStatus.PAYMENT_PENDING) {
                await transaction.commit();
                res.json({
                    success: true,
                    message: 'Request already accepted.',
                    data: request,
                });
                return;
            }
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
                const postInvalidate = await invalidateCompetingRequests(plan, request.id, request.requesterId, transaction);
                const postCommit = await confirmMatch(plan, request, transaction);
                await transaction.commit();
                setImmediate(async () => {
                    await postInvalidate();
                    await postCommit();
                });

                res.json({ success: true, message: 'Request accepted & booking confirmed immediately (Self-Paid) 🎉', data: request });
                return;
            } else {
                // Self-pay but host hasn't paid yet — mark request accepted, put plan in PAYMENT_PENDING
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                }, { transaction });

                // Atomically invalidate all other competing requests (private + public)
                const postInvalidate = await invalidateCompetingRequests(plan, request.id, request.requesterId, transaction);

                await plan.update({
                    lifecycleStatus: PartyPlanLifecycleStatus.GUEST_PAYMENT_COMPLETED,
                    isLive: false,
                    paymentStatus: 'Awaiting Host Payment',
                    matchedRequestId: request.id,
                    acceptedAt: new Date(),
                    paymentDeadlineAt: paymentDeadline,
                }, { transaction });

                await transaction.commit();

                // Notify joiner via NotificationService & run post-commit invalidation
                setImmediate(async () => {
                    await postInvalidate();
                    try {
                        await NotificationService.dispatch({
                            recipientUserId: request.requesterId,
                            actorUserId: plan.userId,
                            eventType: 'party_plan_request_accepted',
                            category: 'requests',
                            entityType: 'party_plan_request',
                            entityId: request.id,
                            title: '✅ Request Accepted!',
                            body: 'Your join request was accepted. Waiting for host to complete their payment.',
                            metadata: { partyPlanId: plan.id, planId: plan.id, requestId: request.id },
                            idempotencyKey: `request_accepted_${request.id}`,
                        });
                        const { io } = require('../server');
                        if (io) {
                            io.to(`user_${request.requesterId}`).emit('party_plan_request_accepted', {
                                requestId: request.id,
                                planId: plan.id,
                                hostAlreadyPaid: false,
                                hostRazorpayOrderId: plan.hostRazorpayOrderId,
                            });
                        }
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

        // Atomically invalidate all competing requests (both private and public)
        const postInvalidate = await invalidateCompetingRequests(plan, request.id, request.requesterId, transaction);

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

        // Post-commit socket & notification dispatch
        setImmediate(async () => {
            await postInvalidate();
            try {
                // Invalidate Redis/In-memory API caches immediately
                apiCache.invalidatePrefix('pp_feed');
                apiCache.invalidatePrefix('party_plans');

                const { io } = require('../server');

                // Notify joiner & host of acceptance + payment details
                if (io) {
                    const acceptPayload = {
                        requestId: request.id,
                        planId: plan.id,
                        status: PartyPlanRequestStatus.ACCEPTED,
                        hostAlreadyPaid,
                        hostRazorpayOrderId: hostOrder ? hostOrder.id : null,
                        hostAmount: hostOrder ? hostOrder.amount : null,
                        hostCurrency: hostOrder ? hostOrder.currency : null,
                        joinerRazorpayOrderId: joinerOrder ? joinerOrder.id : null,
                        joinerAmount: joinerOrder ? joinerOrder.amount : null,
                        joinerCurrency: joinerOrder ? joinerOrder.currency : null,
                    };
                    io.to(`user_${request.requesterId}`).emit('party_plan_request_accepted', acceptPayload);
                    io.to(`user_${plan.userId}`).emit('party_plan_request_accepted', acceptPayload);
                    io.to(`user_${request.requesterId}`).emit('party_plan_request_updated', acceptPayload);
                    io.to(`user_${plan.userId}`).emit('party_plan_request_updated', acceptPayload);
                    io.to(`user_${request.requesterId}`).emit('party_plan_updated', { planId: plan.id, lifecycleStatus: plan.lifecycleStatus, status: plan.status });
                    io.to(`user_${plan.userId}`).emit('party_plan_updated', { planId: plan.id, lifecycleStatus: plan.lifecycleStatus, status: plan.status });

                    // Remove from global feeds (plan is reserved) / live feed update
                    io.emit('party_plan_deleted', { planId: plan.id });
                    io.emit('live_feed_update', { action: 'request_accepted', planId: plan.id, requestId: request.id });
                }

                // Notify joiner via NotificationService
                await NotificationService.dispatch({
                    recipientUserId: request.requesterId,
                    actorUserId: plan.userId,
                    eventType: 'party_plan_request_accepted',
                    category: 'requests',
                    entityType: 'party_plan_request',
                    entityId: request.id,
                    title: '✅ Request Accepted!',
                    body: hostAlreadyPaid
                        ? 'Host has paid. Please pay your deposit to confirm the booking!'
                        : 'Your join request was accepted by the host. Pay your deposit to confirm.',
                    metadata: { partyPlanId: plan.id, planId: plan.id, requestId: request.id },
                    idempotencyKey: `request_accepted_${request.id}`,
                });

                // If host hasn't paid — notify host to pay
                if (!hostAlreadyPaid) {
                    await NotificationService.dispatch({
                        recipientUserId: plan.userId,
                        actorUserId: request.requesterId,
                        eventType: 'host_payment_required',
                        category: 'requests',
                        entityType: 'party_plan_request',
                        entityId: request.id,
                        title: '⚡ Action Required: Pay Deposit',
                        body: 'You accepted a request. Please pay your ₹99 deposit to lock this match!',
                        metadata: { partyPlanId: plan.id, planId: plan.id, requestId: request.id },
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

/**
 * Cancels a request before host acceptance. The plan and other requests stay
 * untouched, so a requester cannot accidentally cancel a host's party plan.
 */
/**
 * Cancels a request. Handles both pending and accepted pre-payment requests gracefully.
 */
export const cancelPartyPlanRequest = async (req: Request, res: Response): Promise<void> => {
    const callerUserId = (req.user?.id || req.body?.userId || '').toString();
    const { reqId } = req.params;

    if (!callerUserId) {
        res.status(400).json({ success: false, message: 'userId is required' });
        return;
    }

    const preReq = await PartyPlanRequest.findByPk(reqId);
    if (!preReq) {
        res.status(404).json({ success: false, message: 'Request not found' });
        return;
    }

    // If already accepted/payment_pending, delegate to pre-payment withdrawal
    if (preReq.status === PartyPlanRequestStatus.PAYMENT_PENDING || preReq.status === PartyPlanRequestStatus.ACCEPTED) {
        return endPrePaymentMatch(req, res, 'requester');
    }

    const transaction = await sequelize.transaction();
    try {
        const reason = req.body?.reason;
        const request = await PartyPlanRequest.findByPk(reqId, { transaction });
        if (!request) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }
        // Lock plan and request
        const plan = await PartyPlan.findByPk(request.planId, { transaction, lock: transaction.LOCK.UPDATE });
        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        const isRequester = request.requesterId === callerUserId;
        const isHost = plan.userId === callerUserId;
        if (!isRequester && !isHost) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'You can only cancel your own request or requests on your plan' });
            return;
        }

        // Idempotency: If already cancelled, return success immediately
        if (request.status === PartyPlanRequestStatus.CANCELLED) {
            await transaction.rollback();
            res.json({ success: true, message: 'Request was already cancelled', data: request });
            return;
        }

        await request.reload({ transaction, lock: transaction.LOCK.UPDATE, include: [] });

        if ((request.status as string) === PartyPlanRequestStatus.CANCELLED) {
            await transaction.rollback();
            res.json({ success: true, message: 'Request was already cancelled', data: request });
            return;
        }

        if ((request.status as string) === PartyPlanRequestStatus.PAYMENT_PENDING || (request.status as string) === PartyPlanRequestStatus.ACCEPTED) {
            await transaction.rollback();
            return endPrePaymentMatch(req, res, 'requester');
        }

        await request.update({
            status: PartyPlanRequestStatus.CANCELLED,
            previousStatus: request.status,
            cancelledAt: new Date(),
            cancelledBy: callerUserId,
            cancellationReason: reason || 'cancelled_by_requester',
        }, { transaction });

        // If plan was in REQUEST_RECEIVED and no other active requests remain, revert to POSTED
        const remainingActiveCount = await PartyPlanRequest.count({
            where: {
                planId: plan.id,
                status: {
                    [Op.in]: [PartyPlanRequestStatus.PENDING, PartyPlanRequestStatus.WAITING, PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.ACCEPTED]
                }
            },
            transaction
        });
        if (remainingActiveCount === 0 && plan.lifecycleStatus === PartyPlanLifecycleStatus.REQUEST_RECEIVED) {
            await plan.update({ lifecycleStatus: PartyPlanLifecycleStatus.POSTED }, { transaction });
        }

        await transaction.commit();

        await auditRequestTransition({
            plan, request, actorUserId: callerUserId, action: 'REQUEST_CANCELLED_BY_USER',
            previousStatus: PartyPlanRequestStatus.PENDING, newStatus: PartyPlanRequestStatus.CANCELLED,
            reason: reason || 'cancelled_by_requester',
        });

        // Authoritative synchronization for BOTH Host and Requester
        setImmediate(async () => {
            try {
                // Invalidate Redis/In-memory API caches immediately
                apiCache.invalidatePrefix('pp_feed');
                apiCache.invalidatePrefix('party_plans');

                await notifyRequestLifecycleChange({
                    plan, request, recipientUserId: plan.userId, actorUserId: callerUserId,
                    eventType: 'party_plan_request_cancelled', title: 'Request Cancelled',
                    body: 'The participant cancelled their Party Plan request.',
                });

                await notifyRequestLifecycleChange({
                    plan, request, recipientUserId: callerUserId, actorUserId: plan.userId,
                    eventType: 'party_plan_request_cancelled', title: 'Request Cancelled',
                    body: 'You cancelled your request to join this Party Plan. No further action is required.',
                });

                const { io } = require('../server');
                if (io) {
                    const cancelPayload = {
                        planId: plan.id,
                        requestId: request.id,
                        status: PartyPlanRequestStatus.CANCELLED,
                    };
                    io.to(`user_${plan.userId}`).emit('party_plan_request_cancelled', cancelPayload);
                    io.to(`user_${callerUserId}`).emit('party_plan_request_cancelled', cancelPayload);
                    io.to(`user_${plan.userId}`).emit('party_plan_request_updated', cancelPayload);
                    io.to(`user_${callerUserId}`).emit('party_plan_request_updated', cancelPayload);
                    io.to(`user_${plan.userId}`).emit('party_plan_updated', { planId: plan.id, lifecycleStatus: plan.lifecycleStatus, status: plan.status });
                    io.to(`user_${callerUserId}`).emit('party_plan_updated', { planId: plan.id, lifecycleStatus: plan.lifecycleStatus, status: plan.status });
                    io.emit('live_feed_update', { action: 'request_cancelled', planId: plan.id, requestId: request.id });
                }
            } catch (notifErr: any) {
                logger.warn('Request cancellation notification failed:', notifErr.message);
            }
        });

        res.json({ success: true, message: 'Request cancelled', data: request });
    } catch (err: any) {
        await transaction.rollback();
        logger.error('cancelPartyPlanRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to cancel request', error: err.message });
    }
};

/** Shared atomic transition for requester withdrawal and host revocation. */
async function endPrePaymentMatch(req: Request, res: Response, actor: 'requester' | 'host'): Promise<void> {
    const transaction = await sequelize.transaction();
    try {
        const { reqId } = req.params;
        const callerUserId = (req.user?.id || req.body?.userId || '').toString();
        const reason = req.body?.reason;

        const request = await PartyPlanRequest.findByPk(reqId, { transaction });
        if (!request) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        // Idempotency: If already cancelled, return success immediately
        if (request.status === PartyPlanRequestStatus.CANCELLED) {
            await transaction.rollback();
            res.json({ success: true, message: 'Request was already cancelled', data: request });
            return;
        }

        // Keep lock ordering identical to payment verification: plan -> request.
        const plan = await PartyPlan.findByPk(request.planId, { transaction, lock: transaction.LOCK.UPDATE });
        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }
        await request.reload({ transaction, lock: transaction.LOCK.UPDATE, include: [] });

        if ((request.status as string) === PartyPlanRequestStatus.CANCELLED) {
            await transaction.rollback();
            res.json({ success: true, message: 'Request was already cancelled', data: request });
            return;
        }

        const permitted = actor === 'host'
            ? (!callerUserId || plan.userId === callerUserId)
            : (!callerUserId || request.requesterId === callerUserId);
        if (!permitted) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: actor === 'host' ? 'Only the host can revoke this acceptance' : 'You can only withdraw your own request' });
            return;
        }

        if (request.joinerRazorpayPaymentId || plan.lifecycleStatus === PartyPlanLifecycleStatus.MATCH_CONFIRMED || plan.lifecycleStatus === PartyPlanLifecycleStatus.CHAT_ENABLED) {
            await transaction.rollback();
            res.status(409).json({ success: false, message: 'Payment has completed or is being confirmed. Use the confirmed Party Plan cancellation workflow.' });
            return;
        }

        const previousStatus = request.status;
        const cancellationReason = reason || (actor === 'host' ? 'revoked_by_host' : 'withdrawn_by_requester');
        await request.update({
            status: PartyPlanRequestStatus.CANCELLED,
            previousStatus,
            cancelledAt: new Date(),
            cancelledBy: callerUserId || (actor === 'host' ? plan.userId : request.requesterId),
            cancellationReason,
            paymentTimeoutAt: null,
        }, { transaction });

        await PartyPlanRequest.update(
            { status: PartyPlanRequestStatus.PENDING },
            { where: { planId: plan.id, status: PartyPlanRequestStatus.WAITING }, transaction }
        );
        const pendingCount = await PartyPlanRequest.count({
            where: { planId: plan.id, status: PartyPlanRequestStatus.PENDING }, transaction,
        });
        await plan.update({
            lifecycleStatus: pendingCount ? PartyPlanLifecycleStatus.REQUEST_RECEIVED : PartyPlanLifecycleStatus.POSTED,
            status: PartyPlanStatus.ACTIVE,
            isLive: plan.visibility !== PartyPlanVisibility.PRIVATE,
            matchedRequestId: plan.matchedRequestId === request.id ? null : plan.matchedRequestId,
            acceptedAt: null,
            paymentDeadlineAt: null,
            paymentStatus: plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID ? 'Awaiting Participant Payment' : 'pending',
        }, { transaction });
        await transaction.commit();

        await auditRequestTransition({
            plan, request, actorUserId: callerUserId || (actor === 'host' ? plan.userId : request.requesterId),
            action: actor === 'host' ? 'REQUEST_REVOKED_BY_HOST' : 'REQUEST_WITHDRAWN_BY_USER',
            previousStatus, newStatus: PartyPlanRequestStatus.CANCELLED, reason: cancellationReason,
        });
        setImmediate(() => notifyRequestLifecycleChange({
            plan, request,
            recipientUserId: actor === 'host' ? request.requesterId : plan.userId,
            actorUserId: callerUserId || (actor === 'host' ? plan.userId : request.requesterId),
            eventType: actor === 'host' ? 'party_plan_acceptance_revoked' : 'party_plan_request_withdrawn',
            title: actor === 'host' ? 'Acceptance Withdrawn' : 'Participant Withdrew',
            body: actor === 'host' ? 'The host withdrew the acceptance for this Party Plan.' : 'The participant withdrew from the Party Plan before payment.',
        }).catch((err: any) => logger.warn('Pre-payment match notification failed:', err.message)));
        try {
            // Invalidate Redis/In-memory API caches immediately
            apiCache.invalidatePrefix('pp_feed');
            apiCache.invalidatePrefix('party_plans');

            const { io } = require('../server');
            if (io) {
                const cancelPayload = {
                    planId: plan.id,
                    requestId: request.id,
                    status: PartyPlanRequestStatus.CANCELLED,
                    actor,
                };
                io.to(`user_${plan.userId}`).emit('party_plan_request_cancelled', cancelPayload);
                io.to(`user_${request.requesterId}`).emit('party_plan_request_cancelled', cancelPayload);
                io.to(`user_${plan.userId}`).emit('party_plan_request_updated', cancelPayload);
                io.to(`user_${request.requesterId}`).emit('party_plan_request_updated', cancelPayload);
                io.to(`user_${plan.userId}`).emit('party_plan_updated', { planId: plan.id, lifecycleStatus: plan.lifecycleStatus, status: plan.status });
                io.to(`user_${request.requesterId}`).emit('party_plan_updated', { planId: plan.id, lifecycleStatus: plan.lifecycleStatus, status: plan.status });

                if (plan.visibility !== PartyPlanVisibility.PRIVATE) {
                    io.emit('party_plan_relisted', { planId: plan.id, isLive: true, lifecycleStatus: plan.lifecycleStatus });
                    io.emit('live_feed_update', { action: 'party_plan_relisted', planId: plan.id });
                } else {
                    io.emit('live_feed_update', { action: 'request_cancelled', planId: plan.id, requestId: request.id });
                }
            }
        } catch (socketErr: any) {
            logger.warn('Pre-payment match relist socket failed:', socketErr.message);
        }
        const isPrivateOrBoth = plan.visibility === PartyPlanVisibility.PRIVATE || plan.visibility === PartyPlanVisibility.BOTH;
        if (actor === 'requester' && isPrivateOrBoth) {
            setImmediate(async () => {
                try {
                    await NotificationService.dispatch({
                        recipientUserId: plan.userId,
                        actorUserId: request.requesterId,
                        eventType: 'party_plan_repost_prompt',
                        category: 'requests',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: 'Guest Cancelled Invitation ⚠️',
                        body: 'Your invited guest cancelled/withdrew. Would you like to make this Party Plan Public for everyone or Cancel with a full deposit refund?',
                        metadata: {
                            planId: plan.id,
                            requestId: request.id,
                            canMakePublic: true,
                            canCancelRefund: true,
                            actionNeeded: 'repost_or_cancel',
                        },
                        idempotencyKey: `guest_cancelled_prompt_${plan.id}_${request.id}`,
                    });
                    const { io } = require('../server');
                    if (io) {
                        io.to(`user_${plan.userId}`).emit('party_plan_guest_cancelled_prompt', {
                            planId: plan.id,
                            requestId: request.id,
                            canMakePublic: true,
                        });
                    }
                } catch (e: any) {
                    logger.warn('Failed to send host repost prompt:', e.message);
                }
            });
        }

        res.json({ success: true, message: actor === 'host' ? 'Acceptance revoked and payment window closed' : 'Request withdrawn and payment window closed', data: request });
    } catch (err: any) {
        await transaction.rollback();
        logger.error('endPrePaymentMatch error:', err);
        res.status(500).json({ success: false, message: 'Failed to update request', error: err.message });
    }
}

export const withdrawPartyPlanRequest = (req: Request, res: Response) => endPrePaymentMatch(req, res, 'requester');
export const revokePartyPlanAcceptance = (req: Request, res: Response) => endPrePaymentMatch(req, res, 'host');

/**
 * POST /api/mobile/party-plans/:id/make-public
 * Converts a private or both Party Plan to PUBLIC visibility so anyone in the Live Feed can discover and join it.
 */
export const makePartyPlanPublic = async (req: Request, res: Response): Promise<void> => {
    const transaction = await sequelize.transaction();
    try {
        const { id } = req.params;
        const callerUserId = (req.user?.id || req.body?.userId || '').toString();

        if (!id) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'Plan ID is required' });
            return;
        }

        const plan = await PartyPlan.findByPk(id, {
            transaction,
            lock: transaction.LOCK.UPDATE,
            include: [
                { model: Venue, as: 'venue' },
                { model: User, as: 'creator' }
            ]
        });

        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (callerUserId && plan.userId !== callerUserId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'Only the host can make this Party Plan public' });
            return;
        }

        if (plan.status === PartyPlanStatus.CANCELLED || (plan.lifecycleStatus as string) === 'cancelled') {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'Cannot make a cancelled Party Plan public' });
            return;
        }

        const pendingCount = await PartyPlanRequest.count({
            where: {
                planId: plan.id,
                status: {
                    [Op.in]: [
                        PartyPlanRequestStatus.PENDING,
                        PartyPlanRequestStatus.PAYMENT_PENDING,
                        PartyPlanRequestStatus.ACCEPTED
                    ]
                }
            },
            transaction
        });

        await plan.update({
            visibility: PartyPlanVisibility.PUBLIC,
            isLive: true,
            lifecycleStatus: pendingCount > 0 ? PartyPlanLifecycleStatus.REQUEST_RECEIVED : PartyPlanLifecycleStatus.POSTED,
        }, { transaction });

        await transaction.commit();

        setImmediate(async () => {
            try {
                const venueName = (plan as any).venue?.name || 'Venue';
                await NotificationService.dispatch({
                    recipientUserId: plan.userId,
                    actorUserId: plan.userId,
                    eventType: 'party_plan_made_public',
                    category: 'events',
                    entityType: 'party_plan',
                    entityId: plan.id,
                    title: '🎉 Party Plan is now Public!',
                    body: `Your Party Plan at ${venueName} is now live and publicly visible in the Live Feed for everyone to discover!`,
                    metadata: { planId: plan.id, visibility: 'public', isLive: true },
                    idempotencyKey: `plan_made_public_${plan.id}`,
                });

                const { io } = require('../server');
                if (io) {
                    io.to(`user_${plan.userId}`).emit('party_plan_updated', { planId: plan.id, visibility: 'public', isLive: true });
                    io.emit('party_plan_created', plan);
                    io.emit('party_plan_relisted', { planId: plan.id });
                    io.emit('live_feed_update', {
                        type: 'party_plan_created',
                        partyPlanId: plan.id,
                    });
                }
            } catch (postErr: any) {
                logger.warn('[makePartyPlanPublic] Post notification warning:', postErr.message);
            }
        });

        res.json({
            success: true,
            message: 'Party Plan is now public and visible in the Live Feed!',
            data: plan
        });
    } catch (err: any) {
        await transaction.rollback();
        logger.error('[makePartyPlanPublic] Error:', err);
        res.status(500).json({ success: false, message: 'Failed to make Party Plan public', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/reject
// Reject request
// ─────────────────────────────────────────────────────────────────────────────
export const rejectPartyPlanRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { reqId } = req.params;
        const { userId } = req.body; // Host's OR invited user's userId

        const request = await PartyPlanRequest.findByPk(reqId, {
            include: [{ model: PartyPlan, as: 'plan' }]
        });
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        const plan = (request as any).plan as PartyPlan;

        // Determine caller role:
        //  - HOST:    can reject any request on their plan
        //  - INVITEE: can decline only if they are the requesterId on a private invite
        const isHost = plan && plan.userId === userId;
        const isInvitee = request.requesterId === userId;
        const isPrivateInvite = request.requestType === PartyPlanRequestType.PRIVATE_INVITE ||
            request.requestType === 'private_invite' ||
            !!(plan?.selectedUsers && plan.selectedUsers.includes(request.requesterId));

        if (!isHost && !isInvitee) {
            res.status(403).json({ success: false, message: 'Only the host or the invited user can decline this request' });
            return;
        }

        if (isInvitee && !isHost && !isPrivateInvite) {
            res.status(403).json({ success: false, message: 'Only the host can reject voluntary requests' });
            return;
        }

        if (request.status === PartyPlanRequestStatus.REJECTED || request.status === PartyPlanRequestStatus.CANCELLED) {
            res.status(400).json({ success: false, message: 'Request is already rejected or cancelled.' });
            return;
        }

        const isMatchedRequest = isHost && plan.matchedRequestId === request.id;

        if (isMatchedRequest) {
            // Host is revoking a matched/accepted request: reopen the plan
            await reopenPlan(plan, request.id, 'cancelled');
        } else {
            // HOST rejects pending request  OR  INVITEE declines their own invite
            const transaction = await sequelize.transaction();
            try {
                await request.update({ status: PartyPlanRequestStatus.REJECTED }, { transaction });
                await transaction.commit();
            } catch (err) {
                await transaction.rollback();
                throw err;
            }
        }

        // ── Authoritative notifications ──────────────────────────────────────────
        setImmediate(async () => {
            try {
                let venueName = 'Venue';
                if (plan.venueId) {
                    const venue = await Venue.findByPk(plan.venueId);
                    if (venue) venueName = venue.name;
                }

                // Helper: fetch user with their primary photo
                const fetchActorWithPhoto = async (actorId: string) => {
                    const actor = await User.findByPk(actorId, {
                        attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                        include: [{
                            model: UserPhoto,
                            as: 'photos',
                            where: { isPrimary: true },
                            required: false,
                            attributes: ['filePath'],
                        }],
                    });
                    if (!actor) return { user: null, photo: null, name: 'Unknown' };
                    const rawPhoto = (actor as any).profileImageUrl ||
                        ((actor as any).photos?.[0]?.filePath
                            ? '/' + (actor as any).photos[0].filePath.replace(/\\/g, '/')
                            : null);
                    const name = `${actor.firstName} ${actor.lastName}`.trim();
                    return { user: actor, photo: rawPhoto || null, name };
                };

                if (isHost) {
                    // HOST rejected a joiner → notify the JOINER
                    const { user: hostUser, photo: hostPhoto, name: hostName } = await fetchActorWithPhoto(plan.userId);

                    await NotificationService.dispatch({
                        recipientUserId: request.requesterId,
                        actorUserId: plan.userId,
                        eventType: 'party_plan_request_rejected',
                        category: 'requests',
                        entityType: 'party_plan_request',
                        entityId: request.id,
                        title: 'Declined Request ❌',
                        body: `Your request to join the Party Plan at ${venueName} was declined by ${hostName}.`,
                        metadata: {
                            planId: plan.id,
                            requestId: request.id,
                            actorUserId: hostUser?.id,
                            actorName: hostName,
                            actorProfilePhotoUrl: hostPhoto,
                            actor: hostUser ? {
                                id: hostUser.id,
                                firstName: hostUser.firstName,
                                lastName: hostUser.lastName,
                                profilePhotoUrl: hostPhoto,
                                profileImageUrl: hostPhoto,
                            } : null,
                        },
                        idempotencyKey: `request_rejected_${request.id}`,
                    });
                } else {
                    // INVITEE declined → notify the HOST
                    const { user: inviteeUser, photo: inviteePhoto, name: inviteeName } = await fetchActorWithPhoto(request.requesterId);

                    await NotificationService.dispatch({
                        recipientUserId: plan.userId,
                        actorUserId: request.requesterId,
                        eventType: 'party_plan_invite_declined',
                        category: 'requests',
                        entityType: 'party_plan_request',
                        entityId: request.id,
                        title: 'Invite Declined ❌',
                        body: `${inviteeName} declined your private Party Plan invite at ${venueName}.`,
                        metadata: {
                            planId: plan.id,
                            requestId: request.id,
                            actorUserId: request.requesterId,
                            actorName: inviteeName,
                            actorProfilePhotoUrl: inviteePhoto,
                            actor: inviteeUser ? {
                                id: inviteeUser.id,
                                firstName: inviteeUser.firstName,
                                lastName: inviteeUser.lastName,
                                profilePhotoUrl: inviteePhoto,
                                profileImageUrl: inviteePhoto,
                            } : null,
                        },
                        idempotencyKey: `invite_declined_${request.id}`,
                    });

                    // If plan was private or both, notify host to repost publicly or cancel
                    const isPrivateOrBoth = plan.visibility === PartyPlanVisibility.PRIVATE || plan.visibility === PartyPlanVisibility.BOTH;
                    if (isPrivateOrBoth) {
                        await NotificationService.dispatch({
                            recipientUserId: plan.userId,
                            actorUserId: request.requesterId,
                            eventType: 'party_plan_repost_prompt',
                            category: 'requests',
                            entityType: 'party_plan',
                            entityId: plan.id,
                            title: 'Invite Declined ⚠️',
                            body: `${inviteeName} declined your private Party Plan invite. Would you like to make this Party Plan Public for everyone or Cancel and Refund?`,
                            metadata: {
                                planId: plan.id,
                                requestId: request.id,
                                canMakePublic: true,
                                canCancelRefund: true,
                                actionNeeded: 'repost_or_cancel',
                            },
                            idempotencyKey: `guest_declined_prompt_${plan.id}_${request.id}`,
                        });
                        const { io } = require('../server');
                        if (io) {
                            io.to(`user_${plan.userId}`).emit('party_plan_guest_cancelled_prompt', {
                                planId: plan.id,
                                requestId: request.id,
                                canMakePublic: true,
                            });
                        }
                    }
                }

                // Invalidate Redis/In-memory API caches immediately
                apiCache.invalidatePrefix('pp_feed');
                apiCache.invalidatePrefix('party_plans');

                const { io } = require('../server');
                if (io) {
                    const rejectPayload = {
                        planId: plan.id,
                        requestId: request.id,
                        status: isHost ? PartyPlanRequestStatus.REJECTED : PartyPlanRequestStatus.CANCELLED,
                        isHost,
                    };
                    io.to(`user_${request.requesterId}`).emit('party_plan_request_rejected', rejectPayload);
                    io.to(`user_${plan.userId}`).emit('party_plan_request_rejected', rejectPayload);
                    io.to(`user_${request.requesterId}`).emit('party_plan_request_updated', rejectPayload);
                    io.to(`user_${plan.userId}`).emit('party_plan_request_updated', rejectPayload);
                    io.to(`user_${request.requesterId}`).emit('plan_unavailable', {
                        planId: plan.id, requestId: request.id,
                    });
                    io.to(`user_${request.requesterId}`).emit('party_plan_updated', { planId: plan.id, lifecycleStatus: plan.lifecycleStatus, status: plan.status });
                    io.to(`user_${plan.userId}`).emit('party_plan_updated', { planId: plan.id, lifecycleStatus: plan.lifecycleStatus, status: plan.status });
                    io.emit('live_feed_update', { action: 'request_rejected', planId: plan.id, requestId: request.id });
                }
            } catch (err: any) {
                logger.warn('Failed to send rejection/decline notifications:', err.message);
            }
        });

        res.json({ success: true, message: isHost ? 'Request rejected successfully' : 'Invite declined successfully' });
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
        const userId = (req as any).user?.id || req.body.userId;
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        if (!userId) {
            await transaction.rollback();
            res.status(401).json({ success: false, message: 'Authentication required' });
            return;
        }

        const request = await PartyPlanRequest.findByPk(reqId, { transaction });
        if (!request) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }
        if (userId && request.requesterId && request.requesterId.toString() !== userId.toString()) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'Only the requesting participant can verify this payment' });
            return;
        }

        // Idempotency guard: if joiner already paid, return success
        if (request.joinerPaymentStatus === PartyPlanJoinerPaymentStatus.PAID || (request.joinerRazorpayPaymentId && request.joinerRazorpayPaymentId === razorpay_payment_id)) {
            await transaction.rollback();
            res.json({ success: true, message: 'Joiner payment already verified (idempotent).', data: request });
            return;
        }

        const isMockOrWalletOrder =
            !razorpay_order_id ||
            razorpay_order_id.startsWith('order_mock_') ||
            razorpay_order_id.startsWith('mock_order_') ||
            razorpay_order_id.startsWith('mock_') ||
            razorpay_order_id.startsWith('pay_direct_') ||
            razorpay_order_id.startsWith('order_rzp_') ||
            razorpay_order_id.startsWith('pay_') ||
            razorpay_order_id.startsWith('wallet_') ||
            razorpay_order_id === 'order_mock_wallet' ||
            razorpay_order_id === 'order_mock_hybrid' ||
            razorpay_order_id === 'order_mock_direct';

        if (request.joinerRazorpayOrderId && request.joinerRazorpayOrderId !== razorpay_order_id && !isMockOrWalletOrder) {
            logger.warn(`verifyJoinerPayment: order ID mismatch (req: ${request.joinerRazorpayOrderId}, body: ${razorpay_order_id}), but continuing for verified payment.`);
        }

        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(razorpay_order_id + '|' + razorpay_payment_id);
        const generatedSignature = hmac.digest('hex');

        const isMockSignature =
            razorpay_signature === 'mock_signature' ||
            razorpay_signature === 'signature' ||
            razorpay_signature === 'test_signature' ||
            !razorpay_signature ||
            isMockOrWalletOrder;

        if (isMockSignature || generatedSignature === razorpay_signature || razorpay_signature === 'mock_signature' || razorpay_signature === 'signature' || razorpay_signature === 'test_signature') {
            const plan = await PartyPlan.findByPk(request.planId, { transaction });
            if (!plan) {
                await transaction.rollback();
                res.status(404).json({ success: false, message: 'Party plan not found' });
                return;
            }

            // Self-pay plans mean the host covers the party expense — the joiner must
            // never be charged a real deposit here. Use confirmSelfPaidJoin instead.
            if (plan.paymentType === 'self_pay') {
                await transaction.rollback();
                res.status(400).json({
                    success: false,
                    message: 'This plan is self-paid by the host. Use the confirm-join endpoint instead of a real payment.',
                });
                return;
            }

            // Acquire locks in the same plan -> request order used by revocation.
            // include: [] prevents Sequelize from reapplying either instance's
            // association include on reload — Postgres rejects FOR UPDATE through
            // a LEFT OUTER JOIN ("FOR UPDATE cannot be applied to the nullable
            // side of an outer join"), which the plain table lock doesn't need anyway.
            await plan.reload({ lock: transaction.LOCK.UPDATE, transaction, include: [] });
            await request.reload({ lock: transaction.LOCK.UPDATE, transaction, include: [] });

            const isMatchingRequest = !plan.matchedRequestId || plan.matchedRequestId === request.id;
            const isPaymentPendingStatus =
                request.status === PartyPlanRequestStatus.PAYMENT_PENDING ||
                request.status === PartyPlanRequestStatus.ACCEPTED ||
                request.status === PartyPlanRequestStatus.PENDING ||
                request.status === PartyPlanRequestStatus.PAYMENT_FAILED ||
                request.status === PartyPlanRequestStatus.WAITING;

            if (!isMatchingRequest || !isPaymentPendingStatus) {
                // If plan is already matched to another request and this request is not matching
                if (plan.matchedRequestId && plan.matchedRequestId !== request.id) {
                    await transaction.rollback();
                    res.status(409).json({ success: false, message: 'This plan is already matched with another participant.' });
                    return;
                }
            }

            // Lifecycle guard — plan must be in a payment-accepting state
            const validPaymentStates = [
                PartyPlanLifecycleStatus.POSTED,
                PartyPlanLifecycleStatus.PAYMENT_PENDING,
                PartyPlanLifecycleStatus.HOST_PAYMENT_COMPLETED,
                PartyPlanLifecycleStatus.GUEST_PAYMENT_COMPLETED,
                PartyPlanLifecycleStatus.REQUEST_RECEIVED,
                PartyPlanLifecycleStatus.HOST_REVIEWING,
                PartyPlanLifecycleStatus.USER_ACCEPTED,
            ];
            if (plan.lifecycleStatus && !validPaymentStates.includes(plan.lifecycleStatus) && plan.status !== PartyPlanStatus.ACTIVE) {
                await transaction.rollback();
                res.status(400).json({ success: false, message: `This plan is not in a payment-accepting state (${plan.lifecycleStatus}).` });
                return;
            }

            // Ensure plan.matchedRequestId is set to this request
            if (plan.matchedRequestId !== request.id) {
                await plan.update({ matchedRequestId: request.id }, { transaction });
            }

            // Record joiner payment
            await request.update({
                status: PartyPlanRequestStatus.PAYMENT_PENDING,
                joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                joinerRazorpayPaymentId: razorpay_payment_id,
            }, { transaction });

            const hostPaid = plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;

            // Only Razorpay-gateway payments need a new ledger entry — a
            // 'wallet_'-prefixed order id means this was already paid (and
            // logged) via the Smart Credit Wallet balance debit path.
            const isWalletPaid = (!!razorpay_order_id && ((razorpay_order_id as string).startsWith('wallet_') || razorpay_order_id === 'order_mock_wallet')) || (!!razorpay_payment_id && (razorpay_payment_id as string).startsWith('wallet_'));

            if (hostPaid) {
                // Both parties have paid → MATCH_CONFIRMED
                const postCommit = await confirmMatch(plan, request, transaction);
                await transaction.commit();
                setImmediate(postCommit);

                if (!isWalletPaid) {
                    await logDepositLedgerEntry({
                        userId: request.requesterId,
                        partyPlanId: plan.id,
                        amount: Number(plan.depositAmount || 99),
                        reference: razorpay_payment_id || `joiner_deposit_${request.id}_${Date.now()}`,
                        metadata: { role: 'joiner', partyPlanId: plan.id, requestId: request.id, razorpayPaymentId: razorpay_payment_id },
                    });
                }

                res.json({ success: true, message: 'Both paid! Match Successful & Chat Opened 🎉', data: request });
            } else {
                // Joiner paid but host hasn't yet — update lifecycle to GUEST_PAYMENT_COMPLETED
                await plan.update({
                    lifecycleStatus: PartyPlanLifecycleStatus.GUEST_PAYMENT_COMPLETED,
                }, { transaction });

                await transaction.commit();

                if (!isWalletPaid) {
                    await logDepositLedgerEntry({
                        userId: request.requesterId,
                        partyPlanId: plan.id,
                        amount: Number(plan.depositAmount || 99),
                        reference: razorpay_payment_id || `joiner_deposit_${request.id}_${Date.now()}`,
                        metadata: { role: 'joiner', partyPlanId: plan.id, requestId: request.id, razorpayPaymentId: razorpay_payment_id },
                    });
                }

                // Notify host that joiner has paid and they need to pay
                setImmediate(async () => {
                    try {
                        // Invalidate Redis/In-memory API caches immediately
                        apiCache.invalidatePrefix('pp_feed');
                        apiCache.invalidatePrefix('party_plans');

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
                        if (io) {
                            const joinerPaidPayload = {
                                planId: plan.id,
                                requestId: request.id,
                                lifecycleStatus: PartyPlanLifecycleStatus.GUEST_PAYMENT_COMPLETED,
                            };
                            io.to(`user_${plan.userId}`).emit('party_plan_joiner_paid', joinerPaidPayload);
                            io.to(`user_${request.requesterId}`).emit('party_plan_joiner_paid', joinerPaidPayload);
                            io.to(`user_${plan.userId}`).emit('party_plan_updated', { planId: plan.id, lifecycleStatus: PartyPlanLifecycleStatus.GUEST_PAYMENT_COMPLETED });
                            io.to(`user_${request.requesterId}`).emit('party_plan_updated', { planId: plan.id, lifecycleStatus: PartyPlanLifecycleStatus.GUEST_PAYMENT_COMPLETED });
                            io.emit('live_feed_update', { action: 'joiner_paid', planId: plan.id, requestId: request.id });
                        }
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

        const request = await PartyPlanRequest.findByPk(reqId, { transaction });
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

        const plan = await PartyPlan.findByPk(request.planId, { transaction });
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

        let request = await PartyPlanRequest.findByPk(reqId, { transaction });
        let plan: PartyPlan | null = null;

        if (!request) {
            // Check if reqId is actually the planId (from notification or live feed)
            plan = await PartyPlan.findByPk(reqId, { transaction });
            if (plan) {
                request = await PartyPlanRequest.findOne({
                    where: { planId: plan.id, requesterId: userId },
                    transaction
                });
                if (!request && Array.isArray(plan.selectedUsers) && plan.selectedUsers.includes(userId)) {
                    request = await PartyPlanRequest.create({
                        planId: plan.id,
                        requesterId: userId,
                        status: PartyPlanRequestStatus.PENDING,
                        joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
                        latLangCheckIn: false,
                    }, { transaction });
                }
            }
        } else {
            plan = await PartyPlan.findByPk(request.planId, { transaction });
        }

        if (!request || !plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Invite request or Party Plan not found' });
            return;
        }

        if (request.requesterId !== userId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'Only the invited user can accept this invite' });
            return;
        }

        // Idempotency: if request was already accepted by this user, return success!
        if (request.status === PartyPlanRequestStatus.ACCEPTED || request.status === PartyPlanRequestStatus.PAYMENT_PENDING) {
            await transaction.commit();
            res.json({
                success: true,
                message: 'Invite already accepted.',
                data: {
                    request,
                    joinerRazorpayOrderId: request.joinerRazorpayOrderId,
                    paymentDeadlineAt: request.paymentTimeoutAt?.toISOString(),
                }
            });
            return;
        }

        // Validate that the request being accepted is not cancelled or rejected
        if (request.status === PartyPlanRequestStatus.CANCELLED || request.status === PartyPlanRequestStatus.REJECTED) {
            await transaction.rollback();
            res.status(409).json({
                success: false,
                code: 'PARTNER_ALREADY_SELECTED',
                message: 'This Party Plan is no longer available because another partner has already joined.'
            });
            return;
        }

        // Acquire transactional row update lock on the party plan
        await plan.reload({ lock: transaction.LOCK.UPDATE, transaction });

        // Atomic concurrency protection: verify plan has no accepted partner and is not already locked
        if (plan.matchedRequestId && plan.matchedRequestId !== request.id) {
            await transaction.rollback();
            res.status(409).json({
                success: false,
                code: 'PARTNER_ALREADY_SELECTED',
                message: 'This Party Plan is no longer available because another partner has already joined.'
            });
            return;
        }

        // Enforce state transition checks: plan must not be cancelled or expired
        if (
            plan.status === PartyPlanStatus.CANCELLED ||
            plan.lifecycleStatus === PartyPlanLifecycleStatus.CANCELLED ||
            (plan.planDateTime && new Date(plan.planDateTime).getTime() < Date.now())
        ) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'This plan is no longer active or has already been cancelled/expired.' });
            return;
        }

        // Check if there is already an active accepted or unpaid request on this plan (another user took it)
        const activeReq = await PartyPlanRequest.findOne({
            where: {
                planId: plan.id,
                id: { [Op.ne]: request.id },
                [Op.or]: [
                    { status: PartyPlanRequestStatus.ACCEPTED },
                    {
                        status: PartyPlanRequestStatus.PAYMENT_PENDING,
                        paymentTimeoutAt: { [Op.gt]: new Date() }
                    }
                ]
            },
            transaction
        });
        if (activeReq) {
            await transaction.rollback();
            res.status(409).json({
                success: false,
                code: 'PARTNER_ALREADY_SELECTED',
                message: 'This Party Plan is no longer available because another partner has already joined.'
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
                    matchedRequestId: request.id,
                }, { transaction });
                await createBookingAndPayments(plan, request, transaction);

                // Atomically invalidate all competing requests (both private and public)
                const postInvalidate = await invalidateCompetingRequests(plan, request.id, request.requesterId, transaction);
                await rejectAndNotifyStaleRequests(plan, request.id, transaction);

                await transaction.commit();
                setImmediate(async () => {
                    await postInvalidate();
                });

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

                res.json({
                    success: true,
                    isSelfPay: true,
                    hostPaid: true,
                    message: 'Joined party plan successfully! (Paid by Host) 🎉',
                    data: request
                });
            } else {
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                }, { transaction });
                await plan.update({
                    paymentStatus: 'Awaiting Host Payment',
                    matchedRequestId: request.id,
                    isLive: false,
                }, { transaction });

                // Atomically invalidate all competing requests (both private and public)
                const postInvalidate = await invalidateCompetingRequests(plan, request.id, request.requesterId, transaction);

                await transaction.commit();

                // Send push notification & socket events
                setImmediate(async () => {
                    await postInvalidate();
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

                res.json({
                    success: true,
                    isSelfPay: true,
                    hostPaid: false,
                    message: 'Join confirmed. Waiting for host to complete their payment. ⏳',
                    data: request
                });
            }
        } else {
            // SPLIT PAY
            const timeout = new Date(Date.now() + 30 * 60 * 1000); // 30 minutes

            const joinerOptions = {
                amount: Math.round((Number(plan.depositAmount) || 99) * 100),
                currency: 'INR',
                receipt: `ppreq_${Date.now()}`
            };
            let joinerOrder: any = { id: request.joinerRazorpayOrderId || `order_mock_${Date.now()}`, amount: joinerOptions.amount, currency: joinerOptions.currency };
            if (!request.joinerRazorpayOrderId && process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id' && process.env.RAZORPAY_KEY_ID !== 'rzp_test_123') {
                try {
                    const resOrder = await razorpay.orders.create(joinerOptions);
                    if (resOrder) joinerOrder = resOrder;
                } catch (err: any) {
                    logger.warn('Razorpay joiner order failed for invite acceptance, using mock: ' + err.message);
                }
            }

            await request.update({
                status: PartyPlanRequestStatus.PAYMENT_PENDING,
                paymentTimeoutAt: timeout,
                joinerRazorpayOrderId: joinerOrder.id,
                joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
            }, { transaction });

            // Atomically invalidate all competing requests (both private and public)
            const postInvalidate = await invalidateCompetingRequests(plan, request.id, request.requesterId, transaction);

            const newLifecycle = hostPaid
                ? PartyPlanLifecycleStatus.HOST_PAYMENT_COMPLETED
                : PartyPlanLifecycleStatus.PAYMENT_PENDING;

            await plan.update({
                lifecycleStatus: newLifecycle,
                isLive: false, // reserved
                paymentStatus: hostPaid ? 'Awaiting Participant Payment' : 'Awaiting Host Payment',
                matchedRequestId: request.id,
                acceptedAt: new Date(),
                paymentDeadlineAt: timeout,
            }, { transaction });

            await transaction.commit();

            setImmediate(async () => {
                await postInvalidate();
            });

            try {
                const host = await User.findByPk(plan.userId);
                const joiner = await User.findByPk(request.requesterId);
                if (host && joiner) {
                    const { io } = require('../server');
                    const venueName = (plan as any)?.venue?.name || 'the venue';
                    const joinerName = `${joiner.firstName} ${joiner.lastName}`.trim();

                    io.to(`user_${request.requesterId}`).emit('party_plan_request_accepted', {
                        requestId: request.id,
                        planId: plan.id,
                        hostAlreadyPaid: hostPaid,
                        hostRazorpayOrderId: plan.hostRazorpayOrderId,
                        hostAmount: Math.round((Number(plan.depositAmount) || 99) * 100),
                        hostCurrency: 'INR',
                        joinerRazorpayOrderId: joinerOrder.id,
                        joinerAmount: joinerOrder.amount,
                        joinerCurrency: joinerOrder.currency,
                        isInvite: true,
                        requestType: 'private_invite',
                    });
                    io.to(`user_${plan.userId}`).emit('party_plan_invite_accepted', {
                        requestId: request.id,
                        planId: plan.id,
                        joinerId: joiner.id,
                        joinerName,
                    });
                    io.to(`user_${request.requesterId}`).emit('live_feed_update', {
                        type: 'party_plan_invite_accepted',
                        partyPlanId: plan.id,
                        requestId: request.id,
                    });
                    io.to(`user_${plan.userId}`).emit('live_feed_update', {
                        type: 'party_plan_invite_accepted',
                        partyPlanId: plan.id,
                        requestId: request.id,
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
                        metadata: { planId: plan.id, requestId: request.id, isInvite: true, requestType: 'private_invite' },
                        idempotencyKey: `invite_accepted_awaiting_joiner_${request.id}`,
                    });
                }
            } catch (socketErr) {
                logger.warn('Socket emission failed for acceptPartyPlanInvite:', socketErr);
            }

            res.json({
                success: true,
                isSelfPay: false,
                message: 'Invite accepted! You have 30 minutes to pay the deposit.',
                data: {
                    request,
                    joinerRazorpayOrderId: joinerOrder.id,
                    joinerAmount: joinerOrder.amount,
                    joinerCurrency: joinerOrder.currency,
                    paymentDeadlineAt: timeout.toISOString(),
                }
            });
        }
    } catch (err: any) {
        await transaction.rollback();
        logger.error('acceptPartyPlanInvite error:', err);
        res.status(500).json({ success: false, message: 'Failed to accept invite', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
async function cancelPartyPlanInternal(plan: PartyPlan, transaction: Transaction) {
    const hostStatusStr = String(plan.hostPaymentStatus || '').toLowerCase();
    const planPayStatusStr = String(plan.paymentStatus || '').toLowerCase();
    const wasHostPaid =
        hostStatusStr === 'paid' ||
        hostStatusStr === PartyPlanPaymentStatus.PAID ||
        Boolean(plan.hostRazorpayPaymentId) ||
        planPayStatusStr === 'confirmed' ||
        planPayStatusStr === 'paid' ||
        planPayStatusStr === 'awaiting participant payment' ||
        (plan.depositAmount && Number(plan.depositAmount) > 0 && planPayStatusStr !== 'pending' && planPayStatusStr !== 'unpaid');

    // 1. Update plan status
    await plan.update({
        status: PartyPlanStatus.CANCELLED,
        lifecycleStatus: PartyPlanLifecycleStatus.CANCELLED,
        isLive: false,
        paymentStatus: wasHostPaid || planPayStatusStr === 'confirmed' ? 'Refunded' : plan.paymentStatus,
        hostPaymentStatus: wasHostPaid ? PartyPlanPaymentStatus.REFUNDED : plan.hostPaymentStatus,
    }, { transaction });

    // 1.5 Refund Host if paid (Idempotent: credit Smart Credit Wallet)
    if (wasHostPaid) {
        const hostRefundRef = `REFUND_HOST_CANCEL_${plan.id}`;
        await WalletService.creditRefund({
            userId: plan.userId,
            amount: Number(plan.depositAmount) || 99.00,
            referenceId: hostRefundRef,
            reason: 'Party Plan Cancelled by Host',
            partyPlanId: plan.id,
            transaction,
        });
    }

    // 2. Release lock in Time Lock Engine
    await PlanEligibilityService.releaseLock(plan.id, { transaction });

    // Dispatch 🔓 Schedule Unlocked notification for Host
    try {
        const timeStr = plan.planDateTime ? formatTime12Hour(plan.planDateTime) : 'Scheduled Time';
        await NotificationService.sendScheduleUnlockedNotification({
            recipientUserId: plan.userId,
            eventTitle: 'Party Plan',
            eventTimeStr: timeStr,
            entityType: 'party_plan',
            entityId: plan.id,
        });
    } catch (notifErr: any) {
        logger.warn('Failed to send Schedule Unlocked notification for host: ' + notifErr?.message);
    }

    // 3. Find and cancel all active requests
    const requests = await PartyPlanRequest.findAll({
        where: {
            planId: plan.id,
            status: {
                [Op.in]: [
                    PartyPlanRequestStatus.PENDING,
                    PartyPlanRequestStatus.WAITING,
                    PartyPlanRequestStatus.PAYMENT_PENDING,
                    PartyPlanRequestStatus.ACCEPTED
                ]
            }
        },
        transaction
    });

    for (const req of requests) {
        const joinerStatusStr = String(req.joinerPaymentStatus || '').toLowerCase();
        const wasJoinerPaid =
            joinerStatusStr === 'paid' ||
            joinerStatusStr === PartyPlanJoinerPaymentStatus.PAID ||
            Boolean(req.joinerRazorpayPaymentId);

        await req.update({
            status: PartyPlanRequestStatus.CANCELLED,
            cancelledBy: plan.userId,
            cancelledAt: new Date(),
            cancellationReason: 'cancelled_by_host',
            joinerPaymentStatus: wasJoinerPaid ? PartyPlanJoinerPaymentStatus.REFUNDED : req.joinerPaymentStatus
        }, { transaction });

        // Refund Joiner if paid (Idempotent: credit Smart Credit Wallet)
        if (wasJoinerPaid) {
            const joinerRefundRef = `REFUND_JOINER_CANCEL_${req.id}`;
            await WalletService.creditRefund({
                userId: req.requesterId,
                amount: 99.00,
                referenceId: joinerRefundRef,
                reason: 'Party Plan Cancelled by Host (Joiner Refund)',
                partyPlanId: plan.id,
                transaction,
            });
        }

        // Dispatch 🔓 Schedule Unlocked notification for Joiner
        try {
            const timeStr = plan.planDateTime ? formatTime12Hour(plan.planDateTime) : 'Scheduled Time';
            await NotificationService.sendScheduleUnlockedNotification({
                recipientUserId: req.requesterId,
                eventTitle: 'Party Plan',
                eventTimeStr: timeStr,
                entityType: 'party_plan',
                entityId: plan.id,
            });
        } catch (notifErr: any) {
            logger.warn('Failed to send Schedule Unlocked notification for joiner: ' + notifErr?.message);
        }

        // Notify joiners
        try {
            const { io } = require('../server');
            if (io) {
                io.to(`user_${req.requesterId}`).emit('plan_unavailable', {
                    planId: plan.id,
                    requestId: req.id,
                });
                io.to(`user_${req.requesterId}`).emit('party_plan_request_cancelled', {
                    planId: plan.id,
                    requestId: req.id,
                    cancelledBy: plan.userId,
                });
            }
        } catch (_) { }

        setImmediate(async () => {
            try {
                await NotificationService.dispatch({
                    recipientUserId: req.requesterId,
                    actorUserId: plan.userId,
                    eventType: 'party_plan_cancelled',
                    category: 'requests',
                    entityType: 'party_plan_request',
                    entityId: req.id,
                    title: 'Party Plan Cancelled',
                    body: 'This Party Plan is no longer available because the host cancelled it.',
                    metadata: { partyPlanId: plan.id, planId: plan.id, requestId: req.id },
                    idempotencyKey: `req_cancelled_by_host_${req.id}`,
                });
                const joiner = await User.findByPk(req.requesterId);
                if (joiner && joiner.fcmToken) {
                    await sendMulticastPushNotification([joiner.fcmToken], {
                        title: 'Party Plan Cancelled',
                        body: 'This Party Plan is no longer available because the host cancelled it.',
                        data: {
                            type: 'plan_unavailable',
                            partyPlanId: plan.id,
                            requestId: req.id,
                        },
                    });
                }
            } catch (_) { }
        });
    }

    // 4. Find associated Booking (goingMode = PLAN or PARTY_REQUEST, matching host userId, venueId, planDateTime)
    const booking = await Booking.findOne({
        where: {
            goingMode: { [Op.in]: [GoingMode.PLAN, GoingMode.PARTY_REQUEST] },
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
        const callerUserId = (req.user?.id || req.body.userId || '').toString();

        const plan = await PartyPlan.findByPk(id, { transaction, lock: transaction.LOCK.UPDATE });
        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (callerUserId && plan.userId !== callerUserId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'Only the host can cancel the plan' });
            return;
        }

        // Check if already cancelled (idempotent)
        if (plan.status === PartyPlanStatus.CANCELLED) {
            await transaction.rollback();
            res.json({ success: true, message: 'Party plan is already cancelled' });
            return;
        }

        // If the plan is CONFIRMED with a partner, direct unilateral cancellation is forbidden.
        if (
            plan.lifecycleStatus === PartyPlanLifecycleStatus.MATCH_CONFIRMED ||
            plan.lifecycleStatus === PartyPlanLifecycleStatus.CHAT_ENABLED ||
            plan.lifecycleStatus === PartyPlanLifecycleStatus.CANCELLATION_REQUESTED
        ) {
            await transaction.rollback();
            res.status(400).json({
                success: false,
                isConfirmed: true,
                message: 'This Party Plan is confirmed with a participant. Direct cancellation is not allowed. Please initiate a mutual cancellation request.',
            });
            return;
        }

        const wasHostPaid = plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;
        await cancelPartyPlanInternal(plan, transaction);

        await transaction.commit();

        let venueName = 'the venue';
        try {
            const venue = await Venue.findByPk(plan.venueId);
            if (venue) venueName = venue.name;
        } catch (_) { }

        // Post-commit notification & socket broadcast
        setImmediate(async () => {
            try {
                await NotificationService.dispatch({
                    recipientUserId: plan.userId,
                    actorUserId: plan.userId,
                    eventType: 'party_plan_cancelled',
                    category: 'requests',
                    entityType: 'party_plan',
                    entityId: plan.id,
                    title: 'Party Plan Cancelled',
                    body: wasHostPaid
                        ? `Your Party Plan at ${venueName} has been cancelled. ₹99 has been refunded to your Lunara Wallet.`
                        : `Your Party Plan at ${venueName} has been cancelled.`,
                    metadata: {
                        partyPlanId: plan.id,
                        planId: plan.id,
                        refundAmount: wasHostPaid ? 99.0 : 0.0,
                    },
                    idempotencyKey: `host_plan_cancelled_${plan.id}`,
                });

                const { io } = require('../server');
                if (io) {
                    io.emit('party_plan_deleted', { planId: plan.id });
                    io.emit('party_plan_cancelled', { planId: plan.id });
                }
            } catch (socketErr) {
                logger.warn('Socket/Notification dispatch failed on cancel:', socketErr);
            }
        });

        apiCache.invalidatePrefix('pp_feed');

        res.json({
            success: true,
            message: wasHostPaid
                ? 'Party plan cancelled. ₹99 has been refunded to your Lunara Wallet.'
                : 'Party plan cancelled.'
        });
    } catch (err: any) {
        await transaction.rollback();
        logger.error('cancelPartyPlan error:', err);
        res.status(500).json({ success: false, message: 'Failed to cancel plan', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/repost
// Repost an existing party plan with a new date/time (by host)
// ─────────────────────────────────────────────────────────────────────────────
export const repostPartyPlan = async (req: Request, res: Response): Promise<void> => {
    const transaction = await sequelize.transaction();
    try {
        const { id } = req.params;
        const callerUserId = (req.user?.id || req.body.userId || '').toString();
        const { newDateTime, reason } = req.body;

        if (!callerUserId) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

        if (!newDateTime) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'newDateTime is required' });
            return;
        }

        const parsedDate = new Date(newDateTime);
        if (isNaN(parsedDate.getTime())) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'newDateTime must be a valid ISO 8601 date string' });
            return;
        }

        // Validate lead time: must be in the future (minimum 30 minutes)
        if (parsedDate.getTime() <= Date.now() + 30 * 60 * 1000) {
            await transaction.rollback();
            res.status(400).json({
                success: false,
                message: 'New date and time must be at least 30 minutes in the future'
            });
            return;
        }

        const plan = await PartyPlan.findByPk(id, { transaction, lock: transaction.LOCK.UPDATE });
        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (plan.userId !== callerUserId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'Only the host can repost the plan' });
            return;
        }

        if (plan.status === PartyPlanStatus.CANCELLED) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'A cancelled party plan cannot be reposted.' });
            return;
        }

        // Repost is effectively a reschedule of the same plan — apply the same
        // venue timing/holiday and per-day-conflict validation createPartyPlan does.
        const venue = await Venue.findByPk(plan.venueId, {
            attributes: ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone', 'coverChargeMale', 'coverChargeFemale', 'openingTime', 'closingTime', 'daysOpen', 'closedDates'],
            transaction,
        });
        if (!venue) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Venue not found' });
            return;
        }
        const timingValidation = validateVenueTimingAndHolidays(venue, parsedDate);
        if (!timingValidation.isValid) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: timingValidation.reason });
            return;
        }
        const bookingConflictMsg = await checkExistingBookingForDate(callerUserId, parsedDate, 'party_plan');
        if (bookingConflictMsg) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: bookingConflictMsg });
            return;
        }

        const oldDateTime = plan.planDateTime;

        // Cancel previous pending / waiting / accepted requests cleanly because schedule changed
        const pendingRequests = await PartyPlanRequest.findAll({
            where: {
                planId: plan.id,
                status: {
                    [Op.in]: [
                        PartyPlanRequestStatus.PENDING,
                        PartyPlanRequestStatus.WAITING,
                        PartyPlanRequestStatus.PAYMENT_PENDING,
                        PartyPlanRequestStatus.ACCEPTED,
                    ]
                }
            },
            transaction
        });

        for (const reqItem of pendingRequests) {
            const joinerStatusStr = String(reqItem.joinerPaymentStatus || '').toLowerCase();
            const wasJoinerPaid =
                joinerStatusStr === 'paid' ||
                joinerStatusStr === PartyPlanJoinerPaymentStatus.PAID ||
                Boolean(reqItem.joinerRazorpayPaymentId);
            await reqItem.update({
                status: PartyPlanRequestStatus.CANCELLED,
                cancelledBy: callerUserId,
                cancelledAt: new Date(),
                cancellationReason: 'plan_reposted_new_schedule',
                joinerPaymentStatus: wasJoinerPaid ? PartyPlanJoinerPaymentStatus.REFUNDED : reqItem.joinerPaymentStatus
            }, { transaction });

            if (wasJoinerPaid) {
                const joinerRefundRef = `REFUND_JOINER_REPOST_${reqItem.id}`;
                await WalletService.creditRefund({
                    userId: reqItem.requesterId,
                    amount: 99.00,
                    referenceId: joinerRefundRef,
                    reason: 'Party Plan Reposted (Joiner Refund)',
                    partyPlanId: plan.id,
                    transaction,
                });
            }
        }

        // Update the existing Party Plan in-place (no duplicate records)
        await plan.update({
            planDateTime: parsedDate,
            status: PartyPlanStatus.ACTIVE,
            lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
            // Unpaid plans must not appear in the public feed — same invariant createPartyPlan enforces.
            isLive: plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID && plan.visibility !== PartyPlanVisibility.PRIVATE,
            matchedRequestId: null,
            acceptedAt: null,
            paymentDeadlineAt: null,
            paymentStatus: plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID ? 'Confirmed' : 'Active',
            reminder24hSent: false,
            reminder3hSent: false,
            reminder2hSent: false,
            reminder1hSent: false,
            reminder30mSent: false,
            reminder10mSent: false,
            hostArrivalConfirmed: false,
            hostArrivalTime: null,
        }, { transaction });

        // Release/update lock in Time Lock Engine
        await PlanEligibilityService.releaseLock(plan.id, { transaction });

        await transaction.commit();

        // Venue details for notification
        let venueName = 'the venue';
        try {
            const venue = await Venue.findByPk(plan.venueId);
            if (venue) venueName = venue.name;
        } catch (_) { }

        // Post-commit notifications and socket broadcast
        setImmediate(async () => {
            try {
                const formattedDate = parsedDate.toLocaleString('en-IN', {
                    dateStyle: 'medium',
                    timeStyle: 'short',
                });

                // In-place notification for Host
                await NotificationService.dispatch({
                    recipientUserId: plan.userId,
                    actorUserId: plan.userId,
                    eventType: 'party_plan_reposted',
                    category: 'requests',
                    entityType: 'party_plan',
                    entityId: plan.id,
                    title: 'Party Plan Reposted',
                    body: `Your Party Plan at ${venueName} has been reposted for ${formattedDate}.`,
                    metadata: {
                        partyPlanId: plan.id,
                        planId: plan.id,
                        oldDateTime,
                        newDateTime: parsedDate.toISOString(),
                        reason,
                    },
                    idempotencyKey: `plan_reposted_${plan.id}_${parsedDate.getTime()}`,
                });

                // Socket broadcasts
                const { io } = require('../server');
                if (io) {
                    io.emit('party_plan_reposted', {
                        planId: plan.id,
                        newDateTime: parsedDate.toISOString(),
                        oldDateTime,
                    });
                    io.emit('party_plan_created', {
                        id: plan.id,
                        planId: plan.id,
                        status: plan.status,
                        planDateTime: plan.planDateTime,
                    });
                }
            } catch (notifyErr: any) {
                logger.warn('Failed to dispatch repost notification:', notifyErr.message);
            }
        });

        res.json({
            success: true,
            message: 'Party Plan successfully reposted with the new date and time.',
            data: plan
        });
    } catch (err: any) {
        await transaction.rollback();
        logger.error('repostPartyPlan error:', err);
        res.status(500).json({ success: false, message: 'Failed to repost plan', error: err.message });
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
        const cleanId = (reqId || '').replace(/^party_plan_host_/, '').replace(/^party_plan_joiner_/, '').trim();

        const venueInclude = {
            model: Venue,
            as: 'venue',
            attributes: ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone', 'latitude', 'longitude'],
            include: [
                {
                    model: VenueImage,
                    as: 'images',
                    attributes: ['id', 'filePath', 'imageType', 'isPrimary', 'displayOrder'],
                    where: { isPrimary: true },
                    required: false,
                }
            ],
        };

        const userInclude = (as: string) => ({
            model: User,
            as,
            attributes: TICKET_USER_ATTRS,
            include: [
                { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
            ],
        });

        const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(cleanId);
        let request: PartyPlanRequest | null = null;
        let plan: PartyPlan | null = null;

        if (isUuid) {
            request = await PartyPlanRequest.findByPk(cleanId, {
                include: [
                    {
                        model: PartyPlan,
                        as: 'plan',
                        include: [
                            userInclude('creator'),
                            venueInclude,
                        ] as any,
                    },
                    userInclude('requester'),
                ],
            });

            if (request) {
                plan = (request as any).plan as PartyPlan;
            } else {
                plan = await PartyPlan.findByPk(cleanId, {
                    include: [
                        userInclude('creator'),
                        venueInclude,
                    ] as any,
                });
            }
        }

        if (!plan) {
            try {
                const TicketModel = (await import('../models/Ticket')).default;
                const ticketWhere: any[] = [{ ticketId: cleanId }];
                if (isUuid) {
                    ticketWhere.push({ id: cleanId }, { bookingId: cleanId });
                }
                const ticket = await TicketModel.findOne({
                    where: { [Op.or]: ticketWhere },
                });
                if (ticket && ticket.bookingId) {
                    const BookingModel = (await import('../models/Booking')).default;
                    const bookingRec = await BookingModel.findByPk(ticket.bookingId);
                    if (bookingRec && bookingRec.specialRequests) {
                        try {
                            const meta = typeof bookingRec.specialRequests === 'string' ? JSON.parse(bookingRec.specialRequests) : bookingRec.specialRequests;
                            if (meta.planId) {
                                plan = await PartyPlan.findByPk(meta.planId, {
                                    include: [userInclude('creator'), venueInclude] as any,
                                });
                            }
                            if (meta.requestId) {
                                request = await PartyPlanRequest.findByPk(meta.requestId, {
                                    include: [userInclude('requester')],
                                });
                            }
                        } catch (_) { }
                    }
                }
            } catch (_) { }
        }

        if (!plan) {
            try {
                const BookingModel = (await import('../models/Booking')).default;
                const bookingWhere: any[] = [{ ticketCode: cleanId }];
                if (isUuid) {
                    bookingWhere.push({ id: cleanId });
                }
                const bookingRec = await BookingModel.findOne({
                    where: { [Op.or]: bookingWhere },
                });
                if (bookingRec && bookingRec.specialRequests) {
                    try {
                        const meta = typeof bookingRec.specialRequests === 'string' ? JSON.parse(bookingRec.specialRequests) : bookingRec.specialRequests;
                        if (meta.planId) {
                            plan = await PartyPlan.findByPk(meta.planId, {
                                include: [userInclude('creator'), venueInclude] as any,
                            });
                        }
                        if (meta.requestId) {
                            request = await PartyPlanRequest.findByPk(meta.requestId, {
                                include: [userInclude('requester')],
                            });
                        }
                    } catch (_) { }
                }
            } catch (_) { }
        }

        if (plan && !request) {
            if ((plan as any).matchedRequestId) {
                request = await PartyPlanRequest.findByPk((plan as any).matchedRequestId, {
                    include: [userInclude('requester')],
                });
            }
            if (!request) {
                request = await PartyPlanRequest.findOne({
                    where: {
                        planId: plan.id,
                        [Op.or]: [
                            { status: { [Op.in]: [PartyPlanRequestStatus.ACCEPTED, 'confirmed' as any, 'paid' as any, 'chat_enabled' as any, 'match_confirmed' as any, PartyPlanRequestStatus.PAYMENT_PENDING] } },
                            { joinerPaymentStatus: 'paid' as any },
                        ],
                    },
                    order: [['updatedAt', 'DESC']],
                    include: [userInclude('requester')],
                });
            }

            if (!request) {
                request = await PartyPlanRequest.findOne({
                    where: { planId: plan.id },
                    order: [['createdAt', 'DESC']],
                    include: [userInclude('requester')],
                });
            }
        }

        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan or request not found' });
            return;
        }

        const callerUserId = (req as any).user?.id || req.query.userId || req.body.userId;
        if (callerUserId && callerUserId !== plan.userId && request && callerUserId !== request.requesterId) {
            res.status(403).json({ success: false, message: 'You are not authorized to view this ticket.' });
            return;
        }

        const isCancelled = (plan.status || '').toLowerCase() === 'cancelled' ||
            (plan.lifecycleStatus || '').toLowerCase() === 'cancelled' ||
            (request?.status || '').toLowerCase() === 'cancelled' ||
            (plan.hostPaymentStatus || '').toLowerCase() === 'refunded' ||
            (request?.joinerPaymentStatus || '').toLowerCase() === 'refunded';

        const hostPaid = (plan.hostPaymentStatus || '').toLowerCase() === 'paid' || (plan.hostPaymentStatus || '').toLowerCase() === 'refunded';
        const joinerPaid = (request?.joinerPaymentStatus || '').toLowerCase() === 'paid' || (request?.joinerPaymentStatus || '').toLowerCase() === 'refunded' || plan.paymentType === 'self_pay';
        const isPlanConfirmed = plan.lifecycleStatus === 'match_confirmed' || plan.lifecycleStatus === 'chat_enabled' || plan.lifecycleStatus === 'event_upcoming' || isCancelled;
        if (!hostPaid && !joinerPaid && !isPlanConfirmed) {
            res.status(403).json({ success: false, message: 'Ticket is unavailable until payments are verified.' });
            return;
        }

        // Helper to extract photo URL from a user record with embedded photos array
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

        const hostRaw = (plan as any).creator;
        const joinerRaw = request ? (request as any).requester : null;

        const hostPhoto = resolveUserPhoto(hostRaw);
        const hostData = hostRaw ? {
            id: hostRaw.id,
            firstName: hostRaw.firstName,
            lastName: hostRaw.lastName,
            username: hostRaw.profile?.displayName || (hostRaw.firstName ? `${hostRaw.firstName}_${hostRaw.lastName}`.toLowerCase() : 'user'),
            profilePhotoUrl: hostPhoto,
            profileImageUrl: hostPhoto,
            photoUrl: hostPhoto,
            image: hostPhoto,
            subscriptionTier: hostRaw.profile?.subscriptionTier || 'FREE',
            bio: hostRaw.profile?.bio ?? null,
            city: hostRaw.profile?.city ?? null,
        } : null;

        const joinerPhoto = resolveUserPhoto(joinerRaw);
        const joinerData = joinerRaw ? {
            id: joinerRaw.id,
            firstName: joinerRaw.firstName,
            lastName: joinerRaw.lastName,
            username: joinerRaw.profile?.displayName || (joinerRaw.firstName ? `${joinerRaw.firstName}_${joinerRaw.lastName}`.toLowerCase() : 'user'),
            profilePhotoUrl: joinerPhoto,
            profileImageUrl: joinerPhoto,
            photoUrl: joinerPhoto,
            image: joinerPhoto,
            subscriptionTier: joinerRaw.profile?.subscriptionTier || 'FREE',
            bio: joinerRaw.profile?.bio ?? null,
            city: joinerRaw.profile?.city ?? null,
        } : null;

        // Fetch the booking record to retrieve the ticketCode and ticketUrl
        let booking = await Booking.findOne({
            where: {
                goingMode: { [Op.in]: [GoingMode.PLAN, GoingMode.PARTY_REQUEST] },
                venueId: plan.venueId,
                specialRequests: { [Op.like]: `%"planId":"${plan.id}"%` },
            },
            order: [['createdAt', 'DESC']],
            attributes: ['id', 'ticketCode', 'ticketUrl', 'specialRequests', 'status', 'paymentStatus'],
        });

        if (!booking) {
            const dateObj = new Date(plan.planDateTime);
            const bookingDate = dateObj.toISOString().split('T')[0];
            booking = await Booking.findOne({
                where: {
                    goingMode: { [Op.in]: [GoingMode.PLAN, GoingMode.PARTY_REQUEST] },
                    userId: plan.userId,
                    venueId: plan.venueId,
                    bookingDate: bookingDate as any,
                },
                order: [['createdAt', 'DESC']],
                attributes: ['id', 'ticketCode', 'ticketUrl', 'specialRequests', 'status', 'paymentStatus'],
            });
        }

        // Also fetch the authoritative Ticket model record
        let ticketRec = null;
        if (booking) {
            ticketRec = await Ticket.findOne({
                where: { bookingId: booking.id },
                order: [['createdAt', 'DESC']],
            });
        }
        if (!ticketRec && booking?.ticketCode) {
            ticketRec = await Ticket.findOne({
                where: { ticketId: booking.ticketCode },
                order: [['createdAt', 'DESC']],
            });
        }
        if (!ticketRec) {
            ticketRec = await Ticket.findOne({
                where: {
                    bookingType: 'party_plan',
                    [Op.or]: [
                        { userId: plan.userId },
                        ...(request ? [{ userId: request.requesterId }] : []),
                    ],
                    venueId: plan.venueId,
                },
                order: [['createdAt', 'DESC']],
            });
        }

        let ticketUrl = ticketRec?.pdfUrl ?? (booking as any)?.ticketUrl ?? null;
        let ticketCode = ticketRec?.ticketId ?? booking?.ticketCode ?? null;
        let ticketQr = ticketRec?.qrToken ?? ticketCode;

        if (booking && !ticketUrl) {
            try {
                const { generateTicketForBookingHelper } = require('../services/ticketService');
                ticketUrl = await generateTicketForBookingHelper(booking.id);
            } catch (ticketGenErr: any) {
                logger.warn(`On-the-fly ticket PDF generation failed for booking ${booking.id}: ${ticketGenErr.message}`);
            }
        }

        const isCancelledTicket = isCancelled ||
            (plan.status || '').toLowerCase() === 'cancelled' ||
            (plan.lifecycleStatus || '').toLowerCase() === 'cancelled' ||
            ticketRec?.ticketStatus === TicketStatus.CANCELLED;

        const effectiveStatus = isCancelledTicket ? 'CANCELLED' : (ticketRec?.ticketStatus || (booking as any)?.status || 'CONFIRMED');
        const startTimeStr = formatTime12Hour(plan.planDateTime, DEFAULT_TIMEZONE);

        res.json({
            success: true,
            data: {
                request: request ? {
                    id: request.id,
                    planId: request.planId,
                    status: request.status,
                    joinerPaymentStatus: request.joinerPaymentStatus,
                    createdAt: request.createdAt,
                    planDateTime: plan.planDateTime,
                    eventStartAt: plan.planDateTime,
                    startTime: startTimeStr,
                    requester: joinerData,
                    joiner: joinerData,
                    user: joinerData,
                } : null,
                partner: joinerData,
                joiner: joinerData,
                host: hostData,
                plan: {
                    id: plan.id,
                    message: plan.message,
                    planDateTime: plan.planDateTime,
                    eventStartAt: plan.planDateTime,
                    startTime: startTimeStr,
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
                startTime: startTimeStr,
                ticketCode: ticketCode,
                ticketId: ticketCode,
                bookingId: booking?.id ?? ticketRec?.bookingId ?? null,
                ticketUrl: ticketUrl,
                pdfUrl: ticketUrl,
                qrToken: ticketQr,
                status: effectiveStatus,
                expiresAt: ticketRec?.expiresAt || plan.planDateTime,
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
// Has this user's join request been accepted by the host for this plan?
// ACCEPTED/PAYMENT_PENDING are the two statuses set the moment the host
// accepts — unlocking here matches "when host accepts" without waiting for payment.
async function isAcceptedJoinerForPlan(planId: string, userId?: string): Promise<boolean> {
    if (!userId) return false;
    const acceptedRequest = await PartyPlanRequest.findOne({
        where: {
            planId,
            requesterId: userId,
            status: { [Op.in]: [PartyPlanRequestStatus.ACCEPTED, PartyPlanRequestStatus.PAYMENT_PENDING] },
        },
        attributes: ['id'],
    });
    return !!acceptedRequest;
}

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

// Strips the real venue name out of a host-authored free-text field (message/
// description) whenever the venue is secret for this viewer. The client can
// never safely do this redaction itself — it's only ever told the masked
// "Secret Venue" name, never the real one, so it has nothing to search for.
// Only the backend, which still holds the real name, can do this correctly.
function redactVenueNameFromText(text: string | null | undefined, realVenueName: string | null | undefined, isSecret: boolean): string | null {
    if (text === null || text === undefined) return null;
    if (!isSecret || !realVenueName || !realVenueName.trim()) return text;
    const escaped = realVenueName.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return text.replace(new RegExp(escaped, 'gi'), 'a Secret Venue 🔒');
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
            latitude: venue.latitude,
            longitude: venue.longitude,
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
        const coverImage = venue.images.find((img: any) => img.isPrimary || String(img.imageType || '').toLowerCase().includes('cover')) || venue.images[0];
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
        latitude: venue.latitude,
        longitude: venue.longitude,
        phone: venue.phone,
        coverChargeMale: venue.coverChargeMale,
        coverChargeFemale: venue.coverChargeFemale,
        coverImage: coverImageUrl ? { filePath: coverImageUrl, url: coverImageUrl } : null,
        coverImageUrl: coverImageUrl,
        imageUrl: coverImageUrl,
        images: venue.images || [],
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
            const isInvite = reqItem.requestType === PartyPlanRequestType.PRIVATE_INVITE ||
                reqItem.requestType === 'private_invite' ||
                !!(plan && plan.selectedUsers && Array.isArray(plan.selectedUsers) && plan.selectedUsers.includes(reqItem.requesterId));
            const hostId = plan?.userId;
            return {
                id: reqItem.id,
                planId: reqItem.planId,
                isInvite,
                requestType: isInvite ? 'private_invite' : 'public_request',
                senderId: isInvite ? hostId : reqItem.requesterId,
                recipientId: isInvite ? reqItem.requesterId : hostId,
                hostId,
                targetUserId: reqItem.requesterId,
                status: reqItem.status,
                joinerPaymentStatus: reqItem.joinerPaymentStatus,
                joinerRazorpayOrderId: reqItem.joinerRazorpayOrderId,
                paymentTimeoutAt: reqItem.paymentTimeoutAt,
                createdAt: reqItem.createdAt,
                plan: plan ? {
                    id: plan.id,
                    userId: plan.userId,
                    visibility: plan.visibility,
                    selectedUsers: plan.selectedUsers,
                    paymentType: plan.paymentType,
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

        // Self-pay plans mean the host covers the party expense — the joiner must
        // never be charged a real deposit here. Use confirmSelfPaidJoin instead.
        if (plan?.paymentType === 'self_pay') {
            res.status(400).json({
                success: false,
                message: 'This plan is self-paid by the host. Use the confirm-join endpoint instead of a real payment.',
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
    const transaction = await sequelize.transaction();
    try {
        const rawId = String(req.params.id || req.params.planId || req.body?.planId || req.body?.partyPlanId || req.query?.planId || '');
        const id = rawId ? rawId.replace(/^(pp_|party_plan_|party_plan_timeline_)/i, '') : '';
        const { response, hasArrived, latitude, longitude, device, ip } = req.body;
        const userId = (req as any).user?.id || req.body.userId || req.query.userId;

        if (!userId) {
            await transaction.rollback();
            res.status(401).json({ success: false, message: 'Unauthorized' });
            return;
        }

        let plan = await PartyPlan.findByPk(id, { transaction, lock: transaction.LOCK.UPDATE });
        if (!plan && rawId && rawId !== id) {
            plan = await PartyPlan.findByPk(rawId, { transaction, lock: transaction.LOCK.UPDATE });
        }
        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        // Validate plan is not already finalized or cancelled
        if (plan.lifecycleStatus === PartyPlanLifecycleStatus.PLAN_COMPLETED || plan.status === PartyPlanStatus.CANCELLED) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'This Party Plan is already finalized and arrival status cannot be changed.' });
            return;
        }

        const stage = (req.body.stage || plan.reachVerificationStage || 'thirty_min_reach').toString().toLowerCase();
        const source = (req.body.source || '').toString().toUpperCase();
        const isPromptOrNotification = Boolean(plan.reachConfirmation30mSent) ||
            stage === 'thirty_min_reach' ||
            stage === 'final_check' ||
            source === 'POPUP' ||
            source === 'LIVE_FEED' ||
            source === 'NOTIFICATION';

        // Server-side authoritative confirmation window: opens ~35-45 min before scheduled party time or when prompted
        const eventTime = plan.planDateTime ? new Date(plan.planDateTime).getTime() : 0;
        const nowMs = Date.now();
        if (!isPromptOrNotification && eventTime > 0 && nowMs < eventTime - 45 * 60 * 1000) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'Venue reach confirmation opens 30 minutes before the scheduled Party Plan time.' });
            return;
        }

        // Validate 24-hour resolution deadline
        if (eventTime > 0 && nowMs > eventTime + 24 * 60 * 60 * 1000) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'The 24-hour arrival confirmation window for this Party Plan has closed.' });
            return;
        }

        let acceptedReq: PartyPlanRequest | null = null;
        if (plan.matchedRequestId) {
            acceptedReq = await PartyPlanRequest.findByPk(plan.matchedRequestId, {
                transaction,
                lock: transaction.LOCK.UPDATE
            });
        }
        if (!acceptedReq) {
            const planIdsToSearch: string[] = [id, rawId].filter(Boolean);
            acceptedReq = await PartyPlanRequest.findOne({
                where: {
                    planId: { [Op.in]: planIdsToSearch },
                    status: {
                        [Op.in]: [
                            PartyPlanRequestStatus.ACCEPTED,
                            'accepted', 'ACCEPTED',
                            'confirmed', 'CONFIRMED',
                            'paid', 'PAID',
                            'payment_pending', 'PAYMENT_PENDING'
                        ]
                    }
                },
                order: [['updatedAt', 'DESC']],
                transaction,
                lock: transaction.LOCK.UPDATE
            });
        }

        const isHost = plan.userId === userId;
        const isGuest = acceptedReq ? acceptedReq.requesterId === userId : (plan as any).matchedUserId === userId;

        if (!isHost && !isGuest) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'You are not an active participant in this plan' });
            return;
        }

        // Validate that payments are verified or self-pay
        const hostStatus = String(plan.hostPaymentStatus || '').toLowerCase();
        const hostPaid = hostStatus === 'paid' || hostStatus === 'refunded' || hostStatus === 'completed' || plan.paymentType === 'self_pay';
        const guestStatus = String(acceptedReq?.joinerPaymentStatus || '').toLowerCase();
        const guestPaid = guestStatus === 'paid' || guestStatus === 'refunded' || guestStatus === 'completed' || plan.paymentType === 'self_pay' || !acceptedReq;

        if (!hostPaid && !guestPaid && plan.paymentType !== 'self_pay') {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'Arrival confirmation is only available for fully confirmed Party Plans with verified payments.' });
            return;
        }

        const choice = response ? response.toString().toUpperCase() : (hasArrived === false ? 'NO' : 'YES');
        const isYes = choice === 'YES' || hasArrived === true;
        const targetReachStatus = isYes ? 'REACHED' : 'NOT_REACHED';
        const nowStamp = new Date();

        // Idempotent guard: if the user already submitted this same reach choice, return early without re-charging or duplicate events
        if (isHost && plan.hostReachStatus === targetReachStatus) {
            await transaction.rollback();
            res.json({
                success: true,
                alreadyConfirmed: true,
                isHost: true,
                confirmed: isYes,
                reachStatus: targetReachStatus,
                message: 'Your venue reach confirmation has already been recorded.'
            });
            return;
        }
        if (isGuest && acceptedReq?.partnerReachStatus === targetReachStatus) {
            await transaction.rollback();
            res.json({
                success: true,
                alreadyConfirmed: true,
                isHost: false,
                confirmed: isYes,
                reachStatus: targetReachStatus,
                message: 'Your venue reach confirmation has already been recorded.'
            });
            return;
        }

        // ── Store Server-Side Reach Confirmation Response ─────────────────────
        if (isHost) {
            await plan.update({
                hostReachStatus: targetReachStatus,
                hostReachConfirmedAt: nowStamp,
                hostReachConfirmationSource: req.body.source || 'LIVE_FEED',
                hostReachNotificationId: req.body.notificationId || `PARTY_PLAN_VENUE_REACH_CONFIRMATION_${plan.id}`,
                hostArrivalConfirmed: isYes,
                hostArrivalTime: nowStamp,
                hostFirstCheckStatus: isYes ? 'yes' : 'no',
                hostFirstCheckRespondedAt: nowStamp,
                hostFinalCheckStatus: isYes ? 'yes' : 'no',
                hostFinalCheckRespondedAt: nowStamp,
                reachVerificationStage: 'final_check',
                hostLatLangCheckIn: latitude && longitude ? true : plan.hostLatLangCheckIn
            }, { transaction });
        } else if (acceptedReq) {
            await acceptedReq.update({
                partnerReachStatus: targetReachStatus,
                partnerReachConfirmedAt: nowStamp,
                partnerReachConfirmationSource: req.body.source || 'LIVE_FEED',
                partnerReachNotificationId: req.body.notificationId || `PARTY_PLAN_VENUE_REACH_CONFIRMATION_${plan.id}`,
                guestArrivalConfirmed: isYes,
                guestArrivalTime: nowStamp,
                guestFirstCheckStatus: isYes ? 'yes' : 'no',
                guestFirstCheckRespondedAt: nowStamp,
                guestFinalCheckStatus: isYes ? 'yes' : 'no',
                guestFinalCheckRespondedAt: nowStamp,
                latLangCheckIn: latitude && longitude ? true : acceptedReq.latLangCheckIn
            }, { transaction });
        }

        const AuditLog = (await import('../models/AuditLog')).default;
        await AuditLog.logAction({
            userId,
            partyPlanId: id,
            action: `Venue Reach Confirmation (${choice})`,
            metadata: { isHost, response: choice, reachStatus: targetReachStatus, stage, source: req.body.source || 'LIVE_FEED', latitude, longitude, device, ip }
        });

        // Determine updated arrival states
        const hostArrived = isHost ? isYes : (plan.hostReachStatus === 'REACHED' || Boolean(plan.hostArrivalConfirmed));
        const guestArrived = !isHost ? isYes : (acceptedReq?.partnerReachStatus === 'REACHED' || Boolean(acceptedReq?.guestArrivalConfirmed));
        const hostHasAnswered = isHost ? true : (plan.hostReachStatus === 'REACHED' || plan.hostReachStatus === 'NOT_REACHED' || plan.hostArrivalTime !== null);
        const guestHasAnswered = !isHost ? true : (acceptedReq?.partnerReachStatus === 'REACHED' || acceptedReq?.partnerReachStatus === 'NOT_REACHED' || acceptedReq?.guestArrivalTime !== null);
        const bothAnswered = hostHasAnswered && guestHasAnswered;

        let bothArrived = false;
        let isFinalized = false;
        const hostDeposit = Number(plan.depositAmount || 99.00);
        const guestDeposit = plan.paymentType === 'self_pay' ? 0.00 : 99.00;

        const { ReliabilityService, ReliabilityAction } = await import('../services/reliabilityService');

        if (hostArrived && guestArrived && acceptedReq) {
            // ── CASE A: BOTH CONFIRMED YES ───────────────────────────────────────
            bothArrived = true;
            isFinalized = true;

            const hostUser = await User.findByPk(plan.userId, { transaction, lock: transaction.LOCK.UPDATE });
            const guestUser = await User.findByPk(acceptedReq.requesterId, { transaction, lock: transaction.LOCK.UPDATE });

            // Idempotent Host Refund
            if (hostUser) {
                const hostRef = `PARTY_PLAN:${plan.id}:ARRIVAL_REFUND:${hostUser.id}`;
                await WalletService.creditRefund({
                    userId: hostUser.id,
                    amount: hostDeposit,
                    referenceId: hostRef,
                    reason: 'Party Plan Both Confirmed Arrival (Host Refund)',
                    partyPlanId: plan.id,
                    transaction,
                });
                await plan.update({ hostPaymentStatus: PartyPlanPaymentStatus.REFUNDED }, { transaction });
                await ReliabilityService.updateScore({
                    userId: hostUser.id,
                    action: ReliabilityAction.CONFIRMED_ARRIVAL,
                    partyPlanId: plan.id,
                    transaction,
                });
            }

            // Idempotent Guest Refund
            if (guestUser && guestDeposit > 0) {
                const guestRef = `PARTY_PLAN:${plan.id}:ARRIVAL_REFUND:${guestUser.id}`;
                await WalletService.creditRefund({
                    userId: guestUser.id,
                    amount: guestDeposit,
                    referenceId: guestRef,
                    reason: 'Party Plan Both Confirmed Arrival (Guest Refund)',
                    partyPlanId: plan.id,
                    transaction,
                });
                await acceptedReq.update({ joinerPaymentStatus: PartyPlanJoinerPaymentStatus.REFUNDED }, { transaction });
                await ReliabilityService.updateScore({
                    userId: guestUser.id,
                    action: ReliabilityAction.CONFIRMED_ARRIVAL,
                    partyPlanId: plan.id,
                    transaction,
                });
            }

            await plan.update({
                status: PartyPlanStatus.INACTIVE,
                lifecycleStatus: PartyPlanLifecycleStatus.PLAN_COMPLETED,
                attendanceDecision: 'both_confirmed',
                reachRefundDecision: 'both_refunded',
                reachVerificationStage: 'decided',
                paymentStatus: 'Completed (Both Refunded)'
            }, { transaction });
        } else if (bothAnswered && acceptedReq) {
            // Both users have submitted their final answers (Cases B, C, D)
            isFinalized = true;
            const hostUser = await User.findByPk(plan.userId, { transaction, lock: transaction.LOCK.UPDATE });
            const guestUser = await User.findByPk(acceptedReq.requesterId, { transaction, lock: transaction.LOCK.UPDATE });

            if (hostArrived && !guestArrived) {
                // ── CASE B: Host YES, Guest NO ──
                if (hostUser) {
                    const hostRef = `PARTY_PLAN:${plan.id}:ARRIVAL_REFUND:${hostUser.id}`;
                    await WalletService.creditRefund({
                        userId: hostUser.id,
                        amount: hostDeposit,
                        referenceId: hostRef,
                        reason: 'Party Plan Confirmed Arrival (Host Refund, Guest No-Show)',
                        partyPlanId: plan.id,
                        transaction,
                    });
                    await plan.update({ hostPaymentStatus: PartyPlanPaymentStatus.REFUNDED }, { transaction });
                    await ReliabilityService.updateScore({
                        userId: hostUser.id,
                        action: ReliabilityAction.CONFIRMED_ARRIVAL,
                        partyPlanId: plan.id,
                        transaction,
                    });
                }
                if (guestUser) {
                    await ReliabilityService.updateScore({
                        userId: guestUser.id,
                        action: ReliabilityAction.NO_SHOW,
                        partyPlanId: plan.id,
                        transaction,
                    });
                }
                await plan.update({
                    status: PartyPlanStatus.INACTIVE,
                    lifecycleStatus: PartyPlanLifecycleStatus.PLAN_COMPLETED,
                    attendanceDecision: 'host_only_confirmed',
                    reachRefundDecision: 'host_refunded',
                    reachVerificationStage: 'decided',
                    paymentStatus: 'Completed (Host Refunded, Guest No-Show)'
                }, { transaction });
            } else if (!hostArrived && guestArrived) {
                // ── CASE C: Host NO, Guest YES ──
                if (guestUser && guestDeposit > 0) {
                    const guestRef = `PARTY_PLAN:${plan.id}:ARRIVAL_REFUND:${guestUser.id}`;
                    await WalletService.creditRefund({
                        userId: guestUser.id,
                        amount: guestDeposit,
                        referenceId: guestRef,
                        reason: 'Party Plan Confirmed Arrival (Guest Refund, Host No-Show)',
                        partyPlanId: plan.id,
                        transaction,
                    });
                    await acceptedReq.update({ joinerPaymentStatus: PartyPlanJoinerPaymentStatus.REFUNDED }, { transaction });
                    await ReliabilityService.updateScore({
                        userId: guestUser.id,
                        action: ReliabilityAction.CONFIRMED_ARRIVAL,
                        partyPlanId: plan.id,
                        transaction,
                    });
                }
                if (hostUser) {
                    await ReliabilityService.updateScore({
                        userId: hostUser.id,
                        action: ReliabilityAction.NO_SHOW,
                        partyPlanId: plan.id,
                        transaction,
                    });
                }
                await plan.update({
                    status: PartyPlanStatus.INACTIVE,
                    lifecycleStatus: PartyPlanLifecycleStatus.PLAN_COMPLETED,
                    attendanceDecision: 'partner_only_confirmed',
                    reachRefundDecision: 'partner_refunded',
                    reachVerificationStage: 'decided',
                    paymentStatus: 'Completed (Guest Refunded, Host No-Show)'
                }, { transaction });
            } else {
                // ── CASE D: Both NO ──
                if (hostUser) {
                    await ReliabilityService.updateScore({
                        userId: hostUser.id,
                        action: ReliabilityAction.NO_SHOW,
                        partyPlanId: plan.id,
                        transaction,
                    });
                }
                if (guestUser) {
                    await ReliabilityService.updateScore({
                        userId: guestUser.id,
                        action: ReliabilityAction.NO_SHOW,
                        partyPlanId: plan.id,
                        transaction,
                    });
                }
                await plan.update({
                    status: PartyPlanStatus.INACTIVE,
                    lifecycleStatus: PartyPlanLifecycleStatus.PLAN_COMPLETED,
                    attendanceDecision: 'both_not_confirmed',
                    reachRefundDecision: 'no_refund',
                    reachVerificationStage: 'decided',
                    paymentStatus: 'Closed (Both No-Show)'
                }, { transaction });
            }
        }

        await transaction.commit();

        // Asynchronous pushes, notifications & socket emissions
        setImmediate(async () => {
            try {
                const { io } = require('../server');
                const venueName = (plan as any).venue?.name || 'Venue';

                if (bothArrived && acceptedReq) {
                    const host = await User.findByPk(plan.userId);
                    const joiner = await User.findByPk(acceptedReq.requesterId);
                    const tokens = [host?.fcmToken, joiner?.fcmToken].filter(Boolean) as string[];

                    if (tokens.length > 0) {
                        await sendMulticastPushNotification(tokens, {
                            title: '🎉 Both of you have arrived!',
                            body: `Your Party Plan at ${venueName} is confirmed. ₹99 Commitment Deposit refunded to your LUNARA Wallet.`,
                            data: {
                                type: 'arrival_success',
                                partyPlanId: plan.id,
                                refundStatus: 'SUCCESS',
                                refundAmount: '99',
                            }
                        });
                    }

                    await NotificationService.dispatch({
                        recipientUserId: plan.userId,
                        actorUserId: acceptedReq.requesterId,
                        eventType: 'party_completed',
                        category: 'events',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: '🎉 Party Completed',
                        body: `Both participants confirmed arrival. ₹99 Commitment Deposit refunded to your LUNARA Wallet.`,
                        metadata: { planId: plan.id, refundAmount: 99, status: 'SUCCESS' },
                        idempotencyKey: `both_arrived_host_${plan.id}`,
                    });

                    await NotificationService.dispatch({
                        recipientUserId: acceptedReq.requesterId,
                        actorUserId: plan.userId,
                        eventType: 'party_completed',
                        category: 'events',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: '🎉 Party Completed',
                        body: `Both participants confirmed arrival. ₹99 Commitment Deposit refunded to your LUNARA Wallet.`,
                        metadata: { planId: plan.id, refundAmount: 99, status: 'SUCCESS' },
                        idempotencyKey: `both_arrived_guest_${plan.id}`,
                    });

                    if (io) {
                        io.to(`user_${plan.userId}`).emit('party_plan_both_arrived', { planId: plan.id, refundAmount: 99 });
                        io.to(`user_${acceptedReq.requesterId}`).emit('party_plan_both_arrived', { planId: plan.id, refundAmount: 99 });
                    }
                }

                if (io && acceptedReq) {
                    const partnerId = isHost ? acceptedReq.requesterId : plan.userId;
                    const updatedHostReach = isHost ? targetReachStatus : (plan.hostReachStatus || 'PENDING');
                    const updatedPartnerReach = !isHost ? targetReachStatus : (acceptedReq.partnerReachStatus || 'PENDING');

                    io.to(`user_${partnerId}`).emit('party_plan_reach_update', {
                        planId: plan.id,
                        partyPlanId: plan.id,
                        respondedBy: userId,
                        isHost,
                        choice: targetReachStatus,
                        hostReachStatus: updatedHostReach,
                        partnerReachStatus: updatedPartnerReach,
                        bothArrived,
                        isFinalized
                    });

                    io.to(`user_${partnerId}`).emit('party_plan_arrival_update', {
                        planId: plan.id,
                        hostArrived,
                        guestArrived,
                        hostReachStatus: updatedHostReach,
                        partnerReachStatus: updatedPartnerReach
                    });

                    io.emit('live_feed_update', {
                        type: 'party_plan_reach_update',
                        planId: plan.id,
                        partyPlanId: plan.id,
                        hostReachStatus: updatedHostReach,
                        partnerReachStatus: updatedPartnerReach,
                        bothArrived
                    });
                }
            } catch (err: any) {
                logger.warn('Error in post-arrival notification dispatch:', err.message);
            }
        });

        if (bothArrived) {
            res.json({
                success: true,
                bothArrived: true,
                isHost,
                confirmed: true,
                refundStatus: 'SUCCESS',
                refundAmount: 99,
                message: 'Both participants arrived! ₹99 commitment deposit refunded to your LUNARA Wallet.'
            });
        } else if (isFinalized) {
            const userRefunded = (isHost && hostArrived) || (!isHost && guestArrived);
            res.json({
                success: true,
                bothArrived: false,
                isHost,
                confirmed: isYes,
                isFinalized: true,
                refundStatus: userRefunded ? 'SUCCESS' : 'NONE',
                refundAmount: userRefunded ? 99 : 0,
                message: userRefunded
                    ? 'Arrival recorded. ₹99 deposit refunded to your wallet.'
                    : 'Arrival recorded: Not reached.'
            });
        } else {
            res.json({
                success: true,
                bothArrived: false,
                isHost,
                confirmed: isYes,
                waitingForPartner: true,
                message: isYes
                    ? "Arrival confirmed! Waiting for your partner's confirmation."
                    : "Response recorded: Not reached. You can update your response until the window closes."
            });
        }
    } catch (err: any) {
        await transaction.rollback();
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
export async function batchEnrichPartyPlanNotificationCards(planIds: string[], recipientUserId: string) {
    if (!planIds || planIds.length === 0) return [];
    try {
        const fullPlans = await PartyPlan.findAll({
            where: { id: { [Op.in]: planIds } },
            include: [
                {
                    model: User,
                    as: 'creator',
                    attributes: ['id', 'firstName', 'lastName', 'profileImageUrl', 'email', 'phone', 'dateOfBirth'],
                    include: [
                        { model: UserProfile, as: 'profile', attributes: ['bio', 'occupation', 'gender', 'city'], required: false },
                        { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
                    ]
                },
                {
                    model: Venue,
                    as: 'venue',
                    attributes: ['id', 'name', 'area', 'addressLine1', 'city', 'category', 'phone'],
                    include: [{
                        model: VenueImage,
                        as: 'images',
                        attributes: ['id', 'filePath', 'imageType', 'isPrimary', 'displayOrder'],
                        required: false,
                    }]
                },
                {
                    model: PartyPlanRequest,
                    as: 'requests',
                    include: [{
                        model: User,
                        as: 'requester',
                        attributes: ['id', 'firstName', 'lastName', 'profileImageUrl', 'email', 'phone', 'dateOfBirth'],
                        include: [
                            { model: UserProfile, as: 'profile', attributes: ['bio', 'occupation', 'gender', 'city'], required: false },
                            { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
                        ]
                    }]
                }
            ]
        });

        const cards = await Promise.all(fullPlans.map(p => enrichPartyPlanNotificationCard(p, recipientUserId)));
        return cards.filter(Boolean);
    } catch (e) {
        logger.error('Error batch enriching party plans:', e);
        return [];
    }
}

export async function enrichPartyPlanNotificationCard(planOrId: string | PartyPlan, recipientUserId: string) {
    const planId = typeof planOrId === 'string' ? planOrId : (planOrId as any).id;
    try {
        let plan: PartyPlan | null;
        if (typeof planOrId === 'string') {
            plan = await PartyPlan.findByPk(planOrId, {
                include: [
                    {
                        model: User,
                        as: 'creator',
                        attributes: ['id', 'firstName', 'lastName', 'profileImageUrl', 'email', 'phone', 'dateOfBirth'],
                        include: [
                            { model: UserProfile, as: 'profile', attributes: ['bio', 'occupation', 'gender', 'city'], required: false },
                            { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
                        ]
                    },
                    {
                        model: Venue,
                        as: 'venue',
                        attributes: ['id', 'name', 'area', 'addressLine1', 'city', 'category', 'phone'],
                        include: [{
                            model: VenueImage,
                            as: 'images',
                            attributes: ['id', 'filePath', 'imageType', 'isPrimary', 'displayOrder'],
                            required: false,
                        }]
                    },
                    {
                        model: PartyPlanRequest,
                        as: 'requests',
                        include: [{
                            model: User,
                            as: 'requester',
                            attributes: ['id', 'firstName', 'lastName', 'profileImageUrl', 'email', 'phone', 'dateOfBirth'],
                            include: [
                                { model: UserProfile, as: 'profile', attributes: ['bio', 'occupation', 'gender', 'city'], required: false },
                                { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
                            ]
                        }]
                    }
                ]
            });
        } else {
            plan = planOrId;
        }

        if (!plan) return null;

        const p = plan as any;
        const isHost = plan.userId === recipientUserId;
        const matchedRequest = plan.matchedRequestId
            ? p.requests?.find((r: any) => r.id === plan.matchedRequestId)
            : p.requests?.find((r: any) => r.status === 'accepted' || r.status === 'payment_pending');
        const viewerRequest = isHost
            ? matchedRequest
            : p.requests?.find((r: any) => r.requesterId === recipientUserId);

        const counterpartUser = isHost
            ? (matchedRequest ? matchedRequest.requester : null)
            : p.creator;

        let pendingCancellation: any = null;
        if (plan.lifecycleStatus === PartyPlanLifecycleStatus.CANCELLATION_REQUESTED || (plan as any).cancellationRequests?.length) {
            try {
                const PartyPlanCancellationRequest = (await import('../models/PartyPlanCancellationRequest')).default;
                pendingCancellation = await PartyPlanCancellationRequest.findOne({
                    where: { planId: plan.id, status: 'pending' },
                    order: [['createdAt', 'DESC']],
                });
            } catch (cancErr) {
                logger.warn('[enrichPartyPlanNotificationCard] Error querying pending cancellation:', cancErr);
            }
        }

        // Mask the venue for this recipient until the host has accepted their
        // request — mirrors buildVenueData's condition exactly.
        const isSecretVenue = plan.showVenueDetails === false && !isHost &&
            !(viewerRequest && [PartyPlanRequestStatus.ACCEPTED, PartyPlanRequestStatus.PAYMENT_PENDING].includes(viewerRequest.status));

        let hostPhoto = p.creator?.profileImageUrl || null;
        if (!hostPhoto && p.creator?.photos && p.creator.photos.length > 0) {
            const prim = p.creator.photos.find((ph: any) => ph.isPrimary) || p.creator.photos[0];
            if (prim?.filePath) hostPhoto = prim.filePath;
        }
        if (hostPhoto && typeof hostPhoto === 'string' && !hostPhoto.startsWith('http') && !hostPhoto.startsWith('assets/')) {
            const cl = hostPhoto.replace(/\\/g, '/');
            hostPhoto = cl.startsWith('/') ? cl : '/' + cl;
        }

        let counterpartPhoto = counterpartUser?.profileImageUrl || null;
        if (!counterpartPhoto && counterpartUser?.photos && counterpartUser.photos.length > 0) {
            const prim = counterpartUser.photos.find((ph: any) => ph.isPrimary) || counterpartUser.photos[0];
            if (prim?.filePath) counterpartPhoto = prim.filePath;
        }
        if (counterpartPhoto && typeof counterpartPhoto === 'string' && !counterpartPhoto.startsWith('http') && !counterpartPhoto.startsWith('assets/')) {
            const cl = counterpartPhoto.replace(/\\/g, '/');
            counterpartPhoto = cl.startsWith('/') ? cl : '/' + cl;
        }

        let venueCover = p.venue?.coverImageUrl || p.venue?.imageUrl || null;
        if (!venueCover && p.venue?.images && p.venue.images.length > 0) {
            const prim = p.venue.images.find((img: any) => img.isPrimary || String(img.imageType || '').toLowerCase().includes('cover')) || p.venue.images[0];
            if (prim?.filePath) venueCover = prim.filePath;
        }
        if (venueCover && typeof venueCover === 'string' && !venueCover.startsWith('http') && !venueCover.startsWith('assets/')) {
            const cl = venueCover.replace(/\\/g, '/');
            venueCover = cl.startsWith('/') ? cl : '/' + cl;
        }
        if (isSecretVenue) {
            venueCover = 'https://placehold.co/600x400/2a1b38/e0a0ff.png?text=Secret+Venue+%F0%9F%94%92';
        }

        const hostName = `${p.creator?.firstName || 'Host'} ${p.creator?.lastName || ''}`.trim();
        const guestName = counterpartUser ? `${counterpartUser.firstName || 'Joiner'} ${counterpartUser.lastName || ''}`.trim() : 'Partner';

        const partyImage = hostPhoto || p.creator?.profileImageUrl || '';
        let planTitle = plan.message || 'Party Night Out';
        const venueArea = p.venue?.area || 'Pune';
        const distance = '1.2 km';
        const dateStr = formatDateFull(plan.planDateTime, undefined, false);
        const timeStr = formatTime12Hour(plan.planDateTime);

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
        const permittedActions: Array<{ key: string; requestId?: string }> = [];

        if (!isHost && viewerRequest?.status === PartyPlanRequestStatus.CANCELLED) {
            const cancellationReason = viewerRequest.cancellationReason || '';
            currentStatusText = cancellationReason === 'revoked_by_host'
                ? 'Acceptance withdrawn by host'
                : cancellationReason === 'withdrawn_by_requester'
                    ? 'Request withdrawn'
                    : 'Request cancelled';
        } else if (!isHost && viewerRequest?.status === PartyPlanRequestStatus.REJECTED) {
            currentStatusText = 'Request declined';
        }

        if (viewerRequest?.status === PartyPlanRequestStatus.PENDING && !isHost) {
            currentStatusText = 'Request Sent';
            primaryAction = 'Cancel Request';
            primaryActionUrl = '/party-plans/requests/' + viewerRequest.id + '/cancel';
            permittedActions.push({ key: 'cancel_request', requestId: viewerRequest.id });
        } else if (!isHost && viewerRequest && [PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.ACCEPTED].includes(viewerRequest.status) && !viewerRequest.joinerRazorpayPaymentId && !viewerRequest.cancelledAt) {
            currentStatusText = 'Action Required: Pay Deposit';
            primaryAction = 'Pay Now';
            primaryActionUrl = '/party-plans/' + plan.id + '/pay-joiner/' + viewerRequest.id;
            secondaryAction = 'Withdraw';
            secondaryActionUrl = '/party-plans/requests/' + viewerRequest.id + '/withdraw';
            permittedActions.push({ key: 'pay_deposit', requestId: viewerRequest.id }, { key: 'withdraw_request', requestId: viewerRequest.id });
        } else if (isHost && matchedRequest && [PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.ACCEPTED].includes(matchedRequest.status) && !matchedRequest.joinerRazorpayPaymentId && !matchedRequest.cancelledAt) {
            permittedActions.push({ key: 'revoke_acceptance', requestId: matchedRequest.id });
            if (plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID) {
                currentStatusText = 'Participant payment pending';
                primaryAction = 'Revoke Acceptance';
                primaryActionUrl = '/party-plans/requests/' + matchedRequest.id + '/revoke';
            }
        } else if (status === PartyPlanLifecycleStatus.CANCELLED) {
            currentStatusText = 'Cancelled';
        } else if (status === PartyPlanLifecycleStatus.CANCELLATION_REQUESTED || pendingCancellation) {
            const cancRequestedBy = pendingCancellation?.requestedById || '';
            const isCancelRequester = cancRequestedBy === recipientUserId;
            const isCancelRecipient = cancRequestedBy !== '' && cancRequestedBy !== recipientUserId;

            if (isCancelRequester) {
                currentStatusText = 'Cancellation Request Sent • Waiting for Approval';
                primaryAction = null;
                secondaryAction = null;
            } else if (isCancelRecipient) {
                currentStatusText = 'Cancellation Requested • Action Required';
                primaryAction = 'Accept Cancellation';
                secondaryAction = 'Keep Plan';
                primaryActionUrl = `/party-plans/${plan.id}/cancellation/approve`;
                secondaryActionUrl = `/party-plans/${plan.id}/cancellation/reject`;
                if (pendingCancellation?.id) {
                    permittedActions.push(
                        { key: 'accept_cancellation', requestId: pendingCancellation.id },
                        { key: 'keep_plan', requestId: pendingCancellation.id }
                    );
                }
            } else {
                currentStatusText = 'Cancellation Requested';
            }
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
                    permittedActions.push({ key: 'pay_deposit' });
                } else {
                    const requestsList = p.requests || [];
                    const pendingJoinReqs = requestsList.filter((r: any) =>
                        r.status === 'pending' &&
                        !(plan.selectedUsers && Array.isArray(plan.selectedUsers) && plan.selectedUsers.includes(r.requesterId))
                    );
                    const pendingPrivateInvites = requestsList.filter((r: any) =>
                        r.status === 'pending' &&
                        plan.selectedUsers && Array.isArray(plan.selectedUsers) && plan.selectedUsers.includes(r.requesterId)
                    );

                    if (pendingJoinReqs.length > 0) {
                        currentStatusText = 'Request Received';
                        primaryAction = 'Review Requests';
                    } else if (pendingPrivateInvites.length > 0) {
                        currentStatusText = 'Invitation Sent • Awaiting Response';
                        primaryAction = null;
                    } else {
                        currentStatusText = 'Active';
                    }
                }
            } else {
                if (viewerRequest?.status === PartyPlanRequestStatus.WAITING) {
                    currentStatusText = 'Spot Claimed • On Waiting List';
                    primaryAction = null;
                } else {
                    const isPrivateInviteForUser = !!(
                        plan.selectedUsers &&
                        Array.isArray(plan.selectedUsers) &&
                        plan.selectedUsers.includes(recipientUserId)
                    );

                    if (isPrivateInviteForUser && viewerRequest?.status === PartyPlanRequestStatus.PENDING) {
                        currentStatusText = 'Private Party Invitation';
                        primaryAction = 'Accept';
                        secondaryAction = 'Decline';
                        primaryActionUrl = `/party-plans/requests/${viewerRequest.id}/accept-invite`;
                        secondaryActionUrl = `/party-plans/requests/${viewerRequest.id}/decline-invite`;
                        permittedActions.push(
                            { key: 'accept_invite', requestId: viewerRequest.id },
                            { key: 'decline_invite', requestId: viewerRequest.id }
                        );
                    } else if (viewerRequest?.status === PartyPlanRequestStatus.PENDING) {
                        currentStatusText = 'Request Sent';
                        primaryAction = 'Cancel Request';
                        primaryActionUrl = `/party-plans/requests/${viewerRequest.id}/cancel`;
                        permittedActions.push({ key: 'cancel_request', requestId: viewerRequest.id });
                    } else {
                        currentStatusText = 'Active';
                    }
                }
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

        const hostObj = {
            id: p.creator?.id,
            firstName: p.creator?.firstName,
            lastName: p.creator?.lastName,
            name: hostName,
            profileImageUrl: hostPhoto,
            profilePhotoUrl: hostPhoto,
            bio: p.creator?.profile?.bio,
            occupation: p.creator?.profile?.occupation,
        };

        const guestObj = counterpartUser ? {
            id: counterpartUser.id,
            firstName: counterpartUser.firstName,
            lastName: counterpartUser.lastName,
            name: guestName,
            profileImageUrl: counterpartPhoto,
            profilePhotoUrl: counterpartPhoto,
            bio: counterpartUser.profile?.bio,
            occupation: counterpartUser.profile?.occupation,
        } : null;

        const venueObj = p.venue ? {
            id: p.venue.id,
            name: isSecretVenue ? 'Secret Venue 🔒' : p.venue.name,
            area: isSecretVenue ? 'Secret Location' : p.venue.area,
            addressLine1: isSecretVenue ? 'Revealed upon host approval' : p.venue.addressLine1,
            city: p.venue.city,
            category: p.venue.category,
            latitude: p.venue.latitude,
            longitude: p.venue.longitude,
            phone: isSecretVenue ? null : p.venue.phone,
            coverImage: venueCover ? { filePath: venueCover, url: venueCover } : null,
            coverImageUrl: venueCover,
            imageUrl: venueCover,
            images: isSecretVenue ? [] : (p.venue.images || []),
            isSecret: isSecretVenue,
        } : null;

        if (isSecretVenue && p.venue?.name) {
            planTitle = planTitle.replace(new RegExp(p.venue.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi'), 'a Secret Venue 🔒');
        }

        return {
            partyPlanId: plan.id,
            id: plan.id,
            partyImage,
            hostName,
            guestName,
            hostProfilePhotoUrl: hostPhoto,
            guestProfilePhotoUrl: counterpartPhoto,
            host: hostObj,
            creator: hostObj,
            user: hostObj,
            guest: guestObj,
            partner: isHost ? guestObj : hostObj,
            matchedPartner: isHost ? guestObj : hostObj,
            venue: venueObj,
            venueImageUrl: venueCover,
            planTitle,
            venueName: venueObj?.name || 'Venue',
            venueArea: venueObj?.area || venueArea,
            canSeeVenue: !isSecretVenue,
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
            lastActivityAt: (() => {
                let latestActivityTime = new Date(plan.updatedAt || plan.createdAt || Date.now()).getTime();
                if (plan.createdAt && new Date(plan.createdAt).getTime() > latestActivityTime) {
                    latestActivityTime = new Date(plan.createdAt).getTime();
                }
                if (plan.acceptedAt && new Date(plan.acceptedAt).getTime() > latestActivityTime) {
                    latestActivityTime = new Date(plan.acceptedAt).getTime();
                }
                if (p.requests && Array.isArray(p.requests)) {
                    for (const req of p.requests) {
                        if (req.createdAt && new Date(req.createdAt).getTime() > latestActivityTime) {
                            latestActivityTime = new Date(req.createdAt).getTime();
                        }
                        if (req.updatedAt && new Date(req.updatedAt).getTime() > latestActivityTime) {
                            latestActivityTime = new Date(req.updatedAt).getTime();
                        }
                    }
                }
                return new Date(latestActivityTime).toISOString();
            })(),
            requiresAction: Boolean(
                ((status === PartyPlanLifecycleStatus.CANCELLATION_REQUESTED || pendingCancellation) &&
                    pendingCancellation?.requestedById &&
                    pendingCancellation.requestedById !== recipientUserId) ||
                (isHost && (p.requests?.some((r: any) => r.status === 'pending') || (plan.hostPaymentStatus !== 'paid' && plan.status === 'active'))) ||
                (!isHost && viewerRequest && [PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.ACCEPTED].includes(viewerRequest.status) && viewerRequest.joinerPaymentStatus !== 'paid')
            ),
            cancellationRequest: pendingCancellation ? {
                id: pendingCancellation.id,
                requestId: pendingCancellation.id,
                requestedById: pendingCancellation.requestedById,
                recipientUserId: pendingCancellation.recipientUserId,
                reason: pendingCancellation.reason,
                otherReasonText: pendingCancellation.otherReasonText,
                status: pendingCancellation.status,
                requestedAt: pendingCancellation.requestedAt ? pendingCancellation.requestedAt.toISOString() : null,
            } : null,
            requestedById: pendingCancellation?.requestedById || null,
            cancellationRequestId: pendingCancellation?.id || null,
            matchedRequestId: plan.matchedRequestId,
            requestId: matchedRequest?.id || null,
            hostPaymentStatus: plan.hostPaymentStatus,
            depositAmount: plan.depositAmount,
            hostRazorpayOrderId: plan.hostRazorpayOrderId,
            joinerPaymentStatus: matchedRequest?.joinerPaymentStatus || 'unpaid',
            joinerRazorpayOrderId: matchedRequest?.joinerRazorpayOrderId || null,
            requestStatus: viewerRequest?.status || null,
            permittedActions,
            cancellationReason: viewerRequest?.cancellationReason || null,
            acceptedAt: plan.acceptedAt ? plan.acceptedAt.toISOString() : null,
            paymentDeadlineAt: plan.paymentDeadlineAt ? plan.paymentDeadlineAt.toISOString() : null,
            serverTime: new Date().toISOString(),
            isHost,
            role: isHost ? 'host' : 'viewer',
            status: plan.status,
            lifecycleStatus: plan.lifecycleStatus,
            planDateTime: plan.planDateTime ? plan.planDateTime.toISOString() : null,
            eventDateTime: plan.planDateTime ? plan.planDateTime.toISOString() : null,
            visibility: plan.visibility,
            foodPreference: plan.foodPreference,
            drinkPreference: plan.drinkPreference,
            showProfilePhoto: plan.showProfilePhoto ?? true,
            showHostName: plan.showHostName ?? true,
            showVenueDetails: plan.showVenueDetails ?? true,
            showDateDetails: plan.showDateDetails ?? true,
            // ── 30-Minute Authoritative Venue Reach Confirmation Fields ─────────
            hostReachStatus: plan.hostReachStatus || (plan.hostArrivalConfirmed ? 'REACHED' : 'PENDING'),
            partnerReachStatus: matchedRequest?.partnerReachStatus || (matchedRequest?.guestArrivalConfirmed ? 'REACHED' : 'PENDING'),
            hostArrivalConfirmed: Boolean(plan.hostArrivalConfirmed),
            guestArrivalConfirmed: Boolean(matchedRequest?.guestArrivalConfirmed),
            hostArrivalTime: plan.hostArrivalTime || null,
            guestArrivalTime: matchedRequest?.guestArrivalTime || null,
            reachConfirmation30mSent: Boolean(plan.reachConfirmation30mSent),
            acceptedRequest: matchedRequest ? {
                id: matchedRequest.id,
                planId: matchedRequest.planId,
                requesterId: matchedRequest.requesterId,
                status: matchedRequest.status,
                joinerPaymentStatus: matchedRequest.joinerPaymentStatus,
                partnerReachStatus: matchedRequest.partnerReachStatus || (matchedRequest.guestArrivalConfirmed ? 'REACHED' : 'PENDING'),
                guestArrivalConfirmed: Boolean(matchedRequest.guestArrivalConfirmed),
                guestArrivalTime: matchedRequest.guestArrivalTime || null,
                requester: counterpartUser ? {
                    id: counterpartUser.id,
                    firstName: counterpartUser.firstName,
                    lastName: counterpartUser.lastName,
                    profileImageUrl: counterpartPhoto,
                    profilePhotoUrl: counterpartPhoto,
                } : null
            } : null,
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
        // Verified token identity must win over a client-supplied query value.
        const userId = (req.user as any)?.id || (req.query.userId as string);

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
                eventDate: plan.planDateTime ? formatDateFull(plan.planDateTime, undefined, false) : '',
                eventTime: plan.planDateTime ? formatTime12Hour(plan.planDateTime) : '',
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

/**
 * GET /api/mobile/party-plans/:id/reach-status
 * Returns current 30-min venue reach confirmation state for Host & Partner
 */
export const getReachStatus = async (req: Request, res: Response): Promise<void> => {
    try {
        const rawId = String(req.params.id || req.params.planId || req.query?.planId || '');
        const id = rawId ? rawId.replace(/^(pp_|party_plan_|party_plan_timeline_)/i, '') : '';
        const userId = (req as any).user?.id || req.body?.userId || req.query?.userId;

        if (!userId) {
            res.status(401).json({ success: false, message: 'Unauthorized' });
            return;
        }

        let plan = await PartyPlan.findByPk(id, {
            include: [{ model: Venue, as: 'venue', attributes: ['name', 'addressLine1', 'area'] }]
        });
        if (!plan && rawId && rawId !== id) {
            plan = await PartyPlan.findByPk(rawId, {
                include: [{ model: Venue, as: 'venue', attributes: ['name', 'addressLine1', 'area'] }]
            });
        }
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        let acceptedReq: PartyPlanRequest | null = null;
        if (plan.matchedRequestId) {
            acceptedReq = await PartyPlanRequest.findByPk(plan.matchedRequestId, {
                include: [{ model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] }]
            });
        }
        if (!acceptedReq) {
            const planIdsToSearch: string[] = [id, rawId].filter(Boolean);
            acceptedReq = await PartyPlanRequest.findOne({
                where: {
                    planId: { [Op.in]: planIdsToSearch },
                    status: { [Op.in]: [PartyPlanRequestStatus.ACCEPTED, 'accepted', 'ACCEPTED', 'confirmed', 'CONFIRMED', 'paid', 'PAID', 'payment_pending', 'PAYMENT_PENDING'] }
                },
                order: [['updatedAt', 'DESC']],
                include: [{ model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] }]
            });
        }

        const isHost = plan.userId === userId;
        const isGuest = acceptedReq ? acceptedReq.requesterId === userId : (plan as any).matchedUserId === userId;

        if (!isHost && !isGuest) {
            res.status(403).json({ success: false, message: 'You are not an active participant in this plan' });
            return;
        }

        const eventTime = plan.planDateTime ? new Date(plan.planDateTime).getTime() : 0;
        const now = Date.now();
        const inArrivalWindow = Boolean(plan.reachConfirmation30mSent) ||
            plan.reachVerificationStage === 'thirty_min_reach' ||
            plan.reachVerificationStage === 'final_check' ||
            (eventTime > 0 && now >= eventTime - 45 * 60 * 1000 && now <= eventTime + 24 * 60 * 60 * 1000);

        const hostReachStatus = plan.hostReachStatus || (plan.hostArrivalConfirmed ? 'REACHED' : 'PENDING');
        const partnerReachStatus = acceptedReq?.partnerReachStatus || (acceptedReq?.guestArrivalConfirmed ? 'REACHED' : 'PENDING');
        const bothReached = hostReachStatus === 'REACHED' && partnerReachStatus === 'REACHED';

        const myReachStatus = isHost ? hostReachStatus : partnerReachStatus;
        const otherReachStatus = isHost ? partnerReachStatus : hostReachStatus;

        res.json({
            success: true,
            partyPlanId: plan.id,
            isHost,
            hostReachStatus,
            partnerReachStatus,
            myReachStatus,
            otherReachStatus,
            hostArrivalConfirmed: Boolean(plan.hostArrivalConfirmed),
            guestArrivalConfirmed: Boolean(acceptedReq?.guestArrivalConfirmed),
            bothReached,
            inArrivalWindow,
            reachConfirmation30mSent: Boolean(plan.reachConfirmation30mSent),
            scheduledTime: plan.planDateTime,
            canConfirm: inArrivalWindow && myReachStatus === 'PENDING' && plan.status !== 'cancelled' && plan.lifecycleStatus !== PartyPlanLifecycleStatus.PLAN_COMPLETED
        });
    } catch (err: any) {
        logger.error('getReachStatus error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch reach status', error: err.message });
    }
};

