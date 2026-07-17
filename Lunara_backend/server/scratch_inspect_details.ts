import sequelize from './src/config/database';

async function check() {
    try {
        const [pkgs]: any = await sequelize.query(`SELECT id, name, tier, price, duration_days FROM "SubscriptionPackages";`);
        console.log('--- PACKAGES ---');
        console.log(JSON.stringify(pkgs, null, 2));

        const [feats]: any = await sequelize.query(`SELECT id, key, name, category FROM "SubscriptionFeatures";`);
        console.log('--- FEATURES ---');
        console.log(JSON.stringify(feats, null, 2));

        const [planFeats]: any = await sequelize.query(`
            SELECT pf.id, pkg.name as package_name, f.key as feature_key, pf.value, pf.is_enabled 
            FROM "SubscriptionPlanFeatures" pf
            JOIN "SubscriptionPackages" pkg ON pf.package_id = pkg.id
            JOIN "SubscriptionFeatures" f ON pf.feature_id = f.id;
        `);
        console.log('--- PLAN FEATURES MAP ---');
        console.log(JSON.stringify(planFeats, null, 2));
    } catch (err) {
        console.error(err);
    } finally {
        await sequelize.close();
    }
}

check();
