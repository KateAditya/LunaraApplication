import '../models';
import sequelize from '../config/database';
import User, { UserRole } from '../models/User';
import SubscriptionAddonPackage from '../models/SubscriptionAddonPackage';
import UserAddon, { UserAddonStatus } from '../models/UserAddon';
import { NightPartnerMatchStatus } from '../models/NightPartnerMatch';
import { SubscriptionService } from '../services/subscriptionService';
import { EntitlementService } from '../services/EntitlementService';

describe('Subscription & Entitlement Engine Test Suite', () => {
    let testUserId: string;

    beforeAll(async () => {
        await sequelize.authenticate();
        let user = await User.findOne({ where: { role: UserRole.CUSTOMER } });
        if (!user) {
            user = await User.create({
                email: 'test_sub_runner@lunara.app',
                phone: '9876543210',
                passwordHash: '$2a$10$abcdefghijklmnopqrstuvwxyz123456',
                firstName: 'Sub',
                lastName: 'Runner',
                dateOfBirth: new Date(1995, 5, 15),
                role: UserRole.CUSTOMER,
            });
        }
        testUserId = user.id;

        // Ensure default add-ons are seeded
        await EntitlementService.seedDefaultAddons();
    });

    describe('1. Database Tables & Column Validations', () => {
        it('should have all valid columns in SubscriptionPackages', async () => {
            const [columns] = await sequelize.query(`
                SELECT column_name FROM information_schema.columns 
                WHERE table_name = 'SubscriptionPackages';
            `) as [any[], any];
            const colNames = columns.map((c: any) => c.column_name);

            expect(colNames).toContain('party_plan_limit');
            expect(colNames).toContain('party_plan_period_days');
            expect(colNames).toContain('daily_likes');
            expect(colNames).toContain('superlikes_per_cycle');
            expect(colNames).toContain('boosts_per_cycle');
            expect(colNames).toContain('can_see_who_liked');
            expect(colNames).toContain('tier');
            expect(colNames).toContain('price');
        });

        it('should have all valid columns in SubscriptionAddonPackages', async () => {
            const [columns] = await sequelize.query(`
                SELECT column_name FROM information_schema.columns 
                WHERE table_name = 'SubscriptionAddonPackages';
            `) as [any[], any];
            const colNames = columns.map((c: any) => c.column_name);

            expect(colNames).toContain('id');
            expect(colNames).toContain('name');
            expect(colNames).toContain('feature_key');
            expect(colNames).toContain('quantity');
            expect(colNames).toContain('price');
            expect(colNames).toContain('currency');
            expect(colNames).toContain('is_active');
            expect(colNames).toContain('display_order');
        });

        it('should have all valid columns in UserAddons', async () => {
            const [columns] = await sequelize.query(`
                SELECT column_name FROM information_schema.columns 
                WHERE table_name = 'UserAddons';
            `) as [any[], any];
            const colNames = columns.map((c: any) => c.column_name);

            expect(colNames).toContain('id');
            expect(colNames).toContain('user_id');
            expect(colNames).toContain('addon_package_id');
            expect(colNames).toContain('feature_key');
            expect(colNames).toContain('purchased_quantity');
            expect(colNames).toContain('used_quantity');
            expect(colNames).toContain('remaining_quantity');
            expect(colNames).toContain('status');
        });

        it('should have all valid columns in user_likes table', async () => {
            const [columns] = await sequelize.query(`
                SELECT column_name FROM information_schema.columns 
                WHERE table_name = 'user_likes';
            `) as [any[], any];
            const colNames = columns.map((c: any) => c.column_name);

            expect(colNames).toContain('user_id');
            expect(colNames).toContain('target_user_id');
            expect(colNames).toContain('action_type');
        });

        it('should have valid uppercase enum values in NightPartnerMatchStatus', () => {
            expect(NightPartnerMatchStatus.MATCHED).toBe('MATCHED');
            expect(NightPartnerMatchStatus.PAYMENT_PENDING).toBe('PAYMENT_PENDING');
            expect(NightPartnerMatchStatus.CONFIRMED).toBe('CONFIRMED');
            expect(NightPartnerMatchStatus.CANCELLED).toBe('CANCELLED');
            expect(NightPartnerMatchStatus.EXPIRED).toBe('EXPIRED');
        });
    });

    describe('2. Add-on Packages & Entitlements Engine', () => {
        it('should seed default add-on packages including Backtracks, Superlikes, Boosts, Party Plans', async () => {
            const addons = await SubscriptionAddonPackage.findAll({ where: { isActive: true } });
            expect(addons.length).toBeGreaterThanOrEqual(5);

            const featureKeys = addons.map(a => a.featureKey);
            expect(featureKeys).toContain('superlike');
            expect(featureKeys).toContain('profile_boost');
            expect(featureKeys).toContain('party_creation');
            expect(featureKeys).toContain('backtrack');

            const backtrackAddon = addons.find(a => a.featureKey === 'backtrack');
            expect(backtrackAddon).toBeDefined();
            expect(backtrackAddon?.quantity).toBe(10);
        });

        it('should return accurate full status with dynamic limits for Free user', async () => {
            const status = await SubscriptionService.getFullStatus(testUserId);
            expect(status).toBeDefined();
            expect(status.dailyLikesLimit).toBeGreaterThanOrEqual(7);
            expect((status as any).partyPlanLimit).toBe(1);
            expect((status as any).partyPlanPeriodDays).toBe(7);
            expect(status.canSeeWhoLiked).toBe(false);
        });

        it('should evaluate rolling window period for party plan creation limit', async () => {
            const check = await SubscriptionService.checkPartyPlanLimit(testUserId);
            expect(check).toBeDefined();
            expect(check.allowed).toBe(true);
            expect(check.limit).toBe(1);
            expect(check.resetAt).toBeInstanceOf(Date);
        });

        it('should compute entitlements summary correctly with dynamic plan items and totals', async () => {
            const summary = await EntitlementService.getEntitlementsSummary(testUserId);
            expect(summary).toBeDefined();
            expect(summary.planBenefits).toBeInstanceOf(Array);
            
            const partyPlanItem = summary.planBenefits.find(b => b.featureKey === 'party_creation');
            expect(partyPlanItem).toBeDefined();
            expect(partyPlanItem?.includedQuantity).toBe(1);
            expect(partyPlanItem?.unit).toBe('per week');

            const dailyLikesItem = summary.planBenefits.find(b => b.featureKey === 'daily_likes');
            expect(dailyLikesItem).toBeDefined();
            expect(dailyLikesItem?.includedQuantity).toBe(7);
            expect(dailyLikesItem?.unit).toBe('per day');

            expect(summary.totals).toBeDefined();
            expect(summary.totals.superlikesAvailable).toBeDefined();
            expect(summary.totals.boostsAvailable).toBeDefined();
            expect(summary.totals.partyPlansAvailable).toBeDefined();
            expect(summary.totals.backtracksAvailable).toBeDefined();
        });

        it('should consume add-on balance FIFO when plan quota is zero', async () => {
            // Find backtrack addon package
            const addonPkg = await SubscriptionAddonPackage.findOne({ where: { featureKey: 'backtrack', isActive: true } });
            expect(addonPkg).toBeDefined();

            // Grant user a test backtrack addon
            const userAddon = await UserAddon.create({
                userId: testUserId,
                addonPackageId: addonPkg!.id,
                featureKey: 'backtrack',
                purchasedQuantity: 10,
                usedQuantity: 0,
                remainingQuantity: 10,
                status: UserAddonStatus.ACTIVE,
            });

            // Consume 1 backtrack
            const result = await EntitlementService.consumeFeatureEntitlement(testUserId, 'backtrack', 1);
            expect(result.success).toBe(true);
            expect(result.source).toBe('ADDON');
            expect(result.consumed).toBe(1);

            // Verify remaining on user addon record
            await userAddon.reload();
            expect(userAddon.usedQuantity).toBe(1);
            expect(userAddon.remainingQuantity).toBe(9);

            // Clean up test addon
            await userAddon.destroy();
        });
    });
});
