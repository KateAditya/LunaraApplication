/**
 * Read-only latency diagnostic.
 *
 * Separates the three things that can make a request slow:
 *   1. network round-trip to the database,
 *   2. how long each real query actually takes,
 *   3. how many rows the database had to materialise to answer it.
 *
 * Runs SELECT / EXPLAIN ANALYZE only. Nothing is written or altered.
 *
 * Usage: node diagnose-slow-queries.js
 */

const { Client } = require('pg');
const dotenv = require('dotenv');

dotenv.config();

const client = new Client({
    host: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT || '5432', 10),
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    ssl: process.env.DB_SSL === 'true'
        ? { rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED !== 'false' }
        : false,
    statement_timeout: 120000,
});

const TABLES = [
    'users', 'user_photos', 'user_profiles', 'venues', 'venue_images',
    'plans', 'party_plans', 'party_plan_requests', 'bookings', 'tickets',
    'notifications', 'strangers_meet_requests', 'strangers_meet_joiners',
    'group_parties', 'user_likes', 'user_matches', 'conversations', 'messages',
];

async function rtt(samples = 7) {
    const times = [];
    for (let i = 0; i < samples; i++) {
        const t0 = process.hrtime.bigint();
        await client.query('SELECT 1');
        times.push(Number(process.hrtime.bigint() - t0) / 1e6);
    }
    times.sort((a, b) => a - b);
    return { min: times[0], median: times[Math.floor(times.length / 2)], max: times[times.length - 1] };
}

async function timed(label, sql) {
    const t0 = process.hrtime.bigint();
    let rows = 0;
    try {
        const r = await client.query(sql);
        rows = r.rowCount;
    } catch (err) {
        console.log(`  ${label.padEnd(44)}  FAILED: ${err.message.slice(0, 60)}`);
        return null;
    }
    const ms = Number(process.hrtime.bigint() - t0) / 1e6;
    console.log(`  ${label.padEnd(44)} ${ms.toFixed(0).padStart(7)}ms  ${String(rows).padStart(6)} rows`);
    return ms;
}

async function explain(label, sql) {
    try {
        const r = await client.query(`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ${sql}`);
        const plan = r.rows[0]['QUERY PLAN'][0];
        const exec = plan['Execution Time'];
        const planning = plan['Planning Time'];

        // walk the plan tree for scan types and the widest row count
        const scans = {};
        let maxRows = 0;
        (function walk(node) {
            const t = node['Node Type'] || '';
            if (/Scan/.test(t)) {
                const key = `${t}${node['Relation Name'] ? ' ' + node['Relation Name'] : ''}`;
                scans[key] = (scans[key] || 0) + 1;
            }
            maxRows = Math.max(maxRows, node['Actual Rows'] || 0);
            for (const child of node.Plans || []) walk(child);
        })(plan.Plan);

        console.log(`\n  ${label}`);
        console.log(`    planning ${planning.toFixed(1)}ms   execution ${exec.toFixed(1)}ms   widest node ${maxRows} rows`);
        const seq = Object.keys(scans).filter((k) => k.startsWith('Seq Scan'));
        console.log(`    scans: ${Object.entries(scans).map(([k, v]) => `${k}${v > 1 ? ' x' + v : ''}`).join(', ') || 'none'}`);
        if (seq.length) console.log(`    >> ${seq.length} sequential scan(s): ${seq.join(', ')}`);
    } catch (err) {
        console.log(`\n  ${label}\n    EXPLAIN failed: ${err.message.slice(0, 90)}`);
    }
}

async function main() {
    await client.connect();
    console.log(`Connected to ${process.env.DB_NAME} @ ${process.env.DB_HOST}\n`);

    console.log('1. NETWORK ROUND-TRIP  (SELECT 1, so ~pure latency)');
    const r = await rtt();
    console.log(`  min ${r.min.toFixed(1)}ms   median ${r.median.toFixed(1)}ms   max ${r.max.toFixed(1)}ms`);
    console.log('  Every query a request makes pays this at least once.\n');

    console.log('2. TABLE SIZES  (how much data these queries walk)');
    const sizes = {};
    for (const t of TABLES) {
        try {
            const q = await client.query(`SELECT count(*)::int AS n FROM ${t}`);
            sizes[t] = q.rows[0].n;
        } catch { sizes[t] = null; }
    }
    for (const [t, n] of Object.entries(sizes)) {
        if (n === null) { console.log(`  ${t.padEnd(26)}  (absent)`); continue; }
        console.log(`  ${t.padEnd(26)} ${String(n).padStart(8)} rows`);
    }

    console.log('\n3. THE LIVE-FEED QUERY  (the one the app calls most)');
    await explain('Plan.findAll with host->profile/photos + venue->images, limit 30', `
        SELECT "Plan".*, "host"."id", "host->profile"."id", "host->photos"."id", "venue"."id", "venue->images"."id"
        FROM "plans" AS "Plan"
        LEFT JOIN "users" AS "host" ON "Plan"."user_id" = "host"."id"
        LEFT JOIN "user_profiles" AS "host->profile" ON "host"."id" = "host->profile"."user_id"
        LEFT JOIN "user_photos" AS "host->photos" ON "host"."id" = "host->photos"."user_id" AND "host->photos"."is_primary" = true
        LEFT JOIN "venues" AS "venue" ON "Plan"."venue_id" = "venue"."id"
        LEFT JOIN "venue_images" AS "venue->images" ON "venue"."id" = "venue->images"."venue_id" AND "venue->images"."is_primary" = true
        WHERE "Plan"."status" = 'active'
        ORDER BY "Plan"."created_at" DESC
        LIMIT 30
    `);

    console.log('\n4. PROFILE METRICS  (::text casts - do they use an index?)');
    const anyUser = await client.query('SELECT id::text AS id FROM users LIMIT 1');
    if (anyUser.rows.length) {
        const uid = anyUser.rows[0].id;
        await explain('COUNT with target_user_id::text = $uuid (cast blocks index)',
            `SELECT COUNT(*)::int FROM user_likes WHERE target_user_id::text = '${uid}' AND action_type = 'like'`);
        await explain('same COUNT without the cast (index-eligible)',
            `SELECT COUNT(*)::int FROM user_likes WHERE target_user_id = '${uid}'::uuid AND action_type = 'like'`);
    }

    console.log('\n5. TICKET LOOKUP  (LIKE %...% used as a join)');
    await explain('Booking lookup by substring match on special_requests',
        `SELECT * FROM bookings WHERE special_requests LIKE '%"planId":"00000000-0000-0000-0000-000000000000"%' LIMIT 1`);

    console.log('\n6. INDEX PRESENCE  (did add-performance-indexes.js ever run?)');
    const idx = await client.query(`
        SELECT indexname FROM pg_indexes
        WHERE indexname IN (
            'idx_user_likes_target_text','idx_party_plans_user_text','idx_bookings_user_text',
            'idx_bookings_special_requests_trgm','idx_tickets_user_text'
        ) ORDER BY indexname`);
    if (idx.rows.length === 0) {
        console.log('  none of the new performance indexes exist -> migration has NOT been run');
    } else {
        for (const row of idx.rows) console.log(`  present: ${row.indexname}`);
    }

    await client.end();
}

main().catch((e) => { console.error('diagnostic failed:', e.message); process.exit(1); });
