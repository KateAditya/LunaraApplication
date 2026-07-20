import { Request, Response } from 'express';
import { Op } from 'sequelize';
import SubscriptionPackage, { PackageTier } from '../models/SubscriptionPackage';
import SubscriptionFeature from '../models/SubscriptionFeature';
import SubscriptionPlanFeature from '../models/SubscriptionPlanFeature';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import SubscriptionTransaction from '../models/SubscriptionTransaction';
import SubscriptionUsage from '../models/SubscriptionUsage';
import User from '../models/User';
import { logger } from '../config/logger';
import { SubscriptionService } from '../services/subscriptionService';
import { sendPushNotification } from '../services/fcmService';

// ─── Plans CRUD ───────────────────────────────────────────────────────────────

// @route GET /api/admin/subscriptions
export const getAllPackages = async (_req: Request, res: Response): Promise<void> => {
    try {
        const packages = await SubscriptionPackage.findAll({
            order: [['display_order', 'ASC'], ['price', 'ASC']],
        });

        // Attach subscriber counts
        const packagesWithStats = await Promise.all(packages.map(async (pkg) => {
            const activeCount = await UserSubscription.count({
                where: { packageId: pkg.id, status: SubscriptionStatus.ACTIVE },
            });
            const totalRevenue = await SubscriptionTransaction.sum('amount', {
                where: { packageId: pkg.id, status: 'success' },
            });
            return {
                ...pkg.toJSON(),
                activeSubscribers: activeCount,
                totalRevenue: totalRevenue || 0,
            };
        }));

        res.status(200).json({ success: true, data: packagesWithStats });
    } catch (error: any) {
        logger.error('Error fetching packages:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @route POST /api/admin/subscriptions
export const createPackage = async (req: Request, res: Response): Promise<void> => {
    try {
        const adminId = (req as any).user?.id;
        const packageData = { ...req.body, createdBy: adminId, updatedBy: adminId };

        // Auto-set display_order if not provided
        if (!packageData.displayOrder && !packageData.display_order) {
            const maxOrder = await SubscriptionPackage.max('displayOrder') as number || 0;
            packageData.displayOrder = maxOrder + 1;
        }

        const newPackage = await SubscriptionPackage.create(packageData);
        SubscriptionService.invalidateCache();

        logger.info(`Admin ${adminId} created subscription package: ${newPackage.id}`);
        res.status(201).json({ success: true, data: newPackage, message: 'Subscription package created' });
    } catch (error: any) {
        logger.error('Error creating package:', error);
        res.status(500).json({ success: false, message: error.message || 'Server error' });
    }
};

// @route PUT /api/admin/subscriptions/:id
export const updatePackage = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const adminId = (req as any).user?.id;
        const pkg = await SubscriptionPackage.findByPk(id);

        if (!pkg) {
            res.status(404).json({ success: false, message: 'Package not found' });
            return;
        }

        await pkg.update({ ...req.body, updatedBy: adminId });
        SubscriptionService.invalidateCache(); // Clear all caches since plan changed
        logger.info(`Admin ${adminId} updated package ${id}`);
        res.status(200).json({ success: true, data: pkg, message: 'Package updated' });
    } catch (error: any) {
        logger.error('Error updating package:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @route DELETE /api/admin/subscriptions/:id
export const deletePackage = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const pkg = await SubscriptionPackage.findByPk(id);

        if (!pkg) {
            res.status(404).json({ success: false, message: 'Package not found' });
            return;
        }

        // Only delete if no active subscribers
        const activeCount = await UserSubscription.count({
            where: { packageId: id, status: SubscriptionStatus.ACTIVE },
        });

        if (activeCount > 0) {
            res.status(400).json({
                success: false,
                message: `Cannot delete — ${activeCount} active subscriber(s). Archive it instead.`,
            });
            return;
        }

        await pkg.destroy();
        SubscriptionService.invalidateCache();
        res.status(200).json({ success: true, message: 'Package deleted' });
    } catch (error: any) {
        logger.error('Error deleting package:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @route POST /api/admin/subscriptions/:id/duplicate
export const duplicatePackage = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const adminId = (req as any).user?.id;
        const original = await SubscriptionPackage.findByPk(id);

        if (!original) {
            res.status(404).json({ success: false, message: 'Package not found' });
            return;
        }

        const originalData = original.toJSON() as any;
        delete originalData.id;
        delete originalData.createdAt;
        delete originalData.updatedAt;

        const maxOrder = await SubscriptionPackage.max('displayOrder') as number || 0;
        const duplicate = await SubscriptionPackage.create({
            ...originalData,
            name: `${originalData.name} (Copy)`,
            isActive: false,
            displayOrder: maxOrder + 1,
            createdBy: adminId,
            updatedBy: adminId,
        });

        // Also duplicate plan features
        const planFeatures = await SubscriptionPlanFeature.findAll({ where: { packageId: id } });
        for (const pf of planFeatures) {
            await SubscriptionPlanFeature.create({
                packageId: duplicate.id,
                featureId: pf.featureId,
                value: pf.value,
                isEnabled: pf.isEnabled,
            });
        }

        logger.info(`Admin ${adminId} duplicated package ${id} → ${duplicate.id}`);
        res.status(201).json({ success: true, data: duplicate, message: 'Package duplicated' });
    } catch (error: any) {
        logger.error('Error duplicating package:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @route PATCH /api/admin/subscriptions/:id/archive
export const archivePackage = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const pkg = await SubscriptionPackage.findByPk(id);

        if (!pkg) {
            res.status(404).json({ success: false, message: 'Package not found' });
            return;
        }

        await pkg.update({ isArchived: true, isActive: false } as any);
        SubscriptionService.invalidateCache();
        res.status(200).json({ success: true, message: 'Package archived' });
    } catch (error: any) {
        logger.error('Error archiving package:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @route PATCH /api/admin/subscriptions/:id/toggle-status
export const togglePackageStatus = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const pkg = await SubscriptionPackage.findByPk(id);

        if (!pkg) {
            res.status(404).json({ success: false, message: 'Package not found' });
            return;
        }

        await pkg.update({ isActive: !pkg.isActive });
        SubscriptionService.invalidateCache();
        res.status(200).json({
            success: true,
            data: { isActive: !pkg.isActive },
            message: pkg.isActive ? 'Package disabled' : 'Package enabled',
        });
    } catch (error: any) {
        logger.error('Error toggling package status:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Seed Defaults ────────────────────────────────────────────────────────────

// @route POST /api/admin/subscriptions/seed
export const seedDefaultPackages = async (_req: Request, res: Response): Promise<void> => {
    try {
        const existing = await SubscriptionPackage.count();
        if (existing > 0) {
            res.status(400).json({ success: false, message: 'Packages already exist' });
            return;
        }

        const defaultPackages = [
            {
                name: 'Free Service (Basic Access)',
                tier: PackageTier.FREE,
                price: 0,
                durationDays: 3650,
                dailyMatchRequests: 3,
                dailyLikes: 7,
                dailyPosts: 5,
                superlikesPerCycle: 0,
                boostsPerCycle: 0,
                hasHideProfile: false,
                hasPriorityVisibility: false,
                hasTrustBadge: false,
                hasEliteBadge: false,
                canSeeWhoLiked: false,
                isActive: true,
                displayOrder: 0,
                themeColor: '#6c757d',
            },
            {
                name: 'Lunara Core',
                tier: PackageTier.CORE,
                price: 199,
                durationDays: 7,
                dailyMatchRequests: -1,
                dailyLikes: -1,
                dailyPosts: -1,
                superlikesPerCycle: 3,
                boostsPerCycle: 0,
                hasHideProfile: false,
                hasPriorityVisibility: false,
                hasTrustBadge: false,
                hasEliteBadge: false,
                canSeeWhoLiked: true,
                isActive: true,
                displayOrder: 1,
                themeColor: '#00A9FF',
            },
            {
                name: 'Lunara Plus',
                tier: PackageTier.PLUS,
                price: 299,
                durationDays: 7,
                dailyMatchRequests: -1,
                dailyLikes: -1,
                dailyPosts: -1,
                superlikesPerCycle: 10,
                boostsPerCycle: 2,
                hasHideProfile: true,
                hasPriorityVisibility: false,
                hasTrustBadge: false,
                hasEliteBadge: false,
                canSeeWhoLiked: true,
                isActive: true,
                isPopular: true,
                displayOrder: 2,
                themeColor: '#7F00FF',
            },
            {
                name: 'Lunara Pro',
                tier: PackageTier.PRO,
                price: 599,
                durationDays: 14,
                dailyMatchRequests: -1,
                dailyLikes: -1,
                dailyPosts: -1,
                superlikesPerCycle: 14,
                boostsPerCycle: 4,
                hasHideProfile: true,
                hasPriorityVisibility: true,
                hasTrustBadge: true,
                hasEliteBadge: false,
                canSeeWhoLiked: true,
                isActive: true,
                isRecommended: true,
                displayOrder: 3,
                themeColor: '#E100FF',
            },
            {
                name: 'Lunara Elite - 15 Days',
                tier: PackageTier.ELITE,
                price: 999,
                durationDays: 15,
                dailyMatchRequests: -1,
                dailyLikes: -1,
                dailyPosts: -1,
                superlikesPerCycle: 9999,
                boostsPerCycle: 9999,
                hasHideProfile: true,
                hasPriorityVisibility: true,
                hasTrustBadge: true,
                hasEliteBadge: true,
                canSeeWhoLiked: true,
                isActive: true,
                displayOrder: 4,
                themeColor: '#FFB703',
            },
            {
                name: 'Lunara Elite - 30 Days',
                tier: PackageTier.ELITE,
                price: 1699,
                durationDays: 30,
                dailyMatchRequests: -1,
                dailyLikes: -1,
                dailyPosts: -1,
                superlikesPerCycle: 9999,
                boostsPerCycle: 9999,
                hasHideProfile: true,
                hasPriorityVisibility: true,
                hasTrustBadge: true,
                hasEliteBadge: true,
                canSeeWhoLiked: true,
                isActive: true,
                displayOrder: 5,
                themeColor: '#FFB703',
            },
        ];

        await SubscriptionPackage.bulkCreate(defaultPackages as any[]);
        res.status(201).json({ success: true, message: 'Default packages seeded successfully' });
    } catch (error: any) {
        logger.error('Error seeding packages:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Feature Catalog CRUD ─────────────────────────────────────────────────────

// @route GET /api/admin/subscriptions/features
export const getAllFeatures = async (_req: Request, res: Response): Promise<void> => {
    try {
        const features = await SubscriptionFeature.findAll({
            order: [['display_order', 'ASC'], ['category', 'ASC']],
        });
        res.status(200).json({ success: true, data: features });
    } catch (error: any) {
        logger.error('Error fetching features:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @route POST /api/admin/subscriptions/features
export const createFeature = async (req: Request, res: Response): Promise<void> => {
    try {
        const feature = await SubscriptionFeature.create(req.body);
        SubscriptionService.invalidateCache();
        res.status(201).json({ success: true, data: feature, message: 'Feature created' });
    } catch (error: any) {
        logger.error('Error creating feature:', error);
        res.status(500).json({ success: false, message: error.message || 'Server error' });
    }
};

// @route PUT /api/admin/subscriptions/features/:id
export const updateFeature = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const feature = await SubscriptionFeature.findByPk(id);

        if (!feature) {
            res.status(404).json({ success: false, message: 'Feature not found' });
            return;
        }

        await feature.update(req.body);
        SubscriptionService.invalidateCache();
        res.status(200).json({ success: true, data: feature, message: 'Feature updated' });
    } catch (error: any) {
        logger.error('Error updating feature:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @route DELETE /api/admin/subscriptions/features/:id
export const deleteFeature = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const feature = await SubscriptionFeature.findByPk(id);

        if (!feature) {
            res.status(404).json({ success: false, message: 'Feature not found' });
            return;
        }

        await feature.destroy(); // cascades to SubscriptionPlanFeatures
        SubscriptionService.invalidateCache();
        res.status(200).json({ success: true, message: 'Feature deleted' });
    } catch (error: any) {
        logger.error('Error deleting feature:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Plan Feature Assignment ──────────────────────────────────────────────────

// @route GET /api/admin/subscriptions/:id/features
export const getPlanFeatures = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const planFeatures = await SubscriptionPlanFeature.findAll({
            where: { packageId: id },
            include: [{ model: SubscriptionFeature, as: 'feature' }],
            order: [[{ model: SubscriptionFeature, as: 'feature' }, 'display_order', 'ASC']],
        });
        res.status(200).json({ success: true, data: planFeatures });
    } catch (error: any) {
        logger.error('Error fetching plan features:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @route PUT /api/admin/subscriptions/:id/features
// Body: { features: [{ featureId, value, isEnabled }] }
export const updatePlanFeatures = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { features } = req.body;

        if (!Array.isArray(features)) {
            res.status(400).json({ success: false, message: 'features must be an array' });
            return;
        }

        const pkg = await SubscriptionPackage.findByPk(id);
        if (!pkg) {
            res.status(404).json({ success: false, message: 'Package not found' });
            return;
        }

        // Upsert each feature assignment
        for (const f of features) {
            await SubscriptionPlanFeature.upsert({
                packageId: id,
                featureId: f.featureId,
                value: f.value || { enabled: !!f.isEnabled },
                isEnabled: f.isEnabled !== false,
            });
        }

        SubscriptionService.invalidateCache();
        res.status(200).json({ success: true, message: 'Plan features updated' });
    } catch (error: any) {
        logger.error('Error updating plan features:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Analytics ────────────────────────────────────────────────────────────────

// @route GET /api/admin/subscriptions/analytics/overview
export const getAnalyticsOverview = async (_req: Request, res: Response): Promise<void> => {
    try {
        const now = new Date();
        const firstDayOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        const firstDayOfLastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);

        const [
            totalPlans,
            activeSubscribers,
            expiredCount,
            monthlyRevenue,
            lastMonthRevenue,
            totalRevenue,
            trialUsers,
        ] = await Promise.all([
            SubscriptionPackage.count({ where: { isActive: true } }),
            UserSubscription.count({
                where: { status: SubscriptionStatus.ACTIVE, endDate: { [Op.gt]: now } },
            }),
            UserSubscription.count({ where: { status: SubscriptionStatus.EXPIRED } }),
            SubscriptionTransaction.sum('amount', {
                where: { status: 'success', createdAt: { [Op.gte]: firstDayOfMonth } },
            }),
            SubscriptionTransaction.sum('amount', {
                where: {
                    status: 'success',
                    createdAt: { [Op.gte]: firstDayOfLastMonth, [Op.lt]: firstDayOfMonth },
                },
            }),
            SubscriptionTransaction.sum('amount', { where: { status: 'success' } }),
            UserSubscription.count({ where: { status: SubscriptionStatus.ACTIVE } }), // Fallback active count
        ]);

        // Plan distribution
        const packages = await SubscriptionPackage.findAll({ where: { isActive: true } });
        const planDistribution = await Promise.all(packages.map(async (pkg) => {
            const count = await UserSubscription.count({
                where: { packageId: pkg.id, status: SubscriptionStatus.ACTIVE },
            });
            return { planName: pkg.name, count, tier: pkg.tier };
        }));

        const popularPlan = planDistribution.reduce((prev, curr) =>
            curr.count > prev.count ? curr : prev, planDistribution[0] || { planName: 'N/A', count: 0 });

        // Monthly growth (last 6 months)
        const growthData = [];
        for (let i = 5; i >= 0; i--) {
            const monthStart = new Date(now.getFullYear(), now.getMonth() - i, 1);
            const monthEnd = new Date(now.getFullYear(), now.getMonth() - i + 1, 0, 23, 59, 59);
            const monthLabel = monthStart.toLocaleString('default', { month: 'short' });

            const [newSubs, monthRevenue] = await Promise.all([
                UserSubscription.count({ where: { createdAt: { [Op.between]: [monthStart, monthEnd] } } }),
                SubscriptionTransaction.sum('amount', {
                    where: { status: 'success', createdAt: { [Op.between]: [monthStart, monthEnd] } },
                }),
            ]);

            growthData.push({ month: monthLabel, subscribers: newSubs, revenue: monthRevenue || 0 });
        }

        res.status(200).json({
            success: true,
            data: {
                stats: {
                    totalPlans,
                    activeSubscribers,
                    expiredCount,
                    monthlyRevenue: monthlyRevenue || 0,
                    lastMonthRevenue: lastMonthRevenue || 0,
                    totalRevenue: totalRevenue || 0,
                    trialUsers: trialUsers || 0,
                    popularPlan: popularPlan?.planName || 'N/A',
                    revenueGrowth: lastMonthRevenue
                        ? (((monthlyRevenue || 0) - lastMonthRevenue) / lastMonthRevenue * 100).toFixed(1)
                        : 0,
                },
                planDistribution,
                growthData,
            },
        });
    } catch (error: any) {
        logger.error('Error fetching analytics:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Transactions ─────────────────────────────────────────────────────────────

// @route GET /api/admin/subscriptions/transactions
export const getAllTransactions = async (req: Request, res: Response): Promise<void> => {
    try {
        const page = parseInt(req.query.page as string) || 1;
        const limit = parseInt(req.query.limit as string) || 20;
        const offset = (page - 1) * limit;
        const search = req.query.search as string;
        const status = req.query.status as string;
        const type = req.query.type as string;

        const where: any = {};
        if (status) where.status = status;
        if (type) where.type = type;
        if (search) {
            where[Op.or] = [
                { invoiceNumber: { [Op.iLike]: `%${search}%` } },
                { '$user.first_name$': { [Op.iLike]: `%${search}%` } },
                { '$user.last_name$': { [Op.iLike]: `%${search}%` } },
                { '$user.email$': { [Op.iLike]: `%${search}%` } }
            ];
        }

        const { count, rows } = await SubscriptionTransaction.findAndCountAll({
            where,
            include: [
                { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email'] },
                { model: SubscriptionPackage, as: 'package', attributes: ['id', 'name', 'tier'] },
            ],
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
        logger.error('Error fetching transactions:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── User Subscription Management ────────────────────────────────────────────

// @route GET /api/admin/subscriptions/users
export const getSubscribedUsers = async (req: Request, res: Response): Promise<void> => {
    try {
        const page = parseInt(req.query.page as string) || 1;
        const limit = parseInt(req.query.limit as string) || 20;
        const offset = (page - 1) * limit;

        const { count, rows } = await UserSubscription.findAndCountAll({
            include: [
                { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email'] },
                { model: SubscriptionPackage, as: 'package' },
            ],
            order: [['createdAt', 'DESC']],
            limit,
            offset,
        });

        res.status(200).json({
            success: true,
            data: {
                subscriptions: rows,
                pagination: { page, limit, total: count, totalPages: Math.ceil(count / limit) },
            },
        });
    } catch (error: any) {
        logger.error('Error fetching subscribed users:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Admin: Force-expire a user's active subscription ────────────────────────

// @route PATCH /api/admin/subscriptions/users/:userId/force-expire
export const forceExpireUserSubscription = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;
        const { reason } = req.body;

        const activeSubs = await UserSubscription.findAll({
            where: { userId, status: SubscriptionStatus.ACTIVE },
            include: [{ model: SubscriptionPackage, as: 'package' }],
        });

        if (!activeSubs.length) {
            res.status(404).json({ success: false, message: 'No active subscription found for this user' });
            return;
        }

        for (const sub of activeSubs) {
            await sub.update({ status: SubscriptionStatus.EXPIRED, endDate: new Date() });

            await SubscriptionTransaction.create({
                userId,
                packageId: sub.packageId,
                type: 'expire' as any,
                amount: 0,
                status: 'cancelled' as any,
                invoiceNumber: `ADMIN-EXP-${Date.now().toString(36).toUpperCase()}`,
                metadata: {
                    adminAction: 'force_expire',
                    reason: reason || 'Admin forced expiry',
                    planName: (sub as any).package?.name,
                },
            });
        }

        SubscriptionService.invalidateCache(userId);

        // Fetch user and dispatch push notification
        const user = await User.findByPk(userId);
        if (user && user.fcmToken) {
            await sendPushNotification(user.fcmToken, {
                title: 'VIP Subscription Expired',
                body: `Your VIP Subscription (${(activeSubs[0] as any).package?.name || 'VIP Package'}) has expired or has been revoked.`,
                data: {
                    type: 'subscription_expired',
                    userId: userId,
                }
            });
        }

        logger.info(`Admin force-expired subscriptions for user ${userId}`);
        res.status(200).json({
            success: true,
            message: `Force-expired ${activeSubs.length} subscription(s) for user ${userId}`,
        });
    } catch (error: any) {
        logger.error('Error force-expiring subscription:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @route PATCH /api/admin/subscriptions/users/:userId/extend
export const extendUserSubscription = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;
        const { days, reason } = req.body;

        if (!days || days <= 0) {
            res.status(400).json({ success: false, message: 'days must be a positive integer' });
            return;
        }

        const sub = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE },
            include: [{ model: SubscriptionPackage, as: 'package' }],
            order: [['createdAt', 'DESC']],
        });

        if (!sub) {
            res.status(404).json({ success: false, message: 'No active subscription found' });
            return;
        }

        const newEnd = new Date(sub.endDate);
        newEnd.setDate(newEnd.getDate() + days);
        await sub.update({ endDate: newEnd });

        await SubscriptionTransaction.create({
            userId,
            packageId: sub.packageId,
            type: 'renew' as any,
            amount: 0,
            status: 'success' as any,
            invoiceNumber: `ADMIN-EXT-${Date.now().toString(36).toUpperCase()}`,
            metadata: {
                adminAction: 'extend',
                daysAdded: days,
                reason: reason || 'Admin extension',
                planName: (sub as any).package?.name,
            },
        });

        SubscriptionService.invalidateCache(userId);

        // Fetch user and dispatch push notification
        const user = await User.findByPk(userId);
        if (user && user.fcmToken) {
            await sendPushNotification(user.fcmToken, {
                title: 'VIP Subscription Extended!',
                body: `Your VIP Subscription (${(sub as any).package?.name || 'VIP Package'}) has been extended by ${days} days by support.`,
                data: {
                    type: 'subscription_extended',
                    userId: userId,
                    daysAdded: String(days),
                    newEndDate: newEnd.toISOString()
                }
            });
        }

        logger.info(`Admin extended subscription for user ${userId} by ${days} days`);
        res.status(200).json({
            success: true,
            message: `Extended subscription by ${days} days. New expiry: ${newEnd.toISOString()}`,
            data: { newEndDate: newEnd },
        });
    } catch (error: any) {
        logger.error('Error extending subscription:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Admin: Grant a free subscription to any user ────────────────────────────

// @route POST /api/admin/subscriptions/users/:userId/grant
// Body: { packageId, durationDays?, reason? }
export const grantUserSubscription = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;
        const { packageId, durationDays, reason } = req.body;
        const adminId = (req as any).user?.id;

        if (!packageId) {
            res.status(400).json({ success: false, message: 'packageId is required' });
            return;
        }

        const user = await User.findByPk(userId);
        if (!user) {
            res.status(404).json({ success: false, message: 'User not found' });
            return;
        }

        const pkg = await SubscriptionPackage.findByPk(packageId);
        if (!pkg) {
            res.status(404).json({ success: false, message: 'Package not found' });
            return;
        }

        // Expire any currently active subscriptions
        await UserSubscription.update(
            { status: SubscriptionStatus.EXPIRED, endDate: new Date() },
            { where: { userId, status: SubscriptionStatus.ACTIVE } }
        );

        const days = durationDays || pkg.durationDays;
        const startDate = new Date();
        const endDate = new Date();
        endDate.setDate(endDate.getDate() + days);

        const newSub = await UserSubscription.create({
            userId,
            packageId,
            status: SubscriptionStatus.ACTIVE,
            startDate,
            endDate,
            superlikesRemaining: pkg.superlikesPerCycle,
            boostsRemaining: pkg.boostsPerCycle,
        });

        await SubscriptionTransaction.create({
            userId,
            packageId,
            type: 'purchase' as any,
            amount: 0,
            status: 'success' as any,
            invoiceNumber: `ADMIN-GRANT-${Date.now().toString(36).toUpperCase()}`,
            metadata: {
                adminAction: 'grant',
                adminId,
                reason: reason || 'Admin granted complimentary subscription',
                planName: pkg.name,
                durationDays: days,
            },
        });

        SubscriptionService.invalidateCache(userId);

        if (user.fcmToken) {
            await sendPushNotification(user.fcmToken, {
                title: '🎉 VIP Subscription Activated!',
                body: `You have been granted ${pkg.name} access for ${days} days. Enjoy all premium features!`,
                data: { type: 'subscription_granted', packageName: pkg.name, endDate: endDate.toISOString() },
            });
        }

        logger.info(`Admin ${adminId} granted ${pkg.name} to user ${userId} for ${days} days`);
        res.status(201).json({
            success: true,
            message: `Granted ${pkg.name} to user for ${days} days`,
            data: { subscription: newSub, endDate },
        });
    } catch (error: any) {
        logger.error('Error granting subscription:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Admin: Adjust superlike / backtrack credits for a user ──────────────────

// @route PATCH /api/admin/subscriptions/users/:userId/credits
// Body: { superlikesRemaining?, boostsRemaining? }
export const adjustUserCredits = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;
        const { superlikesRemaining, boostsRemaining, reason: _reason } = req.body;
        const adminId = (req as any).user?.id;

        const sub = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE },
            include: [{ model: SubscriptionPackage, as: 'package' }],
            order: [['createdAt', 'DESC']],
        });

        if (!sub) {
            res.status(404).json({ success: false, message: 'No active subscription found for this user' });
            return;
        }

        const updates: any = {};
        if (superlikesRemaining !== undefined) updates.superlikesRemaining = Math.max(0, parseInt(superlikesRemaining));
        if (boostsRemaining !== undefined) updates.boostsRemaining = Math.max(0, parseInt(boostsRemaining));

        if (Object.keys(updates).length === 0) {
            res.status(400).json({ success: false, message: 'Provide superlikesRemaining and/or boostsRemaining to update' });
            return;
        }

        await sub.update(updates);
        SubscriptionService.invalidateCache(userId);

        const user = await User.findByPk(userId);
        if (user?.fcmToken) {
            await sendPushNotification(user.fcmToken, {
                title: '✨ Credits Updated',
                body: `Your VIP credits have been updated by support. Check your profile for the latest balance.`,
                data: { type: 'credits_adjusted' },
            });
        }

        logger.info(`Admin ${adminId} adjusted credits for user ${userId}: ${JSON.stringify(updates)}`);
        res.status(200).json({
            success: true,
            message: 'User credits updated successfully',
            data: { superlikesRemaining: sub.superlikesRemaining, boostsRemaining: sub.boostsRemaining },
        });
    } catch (error: any) {
        logger.error('Error adjusting credits:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Admin: Reset a user's daily usage counters ──────────────────────────────

// @route DELETE /api/admin/subscriptions/users/:userId/usage
// Query: ?featureKey=daily_likes  (omit to reset all features)
export const resetUserUsage = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;
        const { featureKey } = req.query;
        const adminId = (req as any).user?.id;

        const user = await User.findByPk(userId);
        if (!user) {
            res.status(404).json({ success: false, message: 'User not found' });
            return;
        }

        const where: any = { userId };
        if (featureKey) where.featureKey = featureKey as string;

        const deleted = await SubscriptionUsage.destroy({ where });
        SubscriptionService.invalidateCache(userId);

        logger.info(`Admin ${adminId} reset usage for user ${userId}${featureKey ? ` [${featureKey}]` : ' [ALL]'} — ${deleted} records cleared`);
        res.status(200).json({
            success: true,
            message: `Usage reset for ${featureKey || 'all features'}. Cleared ${deleted} record(s).`,
        });
    } catch (error: any) {
        logger.error('Error resetting usage:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Admin: View a user's live feature access & usage status ─────────────────

// @route GET /api/admin/subscriptions/users/:userId/status
export const getUserFeatureStatus = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;

        const user = await User.findByPk(userId, { attributes: ['id', 'firstName', 'lastName', 'email'] });
        if (!user) {
            res.status(404).json({ success: false, message: 'User not found' });
            return;
        }

        // Active subscription
        const activeSub = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE, endDate: { [Op.gt]: new Date() } },
            include: [{ model: SubscriptionPackage, as: 'package' }],
            order: [['createdAt', 'DESC']],
        });

        // Feature summary
        const featureSummary = await SubscriptionService.getUserFeatureSummary(userId);

        // Current usage records
        const usageRecords = await SubscriptionUsage.findAll({
            where: { userId },
            order: [['updatedAt', 'DESC']],
        });

        res.status(200).json({
            success: true,
            data: {
                user,
                subscription: activeSub
                    ? {
                        id: activeSub.id,
                        packageName: (activeSub as any).package?.name,
                        tier: (activeSub as any).package?.tier,
                        status: activeSub.status,
                        startDate: activeSub.startDate,
                        endDate: activeSub.endDate,
                        superlikesRemaining: activeSub.superlikesRemaining,
                        boostsRemaining: activeSub.boostsRemaining,
                    }
                    : null,
                featureSummary,
                usageRecords,
            },
        });
    } catch (error: any) {
        logger.error('Error fetching user feature status:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─── Admin: Bulk-configure feature flags per tier ────────────────────────────

// @route PUT /api/admin/subscriptions/tiers/:tier/features
// Body: { features: [{ featureKey, value, isEnabled }] }
// This upserts SubscriptionPlanFeature rows for ALL packages of the given tier.
export const bulkConfigureTierFeatures = async (req: Request, res: Response): Promise<void> => {
    try {
        const { tier } = req.params;
        const { features } = req.body;
        const adminId = (req as any).user?.id;

        if (!Object.values(PackageTier).includes(tier as PackageTier)) {
            res.status(400).json({
                success: false,
                message: `Invalid tier. Must be one of: ${Object.values(PackageTier).join(', ')}`,
            });
            return;
        }

        if (!Array.isArray(features) || features.length === 0) {
            res.status(400).json({ success: false, message: 'features array is required and cannot be empty' });
            return;
        }

        const packages = await SubscriptionPackage.findAll({ where: { tier: tier as PackageTier, isActive: true } });
        if (packages.length === 0) {
            res.status(404).json({ success: false, message: `No active packages found for tier: ${tier}` });
            return;
        }

        let upsertCount = 0;
        for (const pkg of packages) {
            for (const f of features) {
                // Lookup featureId by key if featureKey is provided instead of featureId
                let featureId = f.featureId;
                if (!featureId && f.featureKey) {
                    const feat = await SubscriptionFeature.findOne({ where: { key: f.featureKey } });
                    if (!feat) continue;
                    featureId = feat.id;
                }
                if (!featureId) continue;

                await SubscriptionPlanFeature.upsert({
                    packageId: pkg.id,
                    featureId,
                    value: f.value || { enabled: !!f.isEnabled },
                    isEnabled: f.isEnabled !== false,
                });
                upsertCount++;
            }
        }

        SubscriptionService.invalidateCache();
        logger.info(`Admin ${adminId} bulk-configured ${upsertCount} feature(s) for tier ${tier} across ${packages.length} package(s)`);

        res.status(200).json({
            success: true,
            message: `Updated ${upsertCount} feature assignment(s) across ${packages.length} ${tier} package(s)`,
            data: { tier, packagesAffected: packages.length, featuresUpserted: upsertCount },
        });
    } catch (error: any) {
        logger.error('Error bulk-configuring tier features:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};
