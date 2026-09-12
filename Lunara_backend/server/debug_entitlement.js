require('dotenv').config();

async function testEntitlement() {
    try {
        const { connectDatabase } = require('./dist/config/database');
        await connectDatabase();

        const { User } = require('./dist/models');
        const user = await User.findOne();
        console.log('Testing with User:', user.id, user.email);

        const { EntitlementService } = require('./dist/services/EntitlementService');
        const result = await EntitlementService.consumeFeatureEntitlement(user.id, 'daily_likes', 1);
        console.log('Result:', result);
        process.exit(0);
    } catch (err) {
        console.error('Fatal Error:', err);
        process.exit(1);
    }
}

testEntitlement();
