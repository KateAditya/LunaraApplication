/**
 * Adds a nullable `start_time` column to `group_parties`.
 *
 * GroupParty.partyDate is DATEONLY — the actual party start time selected by
 * the user in the booking form was silently discarded at creation, so
 * tickets always showed midnight ("12:00 AM Onwards") instead of the real
 * time. This column lets new bookings persist the real time; existing rows
 * remain NULL (their ticket screens fall back to the existing default).
 *
 * SAFE: additive only — `ADD COLUMN IF NOT EXISTS`, never touches existing data.
 *
 * Run with: npx ts-node src/scripts/add-group-party-start-time.ts
 */

import dotenv from 'dotenv';
import sequelize from '../config/database';

dotenv.config();

async function run(): Promise<void> {
    await sequelize.authenticate();
    await sequelize.query(`ALTER TABLE "group_parties" ADD COLUMN IF NOT EXISTS start_time VARCHAR(5)`);
    console.log('Added group_parties.start_time (or it already existed).');
    await sequelize.close();
    process.exit(0);
}

run().catch((error) => {
    console.error('Failed to add group_parties.start_time:', error);
    process.exit(1);
});
