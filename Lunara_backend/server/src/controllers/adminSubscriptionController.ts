import { Request, Response } from 'express';
import { Op } from 'sequelize';
import SubscriptionPackage, { PackageTier } from '../models/SubscriptionPackage';
import SubscriptionFeature from '../models/SubscriptionFeature';
import SubscriptionPlanFeature from '../models/SubscriptionPlanFeature';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import SubscriptionTransaction from '../models/SubscriptionTransaction';
import User from '../models/User';
import { logger } from '../config/logger';
import { SubscriptionService } from '../services/subscriptionService';

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
