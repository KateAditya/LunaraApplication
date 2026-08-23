import request from 'supertest';
import app from '../server';
import User, { UserRole } from '../models/User';
import Venue, { VenueCategory } from '../models/Venue';
import PartyPlan, { PartyPlanStatus, PartyPlanLifecycleStatus, PartyPlanVisibility, PartyPlanPaymentStatus, PartyPlanPaymentType } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus } from '../models/PartyPlanRequest';
import { generateAccessToken } from '../utils/jwt';

jest.mock('razorpay', () => {
    return jest.fn().mockImplementation(() => {
        return {
            orders: {
                create: jest.fn().mockImplementation((options: any) => {
                    return Promise.resolve({
                        id: `order_mock_${Math.random().toString(36).substr(2, 9)}`,
                        amount: options.amount,
                        currency: options.currency,
                    });
                }),
            },
        };
    });
});

jest.mock('../services/fcmService', () => ({
    sendPushNotification: jest.fn().mockResolvedValue(true),
    sendMulticastPushNotification: jest.fn().mockResolvedValue(true),
}));

describe('Party Plan Multiple Requests, Cancellation & Re-Request Lifecycle', () => {
    let host: User;
    let userA: User;
    let userB: User;
    let userC: User;
    let venue: Venue;
    let partyPlan: PartyPlan;

    let hostToken: string;
    let userAToken: string;
    let userBToken: string;
    let userCToken: string;

    beforeAll(async () => {
        // Create host and requesters
        const ts = Date.now();
        host = await User.create({
            firstName: 'Aditya',
            lastName: 'Host',
            email: `host_${ts}@test.com`,
            phone: '9876543210',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1995-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        userA = await User.create({
            firstName: 'Prashant',
            lastName: 'A',
            email: `usera_${ts}@test.com`,
            phone: '9876543211',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1996-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        userB = await User.create({
            firstName: 'Rahul',
            lastName: 'B',
            email: `userb_${ts}@test.com`,
            phone: '9876543212',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1997-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        userC = await User.create({
            firstName: 'Amit',
            lastName: 'C',
            email: `userc_${ts}@test.com`,
            phone: '9876543213',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1998-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        hostToken = generateAccessToken({ userId: host.id, email: host.email, role: host.role });
        userAToken = generateAccessToken({ userId: userA.id, email: userA.email, role: userA.role });
        userBToken = generateAccessToken({ userId: userB.id, email: userB.email, role: userB.role });
        userCToken = generateAccessToken({ userId: userC.id, email: userC.email, role: userC.role });

        venue = await Venue.create({
            ownerId: host.id,
            name: 'The Ruby Hilltop',
            slug: `ruby-hilltop-${ts}`,
            addressLine1: 'Hilltop Road, Vagator',
            city: 'Goa',
            state: 'Goa',
            postalCode: '403509',
            phone: '9876543210',
            capacity: 200,
            openingTime: '18:00:00',
            closingTime: '03:00:00',
            daysOpen: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
            category: VenueCategory.CLUB,
            isActive: true,
        });

        // Create an active Party Plan
        const futureDate = new Date(Date.now() + 24 * 60 * 60 * 1000);
        partyPlan = await PartyPlan.create({
            userId: host.id,
            venueId: venue.id,
            planDateTime: futureDate,
            mobileNumber: '9876543210',
            message: "Let's party at The Ruby Hilltop! 🚀",
            visibility: PartyPlanVisibility.PUBLIC,
            paymentType: PartyPlanPaymentType.SPLIT,
            depositAmount: 99.0,
            status: PartyPlanStatus.ACTIVE,
            lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
            isLive: true,
            hostPaymentStatus: PartyPlanPaymentStatus.UNPAID,
        });
    });

    let reqAId = '';
    let reqBId = '';
    let reqCId = '';

    test('Case 1: Multiple users (A, B, C) can request the same party plan independently', async () => {
        // User A requests
        const resA = await request(app)
            .post(`/api/mobile/party-plans/${partyPlan.id}/requests`)
            .set('Authorization', `Bearer ${userAToken}`)
            .send({ userId: userA.id });
        expect(resA.status).toBe(201);
        expect(resA.body.success).toBe(true);
        expect(resA.body.data.status).toBe(PartyPlanRequestStatus.PENDING);
        reqAId = resA.body.data.id;

        // User B requests
        const resB = await request(app)
            .post(`/api/mobile/party-plans/${partyPlan.id}/requests`)
            .set('Authorization', `Bearer ${userBToken}`)
            .send({ userId: userB.id });
        expect(resB.status).toBe(201);
        expect(resB.body.success).toBe(true);
        expect(resB.body.data.status).toBe(PartyPlanRequestStatus.PENDING);
        reqBId = resB.body.data.id;

        // User C requests
        const resC = await request(app)
            .post(`/api/mobile/party-plans/${partyPlan.id}/requests`)
            .set('Authorization', `Bearer ${userCToken}`)
            .send({ userId: userC.id });
        expect(resC.status).toBe(201);
        expect(resC.body.success).toBe(true);
        expect(resC.body.data.status).toBe(PartyPlanRequestStatus.PENDING);
        reqCId = resC.body.data.id;

        // Verify all 3 exist with PENDING
        const allPending = await PartyPlanRequest.findAll({
            where: { planId: partyPlan.id, status: PartyPlanRequestStatus.PENDING }
        });
        expect(allPending.length).toBe(3);
    });

    test('Case 2: Duplicate active request from the same user is rejected (409)', async () => {
        const res = await request(app)
            .post(`/api/mobile/party-plans/${partyPlan.id}/requests`)
            .set('Authorization', `Bearer ${userAToken}`)
            .send({ userId: userA.id });
        expect(res.status).toBe(409);
        expect(res.body.success).toBe(false);
        expect(res.body.message).toContain('active request');
    });

    test('Case 3: User A cancels request -> Request marked CANCELLED without physical deletion', async () => {
        const cancelRes = await request(app)
            .post(`/api/mobile/party-plans/requests/${reqAId}/cancel`)
            .set('Authorization', `Bearer ${userAToken}`)
            .send({ userId: userA.id, reason: 'changed_plans' });
        expect(cancelRes.status).toBe(200);
        expect(cancelRes.body.success).toBe(true);

        const updatedReqA = await PartyPlanRequest.findByPk(reqAId);
        expect(updatedReqA).not.toBeNull();
        expect(updatedReqA!.status).toBe(PartyPlanRequestStatus.CANCELLED);
        expect(updatedReqA!.cancelledBy).toBe(userA.id);
        expect(updatedReqA!.cancelledAt).not.toBeNull();
    });

    test('Case 4: User A cancelling does NOT affect User B and User C requests', async () => {
        const reqB = await PartyPlanRequest.findByPk(reqBId);
        const reqC = await PartyPlanRequest.findByPk(reqCId);

        expect(reqB!.status).toBe(PartyPlanRequestStatus.PENDING);
        expect(reqC!.status).toBe(PartyPlanRequestStatus.PENDING);
    });

    test('Case 5: Cancellation is idempotent (repeated cancel returns 200)', async () => {
        const cancelAgain = await request(app)
            .post(`/api/mobile/party-plans/requests/${reqAId}/cancel`)
            .set('Authorization', `Bearer ${userAToken}`)
            .send({ userId: userA.id });
        expect(cancelAgain.status).toBe(200);
        expect(cancelAgain.body.success).toBe(true);
        expect(cancelAgain.body.message).toContain('already cancelled');
    });

    test('Case 6: Host cannot accept User A cancelled request (rejected with 409)', async () => {
        const acceptCancelled = await request(app)
            .post(`/api/mobile/party-plans/requests/${reqAId}/accept`)
            .set('Authorization', `Bearer ${hostToken}`)
            .send({ userId: host.id });
        expect(acceptCancelled.status).toBe(409);
        expect(acceptCancelled.body.success).toBe(false);
        expect(acceptCancelled.body.message).toContain('cancelled');
    });

    test('Case 7: Host fetching requests only returns active requests (B & C, not cancelled A)', async () => {
        const hostRequestsRes = await request(app)
            .get(`/api/mobile/party-plans/${partyPlan.id}/requests?userId=${host.id}`)
            .set('Authorization', `Bearer ${hostToken}`);
        expect(hostRequestsRes.status).toBe(200);
        expect(hostRequestsRes.body.success).toBe(true);

        const activeReqIds = hostRequestsRes.body.data.map((r: any) => r.id);
        expect(activeReqIds).toContain(reqBId);
        expect(activeReqIds).toContain(reqCId);
        expect(activeReqIds).not.toContain(reqAId);
    });

    test('Case 8: User A CAN send a new join request after cancelling previous request', async () => {
        const reRequestRes = await request(app)
            .post(`/api/mobile/party-plans/${partyPlan.id}/requests`)
            .set('Authorization', `Bearer ${userAToken}`)
            .send({ userId: userA.id });
        expect(reRequestRes.status).toBe(201);
        expect(reRequestRes.body.success).toBe(true);
        expect(reRequestRes.body.data.status).toBe(PartyPlanRequestStatus.PENDING);

        const newReqAId = reRequestRes.body.data.id;
        expect(newReqAId).not.toBe(reqAId);

        // Historical request remains CANCELLED
        const historicalReqA = await PartyPlanRequest.findByPk(reqAId);
        expect(historicalReqA!.status).toBe(PartyPlanRequestStatus.CANCELLED);

        // New request is PENDING
        const activeReqA = await PartyPlanRequest.findByPk(newReqAId);
        expect(activeReqA!.status).toBe(PartyPlanRequestStatus.PENDING);
    });

    test('Case 9: Host accepts User B -> User B goes to PAYMENT_PENDING, User C goes to WAITING', async () => {
        const acceptRes = await request(app)
            .post(`/api/mobile/party-plans/requests/${reqBId}/accept`)
            .set('Authorization', `Bearer ${hostToken}`)
            .send({ userId: host.id });
        expect(acceptRes.status).toBe(200);
        expect(acceptRes.body.success).toBe(true);

        const updatedReqB = await PartyPlanRequest.findByPk(reqBId);
        expect(updatedReqB!.status).toBe(PartyPlanRequestStatus.PAYMENT_PENDING);

        const updatedReqC = await PartyPlanRequest.findByPk(reqCId);
        expect(updatedReqC!.status).toBe(PartyPlanRequestStatus.WAITING);
    });

    test('Case 10: While User B is matched, other requests cannot be accepted', async () => {
        const acceptC = await request(app)
            .post(`/api/mobile/party-plans/requests/${reqCId}/accept`)
            .set('Authorization', `Bearer ${hostToken}`)
            .send({ userId: host.id });
        expect(acceptC.status).toBe(400);
        expect(acceptC.body.success).toBe(false);
    });

    test('Case 11: When accepted match is reopened (timeout/cancellation), WAITING requests reactivate to PENDING', async () => {
        const { reopenPlan } = require('../controllers/partyPlanController');
        const plan = await PartyPlan.findByPk(partyPlan.id);
        await reopenPlan(plan, reqBId, 'payment_failed');

        const failedReqB = await PartyPlanRequest.findByPk(reqBId);
        expect(failedReqB!.status).toBe(PartyPlanRequestStatus.PAYMENT_FAILED);

        // User C should be reactivated to PENDING
        const reactivatedReqC = await PartyPlanRequest.findByPk(reqCId);
        expect(reactivatedReqC!.status).toBe(PartyPlanRequestStatus.PENDING);

        // Plan should be back to active
        const reloadedPlan = await PartyPlan.findByPk(partyPlan.id);
        expect(reloadedPlan!.status).toBe(PartyPlanStatus.ACTIVE);
    });

    test('Case 12: Authorization security checks', async () => {
        // User B cannot cancel User C's request (403)
        const unauthorizedCancel = await request(app)
            .post(`/api/mobile/party-plans/requests/${reqCId}/cancel`)
            .set('Authorization', `Bearer ${userBToken}`)
            .send({ userId: userB.id });
        expect(unauthorizedCancel.status).toBe(403);

        // Non-host (User A) cannot accept requests on host's plan (403)
        const unauthorizedAccept = await request(app)
            .post(`/api/mobile/party-plans/requests/${reqCId}/accept`)
            .set('Authorization', `Bearer ${userAToken}`)
            .send({ userId: userA.id });
        expect(unauthorizedAccept.status).toBe(403);
    });
});
