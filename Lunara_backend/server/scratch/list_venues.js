const { Sequelize } = require('sequelize');
require('dotenv').config();

const sequelize = new Sequelize(
    process.env.DB_NAME,
    process.env.DB_USER,
    process.env.DB_PASSWORD,
    {
        host: process.env.DB_HOST,
        dialect: 'postgres',
        logging: false
    }
);

async function listVenues() {
    try {
        const [results] = await sequelize.query(
            "SELECT id, name, city, status, is_active FROM venues"
        );
        console.log("Venues in DB:", JSON.stringify(results, null, 2));
    } catch (error) {
        console.error('Error:', error.message);
    } finally {
        await sequelize.close();
    }
}

listVenues();
