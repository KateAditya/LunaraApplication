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

async function checkColumns() {
    try {
        const [results] = await sequelize.query(
            "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'users'"
        );
        console.log("Columns in 'users' table:");
        console.log(results.map(r => `${r.column_name}: ${r.data_type}`).join('\n'));
    } catch (error) {
        console.error('Error:', error.message);
    } finally {
        await sequelize.close();
    }
}

checkColumns();
