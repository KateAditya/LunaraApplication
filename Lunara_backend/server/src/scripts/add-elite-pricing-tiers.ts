/**
 * Adds the 3 missing Lunara Elite pricing tiers (3 / 6 / 12 months) defined
 * in the subscription spec. `seedDefaultPackages` only ever created the
 * 15-day and 30-day Elite rows and refuses to run again once any package
 * exists, so those longer tiers can never appear without a one-off insert.
 *
 * SAFE: only inserts rows that don't already exist (matched on tier +
 * durationDays). Never touches any existing package.
 *
 * Run with: npx ts-node src/scripts/add-elite-pricing-tiers.ts
 */

import dotenv from 'dotenv';
import sequelize from '../config/database';
import SubscriptionPackage, { PackageTier } from '../models/SubscriptionPackage';

dotenv.config();

const MISSING_ELITE_TIERS = [
    { name: 'Lunara Elite - 3 Months', price: 4999, durationDays: 90, displayOrder: 6 },
    { name: 'Lunara Elite - 6 Months', price: 8249, durationDays: 180, displayOrder: 7 },
    { name: 'Lunara Elite - 12 Months', price: 16549, durationDays: 365, displayOrder: 8 },
];

async function run(): Promise<void> {
    await sequelize.authenticate();

    for (const tierDef of MISSING_ELITE_TIERS) {
        const existing = await SubscriptionPackage.findOne({
            where: { tier: PackageTier.ELITE, durationDays: tierDef.durationDays },
        });

        if (existing) {
            console.log(`Skipping "${tierDef.name}" — a package with tier=ELITE, durationDays=${tierDef.durationDays} already exists.`);
            continue;
        }

        await SubscriptionPackage.create({
            name: tierDef.name,
            tier: PackageTier.ELITE,
            price: tierDef.price,
            durationDays: tierDef.durationDays,
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
            displayOrder: tierDef.displayOrder,
            themeColor: '#FFB703',
        } as any);

        console.log(`Created "${tierDef.name}" (₹${tierDef.price} / ${tierDef.durationDays} days).`);
    }

    console.log('Done.');
    await sequelize.close();
    process.exit(0);
}

run().catch((error) => {
    console.error('Failed to add Elite pricing tiers:', error);
    process.exit(1);
});
