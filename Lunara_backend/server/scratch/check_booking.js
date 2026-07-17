const { Sequelize } = require('sequelize');
require('dotenv').config();

const sequelize = new Sequelize(
    process.env.DB_NAME,
    process.env.DB_USER,
    process.env.DB_PASSWORD,
    {
        host: process.env.DB_HOST,
        dialect: 'postgres',
        logging: false,
        dialectOptions: {
            ssl: {
                require: true,
                rejectUnauthorized: false
            }
        }
    }
);

async function checkBooking() {
    try {
        const [results] = await sequelize.query(
            "SELECT * FROM bookings WHERE id = '78cc2e0b-5694-4029-ab23-0c0504cc4656'"
        );
        console.log("Booking in DB:", JSON.stringify(results, null, 2));
    } catch (error) {
        console.error('Error:', error.message);
    } finally {
        await sequelize.close();
    }
}

checkBooking();
