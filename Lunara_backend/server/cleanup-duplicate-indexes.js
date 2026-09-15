#!/usr/bin/env node
/**
 * Removes duplicate UNIQUE constraints and duplicate plain indexes.
 *
 * WHY THIS EXISTS
 * ---------------
 * Repeated `sequelize.sync({ alter: true })` runs (see src/initDatabase.ts and
 * src/scripts/seed-cities.ts) re-create a table's UNIQUE constraints on every
 * invocation instead of reusing them, so each run appends another copy:
 * users_email_key, users_email_key1, users_email_key2, ... This accumulated
 * until `users` carried 296 UNIQUE constraints for what should be 2 columns.
 *
 * The cost is on every write, not on reads: an INSERT or UPDATE must maintain
 * every index on the table. With 303 indexes on `users`, a single profile
 * update does ~150x the index work it should, and the redundant index pages
 * evict genuinely useful data from the Postgres buffer cache.
 *
 * `connectDatabase()` only calls `authenticate()`, so a normal server boot does
 * NOT regenerate these. They are historical damage and will stay gone once
 * dropped — provided nobody runs `sync({ alter: true })` against this database
 * again.
 *
 * WHAT IT KEEPS
 * -------------
 * Exactly one constraint (or index) per distinct column set, preferring the
 * canonical unsuffixed name (`users_email_key` over `users_email_key117`). The
 * uniqueness guarantee on every column set is therefore unchanged: dropping a
 * duplicate of a constraint that still exists cannot allow a duplicate row.
 * Primary keys and foreign keys are never touched.
 *
 * USAGE
 *   node cleanup-duplicate-indexes.js            # dry run, prints the plan
 *   node cleanup-duplicate-indexes.js --apply    # execute
 *
 * Each statement runs on its own connection-level transaction and is reported
 * individually, so an interrupted run can simply be re-run: the script is
 * idempotent and re-reads current state every time.
 */

require('dotenv').config();
const { Client } = require('pg');

const APPLY = process.argv.includes('--apply');

function buildClient() {
    return new Client({
        host: process.env.DB_HOST || 'localhost',
        port: parseInt(process.env.DB_PORT || '5432', 10),
        database: process.env.DB_NAME || 'lunara_db',
        user: process.env.DB_USER || 'postgres',
        password: process.env.DB_PASSWORD || '',
        ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
        statement_timeout: 120000,
    });
}

/**
 * Picks which name to keep from a group of interchangeable duplicates.
 * Prefers a name with no trailing digits (the original Sequelize created), then
 * the shortest, then alphabetical — so the survivor is stable across runs.
 */
function pickSurvivor(names) {
    const sorted = [...names].sort((a, b) => {
        const aSuffixed = /\d+$/.test(a) ? 1 : 0;
        const bSuffixed = /\d+$/.test(b) ? 1 : 0;
        if (aSuffixed !== bSuffixed) return aSuffixed - bSuffixed;
        if (a.length !== b.length) return a.length - b.length;
        return a.localeCompare(b);
    });
    return sorted[0];
}

async function planUniqueConstraintDrops(c) {
    const { rows } = await c.query(`
        SELECT t.relname AS table_name,
               con.conname AS constraint_name,
               pg_get_constraintdef(con.oid) AS def
        FROM pg_constraint con
        JOIN pg_class t ON t.oid = con.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'public' AND con.contype = 'u'
        ORDER BY t.relname, con.conname`);

    const groups = new Map();
    for (const r of rows) {
        const key = `${r.table_name}::${r.def}`;
        (groups.get(key) || groups.set(key, []).get(key)).push(r);
    }

    const drops = [];
    for (const [key, members] of groups) {
        if (members.length < 2) continue;
        const [table] = key.split('::');
        const survivor = pickSurvivor(members.map((m) => m.constraint_name));
        for (const m of members) {
            if (m.constraint_name === survivor) continue;
            drops.push({
                table,
                name: m.constraint_name,
                keep: survivor,
                def: m.def,
                sql: `ALTER TABLE public."${table}" DROP CONSTRAINT "${m.constraint_name}"`,
            });
        }
    }
    return drops;
}

async function planPlainIndexDrops(c) {
    // Plain (non-constraint, non-unique, non-primary) indexes with an identical
    // definition apart from their name.
    const { rows } = await c.query(`
        SELECT t.relname AS table_name,
               ic.relname AS index_name,
               pg_get_indexdef(i.indexrelid) AS def
        FROM pg_index i
        JOIN pg_class ic ON ic.oid = i.indexrelid
        JOIN pg_class t  ON t.oid  = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'public'
          AND NOT i.indisprimary
          AND NOT i.indisunique
          AND NOT EXISTS (SELECT 1 FROM pg_constraint con WHERE con.conindid = i.indexrelid)
        ORDER BY t.relname, ic.relname`);

    const groups = new Map();
    for (const r of rows) {
        const normalised = r.def.replace(/INDEX \S+ ON/, 'INDEX <n> ON');
        const key = `${r.table_name}::${normalised}`;
        (groups.get(key) || groups.set(key, []).get(key)).push(r);
    }

    const drops = [];
    for (const [key, members] of groups) {
        if (members.length < 2) continue;
        const [table] = key.split('::');
        const survivor = pickSurvivor(members.map((m) => m.index_name));
        for (const m of members) {
            if (m.index_name === survivor) continue;
            drops.push({
                table,
                name: m.index_name,
                keep: survivor,
                def: m.def,
                // CONCURRENTLY never blocks reads or writes on a live table.
                sql: `DROP INDEX CONCURRENTLY IF EXISTS public."${m.index_name}"`,
            });
        }
    }
    return drops;
}

async function snapshot(c) {
    const { rows } = await c.query(`
        SELECT count(*)::int AS index_count,
               pg_size_pretty(sum(pg_relation_size(i.indexrelid))) AS index_size
        FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'public'`);
    return rows[0];
}

(async () => {
    const c = buildClient();
    await c.connect();

    const before = await snapshot(c);
    console.log(`Database currently has ${before.index_count} indexes totalling ${before.index_size}.\n`);

    const constraintDrops = await planUniqueConstraintDrops(c);
    const indexDrops = await planPlainIndexDrops(c);
    const all = [...constraintDrops, ...indexDrops];

    if (all.length === 0) {
        console.log('No duplicate constraints or indexes found. Nothing to do.');
        await c.end();
        return;
    }

    // Summarise per table so the plan is reviewable at a glance.
    const perTable = new Map();
    for (const d of all) perTable.set(d.table, (perTable.get(d.table) || 0) + 1);
    console.log('Planned drops (one copy of each column set is always kept):');
    for (const [table, n] of [...perTable].sort((a, b) => b[1] - a[1])) {
        console.log(`   ${String(n).padStart(5)}  ${table}`);
    }
    console.log(`\n   TOTAL: ${all.length} (${constraintDrops.length} unique constraints, ${indexDrops.length} plain indexes)`);

    if (!APPLY) {
        console.log('\nDRY RUN — nothing was changed. Re-run with --apply to execute.');
        console.log('Sample statements:');
        for (const d of all.slice(0, 5)) console.log(`   ${d.sql};   -- keeping ${d.keep}`);
        await c.end();
        return;
    }

    console.log('\nApplying...');
    let ok = 0;
    let failed = 0;
    for (const d of all) {
        try {
            await c.query(d.sql);
            ok++;
            if (ok % 100 === 0) console.log(`   ...${ok}/${all.length}`);
        } catch (err) {
            failed++;
            console.error(`   FAILED ${d.name} on ${d.table}: ${err.message}`);
        }
    }

    const after = await snapshot(c);
    console.log(`\nDone. Dropped ${ok}, failed ${failed}.`);
    console.log(`Indexes: ${before.index_count} -> ${after.index_count}`);
    console.log(`Index size: ${before.index_size} -> ${after.index_size}`);
    console.log('\nRun ANALYZE afterwards so the planner refreshes its statistics:');
    console.log('   node -e "require(\'dotenv\').config();const{Client}=require(\'pg\');..."  or simply: ANALYZE;');

    await c.end();
})().catch((e) => {
    console.error('ERROR:', e.message);
    process.exit(1);
});
