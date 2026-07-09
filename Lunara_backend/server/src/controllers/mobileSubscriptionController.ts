import { Request, Response } from 'express';
import SubscriptionPackage from '../models/SubscriptionPackage';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import UserProfile from '../models/UserProfile';
import { logger } from '../config/logger';

// @desc    Get all active subscription packages for purchase
// @route   GET /api/mobile/subscriptions/packages
export const getAvailablePackages = async (_req: Request, res: Response): Promise<void> => {
    try {
        const packages = await SubscriptionPackage.findAll({
            where: { isActive: true },
            order: [['price', 'ASC']]
        });
        res.status(200).json({ success: true, data: packages });
    } catch (error: any) {
        logger.error('Error fetching packages:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @desc    Get current user's active subscription
// @route   GET /api/mobile/subscriptions/current
export const getCurrentSubscription = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;
        
        const subscription = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE },
            include: [{ model: SubscriptionPackage, as: 'package' }],
            order: [['createdAt', 'DESC']]
        });

        // Also fetch daily usage from profile
        const profile = await UserProfile.findOne({ where: { userId } });

        res.status(200).json({ 
            success: true, 
            data: {
                subscription: subscription || null,
                usage: profile ? {
                    dailyMatchRequestsCount: profile.dailyMatchRequestsCount,
                    dailyLikesCount: profile.dailyLikesCount,
                    dailyPostsCount: profile.dailyPostsCount,
                    lastActivityDate: profile.lastActivityDate
                } : null
            }
        });
    } catch (error: any) {
        logger.error('Error fetching current subscription:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @desc    Purchase a subscription package (Mock)
// @route   POST /api/mobile/subscriptions/purchase
export const purchaseSubscription = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;
        const { packageId } = req.body;

        const pkg = await SubscriptionPackage.findByPk(packageId);
        if (!pkg || !pkg.isActive) {
            res.status(404).json({ success: false, message: 'Package not found or inactive' });
            return;
        }

        // Deactivate previous subscriptions
        await UserSubscription.update(
            { status: SubscriptionStatus.EXPIRED },
            { where: { userId, status: SubscriptionStatus.ACTIVE } }
        );

        // Calculate dates
        const startDate = new Date();
        const endDate = new Date();
        endDate.setDate(endDate.getDate() + pkg.durationDays);

        // Create new subscription
        const newSub = await UserSubscription.create({
            userId,
            packageId: pkg.id,
            status: SubscriptionStatus.ACTIVE,
            startDate,
            endDate,
            superlikesRemaining: pkg.superlikesPerCycle,
            boostsRemaining: pkg.boostsPerCycle
        });

        res.status(201).json({ success: true, data: newSub, message: 'Subscription purchased successfully' });
    } catch (error: any) {
        logger.error('Error purchasing subscription:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

// @desc    Purchase additional boosts (In-App Purchase)
// @route   POST /api/mobile/subscriptions/purchase-boost
export const purchaseBoost = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req as any).user.id;
        const { boostCount } = req.body; // e.g., 1, 2, 3, 5

        if (![1, 2, 3, 5].includes(boostCount)) {
            res.status(400).json({ success: false, message: 'Invalid boost count' });
            return;
        }

        // Find active subscription to add boosts to
        let sub = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE },
            order: [['createdAt', 'DESC']]
        });

        if (!sub) {
            res.status(400).json({ success: false, message: 'You need an active subscription to purchase boosts (even a Free one)' });
            return;
        }

        await sub.update({
            boostsRemaining: sub.boostsRemaining + boostCount
        });

        res.status(200).json({ success: true, message: `Purchased ${boostCount} boosts successfully`, data: sub });
    } catch (error: any) {
        logger.error('Error purchasing boosts:', error);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};
