const { default: sequelize } = require('./dist/config/database');

(async () => {
    try {
        await sequelize.authenticate();
        console.log('Database connected.');

        const [tables] = await sequelize.query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name");
        console.log('Tables in DB:', tables.map(t => t.table_name));

        const [smhCols] = await sequelize.query("SELECT column_name FROM information_schema.columns WHERE table_name = 'strangers_meet_host_cancellation_requests'");
        console.log('strangers_meet_host_cancellation_requests columns:', smhCols.map(c => c.column_name));

        const [lpcCols] = await sequelize.query("SELECT column_name FROM information_schema.columns WHERE table_name = 'large_party_cancellation_requests'");
        console.log('large_party_cancellation_requests columns:', lpcCols.map(c => c.column_name));

        const [gpcCols] = await sequelize.query("SELECT column_name FROM information_schema.columns WHERE table_name = 'party_plan_cancellation_requests'");
        console.log('party_plan_cancellation_requests columns:', gpcCols.map(c => c.column_name));

        const [bpcCols] = await sequelize.query("SELECT column_name FROM information_schema.columns WHERE table_name = 'booking_policy_configs'");
        console.log('booking_policy_configs columns:', bpcCols.map(c => c.column_name));

        const [policies] = await sequelize.query("SELECT * FROM booking_policy_configs");
        console.log('Existing booking_policy_configs:', policies);

        const [latestSmh] = await sequelize.query("SELECT * FROM strangers_meet_host_cancellation_requests ORDER BY created_at DESC LIMIT 5");
        console.log('Latest SM host cancellations:', latestSmh);

        process.exit(0);
    } catch (err) {
        console.error('Error:', err);
        process.exit(1);
    }
})();
