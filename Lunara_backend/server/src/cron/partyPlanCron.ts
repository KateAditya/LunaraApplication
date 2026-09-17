import cron from 'node-cron';
import { Op } from 'sequelize';
import PartyPlanRequest, { PartyPlanRequestStatus, PartyPlanJoinerPaymentStatus } from '../models/PartyPlanRequest';
import PartyPlan, { PartyPlanStatus, PartyPlanPaymentStatus, PartyPlanLifecycleStatus } from '../models/PartyPlan';
import User from '../models/User';
import Venue from '../models/Venue';
import UserProfile from '../models/UserProfile';
import UserPhoto from '../models/UserPhoto';
import VenueImage from '../models/VenueImage';
import { logger } from '../config/logger';
import '../models';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import SubscriptionPackage, { PackageTier } from '../models/SubscriptionPackage';
import PartySafetyCheck, { SafetyStatus } from '../models/PartySafetyCheck';
import Booking, { AdminApprovalStatus, BookingStatus } from '../models/Booking';
import GroupParty, { GroupPartyStatus } from '../models/GroupParty';
import { formatTime12Hour, parseEventDateTimeToUTC } from '../utils/dateTimeUtils';

/**
 * Sweeps large-party Bookings and small GroupParty requests that were approved
 * (or had a payment link sent) but whose `expiresAt` deadline — the party's own
 * scheduled start time — has passed without payment. Flips them to 'expired' and
 * notifies the requester over push + socket, reusing the same notification shape
 * as `adminBookingController.approveLargePartyRequest`.
 */
async function expireUnpaidLargePartyRequests(now: Date): Promise<void> {
    const expiredBookings = await Booking.findAll({
        where: {
            isLargePartyRequest: true,
            adminApprovalStatus: { [Op.in]: [AdminApprovalStatus.APPROVED, AdminApprovalStatus.PAYMENT_SENT] },
            paymentStatus: { [Op.ne]: 'paid' },
            expiresAt: { [Op.lt]: now },
        },
    });

    if (expiredBookings.length > 0) {
        const userIds = [...new Set(expiredBookings.map(b => b.userId).filter(Boolean))];
        const venueIds = [...new Set(expiredBookings.map(b => b.venueId).filter(Boolean))];
        const [users, venues] = await Promise.all([
            User.findAll({ where: { id: { [Op.in]: userIds } }, attributes: ['id', 'fcmToken'] }),
            Venue.findAll({ where: { id: { [Op.in]: venueIds } }, attributes: ['id', 'name'] }),
        ]);
        const userMap = new Map(users.map(u => [u.id, u]));
        const venueMap = new Map(venues.map(v => [v.id, v]));

        for (const booking of expiredBookings) {
            await booking.update({
                adminApprovalStatus: AdminApprovalStatus.EXPIRED,
                status: BookingStatus.CANCELLED,
            });

            try {
                const host = userMap.get(booking.userId);
                const venue = venueMap.get(booking.venueId);
                const venueName = venue?.name || 'Venue';
                const title = 'Large Party Request Expired ⌛';
                const body = `Your party request at ${venueName} expired because payment wasn't completed before the event started.`;

                try {
                    const NotificationModel = (await import('../models/Notification')).default;
                    await NotificationModel.create({
                        recipientUserId: booking.userId,
                        eventType: 'large_party_expired',
                        category: 'bookings' as any,
                        entityType: 'booking',
                        entityId: booking.id,
                        title,
                        body,
                        priority: 'HIGH' as any,
                        isRead: false,
                        metadata: { bookingId: booking.id, venueName },
                    });
                } catch (dbErr) {
                    logger.warn('[Cron] Failed to save DB notification for large party expiry: ' + dbErr);
                }

                if (host?.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(host.fcmToken, {
                        title,
                        body,
                        data: { type: 'large_party_expired', bookingId: booking.id },
                    });
                }

                const { io } = require('../server');
                if (io) {
                    io.to(`user_${booking.userId}`).emit('large_party_status_update', {
                        bookingId: booking.id,
                        status: booking.adminApprovalStatus,
                    });
                    try {
                        const { GroupPartyService } = await import('../services/GroupPartyService');
                        const enrichedCard = await GroupPartyService.enrichLargePartyNotificationCard(booking.id, booking.userId);
                        io.to(`user_${booking.userId}`).emit('notification_updated', enrichedCard);
                    } catch (cardErr) {}
                }

                try {
                    const AuditLog = (await import('../models/AuditLog')).default;
                    await AuditLog.logAction({
                        userId: booking.userId,
                        action: 'LARGE_PARTY_EXPIRED',
                        bookingId: booking.id,
                        metadata: { venueName },
                    }).catch(() => {});
                } catch (aErr) {}
            } catch (notifyErr: any) {
                logger.warn(`[Cron] Failed to notify user for expired large party booking ${booking.id}: ` + notifyErr.message);
            }

            logger.info(`[Cron] Expired unpaid large party booking ${booking.id}`);
        }
    }

    const expiredGroupParties = await GroupParty.findAll({
        where: {
            status: GroupPartyStatus.APPROVED,
            paymentStatus: { [Op.ne]: 'paid' },
            expiresAt: { [Op.lt]: now },
        },
    });

    if (expiredGroupParties.length > 0) {
        const gpUserIds = [...new Set(expiredGroupParties.map(gp => gp.userId).filter(Boolean))];
        const gpVenueIds = [...new Set(expiredGroupParties.map(gp => gp.venueId).filter(Boolean))];
        const [gpUsers, gpVenues] = await Promise.all([
            User.findAll({ where: { id: { [Op.in]: gpUserIds } }, attributes: ['id', 'fcmToken'] }),
            Venue.findAll({ where: { id: { [Op.in]: gpVenueIds } }, attributes: ['id', 'name'] }),
        ]);
        const gpUserMap = new Map(gpUsers.map(u => [u.id, u]));
        const gpVenueMap = new Map(gpVenues.map(v => [v.id, v]));

        for (const groupParty of expiredGroupParties) {
            await groupParty.update({ status: GroupPartyStatus.EXPIRED });

            try {
                const host = gpUserMap.get(groupParty.userId);
                const venue = gpVenueMap.get(groupParty.venueId);
                const venueName = venue?.name || 'Venue';
                const title = 'Group Party Request Expired ⌛';
                const body = `Your group party request at ${venueName} expired because payment wasn't completed before the event started.`;

                if (host?.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(host.fcmToken, {
                        title,
                        body,
                        data: { type: 'group_party_expired', partyId: groupParty.id },
                    });
                }

                const { io } = require('../server');
                if (io) {
                    io.to(`user_${groupParty.userId}`).emit('large_party_status_update', {
                        bookingId: groupParty.id,
                        status: groupParty.status,
                    });
                    io.to(`user_${groupParty.userId}`).emit('notification_created', {
                        id: `group_party_${groupParty.id}_expired`,
                        title,
                        body,
                        createdAt: new Date().toISOString(),
                        read: false,
                        data: { type: 'group_party_expired', partyId: groupParty.id },
                    });
                }
            } catch (notifyErr: any) {
                logger.warn(`[Cron] Failed to notify user for expired group party ${groupParty.id}: ` + notifyErr.message);
            }

            logger.info(`[Cron] Expired unpaid group party ${groupParty.id}`);
        }
    }
}

// Run every 5 minutes with overlap protection
let isPartyPlanCronRunning = false;
export const startPartyPlanCron = () => {
    cron.schedule('*/5 * * * *', () => {
        setTimeout(async () => {
            if (isPartyPlanCronRunning) {
                logger.warn('[Cron] Party Plan Cron already running, skipping overlapping tick.');
                return;
            }
            isPartyPlanCronRunning = true;
            try {
                logger.info('Running Party Plan Cron Jobs...');

            // 0. Ask hosts of event-linked plans that have gone 24 hours without
            // a match what they want to do. Runs first and independently so a
            // failure in the payment-timeout sweep below cannot starve it, and
            // it is a no-op for every ordinary party plan.
            try {
                const { EventPlanNoMatchService } = await import('../services/EventPlanNoMatchService');
                const notified = await EventPlanNoMatchService.notifyUnmatchedPlans();
                if (notified > 0) {
                    logger.info(`[Cron] Prompted ${notified} unmatched event plan host(s).`);
                }
            } catch (noMatchErr: any) {
                logger.error('[Cron] Event plan no-match sweep failed:', noMatchErr?.message);
            }

            const now = new Date();

            // 1. Check for expired payment timeouts (batch limit 500 for scalability)
            const expiredRequests = await PartyPlanRequest.findAll({
                where: {
                    status: PartyPlanRequestStatus.PAYMENT_PENDING,
                    paymentTimeoutAt: {
                        [Op.lt]: now
                    }
                },
                include: [{ model: PartyPlan, as: 'plan' }],
                limit: 500,
            });

            for (const request of expiredRequests) {
                const plan = (request as any).plan as PartyPlan;
                if (!plan) {
                    await request.update({ status: PartyPlanRequestStatus.PAYMENT_FAILED });
                    continue;
                }

                const hostPaid = plan.hostPaymentStatus === 'paid';
                const joinerPaid = request.joinerPaymentStatus === 'paid';

                if (!hostPaid) {
                    // Host did not pay within their 30 min acceptance window
                    logger.info(`[Cron] Payment expired for plan ${plan.id}: host did not pay. Reopening plan.`);
                    try {
                        const { reopenPlan } = require('../controllers/partyPlanController');
                        await reopenPlan(plan, request.id, 'payment_failed');
                    } catch (reopenErr: any) {
                        // Fallback: legacy reset
                        logger.warn(`[Cron] reopenPlan failed for plan ${plan.id}, using legacy fallback:`, reopenErr.message);
                        await request.update({ status: PartyPlanRequestStatus.PAYMENT_FAILED });
                        await plan.update({ status: PartyPlanStatus.ACTIVE, isLive: plan.visibility !== 'private' });
                        await relistPartyPlanInSocket(plan.id);
                    }
                } else if (hostPaid && !joinerPaid) {
                    // Joiner did not pay within their 30 min window (starts after host paid)
                    logger.info(`[Cron] Payment expired for plan ${plan.id}: joiner (req ${request.id}) did not pay. Reopening plan.`);
                    try {
                        const { reopenPlan } = require('../controllers/partyPlanController');
                        await reopenPlan(plan, request.id, 'payment_failed');
                    } catch (reopenErr: any) {
                        // Fallback: legacy reset, host stays paid, plan goes live again
                        logger.warn(`[Cron] reopenPlan failed for plan ${plan.id}, using legacy fallback:`, reopenErr.message);
                        await request.update({ status: PartyPlanRequestStatus.PAYMENT_FAILED });
                        await plan.update({ status: PartyPlanStatus.ACTIVE, isLive: plan.visibility !== 'private' });
                        await relistPartyPlanInSocket(plan.id);

                        try {
                            const hostUser = await User.findByPk(plan.userId);
                            if (hostUser && hostUser.fcmToken) {
                                const { sendMulticastPushNotification } = require('../services/fcmService');
                                await sendMulticastPushNotification([hostUser.fcmToken], {
                                    title: '⚡ Plan Live Again',
                                    body: 'The joiner did not complete payment within 30 minutes. Your party plan is live again!',
                                    data: { type: 'party_plan_timeout_relist', partyPlanId: plan.id },
                                });
                            }
                        } catch (pushErr: any) {
                            logger.warn('Failed to send timeout relist push notification:', pushErr.message);
                        }
                    }
                } else {
                    // Fallback: both paid. Mark accepted and inactive.
                    await request.update({ 
                        status: PartyPlanRequestStatus.ACCEPTED,
                        joinerPaymentStatus: 'paid' as any
                    });
                    await plan.update({ 
                        hostPaymentStatus: 'paid' as any,
                        status: PartyPlanStatus.INACTIVE,
                        isLive: false
                    });
                    logger.info(`Match Success (cron fallback) for plan ${plan.id}.`);
                }
            }

            // 1.5 Check for expired or auto-approved cancellation requests
            try {
                const { checkExpiredOrAutoApprovedRequests } = require('../controllers/cancellationController');
                await checkExpiredOrAutoApprovedRequests();
            } catch (cancelCronErr: any) {
                logger.warn('[Cron] checkExpiredOrAutoApprovedRequests warning:', cancelCronErr.message);
            }

            // 1.6 Expire large/group party requests that were approved (or sent a
            // payment link) but never paid before the party's own scheduled start time.
            try {
                await expireUnpaidLargePartyRequests(now);
            } catch (expiryErr: any) {
                logger.warn('[Cron] expireUnpaidLargePartyRequests warning:', expiryErr.message);
            }


            // ── 2. Event Countdown Engine (24h, 3h, 1h, 30m Reminders) ─────────
            const next25h = new Date(now.getTime() + 25 * 60 * 60 * 1000);
            const next23h = new Date(now.getTime() + 23 * 60 * 60 * 1000);
            const upcoming24hPlans = await PartyPlan.findAll({
                where: {
                    status: { [Op.in]: ['active', 'inactive'] },
                    reminder24hSent: false,
                    planDateTime: { [Op.between]: [next23h, next25h] },
                },
                include: [{ model: User, as: 'creator' }]
            });

            for (const plan of upcoming24hPlans) {
                await plan.update({ reminder24hSent: true });
                const acceptedReq = await PartyPlanRequest.findOne({
                    where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                });
                if (acceptedReq) {
                    const host = await User.findByPk(plan.userId);
                    const joiner = await User.findByPk(acceptedReq.requesterId);
                    const { sendMulticastPushNotification } = require('../services/fcmService');
                    const NotificationService = (await import('../services/NotificationService')).NotificationService;

                    if (host?.fcmToken) {
                        await sendMulticastPushNotification([host.fcmToken], {
                            title: '📅 Event Reminder (24 Hours)',
                            body: `Your Party Plan with ${joiner?.firstName || 'your partner'} is tomorrow!`,
                            data: { type: 'reminder_24h', partyPlanId: plan.id }
                        });
                    }
                    if (joiner?.fcmToken) {
                        await sendMulticastPushNotification([joiner.fcmToken], {
                            title: '📅 Event Reminder (24 Hours)',
                            body: `Your Party Plan with ${host?.firstName || 'the host'} is tomorrow!`,
                            data: { type: 'reminder_24h', partyPlanId: plan.id }
                        });
                    }

                    await NotificationService.dispatch({
                        recipientUserId: plan.userId,
                        actorUserId: acceptedReq.requesterId,
                        eventType: 'reminder_24h',
                        category: 'events',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: '📅 Event Tomorrow',
                        body: `Your Party Plan with ${joiner?.firstName || 'your partner'} is tomorrow!`,
                    });
                }
            }

            // 3-Hour Reminder
            const next3hHalf = new Date(now.getTime() + 3.5 * 60 * 60 * 1000);
            const next2hHalf = new Date(now.getTime() + 2.5 * 60 * 60 * 1000);
            const upcoming3hPlans = await PartyPlan.findAll({
                where: {
                    status: { [Op.in]: ['active', 'inactive'] },
                    reminder3hSent: false,
                    planDateTime: { [Op.between]: [next2hHalf, next3hHalf] },
                }
            });

            for (const plan of upcoming3hPlans) {
                await plan.update({ reminder3hSent: true });
                const acceptedReq = await PartyPlanRequest.findOne({
                    where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                });
                if (acceptedReq) {
                    const host = await User.findByPk(plan.userId);
                    const joiner = await User.findByPk(acceptedReq.requesterId);
                    const { sendMulticastPushNotification } = require('../services/fcmService');
                    if (host?.fcmToken) {
                        await sendMulticastPushNotification([host.fcmToken], {
                            title: '⏳ Event Reminder (3 Hours)',
                            body: `Your Party Plan starts in 3 hours!`,
                            data: { type: 'reminder_3h', partyPlanId: plan.id }
                        });
                    }
                    if (joiner?.fcmToken) {
                        await sendMulticastPushNotification([joiner.fcmToken], {
                            title: '⏳ Event Reminder (3 Hours)',
                            body: `Your Party Plan starts in 3 hours!`,
                            data: { type: 'reminder_3h', partyPlanId: plan.id }
                        });
                    }
                }
            }

            // 2-Hour Reminder
            const next2h15m = new Date(now.getTime() + 2.25 * 60 * 60 * 1000);
            const next1h45m = new Date(now.getTime() + 1.75 * 60 * 60 * 1000);
            const upcoming2hPlans = await PartyPlan.findAll({
                where: {
                    status: { [Op.in]: ['active', 'inactive'] },
                    reminder2hSent: false,
                    planDateTime: { [Op.between]: [next1h45m, next2h15m] },
                }
            });

            for (const plan of upcoming2hPlans) {
                await plan.update({ reminder2hSent: true });
                const acceptedReq = await PartyPlanRequest.findOne({
                    where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                });
                if (acceptedReq) {
                    const host = await User.findByPk(plan.userId);
                    const joiner = await User.findByPk(acceptedReq.requesterId);
                    const { sendMulticastPushNotification } = require('../services/fcmService');
                    if (host?.fcmToken) {
                        await sendMulticastPushNotification([host.fcmToken], {
                            title: '⏳ Event Reminder (2 Hours)',
                            body: `Your Party Plan starts in 2 hours!`,
                            data: { type: 'reminder_2h', partyPlanId: plan.id }
                        });
                    }
                    if (joiner?.fcmToken) {
                        await sendMulticastPushNotification([joiner.fcmToken], {
                            title: '⏳ Event Reminder (2 Hours)',
                            body: `Your Party Plan starts in 2 hours!`,
                            data: { type: 'reminder_2h', partyPlanId: plan.id }
                        });
                    }
                }
            }

            // 1-Hour Reminder
            const next75m = new Date(now.getTime() + 75 * 60 * 1000);
            const next45m = new Date(now.getTime() + 45 * 60 * 1000);
            const upcoming1hPlans = await PartyPlan.findAll({
                where: {
                    status: { [Op.in]: ['active', 'inactive'] },
                    reminder1hSent: false,
                    planDateTime: { [Op.between]: [next45m, next75m] },
                },
                include: [{ model: Venue, as: 'venue', attributes: ['name', 'addressLine1'] }]
            });

            for (const plan of upcoming1hPlans) {
                await plan.update({
                    reminder1hSent: true,
                    lifecycleStatus: PartyPlanLifecycleStatus.ONE_HOUR_REMINDER,
                });
                const acceptedReq = await PartyPlanRequest.findOne({
                    where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                });
                if (acceptedReq) {
                    const host = await User.findByPk(plan.userId);
                    const joiner = await User.findByPk(acceptedReq.requesterId);
                    const venueName = (plan as any).venue?.name || 'Venue';
                    const { sendMulticastPushNotification } = require('../services/fcmService');
                    const NotificationService = (await import('../services/NotificationService')).NotificationService;

                    const hostMsg = `Hurry! Your Party Plan at ${venueName} starts in 1 hour.`;
                    const guestMsg = `Your Party Plan at ${venueName} starts in 1 hour.`;

                    if (host?.fcmToken) {
                        await sendMulticastPushNotification([host.fcmToken], {
                            title: '🚀 1 Hour Remaining!',
                            body: hostMsg,
                            data: { type: 'reminder_1h', partyPlanId: plan.id }
                        });
                    }
                    if (joiner?.fcmToken) {
                        await sendMulticastPushNotification([joiner.fcmToken], {
                            title: '🚀 1 Hour Remaining!',
                            body: guestMsg,
                            data: { type: 'reminder_1h', partyPlanId: plan.id }
                        });
                    }

                    await NotificationService.dispatch({
                        recipientUserId: plan.userId,
                        actorUserId: acceptedReq.requesterId,
                        eventType: 'reminder_1h',
                        category: 'events',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: '🚀 1 Hour Remaining!',
                        body: hostMsg,
                    });

                    await NotificationService.dispatch({
                        recipientUserId: acceptedReq.requesterId,
                        actorUserId: plan.userId,
                        eventType: 'reminder_1h',
                        category: 'events',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: '🚀 1 Hour Remaining!',
                        body: guestMsg,
                    });
                }
            }

            // 30-Minute Reminder
            const next40m = new Date(now.getTime() + 40 * 60 * 1000);
            const next15m = new Date(now.getTime() + 15 * 60 * 1000);
            const upcoming30mPlans = await PartyPlan.findAll({
                where: {
                    status: { [Op.in]: ['active', 'inactive'] },
                    reminder30mSent: false,
                    planDateTime: { [Op.between]: [next15m, next40m] },
                },
                include: [{ model: Venue, as: 'venue', attributes: ['name', 'addressLine1'] }]
            });

            for (const plan of upcoming30mPlans) {
                await plan.update({
                    reminder30mSent: true,
                    lifecycleStatus: PartyPlanLifecycleStatus.THIRTY_MIN_REMINDER,
                });
                const acceptedReq = await PartyPlanRequest.findOne({
                    where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                });
                if (acceptedReq) {
                    const host = await User.findByPk(plan.userId);
                    const joiner = await User.findByPk(acceptedReq.requesterId);
                    const venueName = (plan as any).venue?.name || 'Venue';
                    const mapsUrl = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(venueName)}`;
                    const { sendMulticastPushNotification } = require('../services/fcmService');
                    const NotificationService = (await import('../services/NotificationService')).NotificationService;
                    const msg = `Time to leave for ${venueName}! Event starts in 30 minutes.`;

                    if (host?.fcmToken) {
                        await sendMulticastPushNotification([host.fcmToken], {
                            title: '🕒 Time to leave!',
                            body: msg,
                            data: { type: 'reminder_30m', partyPlanId: plan.id, mapsUrl }
                        });
                    }
                    if (joiner?.fcmToken) {
                        await sendMulticastPushNotification([joiner.fcmToken], {
                            title: '🕒 Time to leave!',
                            body: msg,
                            data: { type: 'reminder_30m', partyPlanId: plan.id, mapsUrl }
                        });
                    }

                    await NotificationService.dispatch({
                        recipientUserId: plan.userId,
                        actorUserId: acceptedReq.requesterId,
                        eventType: 'reminder_30m',
                        category: 'events',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: '🕒 Time to leave!',
                        body: msg,
                    });

                    await NotificationService.dispatch({
                        recipientUserId: acceptedReq.requesterId,
                        actorUserId: plan.userId,
                        eventType: 'reminder_30m',
                        category: 'events',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: '🕒 Time to leave!',
                        body: msg,
                    });
                }
            }

            // ── 1B. 30-Minute Authoritative Venue Reach Confirmation ─────────────
            try {
                const reachWindowStart = new Date(now.getTime() + 15 * 60 * 1000);
                const reachWindowEnd = new Date(now.getTime() + 40 * 60 * 1000);
                const upcoming30mReachPlans = await PartyPlan.findAll({
                    where: {
                        status: PartyPlanStatus.ACTIVE,
                        reachConfirmation30mSent: false,
                        hostPaymentStatus: PartyPlanPaymentStatus.PAID,
                        planDateTime: { [Op.between]: [reachWindowStart, reachWindowEnd] },
                    },
                    include: [{ model: Venue, as: 'venue', attributes: ['name', 'addressLine1', 'area'] }]
                });

                for (const plan of upcoming30mReachPlans) {
                    if (plan.lifecycleStatus === PartyPlanLifecycleStatus.PLAN_COMPLETED || plan.status === 'cancelled') {
                        continue;
                    }

                    const acceptedReq = await PartyPlanRequest.findOne({
                        where: {
                            planId: plan.id,
                            status: { [Op.in]: [PartyPlanRequestStatus.ACCEPTED, 'confirmed', 'paid'] },
                            joinerPaymentStatus: { [Op.in]: [PartyPlanJoinerPaymentStatus.PAID, 'paid'] }
                        }
                    });

                    if (!acceptedReq) {
                        continue;
                    }

                    // Mark 30-min reach confirmation sent (Idempotent guard)
                    await plan.update({ reachConfirmation30mSent: true });

                    const host = await User.findByPk(plan.userId);
                    const joiner = await User.findByPk(acceptedReq.requesterId);
                    const venueName = (plan as any).venue?.name || 'the venue';

                    const hostName = `${host?.firstName || 'Host'} ${host?.lastName || ''}`.trim();
                    const hostPhoto = host?.profileImageUrl || null;
                    const joinerName = `${joiner?.firstName || 'Partner'} ${joiner?.lastName || ''}`.trim();
                    const joinerPhoto = joiner?.profileImageUrl || null;

                    const { sendMulticastPushNotification } = require('../services/fcmService');
                    const NotificationService = (await import('../services/NotificationService')).NotificationService;
                    const { io } = require('../server');

                    const eventKey = `PARTY_PLAN_VENUE_REACH_CONFIRMATION_${plan.id}`;
                    const scheduledTimeString = plan.planDateTime ? formatTime12Hour(plan.planDateTime) : '10:00 PM';

                    // Host Notification: "Your Party Plan with [Partner Name] starts in 30 minutes. Have you reached [Venue Name]?"
                    const hostNotifTitle = '📍 Venue Confirmation Required';
                    const hostNotifBody = `Your Party Plan with ${joinerName} starts in 30 minutes. Have you reached ${venueName}?`;

                    if (host?.fcmToken) {
                        await sendMulticastPushNotification([host.fcmToken], {
                            title: hostNotifTitle,
                            body: hostNotifBody,
                            data: {
                                type: 'party_plan_reach_prompt',
                                actionType: 'CONFIRM_VENUE_REACH',
                                partyPlanId: plan.id,
                                planId: plan.id,
                                eventKey,
                                stage: 'thirty_min_reach',
                                partnerName: joinerName,
                                partnerPhoto: joinerPhoto || '',
                                hostName,
                                hostPhoto: hostPhoto || '',
                                venueName,
                                partyTime: scheduledTimeString,
                                planDateTime: plan.planDateTime ? plan.planDateTime.toISOString() : '',
                                click_action: 'FLUTTER_NOTIFICATION_CLICK'
                            }
                        });
                    }

                    await NotificationService.dispatch({
                        recipientUserId: plan.userId,
                        actorUserId: acceptedReq.requesterId,
                        eventType: 'party_plan_reach_prompt',
                        category: 'events',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: hostNotifTitle,
                        body: hostNotifBody,
                        actionType: 'CONFIRM_VENUE_REACH',
                        metadata: {
                            partyPlanId: plan.id,
                            eventKey,
                            stage: 'thirty_min_reach',
                            isHost: true,
                            hostName,
                            hostPhoto,
                            partnerName: joinerName,
                            partnerPhoto: joinerPhoto,
                            venueName,
                            partyTime: scheduledTimeString,
                            planDateTime: plan.planDateTime,
                        },
                        idempotencyKey: `reach_30m_${plan.id}_host`
                    });

                    // Joiner Notification: "Your Party Plan with [Host Name] starts in 30 minutes. Have you reached [Venue Name]?"
                    const joinerNotifTitle = '📍 Venue Confirmation Required';
                    const joinerNotifBody = `Your Party Plan with ${hostName} starts in 30 minutes. Have you reached ${venueName}?`;

                    if (joiner?.fcmToken) {
                        await sendMulticastPushNotification([joiner.fcmToken], {
                            title: joinerNotifTitle,
                            body: joinerNotifBody,
                            data: {
                                type: 'party_plan_reach_prompt',
                                actionType: 'CONFIRM_VENUE_REACH',
                                partyPlanId: plan.id,
                                planId: plan.id,
                                eventKey,
                                stage: 'thirty_min_reach',
                                partnerName: hostName,
                                partnerPhoto: hostPhoto || '',
                                hostName,
                                hostPhoto: hostPhoto || '',
                                venueName,
                                partyTime: scheduledTimeString,
                                planDateTime: plan.planDateTime ? plan.planDateTime.toISOString() : '',
                                click_action: 'FLUTTER_NOTIFICATION_CLICK'
                            }
                        });
                    }

                    await NotificationService.dispatch({
                        recipientUserId: acceptedReq.requesterId,
                        actorUserId: plan.userId,
                        eventType: 'party_plan_reach_prompt',
                        category: 'events',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: joinerNotifTitle,
                        body: joinerNotifBody,
                        actionType: 'CONFIRM_VENUE_REACH',
                        metadata: {
                            partyPlanId: plan.id,
                            eventKey,
                            stage: 'thirty_min_reach',
                            isHost: false,
                            hostName,
                            hostPhoto,
                            partnerName: hostName,
                            partnerPhoto: hostPhoto,
                            venueName,
                            partyTime: scheduledTimeString,
                            planDateTime: plan.planDateTime,
                        },
                        idempotencyKey: `reach_30m_${plan.id}_joiner`
                    });

                    // Real-time Sockets for in-app popup and Live Feed synchronization
                    if (io) {
                        io.to(`user_${plan.userId}`).emit('party_plan_reach_prompt', {
                            planId: plan.id,
                            partyPlanId: plan.id,
                            eventKey,
                            stage: 'thirty_min_reach',
                            isHost: true,
                            hostName,
                            hostPhoto,
                            partnerName: joinerName,
                            partnerPhoto: joinerPhoto,
                            venueName,
                            partyTime: scheduledTimeString,
                            eventDateTime: plan.planDateTime,
                            planDateTime: plan.planDateTime,
                            planTitle: plan.message || 'Party Plan'
                        });

                        io.to(`user_${acceptedReq.requesterId}`).emit('party_plan_reach_prompt', {
                            planId: plan.id,
                            partyPlanId: plan.id,
                            eventKey,
                            stage: 'thirty_min_reach',
                            isHost: false,
                            hostName,
                            hostPhoto,
                            partnerName: hostName,
                            partnerPhoto: hostPhoto,
                            venueName,
                            partyTime: scheduledTimeString,
                            eventDateTime: plan.planDateTime,
                            planDateTime: plan.planDateTime,
                            planTitle: plan.message || 'Party Plan'
                        });

                        // Targeted user emits above (lines 708 + 725) already cover host and joiner
                        // No global live_feed broadcast needed — this is a private venue-approach prompt
                    }
                }
            } catch (reach30mErr: any) {
                logger.error('[Cron] 30m Venue Reach Confirmation error: ' + reach30mErr.message);
            }

            // ── 2. Party Plan Arrival Cadence Engine (T-20m, T-10m, T-5m, On-Time, T+5m, T+10m, T+30m, 5h Expiry) ──
            try {
                const sequelize = (await import('../config/database')).default;
                await sequelize.query(`
                    ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_20m_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_10m_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_5m_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_on_time_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_post_5m_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_post_10m_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_post_30m_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS expired_no_show_cancelled BOOLEAN DEFAULT FALSE;
                `).catch(() => {});

                const { sendMulticastPushNotification } = require('../services/fcmService');
                const NotificationService = (await import('../services/NotificationService')).NotificationService;
                const { io } = require('../server');

                const sendPartyArrivalPrompt = async (plan: any, acceptedReq: any, stepLabel: string) => {
                    const bothConfirmed = plan.hostArrivalConfirmed === true && acceptedReq?.guestArrivalConfirmed === true;
                    if (bothConfirmed || plan.status === 'cancelled' || plan.status === 'completed') {
                        return; // Stoppage rule: Do not send any arrival check notifications once both have confirmed or plan is settled
                    }

                    const host = await User.findByPk(plan.userId);
                    const joiner = await User.findByPk(acceptedReq.requesterId);
                    const venue = plan.venue || await (await import('../models/Venue')).default.findByPk(plan.venueId);
                    const venueName = venue?.name || 'the venue';

                    const hostName = `${host?.firstName || 'Host'} ${host?.lastName || ''}`.trim();
                    const hostPhoto = host?.profileImageUrl || null;
                    const joinerName = `${joiner?.firstName || 'Partner'} ${joiner?.lastName || ''}`.trim();
                    const joinerPhoto = joiner?.profileImageUrl || null;

                    const title = '📍 Has your partner reached?';
                    const body = `Your Party Plan at ${venueName} is starting! Please confirm if your partner has reached.`;

                    const recipients = [
                        { user: host, isHost: true, partnerId: acceptedReq.requesterId, partnerName: joinerName, partnerPhoto: joinerPhoto },
                        { user: joiner, isHost: false, partnerId: plan.userId, partnerName: hostName, partnerPhoto: hostPhoto }
                    ];

                    for (const r of recipients) {
                        if (!r.user) continue;
                        if (r.user.fcmToken) {
                            await sendMulticastPushNotification([r.user.fcmToken], {
                                title,
                                body,
                                data: {
                                    type: 'arrival_prompt',
                                    partyPlanId: plan.id,
                                    action: 'CONFIRM_ARRIVAL',
                                    partnerName: r.partnerName,
                                    partnerPhoto: r.partnerPhoto || '',
                                    venueName,
                                    eventDateTime: plan.planDateTime ? plan.planDateTime.toISOString() : ''
                                }
                            });
                        }

                        await NotificationService.dispatch({
                            recipientUserId: r.user.id,
                            actorUserId: r.partnerId,
                            eventType: 'arrival_prompt',
                            category: 'events',
                            entityType: 'party_plan',
                            entityId: plan.id,
                            title,
                            body,
                            actionType: 'CONFIRM_ARRIVAL',
                            metadata: {
                                partyPlanId: plan.id,
                                step: stepLabel,
                                isHost: r.isHost,
                                partnerName: r.partnerName,
                                partnerPhoto: r.partnerPhoto,
                                venueName,
                                eventDateTime: plan.planDateTime
                            }
                        });
                    }

                    if (io) {
                        io.to(`user_${plan.userId}`).emit('party_plan_arrival_prompt', {
                            planId: plan.id,
                            partyPlanId: plan.id,
                            step: stepLabel,
                            stage: 'final_check',
                            isHost: true,
                            hostName,
                            hostPhoto,
                            partnerName: joinerName,
                            partnerPhoto: joinerPhoto,
                            venueName,
                            eventDateTime: plan.planDateTime,
                            planDateTime: plan.planDateTime,
                            planTitle: plan.message || 'Party Plan'
                        });
                        io.to(`user_${acceptedReq.requesterId}`).emit('party_plan_arrival_prompt', {
                            planId: plan.id,
                            partyPlanId: plan.id,
                            step: stepLabel,
                            stage: 'final_check',
                            isHost: false,
                            hostName,
                            hostPhoto,
                            partnerName: hostName,
                            partnerPhoto: hostPhoto,
                            venueName,
                            eventDateTime: plan.planDateTime,
                            planDateTime: plan.planDateTime,
                            planTitle: plan.message || 'Party Plan'
                        });
                    }
                };

                // A. T - 20 Minutes Arrival Prompt
                const next25m = new Date(now.getTime() + 25 * 60 * 1000);
                const next16m = new Date(now.getTime() + 16 * 60 * 1000);
                const plans20m = await PartyPlan.findAll({
                    where: {
                        status: { [Op.in]: ['active', 'inactive'] },
                        reminder20mSent: false,
                        planDateTime: { [Op.between]: [next16m, next25m] },
                    }
                });
                for (const plan of plans20m) {
                    await plan.update({ reminder20mSent: true });
                    const acceptedReq = await PartyPlanRequest.findOne({
                        where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                    });
                    if (acceptedReq) {
                        await sendPartyArrivalPrompt(plan, acceptedReq, '20m_before');
                    }
                }

                // B. T - 10 Minutes Arrival Prompt
                const next15m = new Date(now.getTime() + 15 * 60 * 1000);
                const next7m = new Date(now.getTime() + 7 * 60 * 1000);
                const plans10m = await PartyPlan.findAll({
                    where: {
                        status: { [Op.in]: ['active', 'inactive'] },
                        reminder10mSent: false,
                        planDateTime: { [Op.between]: [next7m, next15m] },
                    }
                });
                for (const plan of plans10m) {
                    await plan.update({ reminder10mSent: true, lifecycleStatus: PartyPlanLifecycleStatus.TEN_MIN_CONFIRMATION });
                    const acceptedReq = await PartyPlanRequest.findOne({
                        where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                    });
                    if (acceptedReq) {
                        await sendPartyArrivalPrompt(plan, acceptedReq, '10m_before');
                    }
                }

                // C. T - 5 Minutes Arrival Prompt
                const next6m = new Date(now.getTime() + 6 * 60 * 1000);
                const next2m = new Date(now.getTime() + 2 * 60 * 1000);
                const plans5m = await PartyPlan.findAll({
                    where: {
                        status: { [Op.in]: ['active', 'inactive'] },
                        reminder5mSent: false,
                        planDateTime: { [Op.between]: [next2m, next6m] },
                    }
                });
                for (const plan of plans5m) {
                    await plan.update({ reminder5mSent: true });
                    const acceptedReq = await PartyPlanRequest.findOne({
                        where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                    });
                    if (acceptedReq) {
                        await sendPartyArrivalPrompt(plan, acceptedReq, '5m_before');
                    }
                }

                // D. On-Time Arrival Prompt (T = 0m)
                const onTimeStart = new Date(now.getTime() - 2 * 60 * 1000);
                const onTimeEnd = new Date(now.getTime() + 2 * 60 * 1000);
                const plansOnTime = await PartyPlan.findAll({
                    where: {
                        status: { [Op.in]: ['active', 'inactive'] },
                        reminderOnTimeSent: false,
                        planDateTime: { [Op.between]: [onTimeStart, onTimeEnd] },
                    }
                });
                for (const plan of plansOnTime) {
                    await plan.update({ reminderOnTimeSent: true, lifecycleStatus: PartyPlanLifecycleStatus.ARRIVAL_PENDING });
                    const acceptedReq = await PartyPlanRequest.findOne({
                        where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                    });
                    if (acceptedReq) {
                        await sendPartyArrivalPrompt(plan, acceptedReq, 'on_time');
                    }
                }

                // E. T + 5 Minutes Post-Start Follow-up
                const post5mStart = new Date(now.getTime() - 9 * 60 * 1000);
                const post5mEnd = new Date(now.getTime() - 3 * 60 * 1000);
                const plansPost5m = await PartyPlan.findAll({
                    where: {
                        status: { [Op.in]: ['active', 'inactive'] },
                        reminderPost5mSent: false,
                        planDateTime: { [Op.between]: [post5mStart, post5mEnd] },
                    }
                });
                for (const plan of plansPost5m) {
                    await plan.update({ reminderPost5mSent: true });
                    const acceptedReq = await PartyPlanRequest.findOne({
                        where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                    });
                    if (acceptedReq) {
                        await sendPartyArrivalPrompt(plan, acceptedReq, '5m_after');
                    }
                }

                // F. T + 10 Minutes Post-Start Follow-up
                const post10mStart = new Date(now.getTime() - 19 * 60 * 1000);
                const post10mEnd = new Date(now.getTime() - 9 * 60 * 1000);
                const plansPost10m = await PartyPlan.findAll({
                    where: {
                        status: { [Op.in]: ['active', 'inactive'] },
                        reminderPost10mSent: false,
                        planDateTime: { [Op.between]: [post10mStart, post10mEnd] },
                    }
                });
                for (const plan of plansPost10m) {
                    await plan.update({ reminderPost10mSent: true });
                    const acceptedReq = await PartyPlanRequest.findOne({
                        where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                    });
                    if (acceptedReq) {
                        await sendPartyArrivalPrompt(plan, acceptedReq, '10m_after');
                    }
                }

                // G. T + 30 Minutes Post-Start Follow-up
                const post30mStart = new Date(now.getTime() - 45 * 60 * 1000);
                const post30mEnd = new Date(now.getTime() - 20 * 60 * 1000);
                const plansPost30m = await PartyPlan.findAll({
                    where: {
                        status: { [Op.in]: ['active', 'inactive'] },
                        reminderPost30mSent: false,
                        planDateTime: { [Op.between]: [post30mStart, post30mEnd] },
                    }
                });
                for (const plan of plansPost30m) {
                    await plan.update({ reminderPost30mSent: true });
                    const acceptedReq = await PartyPlanRequest.findOne({
                        where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                    });
                    if (acceptedReq) {
                        await sendPartyArrivalPrompt(plan, acceptedReq, '30m_after');
                    }
                }

                // H. 5-Hour No-Action Cancellation & Forfeiture Check (T + 5 hours / 300 mins)
                const fiveHoursAgo = new Date(now.getTime() - 5 * 60 * 60 * 1000);
                const expiredUnconfirmedPlans = await PartyPlan.findAll({
                    where: {
                        status: { [Op.in]: ['active', 'inactive'] },
                        expiredNoShowCancelled: false,
                        planDateTime: { [Op.lte]: fiveHoursAgo },
                    }
                });

                for (const plan of expiredUnconfirmedPlans) {
                    const acceptedReq = await PartyPlanRequest.findOne({
                        where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                    });

                    const bothConfirmed = plan.hostArrivalConfirmed === true && acceptedReq?.guestArrivalConfirmed === true;
                    if (bothConfirmed) {
                        await plan.update({ expiredNoShowCancelled: true });
                        continue;
                    }

                    // Cancel plan, DO NOT refund deposit (forfeit deposit)
                    await plan.update({
                        status: PartyPlanStatus.CANCELLED,
                        lifecycleStatus: PartyPlanLifecycleStatus.EXPIRED,
                        attendanceDecision: 'expired',
                        reachRefundDecision: 'expired_no_refund',
                        reachVerificationStage: 'expired',
                        paymentStatus: 'Cancelled (Deposit Forfeited - No Confirmation within 8h)',
                        expiredNoShowCancelled: true,
                    });

                    if (acceptedReq) {
                        await acceptedReq.update({
                            status: PartyPlanRequestStatus.CANCELLED,
                            cancellationReason: 'No arrival confirmation within 5 hours. Deposit forfeited.',
                        });
                    }

                    // Release time lock
                    const { PlanEligibilityService } = await import('../services/PlanEligibilityService');
                    await PlanEligibilityService.releaseLock(plan.id);

                    const host = await User.findByPk(plan.userId);
                    const joiner = acceptedReq ? await User.findByPk(acceptedReq.requesterId) : null;
                    const venue = (plan as any).venue || await (await import('../models/Venue')).default.findByPk(plan.venueId);
                    const venueName = venue?.name || 'the venue';

                    const cancelTitle = '❌ Party Plan Cancelled (Deposit Forfeited)';
                    const cancelBody = `Your party plan at ${venueName} expired without arrival confirmation within 5 hours. As per policy, the commitment deposit has been forfeited.`;

                    const tokens = [host?.fcmToken, joiner?.fcmToken].filter(Boolean) as string[];
                    if (tokens.length > 0) {
                        await sendMulticastPushNotification(tokens, {
                            title: cancelTitle,
                            body: cancelBody,
                            data: { type: 'party_plan_expired_forfeited', partyPlanId: plan.id }
                        });
                    }

                    if (host) {
                        await NotificationService.dispatch({
                            recipientUserId: host.id,
                            eventType: 'party_cancelled',
                            category: 'events',
                            entityType: 'party_plan',
                            entityId: plan.id,
                            title: cancelTitle,
                            body: cancelBody,
                            metadata: { partyPlanId: plan.id, refundStatus: 'FORFEITED' }
                        });
                    }
                    if (joiner) {
                        await NotificationService.dispatch({
                            recipientUserId: joiner.id,
                            eventType: 'party_cancelled',
                            category: 'events',
                            entityType: 'party_plan',
                            entityId: plan.id,
                            title: cancelTitle,
                            body: cancelBody,
                            metadata: { partyPlanId: plan.id, refundStatus: 'FORFEITED' }
                        });
                    }

                    if (io) {
                        io.to(`user_${plan.userId}`).emit('party_plan_cancelled', { planId: plan.id, reason: 'Deposit forfeited after 5h no-confirmation' });
                        if (joiner) {
                            io.to(`user_${joiner.id}`).emit('party_plan_cancelled', { planId: plan.id, reason: 'Deposit forfeited after 5h no-confirmation' });
                        }
                    }
                }
            } catch (arrivalCronErr: any) {
                logger.error('[Cron] Party Plan Arrival Cadence Engine error: ' + arrivalCronErr.message);
            }

            // ── 2.5 Stranger Meet Automated Reminder Engine (2h, 1h, 30m) ─────
            try {
                const sequelize = (await import('../config/database')).default;
                await sequelize.query(`
                    ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS reminder_2h_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS reminder_1h_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS reminder_30m_sent BOOLEAN DEFAULT FALSE;
                `).catch(() => {});

                const StrangersMeetRequest = (await import('../models/StrangersMeetRequest')).default;
                const StrangersMeetStatus = (await import('../models/StrangersMeetRequest')).StrangersMeetStatus;
                const StrangersMeetPaymentStatus = (await import('../models/StrangersMeetRequest')).StrangersMeetPaymentStatus;
                const StrangersMeetJoiner = (await import('../models/StrangersMeetJoiner')).default;
                const { StrangersMeetService } = await import('../services/StrangersMeetService');
                const { sendMulticastPushNotification } = require('../services/fcmService');

                // 2 Hours Before Reminder
                const smNext2h5 = new Date(now.getTime() + 135 * 60 * 1000);
                const smNext2h15 = new Date(now.getTime() + 105 * 60 * 1000);
                const sm2hMeets = await StrangersMeetRequest.findAll({
                    where: {
                        status: StrangersMeetStatus.APPROVED,
                        paymentStatus: StrangersMeetPaymentStatus.PAID,
                        reminder2hSent: false,
                        eventDateTime: { [Op.between]: [smNext2h15, smNext2h5] }
                    }
                });

                for (const meet of sm2hMeets) {
                    await meet.update({ reminder2hSent: true });
                    const joiners = await StrangersMeetJoiner.findAll({
                        where: { strangersMeetRequestId: meet.id, paymentStatus: 'paid' }
                    });
                    const participantUserIds = Array.from(new Set([meet.userId, ...joiners.map(j => j.userId)]));
                    const users = await User.findAll({ where: { id: { [Op.in]: participantUserIds } }, attributes: ['id', 'fcmToken'] });
                    const fcmTokens = users.map(u => u.fcmToken).filter(Boolean) as string[];

                    if (fcmTokens.length > 0) {
                        await sendMulticastPushNotification(fcmTokens, {
                            title: '⏳ Stranger Meet Reminder (2 Hours)',
                            body: 'Your Stranger Meet starts in 2 hours.',
                            data: { type: 'sm_reminder_2h', strangersMeetId: meet.id }
                        });
                    }

                    for (const uId of participantUserIds) {
                        await StrangersMeetService.emitNotification({
                            recipientUserId: uId,
                            eventType: 'sm_reminder_2h',
                            title: '⏳ Stranger Meet Reminder (2 Hours)',
                            body: 'Your Stranger Meet starts in 2 hours.',
                            entityId: meet.id
                        });
                    }
                }

                // 1 Hour Before Reminder
                const smNext1h15 = new Date(now.getTime() + 75 * 60 * 1000);
                const smNext1h45 = new Date(now.getTime() + 45 * 60 * 1000);
                const sm1hMeets = await StrangersMeetRequest.findAll({
                    where: {
                        status: StrangersMeetStatus.APPROVED,
                        paymentStatus: StrangersMeetPaymentStatus.PAID,
                        reminder1hSent: false,
                        eventDateTime: { [Op.between]: [smNext1h45, smNext1h15] }
                    }
                });

                for (const meet of sm1hMeets) {
                    await meet.update({ reminder1hSent: true });
                    const joiners = await StrangersMeetJoiner.findAll({
                        where: { strangersMeetRequestId: meet.id, paymentStatus: 'paid' }
                    });
                    const participantUserIds = Array.from(new Set([meet.userId, ...joiners.map(j => j.userId)]));
                    const users = await User.findAll({ where: { id: { [Op.in]: participantUserIds } }, attributes: ['id', 'fcmToken'] });
                    const fcmTokens = users.map(u => u.fcmToken).filter(Boolean) as string[];

                    if (fcmTokens.length > 0) {
                        await sendMulticastPushNotification(fcmTokens, {
                            title: '⏳ Stranger Meet Reminder (1 Hour)',
                            body: 'Your Stranger Meet starts in 1 hour.',
                            data: { type: 'sm_reminder_1h', strangersMeetId: meet.id }
                        });
                    }

                    for (const uId of participantUserIds) {
                        await StrangersMeetService.emitNotification({
                            recipientUserId: uId,
                            eventType: 'sm_reminder_1h',
                            title: '⏳ Stranger Meet Reminder (1 Hour)',
                            body: 'Your Stranger Meet starts in 1 hour.',
                            entityId: meet.id
                        });
                    }
                }

                // 30 Minutes Before Departure Reminder
                const smNext35m = new Date(now.getTime() + 35 * 60 * 1000);
                const smNext25m = new Date(now.getTime() + 25 * 60 * 1000);
                const sm30mMeets = await StrangersMeetRequest.findAll({
                    where: {
                        status: StrangersMeetStatus.APPROVED,
                        paymentStatus: StrangersMeetPaymentStatus.PAID,
                        reminder30mSent: false,
                        eventDateTime: { [Op.between]: [smNext25m, smNext35m] }
                    }
                });

                for (const meet of sm30mMeets) {
                    await meet.update({ reminder30mSent: true });
                    const joiners = await StrangersMeetJoiner.findAll({
                        where: { strangersMeetRequestId: meet.id, paymentStatus: 'paid' }
                    });
                    const participantUserIds = Array.from(new Set([meet.userId, ...joiners.map(j => j.userId)]));
                    const users = await User.findAll({ where: { id: { [Op.in]: participantUserIds } }, attributes: ['id', 'fcmToken'] });
                    const fcmTokens = users.map(u => u.fcmToken).filter(Boolean) as string[];

                    if (fcmTokens.length > 0) {
                        await sendMulticastPushNotification(fcmTokens, {
                            title: '🚗 Time to Leave!',
                            body: 'It\'s time to leave for your Stranger Meet.',
                            data: { type: 'sm_reminder_30m', strangersMeetId: meet.id }
                        });
                    }

                    for (const uId of participantUserIds) {
                        await StrangersMeetService.emitNotification({
                            recipientUserId: uId,
                            eventType: 'sm_reminder_30m',
                            title: '🚗 Time to Leave!',
                            body: 'It\'s time to leave for your Stranger Meet.',
                            entityId: meet.id
                        });
                    }
                }
            } catch (smCronErr) {
                logger.error('[partyPlanCron] Stranger Meet reminder engine error:', smCronErr);
            }

            // ── 2.6 Group Party Automated Reminder Engine (2h, 1h, 30m) ─────
            try {
                const sequelize = (await import('../config/database')).default;
                await sequelize.query(`
                    ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS reminder_2h_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS reminder_1h_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS reminder_30m_sent BOOLEAN DEFAULT FALSE;
                `).catch(() => {});

                const GroupParty = (await import('../models/GroupParty')).default;
                const GroupPartyStatus = (await import('../models/GroupParty')).GroupPartyStatus;
                const GroupPartyPaymentStatus = (await import('../models/GroupParty')).GroupPartyPaymentStatus;
                const { GroupPartyService } = await import('../services/GroupPartyService');
                const { sendPushNotification } = require('../services/fcmService');

                // ── 2.6 Group Party Automated Reminder Engine (2h, 1h, 30m) ─────
                const gpParties = await GroupParty.findAll({
                    where: {
                        status: GroupPartyStatus.CONFIRMED,
                        paymentStatus: GroupPartyPaymentStatus.PAID,
                        [Op.or]: [
                            { reminder2hSent: false },
                            { reminder1hSent: false },
                            { reminder30mSent: false }
                        ]
                    }
                });

                for (const party of gpParties) {
                    const partyDateTime = parseEventDateTimeToUTC(party.partyDate, party.startTime || (party as any).partyTime);
                    if (!partyDateTime || isNaN(partyDateTime.getTime())) continue;
                    const diffMinutes = (partyDateTime.getTime() - now.getTime()) / (60 * 1000);

                    // 2 Hours Before Reminder
                    if (diffMinutes <= 135 && diffMinutes >= 105 && !party.reminder2hSent) {
                        await party.update({ reminder2hSent: true });
                        const user = await User.findByPk(party.userId, { attributes: ['id', 'fcmToken'] });
                        if (user && user.fcmToken) {
                            await sendPushNotification(user.fcmToken, {
                                title: '⏳ Group Party Reminder (2 Hours)',
                                body: 'Your Group Party starts in 2 hours.',
                                data: { type: 'gp_reminder_2h', partyId: party.id }
                            }).catch(() => {});
                        }
                        const enrichedCard = await GroupPartyService.enrichGroupPartyNotificationCard(party.id, party.userId);
                        const { io } = require('../server');
                        if (io) {
                            io.to(`user_${party.userId}`).emit('notification_updated', enrichedCard);
                            io.to(`user_${party.userId}`).emit('group_party_status_update', { partyId: party.id, eventType: 'gp_reminder_2h' });
                        }
                    }

                    // 1 Hour Before Reminder
                    if (diffMinutes <= 75 && diffMinutes >= 45 && !party.reminder1hSent) {
                        await party.update({ reminder1hSent: true });
                        const user = await User.findByPk(party.userId, { attributes: ['id', 'fcmToken'] });
                        if (user && user.fcmToken) {
                            await sendPushNotification(user.fcmToken, {
                                title: '⏳ Group Party Reminder (1 Hour)',
                                body: 'Your Group Party starts in 1 hour.',
                                data: { type: 'gp_reminder_1h', partyId: party.id }
                            }).catch(() => {});
                        }
                        const enrichedCard = await GroupPartyService.enrichGroupPartyNotificationCard(party.id, party.userId);
                        const { io } = require('../server');
                        if (io) {
                            io.to(`user_${party.userId}`).emit('notification_updated', enrichedCard);
                            io.to(`user_${party.userId}`).emit('group_party_status_update', { partyId: party.id, eventType: 'gp_reminder_1h' });
                        }
                    }

                    // 30 Minutes Before Departure Reminder
                    if (diffMinutes <= 35 && diffMinutes >= 15 && !party.reminder30mSent) {
                        await party.update({ reminder30mSent: true });
                        const user = await User.findByPk(party.userId, { attributes: ['id', 'fcmToken'] });
                        if (user && user.fcmToken) {
                            await sendPushNotification(user.fcmToken, {
                                title: '🚗 Time to Leave!',
                                body: "It's time to leave for your Group Party.",
                                data: { type: 'gp_reminder_30m', partyId: party.id }
                            }).catch(() => {});
                        }
                        const enrichedCard = await GroupPartyService.enrichGroupPartyNotificationCard(party.id, party.userId);
                        const { io } = require('../server');
                        if (io) {
                            io.to(`user_${party.userId}`).emit('notification_updated', enrichedCard);
                            io.to(`user_${party.userId}`).emit('group_party_status_update', { partyId: party.id, eventType: 'gp_reminder_30m' });
                        }
                    }
                }
            } catch (gpCronErr) {
                logger.error('[partyPlanCron] Group Party reminder engine error:', gpCronErr);
            }

            // ── 2.7 Large Party Automated Reminder Engine (2h, 1h, 30m) ─────
            try {
                const sequelize = (await import('../config/database')).default;
                await sequelize.query(`
                    ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_2h_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_1h_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_30m_sent BOOLEAN DEFAULT FALSE;
                `).catch(() => {});

                const Booking = (await import('../models/Booking')).default;
                const BookingStatus = (await import('../models/Booking')).BookingStatus;
                const PaymentStatus = (await import('../models/Booking')).PaymentStatus;
                const { GroupPartyService } = await import('../services/GroupPartyService');
                const { sendPushNotification } = require('../services/fcmService');

                const lpBookings = await Booking.findAll({
                    where: {
                        isLargePartyRequest: true,
                        status: BookingStatus.CONFIRMED,
                        paymentStatus: PaymentStatus.PAID,
                        [Op.or]: [
                            { reminder2hSent: false },
                            { reminder1hSent: false },
                            { reminder30mSent: false }
                        ]
                    }
                });

                for (const booking of lpBookings) {
                    const bookingDateTime = parseEventDateTimeToUTC(booking.bookingDate, booking.startTime || (booking as any).bookingTime);
                    if (!bookingDateTime || isNaN(bookingDateTime.getTime())) continue;
                    const diffMinutes = (bookingDateTime.getTime() - now.getTime()) / (60 * 1000);

                    // 2 Hours Before Reminder
                    if (diffMinutes <= 135 && diffMinutes >= 105 && !booking.reminder2hSent) {
                        await booking.update({ reminder2hSent: true });
                        const user = await User.findByPk(booking.userId, { attributes: ['id', 'fcmToken'] });
                        if (user && user.fcmToken) {
                            await sendPushNotification(user.fcmToken, {
                                title: '⏳ Large Party Reminder (2 Hours)',
                                body: 'Your Large Party starts in 2 hours.',
                                data: { type: 'lp_reminder_2h', bookingId: booking.id }
                            }).catch(() => {});
                        }
                        const enrichedCard = await GroupPartyService.enrichLargePartyNotificationCard(booking.id, booking.userId);
                        const { io } = require('../server');
                        if (io) {
                            io.to(`user_${booking.userId}`).emit('notification_updated', enrichedCard);
                            io.to(`user_${booking.userId}`).emit('large_party_status_update', { bookingId: booking.id, eventType: 'lp_reminder_2h' });
                        }
                    }

                    // 1 Hour Before Reminder
                    if (diffMinutes <= 75 && diffMinutes >= 45 && !booking.reminder1hSent) {
                        await booking.update({ reminder1hSent: true });
                        const user = await User.findByPk(booking.userId, { attributes: ['id', 'fcmToken'] });
                        if (user && user.fcmToken) {
                            await sendPushNotification(user.fcmToken, {
                                title: '⏳ Large Party Reminder (1 Hour)',
                                body: 'Your Large Party starts in 1 hour.',
                                data: { type: 'lp_reminder_1h', bookingId: booking.id }
                            }).catch(() => {});
                        }
                        const enrichedCard = await GroupPartyService.enrichLargePartyNotificationCard(booking.id, booking.userId);
                        const { io } = require('../server');
                        if (io) {
                            io.to(`user_${booking.userId}`).emit('notification_updated', enrichedCard);
                            io.to(`user_${booking.userId}`).emit('large_party_status_update', { bookingId: booking.id, eventType: 'lp_reminder_1h' });
                        }
                    }

                    // 30 Minutes Before Departure Reminder
                    if (diffMinutes <= 35 && diffMinutes >= 15 && !booking.reminder30mSent) {
                        await booking.update({ reminder30mSent: true });
                        const user = await User.findByPk(booking.userId, { attributes: ['id', 'fcmToken'] });
                        if (user && user.fcmToken) {
                            await sendPushNotification(user.fcmToken, {
                                title: '🚗 Time to Leave!',
                                body: "It's time to leave for your Large Party.",
                                data: { type: 'lp_reminder_30m', bookingId: booking.id }
                            }).catch(() => {});
                        }
                        const enrichedCard = await GroupPartyService.enrichLargePartyNotificationCard(booking.id, booking.userId);
                        const { io } = require('../server');
                        if (io) {
                            io.to(`user_${booking.userId}`).emit('notification_updated', enrichedCard);
                            io.to(`user_${booking.userId}`).emit('large_party_status_update', { bookingId: booking.id, eventType: 'lp_reminder_30m' });
                        }
                    }
                }
            } catch (lpCronErr) {
                logger.error('[partyPlanCron] Large Party reminder engine error:', lpCronErr);
            }

            // ── 2.8 Upcoming Nights Automated Reminder Engine (2h, 1h, 30m) ─────
            try {
                const sequelize = (await import('../config/database')).default;
                await sequelize.query(`
                    ALTER TABLE night_partner_matches ADD COLUMN IF NOT EXISTS reminder_2h_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE night_partner_matches ADD COLUMN IF NOT EXISTS reminder_1h_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE night_partner_matches ADD COLUMN IF NOT EXISTS reminder_30m_sent BOOLEAN DEFAULT FALSE;
                `).catch(() => {});

                const NightPartnerMatch = (await import('../models/NightPartnerMatch')).default;
                const NightPartnerMatchStatus = (await import('../models/NightPartnerMatch')).NightPartnerMatchStatus;
                const { NightPartnerService } = await import('../services/NightPartnerService');
                const { sendPushNotification } = require('../services/fcmService');

                const unMatches = await NightPartnerMatch.findAll({
                    where: {
                        status: NightPartnerMatchStatus.CONFIRMED,
                        [Op.or]: [
                            { reminder2hSent: false },
                            { reminder1hSent: false },
                            { reminder30mSent: false }
                        ]
                    }
                });

                for (const match of unMatches) {
                    const matchDateTime = parseEventDateTimeToUTC(match.eventDate, match.eventTime);
                    if (!matchDateTime || isNaN(matchDateTime.getTime())) continue;
                    const diffMinutes = (matchDateTime.getTime() - now.getTime()) / (60 * 1000);

                    // 2 Hours Before Reminder
                    if (diffMinutes <= 135 && diffMinutes >= 105 && !match.reminder2hSent) {
                        await match.update({ reminder2hSent: true });
                        const participants = [match.hostId, match.partnerId];
                        for (const pId of participants) {
                            const user = await User.findByPk(pId, { attributes: ['id', 'fcmToken'] });
                            if (user && user.fcmToken) {
                                await sendPushNotification(user.fcmToken, {
                                    title: '⏳ Upcoming Night Reminder (2 Hours)',
                                    body: 'Your Upcoming Night starts in 2 hours.',
                                    data: { type: 'un_reminder_2h', matchId: match.id }
                                }).catch(() => {});
                            }
                            const enrichedCard = await NightPartnerService.enrichUpcomingNightNotificationCard(match.id, pId);
                            const { io } = require('../server');
                            if (io) {
                                io.to(`user_${pId}`).emit('notification_updated', enrichedCard);
                                io.to(`user_${pId}`).emit('upcoming_night_status_update', { matchId: match.id, eventType: 'un_reminder_2h' });
                            }
                        }
                    }

                    // 1 Hour Before Reminder
                    if (diffMinutes <= 75 && diffMinutes >= 45 && !match.reminder1hSent) {
                        await match.update({ reminder1hSent: true });
                        const participants = [match.hostId, match.partnerId];
                        for (const pId of participants) {
                            const user = await User.findByPk(pId, { attributes: ['id', 'fcmToken'] });
                            if (user && user.fcmToken) {
                                await sendPushNotification(user.fcmToken, {
                                    title: '⏳ Upcoming Night Reminder (1 Hour)',
                                    body: 'Your Upcoming Night starts in 1 hour.',
                                    data: { type: 'un_reminder_1h', matchId: match.id }
                                }).catch(() => {});
                            }
                            const enrichedCard = await NightPartnerService.enrichUpcomingNightNotificationCard(match.id, pId);
                            const { io } = require('../server');
                            if (io) {
                                io.to(`user_${pId}`).emit('notification_updated', enrichedCard);
                                io.to(`user_${pId}`).emit('upcoming_night_status_update', { matchId: match.id, eventType: 'un_reminder_1h' });
                            }
                        }
                    }

                    // 30 Minutes Before Departure Reminder
                    if (diffMinutes <= 35 && diffMinutes >= 15 && !match.reminder30mSent) {
                        await match.update({ reminder30mSent: true });
                        const participants = [match.hostId, match.partnerId];
                        for (const pId of participants) {
                            const user = await User.findByPk(pId, { attributes: ['id', 'fcmToken'] });
                            if (user && user.fcmToken) {
                                await sendPushNotification(user.fcmToken, {
                                    title: '🚗 Time to Leave!',
                                    body: "It's time to leave for your Upcoming Night.",
                                    data: { type: 'un_reminder_30m', matchId: match.id }
                                }).catch(() => {});
                            }
                            const enrichedCard = await NightPartnerService.enrichUpcomingNightNotificationCard(match.id, pId);
                            const { io } = require('../server');
                            if (io) {
                                io.to(`user_${pId}`).emit('notification_updated', enrichedCard);
                                io.to(`user_${pId}`).emit('upcoming_night_status_update', { matchId: match.id, eventType: 'un_reminder_30m' });
                            }
                        }
                    }
                }
            } catch (unCronErr) {
                logger.error('[partyPlanCron] Upcoming Night reminder engine error:', unCronErr);
            }

            // ── 2.9 Venue Booking Automated Reminder Engine (2h, 1h, 30m) ─────
            try {
                const Booking = (await import('../models/Booking')).default;
                const BookingStatus = (await import('../models/Booking')).BookingStatus;
                const PaymentStatus = (await import('../models/Booking')).PaymentStatus;
                const { VenueBookingService } = await import('../services/VenueBookingService');
                const { sendPushNotification } = require('../services/fcmService');

                const vbBookings = await Booking.findAll({
                    where: {
                        isGroupBooking: false,
                        isLargePartyRequest: false,
                        status: BookingStatus.CONFIRMED,
                        paymentStatus: PaymentStatus.PAID,
                        [Op.or]: [
                            { reminder2hSent: false },
                            { reminder1hSent: false },
                            { reminder30mSent: false }
                        ]
                    }
                });

                for (const booking of vbBookings) {
                    const bookingDateTime = parseEventDateTimeToUTC(booking.bookingDate, booking.startTime || (booking as any).bookingTime);
                    if (!bookingDateTime || isNaN(bookingDateTime.getTime())) continue;
                    const diffMinutes = (bookingDateTime.getTime() - now.getTime()) / (60 * 1000);

                    // 2 Hours Before Reminder
                    if (diffMinutes <= 135 && diffMinutes >= 105 && !booking.reminder2hSent) {
                        await booking.update({ reminder2hSent: true });
                        const user = await User.findByPk(booking.userId, { attributes: ['id', 'fcmToken'] });
                        if (user && user.fcmToken) {
                            await sendPushNotification(user.fcmToken, {
                                title: '⏳ Venue Booking Reminder (2 Hours)',
                                body: 'Your Venue Booking starts in 2 hours.',
                                data: { type: 'vb_reminder_2h', bookingId: booking.id }
                            }).catch(() => {});
                        }
                        const enrichedCard = await VenueBookingService.enrichVenueBookingNotificationCard(booking.id, booking.userId);
                        const { io } = require('../server');
                        if (io) {
                            io.to(`user_${booking.userId}`).emit('notification_updated', enrichedCard);
                            io.to(`user_${booking.userId}`).emit('venue_booking_status_update', { bookingId: booking.id, eventType: 'vb_reminder_2h' });
                        }
                    }

                    // 1 Hour Before Reminder
                    if (diffMinutes <= 75 && diffMinutes >= 45 && !booking.reminder1hSent) {
                        await booking.update({ reminder1hSent: true });
                        const user = await User.findByPk(booking.userId, { attributes: ['id', 'fcmToken'] });
                        if (user && user.fcmToken) {
                            await sendPushNotification(user.fcmToken, {
                                title: '⏳ Venue Booking Reminder (1 Hour)',
                                body: 'Your Venue Booking starts in 1 hour.',
                                data: { type: 'vb_reminder_1h', bookingId: booking.id }
                            }).catch(() => {});
                        }
                        const enrichedCard = await VenueBookingService.enrichVenueBookingNotificationCard(booking.id, booking.userId);
                        const { io } = require('../server');
                        if (io) {
                            io.to(`user_${booking.userId}`).emit('notification_updated', enrichedCard);
                            io.to(`user_${booking.userId}`).emit('venue_booking_status_update', { bookingId: booking.id, eventType: 'vb_reminder_1h' });
                        }
                    }

                    // 30 Minutes Before Departure Reminder
                    if (diffMinutes <= 35 && diffMinutes >= 15 && !booking.reminder30mSent) {
                        await booking.update({ reminder30mSent: true });
                        const user = await User.findByPk(booking.userId, { attributes: ['id', 'fcmToken'] });
                        if (user && user.fcmToken) {
                            await sendPushNotification(user.fcmToken, {
                                title: '🚗 Time to Leave!',
                                body: "It's time to leave for your Venue Booking.",
                                data: { type: 'vb_reminder_30m', bookingId: booking.id }
                            }).catch(() => {});
                        }
                        const enrichedCard = await VenueBookingService.enrichVenueBookingNotificationCard(booking.id, booking.userId);
                        const { io } = require('../server');
                        if (io) {
                            io.to(`user_${booking.userId}`).emit('notification_updated', enrichedCard);
                            io.to(`user_${booking.userId}`).emit('venue_booking_status_update', { bookingId: booking.id, eventType: 'vb_reminder_30m' });
                        }
                    }
                }
            } catch (vbCronErr) {
                logger.error('[partyPlanCron] Venue Booking reminder engine error:', vbCronErr);
            }

            // ── 3. Process Completed Plans & Execute 4-Case Refund Engine ─────
            const candidatePlans = await PartyPlan.findAll({
                where: {
                    status: { [Op.in]: ['active', 'inactive'] },
                    lifecycleStatus: { [Op.ne]: PartyPlanLifecycleStatus.PLAN_COMPLETED },
                    hostPaymentStatus: { [Op.in]: [PartyPlanPaymentStatus.PAID, 'paid'] },
                    planDateTime: { [Op.lt]: now }
                }
            });

            const { ReliabilityService, ReliabilityAction } = await import('../services/reliabilityService');
            const { WalletService } = await import('../services/walletService');

            for (const plan of candidatePlans) {
                const acceptedReq = await PartyPlanRequest.findOne({
                    where: {
                        planId: plan.id,
                        status: PartyPlanRequestStatus.ACCEPTED,
                        joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                    }
                });

                if (!acceptedReq) {
                    await plan.update({
                        status: PartyPlanStatus.INACTIVE,
                        lifecycleStatus: PartyPlanLifecycleStatus.PLAN_COMPLETED
                    });
                    continue;
                }

                const hostHasAnswered = plan.hostArrivalTime !== null || plan.hostArrivalConfirmed !== null;
                const guestHasAnswered = acceptedReq.guestArrivalTime !== null || acceptedReq.guestArrivalConfirmed !== null;
                const bothAnswered = hostHasAnswered && guestHasAnswered;

                const eventTime = plan.planDateTime ? new Date(plan.planDateTime).getTime() : 0;
                const isPast24hDeadline = eventTime > 0 && now.getTime() >= eventTime + 24 * 60 * 60 * 1000;

                // If neither/both haven't answered and 24h deadline hasn't elapsed, leave the confirmation window open
                if (!bothAnswered && !isPast24hDeadline) {
                    continue;
                }

                const hostYes = Boolean(plan.hostArrivalConfirmed || plan.hostLatLangCheckIn);
                const guestYes = Boolean(acceptedReq.guestArrivalConfirmed || acceptedReq.latLangCheckIn);

                const hostUser = await User.findByPk(plan.userId);
                const guestUser = await User.findByPk(acceptedReq.requesterId);

                const hostDeposit = Number(plan.depositAmount || 99.00);
                const guestDeposit = plan.paymentType === 'self_pay' ? 0.00 : 99.00;

                // ── CASE 1: Host YES, Guest YES ────────────────────────────────
                if (hostYes && guestYes) {
                    logger.info(`[RefundEngine Case 1] Both Host and Guest confirmed arrival for plan ${plan.id}`);

                    if (hostUser) {
                        await WalletService.creditRefund({
                            userId: hostUser.id,
                            amount: hostDeposit,
                            referenceId: `PARTY_PLAN:${plan.id}:ARRIVAL_REFUND:${hostUser.id}`,
                            reason: 'Party Plan arrival confirmed — host deposit refund',
                            partyPlanId: plan.id,
                        });
                        await plan.update({ hostPaymentStatus: PartyPlanPaymentStatus.REFUNDED });
                        await ReliabilityService.updateScore({
                            userId: hostUser.id,
                            action: ReliabilityAction.SUCCESSFUL_ATTENDANCE,
                            partyPlanId: plan.id,
                        });
                    }

                    if (guestUser && guestDeposit > 0) {
                        await WalletService.creditRefund({
                            userId: guestUser.id,
                            amount: guestDeposit,
                            referenceId: `PARTY_PLAN:${plan.id}:ARRIVAL_REFUND:${guestUser.id}`,
                            reason: 'Party Plan arrival confirmed — guest deposit refund',
                            partyPlanId: plan.id,
                        });
                        await acceptedReq.update({ joinerPaymentStatus: PartyPlanJoinerPaymentStatus.REFUNDED });
                    }

                    if (guestUser) {
                        await ReliabilityService.updateScore({
                            userId: guestUser.id,
                            action: ReliabilityAction.SUCCESSFUL_ATTENDANCE,
                            partyPlanId: plan.id,
                        });
                    }

                    await plan.update({
                        status: PartyPlanStatus.INACTIVE,
                        lifecycleStatus: PartyPlanLifecycleStatus.PLAN_COMPLETED,
                        paymentStatus: 'Completed (Both Refunded)'
                    });
                }
                // ── CASE 2: Host YES, Guest NO (or Guest Unresponsive past 24h) ──
                else if (hostYes && !guestYes) {
                    logger.info(`[RefundEngine Case 2] Host YES, Guest NO for plan ${plan.id}`);

                    if (hostUser) {
                        await WalletService.creditRefund({
                            userId: hostUser.id,
                            amount: hostDeposit,
                            referenceId: `PARTY_PLAN:${plan.id}:ARRIVAL_REFUND:${hostUser.id}`,
                            reason: 'Party Plan arrival confirmed — host deposit refund',
                            partyPlanId: plan.id,
                        });
                        await plan.update({ hostPaymentStatus: PartyPlanPaymentStatus.REFUNDED });
                        await ReliabilityService.updateScore({
                            userId: hostUser.id,
                            action: ReliabilityAction.SUCCESSFUL_ATTENDANCE,
                            partyPlanId: plan.id,
                        });
                    }

                    if (guestUser) {
                        await ReliabilityService.updateScore({
                            userId: guestUser.id,
                            action: ReliabilityAction.NO_SHOW,
                            partyPlanId: plan.id,
                        });
                    }

                    await plan.update({
                        status: PartyPlanStatus.INACTIVE,
                        lifecycleStatus: PartyPlanLifecycleStatus.PLAN_COMPLETED,
                        paymentStatus: 'Completed (Host Refunded, Guest No-Show)'
                    });
                }
                // ── CASE 3: Host NO, Guest YES (or Host Unresponsive past 24h) ──
                else if (!hostYes && guestYes) {
                    logger.info(`[RefundEngine Case 3] Host NO, Guest YES for plan ${plan.id}`);

                    if (guestUser && guestDeposit > 0) {
                        await WalletService.creditRefund({
                            userId: guestUser.id,
                            amount: guestDeposit,
                            referenceId: `PARTY_PLAN:${plan.id}:ARRIVAL_REFUND:${guestUser.id}`,
                            reason: 'Party Plan arrival confirmed — guest deposit refund',
                            partyPlanId: plan.id,
                        });
                        await acceptedReq.update({ joinerPaymentStatus: PartyPlanJoinerPaymentStatus.REFUNDED });
                    }

                    if (guestUser) {
                        await ReliabilityService.updateScore({
                            userId: guestUser.id,
                            action: ReliabilityAction.SUCCESSFUL_ATTENDANCE,
                            partyPlanId: plan.id,
                        });
                    }

                    if (hostUser) {
                        await ReliabilityService.updateScore({
                            userId: hostUser.id,
                            action: ReliabilityAction.NO_SHOW,
                            partyPlanId: plan.id,
                        });
                    }

                    await plan.update({
                        status: PartyPlanStatus.INACTIVE,
                        lifecycleStatus: PartyPlanLifecycleStatus.PLAN_COMPLETED,
                        paymentStatus: 'Completed (Guest Refunded, Host No-Show)'
                    });
                }
                // ── CASE 4 & 5: Host NO, Guest NO (or 24h Deadline Passed - NO REFUND) ──
                else {
                    logger.info(`[RefundEngine Case 4/5] Both NO / Unresolved 24h Deadline for plan ${plan.id}. No refund issued.`);

                    if (hostUser) {
                        await ReliabilityService.updateScore({
                            userId: hostUser.id,
                            action: ReliabilityAction.NO_SHOW,
                            partyPlanId: plan.id,
                        });
                    }

                    if (guestUser) {
                        await ReliabilityService.updateScore({
                            userId: guestUser.id,
                            action: ReliabilityAction.NO_SHOW,
                            partyPlanId: plan.id,
                        });
                    }

                    await plan.update({
                        status: PartyPlanStatus.INACTIVE,
                        lifecycleStatus: PartyPlanLifecycleStatus.PLAN_COMPLETED,
                        paymentStatus: 'Closed (Unresolved / 24h Deadline Passed)'
                    });
                }
            }

            // 3. Chat subscriptions are permanently free & unlimited (no expiration)

            // 4. Check for user subscription expiration and expiration warnings (24h/72h alert)
            const activeSubscriptions = await UserSubscription.findAll({
                where: {
                    status: SubscriptionStatus.ACTIVE,
                },
                include: [{ model: SubscriptionPackage, as: 'package' }]
            });

            const in72Hours = new Date(now.getTime() + 72 * 60 * 60 * 1000);

            for (const sub of activeSubscriptions) {
                const endDate = new Date(sub.endDate);
                const pkg = (sub as any).package;

                // Skip lifetime / free-tier stub records
                if (!pkg || pkg.tier === PackageTier.FREE || endDate.getFullYear() >= 2050) {
                    continue;
                }

                const pkgName = pkg?.name || 'VIP Package';

                if (endDate <= now) {
                    // Plan Has Expired
                    await sub.update({ status: SubscriptionStatus.EXPIRED });
                    logger.info(`Subscription ${sub.id} for user ${sub.userId} marked as EXPIRED.`);

                    // Push Notification & in-app record to user
                    try {
                        const NotificationModel = (await import('../models/Notification')).default;
                        await NotificationModel.create({
                            recipientUserId: sub.userId,
                            eventType: 'SUBSCRIPTION_EXPIRED',
                            category: 'system' as any,
                            title: '⚡ VIP Plan Expired',
                            body: `Your ${pkgName} subscription has expired. Upgrade your plan to continue enjoying exclusive features!`,
                            actionType: 'open_vip_upgrade',
                            deepLink: '/vip-membership',
                            isRead: false,
                            priority: 'HIGH' as any,
                            idempotencyKey: `sub_expired_${sub.id}`,
                        });

                        const user = await User.findByPk(sub.userId);
                        if (user && user.fcmToken) {
                            const { sendMulticastPushNotification } = require('../services/fcmService');
                            await sendMulticastPushNotification([user.fcmToken], {
                                title: '⚡ VIP Plan Expired',
                                body: `Your ${pkgName} subscription has expired. Upgrade your plan to continue enjoying exclusive features!`,
                                data: {
                                    type: 'subscription_expired',
                                    subscriptionId: sub.id,
                                },
                            });
                        }

                        // Socket notification
                        const { io } = require('../server');
                        io.to(`user_${sub.userId}`).emit('subscription_expired', {
                            subscriptionId: sub.id,
                            userId: sub.userId,
                            message: `Your ${pkgName} subscription has expired.`,
                        });
                    } catch (pushErr: any) {
                        logger.warn(`Failed to send subscription expiration push/socket for user ${sub.userId}:`, pushErr.message);
                    }
                } else if (endDate <= in72Hours) {
                    // Plan is expiring within 72 hours - send warning if not already sent
                    if (!sub.expirationAlertSent) {
                        try {
                            const daysRemaining = Math.max(1, Math.ceil((endDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)));
                            const NotificationModel = (await import('../models/Notification')).default;
                            await NotificationModel.create({
                                recipientUserId: sub.userId,
                                eventType: 'SUBSCRIPTION_EXPIRING_SOON',
                                category: 'system' as any,
                                title: '⏳ VIP Plan Expiring Soon',
                                body: `Your ${pkgName} subscription will expire in ${daysRemaining} day${daysRemaining > 1 ? 's' : ''}! Renew or upgrade now to retain all your VIP benefits.`,
                                actionType: 'open_vip_upgrade',
                                deepLink: '/vip-membership',
                                isRead: false,
                                priority: 'NORMAL' as any,
                                idempotencyKey: `sub_expiring_${sub.id}`,
                            });

                            const user = await User.findByPk(sub.userId);
                            if (user && user.fcmToken) {
                                const { sendMulticastPushNotification } = require('../services/fcmService');
                                await sendMulticastPushNotification([user.fcmToken], {
                                    title: '⏳ VIP Plan Expiring Soon',
                                    body: `Your ${pkgName} subscription will expire in ${daysRemaining} day${daysRemaining > 1 ? 's' : ''}! Renew now to retain your benefits.`,
                                    data: {
                                        type: 'subscription_expiring_soon',
                                        subscriptionId: sub.id,
                                    },
                                });
                            }

                            const { io } = require('../server');
                            io.to(`user_${sub.userId}`).emit('subscription_expiring_soon', {
                                subscriptionId: sub.id,
                                userId: sub.userId,
                                endDate: sub.endDate,
                                message: `Your ${pkgName} subscription will expire in ${daysRemaining} day${daysRemaining > 1 ? 's' : ''}!`,
                            });

                            await sub.update({ expirationAlertSent: true });
                        } catch (warnErr: any) {
                            logger.warn(`Failed to send subscription warning to user ${sub.userId}:`, warnErr.message);
                        }
                    }
                }
            }
            
        } catch (error) {
            logger.error('Error running party plan cron jobs:', error);
        } finally {
            isPartyPlanCronRunning = false;
        }
        }, 500);
    });
};

async function relistPartyPlanInSocket(planId: string) {
    try {
        const relistedPlan = await PartyPlan.findByPk(planId, {
            include: [
                {
                    model: User,
                    as: 'creator',
                    include: [
                        { model: UserProfile, as: 'profile', required: false },
                        { model: UserPhoto, as: 'photos', required: false },
                    ]
                },
                {
                    model: Venue,
                    as: 'venue',
                    include: [
                        {
                            model: VenueImage,
                            as: 'images',
                            where: { imageType: 'cover', isPrimary: true },
                            required: false
                        }
                    ]
                }
            ]
        });

        if (relistedPlan) {
            const creator = (relistedPlan as any).creator;
            let photoUrl = creator?.profileImageUrl ?? null;
            if (creator?.photos && creator.photos.length > 0) {
                const primary = creator.photos.find((p: any) => p.isPrimary) || creator.photos[0];
                if (primary && primary.filePath) {
                    photoUrl = '/' + primary.filePath.replace(/\\/g, '/');
                }
            }

            const venueObj = (relistedPlan as any).venue;

            const responseData = {
                id: relistedPlan.id,
                status: relistedPlan.status,
                paymentStatus: relistedPlan.paymentStatus,
                visibility: relistedPlan.visibility,
                selectedUsers: relistedPlan.selectedUsers,
                message: relistedPlan.message,
                planDateTime: relistedPlan.planDateTime,
                createdAt: relistedPlan.createdAt,
                hostPaymentStatus: relistedPlan.hostPaymentStatus,
                hostRazorpayOrderId: relistedPlan.hostRazorpayOrderId,
                isLive: relistedPlan.isLive,
                depositAmount: relistedPlan.depositAmount,
                expiresAt: relistedPlan.expiresAt,
                user: creator ? {
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
                } : null,
                venue: venueObj ? {
                    id: venueObj.id,
                    name: venueObj.name,
                    addressLine1: venueObj.addressLine1,
                    area: venueObj.area,
                    city: venueObj.city,
                    category: venueObj.category,
                } : null,
            };

            const { io } = require('../server');
            io.to(`user_${relistedPlan.userId}`).emit('party_plan_created', responseData);
            if (Array.isArray(relistedPlan.selectedUsers)) {
                for (const invitedUserId of relistedPlan.selectedUsers) {
                    io.to(`user_${invitedUserId}`).emit('party_plan_created', responseData);
                }
            }
        }
    } catch (socketErr) {
        logger.warn('Socket emission failed for relistPartyPlanInSocket:', socketErr);
    }
}

import { NotificationService } from '../services/NotificationService';
import StrangersMeetRequest from '../models/StrangersMeetRequest';
import StrangersMeetJoiner from '../models/StrangersMeetJoiner';
import PlanTimeLock from '../models/PlanTimeLock';

let isNotificationJobCronRunning = false;
export const startNotificationJobCron = () => {
    cron.schedule('* * * * *', () => {
        setTimeout(async () => {
            if (isNotificationJobCronRunning) {
                return;
            }
            isNotificationJobCronRunning = true;
            try {
            const now = new Date();
            const NotificationJob = require('../models/NotificationJob').default;

            const pendingJobs = await NotificationJob.findAll({
                where: {
                    status: 'pending',
                    sendAt: { [Op.lte]: now }
                }
            });

            if (pendingJobs.length === 0) return;

            logger.info(`Processing ${pendingJobs.length} scheduled notification jobs...`);

            for (const job of pendingJobs) {
                try {
                    await NotificationService.dispatch({
                        recipientUserId: job.userId,
                        eventType: 'lock_expired',
                        category: 'alert',
                        entityType: 'NotificationJob',
                        entityId: job.id,
                        title: job.title,
                        body: job.body,
                        priority: 'HIGH',
                        idempotencyKey: `job_dispatch_${job.id}`,
                    });

                    await job.update({ status: 'sent' });
                } catch (jobErr: any) {
                    logger.error(`Error processing job ${job.id}:`, jobErr);
                    await job.update({ status: 'failed' });
                }
            }
        } catch (cronErr: any) {
            logger.error('Notification Job Cron error:', cronErr);
        } finally {
            isNotificationJobCronRunning = false;
        }
        }, 200);
    });
};

let isExpiringPlanAlertCronRunning = false;
export const startExpiringPlanAlertCron = () => {
    // Run every 3 minutes
    cron.schedule('*/3 * * * *', () => {
        setTimeout(async () => {
            if (isExpiringPlanAlertCronRunning) {
                return;
            }
            isExpiringPlanAlertCronRunning = true;
            try {
            const now = new Date();
            const in15Mins = new Date(now.getTime() + 15 * 60 * 1000);
            const in45Mins = new Date(now.getTime() + 45 * 60 * 1000);
            const in10Mins = new Date(now.getTime() + 10 * 60 * 1000);

            // 1. Party Plans starting in ~30 mins (between 15m and 45m from now)
            const startingPlans = await PartyPlan.findAll({
                where: {
                    status: PartyPlanStatus.ACTIVE,
                    planDateTime: {
                        [Op.gte]: in15Mins,
                        [Op.lte]: in45Mins,
                    }
                },
                include: [{ model: Venue, as: 'venue', attributes: ['name'] }]
            });

            for (const plan of startingPlans) {
                const venueName = (plan as any).venue?.name || 'Venue';
                // Notify Host
                await NotificationService.dispatch({
                    recipientUserId: plan.userId,
                    eventType: 'party_plan_starting_soon',
                    category: 'alert',
                    entityType: 'PartyPlan',
                    entityId: plan.id,
                    title: '⏰ Party Plan Starting Soon!',
                    body: `Your party plan at ${venueName} starts in ~30 minutes! Open your ticket to prepare for check-in.`,
                    priority: 'HIGH',
                    idempotencyKey: `alert_plan_start_${plan.id}_${plan.userId}`,
                    deepLink: `/party-plan-ticket/${plan.id}`,
                    actionType: 'view_ticket',
                });

                // Notify Accepted Joiners
                const requests = await PartyPlanRequest.findAll({
                    where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                });
                for (const req of requests) {
                    await NotificationService.dispatch({
                        recipientUserId: req.requesterId,
                        eventType: 'party_plan_starting_soon',
                        category: 'alert',
                        entityType: 'PartyPlan',
                        entityId: plan.id,
                        title: '⏰ Party Plan Starting Soon!',
                        body: `Your party plan at ${venueName} starts in ~30 minutes! Show your ticket at the venue.`,
                        priority: 'HIGH',
                        idempotencyKey: `alert_plan_start_${plan.id}_${req.requesterId}`,
                        deepLink: `/party-plan-ticket/${plan.id}`,
                        actionType: 'view_ticket',
                    });
                }
            }

            // 2. Strangers Meet starting in ~30 mins (between 15m and 45m from now)
            const startingMeets = await StrangersMeetRequest.findAll({
                where: {
                    status: 'approved',
                    eventDateTime: {
                        [Op.gte]: in15Mins,
                        [Op.lte]: in45Mins,
                    }
                },
                include: [{ model: Venue, as: 'venue', attributes: ['name'] }]
            });

            for (const meet of startingMeets) {
                const venueName = (meet as any).venue?.name || 'Venue';
                // Notify Host
                await NotificationService.dispatch({
                    recipientUserId: meet.userId,
                    eventType: 'strangers_meet_starting_soon',
                    category: 'alert',
                    entityType: 'StrangersMeetRequest',
                    entityId: meet.id,
                    title: '⏰ Stranger Meet Starting Soon!',
                    body: `Your meet "${meet.subject}" at ${venueName} starts in ~30 minutes!`,
                    priority: 'HIGH',
                    idempotencyKey: `alert_meet_start_${meet.id}_${meet.userId}`,
                    deepLink: `/strangers-meet-ticket/${meet.id}`,
                    actionType: 'view_ticket',
                });

                // Notify Joiners
                const joiners = await StrangersMeetJoiner.findAll({
                    where: { strangersMeetRequestId: meet.id, paymentStatus: 'paid' }
                });
                for (const j of joiners) {
                    await NotificationService.dispatch({
                        recipientUserId: j.userId,
                        eventType: 'strangers_meet_starting_soon',
                        category: 'alert',
                        entityType: 'StrangersMeetRequest',
                        entityId: meet.id,
                        title: '⏰ Stranger Meet Starting Soon!',
                        body: `Your meet "${meet.subject}" at ${venueName} starts in ~30 minutes!`,
                        priority: 'HIGH',
                        idempotencyKey: `alert_meet_start_${meet.id}_${j.userId}`,
                        deepLink: `/strangers-meet-ticket/${meet.id}`,
                        actionType: 'view_ticket',
                    });
                }
            }

            // 3. Time Lock Cooldown Ending (within next 10 minutes)
            const expiringLocks = await PlanTimeLock.findAll({
                where: {
                    status: 'active',
                    lockEndAt: {
                        [Op.gte]: now,
                        [Op.lte]: in10Mins,
                    }
                }
            });

            for (const lock of expiringLocks) {
                await NotificationService.dispatch({
                    recipientUserId: lock.userId,
                    eventType: 'cooldown_expiring_soon',
                    category: 'alert',
                    entityType: 'PlanTimeLock',
                    entityId: lock.id,
                    title: '⚡ Cooldown Expiring Soon',
                    body: 'Your plan creation cooldown expires in a few minutes. Get ready to post your next party!',
                    priority: 'NORMAL',
                    idempotencyKey: `alert_cooldown_${lock.id}_${lock.userId}`,
                    actionType: 'open_plans',
                });
            }

            // 4. Payment Window Closing Soon (10 minutes remaining)
            const pendingRequests = await PartyPlanRequest.findAll({
                where: {
                    status: PartyPlanRequestStatus.PAYMENT_PENDING,
                    paymentTimeoutAt: {
                        [Op.gte]: now,
                        [Op.lte]: in10Mins,
                    }
                },
                include: [{ model: PartyPlan, as: 'plan', include: [{ model: Venue, as: 'venue', attributes: ['name'] }] }]
            });

            for (const req of pendingRequests) {
                const plan = (req as any).plan;
                const venueName = plan?.venue?.name || 'Venue';
                const recipientId = req.joinerPaymentStatus !== 'paid' ? req.requesterId : plan?.userId;
                if (recipientId) {
                    await NotificationService.dispatch({
                        recipientUserId: recipientId,
                        eventType: 'payment_window_expiring',
                        category: 'alert',
                        entityType: 'PartyPlanRequest',
                        entityId: req.id,
                        title: '💳 Payment Window Closing Soon',
                        body: `Only ~10 minutes left to complete payment for party plan at ${venueName}. Complete payment to lock your spot!`,
                        priority: 'HIGH',
                        idempotencyKey: `alert_pay_timeout_${req.id}_${recipientId}`,
                        actionType: 'pay_now',
                    });
                }
            }
            // 5. Trigger Post-Party Safety Checks (3 hours after party start time)
            await checkAndTriggerPartySafetyChecks();
        } catch (alertErr: any) {
            logger.error('Expiring Plan Alert Cron Error:', alertErr);
        } finally {
            isExpiringPlanAlertCronRunning = false;
        }
        }, 350);
    });
};

/**
 * Automates 3-Hour Post-Party Safety Checks for Party Plans & Stranger Meets
 */
export const checkAndTriggerPartySafetyChecks = async () => {
    try {
        const now = new Date();
        const threeHoursAgo = new Date(now.getTime() - 3 * 60 * 60 * 1000);
        const twelveHoursAgo = new Date(now.getTime() - 12 * 60 * 60 * 1000);

        // 0. Auto-resolve any safety checks older than 12 hours as SAFE
        try {
            const expiredChecks = await PartySafetyCheck.findAll({
                where: {
                    safetyStatus: SafetyStatus.NO_RESPONSE,
                    [Op.or]: [
                        { partyDate: { [Op.lte]: twelveHoursAgo } },
                        { createdAt: { [Op.lte]: twelveHoursAgo } },
                    ]
                }
            });

            if (expiredChecks.length > 0) {
                const expiredIds = expiredChecks.map(c => c.id);
                await PartySafetyCheck.update(
                    {
                        safetyStatus: SafetyStatus.SAFE,
                        notes: 'Auto-resolved safe after 12 hours',
                        respondedAt: now,
                    },
                    {
                        where: { id: { [Op.in]: expiredIds } }
                    }
                );

                try {
                    const Notification = (await import('../models/Notification')).default;
                    await Notification.update(
                        { isRead: true },
                        {
                            where: {
                                entityType: 'PartySafetyCheck',
                                entityId: { [Op.in]: expiredIds },
                            }
                        }
                    );
                } catch (_) {}
            }
        } catch (autoErr: any) {
            logger.warn('[checkAndTriggerPartySafetyChecks] Failed to auto-resolve 12h safety checks:', autoErr.message);
        }

        // 1. Party Plans scheduled 3 to 12 hours ago
        const partyPlans = await PartyPlan.findAll({
            where: {
                planDateTime: { [Op.between]: [twelveHoursAgo, threeHoursAgo] },
            },
            include: [
                { model: Venue, as: 'venue', attributes: ['name'] },
                { model: User, as: 'creator', attributes: ['id', 'firstName', 'lastName', 'phone'] }
            ]
        });

        for (const plan of partyPlans) {
            const venueName = (plan as any).venue?.name || 'Venue';
            const hostId = plan.userId;

            // Find accepted joiner
            const acceptedReq = await PartyPlanRequest.findOne({
                where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED },
                include: [{ model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'phone'] }]
            });

            const joinerId = acceptedReq ? acceptedReq.requesterId : undefined;

            // Dispatch to Host
            await dispatchSafetyCheckIfPending({
                planId: plan.id,
                planType: 'party_plan',
                userId: hostId,
                partnerUserId: joinerId,
                venueName,
                partyDate: plan.planDateTime,
                partyTime: (plan as any).startTime || '10:00 PM',
            });

            // Dispatch to Joiner
            if (joinerId) {
                await dispatchSafetyCheckIfPending({
                    planId: plan.id,
                    planType: 'party_plan',
                    userId: joinerId,
                    partnerUserId: hostId,
                    venueName,
                    partyDate: plan.planDateTime,
                    partyTime: (plan as any).startTime || '10:00 PM',
                });
            }
        }

        // 2. Stranger Meets scheduled 3 to 12 hours ago
        const strangerMeets = await StrangersMeetRequest.findAll({
            where: {
                eventDateTime: { [Op.between]: [twelveHoursAgo, threeHoursAgo] },
            },
            include: [{ model: Venue, as: 'venue', attributes: ['name'] }]
        });

        for (const meet of strangerMeets) {
            const venueName = (meet as any).venue?.name || 'Venue';
            const hostId = meet.userId;

            const joiners = await StrangersMeetJoiner.findAll({
                where: { strangersMeetRequestId: meet.id, paymentStatus: 'paid' }
            });

            const joinerIds = joiners.map(j => j.userId);

            // Dispatch to Host
            await dispatchSafetyCheckIfPending({
                planId: meet.id,
                planType: 'stranger_meet',
                userId: hostId,
                partnerUserId: joinerIds[0],
                venueName,
                partyDate: meet.eventDateTime,
                partyTime: '10:00 PM',
            });

            // Dispatch to Joiners
            for (const jId of joinerIds) {
                await dispatchSafetyCheckIfPending({
                    planId: meet.id,
                    planType: 'stranger_meet',
                    userId: jId,
                    partnerUserId: hostId,
                    venueName,
                    partyDate: meet.eventDateTime,
                    partyTime: '10:00 PM',
                });
            }
        }
    } catch (err: any) {
        logger.error('checkAndTriggerPartySafetyChecks error:', err);
    }
};

async function dispatchSafetyCheckIfPending(data: {
    planId: string;
    planType: string;
    userId: string;
    partnerUserId?: string;
    venueName: string;
    partyDate: Date;
    partyTime?: string;
}) {
    try {
        let existing = null;
        try {
            existing = await PartySafetyCheck.findOne({
                where: {
                    planId: data.planId,
                    userId: data.userId,
                }
            });
        } catch (tableErr) {
            // If table doesn't exist, sync it safely
            await PartySafetyCheck.sync();
        }

        if (existing) return; // Notification already created

        const now = new Date();
        const partyStart = data.partyDate ? new Date(data.partyDate) : now;
        const diffMs = Math.max(0, now.getTime() - partyStart.getTime());
        const elapsedHours = Math.max(1, Math.round(diffMs / (1000 * 60 * 60)));
        const hoursText = `${elapsedHours} hour${elapsedHours === 1 ? '' : 's'} ago`;

        const safetyRecord = await PartySafetyCheck.create({
            planId: data.planId,
            planType: data.planType,
            userId: data.userId,
            partnerUserId: data.partnerUserId,
            venueName: data.venueName,
            partyDate: data.partyDate,
            partyTime: data.partyTime,
            safetyStatus: SafetyStatus.NO_RESPONSE,
            alertTriggered: false,
            notificationSentAt: now,
        });

        await NotificationService.dispatch({
            recipientUserId: data.userId,
            eventType: 'party_safety_check',
            category: 'alert',
            entityType: 'PartySafetyCheck',
            entityId: safetyRecord.id,
            title: 'Safety Check: Has your party ended?',
            body: `Your party at ${data.venueName} started ${hoursText}. Please confirm you are safe & sound.`,
            priority: 'HIGH',
            idempotencyKey: `safety_check_${safetyRecord.id}_${data.userId}`,
            actionType: 'safety_check',
            deepLink: `/safety-check/${safetyRecord.id}`,
            metadata: {
                checkId: safetyRecord.id,
                planId: data.planId,
                venueName: data.venueName,
                partyDate: data.partyDate,
                partyTime: data.partyTime,
                elapsedHours,
            }
        });
    } catch (err: any) {
        logger.error(`Failed to dispatch safety check for plan ${data.planId} and user ${data.userId}:`, err.message || err);
    }
}

export const checkAndTriggerStrangersMeetLifecycle = async () => {
    try {
        const StrangersMeetRequest = (await import('../models/StrangersMeetRequest')).default;
        const { StrangersMeetStatus, StrangersMeetPaymentStatus } = await import('../models/StrangersMeetRequest');
        const Venue = (await import('../models/Venue')).default;
        const { io } = require('../server');

        const now = new Date();

        // 1. Check for Strangers Meets whose start time has arrived and need host start confirmation
        const readyToStartMeets = await StrangersMeetRequest.findAll({
            where: {
                status: StrangersMeetStatus.APPROVED,
                paymentStatus: StrangersMeetPaymentStatus.PAID,
                eventDateTime: { [Op.lte]: now },
                startedAt: null as any,
            },
            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name', 'area'] }]
        });

        for (const meet of readyToStartMeets) {
            const venueName = (meet as any).venue?.name || 'Venue';
            if (io) {
                io.to(`user_${meet.userId}`).emit('strangers_meet_start_prompt', {
                    meetId: meet.id,
                    subject: meet.subject,
                    venueName,
                    eventDateTime: meet.eventDateTime,
                });
            }
        }

        // 2. Check for in-progress Strangers Meets whose expected end time has arrived
        const readyToEndMeets = await StrangersMeetRequest.findAll({
            where: {
                status: StrangersMeetStatus.IN_PROGRESS,
                expectedEndAt: { [Op.lte]: now },
            },
            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name', 'area'] }]
        });

        for (const meet of readyToEndMeets) {
            const venueName = (meet as any).venue?.name || 'Venue';
            if (io) {
                io.to(`user_${meet.userId}`).emit('strangers_meet_end_prompt', {
                    meetId: meet.id,
                    subject: meet.subject,
                    venueName,
                    expectedEndAt: meet.expectedEndAt,
                });
            }
        }

        // 3. Check for overdue settlements (> 24h since admin confirmation without payout)
        const twentyFourHoursAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);
        await StrangersMeetRequest.update(
            { settlementOverdue: true },
            {
                where: {
                    status: StrangersMeetStatus.ADMIN_CONFIRMED_ENDED,
                    adminConfirmedEndedAt: { [Op.lte]: twentyFourHoursAgo },
                    settlementStatus: { [Op.notIn]: ['paid', 'settled'] },
                    settlementOverdue: false,
                }
            }
        );
    } catch (err: any) {
        logger.error('checkAndTriggerStrangersMeetLifecycle error:', err);
    }
};

