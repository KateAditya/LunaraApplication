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
        min: parseInt(process.env.DB_POOL_MIN || '4'),
        max: parseInt(process.env.DB_POOL_MAX || '25'),
        acquire: 30000,
        idle: 10000,
        evict: 5000,
    },
    dialectOptions: {
        ssl: process.env.DB_SSL === 'true' ? {
            require: true,
            rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED !== 'false',
        } : false,
        keepAlive: true,
        keepAliveInitialDelayMillis: 10000,
        statement_timeout: 60000,
    },
    retry: {
        match: [
            /ECONNRESET/,
            /ETIMEDOUT/,
            /EHOSTUNREACH/,
            /ECONNREFUSED/,
            /SequelizeConnectionError/,
            /SequelizeConnectionRefusedError/,
            /SequelizeHostNotFoundError/,
            /SequelizeHostNotReachableError/,
            /SequelizeInvalidConnectionError/,
            /SequelizeConnectionTimedOutError/,
            /Connection lost/,
            /Connection terminated/,
            /Connection refused/,
            /read ECONNRESET/,
        ],
        max: 3,
        backoffBase: 1000,
        backoffExponent: 1.5,
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
        // Run all additive table & column migrations + schema upgrades in a single round-trip
        try {
            await sequelize.query(`
                DO $$ BEGIN
                    -- strangers_meet_requests columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='settlement_status') THEN ALTER TABLE strangers_meet_requests ADD COLUMN settlement_status VARCHAR(50) DEFAULT 'none'; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='bank_details') THEN ALTER TABLE strangers_meet_requests ADD COLUMN bank_details TEXT; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='settlement_transaction_id') THEN ALTER TABLE strangers_meet_requests ADD COLUMN settlement_transaction_id VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='settlement_amount') THEN ALTER TABLE strangers_meet_requests ADD COLUMN settlement_amount DECIMAL(10,2); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='settlement_date') THEN ALTER TABLE strangers_meet_requests ADD COLUMN settlement_date TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='settlement_method') THEN ALTER TABLE strangers_meet_requests ADD COLUMN settlement_method VARCHAR(50); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='bank_name') THEN ALTER TABLE strangers_meet_requests ADD COLUMN bank_name VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='account_number') THEN ALTER TABLE strangers_meet_requests ADD COLUMN account_number VARCHAR(50); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='account_holder_name') THEN ALTER TABLE strangers_meet_requests ADD COLUMN account_holder_name VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='ifsc_code') THEN ALTER TABLE strangers_meet_requests ADD COLUMN ifsc_code VARCHAR(20); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='upi_id') THEN ALTER TABLE strangers_meet_requests ADD COLUMN upi_id VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='upi_number') THEN ALTER TABLE strangers_meet_requests ADD COLUMN upi_number VARCHAR(20); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='platform_charge_per_seat') THEN ALTER TABLE strangers_meet_requests ADD COLUMN platform_charge_per_seat DECIMAL(10,2) DEFAULT 0; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='food_preference') THEN ALTER TABLE strangers_meet_requests ADD COLUMN food_preference VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='drink_preference') THEN ALTER TABLE strangers_meet_requests ADD COLUMN drink_preference VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='ticket_url') THEN ALTER TABLE strangers_meet_requests ADD COLUMN ticket_url VARCHAR(500); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='reminder_2h_sent') THEN ALTER TABLE strangers_meet_requests ADD COLUMN reminder_2h_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='reminder_1h_sent') THEN ALTER TABLE strangers_meet_requests ADD COLUMN reminder_1h_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='reminder_30m_sent') THEN ALTER TABLE strangers_meet_requests ADD COLUMN reminder_30m_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='started_at') THEN ALTER TABLE strangers_meet_requests ADD COLUMN started_at TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='started_by') THEN ALTER TABLE strangers_meet_requests ADD COLUMN started_by UUID; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='duration_hours') THEN ALTER TABLE strangers_meet_requests ADD COLUMN duration_hours DECIMAL(4,2) DEFAULT 3.0; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='expected_end_at') THEN ALTER TABLE strangers_meet_requests ADD COLUMN expected_end_at TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='ended_at') THEN ALTER TABLE strangers_meet_requests ADD COLUMN ended_at TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='ended_confirmed_by') THEN ALTER TABLE strangers_meet_requests ADD COLUMN ended_confirmed_by UUID; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='ended_confirmed_at') THEN ALTER TABLE strangers_meet_requests ADD COLUMN ended_confirmed_at TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='admin_confirmed_ended_at') THEN ALTER TABLE strangers_meet_requests ADD COLUMN admin_confirmed_ended_at TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='admin_confirmed_by') THEN ALTER TABLE strangers_meet_requests ADD COLUMN admin_confirmed_by UUID; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_requests' AND column_name='settlement_overdue') THEN ALTER TABLE strangers_meet_requests ADD COLUMN settlement_overdue BOOLEAN DEFAULT FALSE; END IF;

                    -- Strangers Meet Enums
                    BEGIN ALTER TYPE "enum_strangers_meet_requests_status" ADD VALUE IF NOT EXISTS 'in_progress'; EXCEPTION WHEN others THEN NULL; END;
                    BEGIN ALTER TYPE "enum_strangers_meet_requests_status" ADD VALUE IF NOT EXISTS 'host_confirmed_ended'; EXCEPTION WHEN others THEN NULL; END;
                    BEGIN ALTER TYPE "enum_strangers_meet_requests_status" ADD VALUE IF NOT EXISTS 'admin_confirmed_ended'; EXCEPTION WHEN others THEN NULL; END;
                    BEGIN ALTER TYPE "enum_strangers_meet_requests_status" ADD VALUE IF NOT EXISTS 'completed'; EXCEPTION WHEN others THEN NULL; END;
                    BEGIN ALTER TYPE "enum_strangers_meet_requests_settlement_status" ADD VALUE IF NOT EXISTS 'settlement_pending'; EXCEPTION WHEN others THEN NULL; END;
                    BEGIN ALTER TYPE "enum_strangers_meet_requests_settlement_status" ADD VALUE IF NOT EXISTS 'settled'; EXCEPTION WHEN others THEN NULL; END;

                    -- strangers_meet_joiners columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_joiners' AND column_name='status') THEN ALTER TABLE strangers_meet_joiners ADD COLUMN status VARCHAR(50) DEFAULT 'pending'; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_joiners' AND column_name='food_preference') THEN ALTER TABLE strangers_meet_joiners ADD COLUMN food_preference VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='strangers_meet_joiners' AND column_name='drink_preference') THEN ALTER TABLE strangers_meet_joiners ADD COLUMN drink_preference VARCHAR(100); END IF;

                    -- group_parties columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='group_parties' AND column_name='food_preference') THEN ALTER TABLE group_parties ADD COLUMN food_preference VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='group_parties' AND column_name='drink_preference') THEN ALTER TABLE group_parties ADD COLUMN drink_preference VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='group_parties' AND column_name='ticket_url') THEN ALTER TABLE group_parties ADD COLUMN ticket_url VARCHAR(500); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='group_parties' AND column_name='ticket_code') THEN ALTER TABLE group_parties ADD COLUMN ticket_code VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='group_parties' AND column_name='start_time') THEN ALTER TABLE group_parties ADD COLUMN start_time VARCHAR(5); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='group_parties' AND column_name='expires_at') THEN ALTER TABLE group_parties ADD COLUMN expires_at TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='group_parties' AND column_name='optional_mobile_number') THEN ALTER TABLE group_parties ADD COLUMN optional_mobile_number VARCHAR(255); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='group_parties' AND column_name='reminder_2h_sent') THEN ALTER TABLE group_parties ADD COLUMN reminder_2h_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='group_parties' AND column_name='reminder_1h_sent') THEN ALTER TABLE group_parties ADD COLUMN reminder_1h_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='group_parties' AND column_name='reminder_30m_sent') THEN ALTER TABLE group_parties ADD COLUMN reminder_30m_sent BOOLEAN DEFAULT FALSE; END IF;
                    BEGIN ALTER TYPE "enum_group_parties_status" ADD VALUE IF NOT EXISTS 'expired'; EXCEPTION WHEN others THEN NULL; END;

                    -- UserSubscriptions columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='UserSubscriptions' AND column_name='expiration_alert_sent') THEN ALTER TABLE "UserSubscriptions" ADD COLUMN expiration_alert_sent BOOLEAN NOT NULL DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='UserSubscriptions' AND column_name='superlikes_remaining') THEN ALTER TABLE "UserSubscriptions" ADD COLUMN superlikes_remaining INTEGER DEFAULT 0; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='UserSubscriptions' AND column_name='boosts_remaining') THEN ALTER TABLE "UserSubscriptions" ADD COLUMN boosts_remaining INTEGER DEFAULT 0; END IF;

                    -- SubscriptionPackages columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='superlikes_per_cycle') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN superlikes_per_cycle INTEGER DEFAULT 0; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='boosts_per_cycle') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN boosts_per_cycle INTEGER DEFAULT 0; END IF;

                    -- user_likes table
                    CREATE TABLE IF NOT EXISTS user_likes (
                        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                        target_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                        action_type VARCHAR(50) NOT NULL,
                        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                        CONSTRAINT unique_user_target_like UNIQUE (user_id, target_user_id)
                    );

                    -- users columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='mfa_enabled') THEN ALTER TABLE users ADD COLUMN mfa_enabled BOOLEAN NOT NULL DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='mfa_secret') THEN ALTER TABLE users ADD COLUMN mfa_secret VARCHAR(255); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='profile_image_url') THEN ALTER TABLE users ADD COLUMN profile_image_url VARCHAR(500); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='last_login_at') THEN ALTER TABLE users ADD COLUMN last_login_at TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='is_online') THEN ALTER TABLE users ADD COLUMN is_online BOOLEAN NOT NULL DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='last_active_at') THEN ALTER TABLE users ADD COLUMN last_active_at TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='fcm_token') THEN ALTER TABLE users ADD COLUMN fcm_token VARCHAR(500); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='wallet_balance') THEN ALTER TABLE users ADD COLUMN wallet_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='is_deleted') THEN ALTER TABLE users ADD COLUMN is_deleted BOOLEAN NOT NULL DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='deleted_at') THEN ALTER TABLE users ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='deletion_reason') THEN ALTER TABLE users ADD COLUMN deletion_reason TEXT; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='block_count') THEN ALTER TABLE users ADD COLUMN block_count INTEGER NOT NULL DEFAULT 0; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='is_autoblocked') THEN ALTER TABLE users ADD COLUMN is_autoblocked BOOLEAN NOT NULL DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='autoblocked_reason') THEN ALTER TABLE users ADD COLUMN autoblocked_reason TEXT; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='cleared_notifications_at') THEN ALTER TABLE users ADD COLUMN cleared_notifications_at TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='no_show_count') THEN ALTER TABLE users ADD COLUMN no_show_count INTEGER NOT NULL DEFAULT 0; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='facebook_id') THEN ALTER TABLE users ADD COLUMN facebook_id VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='google_id') THEN ALTER TABLE users ADD COLUMN google_id VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='reliability_score') THEN ALTER TABLE users ADD COLUMN reliability_score INTEGER DEFAULT 70; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='reward_points') THEN ALTER TABLE users ADD COLUMN reward_points INTEGER DEFAULT 0; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='login_streak_days') THEN ALTER TABLE users ADD COLUMN login_streak_days INTEGER DEFAULT 0; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='last_login_streak_date') THEN ALTER TABLE users ADD COLUMN last_login_streak_date TIMESTAMP WITH TIME ZONE; END IF;

                    -- bookings columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='party_event_id') THEN ALTER TABLE bookings ADD COLUMN party_event_id UUID; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='going_mode') THEN ALTER TABLE bookings ADD COLUMN going_mode VARCHAR(20) DEFAULT 'SOLO'; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='table_package') THEN ALTER TABLE bookings ADD COLUMN table_package VARCHAR(20); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='payment_mode') THEN ALTER TABLE bookings ADD COLUMN payment_mode VARCHAR(50); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='ticket_code') THEN ALTER TABLE bookings ADD COLUMN ticket_code VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='ticket_url') THEN ALTER TABLE bookings ADD COLUMN ticket_url VARCHAR(500); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='added_to_wallet') THEN ALTER TABLE bookings ADD COLUMN added_to_wallet BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='party_subject') THEN ALTER TABLE bookings ADD COLUMN party_subject VARCHAR(255); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='party_requirement') THEN ALTER TABLE bookings ADD COLUMN party_requirement TEXT; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='party_description') THEN ALTER TABLE bookings ADD COLUMN party_description TEXT; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='is_large_party_request') THEN ALTER TABLE bookings ADD COLUMN is_large_party_request BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='is_upcoming_night') THEN ALTER TABLE bookings ADD COLUMN is_upcoming_night BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='admin_approval_status') THEN ALTER TABLE bookings ADD COLUMN admin_approval_status VARCHAR(50) DEFAULT 'none'; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='mobile_number') THEN ALTER TABLE bookings ADD COLUMN mobile_number VARCHAR(20); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='optional_mobile_number') THEN ALTER TABLE bookings ADD COLUMN optional_mobile_number VARCHAR(20); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='admin_payment_link') THEN ALTER TABLE bookings ADD COLUMN admin_payment_link TEXT; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='admin_payment_amount') THEN ALTER TABLE bookings ADD COLUMN admin_payment_amount DECIMAL(10,2); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='razorpay_order_id') THEN ALTER TABLE bookings ADD COLUMN razorpay_order_id VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='reminder_2h_sent') THEN ALTER TABLE bookings ADD COLUMN reminder_2h_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='reminder_1h_sent') THEN ALTER TABLE bookings ADD COLUMN reminder_1h_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='reminder_30m_sent') THEN ALTER TABLE bookings ADD COLUMN reminder_30m_sent BOOLEAN DEFAULT FALSE; END IF;

                    -- ads columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='ads' AND column_name='event_date') THEN ALTER TABLE ads ADD COLUMN event_date TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='ads' AND column_name='entry_price') THEN ALTER TABLE ads ADD COLUMN entry_price DECIMAL(10,2); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='ads' AND column_name='seat_limit') THEN ALTER TABLE ads ADD COLUMN seat_limit INTEGER; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='ads' AND column_name='is_unlimited') THEN ALTER TABLE ads ADD COLUMN is_unlimited BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='ads' AND column_name='filled_seats') THEN ALTER TABLE ads ADD COLUMN filled_seats INTEGER DEFAULT 0; END IF;

                    -- messages columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='client_message_id') THEN ALTER TABLE messages ADD COLUMN client_message_id VARCHAR(255); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='media_url') THEN ALTER TABLE messages ADD COLUMN media_url TEXT; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='media_mime_type') THEN ALTER TABLE messages ADD COLUMN media_mime_type VARCHAR(50); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='duration') THEN ALTER TABLE messages ADD COLUMN duration INTEGER; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='file_size') THEN ALTER TABLE messages ADD COLUMN file_size INTEGER; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='waveform_data') THEN ALTER TABLE messages ADD COLUMN waveform_data TEXT; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='reply_to_message_id') THEN ALTER TABLE messages ADD COLUMN reply_to_message_id UUID; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='invitation_ref') THEN ALTER TABLE messages ADD COLUMN invitation_ref UUID; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='invitation_ref_type') THEN ALTER TABLE messages ADD COLUMN invitation_ref_type VARCHAR(20); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='invitation_time') THEN ALTER TABLE messages ADD COLUMN invitation_time VARCHAR(100); END IF;

                    -- venues columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='venues' AND column_name='closed_dates') THEN ALTER TABLE venues ADD COLUMN closed_dates TEXT[]; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='venues' AND column_name='days_open') THEN ALTER TABLE venues ADD COLUMN days_open TEXT[]; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='venues' AND column_name='opening_time') THEN ALTER TABLE venues ADD COLUMN opening_time VARCHAR(50); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='venues' AND column_name='closing_time') THEN ALTER TABLE venues ADD COLUMN closing_time VARCHAR(50); END IF;

                    -- party_plans columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='lifecycle_status') THEN ALTER TABLE party_plans ADD COLUMN lifecycle_status VARCHAR(50) DEFAULT 'posted'; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='matched_request_id') THEN ALTER TABLE party_plans ADD COLUMN matched_request_id UUID; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='accepted_at') THEN ALTER TABLE party_plans ADD COLUMN accepted_at TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='payment_deadline_at') THEN ALTER TABLE party_plans ADD COLUMN payment_deadline_at TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='host_razorpay_order_id') THEN ALTER TABLE party_plans ADD COLUMN host_razorpay_order_id VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='host_razorpay_payment_id') THEN ALTER TABLE party_plans ADD COLUMN host_razorpay_payment_id VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='payment_type') THEN ALTER TABLE party_plans ADD COLUMN payment_type VARCHAR(50) DEFAULT 'split'; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='deposit_amount') THEN ALTER TABLE party_plans ADD COLUMN deposit_amount DECIMAL(10,2) DEFAULT 99.00; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='mobile_number') THEN ALTER TABLE party_plans ADD COLUMN mobile_number VARCHAR(50); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='optional_mobile_number') THEN ALTER TABLE party_plans ADD COLUMN optional_mobile_number VARCHAR(50); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='food_preference') THEN ALTER TABLE party_plans ADD COLUMN food_preference VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='drink_preference') THEN ALTER TABLE party_plans ADD COLUMN drink_preference VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='show_profile_photo') THEN ALTER TABLE party_plans ADD COLUMN show_profile_photo BOOLEAN DEFAULT TRUE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='show_host_name') THEN ALTER TABLE party_plans ADD COLUMN show_host_name BOOLEAN DEFAULT TRUE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='show_venue_details') THEN ALTER TABLE party_plans ADD COLUMN show_venue_details BOOLEAN DEFAULT TRUE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='show_date_details') THEN ALTER TABLE party_plans ADD COLUMN show_date_details BOOLEAN DEFAULT TRUE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='reminder_24h_sent') THEN ALTER TABLE party_plans ADD COLUMN reminder_24h_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='reminder_3h_sent') THEN ALTER TABLE party_plans ADD COLUMN reminder_3h_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='reminder_1h_sent') THEN ALTER TABLE party_plans ADD COLUMN reminder_1h_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='reminder_30m_sent') THEN ALTER TABLE party_plans ADD COLUMN reminder_30m_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='reminder_2h_sent') THEN ALTER TABLE party_plans ADD COLUMN reminder_2h_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='reminder_10m_sent') THEN ALTER TABLE party_plans ADD COLUMN reminder_10m_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='host_arrival_confirmed') THEN ALTER TABLE party_plans ADD COLUMN host_arrival_confirmed BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='host_arrival_time') THEN ALTER TABLE party_plans ADD COLUMN host_arrival_time TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plans' AND column_name='host_lat_lang_check_in') THEN ALTER TABLE party_plans ADD COLUMN host_lat_lang_check_in VARCHAR(255); END IF;

                    -- party_plan_requests columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plan_requests' AND column_name='joiner_razorpay_order_id') THEN ALTER TABLE party_plan_requests ADD COLUMN joiner_razorpay_order_id VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plan_requests' AND column_name='joiner_razorpay_payment_id') THEN ALTER TABLE party_plan_requests ADD COLUMN joiner_razorpay_payment_id VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plan_requests' AND column_name='payment_timeout_at') THEN ALTER TABLE party_plan_requests ADD COLUMN payment_timeout_at TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plan_requests' AND column_name='cancelled_at') THEN ALTER TABLE party_plan_requests ADD COLUMN cancelled_at TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plan_requests' AND column_name='cancelled_by') THEN ALTER TABLE party_plan_requests ADD COLUMN cancelled_by UUID; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plan_requests' AND column_name='cancellation_reason') THEN ALTER TABLE party_plan_requests ADD COLUMN cancellation_reason VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plan_requests' AND column_name='previous_status') THEN ALTER TABLE party_plan_requests ADD COLUMN previous_status VARCHAR(50); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plan_requests' AND column_name='lat_lang_check_in') THEN ALTER TABLE party_plan_requests ADD COLUMN lat_lang_check_in VARCHAR(255); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plan_requests' AND column_name='guest_arrival_confirmed') THEN ALTER TABLE party_plan_requests ADD COLUMN guest_arrival_confirmed BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plan_requests' AND column_name='guest_arrival_time') THEN ALTER TABLE party_plan_requests ADD COLUMN guest_arrival_time TIMESTAMP WITH TIME ZONE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='party_plan_requests' AND column_name='joiner_payment_status') THEN ALTER TABLE party_plan_requests ADD COLUMN joiner_payment_status VARCHAR(50) DEFAULT 'unpaid'; END IF;

                    -- SubscriptionPackages columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='display_name') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN display_name VARCHAR(200); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='badge') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN badge VARCHAR(50); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='theme_color') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN theme_color VARCHAR(20) DEFAULT '#7F00FF'; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='is_popular') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN is_popular BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='is_recommended') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN is_recommended BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='is_archived') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN is_archived BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='display_order') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN display_order INTEGER DEFAULT 0; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='trial_days') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN trial_days INTEGER DEFAULT 0; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='grace_period_days') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN grace_period_days INTEGER DEFAULT 0; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='currency') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN currency VARCHAR(5) DEFAULT 'INR'; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='discount_percent') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN discount_percent DECIMAL(5,2) DEFAULT 0; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='description') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN description TEXT; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='icon') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN icon VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='visibility') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN visibility VARCHAR(20) DEFAULT 'public'; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='created_by') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN created_by UUID; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='updated_by') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN updated_by UUID; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='SubscriptionPackages' AND column_name='backtrack_limit') THEN ALTER TABLE "SubscriptionPackages" ADD COLUMN backtrack_limit INTEGER DEFAULT 3; END IF;

                    -- night_partner columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='night_partner_requests' AND column_name='reminder_2h_sent') THEN ALTER TABLE night_partner_requests ADD COLUMN reminder_2h_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='night_partner_requests' AND column_name='reminder_1h_sent') THEN ALTER TABLE night_partner_requests ADD COLUMN reminder_1h_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='night_partner_requests' AND column_name='reminder_30m_sent') THEN ALTER TABLE night_partner_requests ADD COLUMN reminder_30m_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='night_partner_matches' AND column_name='reminder_2h_sent') THEN ALTER TABLE night_partner_matches ADD COLUMN reminder_2h_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='night_partner_matches' AND column_name='reminder_1h_sent') THEN ALTER TABLE night_partner_matches ADD COLUMN reminder_1h_sent BOOLEAN DEFAULT FALSE; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='night_partner_matches' AND column_name='reminder_30m_sent') THEN ALTER TABLE night_partner_matches ADD COLUMN reminder_30m_sent BOOLEAN DEFAULT FALSE; END IF;

                    -- smart_wallets columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='smart_wallets' AND column_name='locked_balance') THEN ALTER TABLE smart_wallets ADD COLUMN locked_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='smart_wallets' AND column_name='pending_balance') THEN ALTER TABLE smart_wallets ADD COLUMN pending_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='smart_wallets' AND column_name='reward_balance') THEN ALTER TABLE smart_wallets ADD COLUMN reward_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='smart_wallets' AND column_name='lifetime_rewards') THEN ALTER TABLE smart_wallets ADD COLUMN lifetime_rewards DECIMAL(10,2) NOT NULL DEFAULT 0.00; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='smart_wallets' AND column_name='lifetime_refunds') THEN ALTER TABLE smart_wallets ADD COLUMN lifetime_refunds DECIMAL(10,2) NOT NULL DEFAULT 0.00; END IF;

                    -- wallet_transactions columns
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='wallet_transactions' AND column_name='wallet_id') THEN ALTER TABLE wallet_transactions ADD COLUMN wallet_id UUID; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='wallet_transactions' AND column_name='source') THEN ALTER TABLE wallet_transactions ADD COLUMN source VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='wallet_transactions' AND column_name='destination') THEN ALTER TABLE wallet_transactions ADD COLUMN destination VARCHAR(100); END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='wallet_transactions' AND column_name='created_by') THEN ALTER TABLE wallet_transactions ADD COLUMN created_by VARCHAR(100); END IF;

                    -- party_plan_cancellation_requests table
                    CREATE TABLE IF NOT EXISTS party_plan_cancellation_requests (
                        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                        plan_id UUID NOT NULL,
                        booking_id UUID,
                        requested_by_id UUID NOT NULL,
                        recipient_user_id UUID NOT NULL,
                        status VARCHAR(50) NOT NULL DEFAULT 'pending',
                        reason VARCHAR(100) NOT NULL DEFAULT 'my_plans_changed',
                        other_reason_text VARCHAR(150),
                        requested_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                        expires_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (NOW() + INTERVAL '2 hours'),
                        responded_at TIMESTAMP WITH TIME ZONE,
                        responded_by_id UUID,
                        auto_approval_eligible BOOLEAN DEFAULT FALSE,
                        host_deposit_amount DECIMAL(10,2) DEFAULT 99.00,
                        joiner_deposit_amount DECIMAL(10,2) DEFAULT 99.00,
                        host_wallet_transaction_id VARCHAR(255),
                        joiner_wallet_transaction_id VARCHAR(255),
                        reliability_impact INTEGER DEFAULT -5,
                        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
                    );
                END $$;
            `);

            // Create performance indexes to speed up all queries (Users, Plans, Requests, Bookings, Messages, etc.)
            await sequelize.query(`
                CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
                CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);
                CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
                CREATE INDEX IF NOT EXISTS idx_party_plans_user_id ON party_plans(user_id);
                CREATE INDEX IF NOT EXISTS idx_party_plans_status ON party_plans(status);
                CREATE INDEX IF NOT EXISTS idx_party_plans_plan_date_time ON party_plans(plan_date_time);
                CREATE INDEX IF NOT EXISTS idx_party_plan_requests_plan_id ON party_plan_requests(plan_id);
                CREATE INDEX IF NOT EXISTS idx_party_plan_requests_requester_id ON party_plan_requests(requester_id);
                CREATE INDEX IF NOT EXISTS idx_party_plan_requests_status ON party_plan_requests(status);
                CREATE INDEX IF NOT EXISTS idx_bookings_user_id ON bookings(user_id);
                CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings(status);
                CREATE INDEX IF NOT EXISTS idx_bookings_booking_date ON bookings(booking_date);
                CREATE INDEX IF NOT EXISTS idx_group_parties_user_id ON group_parties(user_id);
                CREATE INDEX IF NOT EXISTS idx_group_parties_status ON group_parties(status);
                CREATE INDEX IF NOT EXISTS idx_sm_requests_user_id ON strangers_meet_requests(user_id);
                CREATE INDEX IF NOT EXISTS idx_sm_requests_status ON strangers_meet_requests(status);
                CREATE INDEX IF NOT EXISTS idx_sm_joiners_user_id ON strangers_meet_joiners(user_id);
                CREATE INDEX IF NOT EXISTS idx_sm_joiners_req_id ON strangers_meet_joiners(strangers_meet_request_id);
                CREATE INDEX IF NOT EXISTS idx_user_matches_u1 ON user_matches(user1_id);
                CREATE INDEX IF NOT EXISTS idx_user_matches_u2 ON user_matches(user2_id);
                CREATE INDEX IF NOT EXISTS idx_messages_conv_id ON messages(conversation_id);
                CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON messages(sender_id);
                CREATE INDEX IF NOT EXISTS idx_venues_is_active ON venues(is_active);
                CREATE INDEX IF NOT EXISTS idx_ads_is_active ON ads(is_active);
                CREATE INDEX IF NOT EXISTS idx_notifs_recipient ON notifications(recipient_user_id, is_read);
                CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_type ON wallet_transactions(user_id, transaction_type);
                CREATE INDEX IF NOT EXISTS idx_wallet_tx_status ON wallet_transactions(status);
                CREATE INDEX IF NOT EXISTS idx_smart_wallets_user_id ON smart_wallets(user_id);
                CREATE INDEX IF NOT EXISTS idx_venue_images_venue_id ON venue_images(venue_id, image_type);
                CREATE INDEX IF NOT EXISTS idx_user_photos_user_id ON user_photos(user_id);
                CREATE INDEX IF NOT EXISTS idx_user_profiles_user_id ON user_profiles(user_id);
                CREATE INDEX IF NOT EXISTS idx_payments_user_status ON payments(user_id, status);
                CREATE INDEX IF NOT EXISTS idx_conv_part1_part2 ON conversations(participant_one, participant_two);
                CREATE INDEX IF NOT EXISTS idx_pp_canc_req_plan ON party_plan_cancellation_requests(plan_id);
                CREATE INDEX IF NOT EXISTS idx_pp_canc_req_status ON party_plan_cancellation_requests(status);
                CREATE INDEX IF NOT EXISTS idx_pp_canc_req_req_by ON party_plan_cancellation_requests(requested_by_id);
                CREATE INDEX IF NOT EXISTS idx_pp_canc_req_rec_id ON party_plan_cancellation_requests(recipient_user_id);
            `);

            logger.info('Database schema and performance indexes verified successfully.');
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

        // ── Seed Default Time Lock Configurations ──
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
        } catch (dbErr: any) {
            logger.warn('Failed to verify/seed Time Lock schema: ' + dbErr.message);
        }

        // ── Seed Default Smart Wallet Config if none exists ──
        try {
            await sequelize.query(`
                CREATE TABLE IF NOT EXISTS smart_wallets (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
                    balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    locked_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    pending_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    promotional_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    cashback_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    reward_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    lifetime_recharged DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    lifetime_spent DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    lifetime_promotional DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    lifetime_cashback DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    lifetime_rewards DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    lifetime_refunds DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    is_frozen BOOLEAN NOT NULL DEFAULT FALSE,
                    frozen_reason TEXT,
                    frozen_at TIMESTAMP WITH TIME ZONE,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
                );
            `);

            await sequelize.query(`
                CREATE TABLE IF NOT EXISTS smart_wallet_configs (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    scope VARCHAR(50) NOT NULL UNIQUE DEFAULT 'global',
                    min_recharge_amount DECIMAL(10,2) NOT NULL DEFAULT 100.00,
                    max_recharge_amount DECIMAL(10,2) NOT NULL DEFAULT 50000.00,
                    suggested_amounts JSONB NOT NULL DEFAULT '[100, 250, 500, 1000, 2000]',
                    daily_recharge_limit DECIMAL(10,2) NOT NULL DEFAULT 100000.00,
                    monthly_recharge_limit DECIMAL(10,2) NOT NULL DEFAULT 500000.00,
                    is_wallet_active BOOLEAN NOT NULL DEFAULT TRUE,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
                );
            `);

            await sequelize.query(`
                INSERT INTO smart_wallet_configs (id, scope, min_recharge_amount, max_recharge_amount, suggested_amounts, daily_recharge_limit, monthly_recharge_limit, is_wallet_active, created_at, updated_at)
                VALUES (gen_random_uuid(), 'global', 100.00, 50000.00, '[100, 250, 500, 1000, 2000]'::jsonb, 100000.00, 500000.00, true, NOW(), NOW())
                ON CONFLICT (scope) DO NOTHING;
            `);
        } catch (walletErr: any) {
            logger.warn('Failed to verify/seed Smart Credit Wallet schema: ' + walletErr.message);
        }

        // ── Ensure payment_intents table exists (required for Large Party / Group Party Razorpay flow) ──
        try {
            await sequelize.query(`
                CREATE TABLE IF NOT EXISTS payment_intents (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    payment_reference VARCHAR(100) NOT NULL UNIQUE,
                    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    entity_type VARCHAR(50) NOT NULL,
                    entity_id VARCHAR(100) NOT NULL,
                    amount NUMERIC(10,2) NOT NULL,
                    wallet_amount_used NUMERIC(10,2) NOT NULL DEFAULT 0,
                    razorpay_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
                    currency VARCHAR(3) NOT NULL DEFAULT 'INR',
                    status VARCHAR(30) NOT NULL DEFAULT 'initiated',
                    payment_method VARCHAR(30) NOT NULL DEFAULT 'razorpay',
                    razorpay_order_id VARCHAR(100),
                    razorpay_payment_id VARCHAR(100),
                    razorpay_signature VARCHAR(255),
                    expires_at TIMESTAMP WITH TIME ZONE,
                    failure_reason TEXT,
                    metadata JSONB,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
                );
            `);
            // Add any missing columns to existing payment_intents table (idempotent upgrades)
            await sequelize.query(`
                DO $$ BEGIN
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='payment_intents' AND column_name='wallet_amount_used') THEN ALTER TABLE payment_intents ADD COLUMN wallet_amount_used NUMERIC(10,2) NOT NULL DEFAULT 0; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='payment_intents' AND column_name='razorpay_amount') THEN ALTER TABLE payment_intents ADD COLUMN razorpay_amount NUMERIC(10,2) NOT NULL DEFAULT 0; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='payment_intents' AND column_name='failure_reason') THEN ALTER TABLE payment_intents ADD COLUMN failure_reason TEXT; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='payment_intents' AND column_name='metadata') THEN ALTER TABLE payment_intents ADD COLUMN metadata JSONB; END IF;
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='payment_intents' AND column_name='expires_at') THEN ALTER TABLE payment_intents ADD COLUMN expires_at TIMESTAMP WITH TIME ZONE; END IF;
                END $$;
            `);
            // Performance indexes for payment_intents
            await sequelize.query(`
                CREATE INDEX IF NOT EXISTS idx_payment_intents_user_id ON payment_intents(user_id);
                CREATE INDEX IF NOT EXISTS idx_payment_intents_entity ON payment_intents(entity_type, entity_id);
                CREATE INDEX IF NOT EXISTS idx_payment_intents_status ON payment_intents(status);
                CREATE INDEX IF NOT EXISTS idx_payment_intents_reference ON payment_intents(payment_reference);
            `);
            logger.info('payment_intents table and indexes verified successfully.');
        } catch (piErr: any) {
            logger.warn('Failed to verify payment_intents schema: ' + piErr.message);
        }

        // ── High-Performance Ticket Dashboard Indexes ──
        try {
            await sequelize.query(`
                CREATE INDEX IF NOT EXISTS idx_tickets_user_event_start ON tickets(user_id, event_start_at DESC);
                CREATE INDEX IF NOT EXISTS idx_tickets_booking_id ON tickets(booking_id);
                CREATE INDEX IF NOT EXISTS idx_bookings_user_date ON bookings(user_id, booking_date DESC);
                CREATE INDEX IF NOT EXISTS idx_group_parties_user_date ON group_parties(user_id, party_date DESC);
                CREATE INDEX IF NOT EXISTS idx_party_plan_req_user_status ON party_plan_requests(requester_id, status);
                CREATE INDEX IF NOT EXISTS idx_party_plans_user_date ON party_plans(user_id, plan_date_time DESC);
                CREATE INDEX IF NOT EXISTS idx_strangers_joiner_user_status ON strangers_meet_joiners(user_id, status);
                CREATE INDEX IF NOT EXISTS idx_strangers_meet_user_date ON strangers_meet_requests(user_id, event_date_time DESC);
                CREATE INDEX IF NOT EXISTS idx_plans_user_date ON plans(user_id, plan_date DESC);
                CREATE INDEX IF NOT EXISTS idx_plan_join_requests_user_status ON plan_join_requests(requester_id, status);
            `);
            logger.info('Ticket Dashboard performance indexes verified successfully.');
        } catch (idxErr: any) {
            logger.warn('Failed to verify Ticket Dashboard indexes: ' + idxErr.message);
        }

        if (process.env.NODE_ENV === 'development') {
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
