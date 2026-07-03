const dotenv = require('dotenv');

// Load environment variables
dotenv.config();

console.log('Environment Variables Check on Server:');
console.log('NODE_ENV:', process.env.NODE_ENV);
console.log('DB_HOST:', process.env.DB_HOST);
console.log('DB_PORT:', process.env.DB_PORT);
console.log('DB_NAME:', process.env.DB_NAME);
console.log('DB_USER:', process.env.DB_USER);
console.log('DB_PASSWORD:', process.env.DB_PASSWORD ? '***SET***' : 'NOT SET');
console.log('DB_SSL:', process.env.DB_SSL);
console.log('PORT:', process.env.PORT);

// Test database connection
const { Sequelize } = require('sequelize');

const sequelize = new Sequelize({
    dialect: 'postgres',
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432'),
    database: process.env.DB_NAME || 'lunara_db',
    username: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || '',
    logging: false,
});

async function testConnection() {
    try {
        console.log('\nTesting database connection...');
        await sequelize.authenticate();
        console.log('✅ Database connection successful!');
    } catch (error) {
        console.log('❌ Database connection failed:');
        console.error(error.message);
        console.error('Full error:', error);
    } finally {
        await sequelize.close();
    }
}

testConnection();