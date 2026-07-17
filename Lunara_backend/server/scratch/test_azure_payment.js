const https = require('https');
const jwt = require('jsonwebtoken');

const USER_ID = '77fae2bc-c85a-4d0a-925d-0ab102d7aec0';
const JWT_SECRET = 'lunara_jwt_secret_dev_key_change_in_production_2025';

const token = jwt.sign({ id: USER_ID }, JWT_SECRET, { expiresIn: '100y' });

const options = {
    hostname: 'lunara-api-server-a8gfdvg0hjdec6gx.centralindia-01.azurewebsites.net',
    path: '/api/mobile/bookings/78cc2e0b-5694-4029-ab23-0c0504cc4656/initiate-large-party-payment',
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
    }
};

const req = https.request(options, (res) => {
    console.log('Status Code:', res.statusCode);
    let data = '';
    res.on('data', (chunk) => {
        data += chunk;
    });
    res.on('end', () => {
        console.log('Response Body:', data);
    });
});

req.on('error', (error) => {
    console.error('Error:', error);
});

req.end();
