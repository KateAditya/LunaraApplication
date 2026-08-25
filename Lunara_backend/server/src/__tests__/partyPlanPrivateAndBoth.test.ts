import request from 'supertest';
import app from '../server';
import User, { UserRole } from '../models/User';
import Venue, { VenueCategory } from '../models/Venue';
import PartyPlan, { PartyPlanStatus, PartyPlanLifecycleStatus, PartyPlanVisibility, PartyPlanPaymentStatus, PartyPlanPaymentType } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus, PartyPlanJoinerPaymentStatus } from '../models/PartyPlanRequest';
import Booking, { GoingMode } from '../models/Booking';
import { generateAccessToken } from '../utils/jwt';

jest.mock('razorpay', () => {
    return jest.fn().mockImplementation(() => {
        return {
            orders: {
                create: jest.fn().mockImplementation((options: any) => {
                    return Promise.resolve({
                        id: `order_mock_${Math.random().toString(36).substring(2, 11)}`,
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

describe('Party Plan PRIVATE and BOTH Flows with Entity Isolation', () => {
    let host: User;
    let userA: User;
    let userB: User;
    let venue: Venue;

    let hostToken: string;
    let userAToken: string;
    let userBToken: string;

    beforeAll(async () => {
        const ts = Date.now();
        host = await User.create({
            firstName: 'Host',
            lastName: 'User',
            email: `host_p_${ts}@test.com`,
            phone: '9876543201',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1995-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        userA = await User.create({
            firstName: 'Invitee',
            lastName: 'Alice',
            email: `invitee_a_${ts}@test.com`,
            phone: '9876543202',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1996-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        userB = await User.create({
            firstName: 'Public',
            lastName: 'Bob',
            email: `public_b_${ts}@test.com`,
            phone: '9876543203',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1997-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        hostToken = generateAccessToken({ userId: host.id, email: host.email, role: host.role });
        userAToken = generateAccessToken({ userId: userA.id, email: userA.email, role: userA.role });
        userBToken = generateAccessToken({ userId: userB.id, email: userB.email, role: userB.role });

        venue = await Venue.create({
            ownerId: host.id,
            name: 'Sahara Lounge',
            slug: `sahara-lounge-${ts}`,
            addressLine1: 'MG Road',
            city: 'Pune',
            state: 'Maharashtra',
            postalCode: '411001',
            phone: '9876543201',
            capacity: 200,
            openingTime: '18:00:00',
            closingTime: '03:00:00',
            daysOpen: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
            category: VenueCategory.CLUB,
            isActive: true,
        });
    });

    it('Scenario 1: PRIVATE Party Plan flow with proper action ownership and GoingMode.PLAN', async () => {
        // 1. Host creates PRIVATE plan
        const futureDate = new Date();
        futureDate.setDate(futureDate.getDate() + 2);
        futureDate.setHours(20, 0, 0, 0);

        const plan = await PartyPlan.create({
            userId: host.id,
            venueId: venue.id,
            planDateTime: futureDate,
            message: 'Private Dinner & Drinks',
            visibility: PartyPlanVisibility.PRIVATE,
            paymentType: PartyPlanPaymentType.SPLIT,
            depositAmount: 99.00,
            mobileNumber: '9876543201',
            status: PartyPlanStatus.ACTIVE,
            lifecycleStatus: PartyPlanLifecycleStatus.HOST_PAYMENT_COMPLETED,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            selectedUsers: [userA.id],
            isLive: false,
        });

        // 2. Automatically dispatch invite on payment verification
        const inviteReq = await PartyPlanRequest.create({
            planId: plan.id,
            requesterId: userA.id,
            status: PartyPlanRequestStatus.PENDING,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
        });

        // 3. Host inspects requests
        const requestsRes = await request(app)
            .get(`/api/mobile/party-plans/${plan.id}/requests?userId=${host.id}`)
            .set('Authorization', `Bearer ${hostToken}`);

        expect(requestsRes.status).toBe(200);
        expect(requestsRes.body.data.length).toBe(1);
        const reqData = requestsRes.body.data[0];
        expect(reqData.isInvite).toBe(true);
        expect(reqData.senderId).toBe(host.id);
        expect(reqData.recipientId).toBe(userA.id);

        // 4. Host cannot accept outbound invite
        const hostAcceptRes = await request(app)
            .post(`/api/mobile/party-plans/requests/${inviteReq.id}/accept`)
            .set('Authorization', `Bearer ${hostToken}`)
            .send({ userId: host.id });
        expect(hostAcceptRes.status).toBe(403);

        // 5. Invitee accepts invite -> transitions to PAYMENT_PENDING
        const acceptInviteRes = await request(app)
            .post(`/api/mobile/party-plans/requests/${inviteReq.id}/accept-invite`)
            .set('Authorization', `Bearer ${userAToken}`)
            .send({ userId: userA.id });

        expect(acceptInviteRes.status).toBe(200);
        const updatedReq = await PartyPlanRequest.findByPk(inviteReq.id);
        expect(updatedReq!.status).toBe(PartyPlanRequestStatus.PAYMENT_PENDING);

        const updatedPlan = await PartyPlan.findByPk(plan.id);
        expect(updatedPlan!.lifecycleStatus).toBe(PartyPlanLifecycleStatus.HOST_PAYMENT_COMPLETED);
        expect(updatedPlan!.matchedRequestId).toBe(inviteReq.id);

        // 6. Invitee completes deposit payment
        const joinerPayRes = await request(app)
            .post(`/api/mobile/party-plans/requests/${inviteReq.id}/joiner-pay`)
            .set('Authorization', `Bearer ${userAToken}`)
            .send({
                userId: userA.id,
                razorpay_order_id: 'order_mock_123',
                razorpay_payment_id: 'pay_mock_123',
                razorpay_signature: 'mock_signature',
            });

        expect(joinerPayRes.status).toBe(200);

        // 7. Verify match is confirmed and Booking has GoingMode.PLAN (never GoingMode.PARTY_REQUEST)
        const confirmedPlan = await PartyPlan.findByPk(plan.id);
        expect(confirmedPlan!.paymentStatus).toBe('Confirmed');

        const booking = await Booking.findOne({
            where: {
                userId: host.id,
                venueId: venue.id,
            },
            order: [['createdAt', 'DESC']],
        });

        expect(booking).not.toBeNull();
        expect(booking!.goingMode).toBe(GoingMode.PLAN);
        expect(booking!.goingMode).not.toBe(GoingMode.PARTY_REQUEST);
        expect(booking!.isGroupBooking).toBe(false);
        expect(booking!.isLargePartyRequest).toBeFalsy();
    });

    it('Scenario 2: BOTH Party Plan supports concurrent public join request and private invite', async () => {
        const futureDate = new Date();
        futureDate.setDate(futureDate.getDate() + 3);
        futureDate.setHours(21, 0, 0, 0);

        // 1. Host creates BOTH plan
        const plan = await PartyPlan.create({
            userId: host.id,
            venueId: venue.id,
            planDateTime: futureDate,
            message: 'Both Private & Public Plan',
            visibility: PartyPlanVisibility.BOTH,
            paymentType: PartyPlanPaymentType.SPLIT,
            depositAmount: 99.00,
            mobileNumber: '9876543201',
            status: PartyPlanStatus.ACTIVE,
            lifecycleStatus: PartyPlanLifecycleStatus.HOST_PAYMENT_COMPLETED,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            selectedUsers: [userA.id],
            isLive: true,
        });

        // 2. Private invite for userA
        const inviteReqA = await PartyPlanRequest.create({
            planId: plan.id,
            requesterId: userA.id,
            status: PartyPlanRequestStatus.PENDING,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
        });

        // 3. Public request from userB
        const publicReqBRes = await request(app)
            .post(`/api/mobile/party-plans/${plan.id}/requests`)
            .set('Authorization', `Bearer ${userBToken}`)
            .send({
                userId: userB.id,
                foodPreference: 'Veg',
                drinkPreference: 'Non-Alcoholic',
            });

        expect(publicReqBRes.status).toBe(201);
        const reqBId = publicReqBRes.body.data.id;

        // 4. Host views all requests
        const requestsRes = await request(app)
            .get(`/api/mobile/party-plans/${plan.id}/requests?userId=${host.id}`)
            .set('Authorization', `Bearer ${hostToken}`);

        expect(requestsRes.status).toBe(200);
        expect(requestsRes.body.data.length).toBe(2);

        const inviteItem = requestsRes.body.data.find((r: any) => r.id === inviteReqA.id);
        const publicItem = requestsRes.body.data.find((r: any) => r.id === reqBId);

        expect(inviteItem.isInvite).toBe(true);
        expect(inviteItem.senderId).toBe(host.id);
        expect(inviteItem.recipientId).toBe(userA.id);

        expect(publicItem.isInvite).toBe(false);
        expect(publicItem.senderId).toBe(userB.id);
        expect(publicItem.recipientId).toBe(host.id);

        // 5. Host approves public request B
        const acceptBRes = await request(app)
            .post(`/api/mobile/party-plans/requests/${reqBId}/accept`)
            .set('Authorization', `Bearer ${hostToken}`)
            .send({ userId: host.id });

        expect(acceptBRes.status).toBe(200);

        // 6. Check that reqB is PAYMENT_PENDING and inviteReqA is marked WAITING
        const updatedReqB = await PartyPlanRequest.findByPk(reqBId);
        const updatedReqA = await PartyPlanRequest.findByPk(inviteReqA.id);

        expect(updatedReqB!.status).toBe(PartyPlanRequestStatus.PAYMENT_PENDING);
        expect(updatedReqA!.status).toBe(PartyPlanRequestStatus.WAITING);
    });
});
