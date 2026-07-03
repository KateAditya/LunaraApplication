const { Sequelize } = require('sequelize');
require('dotenv').config();
const sequelize = require('./dist/config/database').default;

// Require the model so that it registers with sequelize
const StrangersMeetRequest = require('./dist/models/StrangersMeetRequest').default;
const User = require('./dist/models/User').default;
const Venue = require('./dist/models/Venue').default;

async function main() {
  try {
    console.log("Synchronizing strangers_meet_requests table...");
    await StrangersMeetRequest.sync({ alter: true });
    console.log("strangers_meet_requests table synchronized successfully.");
    process.exit(0);
  } catch (err) {
    console.error("Error synchronizing table:", err);
    process.exit(1);
  }
}

main();
