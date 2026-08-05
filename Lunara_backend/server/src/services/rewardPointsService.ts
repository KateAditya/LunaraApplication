import User from '../models/User';
import RewardPointLedger, { RewardPointType } from '../models/RewardPointLedger';
import AuditLog from '../models/AuditLog';
import { logger } from '../config/logger';

export class RewardPointsService {
    /**
     * Award points to user and log in RewardPointLedger.
     */
    public static async awardPoints(params: {
        userId: string;
        points: number;
        reason: string;
        reference?: string;
        metadata?: object;
    }): Promise<{ newBalance: number; pointsEarned: number }> {
        try {
            const { userId, points, reason, reference, metadata } = params;
            if (points <= 0) return { newBalance: 0, pointsEarned: 0 };

            const user = await User.findByPk(userId);
            if (!user) throw new Error(`User ${userId} not found`);

            const oldBalance = user.rewardPoints || 0;
            const newBalance = oldBalance + points;

            await user.update({ rewardPoints: newBalance });

            await RewardPointLedger.create({
                userId,
                points,
                type: RewardPointType.EARN,
                balanceAfter: newBalance,
                reason,
                reference,
                metadata,
            });

            await AuditLog.logAction({
                userId,
                action: `Reward Points Awarded (+${points})`,
                metadata: { oldBalance, newBalance, points, reason, reference }
            });

            logger.info(`[RewardPointsService] Awarded ${points} points to ${userId}. New balance: ${newBalance}`);

            return { newBalance, pointsEarned: points };
        } catch (err: any) {
            logger.error('[RewardPointsService] Error awarding points:', err);
            return { newBalance: 0, pointsEarned: 0 };
        }
    }

    /**
     * Redeem points with balance validation.
     */
    public static async redeemPoints(params: {
        userId: string;
        points: number;
        reason: string;
        reference?: string;
        metadata?: object;
    }): Promise<{ success: boolean; newBalance: number; message: string }> {
        try {
            const { userId, points, reason, reference, metadata } = params;
            if (points <= 0) return { success: false, newBalance: 0, message: 'Invalid point amount' };

            const user = await User.findByPk(userId);
            if (!user) return { success: false, newBalance: 0, message: 'User not found' };

            const currentBalance = user.rewardPoints || 0;
            if (currentBalance < points) {
                return {
                    success: false,
                    newBalance: currentBalance,
                    message: `Insufficient reward points balance. Required: ${points}, Available: ${currentBalance}`
                };
            }

            const newBalance = currentBalance - points;
            await user.update({ rewardPoints: newBalance });

            await RewardPointLedger.create({
                userId,
                points,
                type: RewardPointType.REDEEM,
                balanceAfter: newBalance,
                reason,
                reference,
                metadata,
            });

            await AuditLog.logAction({
                userId,
                action: `Reward Points Redeemed (-${points})`,
                metadata: { currentBalance, newBalance, points, reason, reference }
            });

            logger.info(`[RewardPointsService] Redeemed ${points} points for ${userId}. Remaining balance: ${newBalance}`);

            return { success: true, newBalance, message: `Successfully redeemed ${points} points!` };
        } catch (err: any) {
            logger.error('[RewardPointsService] Error redeeming points:', err);
            return { success: false, newBalance: 0, message: err.message };
        }
    }

    /**
     * Claims Daily Login reward (+10 Pts) and 7-day weekly streak bonus (+100 Pts).
     */
    public static async checkDailyLoginStreak(userId: string): Promise<{ claimed: boolean; streakDays: number; pointsEarned: number }> {
        try {
            const user = await User.findByPk(userId);
            if (!user) return { claimed: false, streakDays: 0, pointsEarned: 0 };

            const today = new Date();
            today.setHours(0, 0, 0, 0);

            const lastDate = user.lastLoginStreakDate ? new Date(user.lastLoginStreakDate) : null;
            if (lastDate) {
                lastDate.setHours(0, 0, 0, 0);
            }

            // Already claimed today
            if (lastDate && lastDate.getTime() === today.getTime()) {
                return { claimed: false, streakDays: user.loginStreakDays || 0, pointsEarned: 0 };
            }

            let streakDays = user.loginStreakDays || 0;
            const yesterday = new Date(today.getTime() - 24 * 60 * 60 * 1000);

            if (lastDate && lastDate.getTime() === yesterday.getTime()) {
                streakDays += 1;
            } else {
                streakDays = 1; // Reset streak if missed a day
            }

            let pointsEarned = 10; // Daily login reward
            let reason = `Daily Login Bonus (Day ${streakDays})`;

            // 7-Day Streak Bonus (+100 Pts)
            if (streakDays % 7 === 0) {
                pointsEarned += 100;
                reason = `🔥 7-Day Weekly Streak Bonus! (Day ${streakDays})`;
            }

            await user.update({
                loginStreakDays: streakDays,
                lastLoginStreakDate: today,
            });

            await this.awardPoints({
                userId,
                points: pointsEarned,
                reason,
                reference: `STREAK_${today.toISOString().split('T')[0]}`,
            });

            return { claimed: true, streakDays, pointsEarned };
        } catch (err: any) {
            logger.error('[RewardPointsService] Error processing daily login streak:', err);
            return { claimed: false, streakDays: 0, pointsEarned: 0 };
        }
    }
}
