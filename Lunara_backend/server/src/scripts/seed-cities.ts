import dotenv from 'dotenv';
dotenv.config();

import City from '../models/City';
import { connectDatabase } from '../config/database';

const INDIAN_CITIES = [
    { name: 'Mumbai', state: 'Maharashtra', displayOrder: 1 },
    { name: 'Delhi', state: 'Delhi', displayOrder: 2 },
    { name: 'Bangalore', state: 'Karnataka', displayOrder: 3 },
    { name: 'Hyderabad', state: 'Telangana', displayOrder: 4 },
    { name: 'Ahmedabad', state: 'Gujarat', displayOrder: 5 },
    { name: 'Chennai', state: 'Tamil Nadu', displayOrder: 6 },
    { name: 'Kolkata', state: 'West Bengal', displayOrder: 7 },
    { name: 'Surat', state: 'Gujarat', displayOrder: 8 },
    { name: 'Pune', state: 'Maharashtra', displayOrder: 9 },
    { name: 'Jaipur', state: 'Rajasthan', displayOrder: 10 },
    { name: 'Lucknow', state: 'Uttar Pradesh', displayOrder: 11 },
    { name: 'Kanpur', state: 'Uttar Pradesh', displayOrder: 12 },
    { name: 'Nagpur', state: 'Maharashtra', displayOrder: 13 },
    { name: 'Indore', state: 'Madhya Pradesh', displayOrder: 14 },
    { name: 'Thane', state: 'Maharashtra', displayOrder: 15 },
    { name: 'Bhopal', state: 'Madhya Pradesh', displayOrder: 16 },
    { name: 'Visakhapatnam', state: 'Andhra Pradesh', displayOrder: 17 },
    { name: 'Pimpri-Chinchwad', state: 'Maharashtra', displayOrder: 18 },
    { name: 'Patna', state: 'Bihar', displayOrder: 19 },
    { name: 'Vadodara', state: 'Gujarat', displayOrder: 20 },
];

async function seedCities() {
    try {
        await connectDatabase();
        await City.sync({ alter: true });

        for (const city of INDIAN_CITIES) {
            await City.findOrCreate({
                where: { name: city.name },
                defaults: {
                    name: city.name,
                    state: city.state,
                    isActive: true,
                    displayOrder: city.displayOrder,
                },
            });
        }

        const count = await City.count();
        console.log(`✅ Seeded cities table. Total cities: ${count}`);
        process.exit(0);
    } catch (error) {
        console.error('❌ Error seeding cities:', error);
        process.exit(1);
    }
}

seedCities();
