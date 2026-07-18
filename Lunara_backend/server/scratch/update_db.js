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
        
        try {
            await sequelize.query(`ALTER TYPE "enum_group_parties_status" ADD VALUE IF NOT EXISTS 'approved';`);
            console.log('Added approved');
        } catch (e) {
            console.log('approved failed/already exists:', e.message);
        }
        
        try {
            await sequelize.query(`ALTER TYPE "enum_group_parties_status" ADD VALUE IF NOT EXISTS 'rejected';`);
            console.log('Added rejected');
        } catch (e) {
            console.log('rejected failed/already exists:', e.message);
        }
    } catch (err) {
        console.error(err);
    } finally {
        await sequelize.close();
    }
}
run();
