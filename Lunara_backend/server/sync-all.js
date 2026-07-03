require('dotenv').config();
const sequelize = require('./dist/config/database').default;
const models = require('./dist/models/index').default;

async function main() {
  try {
    console.log("Synchronizing all tables...");
    await sequelize.sync({ alter: true });
    console.log("All tables synchronized successfully.");
    process.exit(0);
  } catch (err) {
    console.error("Error synchronizing tables:", err);
    process.exit(1);
  }
}

main();
