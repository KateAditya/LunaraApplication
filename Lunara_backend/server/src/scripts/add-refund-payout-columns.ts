import dotenv from 'dotenv';
import sequelize from '../config/database';

dotenv.config();

async function run(): Promise<void> {
    console.log('Connecting to database...');
    await sequelize.authenticate();
    console.log('Database connection authenticated.');

    const queries = [
        // Bookings table
        `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS refund_method VARCHAR(50) DEFAULT 'WALLET';`,
        `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS payout_type VARCHAR(50);`,
        `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS upi_id VARCHAR(100);`,
        `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS upi_number VARCHAR(20);`,
        `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS bank_account_number VARCHAR(50);`,
        `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS bank_ifsc VARCHAR(20);`,
        `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS bank_holder_name VARCHAR(100);`,
        `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS refund_amount DECIMAL(10,2) DEFAULT 0;`,
        `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS refund_status VARCHAR(50) DEFAULT 'NONE';`,

        // group_parties table
        `ALTER TABLE "group_parties" ADD COLUMN IF NOT EXISTS refund_method VARCHAR(50) DEFAULT 'WALLET';`,
        `ALTER TABLE "group_parties" ADD COLUMN IF NOT EXISTS payout_type VARCHAR(50);`,
        `ALTER TABLE "group_parties" ADD COLUMN IF NOT EXISTS upi_id VARCHAR(100);`,
        `ALTER TABLE "group_parties" ADD COLUMN IF NOT EXISTS upi_number VARCHAR(20);`,
        `ALTER TABLE "group_parties" ADD COLUMN IF NOT EXISTS bank_account_number VARCHAR(50);`,
        `ALTER TABLE "group_parties" ADD COLUMN IF NOT EXISTS bank_ifsc VARCHAR(20);`,
        `ALTER TABLE "group_parties" ADD COLUMN IF NOT EXISTS bank_holder_name VARCHAR(100);`,
        `ALTER TABLE "group_parties" ADD COLUMN IF NOT EXISTS refund_amount DECIMAL(10,2) DEFAULT 0;`,
        `ALTER TABLE "group_parties" ADD COLUMN IF NOT EXISTS refund_status VARCHAR(50) DEFAULT 'NONE';`,
    ];

    for (const q of queries) {
        try {
            await sequelize.query(q);
            console.log('SUCCESS:', q);
        } catch (e: any) {
            console.error('ERROR on query:', q, e.message);
        }
    }

    // Verify columns exist now
    const [bookingCols]: any = await sequelize.query(`
        SELECT column_name FROM information_schema.columns 
        WHERE table_name = 'bookings' AND column_name IN ('refund_method', 'payout_type', 'upi_id', 'upi_number', 'bank_account_number', 'bank_ifsc', 'bank_holder_name', 'refund_amount', 'refund_status');
    `);
    console.log('Verified bookings columns present:', bookingCols.map((c: any) => c.column_name));

    const [gpCols]: any = await sequelize.query(`
        SELECT column_name FROM information_schema.columns 
        WHERE table_name = 'group_parties' AND column_name IN ('refund_method', 'payout_type', 'upi_id', 'upi_number', 'bank_account_number', 'bank_ifsc', 'bank_holder_name', 'refund_amount', 'refund_status');
    `);
    console.log('Verified group_parties columns present:', gpCols.map((c: any) => c.column_name));

    await sequelize.close();
    console.log('Migration completed successfully.');
    process.exit(0);
}

run().catch((err) => {
    console.error('Migration execution failed:', err);
    process.exit(1);
});
