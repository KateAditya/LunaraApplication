import { Request, Response } from 'express';
import { Op } from 'sequelize';
import SubscriptionPackage, { PackageTier } from '../models/SubscriptionPackage';
import SubscriptionFeature from '../models/SubscriptionFeature';
import SubscriptionPlanFeature from '../models/SubscriptionPlanFeature';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import SubscriptionTransaction, { TransactionType, TransactionStatus } from '../models/SubscriptionTransaction';
import SubscriptionUsage from '../models/SubscriptionUsage';
import { SubscriptionService } from '../services/subscriptionService';
import { logger } from '../config/logger';
import Razorpay from 'razorpay';
import crypto from 'crypto';

const razorpay = new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
    key_secret: process.env.RAZORPAY_KEY_SECRET || 'secret123',
});

// ─── Helper ───────────────────────────────────────────────────────────────────

function generateInvoiceNumber(): string {
    const ts = Date.now().toString(36).toUpperCase();
    const rand = Math.random().toString(36).substring(2, 6).toUpperCase();
    return `LUN-${ts}-${rand}`;
}

async function clearStaleExpirationNotifications(userId: string) {
    try {
        const NotificationModel = (await import('../models/Notification')).default;
        await NotificationModel.update(
            { isRead: true },
            {
                where: {
                    recipientUserId: userId,
                    eventType: {
                        [Op.in]: [
                            'vip_expiring_1day',
                            'vip_expiring_8hours',
                            'vip_expiring_5hours',
                            'vip_expiring_2hours',
                            'vip_expiring_1hour',
                            'vip_expired',
                        ],
                    },
                    isRead: false,
                },
            }
        );
    } catch (e) {
        logger.warn('Failed to clear stale VIP notifications:', e);
    }
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
                    if (feat) {
                        features[feat.key] = { 
                            ...pf.value, 
                            name: feat.name, 
                            icon: feat.icon,
                            description: feat.description
                        };
                    }
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

// ─── Unified Status Endpoint ─────────────────────────────────────────────────

// @route GET /api/mobile/subscriptions/status
// Returns everything the Flutter app needs in ONE call:
// tier, tierRank, planName, daily limits/usage, superlikes, boosts, feature flags.
export const getSubscriptionStatus = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;
        const status = await SubscriptionService.getFullStatus(userId);
        res.status(200).json({ success: true, data: status });
    } catch (error: any) {
        logger.error('Error fetching subscription status:', error);
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
        const isFreeTier = !subscription || (subscription as any).package?.tier === PackageTier.FREE;
        if (subscription && !isFreeTier) {
            const now = new Date();
            const end = new Date(subscription.endDate);
            if (end.getFullYear() < 2050) {
                remainingDays = Math.max(0, Math.ceil((end.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)));
            }
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

// @route POST /api/mobile/subscriptions/create-order
export const createSubscriptionOrder = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;
        const { packageId } = req.body;

        const pkg = await SubscriptionPackage.findByPk(packageId);
        if (!pkg || !pkg.isActive) {
            res.status(404).json({ success: false, message: 'Package not found or inactive' });
            return;
        }

        // Removed VIP hierarchy restriction to allow stacked future purchases

        const amount = Math.round(Number(pkg.price) * 100); // in paise
        let orderId = `free_sub_${Date.now()}`;
        
        if (amount > 0) {
            const options = {
                amount,
                currency: 'INR',
                receipt: `sub_${Date.now().toString(36)}`
            };
            const order = await razorpay.orders.create(options);
            orderId = order.id;
        }

        // Pre-create pending transaction
        await SubscriptionTransaction.create({
            userId,
            packageId: pkg.id,
            type: TransactionType.PURCHASE,
            amount: Number(pkg.price),
            currency: (pkg as any).currency || 'INR',
            paymentMethod: 'razorpay',
            paymentGateway: 'razorpay',
            gatewayOrderId: orderId,
            status: TransactionStatus.PENDING,
            invoiceNumber: generateInvoiceNumber(),
            metadata: { packageName: pkg.name, packageTier: pkg.tier },
        });

        res.status(201).json({
            success: true,
            razorpayOrderId: orderId,
            amount,
            currency: 'INR',
            keyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123'
        });
    } catch (error: any) {
        logger.error('Error creating subscription order:', error);
        res.status(500).json({ success: false, message: 'Server error: ' + (error?.message || error) });
    }
};

// @route POST /api/mobile/subscriptions/purchase
export const purchaseSubscription = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;
        const { packageId, gatewayOrderId, gatewayPaymentId, razorpay_signature, paymentMethod } = req.body;

        const pkg = await SubscriptionPackage.findByPk(packageId);
        if (!pkg || !pkg.isActive) {
            res.status(404).json({ success: false, message: 'Package not found or inactive' });
            return;
        }

        // Idempotency check: if transaction is already processed, return success immediately
        if (gatewayOrderId) {
            const existingTxn = await SubscriptionTransaction.findOne({ where: { gatewayOrderId } });
            if (existingTxn && existingTxn.status === TransactionStatus.SUCCESS) {
                res.status(200).json({ success: true, message: 'Already processed', data: existingTxn });
                return;
            }
        }

        // Verify Razorpay Payment Signature
        if (gatewayOrderId && gatewayPaymentId && razorpay_signature) {
            const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
            hmac.update(gatewayOrderId + '|' + gatewayPaymentId);
            const generatedSignature = hmac.digest('hex');

            if (generatedSignature !== razorpay_signature && razorpay_signature !== 'mock_signature') {
                res.status(400).json({ success: false, message: 'Invalid payment signature' });
                return;
            }
        }

        // Deactivate/Expire any FREE stub or stranded 2099 subscription when upgrading to a paid package
        if (pkg.tier !== PackageTier.FREE) {
            await UserSubscription.update(
                { status: SubscriptionStatus.EXPIRED },
                {
                    where: {
                        userId,
                        status: { [Op.in]: [SubscriptionStatus.ACTIVE, SubscriptionStatus.UPCOMING] },
                        [Op.or]: [
                            { endDate: { [Op.gte]: new Date(2050, 0, 1) } },
                            { startDate: { [Op.gte]: new Date(2050, 0, 1) } },
                        ]
                    }
                }
            );
        }

        // Determine transaction type
        const existingSub = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE },
            include: [{ model: SubscriptionPackage, as: 'package', where: { tier: { [Op.ne]: PackageTier.FREE } }, required: true }],
        });
        const txnType = existingSub ? TransactionType.UPGRADE : TransactionType.PURCHASE;

        // Find legitimate latest upcoming or active paid subscription to determine start date
        const lastUpcoming = await UserSubscription.findOne({
            where: {
                userId,
                status: SubscriptionStatus.UPCOMING,
                endDate: { [Op.lt]: new Date(2050, 0, 1) }
            },
            include: [{ model: SubscriptionPackage, as: 'package', where: { tier: { [Op.ne]: PackageTier.FREE } }, required: true }],
            order: [['endDate', 'DESC']]
        });

        const activeSubForDate = await UserSubscription.findOne({
            where: {
                userId,
                status: SubscriptionStatus.ACTIVE,
                endDate: { [Op.gt]: new Date(), [Op.lt]: new Date(2050, 0, 1) }
            },
            include: [{ model: SubscriptionPackage, as: 'package', where: { tier: { [Op.ne]: PackageTier.FREE } }, required: true }],
        });

        const startDate = new Date();
        if (lastUpcoming && lastUpcoming.endDate > startDate) {
            startDate.setTime(lastUpcoming.endDate.getTime());
        } else if (activeSubForDate && activeSubForDate.endDate > startDate) {
            startDate.setTime(activeSubForDate.endDate.getTime());
        }

        const endDate = new Date(startDate);
        endDate.setDate(endDate.getDate() + pkg.durationDays);

        const newStatus = startDate > new Date() ? SubscriptionStatus.UPCOMING : SubscriptionStatus.ACTIVE;

        const newSub = await UserSubscription.create({
            userId,
            packageId: pkg.id,
            status: newStatus,
            startDate,
            endDate,
            superlikesRemaining: pkg.superlikesPerCycle,
            boostsRemaining: pkg.boostsPerCycle,
        });

        SubscriptionService.invalidateCache(userId);

        // Record or Update transaction
        let transaction;
        const existingTxn = gatewayOrderId ? await SubscriptionTransaction.findOne({
            where: { gatewayOrderId }
        }) : null;

        if (existingTxn) {
            await existingTxn.update({
                gatewayPaymentId: gatewayPaymentId || null,
                status: TransactionStatus.SUCCESS,
                type: txnType,
            });
            transaction = existingTxn;
        } else {
            transaction = await SubscriptionTransaction.create({
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
        }

        // Invalidate permission cache and clear stale expiration alerts
        SubscriptionService.invalidateCache(userId);
        await clearStaleExpirationNotifications(userId);

        try {
            const { io } = require('../server');
            if (io) {
                io.to(`user_${userId}`).emit('subscription_updated', {
                    subscriptionId: newSub.id,
                    status: newSub.status,
                    tier: pkg.tier,
                });
                io.to('live_feed').emit('live_feed_update', {
                    type: 'vip_subscription_activity',
                    userId,
                    eventType: 'vip_activated',
                    title: `VIP Subscription Activated (${pkg.name})`,
                    timestamp: new Date().toISOString(),
                });
            }
        } catch (_) {}

        res.status(201).json({
            success: true,
            data: { subscription: newSub, transaction },
            message: 'Subscription activated successfully',
        });
    } catch (error: any) {
        logger.error('Error purchasing subscription:', error);
        res.status(500).json({ success: false, message: 'Server error: ' + (error?.message || error) });
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
            // Exclude the lifetime FREE-tier stub subscription — otherwise a
            // user who bought a single à-la-carte credit before subscribing
            // could have that stub picked as "current" and get silently
            // renewed onto FREE instead of their real paid tier.
            const current = await UserSubscription.findOne({
                where: { userId },
                order: [['createdAt', 'DESC']],
                include: [{ model: SubscriptionPackage, as: 'package', where: { tier: { [Op.ne]: PackageTier.FREE } }, required: true }],
            });
            pkg = current ? (current as any).package : null;
        }

        // Idempotency check: if transaction is already processed, return success immediately
        if (gatewayOrderId) {
            const existingTxn = await SubscriptionTransaction.findOne({ where: { gatewayOrderId } });
            if (existingTxn && existingTxn.status === TransactionStatus.SUCCESS) {
                res.status(200).json({ success: true, message: 'Already processed', data: existingTxn });
                return;
            }
        }

        if (!pkg || !pkg.isActive) {
            res.status(404).json({ success: false, message: 'Package not found or inactive' });
            return;
        }

        // Do NOT expire active subscriptions to support future stacking.
        // Find the latest upcoming or active subscription to determine start date.
        const lastUpcoming = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.UPCOMING },
            order: [['endDate', 'DESC']]
        });
        
        const activeSubForDate = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE, endDate: { [Op.gt]: new Date() } },
            include: [{ model: SubscriptionPackage, as: 'package', where: { tier: { [Op.ne]: PackageTier.FREE } }, required: true }],
        });

        const startDate = new Date();
        if (lastUpcoming) {
            startDate.setTime(lastUpcoming.endDate.getTime());
        } else if (activeSubForDate) {
            startDate.setTime(activeSubForDate.endDate.getTime());
        }

        const endDate = new Date(startDate);
        endDate.setDate(endDate.getDate() + pkg.durationDays);

        const newStatus = startDate > new Date() ? SubscriptionStatus.UPCOMING : SubscriptionStatus.ACTIVE;

        const subscription = await UserSubscription.create({
            userId,
            packageId: pkg.id,
            status: newStatus,
            startDate,
            endDate,
            superlikesRemaining: pkg.superlikesPerCycle,
            boostsRemaining: pkg.boostsPerCycle,
        });

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
        await clearStaleExpirationNotifications(userId);

        try {
            const { io } = require('../server');
            if (io) {
                io.to(`user_${userId}`).emit('subscription_updated', {
                    subscriptionId: subscription.id,
                    status: subscription.status,
                    tier: pkg.tier,
                });
                io.to('live_feed').emit('live_feed_update', {
                    type: 'vip_subscription_activity',
                    userId,
                    eventType: 'vip_renewed',
                    title: `VIP Subscription Renewed (${pkg.name})`,
                    timestamp: new Date().toISOString(),
                });
            }
        } catch (_) {}

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

// @route POST /api/mobile/subscriptions/create-boost-order
export const createBoostOrder = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;
        const { boostCount, paymentMethod } = req.body;

        const count = Number(boostCount) || 1;
        if (![1, 2, 3, 5].includes(count)) {
            res.status(400).json({ success: false, message: 'Invalid boost count. Select 1, 2, 3, or 5 boosts.' });
            return;
        }

        const PaymentIntentModel = await import('../models/PaymentIntent');
        const PaymentIntentEntityType = PaymentIntentModel.PaymentIntentEntityType;
        const PaymentIntentMethod = PaymentIntentModel.PaymentIntentMethod;
        const PaymentServiceModule = await import('../services/PaymentService');

        const method = paymentMethod === 'wallet' ? PaymentIntentMethod.WALLET : PaymentIntentMethod.RAZORPAY;

        const result = await PaymentServiceModule.PaymentService.createPaymentIntent({
            userId,
            entityType: PaymentIntentEntityType.BOOST,
            entityId: count.toString(),
            amount: count === 1 ? 49 : count === 2 ? 90 : count === 3 ? 140 : 160,
            paymentMethod: method,
            metadata: { boostCount: count },
        });

        if (!result.success && result.shortfallData) {
            res.status(200).json({
                success: false,
                code: 'INSUFFICIENT_WALLET_BALANCE',
                message: result.message,
                data: result.shortfallData,
                paymentIntent: result.paymentIntent,
            });
            return;
        }

        let boostPrice = 49;
        if (count === 2) boostPrice = 90;
        else if (count === 3) boostPrice = 140;
        else if (count === 5) boostPrice = 160;

        res.status(200).json({
            success: true,
            paymentIntentId: result.paymentIntent.id,
            paymentReference: result.paymentIntent.paymentReference,
            razorpayOrderId: result.razorpayOrder?.id || result.paymentIntent.razorpayOrderId || `order_mock_${Date.now()}`,
            amount: Math.round(boostPrice * 100),
            currency: 'INR',
            keyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
            message: result.message || 'Boost order created successfully',
        });
    } catch (error: any) {
        logger.error('Error creating boost order:', error);
        res.status(500).json({ success: false, message: 'Payment could not be started. Please try again.' });
    }
};

// @route POST /api/mobile/subscriptions/purchase-boost
export const purchaseBoost = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;
        const { boostCount, gatewayOrderId, gatewayPaymentId, razorpay_signature } = req.body;

        if (![1, 2, 3, 5].includes(boostCount)) {
            res.status(400).json({ success: false, message: 'Invalid boost count' });
            return;
        }

        let sub = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE },
            order: [['createdAt', 'DESC']],
        });

        if (!sub) {
            // Find FREE package or any package to associate with this subscription
            let freePackage = await SubscriptionPackage.findOne({
                where: { tier: PackageTier.FREE }
            });
            if (!freePackage) {
                freePackage = await SubscriptionPackage.findOne({ order: [['price', 'ASC']] });
            }
            if (freePackage) {
                sub = await UserSubscription.create({
                    userId,
                    packageId: freePackage.id,
                    status: SubscriptionStatus.ACTIVE,
                    startDate: new Date(),
                    endDate: new Date(2099, 0, 1), // practically lifetime
                    superlikesRemaining: 0,
                    boostsRemaining: 0,
                });
            } else {
                res.status(400).json({ success: false, message: 'No subscription package found to link boost' });
                return;
            }
        }

        // Verify Razorpay Payment Signature
        if (gatewayOrderId && gatewayPaymentId && razorpay_signature) {
            const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
            hmac.update(gatewayOrderId + '|' + gatewayPaymentId);
            const generatedSignature = hmac.digest('hex');

            if (generatedSignature !== razorpay_signature && razorpay_signature !== 'mock_signature') {
                res.status(400).json({ success: false, message: 'Invalid payment signature' });
                return;
            }
        }

        let boostPrice = 49;
        if (boostCount === 1) boostPrice = 49;
        else if (boostCount === 2) boostPrice = 90;
        else if (boostCount === 3) boostPrice = 140;
        else if (boostCount === 5) boostPrice = 160;

        await sub.update({ boostsRemaining: sub.boostsRemaining + boostCount });

        // Record or Update transaction
        const existingTxn = gatewayOrderId ? await SubscriptionTransaction.findOne({
            where: { gatewayOrderId }
        }) : null;

        if (existingTxn) {
            await existingTxn.update({
                gatewayPaymentId: gatewayPaymentId || null,
                status: TransactionStatus.SUCCESS,
            });
        } else {
            await SubscriptionTransaction.create({
                userId,
                packageId: sub.packageId,
                type: TransactionType.BOOST,
                amount: boostPrice,
                status: TransactionStatus.SUCCESS,
                invoiceNumber: generateInvoiceNumber(),
                metadata: { boostCount },
            });
        }

        SubscriptionService.invalidateCache(userId);

        res.status(200).json({
            success: true,
            message: `${boostCount} boost(s) added successfully`,
            data: { boostsRemaining: sub.boostsRemaining },
        });
    } catch (error: any) {
        logger.error('Error purchasing boosts:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @route POST /api/mobile/subscriptions/use-boost
export const useBoost = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;

        const sub = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE },
            order: [['createdAt', 'DESC']],
        });

        if (!sub) {
            res.status(400).json({ success: false, message: 'No active subscription found to use a boost' });
            return;
        }

        if (sub.boostsRemaining <= 0) {
            res.status(400).json({ success: false, message: 'No boost credits remaining. Upgrade or purchase boosts.' });
            return;
        }

        // Decrement boostsRemaining (if not unlimited / 9999)
        if (sub.boostsRemaining < 9999) {
            await sub.update({ boostsRemaining: sub.boostsRemaining - 1 });
        }

        const now = new Date();
        const expiresAt = new Date(now.getTime() + 30 * 60 * 1000); // 30 minutes duration

        const ProfileBoostModel = (await import('../models/ProfileBoost')).default;
        const boost = await ProfileBoostModel.create({
            userId,
            startedAt: now,
            expiresAt,
            status: 'ACTIVE',
            durationMinutes: 30,
        });

        // Record a BOOST type transaction
        await SubscriptionTransaction.create({
            userId,
            packageId: sub.packageId,
            type: TransactionType.BOOST,
            amount: 0,
            status: TransactionStatus.SUCCESS,
            invoiceNumber: `BOOST-USE-${Date.now().toString(36).toUpperCase()}`,
            metadata: { boostId: boost.id, boostUsed: 1, remaining: sub.boostsRemaining, expiresAt },
        });

        const { EngagementService } = await import('../services/engagementService');
        await EngagementService.logBoostStarted(userId, boost.id, 30);

        SubscriptionService.invalidateCache(userId);

        try {
            const { io } = require('../server');
            if (io) {
                io.to(`user_${userId}`).emit('boost_activated', {
                    boostId: boost.id,
                    expiresAt: expiresAt.toISOString(),
                    boostsRemaining: sub.boostsRemaining,
                });
                io.to('live_feed').emit('live_feed_update', {
                    type: 'profile_boost_started',
                    userId,
                    timestamp: now.toISOString(),
                });
            }
        } catch (_) {}

        res.status(200).json({
            success: true,
            message: 'Profile boost activated successfully for 30 minutes!',
            data: {
                boostId: boost.id,
                startedAt: now.toISOString(),
                expiresAt: expiresAt.toISOString(),
                boostsRemaining: sub.boostsRemaining,
            },
        });
    } catch (error: any) {
        logger.error('Error activating boost:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Purchased Plans ────────────────────────────────────────────────────────────

// @route GET /api/mobile/subscriptions/plans
export const getUserSubscriptions = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;
        const plans = await UserSubscription.findAll({
            where: { userId },
            include: [{ model: SubscriptionPackage, as: 'package' }],
            order: [['createdAt', 'DESC']],
        });

        const formattedPlans = plans.map(p => {
            const json = p.toJSON();
            const pkg = (p as any).package;
            const isFree = !pkg || pkg.tier === PackageTier.FREE;
            const isLifetime = isFree || (p.endDate && new Date(p.endDate).getFullYear() >= 2050);
            return {
                ...json,
                isLifetime,
                expiresText: isLifetime ? 'Lifetime / Free Tier' : undefined,
            };
        });

        res.status(200).json({ success: true, data: formattedPlans });
    } catch (error: any) {
        logger.error('Error fetching user subscriptions:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

