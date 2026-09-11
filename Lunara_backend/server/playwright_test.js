const { chromium } = require('playwright');
const http = require('http');

async function testBackendUnder5UsersConcurrency() {
    console.log('\n======================================================');
    console.log(' STEP 1: TEST BACKEND APIS UNDER 5 CONCURRENT USERS');
    console.log('======================================================\n');

    const endpoints = [
        { name: 'Health Check', path: '/health' },
        { name: 'Venues List', path: '/api/venues' },
        { name: 'Customers (Invite List)', path: '/api/mobile/user/customers?limit=50&allCities=true' },
        { name: 'Party Plans Feed', path: '/api/mobile/party-plans' },
        { name: 'Active Ads (Party)', path: '/api/ads/active?type=Party' },
        { name: 'Cities List', path: '/api/mobile/cities' },
    ];

    for (const ep of endpoints) {
        process.stdout.write(`Benchmarking ${ep.name.padEnd(25)} (5 concurrent requests)... `);
        const reqStart = Date.now();

        const promises = [1, 2, 3, 4, 5].map(() => {
            return new Promise((resolve) => {
                const s = Date.now();
                http.get(`http://localhost:9076${ep.path}`, (res) => {
                    let data = '';
                    res.on('data', c => data += c);
                    res.on('end', () => {
                        resolve({ status: res.statusCode, duration: Date.now() - s, sizeKb: (Buffer.byteLength(data) / 1024).toFixed(1) });
                    });
                }).on('error', (e) => resolve({ status: 'ERR', duration: Date.now() - s, error: e.message }));
            });
        });

        const results = await Promise.all(promises);
        const durations = results.map(r => r.duration);
        const avg = (durations.reduce((a, b) => a + b, 0) / durations.length).toFixed(1);
        const min = Math.min(...durations);
        const max = Math.max(...durations);
        const total = Date.now() - reqStart;

        console.log(`[Avg: ${avg}ms | Min: ${min}ms | Max: ${max}ms | Total Batch: ${total}ms | Size: ${results[0]?.sizeKb} KB]`);
    }
}

async function testFrontendBrowserWithPlaywright() {
    console.log('\n======================================================');
    console.log(' STEP 2: TEST FRONTEND WEB APP CONCURRENCY (PLAYWRIGHT)');
    console.log('======================================================\n');

    const browser = await chromium.launch({ headless: true });
    console.log('Launched Chromium instance...');

    const userCount = 5;
    const contexts = [];

    console.log(`Spinning up ${userCount} isolated browser sessions concurrently...`);

    const startSessionTime = Date.now();

    const userSessions = [1, 2, 3, 4, 5].map(async (userIdx) => {
        const context = await browser.newContext();
        contexts.push(context);
        const page = await context.newPage();

        const networkLogs = [];
        page.on('requestfailed', request => {
            networkLogs.push(`[FAILED] ${request.method()} ${request.url()} - ${request.failure()?.errorText}`);
        });

        const navStart = Date.now();
        try {
            // Attempt to load local flutter web if running on port 8080/auto or fallback to direct URL
            const targetUrl = 'http://localhost:9076/api';
            const response = await page.goto(targetUrl, { timeout: 15000 });
            const navDuration = Date.now() - navStart;
            return {
                userIdx,
                status: response?.status() || 'FAILED',
                navDuration,
                networkFailures: networkLogs,
            };
        } catch (e) {
            return {
                userIdx,
                status: 'TIMEOUT',
                navDuration: Date.now() - navStart,
                error: e.message,
                networkFailures: networkLogs,
            };
        }
    });

    const sessionResults = await Promise.all(userSessions);
    const totalBrowserElapsed = Date.now() - startSessionTime;

    console.log('\n================ PLAYWRIGHT RESULTS ================');
    console.log(`Total time for 5 browser sessions: ${totalBrowserElapsed}ms`);
    sessionResults.forEach(res => {
        console.log(`User ${res.userIdx}: Status: ${res.status} | Time: ${res.navDuration}ms ${res.error ? `| Error: ${res.error}` : ''}`);
    });

    await browser.close();
    console.log('\nAll browser sessions closed.');
}

async function main() {
    await testBackendUnder5UsersConcurrency();
    await testFrontendBrowserWithPlaywright();
}

main().catch(console.error);
