import { Sequelize } from 'sequelize';
import dotenv from 'dotenv';
import { logger } from './logger';

dotenv.config();

const sequelize = new Sequelize({
    dialect: 'postgres',
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432'),
    database: process.env.DB_NAME || 'lunara_db',
    username: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || '',
    pool: {
        min: parseInt(process.env.DB_POOL_MIN || '2'),
        max: parseInt(process.env.DB_POOL_MAX || '25'),
        acquire: 60000,
        idle: 10000,
        evict: 1000,
    },
    dialectOptions: {
        ssl: process.env.DB_SSL === 'true' ? {
            require: true,
            rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED !== 'false',
        } : false,
        keepAlive: true,
    },
    logging: (msg) => logger.debug(msg),
    define: {
        timestamps: true,
        underscored: true,
    },
});

export const connectDatabase = async (maxRetries = 5, retryDelayMs = 2000): Promise<void> => {
    let connected = false;
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            await sequelize.authenticate();
            logger.info('Database connection established successfully');
            connected = true;
            break;
        } catch (err: any) {
            logger.warn(`Database connection attempt ${attempt}/${maxRetries} failed (${err.code || err.message}). Retrying in ${retryDelayMs / 1000}s...`);
            if (attempt === maxRetries) {
                logger.error('All database connection retries exhausted.', err);
                throw err;
            }
            await new Promise((res) => setTimeout(res, retryDelayMs));
        }
    }

    if (connected) {

        // Always ensure new columns are added safely
        try {
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS settlement_status VARCHAR(50) DEFAULT 'none';`);
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS bank_details TEXT;`);
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS settlement_transaction_id VARCHAR(100);`);
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS settlement_amount DECIMAL(10,2);`);
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS settlement_date TIMESTAMP WITH TIME ZONE;`);
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS settlement_method VARCHAR(50);`);

            // v2: Structured bank/UPI details provided at time of request creation
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS bank_name VARCHAR(100);`);
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS account_number VARCHAR(50);`);
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS account_holder_name VARCHAR(100);`);
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS ifsc_code VARCHAR(20);`);
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS upi_id VARCHAR(100);`);
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS upi_number VARCHAR(20);`);
            // Platform per-seat charge (set by admin on approval, auto-calculated from paymentAmount/numberOfPersons)
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS platform_charge_per_seat DECIMAL(10,2) DEFAULT 0;`);

            await sequelize.query(`ALTER TABLE strangers_meet_joiners ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'pending';`);

            await sequelize.query(`ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS food_preference VARCHAR(100);`);
            await sequelize.query(`ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS drink_preference VARCHAR(100);`);
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS food_preference VARCHAR(100);`);
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS drink_preference VARCHAR(100);`);
            await sequelize.query(`ALTER TABLE strangers_meet_joiners ADD COLUMN IF NOT EXISTS food_preference VARCHAR(100);`);
            await sequelize.query(`ALTER TABLE strangers_meet_joiners ADD COLUMN IF NOT EXISTS drink_preference VARCHAR(100);`);

            // ── UserSubscriptions: expiration alert tracking ──────────────────
            await sequelize.query(`ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS expiration_alert_sent BOOLEAN NOT NULL DEFAULT FALSE;`);

            // ── Users table: soft-delete & moderation columns ──────────────
            // These are referenced by the Sequelize User model but may be missing
            // on older production databases. ADD COLUMN IF NOT EXISTS is idempotent.
            await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;`);
            await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;`);
            await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS deletion_reason TEXT;`);
            await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS block_count INTEGER NOT NULL DEFAULT 0;`);
            await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS is_autoblocked BOOLEAN NOT NULL DEFAULT FALSE;`);
            await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS autoblocked_reason TEXT;`);
            await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS cleared_notifications_at TIMESTAMP WITH TIME ZONE;`);
            await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS no_show_count INTEGER NOT NULL DEFAULT 0;`);
            await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS facebook_id VARCHAR(100);`);
            await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id VARCHAR(100);`);
            await sequelize.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS ticket_url VARCHAR(500);`);
            await sequelize.query(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS is_upcoming_night BOOLEAN DEFAULT FALSE;`);
            await sequelize.query(`ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS ticket_url VARCHAR(500);`);
            await sequelize.query(`ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS ticket_url VARCHAR(500);`);
            await sequelize.query(`ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS ticket_code VARCHAR(100);`);
            await sequelize.query(`ALTER TABLE messages ADD COLUMN IF NOT EXISTS client_message_id VARCHAR(255);`);
            await sequelize.query(`ALTER TABLE messages ADD COLUMN IF NOT EXISTS media_url TEXT;`);
            await sequelize.query(`ALTER TABLE messages ADD COLUMN IF NOT EXISTS media_mime_type VARCHAR(50);`);
            await sequelize.query(`ALTER TABLE messages ADD COLUMN IF NOT EXISTS duration INTEGER;`);
            await sequelize.query(`ALTER TABLE messages ADD COLUMN IF NOT EXISTS file_size INTEGER;`);
            await sequelize.query(`ALTER TABLE messages ADD COLUMN IF NOT EXISTS waveform_data TEXT;`);
            await sequelize.query(`ALTER TABLE messages ADD COLUMN IF NOT EXISTS reply_to_message_id UUID;`);
            await sequelize.query(`ALTER TABLE messages ADD COLUMN IF NOT EXISTS invitation_ref UUID;`);
            await sequelize.query(`ALTER TABLE messages ADD COLUMN IF NOT EXISTS invitation_ref_type VARCHAR(20);`);
            await sequelize.query(`ALTER TABLE messages ADD COLUMN IF NOT EXISTS invitation_time VARCHAR(100);`);
            await sequelize.query(`ALTER TABLE messages ADD COLUMN IF NOT EXISTS invitation_status VARCHAR(20) DEFAULT 'pending';`);
            logger.info('users and messages table columns verified/migrated successfully.');




            // Additive Subscription tables
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
            `);

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
            `);

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
            `);

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
            `);

            // Additive columns for SubscriptionPackages
            const addCols = [
                'display_name VARCHAR(200)',
                'badge VARCHAR(50)',
                "theme_color VARCHAR(20) DEFAULT '#7F00FF'",
                'is_popular BOOLEAN DEFAULT FALSE',
                'is_recommended BOOLEAN DEFAULT FALSE',
                'is_archived BOOLEAN DEFAULT FALSE',
                'display_order INTEGER DEFAULT 0',
                'trial_days INTEGER DEFAULT 0',
                'grace_period_days INTEGER DEFAULT 0',
                "currency VARCHAR(5) DEFAULT 'INR'",
                'discount_percent DECIMAL(5,2) DEFAULT 0',
                'description TEXT',
                'icon VARCHAR(100)',
                "visibility VARCHAR(20) DEFAULT 'public'",
                'created_by UUID',
                'updated_by UUID',
                'backtrack_limit INTEGER DEFAULT 3'
            ];

            for (const colDef of addCols) {
                const colName = colDef.split(' ')[0];
                try {
                    await sequelize.query(`ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS ${colDef};`);
                } catch (colErr: any) {
                    logger.debug(`Column ${colName} might already exist: ` + colErr.message);
                }
            }

            // Seed default features if they do not exist
            await sequelize.query(`
                INSERT INTO "SubscriptionFeatures" (key, name, description, category, value_type, display_order, icon, created_at, updated_at) VALUES
                    ('daily_likes', 'Daily Likes', 'Number of profiles you can like per day', 'matching', 'integer', 1, 'heart', NOW(), NOW()),
                    ('daily_match_requests', 'Daily Match Requests', 'Number of match requests you can send per day', 'matching', 'integer', 2, 'handshake', NOW(), NOW()),
                    ('daily_posts', 'Daily Posts', 'Number of posts you can create per day', 'social', 'integer', 3, 'camera', NOW(), NOW()),
                    ('super_likes', 'Super Likes (per cycle)', 'Super likes included in each subscription cycle', 'matching', 'integer', 4, 'star', NOW(), NOW()),
                    ('boosts', 'Profile Boosts (per cycle)', 'Profile boost credits included per cycle', 'visibility', 'integer', 5, 'rocket', NOW(), NOW()),
                    ('hide_profile', 'Hide Profile', 'Ability to hide your profile from others', 'privacy', 'boolean', 6, 'eye-off', NOW(), NOW()),
                    ('priority_visibility', 'Priority Visibility', 'Appear at the top of discovery feeds', 'visibility', 'boolean', 7, 'trending-up', NOW(), NOW()),
                    ('trust_badge', 'Trust Badge', 'Display a verified trust badge on your profile', 'badge', 'boolean', 8, 'shield', NOW(), NOW()),
                    ('elite_badge', 'Elite Badge', 'Exclusive elite member badge', 'badge', 'boolean', 9, 'crown', NOW(), NOW()),
                    ('who_liked_me', 'See Who Liked Me', 'View profiles of people who liked you', 'insights', 'boolean', 10, 'eye', NOW(), NOW()),
                    ('who_viewed_me', 'See Who Viewed Me', 'View profiles of people who visited your profile', 'insights', 'boolean', 11, 'binoculars', NOW(), NOW()),
                    ('ai_features', 'AI-Powered Features', 'Access to AI-driven matching and suggestions', 'ai', 'boolean', 12, 'brain', NOW(), NOW()),
                    ('voice_calls', 'Voice Calls', 'Make voice calls with your matches', 'communication', 'boolean', 13, 'phone', NOW(), NOW()),
                    ('video_calls', 'Video Calls', 'Make video calls with your matches', 'communication', 'boolean', 14, 'video', NOW(), NOW()),
                    ('stranger_meet', 'Stranger Meet Access', 'Access the Stranger Meet feature', 'social', 'boolean', 15, 'users', NOW(), NOW()),
                    ('party_creation', 'Party Creation', 'Create group party plans on the live feed', 'events', 'boolean', 16, 'party-popper', NOW(), NOW()),
                    ('advanced_search', 'Advanced Search', 'Use advanced filters to find specific profiles', 'discovery', 'boolean', 17, 'search', NOW(), NOW()),
                    ('premium_filters', 'Premium Filters', 'Access premium discovery filters', 'discovery', 'boolean', 18, 'filter', NOW(), NOW()),
                    ('profile_boost', 'Profile Boost Purchase', 'Ability to purchase additional profile boosts', 'visibility', 'boolean', 19, 'zap', NOW(), NOW()),
                    ('storage', 'Photo Storage (GB)', 'Amount of storage for photos and media', 'storage', 'decimal', 20, 'database', NOW(), NOW()),
                    ('daily_backtracks', 'Daily Backtracks', 'Number of times you can backtrack per day', 'matching', 'integer', 21, 'rotate-left', NOW(), NOW())
                ON CONFLICT (key) DO NOTHING;
            `);

            // Seed default subscription packages if none exist
            const [pkgCountResult]: any = await sequelize.query(`SELECT count(*) as count FROM "SubscriptionPackages";`);
            const pkgCount = parseInt(pkgCountResult[0]?.count || '0');
            if (pkgCount === 0) {
                logger.info('No subscription packages found. Seeding default subscription packages...');
                await sequelize.query(`
                    INSERT INTO "SubscriptionPackages" (
                        id, name, tier, price, duration_days, 
                        daily_match_requests, daily_likes, daily_posts, 
                        superlikes_per_cycle, boosts_per_cycle, backtrack_limit,
                        has_hide_profile, has_priority_visibility, has_trust_badge, 
                        has_elite_badge, can_see_who_liked, is_active, 
                        display_order, theme_color, created_at, updated_at
                    ) VALUES 
                        (gen_random_uuid(), 'Free Service (Basic Access)', 'FREE', 0.00, 3650, 3, 7, 5, 0, 0, 3, false, false, false, false, false, true, 0, '#6c757d', NOW(), NOW()),
                        (gen_random_uuid(), 'Lunara Core', 'CORE', 199.00, 7, -1, -1, -1, 3, 0, 5, false, false, false, false, true, true, 1, '#00A9FF', NOW(), NOW()),
                        (gen_random_uuid(), 'Lunara Plus', 'PLUS', 299.00, 7, -1, -1, -1, 10, 2, 10, true, false, false, false, true, true, 2, '#7F00FF', NOW(), NOW()),
                        (gen_random_uuid(), 'Lunara Pro', 'PRO', 599.00, 14, -1, -1, -1, 14, 4, 15, true, true, true, false, true, true, 3, '#E100FF', NOW(), NOW()),
                        (gen_random_uuid(), 'Lunara Elite - 15 Days', 'ELITE', 999.00, 15, -1, -1, -1, 9999, 9999, 9999, true, true, true, true, true, true, 4, '#FFB703', NOW(), NOW()),
                        (gen_random_uuid(), 'Lunara Elite - 30 Days', 'ELITE', 1699.00, 30, -1, -1, -1, 9999, 9999, 9999, true, true, true, true, true, true, 5, '#FFB703', NOW(), NOW());
                `);
                logger.info('Default subscription packages seeded successfully.');
            }

            // ── Additive party_safety_checks table migration ──────────────────
            await sequelize.query(`
                CREATE TABLE IF NOT EXISTS party_safety_checks (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    plan_id UUID NOT NULL,
                    plan_type VARCHAR(50) NOT NULL DEFAULT 'party_plan',
                    user_id UUID NOT NULL,
                    partner_user_id UUID,
                    venue_name VARCHAR(255) NOT NULL DEFAULT 'Venue',
                    party_date TIMESTAMP WITH TIME ZONE NOT NULL,
                    party_time VARCHAR(50),
                    safety_status VARCHAR(50) NOT NULL DEFAULT 'NO_RESPONSE',
                    notes TEXT,
                    location_lat FLOAT,
                    location_lng FLOAT,
                    alert_triggered BOOLEAN NOT NULL DEFAULT FALSE,
                    notification_sent_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                    responded_at TIMESTAMP WITH TIME ZONE,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
                );
            `);
            logger.info('party_safety_checks table verified/migrated successfully.');
        } catch (alterError: any) {
            logger.warn('Dynamic table migration warning: ' + alterError.message);
        }

        // ── Seed Default Admin User if None Exists ──
        try {
            const [existingAdmins]: any = await sequelize.query(
                `SELECT id FROM users WHERE role = 'admin' OR email = 'admin@lunara.com' LIMIT 1;`
            );
            if (!existingAdmins || existingAdmins.length === 0) {
                logger.info('No admin user found. Seeding default admin user...');
                const bcrypt = require('bcryptjs');
                const adminEmail = (process.env.ADMIN_EMAIL || 'admin@lunara.com').toLowerCase().trim();
                const adminPassword = process.env.ADMIN_PASSWORD || 'JaiGanesh@2026';
                const hashedPw = await bcrypt.hash(adminPassword, 10);
                const adminId = require('crypto').randomUUID();

                await sequelize.query(`
                    INSERT INTO users (
                        id, email, phone, password_hash, first_name, last_name, 
                        date_of_birth, role, is_verified, is_active, mfa_enabled, 
                        is_online, no_show_count, block_count, is_autoblocked, 
                        created_at, updated_at
                    ) VALUES (
                        :id, :email, :phone, :password_hash, :first_name, :last_name, 
                        :date_of_birth, :role, :is_verified, :is_active, :mfa_enabled, 
                        :is_online, :no_show_count, :block_count, :is_autoblocked, 
                        NOW(), NOW()
                    )
                `, {
                    replacements: {
                        id: adminId,
                        email: adminEmail,
                        phone: process.env.ADMIN_PHONE || '9999999999',
                        password_hash: hashedPw,
                        first_name: 'Super',
                        last_name: 'Admin',
                        date_of_birth: '1990-01-01',
                        role: 'admin',
                        is_verified: true,
                        is_active: true,
                        mfa_enabled: false,
                        is_online: false,
                        no_show_count: 0,
                        block_count: 0,
                        is_autoblocked: false
                    }
                });

                // Create default profile for the admin user
                const profileId = require('crypto').randomUUID();
                await sequelize.query(`
                    INSERT INTO user_profiles (id, user_id, display_name, created_at, updated_at)
                    VALUES (:id, :user_id, 'Super Admin', NOW(), NOW())
                `, {
                    replacements: { id: profileId, user_id: adminId }
                });

                // Create default preference for the admin user
                const preferenceId = require('crypto').randomUUID();
                await sequelize.query(`
                    INSERT INTO user_preferences (id, user_id, created_at, updated_at)
                    VALUES (:id, :user_id, NOW(), NOW())
                `, {
                    replacements: { id: preferenceId, user_id: adminId }
                });

                logger.info(`Default admin user seeded successfully: ${adminEmail}`);
            }
        } catch (seedError: any) {
            logger.warn('Failed to seed default admin user: ' + seedError.message);
        }

        // ── Create Plan Time Lock & Cooldown Engine Tables ──
        try {
            await sequelize.query(`
                CREATE TABLE IF NOT EXISTS plan_time_lock_configs (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    scope VARCHAR(100) UNIQUE NOT NULL,
                    time_lock_enabled BOOLEAN NOT NULL DEFAULT TRUE,
                    default_cooldown_hours INTEGER NOT NULL DEFAULT 4,
                    max_active_plans INTEGER NOT NULL DEFAULT 1,
                    max_daily_plans INTEGER NOT NULL DEFAULT 3,
                    max_weekly_plans INTEGER NOT NULL DEFAULT 10,
                    allow_overlapping_plans BOOLEAN NOT NULL DEFAULT FALSE,
                    allow_same_venue BOOLEAN NOT NULL DEFAULT FALSE,
                    allow_different_venue BOOLEAN NOT NULL DEFAULT FALSE,
                    allow_future_plans BOOLEAN NOT NULL DEFAULT TRUE,
                    allow_emergency_override BOOLEAN NOT NULL DEFAULT FALSE,
                    overlap_policy VARCHAR(100) NOT NULL DEFAULT 'NO_OVERLAP',
                    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
                );
            `);

            await sequelize.query(`
                CREATE TABLE IF NOT EXISTS plan_time_locks (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    source_plan_id UUID NOT NULL,
                    source_plan_type VARCHAR(100) NOT NULL,
                    lock_start_at TIMESTAMP WITH TIME ZONE NOT NULL,
                    lock_end_at TIMESTAMP WITH TIME ZONE NOT NULL,
                    status VARCHAR(50) NOT NULL DEFAULT 'active',
                    reason TEXT,
                    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
                );
            `);

            await sequelize.query(`
                CREATE TABLE IF NOT EXISTS plan_time_lock_config_histories (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    config_id UUID NOT NULL REFERENCES plan_time_lock_configs(id) ON DELETE CASCADE,
                    admin_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    scope VARCHAR(100) NOT NULL,
                    previous_value JSONB NOT NULL,
                    new_value JSONB NOT NULL,
                    change_reason TEXT,
                    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
                );
            `);

            await sequelize.query(`
                CREATE TABLE IF NOT EXISTS notification_jobs (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    send_at TIMESTAMP WITH TIME ZONE NOT NULL,
                    title VARCHAR(255) NOT NULL,
                    body TEXT NOT NULL,
                    status VARCHAR(50) NOT NULL DEFAULT 'pending',
                    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
                );
            `);

            logger.info('Time Lock tables verified/migrated successfully.');

            // Seed default configs if not existing
            const defaultConfigs = [
                { scope: 'global', time_lock_enabled: true, default_cooldown_hours: 4, max_active_plans: 3, max_daily_plans: 3, max_weekly_plans: 10, allow_overlapping_plans: false, overlap_policy: 'NO_OVERLAP' },
                { scope: 'subscription:FREE', time_lock_enabled: true, default_cooldown_hours: 6, max_active_plans: 2, max_daily_plans: 2, max_weekly_plans: 5, allow_overlapping_plans: false, overlap_policy: 'NO_OVERLAP' },
                { scope: 'subscription:CORE', time_lock_enabled: true, default_cooldown_hours: 4, max_active_plans: 3, max_daily_plans: 3, max_weekly_plans: 10, allow_overlapping_plans: false, overlap_policy: 'NO_OVERLAP' },
                { scope: 'subscription:PLUS', time_lock_enabled: true, default_cooldown_hours: 4, max_active_plans: 3, max_daily_plans: 3, max_weekly_plans: 10, allow_overlapping_plans: false, overlap_policy: 'NO_OVERLAP' },
                { scope: 'subscription:PRO', time_lock_enabled: true, default_cooldown_hours: 2, max_active_plans: 5, max_daily_plans: 5, max_weekly_plans: 15, allow_overlapping_plans: true, overlap_policy: 'ALLOW_TOUCHING_BOUNDARIES' },
                { scope: 'subscription:ELITE', time_lock_enabled: false, default_cooldown_hours: 0, max_active_plans: 999, max_daily_plans: 999, max_weekly_plans: 999, allow_overlapping_plans: true, overlap_policy: 'ALLOW_OVERLAP_FOR_PREMIUM_USERS' },
                { scope: 'role:admin', time_lock_enabled: false, default_cooldown_hours: 0, max_active_plans: 999, max_daily_plans: 999, max_weekly_plans: 999, allow_overlapping_plans: true, overlap_policy: 'ALLOW_OVERLAP_FOR_PREMIUM_USERS' },
                { scope: 'role:venue_owner', time_lock_enabled: false, default_cooldown_hours: 0, max_active_plans: 999, max_daily_plans: 999, max_weekly_plans: 999, allow_overlapping_plans: true, overlap_policy: 'ALLOW_OVERLAP_FOR_PREMIUM_USERS' },
                { scope: 'role:customer', time_lock_enabled: true, default_cooldown_hours: 4, max_active_plans: 3, max_daily_plans: 3, max_weekly_plans: 10, allow_overlapping_plans: false, overlap_policy: 'NO_OVERLAP' }
            ];

            for (const cfg of defaultConfigs) {
                await sequelize.query(`
                    INSERT INTO plan_time_lock_configs 
                        (id, scope, time_lock_enabled, default_cooldown_hours, max_active_plans, max_daily_plans, max_weekly_plans, allow_overlapping_plans, overlap_policy, created_at, updated_at)
                    VALUES 
                        (gen_random_uuid(), :scope, :time_lock_enabled, :default_cooldown_hours, :max_active_plans, :max_daily_plans, :max_weekly_plans, :allow_overlapping_plans, :overlap_policy, NOW(), NOW())
                    ON CONFLICT (scope) DO UPDATE SET 
                        max_active_plans = EXCLUDED.max_active_plans,
                        max_daily_plans = EXCLUDED.max_daily_plans;
                `, { replacements: cfg });
            }
            // Update existing tables to ensure max_active_plans is at least max_daily_plans
            await sequelize.query(`
                UPDATE plan_time_lock_configs 
                SET max_active_plans = max_daily_plans 
                WHERE max_active_plans < max_daily_plans;
            `);
            logger.info('Default Time Lock configurations seeded.');
        } catch (dbErr: any) {
            logger.warn('Failed to verify/seed Time Lock schema: ' + dbErr.message);
        }

        if (process.env.NODE_ENV === 'development') {
            // Sync models in development (be careful in production)
            try {
                await sequelize.sync();
                logger.info('Database models synchronized');
            } catch (syncErr: any) {
                logger.warn('Sequelize sync warning: ' + syncErr.message);
            }
        }
    }
};

export default sequelize;
