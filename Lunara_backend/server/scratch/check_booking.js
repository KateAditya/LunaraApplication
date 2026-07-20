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

async function findBooking() {
    try {
        const [bookings] = await sequelize.query(
            "SELECT id, booking_number, status, admin_approval_status, admin_payment_amount, going_mode, total_amount, number_of_guests FROM bookings WHERE number_of_guests = 21 OR total_amount::numeric = 234567.00"
        );
        console.log("Bookings found:", JSON.stringify(bookings, null, 2));

        const [groupParties] = await sequelize.query(
            "SELECT * FROM group_parties WHERE total_amount::numeric = 234567.00"
        );
        console.log("Group Parties found:", JSON.stringify(groupParties, null, 2));
    } catch (error) {
        console.error('Error:', error.message);
    } finally {
        await sequelize.close();
    }
}

findBooking();
