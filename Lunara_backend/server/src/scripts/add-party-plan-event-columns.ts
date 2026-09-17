import 'dotenv/config';
import sequelize from '../config/database';
import { logger } from '../config/logger';
import { DataTypes } from 'sequelize';

/**
 * Links a party plan back to the Upcoming Night event it was posted from.
 *
 * `party_event_id` is what lets the server resolve the event's own entry price
 * (never trusting the client for it) and hold seats against the event's
 * capacity. `event_seats_reserved` records how many of those seats this plan is
 * currently holding, so a cancellation or a solo conversion releases exactly
 * what was taken and never double-releases.
 *
 * Both are nullable / defaulted, so every existing party plan is unaffected and
 * keeps its ₹99 commitment-deposit behaviour.
 */
async function migrate() {
    try {
        await sequelize.authenticate();
        logger.info('Connected to database.');

        const queryInterface = sequelize.getQueryInterface();
        const tableDesc: any = await queryInterface.describeTable('party_plans');

        if (!tableDesc.party_event_id) {
            logger.info('Adding party_event_id column to party_plans table...');
            await queryInterface.addColumn('party_plans', 'party_event_id', {
                type: DataTypes.UUID,
                allowNull: true,
            });
            logger.info('Successfully added party_event_id column.');
        } else {
            logger.info('party_event_id column already exists.');
        }

        if (!tableDesc.event_seats_reserved) {
            logger.info('Adding event_seats_reserved column to party_plans table...');
            await queryInterface.addColumn('party_plans', 'event_seats_reserved', {
                type: DataTypes.INTEGER,
                allowNull: false,
                defaultValue: 0,
            });
            logger.info('Successfully added event_seats_reserved column.');
        } else {
            logger.info('event_seats_reserved column already exists.');
        }

        if (!tableDesc.event_no_match_notified_at) {
            logger.info('Adding event_no_match_notified_at column to party_plans table...');
            await queryInterface.addColumn('party_plans', 'event_no_match_notified_at', {
                type: DataTypes.DATE,
                allowNull: true,
            });
            logger.info('Successfully added event_no_match_notified_at column.');
        } else {
            logger.info('event_no_match_notified_at column already exists.');
        }

        // Every lookup of "which plans hold seats for this event" filters on
        // this column, and the 24-hour no-match sweep runs it on a schedule.
        try {
            await queryInterface.addIndex('party_plans', ['party_event_id'], {
                name: 'party_plans_party_event_id_idx',
            });
            logger.info('Added index party_plans_party_event_id_idx.');
        } catch (idxErr: any) {
            logger.info(`Index party_plans_party_event_id_idx not added (likely exists): ${idxErr.message}`);
        }

        logger.info('Migration complete!');
    } catch (error) {
        logger.error('Migration failed:', error);
    } finally {
        await sequelize.close();
    }
}

migrate();
