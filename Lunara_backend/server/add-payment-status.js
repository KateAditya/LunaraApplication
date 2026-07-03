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

async function addColumn() {
    try {
        console.log("Checking if payment_status exists...");
        const [results] = await sequelize.query(
            "SELECT column_name FROM information_schema.columns WHERE table_name = 'party_plans' AND column_name = 'payment_status'"
        );
        if (results.length === 0) {
            console.log("Adding column payment_status to party_plans...");
            await sequelize.query(
                "ALTER TABLE party_plans ADD COLUMN payment_status VARCHAR(20) DEFAULT 'pending'"
            );
            console.log("✅ Column payment_status added successfully.");
        } else {
            console.log("Column payment_status already exists.");
        }
    } catch (error) {
        console.error('Error adding column:', error.message);
    } finally {
        await sequelize.close();
    }
}

addColumn();
