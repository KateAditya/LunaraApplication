const Redis = require('ioredis');
require('dotenv').config();

async function testStandalone() {
    const host = process.env.REDIS_HOST;
    const port = parseInt(process.env.REDIS_PORT || '10000', 10);
    const password = process.env.REDIS_PASSWORD;

    console.log(`Trying standalone TLS connection to ${host}:${port}...`);
    
    const client = new Redis({
        host: host,
        port: port,
        password: password,
        tls: {
            servername: host,
            rejectUnauthorized: false
        },
        connectTimeout: 5000,
        maxRetriesPerRequest: 1,
    });

    client.on('connect', () => console.log('✅ Standalone Connected!'));
    client.on('ready', async () => {
        console.log('🚀 Standalone Redis is ready!');
        const start = Date.now();
        await client.set('lunara:test_key', 'Hello Azure Redis in Central India!', 'EX', 60);
        const val = await client.get('lunara:test_key');
        const latency = Date.now() - start;
        console.log(`⚡ Read/Write Success! Value: "${val}" in ${latency}ms`);
        await client.quit();
        process.exit(0);
    });

    client.on('error', (err) => {
        console.error('❌ Standalone Error:', err.message);
    });

    setTimeout(() => {
        console.log('⚠️ Standalone timeout, will test cluster with natMap next...');
        client.disconnect();
        testClusterNat();
    }, 6000);
}

async function testClusterNat() {
    const host = process.env.REDIS_HOST;
    const port = parseInt(process.env.REDIS_PORT || '10000', 10);
    const password = process.env.REDIS_PASSWORD;

    console.log(`Trying Cluster with TLS & NatMap to ${host}:${port}...`);

    const cluster = new Redis.Cluster(
        [{ host, port }],
        {
            dnsLookup: (hostname, callback) => callback(null, hostname),
            redisOptions: {
                password: password,
                tls: {
                    servername: host,
                    rejectUnauthorized: false,
                },
                connectTimeout: 5000,
            },
            natMap: {
                [`${host}:${port}`]: { host, port }
            }
        }
    );

    cluster.on('connect', () => console.log('✅ Cluster Connected!'));
    cluster.on('ready', async () => {
        console.log('🚀 Cluster Redis is ready!');
        const start = Date.now();
        await cluster.set('lunara:test_key', 'Hello Azure Redis in Central India!', 'EX', 60);
        const val = await cluster.get('lunara:test_key');
        const latency = Date.now() - start;
        console.log(`⚡ Read/Write Success! Value: "${val}" in ${latency}ms`);
        await cluster.quit();
        process.exit(0);
    });

    cluster.on('error', (err) => {
        console.error('❌ Cluster Error:', err.message);
    });
}

testStandalone();
