/**
 * migrate-compliance.js
 * ---------------------
 * Adds venue compliance columns and creates the venue_compliance_logs table.
 * Run ONCE against your PostgreSQL database:
 *
 *   node migrate-compliance.js
 *
 * It is idempotent — safe to run multiple times (uses IF NOT EXISTS / IF NOT EXISTS column checks).
 */

require('dotenv').config();
const { Sequelize } = require('sequelize');

const sequelize = new Sequelize(
  process.env.DB_NAME,
  process.env.DB_USER,
  process.env.DB_PASSWORD,
  {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432'),
    dialect: 'postgres',
    logging: console.log,
  }
);

async function migrate() {
  try {
    await sequelize.authenticate();
    console.log('✅ Connected to database');

    // ── 1. Widen status column to VARCHAR(50) so new pipeline statuses fit ───
    await sequelize.query(`
      ALTER TABLE venues
        ALTER COLUMN status TYPE VARCHAR(50);
    `).catch(() => console.log('ℹ️  status column already wide enough — skipping'));

    // ── 2. Add compliance tracking columns to venues ─────────────────────────
    const addColSQL = (col, definition) => `
      DO $$ BEGIN
        ALTER TABLE venues ADD COLUMN ${col} ${definition};
      EXCEPTION WHEN duplicate_column THEN
        RAISE NOTICE 'column ${col} already exists, skipping';
      END $$;
    `;

    await sequelize.query(addColSQL('terms_accepted_at', 'TIMESTAMP'));
    console.log('✅ venues.terms_accepted_at');

    await sequelize.query(addColSQL('confirmation_token', 'VARCHAR(128) UNIQUE'));
    console.log('✅ venues.confirmation_token');

    await sequelize.query(addColSQL('confirmation_token_expires_at', 'TIMESTAMP'));
    console.log('✅ venues.confirmation_token_expires_at');

    await sequelize.query(addColSQL('owner_email_sent_at', 'TIMESTAMP'));
    console.log('✅ venues.owner_email_sent_at');

    await sequelize.query(addColSQL('owner_confirmed_at', 'TIMESTAMP'));
    console.log('✅ venues.owner_confirmed_at');

    // ── 3. Create venue_compliance_logs table ────────────────────────────────
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS venue_compliance_logs (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        venue_id UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
        event_type VARCHAR(50) NOT NULL,
        actor_email VARCHAR(255),
        ip_address VARCHAR(45),
        metadata JSONB,
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);
    console.log('✅ venue_compliance_logs table ready');

    await sequelize.query(`
      CREATE INDEX IF NOT EXISTS idx_vcl_venue_id ON venue_compliance_logs(venue_id);
      CREATE INDEX IF NOT EXISTS idx_vcl_event_type ON venue_compliance_logs(event_type);
    `);
    console.log('✅ Indexes created');

    console.log('\n🎉 Migration completed successfully!');
    await sequelize.close();
    process.exit(0);
  } catch (err) {
    console.error('❌ Migration failed:', err.message || err);
    await sequelize.close();
    process.exit(1);
  }
}

migrate();
