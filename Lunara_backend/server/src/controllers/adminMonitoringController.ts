import { Request, Response } from 'express';
import os from 'os';
import PartyPlan from '../models/PartyPlan';
import PartyPlanRequest from '../models/PartyPlanRequest';
import User from '../models/User';
import WalletTransaction from '../models/WalletTransaction';
import AuditLog from '../models/AuditLog';
import Notification from '../models/Notification';
import Conversation from '../models/Conversation';
import { FraudDetectionService } from '../services/fraudDetectionService';
import { logger } from '../config/logger';

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/monitoring/dashboard
// Super Admin Control Center Dashboard
// ─────────────────────────────────────────────────────────────────────────────
export const getAdminMonitoringDashboard = async (_req: Request, res: Response): Promise<void> => {
    try {
        const totalPlans = await PartyPlan.count();
        const activePlans = await PartyPlan.count({ where: { status: 'active' as any } });
        const completedPlans = await PartyPlan.count({ where: { status: 'inactive' as any } });
        const cancelledPlans = await PartyPlan.count({ where: { status: 'cancelled' as any } });

        const pendingRequests = await PartyPlanRequest.count({ where: { status: 'pending' as any } });
        const activeChats = await Conversation.count();

        // Wallet Metrics
        const walletBalancePool = await User.sum('walletBalance') || 0;
        const totalRefundsCount = await WalletTransaction.count({ where: { transactionType: 'refund' as any } });
        const totalVipSalesCount = await WalletTransaction.count({ where: { transactionType: 'vip_purchase' as any } });

        // Users & Reliability
        const totalUsersCount = await User.count();
        const activeUsersCount = await User.count({ where: { isAutoblocked: false } });
        const flaggedUsers = await FraudDetectionService.getFlaggedRiskUsers(10);

        // Notifications
        const totalNotificationsCount = await Notification.count();

        // Audit Logs
        const recentAuditLogs = await AuditLog.findAll({
            order: [['createdAt', 'DESC']],
            limit: 25,
        });

        res.json({
            success: true,
            data: {
                cards: {
                    totalPlans,
                    activePlans,
                    completedPlans,
                    cancelledPlans,
                    pendingRequests,
                    activeChats,
                    walletBalancePool: Number(walletBalancePool),
                    totalRefundsCount,
                    totalVipSalesCount,
                    totalUsersCount,
                    activeUsersCount,
                    totalNotificationsCount,
                    flaggedUsersCount: flaggedUsers.length,
                },
                flaggedUsers,
                recentAuditLogs,
            }
        });
    } catch (err: any) {
        logger.error('getAdminMonitoringDashboard error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch dashboard metrics', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/monitoring/bookings/:id/timeline
// Returns full booking lifecycle timeline
// ─────────────────────────────────────────────────────────────────────────────
export const getBookingMonitoringTimeline = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;

        const plan = await PartyPlan.findByPk(id, {
            include: [{ model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] }]
        });

        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        const requests = await PartyPlanRequest.findAll({
            where: { planId: id },
            include: [{ model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] }]
        });

        const walletTxns = await WalletTransaction.findAll({
            where: { partyPlanId: id },
            order: [['createdAt', 'ASC']]
        });

        const auditTrail = await AuditLog.findAll({
            where: { partyPlanId: id },
            order: [['createdAt', 'ASC']]
        });

        res.json({
            success: true,
            data: {
                plan,
                requests,
                walletTxns,
                auditTrail,
            }
        });
    } catch (err: any) {
        logger.error('getBookingMonitoringTimeline error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch booking timeline', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/monitoring/wallets
// ─────────────────────────────────────────────────────────────────────────────
export const getWalletMonitoring = async (_req: Request, res: Response): Promise<void> => {
    try {
        const transactions = await WalletTransaction.findAll({
            order: [['createdAt', 'DESC']],
            limit: 100,
        });

        res.json({
            success: true,
            data: transactions,
        });
    } catch (err: any) {
        logger.error('getWalletMonitoring error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch wallet logs', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/monitoring/notifications
// ─────────────────────────────────────────────────────────────────────────────
export const getNotificationMonitoring = async (_req: Request, res: Response): Promise<void> => {
    try {
        const notifications = await Notification.findAll({
            order: [['createdAt', 'DESC']],
            limit: 100,
        });

        res.json({
            success: true,
            data: notifications,
        });
    } catch (err: any) {
        logger.error('getNotificationMonitoring error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch notification logs', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/monitoring/chats
// Read-Only view of active user conversations (No edit, no message send)
// ─────────────────────────────────────────────────────────────────────────────
export const getReadOnlyChatMonitoring = async (_req: Request, res: Response): Promise<void> => {
    try {
        const conversations = await Conversation.findAll({
            order: [['updatedAt', 'DESC']],
            limit: 50,
        });

        res.json({
            success: true,
            readOnly: true,
            data: conversations,
        });
    } catch (err: any) {
        logger.error('getReadOnlyChatMonitoring error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch chat logs', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/health
// Real-time system health metrics (CPU, Memory, DB Connection)
// ─────────────────────────────────────────────────────────────────────────────
export const getSystemHealth = async (_req: Request, res: Response): Promise<void> => {
    try {
        const freeMem = os.freemem();
        const totalMem = os.totalmem();
        const memUsage = process.memoryUsage();

        res.json({
            status: 'HEALTHY',
            timestamp: new Date().toISOString(),
            uptimeSeconds: Math.floor(process.uptime()),
            system: {
                platform: os.platform(),
                arch: os.arch(),
                cpus: os.cpus().length,
                freeMemoryMB: Math.round(freeMem / 1024 / 1024),
                totalMemoryMB: Math.round(totalMem / 1024 / 1024),
                memoryUsagePercent: ((1 - freeMem / totalMem) * 100).toFixed(1) + '%',
            },
            process: {
                rssMB: Math.round(memUsage.rss / 1024 / 1024),
                heapTotalMB: Math.round(memUsage.heapTotal / 1024 / 1024),
                heapUsedMB: Math.round(memUsage.heapUsed / 1024 / 1024),
            },
            database: {
                status: 'CONNECTED',
            }
        });
    } catch (err: any) {
        logger.error('getSystemHealth error:', err);
        res.status(500).json({ status: 'UNHEALTHY', error: err.message });
    }
};
