const { Client } = require('pg');

async function main() {
    const client = new Client({
        host: 'lunara-db-v2.postgres.database.azure.com',
        port: 5432,
        user: 'lunaraadmin',
        password: 'JaiGanesh@2026',
        database: 'postgres',
        ssl: {
            rejectUnauthorized: false
        }
    });

    try {
        await client.connect();
        console.log('Connected to postgres database. Creating lunara_test...');
        await client.query('CREATE DATABASE lunara_test;');
        console.log('Database lunara_test created successfully!');
    } catch (err) {
        if (err.code === '42P04') {
            console.log('Database lunara_test already exists.');
        } else {
            console.error('Error creating database:', err);
        }
    } finally {
        await client.end();
    }
}

main();
