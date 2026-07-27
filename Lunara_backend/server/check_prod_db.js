const { Client } = require('pg');

async function test() {
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
    
    const res = await client.query(`
      SELECT payment_status, COUNT(*) 
      FROM bookings 
      GROUP BY payment_status
    `);
    
    console.log('Payment statuses:');
    console.table(res.rows);
    
  } catch (err) {
    console.error('Error executing query', err.stack);
  } finally {
    await client.end();
  }
}

test();
