require('dotenv').config();
const sequelize = require('./dist/config/database').default;

async function run() {
  try {
    console.log("Adding no_show_count to users table...");
    await sequelize.query('ALTER TABLE users ADD COLUMN no_show_count INTEGER DEFAULT 0;');
    console.log('Success: Added no_show_count to users');
  } catch (e) {
    console.error('Error adding no_show_count:', e.message);
  }

  try {
    console.log("Adding host_lat_lang_check_in to party_plans table...");
    await sequelize.query('ALTER TABLE party_plans ADD COLUMN host_lat_lang_check_in BOOLEAN DEFAULT false;');
    console.log('Success: Added host_lat_lang_check_in to party_plans');
  } catch (e) {
    console.error('Error adding host_lat_lang_check_in:', e.message);
  }
  
  process.exit();
}

run();
