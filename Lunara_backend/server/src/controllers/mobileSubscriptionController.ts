import { Request, Response } from 'express';
import { Op } from 'sequelize';
import SubscriptionPackage from '../models/SubscriptionPackage';
import SubscriptionFeature from '../models/SubscriptionFeature';
import SubscriptionPlanFeature from '../models/SubscriptionPlanFeature';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import SubscriptionTransaction, { TransactionType, TransactionStatus } from '../models/SubscriptionTransaction';
import SubscriptionUsage from '../models/SubscriptionUsage';
import { SubscriptionService } from '../services/subscriptionService';
import { logger } from '../config/logger';

// ─── Helper ───────────────────────────────────────────────────────────────────

function generateInvoiceNumber(): string {
    const ts = Date.now().toString(36).toUpperCase();
    const rand = Math.random().toString(36).substring(2, 6).toUpperCase();
    return `LUN-${ts}-${rand}`;
}

// ─── Plan Listing ─────────────────────────────────────────────────────────────

// @route GET /api/mobile/subscriptions/packages
export const getAvailablePackages = async (_req: Request, res: Response): Promise<void> => {
    try {
        const packages = await SubscriptionPackage.findAll({
            where: { isActive: true },
            order: [['display_order', 'ASC'], ['price', 'ASC']],
        });

        // Attach dynamic features to each package
        const enriched = await Promise.all(packages.map(async (pkg) => {
            const planFeatures = await SubscriptionPlanFeature.findAll({
                where: { packageId: pkg.id, isEnabled: true },
                include: [{ model: SubscriptionFeature, as: 'feature' }],
                order: [[{ model: SubscriptionFeature, as: 'feature' }, 'display_order', 'ASC']],
            });

            const features: Record<string, any> = {};
            if (planFeatures.length > 0) {
                for (const pf of planFeatures) {
                    const feat = (pf as any).feature;
                    if (feat) features[feat.key] = { ...pf.value, name: feat.name, icon: feat.icon };
                } 
            }

            return {
                ...pkg.toJSON(),
                features: Object.keys(features).length > 0 ? features : null,
            };
        }));

        res.status(200).json({ success: true, data: enriched });
    } catch (error: any) {
        logger.error('Error fetching packages:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Current Subscription ─────────────────────────────────────────────────────

// @route GET /api/mobile/subscriptions/current
export const getCurrentSubscription = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;

        const subscription = await UserSubscription.findOne({
            where: {
                userId,
                status: SubscriptionStatus.ACTIVE,
                endDate: { [Op.gt]: new Date() },
            },
            include: [{ model: SubscriptionPackage, as: 'package' }],
            order: [['createdAt', 'DESC']],
        });

        // Get feature summary
        const featureSummary = await SubscriptionService.getUserFeatureSummary(userId);

        // Get usage stats
        const usageRecords = await SubscriptionUsage.findAll({
            where: { userId, period: 'daily' },
        });
        const usageMap: Record<string, number> = {};
        for (const u of usageRecords) {
            usageMap[u.featureKey] = u.used;
        }

        // Compute remaining days
        let remainingDays = 0;
        if (subscription) {
            const now = new Date();
            const end = new Date(subscription.endDate);
            remainingDays = Math.max(0, Math.ceil((end.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)));
        }

        res.status(200).json({
            success: true,
            data: {
                subscription: subscription || null,
                remainingDays,
                features: featureSummary,
                usage: usageMap,
            },
        });
    } catch (error: any) {
        logger.error('Error fetching subscription:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Purchase ─────────────────────────────────────────────────────────────────

// @route POST /api/mobile/subscriptions/purchase
export const purchaseSubscription = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;
        const { packageId, gatewayOrderId, gatewayPaymentId, paymentMethod } = req.body;

        const pkg = await SubscriptionPackage.findByPk(packageId);
        if (!pkg || !pkg.isActive) {
            res.status(404).json({ success: false, message: 'Package not found or inactive' });
            return;
        }

        // Determine transaction type
        const existingSub = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE },
        });
        const txnType = existingSub ? TransactionType.UPGRADE : TransactionType.PURCHASE;

        // Expire current subscriptions
        await UserSubscription.update(
            { status: SubscriptionStatus.EXPIRED },
            { where: { userId, status: SubscriptionStatus.ACTIVE } }
        );

        // Create new subscription
        const startDate = new Date();
        const endDate = new Date();
        endDate.setDate(endDate.getDate() + pkg.durationDays);

        const newSub = await UserSubscription.create({
            userId,
            packageId: pkg.id,
            status: SubscriptionStatus.ACTIVE,
            startDate,
            endDate,
            superlikesRemaining: pkg.superlikesPerCycle,
            boostsRemaining: pkg.boostsPerCycle,
        });

        // Record transaction
        const transaction = await SubscriptionTransaction.create({
            userId,
            packageId: pkg.id,
            type: txnType,
            amount: pkg.price,
            currency: (pkg as any).currency || 'INR',
            paymentMethod: paymentMethod || 'razorpay',
            paymentGateway: 'razorpay',
            gatewayOrderId: gatewayOrderId || null,
            gatewayPaymentId: gatewayPaymentId || null,
            status: TransactionStatus.SUCCESS,
            invoiceNumber: generateInvoiceNumber(),
            metadata: { packageName: pkg.name, packageTier: pkg.tier },
        });

        // Invalidate permission cache
        SubscriptionService.invalidateCache(userId);

        res.status(201).json({
            success: true,
            data: { subscription: newSub, transaction },
            message: 'Subscription activated successfully',
        });
    } catch (error: any) {
        logger.error('Error purchasing subscription:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Renew ────────────────────────────────────────────────────────────────────

// @route POST /api/mobile/subscriptions/renew
export const renewSubscription = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;
        const { packageId, gatewayOrderId, gatewayPaymentId, paymentMethod } = req.body;

        // Default to same package if no packageId given
        let pkg: SubscriptionPackage | null = null;
        if (packageId) {
            pkg = await SubscriptionPackage.findByPk(packageId);
        } else {
            const current = await UserSubscription.findOne({
                where: { userId },
                order: [['createdAt', 'DESC']],
                include: [{ model: SubscriptionPackage, as: 'package' }],
            });
            pkg = current ? (current as any).package : null;
        }

        if (!pkg || !pkg.isActive) {
            res.status(404).json({ success: false, message: 'Package not found or inactive' });
            return;
        }

        // Extend or create active subscription
        const existingSub = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE, packageId: pkg.id },
        });

        let subscription;
        if (existingSub) {
            const newEnd = new Date(existingSub.endDate);
            newEnd.setDate(newEnd.getDate() + pkg.durationDays);
            await existingSub.update({
                endDate: newEnd,
                superlikesRemaining: pkg.superlikesPerCycle,
                boostsRemaining: pkg.boostsPerCycle,
            });
            subscription = existingSub;
        } else {
            // Re-activate
            await UserSubscription.update(
                { status: SubscriptionStatus.EXPIRED },
                { where: { userId, status: SubscriptionStatus.ACTIVE } }
            );
            const startDate = new Date();
            const endDate = new Date();
            endDate.setDate(endDate.getDate() + pkg.durationDays);
            subscription = await UserSubscription.create({
                userId,
                packageId: pkg.id,
                status: SubscriptionStatus.ACTIVE,
                startDate,
                endDate,
                superlikesRemaining: pkg.superlikesPerCycle,
                boostsRemaining: pkg.boostsPerCycle,
            });
        }

        // Record transaction
        const transaction = await SubscriptionTransaction.create({
            userId,
            packageId: pkg.id,
            type: TransactionType.RENEW,
            amount: pkg.price,
            paymentMethod: paymentMethod || 'razorpay',
            paymentGateway: 'razorpay',
            gatewayOrderId: gatewayOrderId || null,
            gatewayPaymentId: gatewayPaymentId || null,
            status: TransactionStatus.SUCCESS,
            invoiceNumber: generateInvoiceNumber(),
            metadata: { packageName: pkg.name },
        });

        SubscriptionService.invalidateCache(userId);

        res.status(200).json({
            success: true,
            data: { subscription, transaction },
            message: 'Subscription renewed successfully',
        });
    } catch (error: any) {
        logger.error('Error renewing subscription:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Cancel ───────────────────────────────────────────────────────────────────

// @route POST /api/mobile/subscriptions/cancel
export const cancelSubscription = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;

        const sub = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE },
            include: [{ model: SubscriptionPackage, as: 'package' }],
        });

        if (!sub) {
            res.status(404).json({ success: false, message: 'No active subscription found' });
            return;
        }

        await sub.update({ status: SubscriptionStatus.CANCELLED });

        // Record cancellation event
        await SubscriptionTransaction.create({
            userId,
            packageId: sub.packageId,
            type: TransactionType.CANCEL,
            amount: 0,
            status: TransactionStatus.CANCELLED,
            invoiceNumber: generateInvoiceNumber(),
            metadata: { reason: req.body.reason || 'User requested cancellation' },
        });

        SubscriptionService.invalidateCache(userId);

        res.status(200).json({
            success: true,
            message: 'Subscription cancelled. You will retain access until expiry.',
        });
    } catch (error: any) {
        logger.error('Error cancelling subscription:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Purchase History ─────────────────────────────────────────────────────────

// @route GET /api/mobile/subscriptions/history
export const getSubscriptionHistory = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;
        const page = parseInt(req.query.page as string) || 1;
        const limit = parseInt(req.query.limit as string) || 10;
        const offset = (page - 1) * limit;

        const { count, rows } = await SubscriptionTransaction.findAndCountAll({
            where: { userId },
            include: [{ model: SubscriptionPackage, as: 'package', attributes: ['id', 'name', 'tier'] }],
            order: [['created_at', 'DESC']],
            limit,
            offset,
        });

        res.status(200).json({
            success: true,
            data: {
                transactions: rows,
                pagination: { page, limit, total: count, totalPages: Math.ceil(count / limit) },
            },
        });
    } catch (error: any) {
        logger.error('Error fetching subscription history:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Feature Access Check ─────────────────────────────────────────────────────

// @route GET /api/mobile/subscriptions/check/:featureKey
export const checkFeatureAccess = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;
        const { featureKey } = req.params;

        const [hasAccess, limit, remaining] = await Promise.all([
            SubscriptionService.hasAccess(userId, featureKey),
            SubscriptionService.getLimit(userId, featureKey),
            SubscriptionService.getRemainingUsage(userId, featureKey),
        ]);

        res.status(200).json({
            success: true,
            data: { featureKey, hasAccess, limit, remaining },
        });
    } catch (error: any) {
        logger.error('Error checking feature access:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Boost Purchase ───────────────────────────────────────────────────────────

// @route POST /api/mobile/subscriptions/purchase-boost
export const purchaseBoost = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;
        const { boostCount } = req.body;

        if (![1, 2, 3, 5].includes(boostCount)) {
            res.status(400).json({ success: false, message: 'Invalid boost count' });
            return;
        }

        const sub = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE },
            order: [['createdAt', 'DESC']],
        });

        if (!sub) {
            res.status(400).json({ success: false, message: 'Active subscription required' });
            return;
        }

        const boostPrice = boostCount * 49; // ₹49 per boost
        await sub.update({ boostsRemaining: sub.boostsRemaining + boostCount });

        await SubscriptionTransaction.create({
            userId,
            packageId: sub.packageId,
            type: TransactionType.BOOST,
            amount: boostPrice,
            status: TransactionStatus.SUCCESS,
            invoiceNumber: generateInvoiceNumber(),
            metadata: { boostCount },
        });

        SubscriptionService.invalidateCache(userId);

        res.status(200).json({
            success: true,
            message: `${boostCount} boost(s) added successfully`,
            data: { boostsRemaining: sub.boostsRemaining + boostCount },
        });
    } catch (error: any) {
        logger.error('Error purchasing boosts:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};
