const { Sequelize } = require('sequelize');
require('dotenv').config();

const sequelize = new Sequelize(process.env.DB_NAME, process.env.DB_USER, process.env.DB_PASSWORD, {
  host: process.env.DB_HOST,
  dialect: 'postgres',
  logging: false,
});

async function main() {
  try {
    const [results] = await sequelize.query(`
      SELECT column_name, data_type, character_maximum_length, udt_name 
      FROM information_schema.columns 
      WHERE table_name = 'venue_images'
    `);
    console.log("Schema:", results);
    process.exit(0);
  } catch (error) {
    console.error("Error:", error.message);
    process.exit(1);
  }
}
main();
