const Redis = require('ioredis');
require('dotenv').config();

async function test() {
    const host = process.env.REDIS_HOST;
    const port = parseInt(process.env.REDIS_PORT || '10000', 10);
    const password = process.env.REDIS_PASSWORD;

    console.log(`Connecting to ${host}:${port} with Redis standalone...`);
    const redis = new Redis(port, host, {
        password,
        tls: {
            servername: host,
            rejectUnauthorized: false
        },
        connectTimeout: 5000,
        maxRetriesPerRequest: 1
    });

    redis.on('connect', () => console.log('✅ Standalone connected!'));
    redis.on('ready', async () => {
        console.log('🚀 Standalone ready!');
        await redis.set('lunara:standalone_test', 'Working perfectly', 'EX', 60);
        const res = await redis.get('lunara:standalone_test');
        console.log('⚡ Standalone Result:', res);
        await redis.quit();
        process.exit(0);
    });

    redis.on('error', (err) => {
        console.error('❌ Error:', err.message);
    });
}

test();
