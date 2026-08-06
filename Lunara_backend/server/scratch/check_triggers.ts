import sequelize from '../src/config/database';

async function checkTriggersAndRules() {
    try {
        console.log('Querying triggers on users table...');
        const [triggers] = await sequelize.query(`
            SELECT trigger_name, event_manipulation, action_statement
            FROM information_schema.triggers
            WHERE event_object_table = 'users';
        `);
        console.log('Triggers found:', JSON.stringify(triggers, null, 2));

        console.log('Querying rules on users table...');
        const [rules] = await sequelize.query(`
            SELECT tablename, rulename, definition
            FROM pg_rules
            WHERE tablename = 'users';
        `);
        console.log('Rules found:', JSON.stringify(rules, null, 2));

        console.log('Querying constraints...');
        const [constraints] = await sequelize.query(`
            SELECT conname, contype
            FROM pg_constraint
            WHERE conrelid = 'users'::regclass;
        `);
        console.log('Constraints found:', JSON.stringify(constraints, null, 2));

    } catch (err: any) {
        console.error('Error querying triggers/rules:', err);
    } finally {
        await sequelize.close();
    }
}

checkTriggersAndRules();
