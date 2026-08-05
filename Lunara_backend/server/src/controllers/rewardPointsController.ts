import { Request, Response } from 'express';
import { RewardPointsService } from '../services/rewardPointsService';
import RewardPointLedger from '../models/RewardPointLedger';
import User from '../models/User';
import { logger } from '../config/logger';

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/rewards/balance
// Returns user reward points balance & full transaction ledger
// ─────────────────────────────────────────────────────────────────────────────
export const getRewardBalance = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req.query.userId || req.body.userId) as string;
        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

        const user = await User.findByPk(userId);
        if (!user) {
            res.status(404).json({ success: false, message: 'User not found' });
            return;
        }

        const ledger = await RewardPointLedger.findAll({
            where: { userId },
            order: [['createdAt', 'DESC']],
            limit: 50,
        });

        res.json({
            success: true,
            data: {
                userId,
                rewardPoints: user.rewardPoints || 0,
                loginStreakDays: user.loginStreakDays || 0,
                ledger,
            }
        });
    } catch (err: any) {
        logger.error('getRewardBalance error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch reward balance', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/rewards/claim-daily
// Claims daily login reward points (+10 Pts)
// ─────────────────────────────────────────────────────────────────────────────
export const claimDailyReward = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.body;
        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

        const result = await RewardPointsService.checkDailyLoginStreak(userId);

        res.json({
            success: result.claimed,
            message: result.claimed
                ? `🎉 Claimed ${result.pointsEarned} Lunara Reward Points! (Streak: ${result.streakDays} Days)`
                : 'Already claimed daily reward for today.',
            data: result,
        });
    } catch (err: any) {
        logger.error('claimDailyReward error:', err);
        res.status(500).json({ success: false, message: 'Failed to claim daily reward', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/rewards/redeem
// Redeems reward points for Profile Boost, Super Likes or VIP Discounts
// ─────────────────────────────────────────────────────────────────────────────
export const redeemRewardPoints = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId, item, points } = req.body;
        if (!userId || !item || !points) {
            res.status(400).json({ success: false, message: 'userId, item, and points are required' });
            return;
        }

        const redeemResult = await RewardPointsService.redeemPoints({
            userId,
            points: Number(points),
            reason: `Redeemed for ${item}`,
            reference: `REDEEM_${item.toUpperCase()}_${Date.now()}`,
        });

        if (!redeemResult.success) {
            res.status(400).json({ success: false, message: redeemResult.message });
            return;
        }

        res.json({
            success: true,
            message: `🎉 Successfully redeemed ${points} points for ${item}!`,
            data: redeemResult,
        });
    } catch (err: any) {
        logger.error('redeemRewardPoints error:', err);
        res.status(500).json({ success: false, message: 'Failed to redeem reward points', error: err.message });
    }
};
