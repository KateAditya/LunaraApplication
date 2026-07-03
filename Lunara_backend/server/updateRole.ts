import User from './src/models/User';
import { UserRole } from './src/models/User';
import sequelize from './src/config/database';

async function updateRole() {
    try {
        await sequelize.authenticate();
        const user = await User.findOne({ where: { email: 'admin@lunara.com' } });
        if (user) {
            user.role = UserRole.ADMIN;
            await user.save();
            console.log('User role updated to admin');
        } else {
            console.log('User not found: admin@lunara.com');
        }
    } catch (error) {
        console.error('Error:', error);
    } finally {
        await sequelize.close();
    }
}

updateRole();
