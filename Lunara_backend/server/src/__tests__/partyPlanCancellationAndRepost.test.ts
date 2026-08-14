import request from 'supertest';
import app from '../server';
import User, { UserRole } from '../models/User';
import Venue, { VenueCategory } from '../models/Venue';
import PartyPlan, { PartyPlanStatus, PartyPlanLifecycleStatus, PartyPlanVisibility, PartyPlanPaymentStatus, PartyPlanPaymentType } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus } from '../models/PartyPlanRequest';
import WalletTransaction, { WalletTransactionType } from '../models/WalletTransaction';

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

describe('Party Plan Cancellation + Repost Flow Suite', () => {
    let host: User;
    let joiner: User;
    let otherUser: User;
    let venue: Venue;

    beforeAll(async () => {
        const ts = Date.now();
        host = await User.create({
            firstName: 'Aarav',
            lastName: 'Host',
            email: `host_cancel_${ts}@test.com`,
            phone: '9876543220',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1994-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
            walletBalance: 100.00,
        });

        joiner = await User.create({
            firstName: 'Rhea',
            lastName: 'Joiner',
            email: `joiner_cancel_${ts}@test.com`,
            phone: '9876543221',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1996-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
            walletBalance: 50.00,
        });

        otherUser = await User.create({
            firstName: 'Karan',
            lastName: 'Other',
            email: `other_cancel_${ts}@test.com`,
            phone: '9876543222',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1997-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        venue = await Venue.create({
            ownerId: host.id,
            name: 'SinQ Nightclub',
            slug: `sinq-nightclub-${ts}`,
            addressLine1: 'Candolim Road',
            city: 'Goa',
            state: 'Goa',
            postalCode: '403515',
            phone: '9876543220',
            capacity: 300,
            openingTime: '19:00:00',
            closingTime: '04:00:00',
            daysOpen: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
            category: VenueCategory.CLUB,
            isActive: true,
        });
    });

    describe('Scenario A: Host Cancels Party Plan (Cancel & Refund)', () => {
        let planA: PartyPlan;

        beforeAll(async () => {
            const futureDate = new Date(Date.now() + 24 * 60 * 60 * 1000);
            planA = await PartyPlan.create({
                userId: host.id,
                venueId: venue.id,
                planDateTime: futureDate,
                mobileNumber: '9876543220',
                message: "Tonight at SinQ! Let's vibe!",
                visibility: PartyPlanVisibility.PUBLIC,
                paymentType: PartyPlanPaymentType.SPLIT,
                depositAmount: 99.0,
                status: PartyPlanStatus.ACTIVE,
                lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
                isLive: true,
                hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            });
        });

        test('Case 1: Host cancels party plan before any participant joins -> refunded ₹99 idempotently', async () => {
            const initialHostUser = await User.findByPk(host.id);
            const initialBalance = Number(initialHostUser!.walletBalance || 0);

            const cancelRes = await request(app)
                .post(`/api/mobile/party-plans/${planA.id}/cancel`)
                .send({ userId: host.id, reason: 'personal_reasons' });

            expect(cancelRes.status).toBe(200);
            expect(cancelRes.body.success).toBe(true);

            // Plan must be CANCELLED and not live
            const updatedPlan = await PartyPlan.findByPk(planA.id);
            expect(updatedPlan!.status).toBe(PartyPlanStatus.CANCELLED);
            expect(updatedPlan!.lifecycleStatus).toBe(PartyPlanLifecycleStatus.CANCELLED);
            expect(updatedPlan!.isLive).toBe(false);

            // Host wallet should be credited ₹99
            const reloadedHost = await User.findByPk(host.id);
            expect(Number(reloadedHost!.walletBalance)).toBe(initialBalance + 99.00);

            // Verify wallet transaction log exists with unique reference
            const tx = await WalletTransaction.findOne({
                where: {
                    userId: host.id,
                    partyPlanId: planA.id,
                    reference: `REFUND_HOST_CANCEL_${planA.id}`,
                }
            });
            expect(tx).not.toBeNull();
            expect(tx!.transactionType).toBe(WalletTransactionType.REFUND);
        });

        test('Case 2: Repeated cancellation call is idempotent and does NOT duplicate refund', async () => {
            const hostBefore = await User.findByPk(host.id);
            const balanceBefore = Number(hostBefore!.walletBalance);

            const cancelAgainRes = await request(app)
                .post(`/api/mobile/party-plans/${planA.id}/cancel`)
                .send({ userId: host.id });

            expect(cancelAgainRes.status).toBe(200);
            expect(cancelAgainRes.body.success).toBe(true);

            const hostAfter = await User.findByPk(host.id);
            expect(Number(hostAfter!.walletBalance)).toBe(balanceBefore);

            // Transaction count must strictly be 1
            const txCount = await WalletTransaction.count({
                where: {
                    userId: host.id,
                    partyPlanId: planA.id,
                    reference: `REFUND_HOST_CANCEL_${planA.id}`,
                }
            });
            expect(txCount).toBe(1);
        });

        test('Case 3: Joiner cannot request to join a cancelled Party Plan (rejected 400 PARTY_PLAN_NOT_ACTIVE)', async () => {
            const joinRes = await request(app)
                .post(`/api/mobile/party-plans/${planA.id}/requests`)
                .send({ userId: joiner.id });

            expect(joinRes.status).toBe(400);
            expect(joinRes.body.success).toBe(false);
            expect(joinRes.body.code).toBe('PARTY_PLAN_NOT_ACTIVE');
        });
    });

    describe('Scenario B: Host Reposts Party Plan (Repost Flow)', () => {
        let planB: PartyPlan;
        let req1: PartyPlanRequest;

        beforeAll(async () => {
            const futureDate = new Date(Date.now() + 12 * 60 * 60 * 1000);
            planB = await PartyPlan.create({
                userId: host.id,
                venueId: venue.id,
                planDateTime: futureDate,
                mobileNumber: '9876543220',
                message: "Party Plan at SinQ with Aditya!",
                visibility: PartyPlanVisibility.PUBLIC,
                paymentType: PartyPlanPaymentType.SPLIT,
                depositAmount: 99.0,
                status: PartyPlanStatus.ACTIVE,
                lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
                isLive: true,
                hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            });

            // Joiner creates a request before repost
            req1 = await PartyPlanRequest.create({
                planId: planB.id,
                requesterId: joiner.id,
                status: PartyPlanRequestStatus.PENDING,
            });
        });

        test('Case 4: Reposting requires valid future date with lead time (>= 30 mins)', async () => {
            // Past date
            const pastRes = await request(app)
                .post(`/api/mobile/party-plans/${planB.id}/repost`)
                .send({
                    userId: host.id,
                    newDateTime: new Date(Date.now() - 1000).toISOString(),
                });
            expect(pastRes.status).toBe(400);

            // Too close (5 mins)
            const tooCloseRes = await request(app)
                .post(`/api/mobile/party-plans/${planB.id}/repost`)
                .send({
                    userId: host.id,
                    newDateTime: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
                });
            expect(tooCloseRes.status).toBe(400);
            expect(tooCloseRes.body.message).toContain('at least 30 minutes in the future');
        });

        test('Case 5: Non-host cannot repost Party Plan (rejected 403)', async () => {
            const newDate = new Date(Date.now() + 48 * 60 * 60 * 1000);
            const unauthRes = await request(app)
                .post(`/api/mobile/party-plans/${planB.id}/repost`)
                .send({
                    userId: otherUser.id,
                    newDateTime: newDate.toISOString(),
                });
            expect(unauthRes.status).toBe(403);
        });

        test('Case 6: Host reposts Party Plan -> Updates same record in-place, resets schedule, does NOT refund host', async () => {
            const hostBefore = await User.findByPk(host.id);
            const balanceBefore = Number(hostBefore!.walletBalance);

            const newSchedule = new Date(Date.now() + 72 * 60 * 60 * 1000);
            const repostRes = await request(app)
                .post(`/api/mobile/party-plans/${planB.id}/repost`)
                .send({
                    userId: host.id,
                    newDateTime: newSchedule.toISOString(),
                    reason: 'my_plans_changed',
                });

            expect(repostRes.status).toBe(200);
            expect(repostRes.body.success).toBe(true);

            // Reload plan: must have updated planDateTime and remain ACTIVE / isLive: true
            const reloadedPlan = await PartyPlan.findByPk(planB.id);
            expect(new Date(reloadedPlan!.planDateTime).getTime()).toBe(newSchedule.getTime());
            expect(reloadedPlan!.status).toBe(PartyPlanStatus.ACTIVE);
            expect(reloadedPlan!.lifecycleStatus).toBe(PartyPlanLifecycleStatus.POSTED);
            expect(reloadedPlan!.isLive).toBe(true);

            // Host wallet balance must NOT change (no refund on repost)
            const hostAfter = await User.findByPk(host.id);
            expect(Number(hostAfter!.walletBalance)).toBe(balanceBefore);

            // Previous request is cleanly cancelled with reason
            const reloadedReq1 = await PartyPlanRequest.findByPk(req1.id);
            expect(reloadedReq1!.status).toBe(PartyPlanRequestStatus.CANCELLED);
            expect(reloadedReq1!.cancellationReason).toBe('plan_reposted_new_schedule');
        });

        test('Case 7: Users can submit new join requests to the reposted plan with the updated date/time', async () => {
            const newReqRes = await request(app)
                .post(`/api/mobile/party-plans/${planB.id}/requests`)
                .send({ userId: joiner.id });

            expect(newReqRes.status).toBe(201);
            expect(newReqRes.body.success).toBe(true);
            expect(newReqRes.body.data.status).toBe(PartyPlanRequestStatus.PENDING);
        });
    });
});
