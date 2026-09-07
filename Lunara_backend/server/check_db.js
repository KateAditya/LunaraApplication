const { Sequelize, QueryTypes } = require('sequelize');
require('dotenv').config();
const seq = new Sequelize({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME,
  username: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  dialect: 'postgres',
  logging: false,
  dialectOptions: { ssl: { require: true, rejectUnauthorized: false } },
});

async function main() {
  await seq.authenticate();
  console.log('Connected.');

  // Check unique constraints on SubscriptionUsage
  const constraints = await seq.query(`
    SELECT conname, pg_get_constraintdef(oid) as def
    FROM pg_constraint
    WHERE conrelid = '"SubscriptionUsage"'::regclass
    ORDER BY contype
  `, { type: QueryTypes.SELECT });
  console.log('Constraints:', JSON.stringify(constraints, null, 2));

  // Show duplicates that would conflict
  const conflicts = await seq.query(`
    SELECT su1.user_id, su1.feature_key, su1.period, su1.used as used_upper, su2.used as used_lower
    FROM "SubscriptionUsage" su1
    JOIN "SubscriptionUsage" su2 ON su1.user_id = su2.user_id AND su1.feature_key = su2.feature_key AND LOWER(su1.period) = su2.period
    WHERE su1.period <> LOWER(su1.period)
  `, { type: QueryTypes.SELECT });
  console.log('Conflicting rows:', JSON.stringify(conflicts));

  // Merge: add used from DAILY into daily, then delete DAILY rows
  if (conflicts.length > 0) {
    await seq.query(`
      UPDATE "SubscriptionUsage" su_lower
      SET used = su_lower.used + su_upper.used,
          updated_at = NOW()
      FROM "SubscriptionUsage" su_upper
      WHERE su_lower.user_id = su_upper.user_id
        AND su_lower.feature_key = su_upper.feature_key
        AND su_lower.period = LOWER(su_upper.period)
        AND su_upper.period <> LOWER(su_upper.period)
    `);
    console.log('Merged usage counts.');

    await seq.query(`DELETE FROM "SubscriptionUsage" WHERE period <> LOWER(period)`);
    console.log('Deleted uppercase period rows.');
  } else {
    // No conflicts, safe to update
    await seq.query(`UPDATE "SubscriptionUsage" SET period = LOWER(period) WHERE period <> LOWER(period)`);
    console.log('Updated period casing directly (no conflicts).');
  }

  const after = await seq.query(`
    SELECT feature_key, period, COUNT(*) as cnt FROM "SubscriptionUsage" GROUP BY feature_key, period ORDER BY feature_key
  `, { type: QueryTypes.SELECT });
  console.log('Final state:', JSON.stringify(after));

  await seq.close();
}

main().catch(e => { console.error('Error:', e.message, '\n', e.stack); process.exit(1); });
