import sequelize from './src/config/database';
import { User, UserRole } from './src/models';

async function findAdmin() {
    try {
        const admin = await User.findOne({ where: { role: UserRole.ADMIN } });
        if (admin) {
            console.log('Found Admin User:');
            console.log('ID:', admin.id);
            console.log('Email:', admin.email);
            console.log('Role:', admin.role);
        } else {
            console.log('No Admin User found in database.');
        }
    } catch (error: any) {
        console.error('Error finding admin:', error.message);
    } finally {
        await sequelize.close();
    }
}

findAdmin();
