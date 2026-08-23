import { Request, Response } from 'express';
import { ReliabilityEngine } from '../services/reliabilityEngine';
import ReliabilityHistory from '../models/ReliabilityHistory';
import User from '../models/User';
import { logger } from '../config/logger';

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/user/reliability-summary
// Returns user reliability score, level badge, attendance rate, verified flags & streak
// ─────────────────────────────────────────────────────────────────────────────
export const getReliabilitySummary = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req.query.userId || req.body.userId) as string;
        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

        const summary = await ReliabilityEngine.getUserSummary(userId);
        if (!summary) {
            res.status(404).json({ success: false, message: 'User not found' });
            return;
        }

        const history = await ReliabilityHistory.findAll({
            where: { userId },
            order: [['createdAt', 'DESC']],
            limit: 20,
        });

        res.json({
            success: true,
            data: {
                summary,
                history,
            }
        });
    } catch (err: any) {
        logger.error('getReliabilitySummary error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch reliability summary', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/reliability/leaderboard
// Admin Leaderboard: Top reliable users and high risk users
// ─────────────────────────────────────────────────────────────────────────────
export const getReliabilityLeaderboard = async (_req: Request, res: Response): Promise<void> => {
    try {
        const topReliableUsers = await User.findAll({
            attributes: ['id', 'firstName', 'lastName', 'email', 'reliabilityScore', 'rewardPoints', 'noShowCount'],
            order: [['reliabilityScore', 'DESC']],
            limit: 20,
        });

        const highRiskUsers = await User.findAll({
            attributes: ['id', 'firstName', 'lastName', 'email', 'reliabilityScore', 'noShowCount', 'isAutoblocked'],
            where: {
                reliabilityScore: { [require('sequelize').Op.lt]: 50 }
            },
            order: [['reliabilityScore', 'ASC']],
            limit: 20,
        });

        res.json({
            success: true,
            data: {
                topReliableUsers,
                highRiskUsers,
            }
        });
    } catch (err: any) {
        logger.error('getReliabilityLeaderboard error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch leaderboard', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/user/reliability-history
// ─────────────────────────────────────────────────────────────────────────────
export const getReliabilityHistory = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user?.id || (req.query.userId as string);
        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

        const page = Math.max(1, parseInt(req.query.page as string) || 1);
        const limit = Math.min(100, parseInt(req.query.limit as string) || 20);
        const offset = (page - 1) * limit;

        const { count, rows } = await ReliabilityHistory.findAndCountAll({
            where: { userId },
            order: [['createdAt', 'DESC']],
            limit,
            offset,
        });

        res.json({
            success: true,
            data: {
                history: rows,
                pagination: {
                    page,
                    limit,
                    total: count,
                    totalPages: Math.ceil(count / limit),
                },
            },
        });
    } catch (err: any) {
        logger.error('getReliabilityHistory error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch reliability history', error: err.message });
    }
};
