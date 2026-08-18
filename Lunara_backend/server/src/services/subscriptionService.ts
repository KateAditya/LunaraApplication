/**
 * SubscriptionService — Centralized Permission Engine
 *
 * USAGE:
 *   const canLike = await SubscriptionService.hasAccess(userId, 'daily_likes');
 *   const limit   = await SubscriptionService.getLimit(userId, 'daily_likes');
 *   const result  = await SubscriptionService.consumeUsage(userId, 'daily_likes');
 *
 * Features map to plan columns (backward-compat) AND the new SubscriptionPlanFeatures table.
 * The new dynamic engine takes precedence when SubscriptionPlanFeatures rows exist.
 */

import { Op, Transaction } from 'sequelize';
import SubscriptionPackage from '../models/SubscriptionPackage';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import SubscriptionPlanFeature from '../models/SubscriptionPlanFeature';
import SubscriptionFeature from '../models/SubscriptionFeature';
import SubscriptionUsage, { UsagePeriod } from '../models/SubscriptionUsage';
import PartyPlan from '../models/PartyPlan';
import { logger } from '../config/logger';

// ─── Types ───────────────────────────────────────────────────────────────────

type FeatureLimit = number | 'unlimited'; // -1 legacy maps to 'unlimited'
const UNLIMITED: FeatureLimit = 'unlimited';

interface UsageResult {
    success: boolean;
    remaining: FeatureLimit;
    used: number;
    limit: FeatureLimit;
    message?: string;
}

// ─── Internal Cache (5-minute TTL per user) ──────────────────────────────────

interface CacheEntry {
    plan: SubscriptionPackage | null;
    features: Map<string, any>;
    expiresAt: number;
}

const CACHE_TTL_MS = 5 * 60 * 1000;
const planCache = new Map<string, CacheEntry>();

// ─── Legacy Column → Feature Key Map ─────────────────────────────────────────
// Maps the dynamic feature key to the legacy SubscriptionPackage column.
// Used as fallback when no SubscriptionPlanFeatures rows exist for a plan.

const LEGACY_COLUMN_MAP: Record<string, { column: string; isBoolean?: boolean }> = {
    daily_likes: { column: 'dailyLikes' },
    daily_match_requests: { column: 'dailyMatchRequests' },
    daily_posts: { column: 'dailyPosts' },
    super_likes: { column: 'superlikesPerCycle' },
    boosts: { column: 'boostsPerCycle' },
    daily_backtracks: { column: 'backtrackLimit' },
    hide_profile: { column: 'hasHideProfile', isBoolean: true },
    priority_visibility: { column: 'hasPriorityVisibility', isBoolean: true },
    trust_badge: { column: 'hasTrustBadge', isBoolean: true },
    elite_badge: { column: 'hasEliteBadge', isBoolean: true },
    who_liked_me: { column: 'canSeeWhoLiked', isBoolean: true },
};

// ─── Main Service ─────────────────────────────────────────────────────────────

export class SubscriptionService {

    // ── Cache Management ──────────────────────────────────────────────────────

    static invalidateCache(userId?: string): void {
        if (userId) {
            planCache.delete(userId);
        } else {
            planCache.clear();
        }
    }

    private static async getFromCache(userId: string): Promise<CacheEntry | null> {
        const entry = planCache.get(userId);
        if (entry && entry.expiresAt > Date.now()) {
            return entry;
        }
        planCache.delete(userId);
        return null;
    }

    static async activateUpcomingSubscriptions(userId: string): Promise<void> {
        const now = new Date();

        // 1. Expire currently ACTIVE subscriptions that have passed endDate
        await UserSubscription.update(
            { status: SubscriptionStatus.EXPIRED },
            { 
                where: { 
                    userId, 
                    status: SubscriptionStatus.ACTIVE, 
                    endDate: { [Op.lte]: now } 
                } 
            }
        );

        // 2. See if there is any CURRENTLY active subscription
        const activeSub = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE }
        });

        if (!activeSub) {
            // 3. Find the oldest UPCOMING subscription that is ready to activate
            const upcomingSub = await UserSubscription.findOne({
                where: { 
                    userId, 
                    status: SubscriptionStatus.UPCOMING,
                    startDate: { [Op.lte]: now }
                },
                order: [['startDate', 'ASC']],
                include: [{ model: SubscriptionPackage, as: 'package' }]
            });

            if (upcomingSub) {
                const pkg = (upcomingSub as any).package;
                await upcomingSub.update({ 
                    status: SubscriptionStatus.ACTIVE,
                    superlikesRemaining: pkg?.superlikesPerCycle || 0,
                    boostsRemaining: pkg?.boostsPerCycle || 0,
                });
                // Recursively call to handle skipped periods if necessary
                await this.activateUpcomingSubscriptions(userId);
            }
        }
    }

    private static async buildCache(userId: string): Promise<CacheEntry> {
        await this.activateUpcomingSubscriptions(userId);

        const subscription = await UserSubscription.findOne({
            where: {
                userId,
                status: SubscriptionStatus.ACTIVE,
                endDate: { [Op.gt]: new Date() },
            },
            include: [{ model: SubscriptionPackage, as: 'package' }],
            order: [['createdAt', 'DESC']],
        });

        const plan: SubscriptionPackage | null = (subscription as any)?.package || null;
        const features = new Map<string, any>();

        if (plan) {
            // Try to load from dynamic feature table first
            const planFeatures = await SubscriptionPlanFeature.findAll({
                where: { packageId: plan.id, isEnabled: true },
                include: [{ model: SubscriptionFeature, as: 'feature' }],
            });

            if (planFeatures.length > 0) {
                // Dynamic engine: use SubscriptionPlanFeatures
                for (const pf of planFeatures) {
                    const feat = (pf as any).feature;
                    if (feat) {
                        features.set(feat.key, pf.value);
                    }
                }
            } else {
                // Fallback: read from legacy columns
                for (const [featureKey, mapping] of Object.entries(LEGACY_COLUMN_MAP)) {
                    const rawVal = (plan as any)[mapping.column];
                    if (mapping.isBoolean) {
                        features.set(featureKey, { enabled: !!rawVal });
                    } else {
                        const numVal = Number(rawVal);
                        features.set(featureKey, {
                            enabled: numVal !== 0,
                            value: numVal === -1 ? 'unlimited' : numVal,
                        });
                    }
                }
                // Enable stranger_meet and party_creation for VIP users
                features.set('stranger_meet', { enabled: true, value: 'unlimited' });
                features.set('party_creation', { enabled: true, value: 'unlimited' });
            }
        } else {
            // Seed programmatical defaults for free/unsubscribed users
            features.set('daily_likes', { enabled: true, value: 3 });
            features.set('daily_match_requests', { enabled: true, value: 3 });
            features.set('daily_posts', { enabled: true, value: 5 });
            features.set('daily_backtracks', { enabled: true, value: 3 });
            features.set('super_likes', { enabled: false, value: 0 });
            features.set('boosts', { enabled: false, value: 0 });
            features.set('stranger_meet', { enabled: true, value: 'unlimited' });
            features.set('party_creation', { enabled: true, value: 1 }); // 1 party plan per calendar month
        }

        const entry: CacheEntry = {
            plan,
            features,
            expiresAt: Date.now() + CACHE_TTL_MS,
        };
        planCache.set(userId, entry);
        return entry;
    }

    // ── Core Methods ──────────────────────────────────────────────────────────

    /**
     * Check Party Plan creation limit for a user according to Phase 1 & Phase 2 entitlement rules:
     * - Free Plan: Maximum 1 Party Plan per calendar month.
     * - Paid VIP Plan: Maximum 3 Party Plans per calendar day (or configured package limit).
     */
    static async checkPartyPlanLimit(
        userId: string,
        targetDate: Date = new Date(),
        options?: { transaction?: Transaction }
    ): Promise<{
        allowed: boolean;
        tier: string;
        limit: FeatureLimit;
        used: number;
        remaining: FeatureLimit;
        resetAt: Date;
        message?: string;
        code?: string;
    }> {
        try {
            await this.activateUpcomingSubscriptions(userId);

            const activeSub = await UserSubscription.findOne({
                where: {
                    userId,
                    status: SubscriptionStatus.ACTIVE,
                    endDate: { [Op.gt]: new Date() },
                },
                include: [{ model: SubscriptionPackage, as: 'package' }],
                order: [['createdAt', 'DESC']],
                transaction: options?.transaction,
            });

            const plan: SubscriptionPackage | null = (activeSub as any)?.package || null;
            const tier = plan ? plan.tier : 'FREE';

            const refDate = targetDate instanceof Date && !isNaN(targetDate.getTime()) ? targetDate : new Date();

            // Calendar Day Window (server time)
            const startOfDay = new Date(refDate.getFullYear(), refDate.getMonth(), refDate.getDate(), 0, 0, 0, 0);
            const endOfDay = new Date(refDate.getFullYear(), refDate.getMonth(), refDate.getDate(), 23, 59, 59, 999);
            const resetAtDay = new Date(refDate.getFullYear(), refDate.getMonth(), refDate.getDate() + 1, 0, 0, 0, 0);

            // Calendar Month Window (server time)
            const startOfMonth = new Date(refDate.getFullYear(), refDate.getMonth(), 1, 0, 0, 0, 0);
            const endOfMonth = new Date(refDate.getFullYear(), refDate.getMonth() + 1, 0, 23, 59, 59, 999);
            const resetAtMonth = new Date(refDate.getFullYear(), refDate.getMonth() + 1, 1, 0, 0, 0, 0);

            // ── 1. Free Tier Check (1 Party Plan per calendar month) ─────────
            if (!plan || tier === 'FREE') {
                const freeMonthlyLimit = 1;
                const monthlyUsed = await PartyPlan.count({
                    where: {
                        userId,
                        createdAt: { [Op.between]: [startOfMonth, endOfMonth] },
                        status: { [Op.ne]: 'cancelled' },
                    },
                    transaction: options?.transaction,
                });

                if (monthlyUsed >= freeMonthlyLimit) {
                    return {
                        allowed: false,
                        tier: 'FREE',
                        limit: freeMonthlyLimit,
                        used: monthlyUsed,
                        remaining: 0,
                        resetAt: resetAtMonth,
                        code: 'PARTY_PLAN_LIMIT_REACHED',
                        message: `You have reached your Free Plan limit of ${freeMonthlyLimit} Party Plan for this month. Upgrade to VIP to create more party plans!`,
                    };
                }

                return {
                    allowed: true,
                    tier: 'FREE',
                    limit: freeMonthlyLimit,
                    used: monthlyUsed,
                    remaining: Math.max(0, freeMonthlyLimit - monthlyUsed),
                    resetAt: resetAtMonth,
                };
            }

            // ── 2. Paid VIP Tier Check (Maximum 3 Party Plans per calendar day) ──
            let vipDailyLimit: number = 3;
            const planFeature = await SubscriptionPlanFeature.findOne({
                where: { packageId: plan.id, isEnabled: true },
                include: [{
                    model: SubscriptionFeature,
                    as: 'feature',
                    where: { key: 'party_creation' }
                }],
                transaction: options?.transaction,
            });

            if (planFeature && (planFeature as any).value) {
                const val = (planFeature as any).value;
                if (val.value !== undefined && val.value !== 'unlimited') {
                    const num = Number(val.value);
                    if (!isNaN(num) && num > 0) vipDailyLimit = num;
                }
            }

            const dailyUsed = await PartyPlan.count({
                where: {
                    userId,
                    createdAt: { [Op.between]: [startOfDay, endOfDay] },
                    status: { [Op.ne]: 'cancelled' },
                },
                transaction: options?.transaction,
            });

            if (dailyUsed >= vipDailyLimit) {
                return {
                    allowed: false,
                    tier,
                    limit: vipDailyLimit,
                    used: dailyUsed,
                    remaining: 0,
                    resetAt: resetAtDay,
                    code: 'PARTY_PLAN_DAILY_LIMIT_REACHED',
                    message: `You have reached today's Party Plan creation limit of ${vipDailyLimit}. You can schedule more plans tomorrow!`,
                };
            }

            return {
                allowed: true,
                tier,
                limit: vipDailyLimit,
                used: dailyUsed,
                remaining: Math.max(0, vipDailyLimit - dailyUsed),
                resetAt: resetAtDay,
            };
        } catch (err) {
            logger.error('SubscriptionService.checkPartyPlanLimit error:', err);
            return {
                allowed: true,
                tier: 'UNKNOWN',
                limit: UNLIMITED,
                used: 0,
                remaining: UNLIMITED,
                resetAt: new Date(),
            };
        }
    }

    /**
     * Get the user's active plan (cached).
     */
    static async getUserPlan(userId: string): Promise<SubscriptionPackage | null> {
        const cached = await this.getFromCache(userId);
        if (cached) return cached.plan;
        const entry = await this.buildCache(userId);
        return entry.plan;
    }

    /**
     * Check if a user has access to a feature (boolean check).
     * Returns true even for unlimited-value numeric features.
     */
    static async hasAccess(userId: string, featureKey: string): Promise<boolean> {
        if (featureKey === 'stranger_meet') {
            return true;
        }
        try {
            const entry = (await this.getFromCache(userId)) || (await this.buildCache(userId));
            const featureValue = entry.features.get(featureKey);
            if (!featureValue) return false;
            return !!featureValue.enabled;
        } catch (err) {
            logger.error(`SubscriptionService.hasAccess error [${featureKey}]:`, err);
            return false;
        }
    }

    /**
     * Get numeric limit for a feature.
     * Returns 'unlimited' for -1 / unlimited features, or a specific number.
     * Returns 0 if the feature is not accessible.
     */
    static async getLimit(userId: string, featureKey: string): Promise<FeatureLimit> {
        try {
            const entry = (await this.getFromCache(userId)) || (await this.buildCache(userId));
            const featureValue = entry.features.get(featureKey);
            if (!featureValue || !featureValue.enabled) return 0;
            if (featureValue.value === 'unlimited') return UNLIMITED;
            if (typeof featureValue.value === 'number') return featureValue.value;
            return featureValue.enabled ? UNLIMITED : 0;
        } catch (err) {
            logger.error(`SubscriptionService.getLimit error [${featureKey}]:`, err);
            return 0;
        }
    }

    /**
     * Get remaining usage for a feature for this period.
     */
    static async getRemainingUsage(userId: string, featureKey: string, period: UsagePeriod = UsagePeriod.DAILY): Promise<FeatureLimit> {
        try {
            const limit = await this.getLimit(userId, featureKey);
            if (limit === 0) return 0;
            if (limit === UNLIMITED) return UNLIMITED;

            // Get or create usage record
            const usage = await this.getOrResetUsage(userId, featureKey, period);
            const remaining = (limit as number) - usage.used;
            return Math.max(0, remaining);
        } catch (err) {
            logger.error(`SubscriptionService.getRemainingUsage error [${featureKey}]:`, err);
            return 0;
        }
    }

    /**
     * Consume one unit of a feature.
     * Returns success/failure with remaining count.
     */
    static async consumeUsage(userId: string, featureKey: string, amount: number = 1, period: UsagePeriod = UsagePeriod.DAILY): Promise<UsageResult> {
        try {
            const limit = await this.getLimit(userId, featureKey);

            if (limit === 0) {
                return {
                    success: false,
                    remaining: 0,
                    used: 0,
                    limit: 0,
                    message: `You don't have access to this feature. Upgrade your plan.`,
                };
            }

            if (limit === UNLIMITED) {
                // Still track usage for analytics, but always allow
                await this.incrementUsage(userId, featureKey, period, amount);
                return {
                    success: true,
                    remaining: UNLIMITED,
                    used: amount,
                    limit: UNLIMITED,
                };
            }

            const usage = await this.getOrResetUsage(userId, featureKey, period);
            const newUsed = usage.used + amount;

            if (newUsed > (limit as number)) {
                return {
                    success: false,
                    remaining: Math.max(0, (limit as number) - usage.used),
                    used: usage.used,
                    limit,
                    message: `Daily limit reached. You've used ${usage.used} of ${limit} ${featureKey.replace(/_/g, ' ')}.`,
                };
            }

            await usage.update({ used: newUsed });

            return {
                success: true,
                remaining: (limit as number) - newUsed,
                used: newUsed,
                limit,
            };
        } catch (err) {
            logger.error(`SubscriptionService.consumeUsage error [${featureKey}]:`, err);
            return {
                success: false,
                remaining: 0,
                used: 0,
                limit: 0,
                message: 'Server error checking usage limits.',
            };
        }
    }

    /**
     * Reset all daily usage counters for a user (called by cron at midnight).
     */
    static async resetDailyUsage(userId?: string): Promise<void> {
        try {
            const where: any = { period: UsagePeriod.DAILY };
            if (userId) where.userId = userId;
            await SubscriptionUsage.update({ used: 0, resetAt: new Date() }, { where });
            if (userId) this.invalidateCache(userId);
        } catch (err) {
            logger.error('SubscriptionService.resetDailyUsage error:', err);
        }
    }

    /**
     * Reset weekly usage counters (called by cron on Monday).
     */
    static async resetWeeklyUsage(userId?: string): Promise<void> {
        try {
            const where: any = { period: UsagePeriod.WEEKLY };
            if (userId) where.userId = userId;
            await SubscriptionUsage.update({ used: 0, resetAt: new Date() }, { where });
        } catch (err) {
            logger.error('SubscriptionService.resetWeeklyUsage error:', err);
        }
    }

    /**
     * Reset monthly usage counters (called by cron on 1st of month).
     */
    static async resetMonthlyUsage(userId?: string): Promise<void> {
        try {
            const where: any = { period: UsagePeriod.MONTHLY };
            if (userId) where.userId = userId;
            await SubscriptionUsage.update({ used: 0, resetAt: new Date() }, { where });
        } catch (err) {
            logger.error('SubscriptionService.resetMonthlyUsage error:', err);
        }
    }

    /**
     * Get complete feature summary for a user (for profile screen).
     */
    static async getUserFeatureSummary(userId: string): Promise<Record<string, any>> {
        try {
            const entry = (await this.getFromCache(userId)) || (await this.buildCache(userId));
            const summary: Record<string, any> = {};

            for (const [key, val] of entry.features.entries()) {
                const limit = val.value === 'unlimited' ? UNLIMITED : (val.value ?? (val.enabled ? UNLIMITED : 0));
                summary[key] = {
                    enabled: val.enabled,
                    limit,
                };
            }

            return summary;
        } catch (err) {
            logger.error('SubscriptionService.getUserFeatureSummary error:', err);
            return {};
        }
    }

    /**
     * Get the complete subscription status for a user — single call for UI.
     * Returns tier, limits, usage, boosts, superlikes, feature flags.
     */
    static async getFullStatus(userId: string): Promise<Record<string, any>> {
        try {
            const entry = (await this.getFromCache(userId)) || (await this.buildCache(userId));
            const plan = entry.plan;

            // Get active subscription record (for boosts/superlikes remaining)
            const subscription = await UserSubscription.findOne({
                where: {
                    userId,
                    status: SubscriptionStatus.ACTIVE,
                    endDate: { [Op.gt]: new Date() },
                },
                order: [['createdAt', 'DESC']],
            });

            // Determine tier
            const tier = plan ? plan.tier : 'FREE';
            const tierRankMap: Record<string, number> = {
                FREE: 0, CORE: 1, PLUS: 2, PRO: 3, ELITE: 4,
            };
            const tierRank = tierRankMap[tier] ?? 0;

            // Collect feature limits from cache
            const featuresOut: Record<string, any> = {};
            for (const [key, val] of entry.features.entries()) {
                featuresOut[key] = {
                    enabled: val.enabled,
                    limit: val.value === 'unlimited' ? 'unlimited' : (val.value ?? 0),
                };
            }

            // Get daily usage
            const usageRecords = await SubscriptionUsage.findAll({
                where: { userId, period: UsagePeriod.DAILY },
            });
            const usageMap: Record<string, number> = {};
            for (const u of usageRecords) {
                usageMap[u.featureKey] = u.used;
            }

            // Remaining days
            let remainingDays = 0;
            if (subscription) {
                const now = new Date();
                const end = new Date(subscription.endDate);
                remainingDays = Math.max(0, Math.ceil((end.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)));
            }

            return {
                isActive: !!subscription,
                tier,
                tierRank,
                planName: plan?.name ?? 'Free',
                packageId: plan?.id ?? null,
                remainingDays,
                superlikesRemaining: subscription?.superlikesRemaining ?? 0,
                superlikesPerCycle: plan?.superlikesPerCycle ?? 0,
                boostsRemaining: subscription?.boostsRemaining ?? 0,
                boostsPerCycle: plan?.boostsPerCycle ?? 0,
                hasPriorityVisibility: plan?.hasPriorityVisibility ?? false,
                hasTrustBadge: plan?.hasTrustBadge ?? false,
                hasEliteBadge: plan?.hasEliteBadge ?? false,
                canSeeWhoLiked: plan?.canSeeWhoLiked ?? false,
                dailyLikesLimit: featuresOut['daily_likes']?.limit ?? 7,
                dailyLikesUsed: usageMap['daily_likes'] ?? 0,
                dailyMatchRequestsLimit: featuresOut['daily_match_requests']?.limit ?? 3,
                dailyMatchRequestsUsed: usageMap['daily_match_requests'] ?? 0,
                dailyPostsLimit: featuresOut['daily_posts']?.limit ?? 5,
                dailyPostsUsed: usageMap['daily_posts'] ?? 0,
                dailyBacktrackLimit: featuresOut['daily_backtracks']?.limit ?? 3,
                dailyBacktrackUsed: usageMap['daily_backtracks'] ?? 0,
                features: featuresOut,
                usage: usageMap,
            };
        } catch (err) {
            logger.error('SubscriptionService.getFullStatus error:', err);
            return {
                isActive: false,
                tier: 'FREE',
                tierRank: 0,
                planName: 'Free',
                remainingDays: 0,
                superlikesRemaining: 0,
                boostsRemaining: 0,
                dailyLikesLimit: 7,
                dailyLikesUsed: 0,
                features: {},
                usage: {},
            };
        }
    }

    // ── Internal Helpers ──────────────────────────────────────────────────────

    private static async getOrResetUsage(userId: string, featureKey: string, period: UsagePeriod): Promise<SubscriptionUsage> {
        let usage = await SubscriptionUsage.findOne({
            where: { userId, featureKey, period },
        });

        if (!usage) {
            usage = await SubscriptionUsage.create({
                userId,
                featureKey,
                period,
                used: 0,
                resetAt: this.nextResetDate(period),
            });
            return usage;
        }

        // Check if reset is needed
        if (usage.resetAt && new Date() > usage.resetAt) {
            await usage.update({ used: 0, resetAt: this.nextResetDate(period) });
        }

        return usage;
    }

    private static async incrementUsage(userId: string, featureKey: string, period: UsagePeriod, amount: number): Promise<void> {
        const [usage] = await SubscriptionUsage.findOrCreate({
            where: { userId, featureKey, period },
            defaults: { used: 0, resetAt: this.nextResetDate(period) },
        });
        await usage.increment('used', { by: amount });
    }

    private static nextResetDate(period: UsagePeriod): Date {
        const now = new Date();
        switch (period) {
            case UsagePeriod.DAILY: {
                const tomorrow = new Date(now);
                tomorrow.setDate(tomorrow.getDate() + 1);
                tomorrow.setHours(0, 0, 0, 0);
                return tomorrow;
            }
            case UsagePeriod.WEEKLY: {
                const nextWeek = new Date(now);
                const dayOfWeek = now.getDay();
                const daysUntilMonday = (8 - dayOfWeek) % 7 || 7;
                nextWeek.setDate(nextWeek.getDate() + daysUntilMonday);
                nextWeek.setHours(0, 0, 0, 0);
                return nextWeek;
            }
            case UsagePeriod.MONTHLY: {
                const nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1, 0, 0, 0, 0);
                return nextMonth;
            }
            default:
                // Lifetime — no reset
                return new Date(2099, 0, 1);
        }
    }
}

export default SubscriptionService;
