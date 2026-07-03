import { v4 as uuidv4 } from 'uuid';
import sequelize from '../config/database';
import Venue, { VenueCategory, VenueStatus } from '../models/Venue';

// Random owner ID for associations
const OWNER_ID = uuidv4();

const puneVenues = [
    {
        ownerId: OWNER_ID,
        name: 'High Spirits Cafe',
        slug: 'high-spirits-koregaon-park',
        description: 'Iconic live music venue and pub in Pune.',
        category: VenueCategory.PUB,
        addressLine1: 'Mundhwa Road',
        addressLine2: 'Next to Westin',
        city: 'Pune',
        state: 'Maharashtra',
        postalCode: '411036',
        latitude: 18.5362,
        longitude: 73.9071,
        phone: '020-65250428',
        capacity: 300,
        openingTime: '19:00:00',
        closingTime: '23:30:00',
        averageRating: 4.6,
        totalReviews: 2450,
        status: VenueStatus.APPROVED,
        featured: true,
    },
    {
        ownerId: OWNER_ID,
        name: 'Elephant & Co.',
        slug: 'elephant-and-co-kalyani-nagar',
        description: 'Gastropub famous for craft beers and lively crowd.',
        category: VenueCategory.PUB,
        addressLine1: 'Ground Floor, Goodwill Enclave',
        addressLine2: 'Kalyani Nagar',
        city: 'Pune',
        state: 'Maharashtra',
        postalCode: '411014',
        latitude: 18.5475,
        longitude: 73.9015,
        phone: '09766860086',
        capacity: 150,
        openingTime: '18:00:00',
        closingTime: '01:00:00',
        averageRating: 4.8,
        totalReviews: 1800,
        status: VenueStatus.APPROVED,
        featured: false,
    },
    {
        ownerId: OWNER_ID,
        name: 'MiAMi',
        slug: 'miami-club-jw-marriott',
        description: 'Premium nightclub at JW Marriott.',
        category: VenueCategory.CLUB,
        addressLine1: 'JW Marriott, Senapati Bapat Road',
        city: 'Pune',
        state: 'Maharashtra',
        postalCode: '411053',
        latitude: 18.5323,
        longitude: 73.8315,
        phone: '020-66833333',
        capacity: 500,
        openingTime: '21:00:00',
        closingTime: '03:00:00',
        averageRating: 4.5,
        totalReviews: 950,
        status: VenueStatus.APPROVED,
        featured: true,
    },
    {
        ownerId: OWNER_ID,
        name: 'The Daily All Day',
        slug: 'the-daily-all-day-koregaon-park',
        description: 'Chic lounge with great cocktails.',
        category: VenueCategory.LOUNGE,
        addressLine1: 'Lane 7, Koregaon Park',
        city: 'Pune',
        state: 'Maharashtra',
        postalCode: '411001',
        latitude: 18.5385,
        longitude: 73.8967,
        phone: '08888201201',
        capacity: 200,
        openingTime: '12:00:00',
        closingTime: '01:30:00',
        averageRating: 4.7,
        totalReviews: 1200,
        status: VenueStatus.APPROVED,
        featured: false,
    },
    {
        ownerId: OWNER_ID,
        name: 'Penthouze Nightlife',
        slug: 'penthouze-koregaon-park',
        description: 'Rooftop club with Pune skyline views.',
        category: VenueCategory.CLUB,
        addressLine1: 'Rooftop, Onyx Tower',
        addressLine2: 'Koregaon Park Annexe',
        city: 'Pune',
        state: 'Maharashtra',
        postalCode: '411001',
        latitude: 18.5391,
        longitude: 73.9090,
        phone: '07397800009',
        capacity: 400,
        openingTime: '19:00:00',
        closingTime: '01:30:00',
        averageRating: 4.2,
        totalReviews: 3100,
        status: VenueStatus.APPROVED,
        featured: true,
    }
];

async function seedPuneVenues() {
    try {
        console.log('Connecting to database...');
        await sequelize.authenticate();

        console.log('Inserting Pune venues...');
        // Disable foreign key checks temporarily if needed, 
        // but here we just pass a random UUID for ownerId. 
        // In Postgres with Sequelize, if there is a strict FK constraint on User, this might fail.
        // If it fails, we will need to create a dummy user first.

        // Let's create a dummy user just in case there is a strict FK
        const User = (await import('../models/User')).default;
        const randomPhone = '9' + Math.floor(100000000 + Math.random() * 900000000).toString();

        await User.findOrCreate({
            where: { email: 'owner@pune.test' },
            defaults: {
                id: OWNER_ID,
                firstName: 'Dummy',
                lastName: 'Owner',
                email: 'owner@pune.test',
                phone: randomPhone,
                passwordHash: 'password123',
                dateOfBirth: new Date('1990-01-01'),
                role: 'venue_owner' as any,
                isActive: true
            }
        });

        for (const venue of puneVenues) {
            await Venue.upsert(venue);
        }

        console.log('Successfully seeded Pune venues!');
    } catch (error) {
        console.error('Error seeding venues:', error);
    } finally {
        await sequelize.close();
    }
}

seedPuneVenues();
