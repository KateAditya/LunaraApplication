import cron from 'node-cron';
import { Op } from 'sequelize';
import StrangersMeetRequest, {
    StrangersMeetStatus,
    StrangersMeetPaymentStatus,
} from '../models/StrangersMeetRequest';
import StrangersMeetHostCancellationRequest, {
    HostCancellationStatus,
} from '../models/StrangersMeetHostCancellationRequest';
import User from '../models/User';
import { StrangersMeetService } from '../services/StrangersMeetService';
import { logger } from '../config/logger';
import AuditLog from '../models/AuditLog';
import { checkAndTriggerStrangersMeetLifecycle } from './partyPlanCron';

/**
 * Strangers Meet Lifecycle & 24h Escalation Background Cron
 * Runs every minute to enforce server-authoritative state transitions:
 * 1. START_CONFIRMATION_PENDING when scheduledStartAt arrives.
 * 2. 24-HOUR FALLBACK: transitions unconfirmed meets to NEEDS_HOST_CONTACT and alerts admin.
 * 3. END_CONFIRMATION_PENDING when expectedEndAt arrives.
 */
let isStrangersMeetCronRunning = false;
const escalatedCancellationMap = new Map<string, number>();

export const startStrangersMeetCron = () => {
    // Run every minute with overlap protection
    cron.schedule('* * * * *', () => {
        setTimeout(async () => {
            if (isStrangersMeetCronRunning) {
                return;
            }
            isStrangersMeetCronRunning = true;
            try {
                await checkAndTriggerStrangersMeetLifecycle().catch((lErr) => {
                    logger.error('[StrangersMeetCron] Lifecycle prompt check error:', lErr);
                });
            const now = new Date();
            const twentyFourHoursAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);

            // ─────────────────────────────────────────────────────────────────
            // 1. Check for 24-Hour Timeout Escalation (NEEDS_HOST_CONTACT)
            // ─────────────────────────────────────────────────────────────────
            const overdueStartMeets = await StrangersMeetRequest.findAll({
                where: {
                    status: {
                        [Op.in]: [
                            StrangersMeetStatus.APPROVED,
                            StrangersMeetStatus.START_CONFIRMATION_PENDING,
                        ],
                    },
                    paymentStatus: StrangersMeetPaymentStatus.PAID,
                    eventDateTime: {
                        [Op.lte]: twentyFourHoursAgo,
                    },
                },
                limit: 500,
            });

            for (const meet of overdueStartMeets) {
                try {
                    await meet.update({
                        status: StrangersMeetStatus.NEEDS_HOST_CONTACT,
                        escalatedAt: now,
                        escalationReason: 'No host start confirmation within 24 hours after scheduled time',
                    });

                    await AuditLog.logAction({
                        userId: meet.userId,
                        partyPlanId: meet.id,
                        action: 'Strangers Meet Escalated (Needs Host Contact)',
                        metadata: {
                            reason: 'No host confirmation within 24 hours',
                            eventDateTime: meet.eventDateTime,
                            escalatedAt: now,
                        },
                    });

                    await StrangersMeetService.emitNotification({
                        recipientUserId: meet.userId,
                        entityId: meet.id,
                        eventType: 'strangers_meet_needs_host_contact',
                        title: '⚠️ Status Update Required',
                        body: 'Your Strangers Meetup status was not confirmed within 24 hours. Our team will contact you.',
                        notifyAdmins: true,
                        metadata: {
                            meetId: meet.id,
                            status: StrangersMeetStatus.NEEDS_HOST_CONTACT,
                            reason: 'No host confirmation within 24 hours',
                        },
                    });
                    logger.info(`[StrangersMeetCron] Meet ${meet.id} escalated to NEEDS_HOST_CONTACT (start timeout).`);
                } catch (itemErr) {
                    logger.error(`[StrangersMeetCron] Error escalating start-overdue meet ${meet.id}:`, itemErr);
                }
            }

            // ─────────────────────────────────────────────────────────────────
            // 2. Check for In-Progress Meets without End Confirmation > 24 Hours
            // ─────────────────────────────────────────────────────────────────
            const overdueEndMeets = await StrangersMeetRequest.findAll({
                where: {
                    status: {
                        [Op.in]: [
                            StrangersMeetStatus.IN_PROGRESS,
                            StrangersMeetStatus.END_CONFIRMATION_PENDING,
                        ],
                    },
                    startedAt: {
                        [Op.lte]: twentyFourHoursAgo,
                    },
                },
            });

            for (const meet of overdueEndMeets) {
                try {
                    await meet.update({
                        status: StrangersMeetStatus.NEEDS_HOST_CONTACT,
                        escalatedAt: now,
                        escalationReason: 'Meetup was started but host did not confirm end within 24 hours',
                    });

                    await AuditLog.logAction({
                        userId: meet.userId,
                        partyPlanId: meet.id,
                        action: 'Strangers Meet Escalated (End Confirmation Timeout)',
                        metadata: {
                            reason: 'No end confirmation within 24 hours of start',
                            startedAt: meet.startedAt,
                            escalatedAt: now,
                        },
                    });

                    await StrangersMeetService.emitNotification({
                        recipientUserId: meet.userId,
                        entityId: meet.id,
                        eventType: 'strangers_meet_needs_host_contact',
                        title: '⚠️ End Confirmation Required',
                        body: 'Your Strangers Meetup was not closed within 24 hours. Lunara Admin has been notified for review.',
                        notifyAdmins: true,
                        metadata: {
                            meetId: meet.id,
                            status: StrangersMeetStatus.NEEDS_HOST_CONTACT,
                        },
                    });
                    logger.info(`[StrangersMeetCron] Meet ${meet.id} escalated to NEEDS_HOST_CONTACT (end timeout).`);
                } catch (itemErr) {
                    logger.error(`[StrangersMeetCron] Error escalating end-overdue meet ${meet.id}:`, itemErr);
                }
            }

            // ─────────────────────────────────────────────────────────────────
            // 3. Check for Arrived Start Time -> START_CONFIRMATION_PENDING
            // ─────────────────────────────────────────────────────────────────
            const readyToStartMeets = await StrangersMeetRequest.findAll({
                where: {
                    status: StrangersMeetStatus.APPROVED,
                    paymentStatus: StrangersMeetPaymentStatus.PAID,
                    eventDateTime: {
                        [Op.lte]: now,
                        [Op.gt]: twentyFourHoursAgo,
                    },
                },
            });

            for (const meet of readyToStartMeets) {
                try {
                    await meet.update({
                        status: StrangersMeetStatus.START_CONFIRMATION_PENDING,
                    });

                    await StrangersMeetService.emitNotification({
                        recipientUserId: meet.userId,
                        entityId: meet.id,
                        eventType: 'strangers_meet_start_confirmation_pending',
                        title: '⏰ Strangers Meet Time Reached',
                        body: 'Your Strangers Meet is scheduled now. Please confirm if the meetup has started.',
                        notifyAdmins: false,
                        metadata: { meetId: meet.id, eventDateTime: meet.eventDateTime },
                    });
                } catch (itemErr) {
                    logger.error(`[StrangersMeetCron] Error transitioning meet ${meet.id} to START_CONFIRMATION_PENDING:`, itemErr);
                }
            }

            // ─────────────────────────────────────────────────────────────────
            // 4. Check for Arrived Expected End Time -> END_CONFIRMATION_PENDING
            // ─────────────────────────────────────────────────────────────────
            const readyToEndMeets = await StrangersMeetRequest.findAll({
                where: {
                    status: StrangersMeetStatus.IN_PROGRESS,
                    expectedEndAt: {
                        [Op.lte]: now,
                    },
                    startedAt: {
                        [Op.gt]: twentyFourHoursAgo,
                    },
                },
            });

            for (const meet of readyToEndMeets) {
                try {
                    await meet.update({
                        status: StrangersMeetStatus.END_CONFIRMATION_PENDING,
                    });

                    await StrangersMeetService.emitNotification({
                        recipientUserId: meet.userId,
                        entityId: meet.id,
                        eventType: 'strangers_meet_end_confirmation_pending',
                        title: '🏁 Strangers Meet Ending Time Reached',
                        body: 'The expected duration of your meetup has ended. Please confirm if the meetup has ended.',
                        notifyAdmins: false,
                        metadata: { meetId: meet.id, expectedEndAt: meet.expectedEndAt },
                    });
                } catch (itemErr) {
                    logger.error(`[StrangersMeetCron] Error transitioning meet ${meet.id} to END_CONFIRMATION_PENDING:`, itemErr);
                }
            }

            // ─────────────────────────────────────────────────────────────────
            // 5. Check for 24-Hour Unresolved Host Cancellations & Pending Refunds (Phase 17)
            // ─────────────────────────────────────────────────────────────────
            const overdueCancellations = await StrangersMeetHostCancellationRequest.findAll({
                where: {
                    status: {
                        [Op.in]: [
                            HostCancellationStatus.PENDING_ADMIN_REVIEW,
                            HostCancellationStatus.REFUND_PROCESSING,
                        ],
                    },
                    createdAt: {
                        [Op.lte]: twentyFourHoursAgo,
                    },
                },
                include: [
                    { model: StrangersMeetRequest, as: 'meet' },
                    { model: User, as: 'host', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] }
                ],
                limit: 100,
            });

            const nowMs = now.getTime();
            for (const cancelReq of overdueCancellations) {
                const lastAlerted = escalatedCancellationMap.get(cancelReq.id);
                // Alert and write AuditLog at most once every 6 hours per cancellation request instead of every 60 seconds
                if (lastAlerted && (nowMs - lastAlerted) < 6 * 60 * 60 * 1000) {
                    continue;
                }
                escalatedCancellationMap.set(cancelReq.id, nowMs);

                try {
                    const hostUser = (cancelReq as any).host;
                    const hostName = hostUser ? `${hostUser.firstName} ${hostUser.lastName}`.trim() : 'Host';
                    logger.warn(`[StrangersMeetCron] ⚠️ Strangers Meet Refund Requires Attention: Meet ${cancelReq.meetId}, Host: ${hostName}, Status: ${cancelReq.status}`);
                    await AuditLog.logAction({
                        userId: cancelReq.hostUserId,
                        partyPlanId: cancelReq.meetId,
                        action: 'Strangers Meet Cancellation Unresolved > 24 Hours',
                        metadata: {
                            meetId: cancelReq.meetId,
                            cancellationId: cancelReq.id,
                            hostName,
                            totalCollectedAmount: cancelReq.totalCollectedAmount,
                            status: cancelReq.status,
                            reason: cancelReq.reason,
                        },
                    });
                } catch (cErr) {
                    logger.error(`[StrangersMeetCron] Error escalating overdue cancellation ${cancelReq.id}:`, cErr);
                }
            }
        } catch (globalErr) {
            logger.error('[StrangersMeetCron] Global error during execution:', globalErr);
        } finally {
            isStrangersMeetCronRunning = false;
        }
        }, 150);
    });

    logger.info('[StrangersMeetCron] Strangers Meet lifecycle & escalation background worker registered.');
};
