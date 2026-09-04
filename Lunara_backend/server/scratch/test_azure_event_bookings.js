const https = require('https');

function request(options, body = null) {
    return new Promise((resolve, reject) => {
        const req = https.request(options, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => {
                try {
                    resolve({ status: res.statusCode, data: JSON.parse(data) });
                } catch (_) {
                    resolve({ status: res.statusCode, raw: data });
                }
            });
        });
        req.on('error', reject);
        if (body) req.write(JSON.stringify(body));
        req.end();
    });
}

async function run() {
    // 1. Admin login
    const loginRes = await request({
        hostname: 'lunara-api-v2-b2cnahe5bzcxfdds.centralindia-01.azurewebsites.net',
        path: '/api/admin/login',
        method: 'POST',
        headers: { 'Content-Type': 'application/json' }
    }, { email: 'admin@lunara.com', password: 'JaiGanesh@2026' });

    console.log('Login Status:', loginRes.status);
    const token = loginRes.data?.data?.accessToken || loginRes.data?.accessToken;
    if (!token) {
        console.error('No token received:', loginRes);
        return;
    }

    const authHeaders = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
    };

    const eventsRes = await request({
        hostname: 'lunara-api-v2-b2cnahe5bzcxfdds.centralindia-01.azurewebsites.net',
        path: '/api/admin/event-bookings/events',
        method: 'GET',
        headers: authHeaders
    });
    console.log('\n--- Events Response ---', eventsRes.status, JSON.stringify(eventsRes.data, null, 2));

    const summaryRes = await request({
        hostname: 'lunara-api-v2-b2cnahe5bzcxfdds.centralindia-01.azurewebsites.net',
        path: '/api/admin/event-bookings/all/summary',
        method: 'GET',
        headers: authHeaders
    });
    console.log('\n--- Summary Response ---', summaryRes.status, JSON.stringify(summaryRes.data, null, 2));

    const groupPartiesRes = await request({
        hostname: 'lunara-api-v2-b2cnahe5bzcxfdds.centralindia-01.azurewebsites.net',
        path: '/api/admin/bookings/group-party-cancellations?page=1&limit=20',
        method: 'GET',
        headers: authHeaders
    });
    console.log('\n--- Group Party Cancellations Response ---', groupPartiesRes.status, JSON.stringify(groupPartiesRes.data, null, 2));

    const largePartiesRes = await request({
        hostname: 'lunara-api-v2-b2cnahe5bzcxfdds.centralindia-01.azurewebsites.net',
        path: '/api/admin/bookings/large-party-cancellations?page=1&limit=20',
        method: 'GET',
        headers: authHeaders
    });
    console.log('\n--- Large Party Cancellations Response ---', largePartiesRes.status, JSON.stringify(largePartiesRes.data, null, 2));

    const strangerMeetRes = await request({
        hostname: 'lunara-api-v2-b2cnahe5bzcxfdds.centralindia-01.azurewebsites.net',
        path: '/api/admin/strangers-meet/cancellations?page=1&limit=20',
        method: 'GET',
        headers: authHeaders
    });
    console.log('\n--- Stranger Meet Cancellations Response ---', strangerMeetRes.status, JSON.stringify(strangerMeetRes.data, null, 2));
}

run();



