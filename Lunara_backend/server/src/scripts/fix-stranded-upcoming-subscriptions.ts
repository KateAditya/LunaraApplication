/**
 * Repairs UserSubscription rows stranded by the FREE-tier-stub stacking bug.
 *
 * Bug: `findOrCreateSubscriptionForCredit` (walletController.ts) and its
 * inline duplicates (mobileSubscriptionController.ts) create a lifetime
 * "FREE" stub UserSubscription (status ACTIVE, endDate ~2099) the first time
 * a user buys an à-la-carte boost/superlike credit before ever subscribing.
 * Every real subscription purchase/renewal made afterward treated that stub
 * as "an active plan to stack behind," so it was created as UPCOMING with a
 * startDate/endDate in ~2099 — a paying user who never actually got their
 * plan. The purchase/renewal/activation code paths are now fixed to exclude
 * FREE-tier subscriptions from that stacking logic; this script repairs
 * subscriptions that were already stranded before that fix.
 *
 * For each affected user, all of their UPCOMING + currently-active-non-FREE
 * subscriptions are re-chained in purchase order (oldest createdAt first),
 * starting from "now": the earliest becomes ACTIVE (startDate = now), and
 * any further stacked purchases queue in sequence after it — exactly what
 * the stacking logic should have produced without the FREE-stub interference.
 *
 * SAFE: only touches UserSubscription rows for users who have both a FREE
 * stub (ACTIVE, endDate far in the future) and at least one UPCOMING row.
 * Never touches the FREE stub itself, never touches unaffected users.
 *
 * Run with: npx ts-node src/scripts/fix-stranded-upcoming-subscriptions.ts
 */

import dotenv from 'dotenv';
import { Op } from 'sequelize';
import sequelize from '../config/database';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import SubscriptionPackage, { PackageTier } from '../models/SubscriptionPackage';

dotenv.config();

async function run(): Promise<void> {
    await sequelize.authenticate();

    // Users with a lifetime FREE stub (the poisoning row)
    const freeStubs = await UserSubscription.findAll({
        where: { status: SubscriptionStatus.ACTIVE, endDate: { [Op.gt]: new Date() } },
        include: [{ model: SubscriptionPackage, as: 'package', where: { tier: PackageTier.FREE }, required: true }],
    });

    if (freeStubs.length === 0) {
        console.log('No FREE-tier stub subscriptions found. Nothing to repair.');
        await sequelize.close();
        return;
    }

    const affectedUserIds = new Set(freeStubs.map((s) => s.userId));
    console.log(`Found ${freeStubs.length} FREE-tier stub subscription(s) across ${affectedUserIds.size} user(s). Checking for stranded UPCOMING subscriptions...`);

    let repairedUsers = 0;
    let repairedRows = 0;

    for (const userId of affectedUserIds) {
        const upcoming = await UserSubscription.findAll({
            where: { userId, status: SubscriptionStatus.UPCOMING },
            include: [{ model: SubscriptionPackage, as: 'package', where: { tier: { [Op.ne]: PackageTier.FREE } }, required: true }],
            order: [['createdAt', 'ASC']],
        });

        if (upcoming.length === 0) continue; // this user's stub never actually blocked a purchase

        // Also include an existing ACTIVE non-FREE subscription for this user
        // (if any) at the front of the chain, so we don't clobber a plan
        // that's already correctly active.
        const alreadyActive = await UserSubscription.findOne({
            where: { userId, status: SubscriptionStatus.ACTIVE, endDate: { [Op.gt]: new Date() } },
            include: [{ model: SubscriptionPackage, as: 'package', where: { tier: { [Op.ne]: PackageTier.FREE } }, required: true }],
        });

        let cursor = new Date();
        const t = await sequelize.transaction();
        try {
            if (alreadyActive) {
                cursor = new Date((alreadyActive as any).endDate);
            } else if (upcoming.length > 0) {
                // Promote the earliest queued purchase to ACTIVE right now.
                const first = upcoming.shift()!;
                const pkg = (first as any).package as SubscriptionPackage;
                const startDate = new Date();
                const endDate = new Date(startDate);
                endDate.setDate(endDate.getDate() + pkg.durationDays);
                await first.update(
                    {
                        status: SubscriptionStatus.ACTIVE,
                        startDate,
                        endDate,
                        superlikesRemaining: pkg.superlikesPerCycle,
                        boostsRemaining: pkg.boostsPerCycle,
                    },
                    { transaction: t }
                );
                cursor = endDate;
                repairedRows++;
                console.log(`  User ${userId}: activated subscription ${first.id} (package ${pkg.name}) — was stranded UPCOMING with a ~2099 startDate.`);
            }

            // Any remaining queued purchases chain in sequence after that.
            for (const sub of upcoming) {
                const pkg = (sub as any).package as SubscriptionPackage;
                const startDate = new Date(cursor);
                const endDate = new Date(startDate);
                endDate.setDate(endDate.getDate() + pkg.durationDays);
                await sub.update({ startDate, endDate }, { transaction: t });
                cursor = endDate;
                repairedRows++;
                console.log(`  User ${userId}: re-queued subscription ${sub.id} (package ${pkg.name}) to start ${startDate.toISOString()}.`);
            }

            await t.commit();
            repairedUsers++;
        } catch (err) {
            await t.rollback();
            console.error(`  Failed to repair user ${userId}:`, err);
        }
    }

    console.log(`\nDone. Repaired ${repairedRows} subscription row(s) across ${repairedUsers} user(s).`);
    await sequelize.close();
}

run().catch((error) => {
    console.error('Failed to repair stranded subscriptions:', error);
    process.exit(1);
});
