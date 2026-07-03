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

async function checkUser() {
    try {
        const [results] = await sequelize.query(
            "SELECT id, email, phone, created_at FROM users WHERE email = 'user_1772518647072@example.com' OR phone = '9404042720'"
        );
        console.log(JSON.stringify(results, null, 2));
    } catch (error) {
        console.error('Error:', error.message);
    } finally {
        await sequelize.close();
    }
}

checkUser();
