const { Sequelize } = require('sequelize');
require('dotenv').config();

const sequelize = new Sequelize({
    dialect: 'postgres',
    host: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT),
    database: process.env.DB_NAME,
    username: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    dialectOptions: {
        ssl: process.env.DB_SSL === 'true' ? {
            require: true,
            rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED !== 'false',
        } : false,
    },
});

async function run() {
    try {
        await sequelize.authenticate();
        console.log('Connected!');
        const [results] = await sequelize.query("SELECT id, name, opening_time, closing_time, days_open, closed_dates FROM venues WHERE name ILIKE '%Favela%' LIMIT 5;");
        console.log(JSON.stringify(results, null, 2));
    } catch (err) {
        console.error(err);
    } finally {
        await sequelize.close();
    }
}
run();
