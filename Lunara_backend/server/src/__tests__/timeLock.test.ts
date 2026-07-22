import request from 'supertest';
import app from '../server';
import sequelize from '../config/database';
import User from '../models/User';
import Venue, { VenueCategory } from '../models/Venue';
import PlanTimeLock from '../models/PlanTimeLock';

describe('Advanced Time-Based Plan Lock & Cooldown Engine', () => {
    let testUser: any;
    let testOwner: any;
    let testVenue: any;

    beforeAll(async () => {
        // Sync database
        await sequelize.sync({ force: false });

        // Create owner user
        const ownerEmail = `owner.${Date.now()}@example.com`;
        const ownerPhone = `8${Math.floor(100000000 + Math.random() * 900000000)}`;
        testOwner = await User.create({
            email: ownerEmail,
            phone: ownerPhone,
            passwordHash: 'hashed_pw',
            firstName: 'Venue',
            lastName: 'Owner',
            dateOfBirth: new Date('1990-01-01'),
            role: 'venue_owner' as any,
            isVerified: true,
            isActive: true,
            isOnline: false
        } as any);

        // Create or find a test venue
        testVenue = await Venue.findOne();
        if (!testVenue) {
            testVenue = await (Venue as any).create({
                ownerId: testOwner.id,
                name: 'Time Lock Test Club',
                slug: 'time-lock-test-club',
                addressLine1: '123 Test St',
                area: 'Koramangala',
                city: 'Bengaluru',
                state: 'Karnataka',
                postalCode: '560034',
                phone: '9876543210',
                category: VenueCategory.CLUB,
                latitude: 12.9716,
                longitude: 77.5946,
                capacity: 500
            });
        }

        // Create a unique test user
        const uniqueEmail = `timelock.${Date.now()}@example.com`;
        const uniquePhone = `9${Math.floor(100000000 + Math.random() * 900000000)}`;
        
        testUser = await User.create({
            email: uniqueEmail,
            phone: uniquePhone,
            passwordHash: 'hashed_pw',
            firstName: 'Time',
            lastName: 'Lock',
            dateOfBirth: new Date('1995-01-01'),
            role: 'customer' as any,
            isVerified: true,
            isActive: true,
            isOnline: false
        } as any);
    });

    afterAll(async () => {
        // Clean up
        if (testUser) {
            await PlanTimeLock.destroy({ where: { userId: testUser.id } });
            await User.destroy({ where: { id: testUser.id } });
        }
        if (testOwner) {
            await Venue.destroy({ where: { ownerId: testOwner.id } });
            await User.destroy({ where: { id: testOwner.id } });
        }
    });

    beforeEach(async () => {
        if (testUser) {
            await PlanTimeLock.destroy({ where: { userId: testUser.id } });
            const Booking = require('../models/Booking').default;
            const Plan = require('../models/Plan').default;
            await Booking.destroy({ where: { userId: testUser.id } });
            await Plan.destroy({ where: { userId: testUser.id } });
        }
    });

    test('1. Basic Lock Enforcement: Creating plan locks out subsequent plan creations within cooldown window', async () => {
        const planDate = '2027-08-01';
        const startTime = '21:00';

        // Post a plan successfully
        const res1 = await request(app)
            .post('/api/mobile/plans')
            .send({
                userId: testUser.id,
                venueId: testVenue.id,
                planDate,
                startTime,
                tablePackage: 'silver'
            });

        expect(res1.status).toBe(201);
        expect(res1.body.success).toBe(true);

        // Try creating another plan on the same time -> should fail due to lock
        const res2 = await request(app)
            .post('/api/mobile/plans')
            .send({
                userId: testUser.id,
                venueId: testVenue.id,
                planDate,
                startTime: '22:00', // 1 hour later (within 4 hours default cooldown)
                tablePackage: 'silver'
            });

        expect(res2.status).toBe(409);
        expect(res2.body.success).toBe(false);
        expect(res2.body.code).toBe('PLAN_TIME_LOCKED');
        expect(res2.body.lock).toBeDefined();
        expect(res2.body.lock.remainingSeconds).toBeGreaterThan(0);
    });

    test('2. Concurrency Test: Simultaneous requests from same user only creates one plan and one lock', async () => {
        const planDate = '2027-09-01';
        
        // Fire 5 requests concurrently
        const requests = Array.from({ length: 5 }).map(() => {
            return request(app)
                .post('/api/mobile/plans')
                .send({
                    userId: testUser.id,
                    venueId: testVenue.id,
                    planDate,
                    startTime: '21:00',
                    tablePackage: 'silver'
                });
        });

        const responses = await Promise.all(requests);

        const successes = responses.filter(r => r.status === 201);
        const locks = responses.filter(r => r.status === 409 && r.body.code === 'PLAN_TIME_LOCKED');

        // Exactly one request must succeed, and all others must fail safely with code PLAN_TIME_LOCKED
        expect(successes.length).toBe(1);
        expect(locks.length).toBe(4);
    });
});
