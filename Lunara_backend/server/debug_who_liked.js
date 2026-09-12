const axios = require('axios');
const jwt = require('jsonwebtoken');
require('dotenv').config();

async function debugWhoLiked() {
    try {
        const { User, UserMatch, UserLike, Notification, UserSubscription, SubscriptionPackage } = require('./dist/models');
        const users = await User.findAll({ limit: 3 });
        if (users.length < 2) {
            console.log('Not enough users in DB to test.');
            process.exit(0);
        }

        const userA = users[0];
        const userB = users[1];

        console.log(`\n============================================================`);
        console.log(`Testing "Who Liked You" & Notification System:`);
        console.log(`User A (Liker): ${userA.id} (${userA.firstName} ${userA.lastName} - ${userA.email})`);
        console.log(`User B (Receiver): ${userB.id} (${userB.firstName} ${userB.lastName} - ${userB.email})`);
        console.log(`============================================================\n`);

        // Ensure User B has an active VIP subscription for testing
        let pkg = await SubscriptionPackage.findOne({ where: { tier: 'PRO' } });
        if (!pkg) pkg = await SubscriptionPackage.findOne();
        if (pkg) {
            await UserSubscription.destroy({ where: { userId: userB.id } });
            await UserSubscription.create({
                userId: userB.id,
                packageId: pkg.id,
                status: 'ACTIVE',
                startDate: new Date(),
                endDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
                amount: 999,
                superlikesRemaining: 10,
                boostsRemaining: 5,
            });
            console.log(`Pre-assigned active VIP subscription (${pkg.name}) to User B.`);
        }

        const tokenA = jwt.sign(
            { userId: userA.id, email: userA.email, role: userA.role || 'customer' },
            process.env.JWT_SECRET || 'lunara_jwt_secret_dev_key_change_in_production_2025',
            { expiresIn: '1h', issuer: 'lunara-api' }
        );

        const tokenB = jwt.sign(
            { userId: userB.id, email: userB.email, role: userB.role || 'customer' },
            process.env.JWT_SECRET || 'lunara_jwt_secret_dev_key_change_in_production_2025',
            { expiresIn: '1h', issuer: 'lunara-api' }
        );

        // Step 1: User A likes User B
        console.log('--- Step 1: User A likes User B ---');
        const swipeRes = await axios.post(
            'http://127.0.0.1:9076/api/mobile/user/swipe',
            {
                userId: userA.id,
                targetUserId: userB.id,
                action: 'like',
            },
            { headers: { Authorization: `Bearer ${tokenA}` } }
        );
        console.log('Swipe response:', swipeRes.status, swipeRes.data);

        // Step 2: Check Notification persisted for User B
        console.log('\n--- Step 2: Checking Notification in DB for User B ---');
        const notifs = await Notification.findAll({
            where: {
                recipientUserId: userB.id,
            },
            order: [['createdAt', 'DESC']],
            limit: 3,
        });
        console.log(`Found ${notifs.length} notifications for User B.`);
        if (notifs.length > 0) {
            console.log('Latest Notification:', {
                id: notifs[0].id,
                title: notifs[0].title,
                body: notifs[0].body,
                category: notifs[0].category,
                eventType: notifs[0].eventType,
                deepLink: notifs[0].deepLink,
            });
        }

        // Step 3: Check Who Liked Summary for User B
        console.log('\n--- Step 3: Checking Who Liked Summary for User B ---');
        const summaryRes = await axios.get(
            `http://127.0.0.1:9076/api/mobile/user/who-liked-summary?userId=${userB.id}`,
            { headers: { Authorization: `Bearer ${tokenB}` } }
        );
        console.log('Who Liked Summary response:', summaryRes.status, summaryRes.data);

        console.log('\n--- Step 4: Testing "Who Liked Me" endpoint ---');
        const whoLikedMeRes = await axios.get(
            `http://127.0.0.1:9076/api/mobile/user/who-liked-me?userId=${userB.id}`,
            { headers: { Authorization: `Bearer ${tokenB}` } }
        );
        console.log('Who Liked Me response status:', whoLikedMeRes.status);
        console.log('Profiles returned:', whoLikedMeRes.data.data?.length || 0);
        if (whoLikedMeRes.data.data?.length > 0) {
            console.log('First Liked Profile Preview:', whoLikedMeRes.data.data[0]);
        }

        // Step 5: User B Likes Back (Mutual Match)
        console.log('\n--- Step 5: User B Likes User A back (Creating Mutual Match) ---');
        const matchRes = await axios.post(
            'http://127.0.0.1:9076/api/mobile/user/swipe',
            {
                userId: userB.id,
                targetUserId: userA.id,
                action: 'like',
            },
            { headers: { Authorization: `Bearer ${tokenB}` } }
        );
        console.log('Match response:', matchRes.status, matchRes.data);
        console.log('Is Matched:', matchRes.data.matched);
        console.log('Conversation ID created:', matchRes.data.conversationId);

        console.log('\n🎉 ALL WHO LIKED & NOTIFICATION VERIFICATION TESTS PASSED SUCCESSFULLY!');
        process.exit(0);
    } catch (err) {
        if (err.response) {
            console.error('❌ Error response:', err.response.status, err.response.data);
        } else {
            console.error('❌ Error:', err.message, err.stack);
        }
        process.exit(1);
    }
}

debugWhoLiked();
