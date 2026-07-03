import sequelize from '../config/database';

async function migrate() {
    try {
        console.log('Running migration to add is_online and last_active_at...');
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS is_online BOOLEAN DEFAULT FALSE;`);
        await sequelize.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMP;`);
        console.log('Migration completed successfully!');
    } catch (err) {
        console.error('Migration failed:', err);
    } finally {
        await sequelize.close();
        process.exit(0);
    }
}

migrate();
