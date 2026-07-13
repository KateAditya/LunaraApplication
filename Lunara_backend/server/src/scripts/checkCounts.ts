import dotenv from 'dotenv';
dotenv.config();

import sequelize from '../config/database';
import { User, Venue, Booking, Payment, PartyPlan, PartyPlanRequest, UserProfile } from '../models/index';

async function checkDatabaseCounts() {
    try {
        console.log('Connecting to database...');
        await sequelize.authenticate();
        console.log('✅ Connected successfully!');
        console.log('----------------------------------------');
        console.log('Fetching record counts...');

        const userCount = await User.count();
        const venueCount = await Venue.count();
        const bookingCount = await Booking.count();
        const paymentCount = await Payment.count();
        const partyPlanCount = await PartyPlan.count();
        const partyPlanRequestCount = await PartyPlanRequest.count();
        const profileCount = await UserProfile.count();

        console.log(`👥 Total Users: ${userCount}`);
        console.log(`👤 Total User Profiles: ${profileCount}`);
        console.log(`🏢 Total Venues: ${venueCount}`);
        console.log(`📅 Total Bookings: ${bookingCount}`);
        console.log(`💳 Total Payments: ${paymentCount}`);
        console.log(`🎉 Total Party Plans: ${partyPlanCount}`);
        console.log(`✉️ Total Party Plan Requests: ${partyPlanRequestCount}`);
        console.log('----------------------------------------');

    } catch (error: any) {
        console.error('❌ Error executing count check:', error.message);
    } finally {
        await sequelize.close();
        process.exit(0);
    }
}

checkDatabaseCounts();
