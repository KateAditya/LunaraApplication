import cron from 'node-cron';
import { Op } from 'sequelize';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import { logger } from '../config/logger';
import { SubscriptionService } from '../services/subscriptionService';

export const startSubscriptionCron = () => {
    // Run every minute to accurately activate/expire subscriptions
    cron.schedule('* * * * *', async () => {
        try {
            const now = new Date();

            // 1. Mark expired active subscriptions as EXPIRED
            const expiredSubs = await UserSubscription.findAll({
                where: {
                    status: SubscriptionStatus.ACTIVE,
                    endDate: { [Op.lte]: now }
                }
            });

            if (expiredSubs.length > 0) {
                logger.info(`[SubscriptionCron] Found ${expiredSubs.length} active subscriptions to expire.`);
                for (const sub of expiredSubs) {
                    await sub.update({ status: SubscriptionStatus.EXPIRED });
                    SubscriptionService.invalidateCache(sub.userId);
                    logger.info(`[SubscriptionCron] Expired subscription ${sub.id} for user ${sub.userId}`);
                }
            }

            // 2. Activate upcoming subscriptions whose start date has arrived
            // We find any UPCOMING subscription where startDate <= now
            const upcomingSubs = await UserSubscription.findAll({
                where: {
                    status: SubscriptionStatus.UPCOMING,
                    startDate: { [Op.lte]: now }
                },
                order: [['startDate', 'ASC']]
            });

            if (upcomingSubs.length > 0) {
                // Group by user to ensure we only activate one per user
                const usersToActivate = new Set<string>();
                
                for (const sub of upcomingSubs) {
                    if (usersToActivate.has(sub.userId)) continue;

                    // Check if they have an active subscription
                    const activeSub = await UserSubscription.findOne({
                        where: {
                            userId: sub.userId,
                            status: SubscriptionStatus.ACTIVE,
                            endDate: { [Op.gt]: now }
                        }
                    });

                    if (activeSub) {
                        // User still has an active subscription (overlap)
                        // Postpone this UPCOMING subscription's start date
                        logger.warn(`[SubscriptionCron] User ${sub.userId} has an active sub ${activeSub.id} but UPCOMING sub ${sub.id} is due. Delaying.`);
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
                    logger.info(`[SubscriptionCron] Activated upcoming subscription ${sub.id} for user ${sub.userId}`);
                }
            }
        } catch (error) {
            logger.error('[SubscriptionCron] Error running subscription cron:', error);
        }
    });
};
