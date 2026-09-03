const { Sequelize } = require('sequelize');
require('dotenv').config();
const sequelize = new Sequelize(process.env.DB_NAME, process.env.DB_USER, process.env.DB_PASSWORD, {
    host: process.env.DB_HOST,
    dialect: 'postgres',
    logging: false
});
async function run() {
    try {
        const tables = ['SubscriptionPackages', 'UserSubscriptions', 'SubscriptionUsage', 'UserAddons', 'ProfileBoosts', 'PartyPlans', 'SubscriptionPlanFeatures', 'SubscriptionFeatures', 'SubscriptionAddonPackages'];
        for (const t of tables) {
            const [res] = await sequelize.query(`SELECT column_name, data_type FROM information_schema.columns WHERE table_name = '${t}' OR table_name = '${t.toLowerCase()}' ORDER BY ordinal_position`);
            console.log('TABLE:', t, res.map(r => r.column_name + ' (' + r.data_type + ')'));
        }
    } catch (e) {
        console.error('Error:', e.message);
    } finally {
        await sequelize.close();
    }
}
run();
