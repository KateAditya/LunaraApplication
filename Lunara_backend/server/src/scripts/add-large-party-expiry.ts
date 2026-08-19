import 'dotenv/config';
import sequelize from '../config/database';
import { logger } from '../config/logger';
import { DataTypes } from 'sequelize';

async function migrate() {
    try {
        await sequelize.authenticate();
        logger.info('Connected to database.');

        const queryInterface = sequelize.getQueryInterface();

        // ── bookings.expires_at ──────────────────────────────────────────────
        const bookingsDesc: any = await queryInterface.describeTable('bookings');
        if (!bookingsDesc.expires_at) {
            logger.info('Adding expires_at column to bookings table...');
            await queryInterface.addColumn('bookings', 'expires_at', {
                type: DataTypes.DATE,
                allowNull: true,
            });
            logger.info('Successfully added bookings.expires_at column.');
        } else {
            logger.info('bookings.expires_at column already exists.');
        }

        // ── group_parties.expires_at ─────────────────────────────────────────
        const groupPartiesDesc: any = await queryInterface.describeTable('group_parties');
        if (!groupPartiesDesc.expires_at) {
            logger.info('Adding expires_at column to group_parties table...');
            await queryInterface.addColumn('group_parties', 'expires_at', {
                type: DataTypes.DATE,
                allowNull: true,
            });
            logger.info('Successfully added group_parties.expires_at column.');
        } else {
            logger.info('group_parties.expires_at column already exists.');
        }

        // ── enum_bookings_admin_approval_status += 'expired' ─────────────────
        try {
            await sequelize.query(`ALTER TYPE enum_bookings_admin_approval_status ADD VALUE IF NOT EXISTS 'expired';`);
            logger.info(`Added 'expired' to enum_bookings_admin_approval_status.`);
        } catch (enumErr: any) {
            logger.warn('Failed to alter enum_bookings_admin_approval_status: ' + enumErr.message);
        }

        // ── enum_group_parties_status += 'expired' ────────────────────────────
        try {
            await sequelize.query(`ALTER TYPE enum_group_parties_status ADD VALUE IF NOT EXISTS 'expired';`);
            logger.info(`Added 'expired' to enum_group_parties_status.`);
        } catch (enumErr: any) {
            logger.warn('Failed to alter enum_group_parties_status: ' + enumErr.message);
        }

        // ── Indexes for the cron sweep ─────────────────────────────────────
        await sequelize.query(`CREATE INDEX IF NOT EXISTS bookings_expires_at_idx ON bookings (expires_at);`);
        await sequelize.query(`CREATE INDEX IF NOT EXISTS group_parties_expires_at_idx ON group_parties (expires_at);`);
        logger.info('Ensured expires_at indexes exist.');

        logger.info('Migration complete!');
    } catch (error) {
        logger.error('Migration failed:', error);
    } finally {
        await sequelize.close();
    }
}

migrate();
