import { Request, Response } from 'express';
import { Op } from 'sequelize';
import { logger } from '../config/logger';
import WalletTransaction from '../models/WalletTransaction';
import WalletPromotionalCampaign from '../models/WalletPromotionalCampaign';
import WalletCashbackRule from '../models/WalletCashbackRule';
import User from '../models/User';
import AuditLog from '../models/AuditLog';
import WalletService from '../services/walletService';

/**
 * GET /api/admin/wallet/config
 * Retrieves global wallet configuration.
 */
export const getWalletConfig = async (_req: Request, res: Response): Promise<void> => {
    try {
        const config = await WalletService.getGlobalConfig();
        res.json({ success: true, data: config });
    } catch (err: any) {
        logger.error('getWalletConfig error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch wallet config', error: err.message });
    }
};

/**
 * PUT /api/admin/wallet/config
 * Updates global wallet configuration.
 */
export const updateWalletConfig = async (req: Request, res: Response): Promise<void> => {
    try {
        const {
            minRechargeAmount,
            maxRechargeAmount,
            suggestedAmounts,
            dailyRechargeLimit,
            monthlyRechargeLimit,
            isWalletActive,
        } = req.body;

        const config = await WalletService.getGlobalConfig();

        if (minRechargeAmount !== undefined) config.minRechargeAmount = Number(minRechargeAmount);
        if (maxRechargeAmount !== undefined) config.maxRechargeAmount = Number(maxRechargeAmount);
        if (suggestedAmounts && Array.isArray(suggestedAmounts)) config.suggestedAmounts = suggestedAmounts.map(Number);
        if (dailyRechargeLimit !== undefined) config.dailyRechargeLimit = Number(dailyRechargeLimit);
        if (monthlyRechargeLimit !== undefined) config.monthlyRechargeLimit = Number(monthlyRechargeLimit);
        if (isWalletActive !== undefined) config.isWalletActive = Boolean(isWalletActive);

        await config.save();

        const adminUserId = (req as any).user?.id || 'admin';
        await AuditLog.logAction({
            userId: adminUserId,
            action: 'Updated Smart Credit Wallet Global Config',
            metadata: { updatedConfig: config.toJSON() },
        });

        res.json({
            success: true,
            message: 'Smart Credit Wallet configuration updated successfully',
            data: config,
        });
    } catch (err: any) {
        logger.error('updateWalletConfig error:', err);
        res.status(500).json({ success: false, message: 'Failed to update wallet config', error: err.message });
    }
};

/**
 * POST /api/admin/wallet/users/:userId/freeze
 */
export const freezeUserWallet = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;
        const { reason } = req.body;

        if (!reason || reason.trim().length < 3) {
            res.status(400).json({ success: false, message: 'Freeze reason is required' });
            return;
        }

        const wallet = await WalletService.getOrCreateWallet(userId);
        wallet.isFrozen = true;
        wallet.frozenReason = reason;
        wallet.frozenAt = new Date();
        await wallet.save();

        const adminUserId = (req as any).user?.id || 'admin';
        await AuditLog.logAction({
            userId: adminUserId,
            action: 'Froze User Smart Wallet',
            metadata: { targetUserId: userId, reason },
        });

        res.json({
            success: true,
            message: `User wallet frozen successfully.`,
            data: wallet,
        });
    } catch (err: any) {
        logger.error('freezeUserWallet error:', err);
        res.status(500).json({ success: false, message: 'Failed to freeze wallet', error: err.message });
    }
};

/**
 * POST /api/admin/wallet/users/:userId/unfreeze
 */
export const unfreezeUserWallet = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;

        const wallet = await WalletService.getOrCreateWallet(userId);
        wallet.isFrozen = false;
        wallet.frozenReason = null;
        wallet.frozenAt = null;
        await wallet.save();

        const adminUserId = (req as any).user?.id || 'admin';
        await AuditLog.logAction({
            userId: adminUserId,
            action: 'Unfroze User Smart Wallet',
            metadata: { targetUserId: userId },
        });

        res.json({
            success: true,
            message: 'User wallet unfrozen successfully.',
            data: wallet,
        });
    } catch (err: any) {
        logger.error('unfreezeUserWallet error:', err);
        res.status(500).json({ success: false, message: 'Failed to unfreeze wallet', error: err.message });
    }
};

/**
 * POST /api/admin/wallet/users/:userId/manual-credit
 */
export const adminManualCredit = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;
        const { amount, reason, creditCategory = 'regular' } = req.body;
        const adminUserId = (req as any).user?.id || 'admin';

        const result = await WalletService.processAdminAdjustment({
            userId,
            adminUserId,
            type: 'credit',
            amount: Number(amount),
            reason,
            creditCategory,
        });

        res.json(result);
    } catch (err: any) {
        logger.error('adminManualCredit error:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to process admin credit' });
    }
};

/**
 * POST /api/admin/wallet/users/:userId/manual-debit
 */
export const adminManualDebit = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;
        const { amount, reason } = req.body;
        const adminUserId = (req as any).user?.id || 'admin';

        const result = await WalletService.processAdminAdjustment({
            userId,
            adminUserId,
            type: 'debit',
            amount: Number(amount),
            reason,
        });

        res.json(result);
    } catch (err: any) {
        logger.error('adminManualDebit error:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to process admin debit' });
    }
};

/**
 * GET /api/admin/wallet/transactions
 * Searches, filters, and exports transaction ledger.
 */
export const getWalletLedger = async (req: Request, res: Response): Promise<void> => {
    try {
        const {
            userId,
            transactionType,
            status,
            search,
            startDate,
            endDate,
            format,
            page = '1',
            limit = '50',
        } = req.query;

        const where: any = {};

        if (userId) where.userId = userId;
        if (transactionType && transactionType !== 'ALL') where.transactionType = transactionType;
        if (status && status !== 'ALL') where.status = status;

        if (startDate || endDate) {
            where.createdAt = {};
            if (startDate) where.createdAt[Op.gte] = new Date(startDate as string);
            if (endDate) where.createdAt[Op.lte] = new Date(endDate as string);
        }

        const pageNum = parseInt(page as string, 10) || 1;
        const limitNum = parseInt(limit as string, 10) || 50;
        const offset = (pageNum - 1) * limitNum;

        let userIncludeWhere: any = undefined;
        if (search) {
            userIncludeWhere = {
                [Op.or]: [
                    { email: { [Op.iLike]: `%${search}%` } },
                    { firstName: { [Op.iLike]: `%${search}%` } },
                    { lastName: { [Op.iLike]: `%${search}%` } },
                ],
            };
        }

        const { count, rows } = await WalletTransaction.findAndCountAll({
            where,
            include: [
                {
                    model: User,
                    as: 'user',
                    attributes: ['id', 'email', 'firstName', 'lastName', 'phone'],
                    where: userIncludeWhere,
                    required: !!userIncludeWhere,
                },
            ],
            order: [['createdAt', 'DESC']],
            limit: format === 'csv' ? 5000 : limitNum,
            offset: format === 'csv' ? 0 : offset,
        });

        // Comprehensive Summary Statistics & Cost Estimation
        const SmartWalletModel = (await import('../models/SmartWallet')).default;

        const totalRecharge = (await WalletTransaction.sum('amount', { where: { transactionType: 'recharge', status: 'success' } })) || 0;
        const totalSpent = (await WalletTransaction.sum('amount', { where: { status: 'success', transactionType: { [Op.in]: ['vip_purchase', 'super_like_purchase', 'boost_purchase', 'booking_payment'] } } })) || 0;
        const totalPromotional = (await WalletTransaction.sum('amount', { where: { transactionType: 'promotional_credit', status: 'success' } })) || 0;
        const totalCashback = (await WalletTransaction.sum('amount', { where: { transactionType: { [Op.in]: ['cashback', 'cashback_credit'] }, status: 'success' } })) || 0;
        const totalRewards = (await WalletTransaction.sum('amount', { where: { transactionType: 'reward_credit', status: 'success' } })) || 0;
        const totalRefunds = (await WalletTransaction.sum('amount', { where: { transactionType: 'refund', status: 'success' } })) || 0;

        const totalLockedDeposits = (await SmartWalletModel.sum('lockedBalance')) || 0;
        const totalAvailablePool = (await SmartWalletModel.sum('balance')) || 0;

        const activeWalletsCount = await SmartWalletModel.count({ where: { isFrozen: false } });
        const frozenWalletsCount = await SmartWalletModel.count({ where: { isFrozen: true } });

        if (format === 'csv') {
            let csv = 'Transaction ID,User ID,User Email,Type,Amount,Opening Bal,Closing Bal,Status,Reference,Created At\n';
            for (const t of rows) {
                const u = (t as any).user;
                csv += `"${t.id}","${t.userId}","${u?.email || ''}","${t.transactionType}","${t.amount}","${t.openingBalance}","${t.closingBalance}","${t.status}","${t.reference || ''}","${t.createdAt}"\n`;
            }
            res.setHeader('Content-Type', 'text/csv');
            res.setHeader('Content-Disposition', `attachment; filename=lunara_wallet_ledger_${Date.now()}.csv`);
            res.send(csv);
            return;
        }

        res.json({
            success: true,
            data: {
                transactions: rows,
                pagination: {
                    total: count,
                    page: pageNum,
                    totalPages: Math.ceil(count / limitNum),
                    limit: limitNum,
                },
                metrics: {
                    totalRecharge: Number(totalRecharge),
                    totalSpent: Number(totalSpent),
                    totalPromotional: Number(totalPromotional),
                    totalCashback: Number(totalCashback),
                    totalRewards: Number(totalRewards),
                    totalRefunds: Number(totalRefunds),
                    totalLockedDeposits: Number(totalLockedDeposits),
                    totalAvailablePool: Number(totalAvailablePool),
                    activeWalletsCount,
                    frozenWalletsCount,
                },
            },
        });
    } catch (err: any) {
        logger.error('getWalletLedger error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch wallet ledger', error: err.message });
    }
};

/**
 * POST /api/admin/wallet/campaigns
 */
export const createPromotionalCampaign = async (req: Request, res: Response): Promise<void> => {
    try {
        const { campaignCode, title, description, creditAmount, expiryDays = 30, maxUses = 1000 } = req.body;

        if (!campaignCode || !title || !creditAmount) {
            res.status(400).json({ success: false, message: 'campaignCode, title, and creditAmount are required' });
            return;
        }

        const campaign = await WalletPromotionalCampaign.create({
            campaignCode: campaignCode.trim().toUpperCase(),
            title,
            description,
            creditAmount: Number(creditAmount),
            expiryDays: Number(expiryDays),
            maxUses: Number(maxUses),
            usedCount: 0,
            isActive: true,
        });

        res.json({ success: true, message: 'Promotional campaign created successfully', data: campaign });
    } catch (err: any) {
        logger.error('createPromotionalCampaign error:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to create campaign' });
    }
};

/**
 * GET /api/admin/wallet/campaigns
 */
export const listPromotionalCampaigns = async (_req: Request, res: Response): Promise<void> => {
    try {
        const campaigns = await WalletPromotionalCampaign.findAll({ order: [['createdAt', 'DESC']] });
        res.json({ success: true, data: campaigns });
    } catch (err: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch campaigns', error: err.message });
    }
};

/**
 * POST /api/admin/wallet/cashback-rules
 */
export const createCashbackRule = async (req: Request, res: Response): Promise<void> => {
    try {
        const { ruleName, triggerType, minSpend = 0, cashbackType = 'percentage', cashbackValue, maxCashback = 500 } = req.body;

        if (!ruleName || !triggerType || cashbackValue === undefined) {
            res.status(400).json({ success: false, message: 'ruleName, triggerType, and cashbackValue are required' });
            return;
        }

        const rule = await WalletCashbackRule.create({
            ruleName,
            triggerType,
            minSpend: Number(minSpend),
            cashbackType,
            cashbackValue: Number(cashbackValue),
            maxCashback: Number(maxCashback),
            isActive: true,
        });

        res.json({ success: true, message: 'Cashback rule created successfully', data: rule });
    } catch (err: any) {
        logger.error('createCashbackRule error:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to create cashback rule' });
    }
};

/**
 * GET /api/admin/wallet/cashback-rules
 */
export const listCashbackRules = async (_req: Request, res: Response): Promise<void> => {
    try {
        const rules = await WalletCashbackRule.findAll({ order: [['createdAt', 'DESC']] });
        res.json({ success: true, data: rules });
    } catch (err: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch cashback rules', error: err.message });
    }
};
