/**
 * Migration: Add food_menu, bar_menu, beverage_menu to venue_image_type PostgreSQL ENUM
 *
 * Run with: node migrate-menu-types.js
 *
 * This script is idempotent — it safely skips values that already exist in the enum.
 */

require('dotenv').config();
const { Client } = require('pg');

async function migrate() {
    const client = new Client({
        host: process.env.DB_HOST || 'localhost',
        port: parseInt(process.env.DB_PORT || '5432'),
        database: process.env.DB_NAME,
        user: process.env.DB_USER,
        password: process.env.DB_PASSWORD,
        ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
    });

    const newValues = ['food_menu', 'bar_menu', 'beverage_menu'];

    try {
        await client.connect();
        console.log('✅ Connected to database');

        // Get existing enum values
        const { rows } = await client.query(`
            SELECT enumlabel
            FROM pg_enum e
            JOIN pg_type t ON e.enumtypid = t.oid
            WHERE t.typname = 'enum_venue_images_image_type'
        `);
        const existing = new Set(rows.map(r => r.enumlabel));
        console.log('📋 Existing enum values:', [...existing]);

        for (const value of newValues) {
            if (existing.has(value)) {
                console.log(`⏭  Skipping "${value}" — already exists`);
                continue;
            }
            await client.query(
                `ALTER TYPE enum_venue_images_image_type ADD VALUE '${value}'`
            );
            console.log(`✅ Added enum value: ${value}`);
        }

        console.log('\n🎉 Migration complete!');
        console.log('   New enum values are: food_menu, bar_menu, beverage_menu');
    } catch (err) {
        console.error('❌ Migration failed:', err.message);
        process.exit(1);
    } finally {
        await client.end();
    }
}

migrate();
