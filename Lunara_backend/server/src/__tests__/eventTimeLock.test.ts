import User, { UserRole } from '../models/User';
import Venue, { VenueCategory, VenueStatus } from '../models/Venue';
import PartyPlan, { PartyPlanStatus, PartyPlanLifecycleStatus, PartyPlanPaymentStatus } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus } from '../models/PartyPlanRequest';
import StrangersMeetRequest, { StrangersMeetStatus, StrangersMeetPaymentStatus } from '../models/StrangersMeetRequest';
import { EventTimeLockService } from '../services/EventTimeLockService';

describe('Universal 4-Hour Time-Lock System Unit & Integration Tests', () => {
    let testUser: User;
    let partnerUser: User;
    let venue: Venue;

    beforeAll(async () => {
        const ts = Date.now();
        testUser = await User.create({
            firstName: 'TimeLock',
            lastName: 'Tester',
            email: `timelock_user_${ts}@test.com`,
            phone: `999${ts.toString().slice(-7)}`,
            passwordHash: 'hashed_password',
            dateOfBirth: new Date('1998-01-01'),
            role: UserRole.CUSTOMER,
        });

        partnerUser = await User.create({
            firstName: 'Partner',
            lastName: 'User',
            email: `timelock_partner_${ts}@test.com`,
            phone: `888${ts.toString().slice(-7)}`,
            passwordHash: 'hashed_password',
            dateOfBirth: new Date('1998-01-01'),
            role: UserRole.CUSTOMER,
        });

        venue = await Venue.create({
            name: 'Time Lock Test Venue',
            addressLine1: '123 Time St',
            city: 'Pune',
            state: 'Maharashtra',
            country: 'India',
            postalCode: '411001',
            category: VenueCategory.CLUB,
            latitude: 18.5204,
            longitude: 73.8567,
            phone: '9876543210',
            ownerId: testUser.id,
            slug: `time-lock-venue-${ts}`,
            capacity: 100,
            status: VenueStatus.APPROVED,
        });
    });

    afterAll(async () => {
        if (testUser) await testUser.destroy();
        if (partnerUser) await partnerUser.destroy();
        if (venue) await venue.destroy();
    });

    test('Case 1: Same day gap < 4h (3 hours gap) -> BLOCKED', async () => {
        const baseTime = new Date('2026-09-01T20:00:00.000Z');
        const plan = await PartyPlan.create({
            userId: testUser.id,
            venueId: venue.id,
            message: '10 PM Party Plan',
            planDateTime: baseTime,
            mobileNumber: '9876543210',
            status: PartyPlanStatus.ACTIVE,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
        });

        const proposedTime = new Date('2026-09-01T23:00:00.000Z'); // 3 hours after baseTime
        const res = await EventTimeLockService.validateFourHourGap(testUser.id, proposedTime, 'party_plan');

        expect(res.allowed).toBe(false);
        if (!res.allowed) {
            expect(res.reason).toBe('FOUR_HOUR_TIME_LOCK');
            expect(res.conflictingEventType).toBe('PARTY_PLAN');
            expect(res.conflictingEventId).toBe(plan.id);
        }

        await plan.destroy();
    });

    test('Case 2: Same day gap >= 4h (4 hours gap) -> ALLOWED', async () => {
        const baseTime = new Date('2026-09-01T20:00:00.000Z');
        const plan = await PartyPlan.create({
            userId: testUser.id,
            venueId: venue.id,
            message: '8 PM Party Plan',
            planDateTime: baseTime,
            mobileNumber: '9876543210',
            status: PartyPlanStatus.ACTIVE,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
        });

        const proposedTime = new Date('2026-09-02T00:00:00.000Z'); // Exactly 4 hours later (12 AM)
        const res = await EventTimeLockService.validateFourHourGap(testUser.id, proposedTime, 'party_plan');

        expect(res.allowed).toBe(true);
        await plan.destroy();
    });

    test('Case 3: Boundary test: 3h 59m gap -> BLOCKED', async () => {
        const baseTime = new Date('2026-09-01T20:00:00.000Z');
        const plan = await PartyPlan.create({
            userId: testUser.id,
            venueId: venue.id,
            message: 'Base Event',
            planDateTime: baseTime,
            mobileNumber: '9876543210',
            status: PartyPlanStatus.ACTIVE,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
        });

        const proposedTime = new Date(baseTime.getTime() + (3 * 3600 + 59 * 60) * 1000); // 3h 59m
        const res = await EventTimeLockService.validateFourHourGap(testUser.id, proposedTime, 'solo_booking');

        expect(res.allowed).toBe(false);
        await plan.destroy();
    });

    test('Case 4: Boundary test: 4h 00m gap -> ALLOWED', async () => {
        const baseTime = new Date('2026-09-01T20:00:00.000Z');
        const plan = await PartyPlan.create({
            userId: testUser.id,
            venueId: venue.id,
            message: 'Base Event',
            planDateTime: baseTime,
            mobileNumber: '9876543210',
            status: PartyPlanStatus.ACTIVE,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
        });

        const proposedTime = new Date(baseTime.getTime() + 4 * 3600 * 1000); // Exactly 4h
        const res = await EventTimeLockService.validateFourHourGap(testUser.id, proposedTime, 'solo_booking');

        expect(res.allowed).toBe(true);
        await plan.destroy();
    });

    test('Case 5: Boundary test: 4h 01m gap -> ALLOWED', async () => {
        const baseTime = new Date('2026-09-01T20:00:00.000Z');
        const plan = await PartyPlan.create({
            userId: testUser.id,
            venueId: venue.id,
            message: 'Base Event',
            planDateTime: baseTime,
            mobileNumber: '9876543210',
            status: PartyPlanStatus.ACTIVE,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
        });

        const proposedTime = new Date(baseTime.getTime() + (4 * 3600 + 1 * 60) * 1000); // 4h 01m
        const res = await EventTimeLockService.validateFourHourGap(testUser.id, proposedTime, 'solo_booking');

        expect(res.allowed).toBe(true);
        await plan.destroy();
    });

    test('Case 6: Date crossover across midnight (Aug 20 11 PM vs Aug 21 2 AM = 3h gap) -> BLOCKED', async () => {
        const baseTime = new Date('2026-08-20T23:00:00.000Z'); // Aug 20 11 PM
        const plan = await PartyPlan.create({
            userId: testUser.id,
            venueId: venue.id,
            message: 'Aug 20 Late Party',
            planDateTime: baseTime,
            mobileNumber: '9876543210',
            status: PartyPlanStatus.ACTIVE,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
        });

        const proposedTime = new Date('2026-08-21T02:00:00.000Z'); // Aug 21 2 AM (3 hours diff)
        const res = await EventTimeLockService.validateFourHourGap(testUser.id, proposedTime, 'party_plan');

        expect(res.allowed).toBe(false);
        await plan.destroy();
    });

    test('Case 7: Date crossover across midnight (Aug 20 11 PM vs Aug 21 3 AM = 4h gap) -> ALLOWED', async () => {
        const baseTime = new Date('2026-08-20T23:00:00.000Z'); // Aug 20 11 PM
        const plan = await PartyPlan.create({
            userId: testUser.id,
            venueId: venue.id,
            message: 'Aug 20 Late Party',
            planDateTime: baseTime,
            mobileNumber: '9876543210',
            status: PartyPlanStatus.ACTIVE,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
        });

        const proposedTime = new Date('2026-08-21T03:00:00.000Z'); // Aug 21 3 AM (4 hours diff)
        const res = await EventTimeLockService.validateFourHourGap(testUser.id, proposedTime, 'party_plan');

        expect(res.allowed).toBe(true);
        await plan.destroy();
    });

    test('Case 8: Cross-event collision: Party Plan locks Solo Booking', async () => {
        const eventTime = new Date('2026-09-05T21:00:00.000Z');
        const plan = await PartyPlan.create({
            userId: testUser.id,
            venueId: venue.id,
            message: 'Cross Event Test Plan',
            planDateTime: eventTime,
            mobileNumber: '9876543210',
            status: PartyPlanStatus.ACTIVE,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
        });

        const proposedBookingTime = new Date('2026-09-05T22:30:00.000Z'); // 1.5h diff
        const res = await EventTimeLockService.validateFourHourGap(testUser.id, proposedBookingTime, 'solo_booking');

        expect(res.allowed).toBe(false);
        if (!res.allowed) {
            expect(res.conflictingEventType).toBe('PARTY_PLAN');
        }
        await plan.destroy();
    });

    test('Case 9: Cross-event collision: Stranger Meet locks Group Party', async () => {
        const meetTime = new Date('2026-09-06T18:00:00.000Z');
        const meet = await StrangersMeetRequest.create({
            userId: testUser.id,
            venueId: venue.id,
            subject: 'Test Stranger Meet',
            tagline: 'Fun meet',
            eventDateTime: meetTime,
            numberOfPersons: 25,
            chargesPerHead: 50,
            slotsFilled: 1,
            mobileNumber: '9876543210',
            status: StrangersMeetStatus.APPROVED,
            paymentStatus: StrangersMeetPaymentStatus.UNPAID,
        });

        const proposedGpTime = new Date('2026-09-06T19:30:00.000Z'); // 1.5h diff
        const res = await EventTimeLockService.validateFourHourGap(testUser.id, proposedGpTime, 'group_party');

        expect(res.allowed).toBe(false);
        if (!res.allowed) {
            expect(res.conflictingEventType).toBe('STRANGER_MEET');
        }
        await meet.destroy();
    });

    test('Case 10: Partner schedule locked when Party Plan request is accepted', async () => {
        const planTime = new Date('2026-09-07T20:00:00.000Z');
        const plan = await PartyPlan.create({
            userId: testUser.id,
            venueId: venue.id,
            message: 'Host Plan for Partner Test',
            planDateTime: planTime,
            mobileNumber: '9876543210',
            status: PartyPlanStatus.ACTIVE,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
        });

        const req = await PartyPlanRequest.create({
            planId: plan.id,
            requesterId: partnerUser.id,
            status: PartyPlanRequestStatus.ACCEPTED,
        });
        await plan.update({ matchedRequestId: req.id });

        // Test partner schedule is locked
        const proposedTimeForPartner = new Date('2026-09-07T22:00:00.000Z'); // 2h diff
        const partnerRes = await EventTimeLockService.validateFourHourGap(partnerUser.id, proposedTimeForPartner, 'party_plan');

        expect(partnerRes.allowed).toBe(false);
        if (!partnerRes.allowed) {
            expect(partnerRes.conflictingEventType).toBe('PARTY_PLAN');
        }

        await req.destroy();
        await plan.destroy();
    });

    test('Case 11: Pending unaccepted request does NOT lock partner schedule', async () => {
        const planTime = new Date('2026-09-08T20:00:00.000Z');
        const plan = await PartyPlan.create({
            userId: testUser.id,
            venueId: venue.id,
            message: 'Host Plan',
            planDateTime: planTime,
            mobileNumber: '9876543210',
            status: PartyPlanStatus.ACTIVE,
            isLive: true,
        });

        const req = await PartyPlanRequest.create({
            planId: plan.id,
            requesterId: partnerUser.id,
            status: PartyPlanRequestStatus.PENDING,
        });

        const proposedTimeForPartner = new Date('2026-09-08T21:00:00.000Z');
        const partnerRes = await EventTimeLockService.validateFourHourGap(partnerUser.id, proposedTimeForPartner, 'party_plan');

        expect(partnerRes.allowed).toBe(true);

        await req.destroy();
        await plan.destroy();
    });

    test('Case 12: Cancelled event releases time lock automatically', async () => {
        const baseTime = new Date('2026-09-09T20:00:00.000Z');
        const plan = await PartyPlan.create({
            userId: testUser.id,
            venueId: venue.id,
            message: 'Cancelled Plan',
            planDateTime: baseTime,
            mobileNumber: '9876543210',
            status: PartyPlanStatus.CANCELLED,
            lifecycleStatus: PartyPlanLifecycleStatus.CANCELLED,
        });

        const proposedTime = new Date('2026-09-09T21:00:00.000Z'); // 1 hour after cancelled plan
        const res = await EventTimeLockService.validateFourHourGap(testUser.id, proposedTime, 'party_plan');

        expect(res.allowed).toBe(true);
        await plan.destroy();
    });

    test('Case 13: Exclude event ID parameter prevents self-conflict during updates', async () => {
        const baseTime = new Date('2026-09-10T20:00:00.000Z');
        const plan = await PartyPlan.create({
            userId: testUser.id,
            venueId: venue.id,
            message: 'Self Update Plan',
            planDateTime: baseTime,
            mobileNumber: '9876543210',
            status: PartyPlanStatus.ACTIVE,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
        });

        const proposedTime = new Date('2026-09-10T21:00:00.000Z'); // 1 hour shift
        const res = await EventTimeLockService.validateFourHourGap(testUser.id, proposedTime, 'party_plan', plan.id);

        expect(res.allowed).toBe(true);
        await plan.destroy();
    });
});
