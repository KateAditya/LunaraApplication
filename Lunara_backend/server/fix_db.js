const { Client } = require('pg');

async function fixDB() {
  const client = new Client({
    host: '103.224.247.22',
    port: 5432,
    database: 'lunara_db',
    user: 'postgres',
    password: 'JaiGanesh@2025',
    ssl: false
  });

  try {
    await client.connect();
    
    // Add missing columns if they don't exist
    await client.query(`
      ALTER TABLE bookings 
      ADD COLUMN IF NOT EXISTS ticket_url VARCHAR(500),
      ADD COLUMN IF NOT EXISTS is_upcoming_night BOOLEAN DEFAULT false,
      ADD COLUMN IF NOT EXISTS razorpay_order_id VARCHAR(255);
    `);
    
    console.log('Successfully added missing columns to the database.');
  } catch (err) {
    console.error('Error fixing database:', err.stack);
  } finally {
    await client.end();
  }
}

fixDB();
