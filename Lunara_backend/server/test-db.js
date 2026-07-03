const { Sequelize } = require('sequelize');
const dotenv = require('dotenv');
dotenv.config();

const sequelize = new Sequelize(process.env.DB_NAME, process.env.DB_USER, process.env.DB_PASSWORD, {
  host: process.env.DB_HOST,
  dialect: 'postgres',
  logging: false,
});

async function main() {
  try {
    const [results] = await sequelize.query("SELECT * FROM venue_images ORDER BY uploaded_at DESC LIMIT 5");
    console.log("Recent images:", JSON.stringify(results, null, 2));
    process.exit(0);
  } catch (error) {
    console.error("Error:", error.message);
    process.exit(1);
  }
}
main();
