import sequelize from './src/config/database';
import { User, UserProfile, UserPreference } from './src/models';

async function testQueryWithData() {
    try {
        console.log('Finding a user...');
        const user = await User.findOne();
        if (!user) {
            console.log('No user found in DB!');
            return;
        }

        console.log(`Temporarily autoblocking user ${user.email} (ID: ${user.id})...`);
        const originalStatus = user.isAutoblocked;
        await user.update({ isAutoblocked: true, autoblockedReason: 'Test autoblock' });

        console.log('Running test query for autoblocked users...');
        const { count, rows } = await User.findAndCountAll({
            where: { isAutoblocked: true },
            attributes: { exclude: ['passwordHash', 'mfaSecret'] },
            include: [
                { model: UserProfile, as: 'profile' },
                { model: UserPreference, as: 'preferences' }
            ],
            limit: 10,
            offset: 0,
            order: [['createdAt', 'DESC']],
        });

        console.log('Query succeeded!');
        console.log('Count:', count);
        console.log('Rows:', rows.map(r => ({ id: r.id, email: r.email, profile: (r as any).profile, preferences: (r as any).preferences })));

        console.log('Restoring user...');
        await user.update({ isAutoblocked: originalStatus, autoblockedReason: null });
        console.log('Restored successfully!');
    } catch (error: any) {
        console.error('Query failed with error:');
        console.error(error);
    } finally {
        await sequelize.close();
    }
}

testQueryWithData();
