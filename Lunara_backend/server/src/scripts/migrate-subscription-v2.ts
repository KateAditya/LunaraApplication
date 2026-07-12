/**
 * Subscription Management System — Safe Additive Migration v2
 * 
 * SAFETY RULES:
 * - Uses CREATE TABLE IF NOT EXISTS (never recreates tables)
 * - Uses ADD COLUMN IF NOT EXISTS (never drops columns)  
 * - Uses ON CONFLICT DO NOTHING for seed data (never overwrites existing)
 * - Wrapped in transaction — rolls back on any error
 * - Does NOT touch existing data
 * - Does NOT DROP any table or column
 * - Does NOT TRUNCATE any table
 * 
 * Run with: npx ts-node src/scripts/migrate-subscription-v2.ts
 */

import dotenv from 'dotenv';
import sequelize from '../config/database';

dotenv.config();

async function runMigration(): Promise<void> {
    console.log('╔══════════════════════════════════════════════════════════════╗');
    console.log('║   Lunara Subscription v2 — Safe Additive Migration           ║');
    console.log('╚══════════════════════════════════════════════════════════════╝');
    console.log('');

    const t = await sequelize.transaction();

    try {
        console.log('Step 1: Verify connection...');
        await sequelize.authenticate();
        console.log('✅ Database connected\n');

        // ── Step 2: SubscriptionFeatures table ──────────────────────────────
        console.log('Step 2: Creating SubscriptionFeatures table...');
        await sequelize.query(`
            CREATE TABLE IF NOT EXISTS "SubscriptionFeatures" (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                key VARCHAR(100) UNIQUE NOT NULL,
                name VARCHAR(200) NOT NULL,
                description TEXT,
                category VARCHAR(50) NOT NULL DEFAULT 'general',
                value_type VARCHAR(20) NOT NULL DEFAULT 'boolean',
                display_order INTEGER NOT NULL DEFAULT 0,
                is_active BOOLEAN NOT NULL DEFAULT TRUE,
                icon VARCHAR(100),
                created_at TIMESTAMP NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMP NOT NULL DEFAULT NOW()
            );
        `, { transaction: t });
        console.log('✅ SubscriptionFeatures\n');

        // ── Step 3: SubscriptionPlanFeatures table ───────────────────────────
        console.log('Step 3: Creating SubscriptionPlanFeatures table...');
        await sequelize.query(`
            CREATE TABLE IF NOT EXISTS "SubscriptionPlanFeatures" (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                package_id UUID NOT NULL REFERENCES "SubscriptionPackages"(id) ON DELETE CASCADE,
                feature_id UUID NOT NULL REFERENCES "SubscriptionFeatures"(id) ON DELETE CASCADE,
                value JSONB NOT NULL DEFAULT '{"enabled": false}',
                is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
                created_at TIMESTAMP NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
                UNIQUE (package_id, feature_id)
            );
        `, { transaction: t });
        await sequelize.query(`
            CREATE INDEX IF NOT EXISTS idx_plan_features_package
            ON "SubscriptionPlanFeatures"(package_id);
        `, { transaction: t });
        console.log('✅ SubscriptionPlanFeatures\n');

        // ── Step 4: SubscriptionUsage table ──────────────────────────────────
        console.log('Step 4: Creating SubscriptionUsage table...');
        await sequelize.query(`
            CREATE TABLE IF NOT EXISTS "SubscriptionUsage" (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                feature_key VARCHAR(100) NOT NULL,
                period VARCHAR(20) NOT NULL,
                used INTEGER NOT NULL DEFAULT 0,
                reset_at TIMESTAMP,
                created_at TIMESTAMP NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
                UNIQUE (user_id, feature_key, period)
            );
        `, { transaction: t });
        await sequelize.query(`
            CREATE INDEX IF NOT EXISTS idx_sub_usage_user
            ON "SubscriptionUsage"(user_id);
        `, { transaction: t });
        console.log('✅ SubscriptionUsage\n');

        // ── Step 5: SubscriptionTransactions table ────────────────────────────
        console.log('Step 5: Creating SubscriptionTransactions table...');
        await sequelize.query(`
            CREATE TABLE IF NOT EXISTS "SubscriptionTransactions" (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                package_id UUID REFERENCES "SubscriptionPackages"(id),
                type VARCHAR(30) NOT NULL,
                amount DECIMAL(10,2) NOT NULL DEFAULT 0,
                currency VARCHAR(5) NOT NULL DEFAULT 'INR',
                payment_method VARCHAR(50),
                payment_gateway VARCHAR(50) NOT NULL DEFAULT 'razorpay',
                gateway_order_id VARCHAR(200),
                gateway_payment_id VARCHAR(200),
                status VARCHAR(20) NOT NULL DEFAULT 'pending',
                invoice_number VARCHAR(50) UNIQUE,
                refund_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
                refunded_at TIMESTAMP,
                metadata JSONB,
                created_at TIMESTAMP NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMP NOT NULL DEFAULT NOW()
            );
        `, { transaction: t });
        await sequelize.query(`
            CREATE INDEX IF NOT EXISTS idx_sub_txn_user
            ON "SubscriptionTransactions"(user_id);
            CREATE INDEX IF NOT EXISTS idx_sub_txn_status
            ON "SubscriptionTransactions"(status);
            CREATE INDEX IF NOT EXISTS idx_sub_txn_type
            ON "SubscriptionTransactions"(type);
            CREATE INDEX IF NOT EXISTS idx_sub_txn_created
            ON "SubscriptionTransactions"(created_at);
        `, { transaction: t });
        console.log('✅ SubscriptionTransactions\n');

        // ── Step 6: Additive columns to SubscriptionPackages ─────────────────
        console.log('Step 6: Adding new columns to SubscriptionPackages (additive only)...');
        const addColumns = [
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS display_name VARCHAR(200)`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS badge VARCHAR(50)`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS theme_color VARCHAR(20) DEFAULT '#7F00FF'`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS is_popular BOOLEAN DEFAULT FALSE`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS is_recommended BOOLEAN DEFAULT FALSE`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT FALSE`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS display_order INTEGER DEFAULT 0`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS trial_days INTEGER DEFAULT 0`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS grace_period_days INTEGER DEFAULT 0`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS currency VARCHAR(5) DEFAULT 'INR'`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS discount_percent DECIMAL(5,2) DEFAULT 0`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS description TEXT`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS icon VARCHAR(100)`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS visibility VARCHAR(20) DEFAULT 'public'`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS created_by UUID`,
            `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS updated_by UUID`,
        ];

        for (const sql of addColumns) {
            await sequelize.query(sql, { transaction: t });
        }
        console.log('✅ SubscriptionPackages columns extended\n');

        // ── Step 7: Seed default features ────────────────────────────────────
        console.log('Step 7: Seeding default feature catalog...');
        await sequelize.query(`
            INSERT INTO "SubscriptionFeatures" (key, name, description, category, value_type, display_order, icon) VALUES
                ('daily_likes', 'Daily Likes', 'Number of profiles you can like per day', 'matching', 'integer', 1, 'heart'),
                ('daily_match_requests', 'Daily Match Requests', 'Number of match requests you can send per day', 'matching', 'integer', 2, 'handshake'),
                ('daily_posts', 'Daily Posts', 'Number of posts you can create per day', 'social', 'integer', 3, 'camera'),
                ('super_likes', 'Super Likes (per cycle)', 'Super likes included in each subscription cycle', 'matching', 'integer', 4, 'star'),
                ('boosts', 'Profile Boosts (per cycle)', 'Profile boost credits included per cycle', 'visibility', 'integer', 5, 'rocket'),
                ('hide_profile', 'Hide Profile', 'Ability to hide your profile from others', 'privacy', 'boolean', 6, 'eye-off'),
                ('priority_visibility', 'Priority Visibility', 'Appear at the top of discovery feeds', 'visibility', 'boolean', 7, 'trending-up'),
                ('trust_badge', 'Trust Badge', 'Display a verified trust badge on your profile', 'badge', 'boolean', 8, 'shield'),
                ('elite_badge', 'Elite Badge', 'Exclusive elite member badge', 'badge', 'boolean', 9, 'crown'),
                ('who_liked_me', 'See Who Liked Me', 'View profiles of people who liked you', 'insights', 'boolean', 10, 'eye'),
                ('who_viewed_me', 'See Who Viewed Me', 'View profiles of people who visited your profile', 'insights', 'boolean', 11, 'binoculars'),
                ('ai_features', 'AI-Powered Features', 'Access to AI-driven matching and suggestions', 'ai', 'boolean', 12, 'brain'),
                ('voice_calls', 'Voice Calls', 'Make voice calls with your matches', 'communication', 'boolean', 13, 'phone'),
                ('video_calls', 'Video Calls', 'Make video calls with your matches', 'communication', 'boolean', 14, 'video'),
                ('stranger_meet', 'Stranger Meet Access', 'Access the Stranger Meet feature', 'social', 'boolean', 15, 'users'),
                ('party_creation', 'Party Creation', 'Create group party plans on the live feed', 'events', 'boolean', 16, 'party-popper'),
                ('advanced_search', 'Advanced Search', 'Use advanced filters to find specific profiles', 'discovery', 'boolean', 17, 'search'),
                ('premium_filters', 'Premium Filters', 'Access premium discovery filters', 'discovery', 'boolean', 18, 'filter'),
                ('profile_boost', 'Profile Boost Purchase', 'Ability to purchase additional profile boosts', 'visibility', 'boolean', 19, 'zap'),
                ('storage', 'Photo Storage (GB)', 'Amount of storage for photos and media', 'storage', 'decimal', 20, 'database')
            ON CONFLICT (key) DO NOTHING;
        `, { transaction: t });
        console.log('✅ Default features seeded (skipped existing)\n');

        // ── Step 8: Commit ────────────────────────────────────────────────────
        await t.commit();

        console.log('╔══════════════════════════════════════════════════════════════╗');
        console.log('║   ✅ Migration completed successfully!                        ║');
        console.log('╚══════════════════════════════════════════════════════════════╝');
        console.log('');
        console.log('New tables created:');
        console.log('  ✓ SubscriptionFeatures');
        console.log('  ✓ SubscriptionPlanFeatures');
        console.log('  ✓ SubscriptionUsage');
        console.log('  ✓ SubscriptionTransactions');
        console.log('');
        console.log('Existing tables extended:');
        console.log('  ✓ SubscriptionPackages (16 new columns, additive only)');
        console.log('');
        console.log('Existing data: UNTOUCHED ✅');
        console.log('');

        await sequelize.close();
        process.exit(0);

    } catch (error: any) {
        await t.rollback();
        console.error('');
        console.error('╔══════════════════════════════════════════════════════════════╗');
        console.error('║   ❌ Migration FAILED — rolled back. No data was changed.     ║');
        console.error('╚══════════════════════════════════════════════════════════════╝');
        console.error('Error:', error.message);
        if (error.stack) console.error(error.stack);
        await sequelize.close();
        process.exit(1);
    }
}

runMigration();
