/**
 * Run with: node add-fcm-token-column.js
 * 
 * Adds the fcm_token column to the users table if it doesn't already exist.
 */
const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
    host:     process.env.DB_HOST,
    port:     parseInt(process.env.DB_PORT || '5432'),
    database: process.env.DB_NAME,
    user:     process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    ssl:      process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
});

async function run() {
    const client = await pool.connect();
    try {
        // Check if column already exists
        const check = await client.query(`
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'users' AND column_name = 'fcm_token'
        `);

        if (check.rows.length > 0) {
            console.log('✅ fcm_token column already exists, skipping.');
        } else {
            await client.query(`
                ALTER TABLE users ADD COLUMN fcm_token VARCHAR(500);
            `);
            console.log('✅ fcm_token column added to users table.');
        }
    } finally {
        client.release();
        await pool.end();
    }
}

run().catch(err => {
    console.error('❌ Migration failed:', err.message);
    process.exit(1);
});
