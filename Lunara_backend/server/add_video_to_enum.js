const { Sequelize } = require('sequelize');
require('dotenv').config();

const sequelize = new Sequelize(process.env.DB_NAME, process.env.DB_USER, process.env.DB_PASSWORD, {
  host: process.env.DB_HOST,
  dialect: 'postgres',
  logging: console.log,
});

async function main() {
  try {
    console.log("Adding 'video' to enum_venue_images_image_type...");
    await sequelize.query("ALTER TYPE enum_venue_images_image_type ADD VALUE IF NOT EXISTS 'video'");
    console.log("Successfully added 'video' to enum_venue_images_image_type");
    
    // Verify
    const [results] = await sequelize.query(`
      SELECT enumlabel 
      FROM pg_enum 
      JOIN pg_type ON pg_enum.enumtypid = pg_type.oid 
      WHERE pg_type.typname = 'enum_venue_images_image_type'
    `);
    console.log("Final enum values:", results.map(r => r.enumlabel));
    
    process.exit(0);
  } catch (error) {
    console.error("Error updating enum:", error.message);
    process.exit(1);
  }
}
main();
