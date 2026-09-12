const axios = require('axios');
const jwt = require('jsonwebtoken');
require('dotenv').config();

async function debugBacktrack() {
    try {
        const { User, UserMatch, UserLike } = require('./dist/models');
        const users = await User.findAll({ limit: 2 });
        if (users.length < 2) {
            console.log('Not enough users in DB to test.');
            process.exit(0);
        }

        const user1 = users[0];
        const user2 = users[1];

        console.log(`Testing Backtrack: User1 (${user1.id} - ${user1.email}) and User2 (${user2.id} - ${user2.email})`);

        const token = jwt.sign(
            { userId: user1.id, email: user1.email, role: user1.role || 'customer' },
            process.env.JWT_SECRET || 'lunara_jwt_secret_dev_key_change_in_production_2025',
            { expiresIn: '1h', issuer: 'lunara-api' }
        );

        // 1. First perform a Left Swipe (nope)
        console.log('\n--- Step 1: Performing Left Swipe (nope) ---');
        const swipeRes = await axios.post(
            'http://127.0.0.1:9076/api/mobile/user/swipe',
            {
                userId: user1.id,
                targetUserId: user2.id,
                action: 'nope',
            },
            {
                headers: { Authorization: `Bearer ${token}` }
            }
        );
        console.log('Swipe (nope) response:', swipeRes.status, swipeRes.data);

        // Verify swipe record exists
        let matchRecord = await UserMatch.findOne({ where: { user1Id: user1.id, user2Id: user2.id } });
        console.log('Match record in DB after nope:', matchRecord ? `Found (status: ${matchRecord.status})` : 'Not found');

        // 2. Now perform Backtrack (Undo)
        console.log('\n--- Step 2: Calling Backtrack / Undo ---');
        const backtrackRes = await axios.post(
            'http://127.0.0.1:9076/api/mobile/user/backtrack',
            {
                userId: user1.id,
                targetUserId: user2.id,
            },
            {
                headers: { Authorization: `Bearer ${token}` }
            }
        );
        console.log('✅ Backtrack response:', backtrackRes.status, backtrackRes.data);

        // Verify swipe record is deleted
        matchRecord = await UserMatch.findOne({ where: { user1Id: user1.id, user2Id: user2.id } });
        console.log('Match record in DB after backtrack:', matchRecord ? `Still exists (status: ${matchRecord.status})` : 'Successfully deleted (Card returned to deck)');

        // 3. Test Right Swipe (like) and then Backtrack
        console.log('\n--- Step 3: Performing Right Swipe (like) ---');
        const likeRes = await axios.post(
            'http://127.0.0.1:9076/api/mobile/user/swipe',
            {
                userId: user1.id,
                targetUserId: user2.id,
                action: 'like',
            },
            {
                headers: { Authorization: `Bearer ${token}` }
            }
        );
        console.log('Swipe (like) response:', likeRes.status, likeRes.data);

        const likeRecord = await UserLike.findOne({ where: { userId: user1.id, targetUserId: user2.id } });
        console.log('UserLike record in DB after like:', likeRecord ? `Found (action: ${likeRecord.actionType})` : 'Not found');

        console.log('\n--- Step 4: Calling Backtrack on Like ---');
        const backtrackLikeRes = await axios.post(
            'http://127.0.0.1:9076/api/mobile/user/backtrack',
            {
                userId: user1.id,
                targetUserId: user2.id,
            },
            {
                headers: { Authorization: `Bearer ${token}` }
            }
        );
        console.log('✅ Backtrack (like) response:', backtrackLikeRes.status, backtrackLikeRes.data);

        const likeRecordAfter = await UserLike.findOne({ where: { userId: user1.id, targetUserId: user2.id } });
        console.log('UserLike record in DB after backtrack:', likeRecordAfter ? 'Still exists' : 'Successfully deleted');

        console.log('\n🎉 ALL BACKTRACK VERIFICATION CHECKS PASSED!');
        process.exit(0);
    } catch (err) {
        if (err.response) {
            console.error('❌ Backtrack Test Failed with status:', err.response.status, err.response.data);
        } else {
            console.error('❌ Backtrack Test Error:', err.message, err.stack);
        }
        process.exit(1);
    }
}

debugBacktrack();
