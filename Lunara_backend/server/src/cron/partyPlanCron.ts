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
import ChatSubscription, { ChatSubscriptionStatus } from '../models/ChatSubscription';
import Conversation from '../models/Conversation';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import SubscriptionPackage from '../models/SubscriptionPackage';
import PartySafetyCheck, { SafetyStatus } from '../models/PartySafetyCheck';

// Run every 5 minutes
export const startPartyPlanCron = () => {
    cron.schedule('*/5 * * * *', async () => {
        try {
            logger.info('Running Party Plan Cron Jobs...');
            
            const now = new Date();

            // 1. Check for expired payment timeouts
            // Requests that are PAYMENT_PENDING but the timeout has passed
            const expiredRequests = await PartyPlanRequest.findAll({
                where: {
                    status: PartyPlanRequestStatus.PAYMENT_PENDING,
                    paymentTimeoutAt: {
                        [Op.lt]: now
                    }
                },
                include: [{ model: PartyPlan, as: 'plan' }]
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


            // ── 2. Event Countdown Engine (24h, 3h, 1h, 30m Reminders) ─────────
            try {
                const sequelize = (await import('../config/database')).default;
                await sequelize.query(`
                    ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_24h_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_3h_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_1h_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_30m_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_2h_sent BOOLEAN DEFAULT FALSE;
                    ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_10m_sent BOOLEAN DEFAULT FALSE;
                `).catch(() => {});
            } catch (_) {}

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

            // 10-Minute Arrival Confirmation Prompt
            const next15m10m = new Date(now.getTime() + 15 * 60 * 1000);
            const next5m = new Date(now.getTime() + 5 * 60 * 1000);
            const upcoming10mPlans = await PartyPlan.findAll({
                where: {
                    status: { [Op.in]: ['active', 'inactive'] },
                    reminder10mSent: false,
                    planDateTime: { [Op.between]: [next5m, next15m10m] },
                }
            });

            for (const plan of upcoming10mPlans) {
                await plan.update({
                    reminder10mSent: true,
                    lifecycleStatus: PartyPlanLifecycleStatus.TEN_MIN_CONFIRMATION,
                });
                const acceptedReq = await PartyPlanRequest.findOne({
                    where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                });
                if (acceptedReq) {
                    const host = await User.findByPk(plan.userId);
                    const joiner = await User.findByPk(acceptedReq.requesterId);
                    const { sendMulticastPushNotification } = require('../services/fcmService');
                    const NotificationService = (await import('../services/NotificationService')).NotificationService;
                    const promptMsg = `Have you reached the venue? Please confirm your arrival.`;

                    if (host?.fcmToken) {
                        await sendMulticastPushNotification([host.fcmToken], {
                            title: '📍 Have you reached the venue?',
                            body: promptMsg,
                            data: { type: 'arrival_prompt', partyPlanId: plan.id }
                        });
                    }
                    if (joiner?.fcmToken) {
                        await sendMulticastPushNotification([joiner.fcmToken], {
                            title: '📍 Have you reached the venue?',
                            body: promptMsg,
                            data: { type: 'arrival_prompt', partyPlanId: plan.id }
                        });
                    }

                    await NotificationService.dispatch({
                        recipientUserId: plan.userId,
                        actorUserId: acceptedReq.requesterId,
                        eventType: 'arrival_prompt',
                        category: 'events',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: '📍 Have you reached the venue?',
                        body: promptMsg,
                        actionType: 'CONFIRM_ARRIVAL'
                    });

                    await NotificationService.dispatch({
                        recipientUserId: acceptedReq.requesterId,
                        actorUserId: plan.userId,
                        eventType: 'arrival_prompt',
                        category: 'events',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: '📍 Have you reached the venue?',
                        body: promptMsg,
                        actionType: 'CONFIRM_ARRIVAL'
                    });
                }
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

                // 2 Hours Before Reminder
                const gpNext2h5 = new Date(now.getTime() + 135 * 60 * 1000);
                const gpNext2h15 = new Date(now.getTime() + 105 * 60 * 1000);
                const gp2hParties = await GroupParty.findAll({
                    where: {
                        status: GroupPartyStatus.CONFIRMED,
                        paymentStatus: GroupPartyPaymentStatus.PAID,
                        reminder2hSent: false,
                        partyDate: { [Op.between]: [gpNext2h15, gpNext2h5] }
                    }
                });

                for (const party of gp2hParties) {
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
                const gpNext1h15 = new Date(now.getTime() + 75 * 60 * 1000);
                const gpNext1h45 = new Date(now.getTime() + 45 * 60 * 1000);
                const gp1hParties = await GroupParty.findAll({
                    where: {
                        status: GroupPartyStatus.CONFIRMED,
                        paymentStatus: GroupPartyPaymentStatus.PAID,
                        reminder1hSent: false,
                        partyDate: { [Op.between]: [gpNext1h45, gpNext1h15] }
                    }
                });

                for (const party of gp1hParties) {
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
                const gpNext35m = new Date(now.getTime() + 35 * 60 * 1000);
                const gpNext25m = new Date(now.getTime() + 25 * 60 * 1000);
                const gp30mParties = await GroupParty.findAll({
                    where: {
                        status: GroupPartyStatus.CONFIRMED,
                        paymentStatus: GroupPartyPaymentStatus.PAID,
                        reminder30mSent: false,
                        partyDate: { [Op.between]: [gpNext25m, gpNext35m] }
                    }
                });

                for (const party of gp30mParties) {
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

                // 2 Hours Before Reminder
                const lpNext2h5 = new Date(now.getTime() + 135 * 60 * 1000);
                const lpNext2h15 = new Date(now.getTime() + 105 * 60 * 1000);
                const lp2hBookings = await Booking.findAll({
                    where: {
                        isLargePartyRequest: true,
                        status: BookingStatus.CONFIRMED,
                        paymentStatus: PaymentStatus.PAID,
                        reminder2hSent: false,
                        bookingDate: { [Op.between]: [lpNext2h15, lpNext2h5] }
                    }
                });

                for (const booking of lp2hBookings) {
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
                const lpNext1h15 = new Date(now.getTime() + 75 * 60 * 1000);
                const lpNext1h45 = new Date(now.getTime() + 45 * 60 * 1000);
                const lp1hBookings = await Booking.findAll({
                    where: {
                        isLargePartyRequest: true,
                        status: BookingStatus.CONFIRMED,
                        paymentStatus: PaymentStatus.PAID,
                        reminder1hSent: false,
                        bookingDate: { [Op.between]: [lpNext1h45, lpNext1h15] }
                    }
                });

                for (const booking of lp1hBookings) {
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
                const lpNext35m = new Date(now.getTime() + 35 * 60 * 1000);
                const lpNext25m = new Date(now.getTime() + 25 * 60 * 1000);
                const lp30mBookings = await Booking.findAll({
                    where: {
                        isLargePartyRequest: true,
                        status: BookingStatus.CONFIRMED,
                        paymentStatus: PaymentStatus.PAID,
                        reminder30mSent: false,
                        bookingDate: { [Op.between]: [lpNext25m, lpNext35m] }
                    }
                });

                for (const booking of lp30mBookings) {
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

                // 2 Hours Before Reminder
                const unNext2h5 = new Date(now.getTime() + 135 * 60 * 1000);
                const unNext2h15 = new Date(now.getTime() + 105 * 60 * 1000);
                const un2hMatches = await NightPartnerMatch.findAll({
                    where: {
                        status: NightPartnerMatchStatus.CONFIRMED,
                        reminder2hSent: false,
                        eventDate: { [Op.between]: [unNext2h15, unNext2h5] }
                    }
                });

                for (const match of un2hMatches) {
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
                const unNext1h15 = new Date(now.getTime() + 75 * 60 * 1000);
                const unNext1h45 = new Date(now.getTime() + 45 * 60 * 1000);
                const un1hMatches = await NightPartnerMatch.findAll({
                    where: {
                        status: NightPartnerMatchStatus.CONFIRMED,
                        reminder1hSent: false,
                        eventDate: { [Op.between]: [unNext1h45, unNext1h15] }
                    }
                });

                for (const match of un1hMatches) {
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
                const unNext35m = new Date(now.getTime() + 35 * 60 * 1000);
                const unNext25m = new Date(now.getTime() + 25 * 60 * 1000);
                const un30mMatches = await NightPartnerMatch.findAll({
                    where: {
                        status: NightPartnerMatchStatus.CONFIRMED,
                        reminder30mSent: false,
                        eventDate: { [Op.between]: [unNext25m, unNext35m] }
                    }
                });

                for (const match of un30mMatches) {
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

                // 2 Hours Before Reminder
                const vbNext2h5 = new Date(now.getTime() + 135 * 60 * 1000);
                const vbNext2h15 = new Date(now.getTime() + 105 * 60 * 1000);
                const vb2hBookings = await Booking.findAll({
                    where: {
                        isGroupBooking: false,
                        isLargePartyRequest: false,
                        status: BookingStatus.CONFIRMED,
                        paymentStatus: PaymentStatus.PAID,
                        reminder2hSent: false,
                        bookingDate: { [Op.between]: [vbNext2h15, vbNext2h5] }
                    }
                });

                for (const booking of vb2hBookings) {
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
                const vbNext1h15 = new Date(now.getTime() + 75 * 60 * 1000);
                const vbNext1h45 = new Date(now.getTime() + 45 * 60 * 1000);
                const vb1hBookings = await Booking.findAll({
                    where: {
                        isGroupBooking: false,
                        isLargePartyRequest: false,
                        status: BookingStatus.CONFIRMED,
                        paymentStatus: PaymentStatus.PAID,
                        reminder1hSent: false,
                        bookingDate: { [Op.between]: [vbNext1h45, vbNext1h15] }
                    }
                });

                for (const booking of vb1hBookings) {
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
                const vbNext35m = new Date(now.getTime() + 35 * 60 * 1000);
                const vbNext25m = new Date(now.getTime() + 25 * 60 * 1000);
                const vb30mBookings = await Booking.findAll({
                    where: {
                        isGroupBooking: false,
                        isLargePartyRequest: false,
                        status: BookingStatus.CONFIRMED,
                        paymentStatus: PaymentStatus.PAID,
                        reminder30mSent: false,
                        bookingDate: { [Op.between]: [vbNext25m, vbNext35m] }
                    }
                });

                for (const booking of vb30mBookings) {
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
            } catch (vbCronErr) {
                logger.error('[partyPlanCron] Venue Booking reminder engine error:', vbCronErr);
            }

            // ── 3. Process Completed Plans & Execute 4-Case Refund Engine ─────
            const twoHoursAgo = new Date(now.getTime() - 2 * 60 * 60 * 1000);
            
            const completedPlans = await PartyPlan.findAll({
                where: {
                    status: { [Op.in]: ['active', 'inactive'] },
                    hostPaymentStatus: PartyPlanPaymentStatus.PAID,
                    planDateTime: { [Op.lt]: twoHoursAgo }
                }
            });

            const { ReliabilityService, ReliabilityAction } = await import('../services/reliabilityService');
            const WalletTransaction = (await import('../models/WalletTransaction')).default;
            const WalletTransactionType = (await import('../models/WalletTransaction')).WalletTransactionType;

            for (const plan of completedPlans) {
                const acceptedReq = await PartyPlanRequest.findOne({
                    where: {
                        planId: plan.id,
                        status: PartyPlanRequestStatus.ACCEPTED,
                        joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                    }
                });

                if (!acceptedReq) {
                    await plan.update({ status: PartyPlanStatus.INACTIVE });
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
                        const existingHostTx = await WalletTransaction.findOne({ where: { reference: `REFUND_HOST_${plan.id}` } });
                        if (!existingHostTx) {
                            const hOld = Number(hostUser.walletBalance || 0);
                            const hNew = hOld + hostDeposit;
                            await hostUser.update({ walletBalance: hNew });
                            await plan.update({ hostPaymentStatus: PartyPlanPaymentStatus.REFUNDED });
                            await WalletTransaction.logTransaction({
                                userId: hostUser.id,
                                partyPlanId: plan.id,
                                amount: hostDeposit,
                                openingBalance: hOld,
                                closingBalance: hNew,
                                transactionType: WalletTransactionType.REFUND,
                                reference: `REFUND_HOST_${plan.id}`,
                            });
                            await ReliabilityService.updateScore({
                                userId: hostUser.id,
                                action: ReliabilityAction.SUCCESSFUL_ATTENDANCE,
                                partyPlanId: plan.id,
                            });
                        }
                    }

                    if (guestUser && guestDeposit > 0) {
                        const existingGuestTx = await WalletTransaction.findOne({ where: { reference: `REFUND_GUEST_${acceptedReq.id}` } });
                        if (!existingGuestTx) {
                            const gOld = Number(guestUser.walletBalance || 0);
                            const gNew = gOld + guestDeposit;
                            await guestUser.update({ walletBalance: gNew });
                            await acceptedReq.update({ joinerPaymentStatus: PartyPlanJoinerPaymentStatus.REFUNDED });
                            await WalletTransaction.logTransaction({
                                userId: guestUser.id,
                                partyPlanId: plan.id,
                                amount: guestDeposit,
                                openingBalance: gOld,
                                closingBalance: gNew,
                                transactionType: WalletTransactionType.REFUND,
                                reference: `REFUND_GUEST_${acceptedReq.id}`,
                            });
                        }
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
                // ── CASE 2: Host YES, Guest NO ─────────────────────────────────
                else if (hostYes && !guestYes) {
                    logger.info(`[RefundEngine Case 2] Host YES, Guest NO for plan ${plan.id}`);

                    if (hostUser) {
                        const existingHostTx = await WalletTransaction.findOne({ where: { reference: `REFUND_HOST_${plan.id}` } });
                        if (!existingHostTx) {
                            const hOld = Number(hostUser.walletBalance || 0);
                            const hNew = hOld + hostDeposit;
                            await hostUser.update({ walletBalance: hNew });
                            await plan.update({ hostPaymentStatus: PartyPlanPaymentStatus.REFUNDED });
                            await WalletTransaction.logTransaction({
                                userId: hostUser.id,
                                partyPlanId: plan.id,
                                amount: hostDeposit,
                                openingBalance: hOld,
                                closingBalance: hNew,
                                transactionType: WalletTransactionType.REFUND,
                                reference: `REFUND_HOST_${plan.id}`,
                            });
                            await ReliabilityService.updateScore({
                                userId: hostUser.id,
                                action: ReliabilityAction.SUCCESSFUL_ATTENDANCE,
                                partyPlanId: plan.id,
                            });
                        }
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
                // ── CASE 3: Host NO, Guest YES ─────────────────────────────────
                else if (!hostYes && guestYes) {
                    logger.info(`[RefundEngine Case 3] Host NO, Guest YES for plan ${plan.id}`);

                    if (guestUser && guestDeposit > 0) {
                        const existingGuestTx = await WalletTransaction.findOne({ where: { reference: `REFUND_GUEST_${acceptedReq.id}` } });
                        if (!existingGuestTx) {
                            const gOld = Number(guestUser.walletBalance || 0);
                            const gNew = gOld + guestDeposit;
                            await guestUser.update({ walletBalance: gNew });
                            await acceptedReq.update({ joinerPaymentStatus: PartyPlanJoinerPaymentStatus.REFUNDED });
                            await WalletTransaction.logTransaction({
                                userId: guestUser.id,
                                partyPlanId: plan.id,
                                amount: guestDeposit,
                                openingBalance: gOld,
                                closingBalance: gNew,
                                transactionType: WalletTransactionType.REFUND,
                                reference: `REFUND_GUEST_${acceptedReq.id}`,
                            });
                        }
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
                // ── CASE 4 & 5: Host NO, Guest NO (or Timeout) ───────────────
                else {
                    logger.info(`[RefundEngine Case 4/5] Host NO, Guest NO for plan ${plan.id}`);

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
                        paymentStatus: 'Closed (Both No-Show / Timeout)'
                    });
                }
            }

            // 3. Check for recently expired chat subscriptions
            const expiredChats = await ChatSubscription.findAll({
                where: {
                    status: ChatSubscriptionStatus.ACTIVE,
                    validUntil: {
                        [Op.lt]: now
                    }
                }
            });

            for (const sub of expiredChats) {
                await sub.update({ status: ChatSubscriptionStatus.EXPIRED });
                
                // Get the conversation participants and send a push notification
                try {
                    const conv = await Conversation.findByPk(sub.conversationId);
                    if (conv) {
                        const host = await User.findByPk(conv.participantOne);
                        const joiner = await User.findByPk(conv.participantTwo);
                        const tokens = [host?.fcmToken, joiner?.fcmToken].filter(t => t && t.trim() !== '') as string[];
                        if (tokens.length > 0) {
                            const { sendMulticastPushNotification } = require('../services/fcmService');
                            await sendMulticastPushNotification(tokens, {
                                title: '💬 Chat Expired',
                                body: 'Your private chat session has expired. Extend it to keep chatting!',
                                data: {
                                    type: 'chat_expired',
                                    conversationId: sub.conversationId,
                                },
                            });
                        }
                    }
                } catch (pushErr: any) {
                    logger.warn('Failed to send chat expired push notification:', pushErr.message);
                }
            }

            // 4. Check for user subscription expiration and expiration warnings (24h alert)
            const activeSubscriptions = await UserSubscription.findAll({
                where: {
                    status: SubscriptionStatus.ACTIVE,
                },
                include: [{ model: SubscriptionPackage, as: 'package' }]
            });

            const in24Hours = new Date(now.getTime() + 24 * 60 * 60 * 1000);

            for (const sub of activeSubscriptions) {
                const endDate = new Date(sub.endDate);
                const pkg = (sub as any).package;
                const pkgName = pkg?.name || 'VIP Package';

                if (endDate <= now) {
                    // Plan Has Expired
                    await sub.update({ status: SubscriptionStatus.EXPIRED });
                    logger.info(`Subscription ${sub.id} for user ${sub.userId} marked as EXPIRED.`);

                    // Push Notification to user
                    try {
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
                } else if (endDate <= in24Hours) {
                    // Plan is expiring within 24 hours - send warning if not already sent
                    if (!sub.expirationAlertSent) {
                        try {
                            const user = await User.findByPk(sub.userId);
                            if (user && user.fcmToken) {
                                const { sendMulticastPushNotification } = require('../services/fcmService');
                                await sendMulticastPushNotification([user.fcmToken], {
                                    title: '⏳ VIP Plan Expiring Soon',
                                    body: `Your ${pkgName} subscription will expire in less than 24 hours! Renew now to retain your benefits.`,
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
                                message: `Your ${pkgName} subscription will expire in less than 24 hours!`,
                            });

                            await sub.update({ expirationAlertSent: true });
                        } catch (warnErr: any) {
                            logger.warn(`Failed to send subscription 24h warning to user ${sub.userId}:`, warnErr.message);
                        }
                    }
                }
            }
            
        } catch (error) {
            logger.error('Error running party plan cron jobs:', error);
        }
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

export const startNotificationJobCron = () => {
    cron.schedule('* * * * *', async () => {
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
        }
    });
};

export const startExpiringPlanAlertCron = () => {
    // Run every 3 minutes
    cron.schedule('*/3 * * * *', async () => {
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
        }
    });
};

/**
 * Automates 3-Hour Post-Party Safety Checks for Party Plans & Stranger Meets
 */
export const checkAndTriggerPartySafetyChecks = async () => {
    try {
        const now = new Date();
        const threeHoursAgo = new Date(now.getTime() - 3 * 60 * 60 * 1000);

        // 1. Party Plans scheduled 3+ hours ago
        const partyPlans = await PartyPlan.findAll({
            where: {
                planDateTime: { [Op.lte]: threeHoursAgo },
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

        // 2. Stranger Meets scheduled 3+ hours ago
        const strangerMeets = await StrangersMeetRequest.findAll({
            where: {
                eventDateTime: { [Op.lte]: threeHoursAgo },
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
            notificationSentAt: new Date(),
        });

        await NotificationService.dispatch({
            recipientUserId: data.userId,
            eventType: 'party_safety_check',
            category: 'alert',
            entityType: 'PartySafetyCheck',
            entityId: safetyRecord.id,
            title: '🛡️ Safety Check: Has your party ended?',
            body: `Your party at ${data.venueName} started 3 hours ago. Please confirm you are safe & sound.`,
            priority: 'HIGH',
            idempotencyKey: `safety_check_${safetyRecord.id}_${data.userId}`,
            actionType: 'safety_check',
            deepLink: `/safety-check/${safetyRecord.id}`,
        });
    } catch (err: any) {
        logger.error(`Failed to dispatch safety check for plan ${data.planId} and user ${data.userId}:`, err.message || err);
    }
}

