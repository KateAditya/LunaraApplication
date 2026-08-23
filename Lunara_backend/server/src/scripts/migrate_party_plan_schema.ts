import dotenv from 'dotenv';
import sequelize from '../config/database';
import { logger } from '../config/logger';

dotenv.config();

/**
 * Safe, idempotent migration script.
 * Uses ADD COLUMN IF NOT EXISTS and CREATE TABLE IF NOT EXISTS exclusively.
 * Safe to run on a live production database — will NOT drop or truncate anything.
 */
async function runMigration() {
    try {
        console.log('='.repeat(70));
        console.log('Lunara — Safe Schema Migration (Party Plan + Cancellation + Wallet)');
        console.log('='.repeat(70));

        await sequelize.authenticate();
        console.log('✅ DB connected\n');

        // ─────────────────────────────────────────────────────────────────────
        // 1. users — add missing columns
        // ─────────────────────────────────────────────────────────────────────
        console.log('Migrating: users...');
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS wallet_balance          DECIMAL(10,2)  NOT NULL DEFAULT 0.00`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS reliability_score        INTEGER        NOT NULL DEFAULT 70`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS reward_points            INTEGER        NOT NULL DEFAULT 0`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS login_streak_days        INTEGER        NOT NULL DEFAULT 0`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_streak_date   TIMESTAMP`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS no_show_count            INTEGER        NOT NULL DEFAULT 0`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token                VARCHAR(500)`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS cleared_notifications_at TIMESTAMP`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS mfa_enabled              BOOLEAN        NOT NULL DEFAULT FALSE`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS mfa_secret               VARCHAR(255)`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS facebook_id              VARCHAR(100)`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id                VARCHAR(100)`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS is_deleted               BOOLEAN        NOT NULL DEFAULT FALSE`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at               TIMESTAMP`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS deletion_reason          TEXT`);
        console.log('✅ users\n');

        // ─────────────────────────────────────────────────────────────────────
        // 2. user_profiles — add missing columns
        // ─────────────────────────────────────────────────────────────────────
        console.log('Migrating: user_profiles...');
        await sequelize.query(`ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS reliability_score          INTEGER   NOT NULL DEFAULT 100`);
        await sequelize.query(`ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS nightlife_preference       TEXT[]    DEFAULT '{}'`);
        await sequelize.query(`ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS daily_match_requests_count INTEGER   DEFAULT 0`);
        await sequelize.query(`ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS daily_likes_count          INTEGER   DEFAULT 0`);
        await sequelize.query(`ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS daily_posts_count          INTEGER   DEFAULT 0`);
        await sequelize.query(`ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS last_activity_date         TIMESTAMP`);
        console.log('✅ user_profiles\n');

        // ─────────────────────────────────────────────────────────────────────
        // 3. party_plans — add ALL missing columns
        // ─────────────────────────────────────────────────────────────────────
        console.log('Migrating: party_plans...');
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS lifecycle_status           VARCHAR(60)    NOT NULL DEFAULT 'posted'`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS payment_type               VARCHAR(20)    NOT NULL DEFAULT 'split'`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS deposit_amount             DECIMAL(10,2)  NOT NULL DEFAULT 99.00`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_payment_status        VARCHAR(20)    NOT NULL DEFAULT 'unpaid'`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_razorpay_order_id     VARCHAR(255)`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_razorpay_payment_id   VARCHAR(255)`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS is_live                    BOOLEAN        NOT NULL DEFAULT FALSE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS expires_at                 TIMESTAMP`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_lat_lang_check_in     BOOLEAN        NOT NULL DEFAULT FALSE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS payment_status             VARCHAR(50)    NOT NULL DEFAULT 'pending'`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS mobile_number              VARCHAR(20)    NOT NULL DEFAULT ''`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS optional_mobile_number     VARCHAR(20)`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS food_preference            VARCHAR(100)`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS drink_preference           VARCHAR(100)`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS show_profile_photo         BOOLEAN        NOT NULL DEFAULT TRUE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS show_host_name             BOOLEAN        NOT NULL DEFAULT TRUE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS show_venue_details         BOOLEAN        NOT NULL DEFAULT TRUE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS show_date_details          BOOLEAN        NOT NULL DEFAULT TRUE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_arrival_confirmed     BOOLEAN        NOT NULL DEFAULT FALSE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_arrival_time          TIMESTAMP`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_first_check_status       VARCHAR(30)    DEFAULT 'pending'`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_first_check_responded_at TIMESTAMP WITH TIME ZONE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_final_check_status       VARCHAR(30)    DEFAULT 'pending'`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_final_check_responded_at TIMESTAMP WITH TIME ZONE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reach_verification_stage      VARCHAR(30)    DEFAULT 'pre_event_check'`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS attendance_decision           VARCHAR(40)    DEFAULT 'pending'`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reach_refund_decision         VARCHAR(40)    DEFAULT 'pending'`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS verification_expiry_at        TIMESTAMP WITH TIME ZONE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_24h_sent          BOOLEAN        NOT NULL DEFAULT FALSE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_3h_sent           BOOLEAN        NOT NULL DEFAULT FALSE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_1h_sent           BOOLEAN        NOT NULL DEFAULT FALSE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_30m_sent          BOOLEAN        NOT NULL DEFAULT FALSE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_2h_sent           BOOLEAN        NOT NULL DEFAULT FALSE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_10m_sent          BOOLEAN        NOT NULL DEFAULT FALSE`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS accepted_at                TIMESTAMP`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS payment_deadline_at        TIMESTAMP`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS matched_request_id         UUID`);
        await sequelize.query(`ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS selected_users             UUID[]`);
        console.log('✅ party_plans\n');

        // ─────────────────────────────────────────────────────────────────────
        // 4. party_plan_requests — add missing columns
        // ─────────────────────────────────────────────────────────────────────
        console.log('Migrating: party_plan_requests...');
        await sequelize.query(`ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS joiner_razorpay_order_id   VARCHAR(255)`);
        await sequelize.query(`ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS joiner_razorpay_payment_id  VARCHAR(255)`);
        await sequelize.query(`ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS payment_timeout_at           TIMESTAMP`);
        await sequelize.query(`ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS lat_lang_check_in            BOOLEAN NOT NULL DEFAULT FALSE`);
        await sequelize.query(`ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_arrival_confirmed      BOOLEAN NOT NULL DEFAULT FALSE`);
        await sequelize.query(`ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_arrival_time           TIMESTAMP`);
        await sequelize.query(`ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_first_check_status       VARCHAR(30) DEFAULT 'pending'`);
        await sequelize.query(`ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_first_check_responded_at TIMESTAMP WITH TIME ZONE`);
        await sequelize.query(`ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_final_check_status       VARCHAR(30) DEFAULT 'pending'`);
        await sequelize.query(`ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_final_check_responded_at TIMESTAMP WITH TIME ZONE`);
        await sequelize.query(`ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS cancelled_at                 TIMESTAMP`);
        await sequelize.query(`ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS cancelled_by                 UUID`);
        await sequelize.query(`ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS cancellation_reason          VARCHAR(100)`);
        await sequelize.query(`ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS previous_status              VARCHAR(50)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_party_plan_requests_cancelled_by ON party_plan_requests(cancelled_by)`);
        console.log('✅ party_plan_requests\n');

        // ─────────────────────────────────────────────────────────────────────
        // 5. smart_wallets (CREATE IF NOT EXISTS)
        // ─────────────────────────────────────────────────────────────────────
        console.log('Creating: smart_wallets...');
        await sequelize.query(`
            CREATE TABLE IF NOT EXISTS smart_wallets (
                id                   UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id              UUID          NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
                balance              DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                locked_balance       DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                pending_balance      DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                promotional_balance  DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                cashback_balance     DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                reward_balance       DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                lifetime_recharged   DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                lifetime_spent       DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                lifetime_promotional DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                lifetime_cashback    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                lifetime_rewards     DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                lifetime_refunds     DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                is_frozen            BOOLEAN       NOT NULL DEFAULT FALSE,
                frozen_reason        TEXT,
                frozen_at            TIMESTAMP,
                created_at           TIMESTAMP     NOT NULL DEFAULT NOW(),
                updated_at           TIMESTAMP     NOT NULL DEFAULT NOW()
            )
        `);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_smart_wallets_user_id  ON smart_wallets(user_id)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_smart_wallets_is_frozen ON smart_wallets(is_frozen)`);
        console.log('✅ smart_wallets\n');

        // ─────────────────────────────────────────────────────────────────────
        // 6. wallet_transactions (CREATE IF NOT EXISTS)
        // ─────────────────────────────────────────────────────────────────────
        console.log('Creating: wallet_transactions...');
        await sequelize.query(`
            CREATE TABLE IF NOT EXISTS wallet_transactions (
                id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
                wallet_id        UUID,
                user_id          UUID          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                booking_id       UUID,
                party_plan_id    UUID,
                amount           DECIMAL(10,2) NOT NULL,
                opening_balance  DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                closing_balance  DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                transaction_type VARCHAR(50)   NOT NULL,
                status           VARCHAR(20)   NOT NULL DEFAULT 'success',
                reference        VARCHAR(255),
                source           VARCHAR(100),
                destination      VARCHAR(100),
                created_by       VARCHAR(100),
                metadata         JSONB,
                created_at       TIMESTAMP     NOT NULL DEFAULT NOW(),
                updated_at       TIMESTAMP     NOT NULL DEFAULT NOW()
            )
        `);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_id         ON wallet_transactions(user_id)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_wallet_tx_transaction_type ON wallet_transactions(transaction_type)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_wallet_tx_status           ON wallet_transactions(status)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_wallet_tx_created_at       ON wallet_transactions(created_at)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_wallet_tx_reference        ON wallet_transactions(reference)`);
        console.log('✅ wallet_transactions\n');

        // ─────────────────────────────────────────────────────────────────────
        // 7. reliability_history (CREATE IF NOT EXISTS)
        // ─────────────────────────────────────────────────────────────────────
        console.log('Creating: reliability_history...');
        await sequelize.query(`
            CREATE TABLE IF NOT EXISTS reliability_history (
                id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id       UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                old_score     INTEGER      NOT NULL,
                new_score     INTEGER      NOT NULL,
                change        INTEGER      NOT NULL,
                reason        VARCHAR(255) NOT NULL,
                action        VARCHAR(255) NOT NULL,
                booking_id    UUID,
                party_plan_id UUID,
                metadata      JSONB,
                created_at    TIMESTAMP    NOT NULL DEFAULT NOW()
            )
        `);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_reliability_history_user_id    ON reliability_history(user_id)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_reliability_history_created_at ON reliability_history(created_at)`);
        console.log('✅ reliability_history\n');

        // ─────────────────────────────────────────────────────────────────────
        // 8. party_plan_cancellation_requests (CREATE IF NOT EXISTS)
        // ─────────────────────────────────────────────────────────────────────
        console.log('Creating: party_plan_cancellation_requests...');
        await sequelize.query(`
            CREATE TABLE IF NOT EXISTS party_plan_cancellation_requests (
                id                           UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
                plan_id                      UUID          NOT NULL REFERENCES party_plans(id) ON DELETE CASCADE,
                booking_id                   UUID,
                requested_by_id              UUID          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                recipient_user_id            UUID          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                status                       VARCHAR(30)   NOT NULL DEFAULT 'pending',
                reason                       VARCHAR(50)   NOT NULL DEFAULT 'my_plans_changed',
                other_reason_text            VARCHAR(150),
                requested_at                 TIMESTAMP     NOT NULL DEFAULT NOW(),
                expires_at                   TIMESTAMP     NOT NULL,
                responded_at                 TIMESTAMP,
                responded_by_id              UUID          REFERENCES users(id) ON DELETE SET NULL,
                auto_approval_eligible       BOOLEAN       NOT NULL DEFAULT FALSE,
                host_deposit_amount          DECIMAL(10,2) NOT NULL DEFAULT 99.00,
                joiner_deposit_amount        DECIMAL(10,2) NOT NULL DEFAULT 99.00,
                host_wallet_transaction_id   VARCHAR(255),
                joiner_wallet_transaction_id VARCHAR(255),
                reliability_impact           INTEGER       NOT NULL DEFAULT -5,
                created_at                   TIMESTAMP     NOT NULL DEFAULT NOW(),
                updated_at                   TIMESTAMP     NOT NULL DEFAULT NOW()
            )
        `);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_cancellation_plan_id         ON party_plan_cancellation_requests(plan_id)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_cancellation_requested_by_id ON party_plan_cancellation_requests(requested_by_id)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_cancellation_recipient_id    ON party_plan_cancellation_requests(recipient_user_id)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_cancellation_status          ON party_plan_cancellation_requests(status)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_cancellation_expires_at      ON party_plan_cancellation_requests(expires_at)`);
        console.log('✅ party_plan_cancellation_requests\n');

        // ─────────────────────────────────────────────────────────────────────
        // 9. plan_time_locks (CREATE IF NOT EXISTS)
        // ─────────────────────────────────────────────────────────────────────
        console.log('Creating: plan_time_locks...');
        await sequelize.query(`
            CREATE TABLE IF NOT EXISTS plan_time_locks (
                id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id          UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                source_plan_id   UUID        NOT NULL,
                source_plan_type VARCHAR(50) NOT NULL,
                lock_start_at    TIMESTAMP   NOT NULL,
                lock_end_at      TIMESTAMP   NOT NULL,
                status           VARCHAR(20) NOT NULL DEFAULT 'active',
                reason           TEXT,
                created_at       TIMESTAMP   NOT NULL DEFAULT NOW(),
                updated_at       TIMESTAMP   NOT NULL DEFAULT NOW()
            )
        `);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_plan_time_locks_user_id        ON plan_time_locks(user_id)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_plan_time_locks_source_plan_id ON plan_time_locks(source_plan_id)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_plan_time_locks_status         ON plan_time_locks(status)`);
        console.log('✅ plan_time_locks\n');

        // ─────────────────────────────────────────────────────────────────────
        // 10. notifications (CREATE IF NOT EXISTS)
        // ─────────────────────────────────────────────────────────────────────
        console.log('Creating: notifications...');
        await sequelize.query(`
            CREATE TABLE IF NOT EXISTS notifications (
                id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
                recipient_user_id UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                actor_user_id     UUID         REFERENCES users(id) ON DELETE SET NULL,
                event_type        VARCHAR(100) NOT NULL,
                category          VARCHAR(50)  NOT NULL DEFAULT 'system',
                entity_type       VARCHAR(50),
                entity_id         VARCHAR(255),
                title             VARCHAR(255) NOT NULL,
                body              TEXT         NOT NULL,
                image_url         VARCHAR(500),
                action_type       VARCHAR(50),
                deep_link         VARCHAR(500),
                is_read           BOOLEAN      NOT NULL DEFAULT FALSE,
                read_at           TIMESTAMP,
                expires_at        TIMESTAMP,
                priority          VARCHAR(20)  NOT NULL DEFAULT 'NORMAL',
                idempotency_key   VARCHAR(255) UNIQUE,
                metadata          JSONB,
                created_at        TIMESTAMP    NOT NULL DEFAULT NOW(),
                updated_at        TIMESTAMP    NOT NULL DEFAULT NOW()
            )
        `);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_notifications_recipient_is_read ON notifications(recipient_user_id, is_read)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_notifications_recipient_created  ON notifications(recipient_user_id, created_at)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_notifications_idempotency_key    ON notifications(idempotency_key)`);
        console.log('✅ notifications\n');

        // ─────────────────────────────────────────────────────────────────────
        // 11. chat_subscriptions — add valid_until if missing
        // ─────────────────────────────────────────────────────────────────────
        console.log('Migrating: chat_subscriptions...');
        await sequelize.query(`ALTER TABLE chat_subscriptions ADD COLUMN IF NOT EXISTS valid_until TIMESTAMP`);
        console.log('✅ chat_subscriptions\n');

        // ─────────────────────────────────────────────────────────────────────
        // 12. audit_logs (CREATE IF NOT EXISTS)
        // ─────────────────────────────────────────────────────────────────────
        console.log('Creating: audit_logs...');
        await sequelize.query(`
            CREATE TABLE IF NOT EXISTS audit_logs (
                id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id       UUID         REFERENCES users(id) ON DELETE SET NULL,
                booking_id    UUID,
                party_plan_id UUID,
                action        VARCHAR(100) NOT NULL,
                metadata      JSONB,
                ip_address    VARCHAR(45),
                device_id     VARCHAR(255),
                created_at    TIMESTAMP    NOT NULL DEFAULT NOW(),
                updated_at    TIMESTAMP    NOT NULL DEFAULT NOW()
            )
        `);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id       ON audit_logs(user_id)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_audit_logs_party_plan_id ON audit_logs(party_plan_id)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_audit_logs_booking_id    ON audit_logs(booking_id)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_audit_logs_action        ON audit_logs(action)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at    ON audit_logs(created_at)`);
        console.log('✅ audit_logs\n');

        // ─────────────────────────────────────────────────────────────────────
        // 13. party_reviews (CREATE IF NOT EXISTS)
        // ─────────────────────────────────────────────────────────────────────
        console.log('Creating: party_reviews...');
        await sequelize.query(`
            CREATE TABLE IF NOT EXISTS party_reviews (
                id            UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
                plan_id       UUID      NOT NULL REFERENCES party_plans(id) ON DELETE CASCADE,
                booking_id    UUID,
                reviewer_id   UUID      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                reviewee_id   UUID      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                rating        INTEGER   NOT NULL CHECK (rating >= 1 AND rating <= 5),
                comment       TEXT,
                is_reported   BOOLEAN   NOT NULL DEFAULT FALSE,
                report_reason VARCHAR(255),
                created_at    TIMESTAMP NOT NULL DEFAULT NOW(),
                updated_at    TIMESTAMP NOT NULL DEFAULT NOW()
            )
        `);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_party_reviews_plan_id     ON party_reviews(plan_id)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_party_reviews_reviewer_id ON party_reviews(reviewer_id)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_party_reviews_reviewee_id ON party_reviews(reviewee_id)`);
        console.log('✅ party_reviews\n');

        // ─────────────────────────────────────────────────────────────────────
        // 14. reward_point_ledgers (CREATE IF NOT EXISTS)
        // ─────────────────────────────────────────────────────────────────────
        console.log('Creating: reward_point_ledgers...');
        await sequelize.query(`
            CREATE TABLE IF NOT EXISTS reward_point_ledgers (
                id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id       UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                points        INTEGER     NOT NULL,
                type          VARCHAR(20) NOT NULL,
                balance_after INTEGER     NOT NULL DEFAULT 0,
                reason        VARCHAR(255) NOT NULL,
                reference     VARCHAR(255),
                metadata      JSONB,
                created_at    TIMESTAMP   NOT NULL DEFAULT NOW()
            )
        `);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_reward_ledger_user_id    ON reward_point_ledgers(user_id)`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS idx_reward_ledger_created_at ON reward_point_ledgers(created_at)`);
        console.log('✅ reward_point_ledgers\n');

        // ─────────────────────────────────────────────────────────────────────
        // Final verification
        // ─────────────────────────────────────────────────────────────────────
        const [tables]: any = await sequelize.query(`
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
            ORDER BY table_name
        `);

        console.log('='.repeat(70));
        console.log(`✅ Migration complete! Total tables: ${tables.length}`);
        console.log('='.repeat(70));
        tables.forEach((t: any) => console.log(`  ✓ ${t.table_name}`));

        await sequelize.close();
        process.exit(0);
    } catch (err: any) {
        console.error('❌ Migration failed:', err.message);
        logger.error('Migration failed:', err);
        process.exit(1);
    }
}

runMigration();
