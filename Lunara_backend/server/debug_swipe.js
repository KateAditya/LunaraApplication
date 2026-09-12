const axios = require('axios');
const jwt = require('jsonwebtoken');
require('dotenv').config();

async function debugSwipe() {
    try {
        const { User } = require('./dist/models');
        const users = await User.findAll({ limit: 2 });
        if (users.length < 2) {
            console.log('Not enough users in DB to test swipe.');
            process.exit(0);
        }

        const user1 = users[0];
        const user2 = users[1];

        console.log(`Testing swipe: User1 (${user1.id} - ${user1.email}) swiping on User2 (${user2.id} - ${user2.email})`);

        const token = jwt.sign(
            { userId: user1.id, email: user1.email, role: user1.role || 'customer' },
            process.env.JWT_SECRET || 'lunara_jwt_secret_dev_key_change_in_production_2025',
            { expiresIn: '1h', issuer: 'lunara-api' }
        );

        const res = await axios.post(
            'http://127.0.0.1:9076/api/mobile/user/swipe',
            {
                userId: user1.id,
                targetUserId: user2.id,
                action: 'nope',
            },
            {
                headers: {
                    Authorization: `Bearer ${token}`,
                }
            }
        );

        console.log('✅ Swipe Success! Status:', res.status, res.data);
        process.exit(0);
    } catch (err) {
        if (err.response) {
            console.error('❌ Swipe Failed with status:', err.response.status, err.response.data);
        } else {
            console.error('❌ Swipe Error:', err.message, err.stack);
        }
        process.exit(1);
    }
}

debugSwipe();
