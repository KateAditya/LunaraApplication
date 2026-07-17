import sequelize from './src/config/database';

async function check() {
    try {
        const [pkgs]: any = await sequelize.query(`SELECT id, name, tier FROM "SubscriptionPackages";`);
        console.log('Packages:');
        console.log(pkgs);

        const [feats]: any = await sequelize.query(`SELECT id, key, name FROM "SubscriptionFeatures";`);
        console.log('Features:');
        console.log(feats);

        const [planFeats]: any = await sequelize.query(`SELECT id, package_id, feature_id, value, is_enabled FROM "SubscriptionPlanFeatures";`);
        console.log('Plan Features:');
        console.log(planFeats);
    } catch (err) {
        console.error(err);
    } finally {
        await sequelize.close();
    }
}

check();
