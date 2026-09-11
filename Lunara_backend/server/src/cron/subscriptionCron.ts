import cron from 'node-cron';
import { Op } from 'sequelize';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import SubscriptionPackage, { PackageTier } from '../models/SubscriptionPackage';
import User from '../models/User';
import Notification from '../models/Notification';
import { logger } from '../config/logger';
import { SubscriptionService } from '../services/subscriptionService';

let isSubscriptionCronRunning = false;

async function sendExpiryNotificationAndEvents(params: {
    userSub: UserSubscription;
    eventType: string;
    title: string;
    body: string;
    remainingHours?: number;
    isExpired?: boolean;
}) {
    const { userSub, eventType, title, body, remainingHours, isExpired } = params;
    const userId = userSub.userId;

    try {
        // 1. Create DB Notification Record
        await Notification.create({
            recipientUserId: userId,
            eventType: eventType as any,
            category: 'system' as any,
            entityType: 'subscription',
            entityId: userSub.id,
            title,
            body,
            priority: 'HIGH' as any,
            isRead: false,
            metadata: {
                subscriptionId: userSub.id,
                packageId: userSub.packageId,
                remainingHours: remainingHours ?? 0,
                isExpired: !!isExpired,
                expiresAt: userSub.endDate ? userSub.endDate.toISOString() : undefined,
                actionType: 'open_vip_membership',
                primaryAction: 'Renew VIP',
            },
        });
    } catch (dbErr) {
        logger.warn(`[SubscriptionCron] DB Notification creation warning for user ${userId}:`, dbErr);
    }

    try {
        // 2. Send FCM Push Notification
        const user = await User.findByPk(userId, { attributes: ['id', 'fcmToken'] });
        if (user && user.fcmToken) {
            const { sendPushNotification } = require('../services/fcmService');
            await sendPushNotification(user.fcmToken, {
                title,
                body,
                data: {
                    type: eventType,
                    subscriptionId: userSub.id,
                    remainingHours: String(remainingHours ?? 0),
                    isExpired: String(!!isExpired),
                    actionType: 'open_vip_membership',
                },
            });
        }
    } catch (pushErr) {
        logger.warn(`[SubscriptionCron] FCM push notification warning for user ${userId}:`, pushErr);
    }

    try {
        // 3. Emit Real-time Socket Events
        const { io } = require('../server');
        if (io) {
            const pkgName = (userSub as any).package?.name || 'VIP Membership';
            const payload = {
                subscriptionId: userSub.id,
                packageId: userSub.packageId,
                eventType,
                title,
                body,
                message: body,
                planName: pkgName,
                remainingHours: remainingHours ?? 0,
                isExpired: !!isExpired,
                expiresAt: userSub.endDate ? userSub.endDate.toISOString() : new Date().toISOString(),
            };
            if (isExpired) {
                io.to(`user_${userId}`).emit('subscription_expired', payload);
            } else {
                io.to(`user_${userId}`).emit('subscription_expiring', payload);
            }
            io.to(`user_${userId}`).emit('notification_updated', payload);
            io.to(`user_${userId}`).emit('live_feed_update', {
                type: 'vip_subscription_activity',
                userId,
                eventType,
                title,
                timestamp: new Date().toISOString(),
            });
        }
    } catch (socketErr) {
        logger.warn(`[SubscriptionCron] Socket emission warning for user ${userId}:`, socketErr);
    }
}

export const startSubscriptionCron = () => {
    // Run every minute to accurately schedule notifications, expire subscriptions, and queue activations
    cron.schedule('* * * * *', () => {
        setTimeout(async () => {
            if (isSubscriptionCronRunning) {
                return;
            }
            isSubscriptionCronRunning = true;
            try {
            const now = new Date();

            // ─────────────────────────────────────────────────────────────────
            // 1. Process Multi-Stage Expiration Reminders (1-Day, 8h, 5h, 2h, 1h)
            // ─────────────────────────────────────────────────────────────────

            // Query active subscriptions that are expiring within the next 25 hours
            const activeSubsNearExpiry = await UserSubscription.findAll({
                where: {
                    status: SubscriptionStatus.ACTIVE,
                    endDate: {
                        [Op.gt]: now,
                        [Op.lte]: new Date(now.getTime() + 25 * 60 * 60 * 1000),
                    },
                },
                include: [{ model: SubscriptionPackage, as: 'package' }],
                limit: 500,
            });

            for (const sub of activeSubsNearExpiry) {
                const pkg = (sub as any).package;
                if (!pkg || pkg.tier === PackageTier.FREE) continue;

                const remainingMs = sub.endDate.getTime() - now.getTime();
                const remainingHours = remainingMs / (1000 * 60 * 60);
                const pkgName = pkg.name || 'VIP';

                // 1-Hour Reminder (0h - 1h remaining)
                if (remainingHours <= 1 && remainingHours > 0 && !sub.reminder1HourSent) {
                    await sub.update({
                        reminder1HourSent: true,
                        reminder2HourSent: true,
                        reminder5HourSent: true,
                        reminder8HourSent: true,
                        reminder1DaySent: true,
                        lastNotifiedAt: now,
                    });
                    await sendExpiryNotificationAndEvents({
                        userSub: sub,
                        eventType: 'vip_expiring_1hour',
                        title: 'VIP Subscription Expiring in 1 Hour! 🔔',
                        body: `Final Call: Your ${pkgName} subscription expires in 1 hour. Tap to renew instantly.`,
                        remainingHours: 1,
                        isExpired: false,
                    });
                    logger.info(`[SubscriptionCron] Sent 1-hour reminder for sub ${sub.id} to user ${sub.userId}`);
                }
                // 2-Hour Reminder (1h - 2h remaining)
                else if (remainingHours <= 2 && remainingHours > 1 && !sub.reminder2HourSent) {
                    await sub.update({
                        reminder2HourSent: true,
                        reminder5HourSent: true,
                        reminder8HourSent: true,
                        reminder1DaySent: true,
                        lastNotifiedAt: now,
                    });
                    await sendExpiryNotificationAndEvents({
                        userSub: sub,
                        eventType: 'vip_expiring_2hours',
                        title: 'VIP Subscription Expiring in 2 Hours 🚨',
                        body: `Only 2 hours left on your ${pkgName} membership! Renew now before VIP features are locked.`,
                        remainingHours: 2,
                        isExpired: false,
                    });
                    logger.info(`[SubscriptionCron] Sent 2-hour reminder for sub ${sub.id} to user ${sub.userId}`);
                }
                // 5-Hour Reminder (2h - 5h remaining)
                else if (remainingHours <= 5 && remainingHours > 2 && !sub.reminder5HourSent) {
                    await sub.update({
                        reminder5HourSent: true,
                        reminder8HourSent: true,
                        reminder1DaySent: true,
                        lastNotifiedAt: now,
                    });
                    await sendExpiryNotificationAndEvents({
                        userSub: sub,
                        eventType: 'vip_expiring_5hours',
                        title: 'VIP Subscription Expiring in 5 Hours ⏱️',
                        body: `Your ${pkgName} membership expires in 5 hours. Tap to renew and maintain your VIP status.`,
                        remainingHours: 5,
                        isExpired: false,
                    });
                    logger.info(`[SubscriptionCron] Sent 5-hour reminder for sub ${sub.id} to user ${sub.userId}`);
                }
                // 8-Hour Reminder (5h - 8h remaining)
                else if (remainingHours <= 8 && remainingHours > 5 && !sub.reminder8HourSent) {
                    await sub.update({
                        reminder8HourSent: true,
                        reminder1DaySent: true,
                        lastNotifiedAt: now,
                    });
                    await sendExpiryNotificationAndEvents({
                        userSub: sub,
                        eventType: 'vip_expiring_8hours',
                        title: 'VIP Subscription Expiring in 8 Hours ⚠️',
                        body: `Your ${pkgName} subscription expires in 8 hours. Renew now to keep your VIP badge and features.`,
                        remainingHours: 8,
                        isExpired: false,
                    });
                    logger.info(`[SubscriptionCron] Sent 8-hour reminder for sub ${sub.id} to user ${sub.userId}`);
                }
                // 1-Day Reminder (8h - 24h remaining)
                else if (remainingHours <= 24 && remainingHours > 8 && !sub.reminder1DaySent) {
                    await sub.update({
                        reminder1DaySent: true,
                        lastNotifiedAt: now,
                    });
                    await sendExpiryNotificationAndEvents({
                        userSub: sub,
                        eventType: 'vip_expiring_1day',
                        title: 'VIP Subscription Expiring Tomorrow ⏳',
                        body: `Your ${pkgName} subscription expires in 24 hours. Renew now to continue enjoying VIP benefits uninterrupted.`,
                        remainingHours: Math.round(remainingHours),
                        isExpired: false,
                    });
                    logger.info(`[SubscriptionCron] Sent 1-day reminder for sub ${sub.id} to user ${sub.userId}`);
                }
            }

            // ─────────────────────────────────────────────────────────────────
            // 2. Mark Expired Active Subscriptions & Dispatch Expiration Events
            // ─────────────────────────────────────────────────────────────────

            const expiredSubs = await UserSubscription.findAll({
                where: {
                    status: SubscriptionStatus.ACTIVE,
                    endDate: { [Op.lte]: now },
                },
                include: [{ model: SubscriptionPackage, as: 'package' }],
                limit: 500,
            });

            if (expiredSubs.length > 0) {
                logger.info(`[SubscriptionCron] Found ${expiredSubs.length} active subscriptions to expire.`);
                for (const sub of expiredSubs) {
                    await sub.update({
                        status: SubscriptionStatus.EXPIRED,
                        expiryNotified: true,
                        lastNotifiedAt: now,
                    });
                    SubscriptionService.invalidateCache(sub.userId);

                    const pkg = (sub as any).package;
                    const pkgName = pkg?.name || 'VIP';

                    await sendExpiryNotificationAndEvents({
                        userSub: sub,
                        eventType: 'vip_expired',
                        title: 'VIP Subscription Expired ❌',
                        body: `Your ${pkgName} membership has expired. Renew now to continue enjoying VIP benefits.`,
                        remainingHours: 0,
                        isExpired: true,
                    });

                    logger.info(`[SubscriptionCron] Expired subscription ${sub.id} for user ${sub.userId}`);
                }
            }

            // ─────────────────────────────────────────────────────────────────
            // 3. Activate Upcoming Subscriptions Whose Start Date Has Arrived
            // ─────────────────────────────────────────────────────────────────

            const upcomingSubs = await UserSubscription.findAll({
                where: {
                    status: SubscriptionStatus.UPCOMING,
                    startDate: { [Op.lte]: now },
                },
                order: [['startDate', 'ASC']],
                limit: 500,
            });

            if (upcomingSubs.length > 0) {
                const usersToActivate = new Set<string>();

                for (const sub of upcomingSubs) {
                    if (usersToActivate.has(sub.userId)) continue;

                    // Check if they have an active paid subscription
                    const activeSub = await UserSubscription.findOne({
                        where: {
                            userId: sub.userId,
                            status: SubscriptionStatus.ACTIVE,
                            endDate: { [Op.gt]: now },
                        },
                        include: [{ model: SubscriptionPackage, as: 'package', where: { tier: { [Op.ne]: PackageTier.FREE } }, required: true }],
                    });

                    if (activeSub) {
                        // Delay upcoming subscription start to run after activeSub.endDate
                        logger.warn(`[SubscriptionCron] User ${sub.userId} has active sub ${activeSub.id}. Delaying upcoming sub ${sub.id}.`);
                        const newStartDate = new Date(activeSub.endDate);
                        const duration = sub.endDate.getTime() - sub.startDate.getTime();
                        const newEndDate = new Date(newStartDate.getTime() + duration);
                        await sub.update({ startDate: newStartDate, endDate: newEndDate });
                        continue;
                    }

                    // Otherwise, activate this UPCOMING subscription
                    await sub.update({ status: SubscriptionStatus.ACTIVE });
                    SubscriptionService.invalidateCache(sub.userId);
                    usersToActivate.add(sub.userId);

                    const pkg = (sub as any).package;
                    const pkgName = pkg?.name || 'VIP';

                    await sendExpiryNotificationAndEvents({
                        userSub: sub,
                        eventType: 'vip_activated',
                        title: 'VIP Subscription Activated! 🎉',
                        body: `Your ${pkgName} subscription is now active. Enjoy VIP features!`,
                        isExpired: false,
                    });

                    logger.info(`[SubscriptionCron] Activated upcoming subscription ${sub.id} for user ${sub.userId}`);
                }
            }
        } catch (error) {
            logger.error('[SubscriptionCron] Error running subscription cron:', error);
        } finally {
            isSubscriptionCronRunning = false;
        }
        }, 100);
    });
};
