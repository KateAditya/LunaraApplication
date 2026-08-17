import 'dotenv/config';
import sequelize from '../config/database';
import { logger } from '../config/logger';
import { DataTypes } from 'sequelize';

async function migrate() {
    try {
        await sequelize.authenticate();
        logger.info('Connected to database.');

        const queryInterface = sequelize.getQueryInterface();
        
        const tableDesc: any = await queryInterface.describeTable('bookings');
        
        if (!tableDesc.party_event_id) {
            logger.info('Adding party_event_id column to bookings table...');
            await queryInterface.addColumn('bookings', 'party_event_id', {
                type: DataTypes.UUID,
                allowNull: true,
            });
            logger.info('Successfully added party_event_id column.');
        } else {
            logger.info('party_event_id column already exists.');
        }

        logger.info('Migration complete!');
    } catch (error) {
        logger.error('Migration failed:', error);
    } finally {
        await sequelize.close();
    }
}

migrate();
