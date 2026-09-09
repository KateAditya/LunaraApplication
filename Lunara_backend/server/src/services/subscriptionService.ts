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
import sequelize from '../config/database';
import '../models';
import SubscriptionPackage, { PackageTier } from '../models/SubscriptionPackage';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import SubscriptionPlanFeature from '../models/SubscriptionPlanFeature';
import SubscriptionFeature from '../models/SubscriptionFeature';
import SubscriptionUsage, { UsagePeriod } from '../models/SubscriptionUsage';
import UserAddon, { UserAddonStatus } from '../models/UserAddon';
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
    // The active UserSubscription's own endDate (distinct from `expiresAt`,
    // which is just this cache entry's TTL) — checked on every cache hit so
    // a subscription that expires mid-window can't keep granting VIP limits
    // (e.g. unlimited likes/superlikes) until the cache entry's TTL happens
    // to lapse.
    subscriptionEndDate: Date | null;
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
            if (entry.subscriptionEndDate && entry.subscriptionEndDate <= new Date()) {
                // The subscription expired since this entry was cached — do not
                // keep serving VIP-tier limits from a stale cache hit.
                planCache.delete(userId);
                return null;
            }
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

        // 2. See if there is any CURRENTLY active PAID subscription.
        // Excludes the lifetime FREE-tier stub (created for à-la-carte
        // credit purchases before ever subscribing, endDate ~2099,
        // status ACTIVE) — otherwise its permanent presence would block
        // every queued UPCOMING paid subscription from ever activating.
        const activeSub = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE },
            include: [{ model: SubscriptionPackage, as: 'package', where: { tier: { [Op.ne]: PackageTier.FREE } }, required: true }],
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
                // Read from package columns (single source of truth)
                for (const [featureKey, mapping] of Object.entries(LEGACY_COLUMN_MAP)) {
                    const rawVal = (plan as any)[mapping.column];
                    if (mapping.isBoolean) {
                        features.set(featureKey, { enabled: !!rawVal });
                    } else {
                        const numVal = Number(rawVal);
                        features.set(featureKey, {
                            enabled: numVal !== 0,
                            value: (numVal === -1 || numVal >= 9999) ? 'unlimited' : numVal,
                        });
                    }
                }
            }

            // Party plan & stranger meet access
            const partyLimit = (plan as any).partyPlanLimit ?? (plan.tier === PackageTier.ELITE ? -1 : 3);
            features.set('party_creation', {
                enabled: true,
                value: (partyLimit === -1 || partyLimit >= 9999 || plan.tier === PackageTier.ELITE) ? 'unlimited' : Number(partyLimit),
                periodDays: (plan as any).partyPlanPeriodDays ?? (plan.tier === PackageTier.ELITE ? 1 : 1),
            });
            features.set('stranger_meet', { enabled: true, value: 'unlimited' });

            // Elite tier overrides for unlimited features
            if ((plan.tier as any) === PackageTier.ELITE || (plan.tier as any) === 'ELITE') {
                features.set('super_likes', { enabled: true, value: 'unlimited' });
                features.set('superlike', { enabled: true, value: 'unlimited' });
                features.set('boosts', { enabled: true, value: 'unlimited' });
                features.set('boost', { enabled: true, value: 'unlimited' });
                features.set('profile_boost', { enabled: true, value: 'unlimited' });
                features.set('daily_backtracks', { enabled: true, value: 'unlimited' });
                features.set('backtrack', { enabled: true, value: 'unlimited' });
                features.set('party_creation', { enabled: true, value: 'unlimited', periodDays: 1 });
            }
        } else {
            // Unsubscribed users: use the admin-configured FREE tier package
            // as the source of truth, falling back to configured defaults
            const freePkg = await SubscriptionPackage.findOne({
                where: { tier: PackageTier.FREE, isActive: true },
                order: [['createdAt', 'DESC']],
            });

            const freeLikes = freePkg ? Number(freePkg.dailyLikes) : 7;
            const freeSuperlikes = freePkg ? Number(freePkg.superlikesPerCycle) : 0;
            const freeBoosts = freePkg ? Number(freePkg.boostsPerCycle) : 0;
            const freePartyLimit = freePkg ? Number((freePkg as any).partyPlanLimit ?? 1) : 1;
            const freePartyPeriodDays = freePkg ? Number((freePkg as any).partyPlanPeriodDays ?? 7) : 7;
            const freeMatchReqs = freePkg ? Number(freePkg.dailyMatchRequests) : 3;
            const freePosts = freePkg ? Number(freePkg.dailyPosts) : 5;
            const freeBacktracks = freePkg ? Number(freePkg.backtrackLimit) : 3;
            const freeCanSeeWhoLiked = freePkg ? !!freePkg.canSeeWhoLiked : false;

            features.set('daily_likes', { enabled: freeLikes > 0, value: freeLikes });
            features.set('daily_match_requests', { enabled: freeMatchReqs > 0, value: freeMatchReqs });
            features.set('daily_posts', { enabled: freePosts > 0, value: freePosts });
            features.set('daily_backtracks', { enabled: freeBacktracks > 0, value: freeBacktracks });
            features.set('super_likes', { enabled: freeSuperlikes > 0, value: freeSuperlikes });
            features.set('superlike', { enabled: freeSuperlikes > 0, value: freeSuperlikes });
            features.set('boosts', { enabled: freeBoosts > 0, value: freeBoosts });
            features.set('profile_boost', { enabled: freeBoosts > 0, value: freeBoosts });
            features.set('stranger_meet', { enabled: true, value: 'unlimited' });
            features.set('party_creation', { enabled: freePartyLimit > 0, value: freePartyLimit, periodDays: freePartyPeriodDays });
            features.set('who_liked_me', { enabled: freeCanSeeWhoLiked });
        }

        const entry: CacheEntry = {
            plan,
            features,
            expiresAt: Date.now() + CACHE_TTL_MS,
            subscriptionEndDate: subscription ? (subscription as any).endDate : null,
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
        _targetDate: Date = new Date(),
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

            // ── 1. Free Tier Check (Rolling period from plan config, default 1 per 7 days) ──
            if (!plan || tier === 'FREE') {
                const freePkg = await SubscriptionPackage.findOne({
                    where: { tier: PackageTier.FREE, isActive: true },
                    order: [['createdAt', 'DESC']],
                    transaction: options?.transaction,
                });

                const freeLimit = freePkg ? Number((freePkg as any).partyPlanLimit ?? 1) : 1;
                const freePeriodDays = freePkg ? Number((freePkg as any).partyPlanPeriodDays ?? 7) : 7;
                const rollingWindowStart = new Date(Date.now() - (freePeriodDays * 24 * 60 * 60 * 1000));

                const recentPlans = await PartyPlan.findAll({
                    where: {
                        userId,
                        createdAt: { [Op.gte]: rollingWindowStart },
                        status: { [Op.ne]: 'cancelled' },
                    },
                    order: [['createdAt', 'ASC']],
                    transaction: options?.transaction,
                });

                const usedCount = recentPlans.length;

                if (usedCount >= freeLimit) {
                    // Check if user has active party_creation add-on credits
                    try {
                        const UserAddonModel = (await import('../models/UserAddon')).default;
                        const activeAddon = await UserAddonModel.findOne({
                            where: {
                                userId,
                                featureKey: 'party_creation',
                                status: 'ACTIVE',
                                remainingQuantity: { [Op.gt]: 0 },
                            },
                            transaction: options?.transaction,
                        });

                        if (activeAddon && activeAddon.remainingQuantity > 0) {
                            return {
                                allowed: true,
                                tier: 'FREE (Add-on Active)',
                                limit: freeLimit + activeAddon.remainingQuantity,
                                used: usedCount,
                                remaining: activeAddon.remainingQuantity,
                                resetAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
                            };
                        }
                    } catch (addonErr) {
                        logger.warn('[checkPartyPlanLimit] Error checking party add-on:', addonErr);
                    }

                    const oldestPlan = recentPlans[0];
                    const nextAvailableAt = oldestPlan
                        ? new Date(oldestPlan.createdAt.getTime() + (freePeriodDays * 24 * 60 * 60 * 1000))
                        : new Date(Date.now() + (freePeriodDays * 24 * 60 * 60 * 1000));
                    
                    const daysRemaining = Math.max(1, Math.ceil((nextAvailableAt.getTime() - Date.now()) / (1000 * 60 * 60 * 24)));

                    return {
                        allowed: false,
                        tier: 'FREE',
                        limit: freeLimit,
                        used: usedCount,
                        remaining: 0,
                        resetAt: nextAvailableAt,
                        code: 'PARTY_PLAN_LIMIT_REACHED',
                        message: `Free users can create ${freeLimit} Party Plan during the current ${freePeriodDays}-day period. Next plan available in ${daysRemaining} day(s). Upgrade to VIP for more!`,
                    };
                }

                return {
                    allowed: true,
                    tier: 'FREE',
                    limit: freeLimit,
                    used: usedCount,
                    remaining: Math.max(0, freeLimit - usedCount),
                    resetAt: new Date(Date.now() + (freePeriodDays * 24 * 60 * 60 * 1000)),
                };
            }

            // ── 2. Elite Tier Check (Unlimited Party Plans) ─────────────────
            if (tier === 'ELITE') {
                return {
                    allowed: true,
                    tier: 'ELITE',
                    limit: UNLIMITED,
                    used: 0,
                    remaining: UNLIMITED,
                    resetAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
                };
            }

            // ── 3. Paid VIP Tier Check (Admin-configured limit and period) ──
            let vipLimit: FeatureLimit = (plan as any).partyPlanLimit ?? 3;
            let vipPeriodDays = (plan as any).partyPlanPeriodDays ?? 1;

            if (vipLimit === -1 || Number(vipLimit) >= 9999) {
                return {
                    allowed: true,
                    tier,
                    limit: UNLIMITED,
                    used: 0,
                    remaining: UNLIMITED,
                    resetAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
                };
            }

            const vipWindowStart = new Date(Date.now() - (vipPeriodDays * 24 * 60 * 60 * 1000));
            const recentVipPlans = await PartyPlan.findAll({
                where: {
                    userId,
                    createdAt: { [Op.gte]: vipWindowStart },
                    status: { [Op.ne]: 'cancelled' },
                },
                order: [['createdAt', 'ASC']],
                transaction: options?.transaction,
            });

            const vipUsed = recentVipPlans.length;
            const numericVipLimit = Number(vipLimit);

            if (vipUsed >= numericVipLimit) {
                // Check if user has active party_creation add-on credits
                try {
                    const UserAddonModel = (await import('../models/UserAddon')).default;
                    const activeAddon = await UserAddonModel.findOne({
                        where: {
                            userId,
                            featureKey: 'party_creation',
                            status: 'ACTIVE',
                            remainingQuantity: { [Op.gt]: 0 },
                        },
                        transaction: options?.transaction,
                    });

                    if (activeAddon && activeAddon.remainingQuantity > 0) {
                        return {
                            allowed: true,
                            tier: `${tier} (Add-on Active)`,
                            limit: numericVipLimit + activeAddon.remainingQuantity,
                            used: vipUsed,
                            remaining: activeAddon.remainingQuantity,
                            resetAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
                        };
                    }
                } catch (addonErr) {
                    logger.warn('[checkPartyPlanLimit] Error checking party add-on:', addonErr);
                }

                const oldestVipPlan = recentVipPlans[0];
                const nextVipAvailableAt = oldestVipPlan
                    ? new Date(oldestVipPlan.createdAt.getTime() + (vipPeriodDays * 24 * 60 * 60 * 1000))
                    : new Date(Date.now() + (vipPeriodDays * 24 * 60 * 60 * 1000));

                return {
                    allowed: false,
                    tier,
                    limit: numericVipLimit,
                    used: vipUsed,
                    remaining: 0,
                    resetAt: nextVipAvailableAt,
                    code: 'PARTY_PLAN_LIMIT_REACHED',
                    message: `You have reached your limit of ${numericVipLimit} Party Plan(s) for the current ${vipPeriodDays}-day period.`,
                };
            }

            return {
                allowed: true,
                tier,
                limit: numericVipLimit,
                used: vipUsed,
                remaining: Math.max(0, numericVipLimit - vipUsed),
                resetAt: new Date(Date.now() + (vipPeriodDays * 24 * 60 * 60 * 1000)),
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
            if (featureValue && (featureValue.enabled || featureValue.value)) {
                return true;
            }

            const plan = entry.plan;
            if (plan) {
                if (featureKey === 'hide_profile') {
                    return !!plan.hasHideProfile || ['PLUS', 'PRO', 'ELITE'].includes(plan.tier);
                }
                if (featureKey === 'priority_visibility') return !!plan.hasPriorityVisibility;
                if (featureKey === 'trust_badge') return !!plan.hasTrustBadge;
                if (featureKey === 'elite_badge') return !!plan.hasEliteBadge;
                if (featureKey === 'who_liked_me') return !!plan.canSeeWhoLiked;
            }
            return false;
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
            const plan = entry.plan;

            // Elite tier overrides for unlimited features
            if (plan && ((plan.tier as any) === PackageTier.ELITE || (plan.tier as any) === 'ELITE')) {
                if (['super_likes', 'superlike', 'boosts', 'boost', 'profile_boost', 'daily_backtracks', 'backtrack', 'party_creation', 'party_plan'].includes(featureKey)) {
                    return UNLIMITED;
                }
            }

            const featureValue = entry.features.get(featureKey);
            if (!featureValue || !featureValue.enabled) return 0;
            if (featureValue.value === 'unlimited' || featureValue.value === -1 || featureValue.value >= 9999) return UNLIMITED;
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
                // Concurrency-safe atomic usage increment with date check
                const currentUsed = await this.incrementUsage(userId, featureKey, period, amount);
                return {
                    success: true,
                    remaining: UNLIMITED,
                    used: currentUsed,
                    limit: UNLIMITED,
                };
            }

            const usage = await this.getOrResetUsage(userId, featureKey, period);
            if (usage.used + amount > (limit as number)) {
                return {
                    success: false,
                    remaining: Math.max(0, (limit as number) - usage.used),
                    used: usage.used,
                    limit,
                    message: `Daily limit reached. You've used ${usage.used} of ${limit} ${featureKey.replace(/_/g, ' ')}. Upgrade to Lunara VIP for unlimited access!`,
                };
            }

            // Atomic conditional update: prevents race condition if multiple requests arrive simultaneously
            const [affected] = await SubscriptionUsage.update(
                { used: sequelize.literal(`used + ${amount}`) },
                {
                    where: {
                        id: usage.id,
                        used: { [Op.lte]: (limit as number) - amount },
                    },
                }
            );

            if (affected === 0) {
                const refreshed = await SubscriptionUsage.findByPk(usage.id);
                const currUsed = refreshed?.used ?? (limit as number);
                return {
                    success: false,
                    remaining: Math.max(0, (limit as number) - currUsed),
                    used: currUsed,
                    limit,
                    message: `Daily limit reached. You've used ${currUsed} of ${limit} ${featureKey.replace(/_/g, ' ')}.`,
                };
            }

            const newUsed = usage.used + amount;
            return {
                success: true,
                remaining: Math.max(0, (limit as number) - newUsed),
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

            // 1. Get active subscription record
            const subscription = await UserSubscription.findOne({
                where: {
                    userId,
                    status: SubscriptionStatus.ACTIVE,
                    endDate: { [Op.gt]: new Date() },
                },
                include: [{ model: SubscriptionPackage, as: 'package' }],
                order: [['createdAt', 'DESC']],
            });

            // 2. Check if there is a recently expired paid subscription (within last 7 days) if no active sub
            let lastExpiredSub: any = null;
            if (!subscription) {
                lastExpiredSub = await UserSubscription.findOne({
                    where: {
                        userId,
                        status: SubscriptionStatus.EXPIRED,
                        endDate: { [Op.gte]: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) },
                    },
                    include: [{ model: SubscriptionPackage, as: 'package', where: { tier: { [Op.ne]: PackageTier.FREE } }, required: true }],
                    order: [['endDate', 'DESC']],
                });
            }

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

            // Remaining days & hours calculation
            let remainingDays = 0;
            let remainingHours = 0;
            let isExpiringSoon = false;
            let isExpired = false;
            let expirationAlert: any = null;

            if (subscription) {
                const now = new Date();
                const end = new Date(subscription.endDate);
                const diffMs = end.getTime() - now.getTime();
                remainingHours = Math.max(0, Math.round(diffMs / (1000 * 60 * 60)));
                remainingDays = Math.max(0, Math.ceil(diffMs / (1000 * 60 * 60 * 24)));

                const currentPkg = (subscription as any).package || plan;
                const isPaidTier = currentPkg && currentPkg.tier !== PackageTier.FREE;

                if (isPaidTier && remainingHours <= 24) {
                    isExpiringSoon = true;
                    const pkgName = currentPkg.name || 'VIP Membership';
                    let alertTitle = 'VIP Subscription Expiring Tomorrow ⏳';
                    let alertBody = `Your ${pkgName} expires in ${remainingHours} hours. Renew now to continue enjoying VIP benefits uninterrupted.`;
                    let eventType = 'vip_expiring_1day';

                    if (remainingHours <= 1) {
                        alertTitle = 'VIP Subscription Expiring in 1 Hour! 🔔';
                        alertBody = `Final Call: Your ${pkgName} expires in 1 hour. Tap to renew instantly.`;
                        eventType = 'vip_expiring_1hour';
                    } else if (remainingHours <= 2) {
                        alertTitle = 'VIP Subscription Expiring in 2 Hours 🚨';
                        alertBody = `Only 2 hours left on your ${pkgName}! Renew now before VIP features are locked.`;
                        eventType = 'vip_expiring_2hours';
                    } else if (remainingHours <= 5) {
                        alertTitle = 'VIP Subscription Expiring in 5 Hours ⏱️';
                        alertBody = `Your ${pkgName} expires in 5 hours. Tap to renew and maintain your VIP status.`;
                        eventType = 'vip_expiring_5hours';
                    } else if (remainingHours <= 8) {
                        alertTitle = 'VIP Subscription Expiring in 8 Hours ⚠️';
                        alertBody = `Your ${pkgName} expires in 8 hours. Renew now to keep your VIP badge and features.`;
                        eventType = 'vip_expiring_8hours';
                    }

                    expirationAlert = {
                        title: alertTitle,
                        body: alertBody,
                        message: alertBody,
                        planName: pkgName,
                        remainingHours,
                        isExpired: false,
                        eventType,
                        expiresAt: subscription.endDate.toISOString(),
                    };
                }
            } else if (lastExpiredSub) {
                isExpired = true;
                const expiredPkg = (lastExpiredSub as any).package;
                const pkgName = expiredPkg?.name || 'VIP Membership';
                expirationAlert = {
                    title: 'VIP Subscription Expired ❌',
                    body: `Your ${pkgName} has expired. Renew now to unlock unlimited likes, verified badges, and VIP features!`,
                    message: `Your ${pkgName} has expired. Renew now to unlock unlimited likes, verified badges, and VIP features!`,
                    planName: pkgName,
                    remainingHours: 0,
                    isExpired: true,
                    eventType: 'vip_expired',
                    expiresAt: lastExpiredSub.endDate.toISOString(),
                };
            }

            let addonSuperlikes = 0;
            let addonBoosts = 0;
            let addonBacktracks = 0;
            let addonPartyPlans = 0;
            try {
                const userAddons = await UserAddon.findAll({
                    where: {
                        userId,
                        status: UserAddonStatus.ACTIVE,
                        remainingQuantity: { [Op.gt]: 0 },
                    },
                });
                for (const ua of userAddons) {
                    const r = Number(ua.remainingQuantity) || 0;
                    if (ua.featureKey === 'superlike') addonSuperlikes += r;
                    else if (ua.featureKey === 'profile_boost') addonBoosts += r;
                    else if (ua.featureKey === 'backtrack' || ua.featureKey === 'undo') addonBacktracks += r;
                    else if (ua.featureKey === 'party_creation') addonPartyPlans += r;
                }
            } catch (err) {
                logger.warn('[subscriptionService.getFullStatus] Could not fetch user addons:', err);
            }

            const planSuperlikes = (tier === 'ELITE') ? 9999 : (subscription?.superlikesRemaining ?? 0);
            const planSuperlikesPerCycle = (tier === 'ELITE') ? 9999 : (plan?.superlikesPerCycle ?? 0);
            const planBoosts = (tier === 'ELITE') ? 9999 : (subscription?.boostsRemaining ?? 0);
            const planBoostsPerCycle = (tier === 'ELITE') ? 9999 : (plan?.boostsPerCycle ?? 0);

            return {
                isActive: !!subscription,
                tier,
                tierRank,
                planName: plan?.name ?? 'Free',
                packageId: plan?.id ?? null,
                remainingDays,
                remainingHours,
                endDate: subscription ? subscription.endDate.toISOString() : (lastExpiredSub ? lastExpiredSub.endDate.toISOString() : null),
                isExpiringSoon,
                isExpired,
                expirationAlert,
                superlikesRemaining: (tier === 'ELITE') ? 9999 : (planSuperlikes + addonSuperlikes),
                superlikesPerCycle: (tier === 'ELITE') ? 9999 : (planSuperlikesPerCycle + addonSuperlikes),
                boostsRemaining: (tier === 'ELITE') ? 9999 : (planBoosts + addonBoosts),
                boostsPerCycle: (tier === 'ELITE') ? 9999 : (planBoostsPerCycle + addonBoosts),
                hasPriorityVisibility: plan?.hasPriorityVisibility ?? (['PRO', 'ELITE'].includes(tier)),
                hasTrustBadge: plan?.hasTrustBadge ?? (['PRO', 'ELITE'].includes(tier)),
                hasEliteBadge: plan?.hasEliteBadge ?? (tier === 'ELITE'),
                canSeeWhoLiked: plan?.canSeeWhoLiked ?? (['CORE', 'PLUS', 'PRO', 'ELITE'].includes(tier)),
                hasHideProfile: plan?.hasHideProfile ?? (['PLUS', 'PRO', 'ELITE'].includes(tier)),
                dailyLikesLimit: featuresOut['daily_likes']?.limit ?? (plan ? ((plan.dailyLikes === -1 || plan.dailyLikes >= 9999) ? 'unlimited' : plan.dailyLikes) : 7),
                dailyLikesUsed: usageMap['daily_likes'] ?? 0,
                dailyMatchRequestsLimit: featuresOut['daily_match_requests']?.limit ?? (plan ? ((plan.dailyMatchRequests === -1 || plan.dailyMatchRequests >= 9999) ? 'unlimited' : plan.dailyMatchRequests) : 3),
                dailyMatchRequestsUsed: usageMap['daily_match_requests'] ?? 0,
                dailyPostsLimit: featuresOut['daily_posts']?.limit ?? (plan ? ((plan.dailyPosts === -1 || plan.dailyPosts >= 9999) ? 'unlimited' : plan.dailyPosts) : 5),
                dailyPostsUsed: usageMap['daily_posts'] ?? 0,
                dailyBacktrackLimit: (tier === 'ELITE') ? 'unlimited' : (featuresOut['daily_backtracks']?.limit ?? ((plan ? plan.backtrackLimit : 3) + addonBacktracks)),
                dailyBacktrackUsed: usageMap['daily_backtracks'] ?? 0,
                partyPlanLimit: featuresOut['party_creation']?.limit ?? (plan ? ((plan.partyPlanLimit === -1 || plan.partyPlanLimit >= 9999) ? 'unlimited' : (plan.partyPlanLimit + addonPartyPlans)) : (1 + addonPartyPlans)),
                partyPlanPeriodDays: featuresOut['party_creation']?.periodDays ?? (plan ? plan.partyPlanPeriodDays : 7),
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

    private static async incrementUsage(userId: string, featureKey: string, period: UsagePeriod, amount: number): Promise<number> {
        let usage = await SubscriptionUsage.findOne({
            where: { userId, featureKey, period },
        });

        if (!usage) {
            usage = await SubscriptionUsage.create({
                userId,
                featureKey,
                period,
                used: amount,
                resetAt: this.nextResetDate(period),
            });
            return amount;
        }

        const now = new Date();
        if (usage.resetAt && now > usage.resetAt) {
            await usage.update({ used: amount, resetAt: this.nextResetDate(period) });
            return amount;
        }

        await usage.increment('used', { by: amount });
        await usage.reload();
        return usage.used;
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
