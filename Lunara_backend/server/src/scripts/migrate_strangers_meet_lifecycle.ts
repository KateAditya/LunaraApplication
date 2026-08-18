import sequelize from '../config/database';

async function migrate() {
    try {
        await sequelize.authenticate();
        console.log('Database connected.');

        await sequelize.query(`
            DO $$ BEGIN
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
            END $$;
        `);

        console.log('✅ Strangers Meet Request lifecycle & reminder columns successfully added to Postgres!');
        await sequelize.close();
        process.exit(0);
    } catch (e) {
        console.error('❌ Migration failed:', e);
        process.exit(1);
    }
}

migrate();
