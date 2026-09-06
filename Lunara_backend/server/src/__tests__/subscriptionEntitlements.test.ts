import '../models';
import sequelize from '../config/database';
import User, { UserRole } from '../models/User';
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
    });

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

    it('should compute entitlements summary correctly with dynamic plan items', async () => {
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
    });
});
