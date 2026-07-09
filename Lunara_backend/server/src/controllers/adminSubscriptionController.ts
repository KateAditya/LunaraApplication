import { Request, Response } from 'express';
import SubscriptionPackage, { PackageTier } from '../models/SubscriptionPackage';
import { logger } from '../config/logger';

// @desc    Get all subscription packages
// @route   GET /api/admin/subscriptions
export const getAllPackages = async (_req: Request, res: Response): Promise<void> => {
    try {
        const packages = await SubscriptionPackage.findAll({
            order: [['price', 'ASC']]
        });
        res.status(200).json({ success: true, data: packages });
    } catch (error: any) {
        logger.error('Error fetching subscription packages:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @desc    Create a new subscription package
// @route   POST /api/admin/subscriptions
export const createPackage = async (req: Request, res: Response): Promise<void> => {
    try {
        const packageData = req.body;
        const newPackage = await SubscriptionPackage.create(packageData);
        res.status(201).json({ success: true, data: newPackage, message: 'Subscription package created' });
    } catch (error: any) {
        logger.error('Error creating subscription package:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @desc    Update a subscription package
// @route   PUT /api/admin/subscriptions/:id
export const updatePackage = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const packageData = req.body;
        const pkg = await SubscriptionPackage.findByPk(id);
        
        if (!pkg) {
            res.status(404).json({ success: false, message: 'Subscription package not found' });
            return;
        }

        await pkg.update(packageData);
        res.status(200).json({ success: true, data: pkg, message: 'Subscription package updated' });
    } catch (error: any) {
        logger.error('Error updating subscription package:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @desc    Delete a subscription package
// @route   DELETE /api/admin/subscriptions/:id
export const deletePackage = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const pkg = await SubscriptionPackage.findByPk(id);
        
        if (!pkg) {
            res.status(404).json({ success: false, message: 'Subscription package not found' });
            return;
        }

        await pkg.destroy();
        res.status(200).json({ success: true, message: 'Subscription package deleted' });
    } catch (error: any) {
        logger.error('Error deleting subscription package:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @desc    Initialize default subscription packages
// @route   POST /api/admin/subscriptions/seed
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
                durationDays: 3650, // Effectively infinite
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
                isActive: true
            },
            {
                name: 'Lunara Core',
                tier: PackageTier.CORE,
                price: 199,
                durationDays: 7,
                dailyMatchRequests: -1, // Unlimited
                dailyLikes: -1,
                dailyPosts: -1,
                superlikesPerCycle: 3,
                boostsPerCycle: 0,
                hasHideProfile: false,
                hasPriorityVisibility: false,
                hasTrustBadge: false,
                hasEliteBadge: false,
                canSeeWhoLiked: true,
                isActive: true
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
                isActive: true
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
                isActive: true
            },
            {
                name: 'Lunara Elite - 15 Days',
                tier: PackageTier.ELITE,
                price: 999,
                durationDays: 15,
                dailyMatchRequests: -1,
                dailyLikes: -1,
                dailyPosts: -1,
                superlikesPerCycle: 9999, // practically unlimited
                boostsPerCycle: 9999,
                hasHideProfile: true,
                hasPriorityVisibility: true,
                hasTrustBadge: true,
                hasEliteBadge: true,
                canSeeWhoLiked: true,
                isActive: true
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
                isActive: true
            }
        ];

        await SubscriptionPackage.bulkCreate(defaultPackages);
        res.status(201).json({ success: true, message: 'Default packages seeded successfully' });
    } catch (error: any) {
        logger.error('Error seeding subscription packages:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};
