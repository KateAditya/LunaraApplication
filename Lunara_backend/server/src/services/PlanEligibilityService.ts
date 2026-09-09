import { Op, Transaction } from 'sequelize';
import sequelize from '../config/database';
import User from '../models/User';
import UserSubscription from '../models/UserSubscription';
import SubscriptionPackage from '../models/SubscriptionPackage';
import PlanTimeLock from '../models/PlanTimeLock';
import PlanTimeLockConfig, { PlanTimeLockConfigAttributes } from '../models/PlanTimeLockConfig';
import NotificationJob from '../models/NotificationJob';
import PartyPlan from '../models/PartyPlan';
import { SubscriptionService } from './subscriptionService';

// Unique 32-bit signed integer hash function for Postgres transaction advisory lock
export function getAdvisoryLockKey(uuidStr: string): number {
    let hash = 0;
    for (let i = 0; i < uuidStr.length; i++) {
        const char = uuidStr.charCodeAt(i);
        hash = (hash << 5) - hash + char;
        hash |= 0; // Convert to 32-bit signed integer
    }
    return hash;
}

export function formatFriendlyTime(date: Date): string {
    const hours = date.getHours();
    const minutes = date.getMinutes();
    const ampm = hours >= 12 ? 'PM' : 'AM';
    const h12 = hours % 12 === 0 ? 12 : hours % 12;
    const mStr = minutes < 10 ? `0${minutes}` : `${minutes}`;
    return `${h12}:${mStr} ${ampm}`;
}

export function formatFriendlyDate(date: Date, relativeTo: Date = new Date()): string {
    const d1 = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    const d2 = new Date(relativeTo.getFullYear(), relativeTo.getMonth(), relativeTo.getDate());
    const diffDays = Math.round((d1.getTime() - d2.getTime()) / (24 * 60 * 60 * 1000));
    if (diffDays === 0) return 'Today';
    if (diffDays === 1) return 'Tomorrow';
    if (diffDays === -1) return 'Yesterday';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return `${months[date.getMonth()]} ${date.getDate()}`;
}

export function formatFriendlyDateTime(date: Date, relativeTo: Date = new Date()): string {
    const dateStr = formatFriendlyDate(date, relativeTo);
    const timeStr = formatFriendlyTime(date);
    return `${dateStr} at ${timeStr}`;
}

export class PlanEligibilityService {
    /**
     * Resolves the hierarchical configurations for a user and a specific plan type.
     * Order of Precedence (highest overrides lowest):
     * 1. User Override (scope: 'user:UUID')
     * 2. Plan Type (scope: 'plan_type:TYPE')
     * 3. User Role (scope: 'role:ROLE')
     * 4. Subscription Plan (scope: 'subscription:TIER')
     * 5. Global (scope: 'global')
     */
    public static async resolveConfig(
        userId: string,
        planType: string
    ): Promise<PlanTimeLockConfigAttributes> {
        // Resolve user role
        const user = await User.findByPk(userId);
        const role = user?.role || 'customer';

        // Resolve subscription tier
        let tier = 'FREE';
        const activeSub = await UserSubscription.findOne({
            where: { userId, status: 'ACTIVE' },
            include: [{ model: SubscriptionPackage, as: 'package' }]
        });
        if (activeSub && (activeSub as any).package) {
            tier = (activeSub as any).package.tier;
        }

        const scopes = [
            'global',
            `subscription:${tier}`,
            `role:${role}`,
            `plan_type:${planType}`,
            `user:${userId}`
        ];

        const configs = await PlanTimeLockConfig.findAll({
            where: { scope: { [Op.in]: scopes } }
        });

        // Initialize with fallback defaults (allow up to 3 active intra-day non-overlapping plans)
        const resolved: PlanTimeLockConfigAttributes = {
            id: 'resolved',
            scope: 'resolved',
            timeLockEnabled: true,
            defaultCooldownHours: 4,
            maxActivePlans: 3,
            maxDailyPlans: 3,
            maxWeeklyPlans: 10,
            allowOverlappingPlans: false,
            allowSameVenue: false,
            allowDifferentVenue: false,
            allowFuturePlans: true,
            allowEmergencyOverride: false,
            overlapPolicy: 'NO_OVERLAP'
        };

        // Merge in strict order of precedence
        const scopeOrder = [
            'global',
            `subscription:${tier}`,
            `role:${role}`,
            `plan_type:${planType}`,
            `user:${userId}`
        ];

        for (const scopeKey of scopeOrder) {
            const match = configs.find(c => c.scope === scopeKey);
            if (match) {
                if (match.timeLockEnabled !== undefined) resolved.timeLockEnabled = match.timeLockEnabled;
                if (match.defaultCooldownHours !== undefined) resolved.defaultCooldownHours = match.defaultCooldownHours;
                if (match.maxActivePlans !== undefined) resolved.maxActivePlans = match.maxActivePlans;
                if (match.maxDailyPlans !== undefined) resolved.maxDailyPlans = match.maxDailyPlans;
                if (match.maxWeeklyPlans !== undefined) resolved.maxWeeklyPlans = match.maxWeeklyPlans;
                if (match.allowOverlappingPlans !== undefined) resolved.allowOverlappingPlans = match.allowOverlappingPlans;
                if (match.allowSameVenue !== undefined) resolved.allowSameVenue = match.allowSameVenue;
                if (match.allowDifferentVenue !== undefined) resolved.allowDifferentVenue = match.allowDifferentVenue;
                if (match.allowFuturePlans !== undefined) resolved.allowFuturePlans = match.allowFuturePlans;
                if (match.allowEmergencyOverride !== undefined) resolved.allowEmergencyOverride = match.allowEmergencyOverride;
                if (match.overlapPolicy !== undefined) resolved.overlapPolicy = match.overlapPolicy;
            }
        }

        return resolved;
    }

    /**
     * Checks if a user is eligible to create a plan of a specific type starting at startTime.
     * Returns eligibility result matching the API response contract.
     */
    public static async checkEligibility(
        userId: string,
        planType: string,
        startTimeInput: Date | string,
        options?: { transaction?: Transaction }
    ): Promise<{
        eligible: boolean;
        reasonCode?: string;
        message?: string;
        lockedUntil?: Date;
        remainingSeconds?: number;
        existingPlanId?: string;
        existingPlanType?: string;
        details?: any;
        config?: PlanTimeLockConfigAttributes;
    }> {
        // Active plan limits, daily/weekly limits, and time lock restrictions apply ONLY to Party Plans ('party_plan').
        // Group parties, large group parties, strangers meet, solo bookings, and regular table bookings are completely exempt.
        if (planType !== 'party_plan') {
            return { eligible: true };
        }

        const transaction = options?.transaction;

        // 0. Lunara Package Tier & Quota Entitlement check for Party Plans
        const startTimeRef = typeof startTimeInput === 'string' ? new Date(startTimeInput) : startTimeInput;
        const limitCheck = await SubscriptionService.checkPartyPlanLimit(userId, startTimeRef, { transaction });
        if (!limitCheck.allowed) {
            return {
                eligible: false,
                reasonCode: limitCheck.code || 'PARTY_PLAN_LIMIT_REACHED',
                message: limitCheck.message || 'Party plan creation limit reached.',
                details: {
                    tier: limitCheck.tier,
                    limit: limitCheck.limit,
                    used: limitCheck.used,
                    remaining: limitCheck.remaining,
                    resetAt: limitCheck.resetAt,
                    upgradeAvailable: true,
                },
            };
        }

        const config = await this.resolveConfig(userId, planType);

        if (!config.timeLockEnabled) {
            return { eligible: true };
        }

        const startTime = typeof startTimeInput === 'string' ? new Date(startTimeInput) : startTimeInput;
        if (isNaN(startTime.getTime())) {
            return { eligible: false, reasonCode: 'PLAN_INVALID_TIME', message: 'Requested party plan start time is invalid.' };
        }

        const now = new Date();
        if (startTime.getTime() < now.getTime() && !config.allowEmergencyOverride) {
            return { eligible: false, reasonCode: 'PLAN_PAST_TIME', message: 'Party plan start time cannot be in the past.' };
        }

        // Calculate proposed lock window
        const cooldownMs = config.defaultCooldownHours * 60 * 60 * 1000;
        const proposedStart = startTime;
        const proposedEnd = new Date(startTime.getTime() + cooldownMs);

        // 1. Time lock checks for party_plan
        const activeLocks = await PlanTimeLock.findAll({
            where: {
                userId,
                sourcePlanType: 'party_plan',
                status: 'active',
                lockEndAt: { [Op.gt]: now }
            },
            transaction
        });

        // 2. Check overlapping locks from PlanTimeLock table
        const overlappingLock = activeLocks.find(lock => {
            const existingStart = new Date(lock.lockStartAt).getTime();
            const existingEnd = new Date(lock.lockEndAt).getTime();
            const reqStart = proposedStart.getTime();
            const reqEnd = proposedEnd.getTime();

            if (config.overlapPolicy === 'ALLOW_TOUCHING_BOUNDARIES') {
                return (reqStart > existingStart && reqStart < existingEnd) ||
                       (reqEnd > existingStart && reqEnd < existingEnd);
            }
            return reqStart < existingEnd && reqEnd > existingStart;
        });

        if (overlappingLock) {
            const existingStart = new Date(overlappingLock.lockStartAt);
            const lockedUntil = new Date(overlappingLock.lockEndAt);
            const remainingSeconds = Math.max(0, Math.floor((lockedUntil.getTime() - now.getTime()) / 1000));

            const existingTimeStr = formatFriendlyDateTime(existingStart, now);
            const availableTimeStr = formatFriendlyDateTime(lockedUntil, now);

            const friendlyMessage = `You already have a party plan scheduled for ${existingTimeStr}. Party plans must be at least ${config.defaultCooldownHours} hours apart. You can schedule your next party plan at or after ${availableTimeStr}.`;

            return {
                eligible: false,
                reasonCode: 'PLAN_TIME_LOCKED',
                message: friendlyMessage,
                lockedUntil,
                remainingSeconds,
                existingPlanId: overlappingLock.sourcePlanId,
                existingPlanType: overlappingLock.sourcePlanType
            };
        }

        // 2b. Check direct PartyPlan source-of-truth table for 4-hour window collisions
        const directCollisions = await PartyPlan.findAll({
            where: {
                userId,
                status: { [Op.ne]: 'cancelled' },
                planDateTime: {
                    [Op.between]: [
                        new Date(proposedStart.getTime() - cooldownMs + 1000),
                        new Date(proposedStart.getTime() + cooldownMs - 1000)
                    ]
                }
            },
            transaction
        });

        if (directCollisions.length > 0) {
            const conflictPlan = directCollisions[0];
            const existingStart = new Date(conflictPlan.planDateTime);
            const lockedUntil = new Date(existingStart.getTime() + cooldownMs);
            const remainingSeconds = Math.max(0, Math.floor((lockedUntil.getTime() - now.getTime()) / 1000));

            const existingTimeStr = formatFriendlyDateTime(existingStart, now);
            const availableTimeStr = formatFriendlyDateTime(lockedUntil, now);

            const friendlyMessage = `You already have a party plan scheduled for ${existingTimeStr}. Party plans must be at least ${config.defaultCooldownHours} hours apart. You can schedule your next party plan at or after ${availableTimeStr}.`;

            return {
                eligible: false,
                reasonCode: 'PLAN_TIME_LOCKED',
                message: friendlyMessage,
                lockedUntil,
                remainingSeconds,
                existingPlanId: conflictPlan.id,
                existingPlanType: 'party_plan'
            };
        }

        // 3. Active party plan limit checks
        const activePlansCount = await PlanTimeLock.count({
            where: {
                userId,
                sourcePlanType: 'party_plan',
                status: 'active',
                lockEndAt: { [Op.gt]: now }
            },
            transaction
        });

        if (activePlansCount >= config.maxActivePlans) {
            return {
                eligible: false,
                reasonCode: 'PLAN_ACTIVE_LIMIT_REACHED',
                message: `You currently have ${activePlansCount} active party plans. Maximum allowed active party plans is ${config.maxActivePlans}.`
            };
        }

        // 4. Daily/weekly limit checks for party_plan
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

        const dailyCount = await PlanTimeLock.count({
            where: {
                userId,
                sourcePlanType: 'party_plan',
                status: { [Op.ne]: 'cancelled' },
                lockStartAt: { [Op.gte]: startOfToday }
            },
            transaction
        });

        if (dailyCount >= config.maxDailyPlans) {
            return {
                eligible: false,
                reasonCode: 'PLAN_DAILY_LIMIT_REACHED',
                message: `You have reached your daily limit of ${config.maxDailyPlans} party plans for Today. You can schedule more party plans Tomorrow!`
            };
        }

        const weeklyCount = await PlanTimeLock.count({
            where: {
                userId,
                sourcePlanType: 'party_plan',
                createdAt: { [Op.gte]: weekAgo }
            },
            transaction
        });

        if (weeklyCount >= config.maxWeeklyPlans) {
            return {
                eligible: false,
                reasonCode: 'PLAN_WEEKLY_LIMIT_REACHED',
                message: `You have reached the maximum limit of ${config.maxWeeklyPlans} weekly party plans.`
            };
        }

        return { eligible: true, config };
    }

    /**
     * Executes atomic transactional verification using PostgreSQL advisory locks.
     * Prevents race conditions from simultaneous requests.
     */
    public static async runAtomicCheckAndCreate(
        userId: string,
        planType: string,
        startTimeInput: Date | string,
        callback: (transaction: Transaction) => Promise<any>
    ): Promise<any> {
        return await sequelize.transaction(async (t) => {
            // Non-party-plan flows (Group parties, solo bookings, strangers meet) are not subject to party plan locks
            if (planType !== 'party_plan') {
                return await callback(t);
            }

            // Acquire advisory transaction lock for the user ID
            const lockKey = getAdvisoryLockKey(userId);
            await sequelize.query(`SELECT pg_advisory_xact_lock(:lockKey)`, {
                replacements: { lockKey },
                transaction: t
            });

            // Re-validate eligibility under current database state inside transaction
            const eligibility = await this.checkEligibility(userId, planType, startTimeInput, { transaction: t });
            if (!eligibility.eligible) {
                const error: any = new Error(eligibility.message || 'Time lock conflict detected.');
                error.code = eligibility.reasonCode || 'PLAN_TIME_LOCKED';
                error.details = eligibility;
                throw error;
            }

            // Execute original plan creation controller logic
            const result = await callback(t);

            // Use already-resolved config to calculate lock times (avoid duplicate DB query)
            const config = eligibility.config || await this.resolveConfig(userId, planType);
            const startTime = typeof startTimeInput === 'string' ? new Date(startTimeInput) : startTimeInput;
            const cooldownMs = config.defaultCooldownHours * 60 * 60 * 1000;
            const endTime = new Date(startTime.getTime() + cooldownMs);

            // Create plan lock metadata row for party_plan
            await PlanTimeLock.create({
                userId,
                sourcePlanId: result.id || result.planId || result.bookingId,
                sourcePlanType: planType,
                lockStartAt: startTime,
                lockEndAt: endTime,
                status: 'active'
            }, { transaction: t });

            // Queue notification job near expiration (only if notifications are enabled)
            if (config.timeLockEnabled && cooldownMs > 0) {
                const alertTime = new Date(endTime.getTime() - 5 * 60 * 1000);
                if (alertTime.getTime() > Date.now()) {
                    await NotificationJob.create({
                        userId,
                        sendAt: alertTime,
                        title: 'Lock Expiration Approaching ⏳',
                        body: 'Your party plan creation lock is expiring in 5 minutes. You can create a new party plan soon!',
                        status: 'pending'
                    }, { transaction: t });
                }
            }

            return result;
        });
    }

    /**
     * Reschedules an existing plan's lock window.
     */
    public static async rescheduleLock(
        userId: string,
        sourcePlanId: string,
        newStartTimeInput: Date | string,
        options?: { transaction?: Transaction }
    ): Promise<void> {
        const transaction = options?.transaction || await sequelize.transaction();
        try {
            const lock = await PlanTimeLock.findOne({
                where: { sourcePlanId, status: 'active' },
                transaction
            });
            if (!lock) return;

            const newStartTime = typeof newStartTimeInput === 'string' ? new Date(newStartTimeInput) : newStartTimeInput;
            const config = await this.resolveConfig(userId, lock.sourcePlanType);
            const cooldownMs = config.defaultCooldownHours * 60 * 60 * 1000;
            const newEndTime = new Date(newStartTime.getTime() + cooldownMs);

            // Temporarily cancel lock for overlap evaluation
            lock.status = 'cancelled';
            await lock.save({ transaction });

            const eligibility = await this.checkEligibility(userId, lock.sourcePlanType, newStartTime, { transaction });
            if (!eligibility.eligible) {
                // Revert status on failure
                lock.status = 'active';
                await lock.save({ transaction });
                const error: any = new Error(eligibility.message || 'Conflict detected during reschedule.');
                error.code = eligibility.reasonCode || 'PLAN_TIME_LOCKED';
                error.details = eligibility;
                throw error;
            }

            lock.lockStartAt = newStartTime;
            lock.lockEndAt = newEndTime;
            lock.status = 'active';
            await lock.save({ transaction });

            if (!options?.transaction) await transaction.commit();
        } catch (err) {
            if (!options?.transaction) await transaction.rollback();
            throw err;
        }
    }

    /**
     * Releases (cancels) a plan lock record immediately.
     */
    public static async releaseLock(
        sourcePlanId: string,
        options?: { transaction?: Transaction }
    ): Promise<void> {
        const transaction = options?.transaction;
        await PlanTimeLock.update(
            { status: 'cancelled', reason: 'User cancelled plan' },
            { where: { sourcePlanId }, transaction }
        );
    }
}
