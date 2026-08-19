import sequelize from '../config/database';

async function runMigration() {
    try {
        console.log('Running party_plans arrival columns migration...');
        await sequelize.query(`
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_24h_sent BOOLEAN DEFAULT false;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_3h_sent BOOLEAN DEFAULT false;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_2h_sent BOOLEAN DEFAULT false;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_1h_sent BOOLEAN DEFAULT false;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_30m_sent BOOLEAN DEFAULT false;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_20m_sent BOOLEAN DEFAULT false;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_10m_sent BOOLEAN DEFAULT false;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_5m_sent BOOLEAN DEFAULT false;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_on_time_sent BOOLEAN DEFAULT false;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_post_5m_sent BOOLEAN DEFAULT false;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_post_10m_sent BOOLEAN DEFAULT false;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_post_30m_sent BOOLEAN DEFAULT false;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS expired_no_show_cancelled BOOLEAN DEFAULT false;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_arrival_confirmed BOOLEAN DEFAULT false;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_arrival_time TIMESTAMP WITH TIME ZONE;
            ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_lat_lang_check_in VARCHAR(255);

            DO $$
            BEGIN
                ALTER TYPE enum_group_parties_status ADD VALUE IF NOT EXISTS 'completed';
            EXCEPTION
                WHEN duplicate_object THEN null;
            END $$;
        `);
        console.log('✅ party_plans arrival columns and group_parties enum migration completed successfully!');
        process.exit(0);
    } catch (err) {
        console.error('❌ Migration failed:', err);
        process.exit(1);
    }
}

runMigration();
