import sequelize from '../config/database';

async function runSchemaFix() {
    console.log('🔄 Executing schema fixes on active database...');

    const queries = [
        `CREATE TABLE IF NOT EXISTS profile_boosts (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
            expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
            duration_minutes INTEGER NOT NULL DEFAULT 30,
            transaction_id UUID,
            metadata JSONB,
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
        );`,
        `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_first_check_status VARCHAR(30) DEFAULT 'pending';`,
        `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_first_check_responded_at TIMESTAMP WITH TIME ZONE;`,
        `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_final_check_status VARCHAR(30) DEFAULT 'pending';`,
        `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_final_check_responded_at TIMESTAMP WITH TIME ZONE;`,
        `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reach_verification_stage VARCHAR(30) DEFAULT 'pre_event_check';`,
        `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS attendance_decision VARCHAR(40) DEFAULT 'pending';`,
        `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reach_refund_decision VARCHAR(40) DEFAULT 'pending';`,
        `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS verification_expiry_at TIMESTAMP WITH TIME ZONE;`,

        `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_first_check_status VARCHAR(30) DEFAULT 'pending';`,
        `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_first_check_responded_at TIMESTAMP WITH TIME ZONE;`,
        `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_final_check_status VARCHAR(30) DEFAULT 'pending';`,
        `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_final_check_responded_at TIMESTAMP WITH TIME ZONE;`,

        `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS party_plan_limit INTEGER DEFAULT 1;`,
        `ALTER TABLE "SubscriptionPackages" ADD COLUMN IF NOT EXISTS party_plan_period_days INTEGER DEFAULT 7;`,
        `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS expiration_alert_sent BOOLEAN DEFAULT false;`,
        `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder1_day_sent BOOLEAN DEFAULT false;`,
        `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder8_hour_sent BOOLEAN DEFAULT false;`,
        `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder5_hour_sent BOOLEAN DEFAULT false;`,
        `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder2_hour_sent BOOLEAN DEFAULT false;`,
        `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder1_hour_sent BOOLEAN DEFAULT false;`,
        `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS expiry_notified BOOLEAN DEFAULT false;`,
        `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS last_notified_at TIMESTAMP WITH TIME ZONE;`,
    ];

    for (const q of queries) {
        try {
            await sequelize.query(q);
            console.log('✅ Executed query:', q.substring(0, 60));
        } catch (err: any) {
            console.warn('⚠️ Query warning:', err?.message);
        }
    }

    console.log('🎉 Schema fix completed successfully!');
    process.exit(0);
}

runSchemaFix().catch((e) => {
    console.error('❌ Schema fix failed:', e);
    process.exit(1);
});
