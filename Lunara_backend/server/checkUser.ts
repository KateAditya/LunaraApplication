import User from './src/models/User';
import sequelize from './src/config/database';

async function checkUser() {
    try {
        await sequelize.authenticate();
        const user = await User.findOne({ where: { email: 'admin@lunara.com' } });
        if (user) {
            console.log('User found:', JSON.stringify(user.toJSON(), null, 2));
        } else {
            console.log('User not found: admin@lunara.com');
        }
    } catch (error) {
        console.error('Error:', error);
    } finally {
        await sequelize.close();
    }
}

checkUser();
