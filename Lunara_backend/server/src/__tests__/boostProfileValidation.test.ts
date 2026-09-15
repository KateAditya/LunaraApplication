import '../models';
import sequelize from '../config/database';
import User, { UserRole } from '../models/User';
import ProfileBoost, { ProfileBoostStatus } from '../models/ProfileBoost';
import SubscriptionAddonPackage from '../models/SubscriptionAddonPackage';
import UserAddon, { UserAddonStatus } from '../models/UserAddon';
import { SubscriptionService } from '../services/subscriptionService';
import { EntitlementService } from '../services/EntitlementService';
import { RankingService, ScoreExplanation } from '../services/rankingService';
import { Op } from 'sequelize';

describe('Profile Boost Comprehensive Feature Test Suite', () => {
    let testUser: User;
    let otherUser: User;

    beforeAll(async () => {
        await sequelize.authenticate();
        await EntitlementService.seedDefaultAddons();

        // Create or find primary test user
        const [u1] = await User.findOrCreate({
            where: { email: 'boost_test_primary@lunara.app' },
            defaults: {
                email: 'boost_test_primary@lunara.app',
                phone: '9888877771',
                passwordHash: '$2a$10$abcdefghijklmnopqrstuvwxyz123456',
                firstName: 'Boost',
                lastName: 'Tester',
                dateOfBirth: new Date(1996, 3, 20),
                role: UserRole.CUSTOMER,
                reliabilityScore: 85,
            },
        });
        testUser = u1;

        // Create or find secondary test user for ranking comparison
        const [u2] = await User.findOrCreate({
            where: { email: 'boost_test_secondary@lunara.app' },
            defaults: {
                email: 'boost_test_secondary@lunara.app',
                phone: '9888877772',
                passwordHash: '$2a$10$abcdefghijklmnopqrstuvwxyz123456',
                firstName: 'Standard',
                lastName: 'User',
                dateOfBirth: new Date(1997, 7, 10),
                role: UserRole.CUSTOMER,
                reliabilityScore: 85,
            },
        });
        otherUser = u2;

        // Clean up previous test boosts / addons for testUser
        await ProfileBoost.destroy({ where: { userId: { [Op.in]: [testUser.id, otherUser.id] } } });
        await UserAddon.destroy({ where: { userId: { [Op.in]: [testUser.id, otherUser.id] } } });
    });

    afterAll(async () => {
        await ProfileBoost.destroy({ where: { userId: { [Op.in]: [testUser.id, otherUser.id] } } });
        await UserAddon.destroy({ where: { userId: { [Op.in]: [testUser.id, otherUser.id] } } });
    });

    describe('1. Free User Quota Validation', () => {
        it('should deny boost activation when user has 0 boost credits', async () => {
            const consumption = await EntitlementService.consumeFeatureEntitlement(testUser.id, 'profile_boost', 1);
            expect(consumption.success).toBe(false);
            expect(consumption.code).toBe('ADDON_REQUIRED');
        });

        it('should report hasActiveBoost as false in full status', async () => {
            const status = await SubscriptionService.getFullStatus(testUser.id);
            expect(status.hasActiveBoost).toBe(false);
            expect(status.boostRemainingSeconds).toBe(0);
        });
    });

    describe('2. Add-on Purchase & Boost Activation', () => {
        it('should consume boost add-on and create an active 30-minute boost', async () => {
            const addonPkg = await SubscriptionAddonPackage.findOne({
                where: { featureKey: 'profile_boost', isActive: true },
            });
            expect(addonPkg).toBeDefined();

            // Grant 1 boost add-on
            const userAddon = await UserAddon.create({
                userId: testUser.id,
                addonPackageId: addonPkg!.id,
                featureKey: 'profile_boost',
                purchasedQuantity: 1,
                usedQuantity: 0,
                remainingQuantity: 1,
                status: UserAddonStatus.ACTIVE,
            });

            // Consume 1 boost entitlement
            const consumption = await EntitlementService.consumeFeatureEntitlement(testUser.id, 'profile_boost', 1);
            expect(consumption.success).toBe(true);
            expect(consumption.consumed).toBe(1);

            // Create active ProfileBoost
            const now = new Date();
            const expiresAt = new Date(now.getTime() + 30 * 60 * 1000);
            const boost = await ProfileBoost.create({
                userId: testUser.id,
                startedAt: now,
                expiresAt,
                status: ProfileBoostStatus.ACTIVE,
                durationMinutes: 30,
            });

            expect(boost).toBeDefined();
            expect(boost.status).toBe(ProfileBoostStatus.ACTIVE);
            expect(boost.durationMinutes).toBe(30);

            // Add-on record should now be marked consumed
            await userAddon.reload();
            expect(userAddon.remainingQuantity).toBe(0);
            expect(userAddon.status).toBe(UserAddonStatus.CONSUMED);
        });

        it('should reflect active boost status with live remaining time in SubscriptionService', async () => {
            const status = await SubscriptionService.getFullStatus(testUser.id);
            expect(status.hasActiveBoost).toBe(true);
            expect(status.boostExpiresAt).toBeDefined();
            expect(status.boostRemainingSeconds).toBeGreaterThan(0);
            expect(status.boostRemainingSeconds).toBeLessThanOrEqual(1800);
        });
    });

    describe('3. Ranking Engine Boost Multiplier', () => {
        it('should elevate boosted user to Priority Tier 1 and highest ranking score', async () => {
            const scores = await RankingService.computeRankings([testUser.id, otherUser.id]);
            expect(scores.length).toBe(2);

            const boostedScore = scores.find((s: ScoreExplanation) => s.userId === testUser.id);
            const unboostedScore = scores.find((s: ScoreExplanation) => s.userId === otherUser.id);

            expect(boostedScore).toBeDefined();
            expect(unboostedScore).toBeDefined();

            // Boosted user gets 5,000,000 boost bonus
            expect(boostedScore!.breakdown.activeBoostScore).toBe(5000000);
            expect(boostedScore!.priorityTier).toBe(1);
            expect(unboostedScore!.breakdown.activeBoostScore).toBe(0);

            // Final score of boosted user must be significantly higher than unboosted user
            expect(boostedScore!.finalRankScore).toBeGreaterThan(unboostedScore!.finalRankScore);
        });
    });

    describe('4. Expiration & Status Clean-up', () => {
        it('should expire boost when expiresAt is reached', async () => {
            const activeBoost = await ProfileBoost.findOne({
                where: { userId: testUser.id, status: ProfileBoostStatus.ACTIVE },
            });
            expect(activeBoost).toBeDefined();

            // Simulate expiration
            await activeBoost!.update({
                expiresAt: new Date(Date.now() - 1000),
                status: ProfileBoostStatus.EXPIRED,
            });

            SubscriptionService.invalidateCache(testUser.id);

            const status = await SubscriptionService.getFullStatus(testUser.id);
            expect(status.hasActiveBoost).toBe(false);
            expect(status.boostRemainingSeconds).toBe(0);
        });
    });
});
