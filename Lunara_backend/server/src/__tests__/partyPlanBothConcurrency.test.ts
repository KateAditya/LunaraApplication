import request from 'supertest';
import app from '../server';
import User, { UserRole } from '../models/User';
import Venue, { VenueCategory } from '../models/Venue';
import PartyPlan, { PartyPlanStatus, PartyPlanLifecycleStatus, PartyPlanVisibility, PartyPlanPaymentStatus, PartyPlanPaymentType } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus, PartyPlanJoinerPaymentStatus } from '../models/PartyPlanRequest';
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

describe('Party Plan BOTH Visibility — Strict 1-Partner Atomic Concurrency Tests', () => {
    let rahulHost: User;
    let amitPrivate: User;
    let sagarPrivate: User;
    let priyaPublic: User;
    let nehaPublic: User;
    let venue: Venue;

    let rahulToken: string;
    let amitToken: string;
    let sagarToken: string;

    beforeAll(async () => {
        const ts = Date.now();
        rahulHost = await User.create({
            firstName: 'Rahul',
            lastName: 'Host',
            email: `rahul_${ts}@test.com`,
            phone: '9876541101',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1995-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        amitPrivate = await User.create({
            firstName: 'Amit',
            lastName: 'Private',
            email: `amit_${ts}@test.com`,
            phone: '9876541102',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1996-02-02'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        sagarPrivate = await User.create({
            firstName: 'Sagar',
            lastName: 'Private',
            email: `sagar_${ts}@test.com`,
            phone: '9876541103',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1996-03-03'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        priyaPublic = await User.create({
            firstName: 'Priya',
            lastName: 'Public',
            email: `priya_${ts}@test.com`,
            phone: '9876541104',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1997-04-04'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        nehaPublic = await User.create({
            firstName: 'Neha',
            lastName: 'Public',
            email: `neha_${ts}@test.com`,
            phone: '9876541105',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1997-05-05'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        rahulToken = generateAccessToken({ userId: rahulHost.id, email: rahulHost.email, role: rahulHost.role });
        amitToken = generateAccessToken({ userId: amitPrivate.id, email: amitPrivate.email, role: amitPrivate.role });
        sagarToken = generateAccessToken({ userId: sagarPrivate.id, email: sagarPrivate.email, role: sagarPrivate.role });

        venue = await Venue.create({
            ownerId: rahulHost.id,
            name: 'ABC Club',
            slug: `abc-club-${ts}`,
            addressLine1: 'Park Street',
            city: 'Kolkata',
            state: 'West Bengal',
            postalCode: '700016',
            phone: '9876541101',
            capacity: 300,
            openingTime: '19:00:00',
            closingTime: '04:00:00',
            daysOpen: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
            category: VenueCategory.CLUB,
            isActive: true,
        });
    });

    it('simultaneous acceptance race condition: exactly 1 winner, exactly 3 invalidated with PARTNER_ALREADY_SELECTED', async () => {
        const futureDate = new Date();
        futureDate.setDate(futureDate.getDate() + 3);
        futureDate.setHours(20, 0, 0, 0);

        // 1. Rahul creates a Party Plan with visibility = BOTH
        const plan = await PartyPlan.create({
            userId: rahulHost.id,
            venueId: venue.id,
            planDateTime: futureDate,
            message: 'Both Visibility Party',
            visibility: PartyPlanVisibility.BOTH,
            paymentType: PartyPlanPaymentType.SPLIT,
            depositAmount: 99.00,
            mobileNumber: '9876541101',
            status: PartyPlanStatus.ACTIVE,
            lifecycleStatus: PartyPlanLifecycleStatus.HOST_PAYMENT_COMPLETED,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            selectedUsers: [amitPrivate.id, sagarPrivate.id],
            isLive: true,
        });

        // 2. Outbound private invites created for Amit and Sagar
        const reqAmit = await PartyPlanRequest.create({
            planId: plan.id,
            requesterId: amitPrivate.id,
            status: PartyPlanRequestStatus.PENDING,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
        });

        const reqSagar = await PartyPlanRequest.create({
            planId: plan.id,
            requesterId: sagarPrivate.id,
            status: PartyPlanRequestStatus.PENDING,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
        });

        // 3. Public join requests sent by Priya and Neha
        const reqPriya = await PartyPlanRequest.create({
            planId: plan.id,
            requesterId: priyaPublic.id,
            status: PartyPlanRequestStatus.PENDING,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
        });

        const reqNeha = await PartyPlanRequest.create({
            planId: plan.id,
            requesterId: nehaPublic.id,
            status: PartyPlanRequestStatus.PENDING,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
        });

        // 4. Fire all 4 acceptances simultaneously via Promise.all
        // - Amit accepts private invite
        // - Sagar accepts private invite
        // - Rahul approves Priya's public request
        // - Rahul approves Neha's public request
        const results = await Promise.all([
            request(app)
                .post(`/api/mobile/party-plans/requests/${reqAmit.id}/accept-invite`)
                .set('Authorization', `Bearer ${amitToken}`)
                .send({ userId: amitPrivate.id }),

            request(app)
                .post(`/api/mobile/party-plans/requests/${reqSagar.id}/accept-invite`)
                .set('Authorization', `Bearer ${sagarToken}`)
                .send({ userId: sagarPrivate.id }),

            request(app)
                .post(`/api/mobile/party-plans/requests/${reqPriya.id}/accept`)
                .set('Authorization', `Bearer ${rahulToken}`)
                .send({ userId: rahulHost.id }),

            request(app)
                .post(`/api/mobile/party-plans/requests/${reqNeha.id}/accept`)
                .set('Authorization', `Bearer ${rahulToken}`)
                .send({ userId: rahulHost.id }),
        ]);

        const successful = results.filter((r) => r.status === 200);
        const rejected = results.filter((r) => r.status === 409);

        // Exactly 1 winner
        expect(successful.length).toBe(1);
        expect(successful[0].body.success).toBe(true);

        // Exactly 3 rejected with PARTNER_ALREADY_SELECTED
        expect(rejected.length).toBe(3);
        rejected.forEach((r) => {
            expect(r.body.success).toBe(false);
            expect(r.body.code).toBe('PARTNER_ALREADY_SELECTED');
            expect(r.body.message).toBe('This Party Plan is no longer available because another partner has already joined.');
        });

        // Verify Database state
        const refreshedPlan = await PartyPlan.findByPk(plan.id);
        expect(refreshedPlan!.matchedRequestId).not.toBeNull();

        const allReqs = await PartyPlanRequest.findAll({ where: { planId: plan.id } });
        const activeAccepted = allReqs.filter((r) => r.id === refreshedPlan!.matchedRequestId);
        const cancelledCompete = allReqs.filter((r) => r.id !== refreshedPlan!.matchedRequestId);

        expect(activeAccepted.length).toBe(1);
        expect(activeAccepted[0].status).toBe(PartyPlanRequestStatus.PAYMENT_PENDING);

        expect(cancelledCompete.length).toBe(3);
        cancelledCompete.forEach((r) => {
            expect(r.status).toBe(PartyPlanRequestStatus.CANCELLED);
            expect(r.cancellationReason).toBe('partner_already_selected');
        });

        // 5. Subsequent sequential attempt by any user must also be rejected with 409
        const losingReq = cancelledCompete[0];
        const isPublicReq = losingReq.requesterId === priyaPublic.id || losingReq.requesterId === nehaPublic.id;

        const lateAttempt = isPublicReq
            ? await request(app)
                .post(`/api/mobile/party-plans/requests/${losingReq.id}/accept`)
                .set('Authorization', `Bearer ${rahulToken}`)
                .send({ userId: rahulHost.id })
            : await request(app)
                .post(`/api/mobile/party-plans/requests/${losingReq.id}/accept-invite`)
                .set('Authorization', `Bearer ${losingReq.requesterId === amitPrivate.id ? amitToken : sagarToken}`)
                .send({ userId: losingReq.requesterId });

        expect(lateAttempt.status).toBe(409);
        expect(lateAttempt.body.code).toBe('PARTNER_ALREADY_SELECTED');
    });
});
