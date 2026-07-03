const { Sequelize } = require('sequelize');
require('dotenv').config();
const Venue = require('./dist/models/Venue').default;
const sequelize = require('./dist/config/database').default;

async function main() {
  try {
    console.log("Synchronizing venues table...");
    await Venue.sync({ alter: true });
    console.log("Venues table synchronized successfully.");
    process.exit(0);
  } catch (err) {
    console.error("Error synchronizing venues:", err);
    process.exit(1);
  }
}

main();
