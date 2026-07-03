import { VenueImage } from './src/models';
import sequelize from './src/config/database';
import fs from 'fs';
import path from 'path';

const clearAll = async () => {
    try {
        await sequelize.authenticate();
        console.log('Connected to database.');

        // Delete all VenueImage records
        await VenueImage.destroy({ where: {} });
        console.log('Deleted all VenueImage records from database.');

        // Clear uploads/venues directory
        const venuesDir = path.join(process.cwd(), 'uploads', 'venues');
        if (fs.existsSync(venuesDir)) {
            fs.rmSync(venuesDir, { recursive: true, force: true });
            fs.mkdirSync(venuesDir, { recursive: true });
            console.log('Cleared uploads/venues directory.');
        } else {
            console.log('uploads/venues directory does not exist, nothing to clear on disk.');
        }

        console.log('Successfully cleared all venue images!');
        process.exit(0);
    } catch (err) {
        console.error('Error clearing venue images:', err);
        process.exit(1);
    }
};

clearAll();
