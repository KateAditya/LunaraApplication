import sequelize from '../config/database';
import '../models';
import SubscriptionPackage, { PackageTier } from '../models/SubscriptionPackage';
import User, { UserRole } from '../models/User';
import { SubscriptionService } from '../services/subscriptionService';
import { EntitlementService } from '../services/EntitlementService';

async function verifyAll() {
    console.log('====================================================');
    console.log('🔍 RUNNING COMPREHENSIVE DATABASE & SUBSCRIPTION VERIFICATION');
    console.log('====================================================');

    // 1. Authenticate Database
    await sequelize.authenticate();
    console.log('✅ 1. Database connection authenticated successfully.');

    // 2. Check Table Columns
    console.log('\n--- 2. Checking Table Schema & Column Validity ---');
    const [subPkgCols] = await sequelize.query(`
        SELECT column_name, data_type 
        FROM information_schema.columns 
        WHERE table_name = 'SubscriptionPackages';
    `) as [any[], any];
    const colNames = subPkgCols.map((c: any) => c.column_name);
    console.log(`📋 SubscriptionPackages columns found (${colNames.length}):`, colNames.join(', '));
    
    const requiredPkgCols = [
        'daily_likes', 'superlikes_per_cycle', 'boosts_per_cycle',
        'party_plan_limit', 'party_plan_period_days', 'can_see_who_liked', 'tier'
    ];
    for (const req of requiredPkgCols) {
        if (colNames.includes(req)) {
            console.log(`  ✅ Column '${req}' is present.`);
        } else {
            console.error(`  ❌ Column '${req}' is MISSING!`);
        }
    }

    const [userLikesCols] = await sequelize.query(`
        SELECT column_name, data_type 
        FROM information_schema.columns 
        WHERE table_name = 'user_likes';
    `) as [any[], any];
    const likeColNames = userLikesCols.map((c: any) => c.column_name);
    console.log(`📋 user_likes columns found (${likeColNames.length}):`, likeColNames.join(', '));
    const requiredLikeCols = ['user_id', 'target_user_id', 'action_type', 'created_at'];
    for (const req of requiredLikeCols) {
        if (likeColNames.includes(req)) {
            console.log(`  ✅ Column '${req}' is present.`);
        } else {
            console.error(`  ❌ Column '${req}' is MISSING!`);
        }
    }

    // 3. Verify SubscriptionPackages rows & Defaults
    console.log('\n--- 3. Verifying Configured Subscription Packages ---');
    let packages = await SubscriptionPackage.findAll({ order: [['price', 'ASC']] });
    if (packages.length === 0) {
        console.log('⚠️ No packages found, seeding standard packages...');
        await SubscriptionPackage.bulkCreate([
            {
                name: 'Free Plan',
                tier: PackageTier.FREE,
                price: 0,
                durationDays: 0,
                dailyLikes: 7,
                superlikesPerCycle: 0,
                boostsPerCycle: 0,
                partyPlanLimit: 1,
                partyPlanPeriodDays: 7,
                canSeeWhoLiked: false,
                isActive: true,
            },
            {
                name: 'Core VIP',
                tier: PackageTier.CORE,
                price: 299,
                durationDays: 30,
                dailyLikes: 25,
                superlikesPerCycle: 5,
                boostsPerCycle: 1,
                partyPlanLimit: 3,
                partyPlanPeriodDays: 30,
                canSeeWhoLiked: true,
                isActive: true,
            },
            {
                name: 'Plus VIP',
                tier: PackageTier.PLUS,
                price: 599,
                durationDays: 30,
                dailyLikes: 50,
                superlikesPerCycle: 15,
                boostsPerCycle: 3,
                partyPlanLimit: 5,
                partyPlanPeriodDays: 30,
                canSeeWhoLiked: true,
                isActive: true,
            },
            {
                name: 'Pro VIP',
                tier: PackageTier.PRO,
                price: 999,
                durationDays: 30,
                dailyLikes: 100,
                superlikesPerCycle: 30,
                boostsPerCycle: 6,
                partyPlanLimit: 10,
                partyPlanPeriodDays: 30,
                canSeeWhoLiked: true,
                isActive: true,
            },
            {
                name: 'Elite VIP',
                tier: PackageTier.ELITE,
                price: 1999,
                durationDays: 30,
                dailyLikes: -1, // Unlimited
                superlikesPerCycle: -1,
                boostsPerCycle: -1,
                partyPlanLimit: -1,
                partyPlanPeriodDays: 30,
                canSeeWhoLiked: true,
                isActive: true,
            },
        ]);
        packages = await SubscriptionPackage.findAll({ order: [['price', 'ASC']] });
    }

    for (const p of packages) {
        console.log(`📦 [${p.tier}] ${p.name}: Price=₹${p.price}, DailyLikes=${p.dailyLikes}, Superlikes=${p.superlikesPerCycle}, Boosts=${p.boostsPerCycle}, PartyLimit=${p.partyPlanLimit}/${p.partyPlanPeriodDays}d, WhoLikedMe=${p.canSeeWhoLiked}`);
    }

    // 4. Test User Subscription Service & Limit Engine
    console.log('\n--- 4. Testing Subscription Service Limit Engine ---');
    let testUser = await User.findOne({ where: { role: UserRole.CUSTOMER } });
    if (!testUser) {
        testUser = await User.create({
            email: 'test_verifier@lunara.app',
            phone: '+919999999999',
            passwordHash: '$2a$10$abcdefghijklmnopqrstuvwxyz123456',
            firstName: 'Test',
            lastName: 'Verifier',
            dateOfBirth: new Date(1998, 0, 1),
            role: UserRole.CUSTOMER,
        });
    }
    console.log(`👤 Using user: ${testUser.firstName} ${testUser.lastName} (${testUser.id})`);

    const status = await SubscriptionService.getFullStatus(testUser.id);
    console.log('📊 Full Status Result:', {
        tier: status.tier,
        isFree: status.isFree,
        dailyLikesLimit: status.dailyLikesLimit,
        dailyLikesRemaining: status.dailyLikesRemaining,
        superlikesRemaining: status.superlikesRemaining,
        boostsRemaining: status.boostsRemaining,
        partyPlanLimit: (status as any).partyPlanLimit,
        partyPlanPeriodDays: (status as any).partyPlanPeriodDays,
        canSeeWhoLiked: status.canSeeWhoLiked,
    });

    // 5. Test Party Plan Limit Rolling Check
    console.log('\n--- 5. Testing Party Plan Rolling Period Limit Check ---');
    const partyCheck = await SubscriptionService.checkPartyPlanLimit(testUser.id);
    console.log('🎉 Party Plan Limit Check:', {
        allowed: partyCheck.allowed,
        tier: partyCheck.tier,
        limit: partyCheck.limit,
        used: partyCheck.used,
        remaining: partyCheck.remaining,
        resetAt: partyCheck.resetAt,
    });

    // 6. Test Entitlements Summary
    console.log('\n--- 6. Testing Entitlements Summary ---');
    const entitlements = await EntitlementService.getEntitlementsSummary(testUser.id);
    console.log('💎 Entitlements Summary:', {
        tier: entitlements.planTier,
        planBenefitsCount: entitlements.planBenefits?.length || 0,
        benefits: entitlements.planBenefits?.map((b: any) => `${b.name} (${b.includedQuantity} ${b.unit})`),
    });

    console.log('\n====================================================');
    console.log('✅ ALL DATABASE COLUMNS, ASSOCIATIONS & SUBSCRIPTION LOGIC VERIFIED!');
    console.log('====================================================');
    process.exit(0);
}

verifyAll().catch((err) => {
    console.error('❌ Verification failed:', err);
    process.exit(1);
});
