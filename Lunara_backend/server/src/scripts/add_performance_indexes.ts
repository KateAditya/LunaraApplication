import sequelize from '../config/database';
import { logger } from '../config/logger';

export async function applyPerformanceIndexes() {
    logger.info('Starting high-performance database indexing...');
    const queryInterface = sequelize.getQueryInterface();

    const indexesToCreate = [
        {
            name: 'idx_party_plan_requests_status_timeout',
            table: 'party_plan_requests',
            fields: ['status', 'payment_timeout_at'],
        },
        {
            name: 'idx_party_plans_status_is_live_datetime',
            table: 'party_plans',
            fields: ['status', 'is_live', 'plan_date_time'],
        },
        {
            name: 'idx_strangers_meet_status_pay_eventdate',
            table: 'strangers_meet_requests',
            fields: ['status', 'payment_status', 'event_date_time'],
        },
        {
            name: 'idx_user_subscriptions_status_enddate',
            table: 'user_subscriptions',
            fields: ['status', 'end_date'],
        },
        {
            name: 'idx_notification_jobs_status_sendat',
            table: 'notification_jobs',
            fields: ['status', 'send_at'],
        },
        {
            name: 'idx_bookings_status_pay_createdat',
            table: 'bookings',
            fields: ['status', 'payment_status', 'created_at'],
        },
        {
            name: 'idx_smart_wallets_user_id',
            table: 'smart_wallets',
            fields: ['user_id'],
        },
        {
            name: 'idx_wallet_transactions_user_createdat',
            table: 'wallet_transactions',
            fields: ['user_id', 'created_at'],
        },
    ];

    for (const idx of indexesToCreate) {
        try {
            await queryInterface.addIndex(idx.table, idx.fields, {
                name: idx.name,
                concurrently: true,
            });
            logger.info(`✅ Successfully created index ${idx.name} on ${idx.table}`);
        } catch (err: any) {
            // Safe fallback if index already exists or table does not yet have the column
            const alreadyExists =
                err.message?.includes('already exists') ||
                err.original?.code === '42P07';  // duplicate_object in PostgreSQL
            if (alreadyExists) {
                logger.info(`ℹ️ Index ${idx.name} on ${idx.table} already exists — skipped.`);
            } else {
                logger.warn(`⚠️ Warning creating index ${idx.name} on ${idx.table}: ${err.message}`);
            }
        }
    }

    logger.info('High-performance database indexing completed successfully.');
}

if (require.main === module) {
    applyPerformanceIndexes()
        .then(() => process.exit(0))
        .catch((err) => {
            logger.error('Failed to apply performance indexes:', err);
            process.exit(1);
        });
}
