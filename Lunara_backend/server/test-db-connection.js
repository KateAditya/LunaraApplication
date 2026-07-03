// Simple PostgreSQL connection test script with better error handling
const { Client } = require('pg');
const fs = require('fs');
require('dotenv').config();

const logFile = 'db-test-log.txt';
let logOutput = '';

function log(message) {
    console.log(message);
    logOutput += message + '\n';
}

const client = new Client({
    host: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT || '5432'),
    database: 'postgres',
    user: 'postgres',
    password: 'JaiGanesh@2025',
    connectionTimeoutMillis: 10000,
    ssl: process.env.DB_SSL === 'true' ? {
        rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED !== 'false',
    } : false,
});

async function testConnection() {
    try {
        log('='.repeat(60));
        log('PostgreSQL Connection Test');
        log('='.repeat(60));
        log('Host: ' + process.env.DB_HOST);
        log('Port: ' + process.env.DB_PORT);
        log('User: ' + process.env.DB_USER);
        log('Database: postgres (default)');
        log('');
        log('Connecting...');

        await client.connect();
        log('SUCCESS: Connected to PostgreSQL!');
        log('');

        const versionResult = await client.query('SELECT version()');
        log('PostgreSQL Version:');
        log(versionResult.rows[0].version.substring(0, 100) + '...');
        log('');

        const dbResult = await client.query(
            "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname"
        );
        log('Existing Databases:');
        dbResult.rows.forEach((row) => {
            log('  - ' + row.datname);
        });
        log('');

        const lunaraDbExists = dbResult.rows.some(row => row.datname === 'lunara_db');

        if (!lunaraDbExists) {
            log('INFO: Database "lunara_db" does not exist yet.');
            log('Creating database "lunara_db"...');
            await client.query('CREATE DATABASE lunara_db');
            log('SUCCESS: Database "lunara_db" created!');
        } else {
            log('INFO: Database "lunara_db" already exists!');
        }

        await client.end();
        log('');
        log('='.repeat(60));
        log('TEST RESULT: SUCCESS');
        log('='.repeat(60));

        fs.writeFileSync(logFile, logOutput);
        log('Log saved to: ' + logFile);

    } catch (error) {
        log('');
        log('='.repeat(60));
        log('TEST RESULT: FAILED');
        log('='.repeat(60));
        log('Error: ' + error.message);
        log('Code: ' + (error.code || 'N/A'));
        log('');

        if (error.code === 'ECONNREFUSED') {
            log('CAUSE: Connection refused');
            log('  - PostgreSQL may not be running');
            log('  - Firewall may be blocking port 5432');
        } else if (error.code === 'ETIMEDOUT') {
            log('CAUSE: Connection timeout');
            log('  - Server may be unreachable');
            log('  - Firewall may be blocking traffic');
        } else if (error.code === '28P01') {
            log('CAUSE: Authentication failed');
            log('  - Check username/password');
        } else if (error.code === '3D000') {
            log('CAUSE: Database does not exist');
        } else {
            log('Full error: ' + JSON.stringify(error, null, 2));
        }

        fs.writeFileSync(logFile, logOutput);
        log('');
        log('Log saved to: ' + logFile);
        process.exit(1);
    }
}

testConnection();
