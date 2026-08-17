import 'dotenv/config';
import sequelize from '../config/database';
import { logger } from '../config/logger';
import { DataTypes } from 'sequelize';

async function migrate() {
    try {
        await sequelize.authenticate();
        logger.info('Connected to DB');

        const queryInterface = sequelize.getQueryInterface();

        const tableDesc = await queryInterface.describeTable('ads');

        if (!tableDesc['event_date']) {
            await queryInterface.addColumn('ads', 'event_date', {
                type: DataTypes.DATE,
                allowNull: true,
            });
            logger.info('Added event_date');
        }

        if (!tableDesc['entry_price']) {
            await queryInterface.addColumn('ads', 'entry_price', {
                type: DataTypes.INTEGER,
                allowNull: true,
            });
            logger.info('Added entry_price');
        }

        if (!tableDesc['seat_limit']) {
            await queryInterface.addColumn('ads', 'seat_limit', {
                type: DataTypes.INTEGER,
                allowNull: true,
            });
            logger.info('Added seat_limit');
        }

        if (!tableDesc['is_unlimited']) {
            await queryInterface.addColumn('ads', 'is_unlimited', {
                type: DataTypes.BOOLEAN,
                allowNull: false,
                defaultValue: false,
            });
            logger.info('Added is_unlimited');
        }

        if (!tableDesc['filled_seats']) {
            await queryInterface.addColumn('ads', 'filled_seats', {
                type: DataTypes.INTEGER,
                allowNull: false,
                defaultValue: 0,
            });
            logger.info('Added filled_seats');
        }

        // Apply defaults to historical party events (entryPrice = 0)
        await queryInterface.sequelize.query(`
            UPDATE ads 
            SET entry_price = 0 
            WHERE type = 'Party' AND entry_price IS NULL
        `);
        logger.info('Applied default entry_price = 0 for historical Party events');

        logger.info('Migration complete!');
    } catch (error) {
        logger.error('Migration failed:', error);
    } finally {
        await sequelize.close();
    }
}

migrate();
