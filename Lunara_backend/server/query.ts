import { Sequelize, DataTypes } from 'sequelize';
import dotenv from 'dotenv';
dotenv.config();

const sequelize = new Sequelize(process.env.DB_NAME!, process.env.DB_USER!, process.env.DB_PASSWORD!, {
    host: process.env.DB_HOST,
    dialect: 'postgres',
    logging: false
});

async function run() {
    try {
        const [results] = await sequelize.query(`
            SELECT id, image_type, file_path, is_primary, display_order, uploaded_at 
            FROM venue_images 
            WHERE venue_id = '4628c2f1-09ee-460f-b242-a71dc3c8f246'
            ORDER BY image_type, display_order
        `);
        console.log("FAVELA IMAGES COUNT:", results.length);
        console.log("FAVELA IMAGES:", JSON.stringify(results, null, 2));
    } catch (e) {
        console.error(e);
    } finally {
        await sequelize.close();
    }
}
run();
