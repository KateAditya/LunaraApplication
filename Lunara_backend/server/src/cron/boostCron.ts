import cron from 'node-cron';
import { Op } from 'sequelize';
import ProfileBoost, { ProfileBoostStatus } from '../models/ProfileBoost';
import { EngagementService } from '../services/engagementService';
import { SubscriptionService } from '../services/subscriptionService';
import { logger } from '../config/logger';

let isBoostCronRunning = false;

export const startBoostCron = () => {
    // Run every minute to check for expired profile boosts
    cron.schedule('* * * * *', () => {
        setTimeout(async () => {
            if (isBoostCronRunning) return;
            isBoostCronRunning = true;
            try {
                const now = new Date();

                const expiredBoosts = await ProfileBoost.findAll({
                    where: {
                        status: ProfileBoostStatus.ACTIVE,
                        expiresAt: { [Op.lte]: now },
                    },
                    limit: 200,
                });

                if (expiredBoosts.length > 0) {
                    logger.info(`[BoostCron] Found ${expiredBoosts.length} profile boosts to expire.`);
                    for (const boost of expiredBoosts) {
                        await boost.update({ status: ProfileBoostStatus.EXPIRED });
                        await EngagementService.logBoostExpired(boost.userId, boost.id);
                        SubscriptionService.invalidateCache(boost.userId);

                        try {
                            const { io } = require('../server');
                            if (io) {
                                io.to(`user_${boost.userId}`).emit('boost_expired', {
                                    boostId: boost.id,
                                    expiresAt: boost.expiresAt.toISOString(),
                                });
                                io.to('live_feed').emit('live_feed_update', {
                                    type: 'profile_boost_expired',
                                    userId: boost.userId,
                                    timestamp: now.toISOString(),
                                });
                            }
                        } catch (_) {}

                        logger.info(`[BoostCron] Expired profile boost ${boost.id} for user ${boost.userId}`);
                    }
                }
            } catch (err) {
                logger.error('[BoostCron] Error running boost cron:', err);
            } finally {
                isBoostCronRunning = false;
            }
        }, 250);
    });
};
