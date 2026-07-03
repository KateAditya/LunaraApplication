import dotenv from 'dotenv';
import sequelize from '../config/database';
import { logger } from '../config/logger';

// Import all models to register them
import '../models/index';

dotenv.config();

const reinitializeDatabase = async () => {
    try {
        console.log('='.repeat(70));
        console.log('Database Reinitialization Script');
        console.log('='.repeat(70));
        console.log('');

        console.log('Step 1: Connecting to database...');
        await sequelize.authenticate();
        console.log('✅ Database connected');
        console.log('');

        console.log('Step 2: Dropping all tables...');
        await sequelize.drop({ cascade: true });
        console.log('✅ All existing tables dropped');
        console.log('');

        console.log('Step 3: Synchronizing models with database...');
        await sequelize.sync({ force: true });
        console.log('✅ Database schema created successfully');
        console.log('');

        console.log('Step 4: Database reinitialization complete!');
        console.log('');
        console.log('Summary:');
        console.log('- All tables have been dropped');
        console.log('- New tables created with correct schema');
        console.log('- Database is ready for use');
        console.log('');
        console.log('='.repeat(70));

        await sequelize.close();
        process.exit(0);
    } catch (error) {
        console.error('❌ Error during database reinitialization:');
        console.error(error);
        logger.error('Database reinitialization failed:', error);
        process.exit(1);
    }
};

// Run the script
reinitializeDatabase();
