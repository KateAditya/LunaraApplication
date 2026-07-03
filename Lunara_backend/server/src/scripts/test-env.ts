import dotenv from 'dotenv';

// Load environment variables
dotenv.config();

console.log('Environment Variables Check:');
console.log('NODE_ENV:', process.env.NODE_ENV);
console.log('DB_HOST:', process.env.DB_HOST);
console.log('DB_PORT:', process.env.DB_PORT);
console.log('DB_NAME:', process.env.DB_NAME);
console.log('DB_USER:', process.env.DB_USER);
console.log('DB_PASSWORD:', process.env.DB_PASSWORD ? '***SET***' : 'NOT SET');
console.log('DB_SSL:', process.env.DB_SSL);
console.log('PORT:', process.env.PORT);

// Test database connection
import sequelize from '../config/database';

async function testConnection() {
    try {
        console.log('\nTesting database connection...');
        await sequelize.authenticate();
        console.log('✅ Database connection successful!');
    } catch (error) {
        console.log('❌ Database connection failed:');
        console.error((error as Error).message);
    } finally {
        await sequelize.close();
    }
}

testConnection();