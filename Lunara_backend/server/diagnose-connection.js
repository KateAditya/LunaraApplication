// PostgreSQL connection diagnostic script
const { Client } = require('pg');
const fs = require('fs');
require('dotenv').config();

const logFile = 'db-diagnostic-log.txt';
let logOutput = '';

function log(message) {
    console.log(message);
    logOutput += message + '\n';
}

async function testVariousConfigs() {
    const configs = [
        {
            name: 'Config 1: No SSL, direct credentials',
            config: {
                host: '103.224.247.22',
                port: 5432,
                database: 'postgres',
                user: 'postgres',
                password: 'JaiGanesh2025',
                connectionTimeoutMillis: 10000,
                ssl: false,
            }
        },
        {
            name: 'Config 2: SSL with rejectUnauthorized false',
            config: {
                host: '103.224.247.22',
                port: 5432,
                database: 'postgres',
                user: 'postgres',
                password: 'JaiGanesh2025',
                connectionTimeoutMillis: 10000,
                ssl: { rejectUnauthorized: false },
            }
        },
        {
            name: 'Config 3: Explicit no SSL, no encryption',
            config: {
                host: '103.224.247.22',
                port: 5432,
                database: 'postgres',
                user: 'postgres',
                password: 'JaiGanesh2025',
                connectionTimeoutMillis: 10000,
                ssl: false,
                options: '-c ssl=off'
            }
        },
    ];

    log('='.repeat(70));
    log('PostgreSQL Connection Diagnostics');
    log('='.repeat(70));
    log('');

    for (const { name, config } of configs) {
        log(`Testing: ${name}`);
        log('-'.repeat(70));

        const client = new Client(config);

        try {
            log('Attempting connection...');
            await client.connect();
            log('✅ SUCCESS! Connected to PostgreSQL');

            // Get version
            const result = await client.query('SELECT version()');
            log('PostgreSQL Version: ' + result.rows[0].version.substring(0, 80));

            // List databases
            const dbResult = await client.query(
                "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname"
            );
            log('Databases found: ' + dbResult.rows.length);
            dbResult.rows.forEach(row => log('  - ' + row.datname));

            await client.end();
            log('');
            log('🎉 THIS CONFIGURATION WORKS!');
            log('='.repeat(70));

            fs.writeFileSync(logFile, logOutput);
            process.exit(0);

        } catch (error) {
            log(`❌ Failed: ${error.message}`);
            log(`   Code: ${error.code || 'N/A'}`);
            log(`   Severity: ${error.severity || 'N/A'}`);

            if (error.code === 'ECONNRESET') {
                log('   → Connection was reset by server');
                log('   → This usually means pg_hba.conf rejected the connection');
            } else if (error.code === 'ECONNREFUSED') {
                log('   → Connection refused - server not listening');
            } else if (error.code === '28000') {
                log('   → Authentication configuration issue (pg_hba.conf)');
            } else if (error.code === '28P01') {
                log('   → Invalid password');
            }

            log('');

            try {
                await client.end();
            } catch (e) {
                // Ignore
            }
        }
    }

    log('='.repeat(70));
    log('❌ ALL CONFIGURATIONS FAILED');
    log('='.repeat(70));
    log('');
    log('Server-side configuration is still required.');
    log('Please check POSTGRES_SERVER_CONFIG.md for instructions.');

    fs.writeFileSync(logFile, logOutput);
    process.exit(1);
}

testVariousConfigs();
