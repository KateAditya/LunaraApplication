/**
 * Performance index migration — behaviour preserving.
 *
 * Adds indexes only. No table, column, query, payload or application logic is
 * touched, so every endpoint returns byte-for-byte what it returned before.
 *
 * Why expression indexes:
 *   The profile metrics queries in mobileUserController compare a uuid column
 *   against a text parameter, e.g.
 *
 *       WHERE target_user_id::text = :userId
 *
 *   The cast makes the ordinary index on target_user_id unusable, so Postgres
 *   falls back to a sequential scan. Rewriting the SQL would fix that, but it
 *   would also change behaviour: today a non-uuid parameter quietly matches
 *   zero rows, whereas `= :userId::uuid` would raise. Indexing the *expression*
 *   keeps the SQL exactly as-is and still gives an index lookup.
 *
 * Safety:
 *   - CREATE INDEX CONCURRENTLY never blocks reads or writes on a live table.
 *   - IF NOT EXISTS makes the script idempotent; re-running it is a no-op.
 *   - Each statement is independent. One failure is reported and skipped; it
 *     cannot abort the rest or leave the database half-migrated.
 *
 * Usage:  node add-performance-indexes.js
 */

const { Client } = require('pg');
const dotenv = require('dotenv');

dotenv.config();

// CONCURRENTLY cannot run inside a transaction block, so each statement is
// issued on its own and reported individually.
const INDEXES = [
    // ── Profile metrics subqueries (getMyProfile) ────────────────────────────
    // Each of these backs a `WHERE <uuid col>::text = :userId` subquery.
    {
        name: 'idx_user_likes_target_text',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_likes_target_text
              ON user_likes ((target_user_id::text), action_type)`,
        note: 'likes_count + superlikes_count subqueries',
    },
    {
        name: 'idx_user_matches_user2_text',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_matches_user2_text
              ON user_matches ((user2_id::text), match_reason)`,
        note: 'superlikes_count subquery',
    },
    {
        name: 'idx_user_matches_user1_text',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_matches_user1_text
              ON user_matches ((user1_id::text))`,
        note: 'matched-partners UNION branch 1',
    },
    {
        name: 'idx_party_plans_user_text',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_party_plans_user_text
              ON party_plans ((user_id::text))`,
        note: 'party_plans_count + total_bookings subqueries',
    },
    {
        name: 'idx_tickets_user_text',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_tickets_user_text
              ON tickets ((user_id::text))`,
        note: 'total_bookings subquery',
    },
    {
        name: 'idx_bookings_user_text',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_bookings_user_text
              ON bookings ((user_id::text))`,
        note: 'total_bookings subquery',
    },
    {
        name: 'idx_sm_requests_user_text',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sm_requests_user_text
              ON strangers_meet_requests ((user_id::text))`,
        note: 'strangers_meet_count + total_bookings subqueries',
    },
    {
        name: 'idx_sm_joiners_user_text',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sm_joiners_user_text
              ON strangers_meet_joiners ((user_id::text))`,
        note: 'total_bookings subquery + matched-partners UNION',
    },
    {
        name: 'idx_group_parties_user_text',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_group_parties_user_text
              ON group_parties ((user_id::text))`,
        note: 'group_party_count + total_bookings subqueries',
    },
    {
        name: 'idx_ppr_requester_text',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ppr_requester_text
              ON party_plan_requests ((requester_id::text))`,
        note: 'total_bookings subquery + matched-partners UNION',
    },

    // ── Matched-partners UNION (getMyProfile, 7-way UNION) ───────────────────
    {
        name: 'idx_npm_host_text',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_npm_host_text
              ON night_partner_matches ((host_id::text))`,
        note: 'matched-partners UNION branch 2',
    },
    {
        name: 'idx_npm_partner_text',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_npm_partner_text
              ON night_partner_matches ((partner_id::text))`,
        note: 'matched-partners UNION branch 2',
    },
    {
        name: 'idx_social_conn_requester_text',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_social_conn_requester_text
              ON social_connections ((requester_id::text))`,
        note: 'matched-partners UNION branch 5',
    },
    {
        name: 'idx_social_conn_receiver_text',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_social_conn_receiver_text
              ON social_connections ((receiver_id::text))`,
        note: 'matched-partners UNION branch 5',
    },

    // ── Ticket synthesis hot loop (mobileTicketController) ───────────────────
    // Booking.findOne uses `specialRequests LIKE '%"planId":"<uuid>"%'` once per
    // plan. A leading wildcard cannot use a B-tree index, but a trigram GIN
    // index accelerates it without altering the query.
    {
        name: 'pg_trgm extension',
        sql: `CREATE EXTENSION IF NOT EXISTS pg_trgm`,
        note: 'required by the trigram index below',
        optional: true,
    },
    {
        name: 'idx_bookings_special_requests_trgm',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_bookings_special_requests_trgm
              ON bookings USING GIN (special_requests gin_trgm_ops)`,
        note: 'substring match on specialRequests in the ticket loop',
        optional: true,
    },
    {
        name: 'idx_bookings_going_mode_venue',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_bookings_going_mode_venue
              ON bookings (going_mode, venue_id, booking_date)`,
        note: 'second Booking.findOne in the same ticket loop',
    },
    {
        name: 'idx_tickets_booking_lookup',
        sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_tickets_booking_lookup
              ON tickets (booking_id, created_at DESC)`,
        note: 'Ticket.findOne following each booking lookup',
    },
];

function buildClient() {
    return new Client({
        host: process.env.DB_HOST || 'localhost',
        port: parseInt(process.env.DB_PORT || '5432', 10),
        database: process.env.DB_NAME || 'lunara_db',
        user: process.env.DB_USER || 'postgres',
        password: process.env.DB_PASSWORD || '',
        ssl: process.env.DB_SSL === 'true'
            ? { rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED !== 'false' }
            : false,
        // An index build on a large table can take a while; do not cut it short.
        statement_timeout: 0,
    });
}

/**
 * Reports whether the configured pool ceiling fits the server's connection
 * limit. Sizing the pool above what Postgres allows trades slow requests for
 * failed ones, so this is worth knowing before the next deploy.
 */
async function checkPoolHeadroom(client) {
    try {
        const { rows } = await client.query(
            `SELECT current_setting('max_connections')::int         AS max_conn,
                    current_setting('superuser_reserved_connections')::int AS reserved,
                    (SELECT count(*) FROM pg_stat_activity)::int    AS in_use`
        );
        const { max_conn: maxConn, reserved, in_use: inUse } = rows[0];
        const usable = maxConn - reserved;
        const poolMax = parseInt(process.env.DB_POOL_MAX || '60', 10);

        console.log('Connection budget');
        console.log(`  server max_connections : ${maxConn} (${reserved} reserved, ${inUse} currently in use)`);
        console.log(`  DB_POOL_MAX per process: ${poolMax}`);

        if (poolMax > usable) {
            console.log(`  >> DB_POOL_MAX (${poolMax}) exceeds usable connections (${usable}). Lower it.`);
        } else if (poolMax > usable * 0.6) {
            console.log(`  >> DB_POOL_MAX uses over 60% of the budget. Safe for one process;`);
            console.log(`     if you ever set ENABLE_CLUSTER=true, divide it by the worker count.`);
        } else {
            console.log('  >> headroom looks fine.');
        }
        console.log('');
    } catch (err) {
        console.log(`Connection budget check skipped: ${err.message}\n`);
    }
}

async function main() {
    const client = buildClient();
    await client.connect();
    console.log(`Connected to ${process.env.DB_NAME} on ${process.env.DB_HOST}\n`);

    await checkPoolHeadroom(client);

    const created = [];
    const existed = [];
    const failed = [];

    for (const idx of INDEXES) {
        const started = Date.now();
        try {
            const before = await indexExists(client, idx.name);
            await client.query(idx.sql);
            const elapsed = ((Date.now() - started) / 1000).toFixed(1);

            if (before) {
                existed.push(idx.name);
                console.log(`  = ${idx.name} — already present`);
            } else {
                created.push(idx.name);
                console.log(`  + ${idx.name} — created in ${elapsed}s  (${idx.note})`);
            }
        } catch (err) {
            failed.push({ name: idx.name, message: err.message, optional: !!idx.optional });
            const tag = idx.optional ? 'optional' : 'REQUIRED';
            console.log(`  ! ${idx.name} — failed [${tag}]: ${err.message}`);
        }
    }

    console.log('\n─────────────────────────────────────────────');
    console.log(`created: ${created.length}   already present: ${existed.length}   failed: ${failed.length}`);

    const hardFailures = failed.filter((f) => !f.optional);
    if (hardFailures.length > 0) {
        console.log('\nFailures that need attention:');
        for (const f of hardFailures) {
            console.log(`  - ${f.name}: ${f.message}`);
        }
        console.log(
            '\nIf a failure mentions IMMUTABLE, this Postgres build will not index that\n' +
            'cast expression. Nothing is broken — those queries simply keep their\n' +
            'current plan, exactly as before this script ran.'
        );
    }

    const trgmFailed = failed.some((f) => f.name.includes('trgm'));
    if (trgmFailed) {
        console.log(
            '\nThe trigram index was skipped. On Azure Database for PostgreSQL,\n' +
            "add 'PG_TRGM' to the azure.extensions server parameter, then re-run."
        );
    }

    await client.end();
}

/** True when an index of this name already exists in the current schema. */
async function indexExists(client, name) {
    if (!name.startsWith('idx_')) return false;
    const { rows } = await client.query(
        'SELECT 1 FROM pg_indexes WHERE indexname = $1 LIMIT 1',
        [name]
    );
    return rows.length > 0;
}

main().catch((err) => {
    console.error('Migration aborted:', err.message);
    process.exit(1);
});
