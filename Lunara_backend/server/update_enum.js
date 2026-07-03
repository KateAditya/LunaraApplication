const { Sequelize } = require('sequelize');
require('dotenv').config();

const sequelize = new Sequelize({
    dialect: 'postgres',
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432'),
    database: process.env.DB_NAME || 'lunara_db',
    username: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || '',
});

async function run() {
    try {
        await sequelize.authenticate();
        console.log('Connected to DB');
        await sequelize.query(`ALTER TYPE enum_bookings_going_mode ADD VALUE IF NOT EXISTS 'party_request';`);
        console.log('Added party_request to enum_bookings_going_mode');
    } catch (e) {
        console.error(e.message);
    } finally {
        await sequelize.close();
    }
}

run();
