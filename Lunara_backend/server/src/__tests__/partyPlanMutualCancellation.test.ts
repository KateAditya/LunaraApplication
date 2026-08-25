import request from 'supertest';
import app from '../server';
import User, { UserRole } from '../models/User';
import UserProfile from '../models/UserProfile';
import Venue, { VenueCategory } from '../models/Venue';
import PartyPlan, { PartyPlanStatus, PartyPlanLifecycleStatus, PartyPlanVisibility, PartyPlanPaymentStatus, PartyPlanPaymentType } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus, PartyPlanJoinerPaymentStatus } from '../models/PartyPlanRequest';
import PartyPlanCancellationRequest, { CancellationRequestStatus, CancellationReason } from '../models/PartyPlanCancellationRequest';
import Booking, { BookingStatus, GoingMode } from '../models/Booking';
import Ticket, { TicketStatus } from '../models/Ticket';
import SmartWallet from '../models/SmartWallet';
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

describe('Party Plan Post-Confirmation Mutual Cancellation Flow', () => {
    let host: User;
    let partner: User;
    let stranger: User;
    let venue: Venue;

    let hostToken: string;
    let partnerToken: string;
    let strangerToken: string;

    beforeAll(async () => {
        const ts = Date.now();
        host = await User.create({
            firstName: 'Host',
            lastName: 'Mutual',
            email: `host_mut_${ts}@test.com`,
            phone: '9876543301',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1995-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
            walletBalance: 0,
        });

        await UserProfile.create({
            userId: host.id,
            reliabilityScore: 100,
        });

        partner = await User.create({
            firstName: 'Partner',
            lastName: 'Mutual',
            email: `partner_mut_${ts}@test.com`,
            phone: '9876543302',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1996-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
            walletBalance: 0,
        });

        await UserProfile.create({
            userId: partner.id,
            reliabilityScore: 100,
        });

        stranger = await User.create({
            firstName: 'Stranger',
            lastName: 'Mutual',
            email: `stranger_mut_${ts}@test.com`,
            phone: '9876543303',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1997-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
            walletBalance: 0,
        });

        hostToken = generateAccessToken({ userId: host.id, email: host.email, role: host.role });
        partnerToken = generateAccessToken({ userId: partner.id, email: partner.email, role: partner.role });
        strangerToken = generateAccessToken({ userId: stranger.id, email: stranger.email, role: stranger.role });

        venue = await Venue.create({
            ownerId: host.id,
            name: 'Aura Skybar',
            slug: `aura-skybar-${ts}`,
            addressLine1: 'FC Road',
            city: 'Pune',
            state: 'Maharashtra',
            postalCode: '411004',
            phone: '9876543301',
            capacity: 200,
            openingTime: '18:00:00',
            closingTime: '03:00:00',
            daysOpen: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
            category: VenueCategory.CLUB,
            isActive: true,
        });
    });

    async function createConfirmedPartyPlan(options: { visibility?: PartyPlanVisibility } = {}) {
        const futureDate = new Date();
        futureDate.setDate(futureDate.getDate() + 3); // 3 days in the future (within cancellation window)

        const plan = await PartyPlan.create({
            userId: host.id,
            venueId: venue.id,
            mobileNumber: '9876543301',
            message: 'Mutual cancellation test plan',
            planDateTime: futureDate,
            visibility: options.visibility || PartyPlanVisibility.PUBLIC,
            paymentType: PartyPlanPaymentType.SPLIT,
            depositAmount: 99.00,
            status: PartyPlanStatus.ACTIVE,
            lifecycleStatus: PartyPlanLifecycleStatus.MATCH_CONFIRMED,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            paymentStatus: 'Confirmed',
            isLive: false,
        });

        const reqRecord = await PartyPlanRequest.create({
            planId: plan.id,
            requesterId: partner.id,
            status: PartyPlanRequestStatus.ACCEPTED,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
        });

        await plan.update({ matchedRequestId: reqRecord.id });

        const booking = await Booking.create({
            userId: host.id,
            venueId: venue.id,
            bookingDate: plan.planDateTime,
            startTime: '20:00:00',
            numberOfGuests: 2,
            commissionAmount: 0,
            status: BookingStatus.CONFIRMED,
            goingMode: GoingMode.PLAN,
            totalAmount: 198.00,
        });

        const ticket = await Ticket.create({
            ticketId: `TCK-${Date.now()}-${Math.floor(Math.random() * 1000)}`,
            bookingId: booking.id,
            bookingType: 'party_plan',
            userId: host.id,
            venueId: venue.id,
            ticketStatus: TicketStatus.ACTIVE,
            eventStartAt: futureDate,
            eventEndAt: new Date(futureDate.getTime() + 4 * 3600000),
            expiresAt: new Date(futureDate.getTime() + 4 * 3600000),
            storageDeletionAt: new Date(futureDate.getTime() + 30 * 86400000),
            storageProvider: 'local',
            pdfVersion: 1,
            qrToken: `QR_TEST_${plan.id}`,
            verificationToken: `VERIFY_${plan.id}`,
        });

        return { plan, reqRecord, booking, ticket };
    }

    it('Flow 1: Partner requests cancellation -> Host accepts -> Plan cancelled, refunded, tickets cancelled', async () => {
        const { plan, reqRecord, booking, ticket } = await createConfirmedPartyPlan();

        // 1. Direct cancellation by host on confirmed plan is forbidden
        const directCancelRes = await request(app)
            .post(`/api/mobile/party-plans/${plan.id}/cancel`)
            .set('Authorization', `Bearer ${hostToken}`)
            .send({ userId: host.id });
        expect(directCancelRes.status).toBe(400);
        expect(directCancelRes.body.message).toContain('Direct cancellation is not allowed');

        // 2. Partner requests cancellation
        const cancelReqRes = await request(app)
            .post(`/api/mobile/plans/${plan.id}/cancellation-request`)
            .set('Authorization', `Bearer ${partnerToken}`)
            .send({
                userId: partner.id,
                reason: CancellationReason.MY_PLANS_CHANGED,
            });

        expect(cancelReqRes.status).toBe(201);
        expect(cancelReqRes.body.success).toBe(true);
        const cancellationReqId = cancelReqRes.body.cancellationRequest.id;

        // Plan lifecycle status updated to CANCELLATION_REQUESTED
        const updatedPlan1 = await PartyPlan.findByPk(plan.id);
        expect(updatedPlan1?.lifecycleStatus).toBe(PartyPlanLifecycleStatus.CANCELLATION_REQUESTED);

        // 3. Partner cannot approve/reject their own cancellation request
        const partnerSelfApprove = await request(app)
            .post(`/api/mobile/plans/${plan.id}/cancellation-request/respond`)
            .set('Authorization', `Bearer ${partnerToken}`)
            .send({
                userId: partner.id,
                requestId: cancellationReqId,
                action: 'approve',
            });
        expect(partnerSelfApprove.status).toBe(403);

        // 4. Stranger cannot approve/reject
        const strangerApprove = await request(app)
            .post(`/api/mobile/plans/${plan.id}/cancellation-request/respond`)
            .set('Authorization', `Bearer ${strangerToken}`)
            .send({
                userId: stranger.id,
                requestId: cancellationReqId,
                action: 'approve',
            });
        expect(strangerApprove.status).toBe(403);

        // 5. Host approves cancellation
        const hostApproveRes = await request(app)
            .post(`/api/mobile/plans/${plan.id}/cancellation-request/respond`)
            .set('Authorization', `Bearer ${hostToken}`)
            .send({
                userId: host.id,
                requestId: cancellationReqId,
                action: 'approve',
            });

        expect(hostApproveRes.status).toBe(200);
        expect(hostApproveRes.body.success).toBe(true);

        // Verify final states
        const finalPlan = await PartyPlan.findByPk(plan.id);
        expect(finalPlan?.status).toBe(PartyPlanStatus.CANCELLED);
        expect(finalPlan?.lifecycleStatus).toBe(PartyPlanLifecycleStatus.CANCELLED);
        expect(finalPlan?.paymentStatus).toBe('Refunded');

        const finalReq = await PartyPlanRequest.findByPk(reqRecord.id);
        expect(finalReq?.status).toBe(PartyPlanRequestStatus.CANCELLED);
        expect(finalReq?.joinerPaymentStatus).toBe(PartyPlanJoinerPaymentStatus.REFUNDED);

        const finalBooking = await Booking.findByPk(booking.id);
        expect(finalBooking?.status).toBe(BookingStatus.CANCELLED);

        const finalTicket = await Ticket.findByPk(ticket.id);
        expect(finalTicket?.ticketStatus).toBe(TicketStatus.CANCELLED);
        expect(finalTicket?.qrToken).toContain('VOID_');

        // Check wallet balances: both Host and Partner received ₹99 refund
        const hostWallet = await SmartWallet.findOne({ where: { userId: host.id } });
        expect(Number(hostWallet?.balance)).toBe(99.00);

        const partnerWallet = await SmartWallet.findOne({ where: { userId: partner.id } });
        expect(Number(partnerWallet?.balance)).toBe(99.00);

        // Reliability: Partner (initiator) deducted by 5; Host unaffected
        const partnerProfile = await UserProfile.findOne({ where: { userId: partner.id } });
        expect(partnerProfile?.reliabilityScore).toBe(95);

        const hostProfile = await UserProfile.findOne({ where: { userId: host.id } });
        expect(hostProfile?.reliabilityScore).toBe(100);
    });

    it('Flow 2: Partner requests cancellation -> Host rejects -> Plan remains MATCH_CONFIRMED', async () => {
        const { plan } = await createConfirmedPartyPlan();

        // 1. Partner requests cancellation
        const cancelReqRes = await request(app)
            .post(`/api/mobile/plans/${plan.id}/cancellation-request`)
            .set('Authorization', `Bearer ${partnerToken}`)
            .send({
                userId: partner.id,
                reason: CancellationReason.NOT_AVAILABLE,
            });
        expect(cancelReqRes.status).toBe(201);
        const cancellationReqId = cancelReqRes.body.cancellationRequest.id;

        // 2. Host rejects cancellation
        const hostRejectRes = await request(app)
            .post(`/api/mobile/plans/${plan.id}/cancellation-request/respond`)
            .set('Authorization', `Bearer ${hostToken}`)
            .send({
                userId: host.id,
                requestId: cancellationReqId,
                action: 'reject',
            });

        expect(hostRejectRes.status).toBe(200);
        expect(hostRejectRes.body.success).toBe(true);
        expect(hostRejectRes.body.message).toContain('rejected');

        // Plan remains MATCH_CONFIRMED and ACTIVE
        const finalPlan = await PartyPlan.findByPk(plan.id);
        expect(finalPlan?.status).toBe(PartyPlanStatus.ACTIVE);
        expect(finalPlan?.lifecycleStatus).toBe(PartyPlanLifecycleStatus.MATCH_CONFIRMED);

        const cancellationReq = await PartyPlanCancellationRequest.findByPk(cancellationReqId);
        expect(cancellationReq?.status).toBe(CancellationRequestStatus.REJECTED);
    });

    it('Flow 3: Host requests cancellation -> Partner accepts -> Both refunded, Host reliability deducted', async () => {
        // Reset wallet balances for clean test
        await SmartWallet.update({ balance: 0 }, { where: { userId: [host.id, partner.id] } });
        await User.update({ walletBalance: 0 }, { where: { id: [host.id, partner.id] } });

        const { plan, booking, ticket } = await createConfirmedPartyPlan({ visibility: PartyPlanVisibility.BOTH });

        // 1. Host requests cancellation
        const cancelReqRes = await request(app)
            .post(`/api/mobile/plans/${plan.id}/cancellation-request`)
            .set('Authorization', `Bearer ${hostToken}`)
            .send({
                userId: host.id,
                reason: CancellationReason.VENUE_CHANGED,
            });

        expect(cancelReqRes.status).toBe(201);
        const cancellationReqId = cancelReqRes.body.cancellationRequest.id;
        expect(cancelReqRes.body.cancellationRequest.recipientUserId).toBe(partner.id);

        // 2. Partner accepts cancellation
        const partnerApproveRes = await request(app)
            .post(`/api/mobile/plans/${plan.id}/cancellation-request/respond`)
            .set('Authorization', `Bearer ${partnerToken}`)
            .send({
                userId: partner.id,
                requestId: cancellationReqId,
                action: 'approve',
            });

        expect(partnerApproveRes.status).toBe(200);
        expect(partnerApproveRes.body.success).toBe(true);

        // Verify plan cancelled and ticket cancelled
        const finalPlan = await PartyPlan.findByPk(plan.id);
        expect(finalPlan?.status).toBe(PartyPlanStatus.CANCELLED);
        expect(booking.id).toBeDefined();

        const finalTicket = await Ticket.findByPk(ticket.id);
        expect(finalTicket?.ticketStatus).toBe(TicketStatus.CANCELLED);

        // Wallets refunded
        const hostWallet = await SmartWallet.findOne({ where: { userId: host.id } });
        expect(Number(hostWallet?.balance)).toBe(99.00);

        const partnerWallet = await SmartWallet.findOne({ where: { userId: partner.id } });
        expect(Number(partnerWallet?.balance)).toBe(99.00);

        // Reliability: Host (initiator) deducted by 5 (100 -> 95)
        const hostProfile = await UserProfile.findOne({ where: { userId: host.id } });
        expect(hostProfile?.reliabilityScore).toBe(95);
    });

    it('Flow 4: Host requests cancellation -> Partner rejects -> Plan remains MATCH_CONFIRMED', async () => {
        const { plan } = await createConfirmedPartyPlan();

        // 1. Host requests cancellation
        const cancelReqRes = await request(app)
            .post(`/api/mobile/plans/${plan.id}/cancellation-request`)
            .set('Authorization', `Bearer ${hostToken}`)
            .send({
                userId: host.id,
                reason: CancellationReason.PERSONAL_REASONS,
            });
        expect(cancelReqRes.status).toBe(201);
        const cancellationReqId = cancelReqRes.body.cancellationRequest.id;

        // 2. Partner rejects cancellation
        const partnerRejectRes = await request(app)
            .post(`/api/mobile/plans/${plan.id}/cancellation-request/respond`)
            .set('Authorization', `Bearer ${partnerToken}`)
            .send({
                userId: partner.id,
                requestId: cancellationReqId,
                action: 'reject',
            });

        expect(partnerRejectRes.status).toBe(200);

        // Plan remains MATCH_CONFIRMED
        const finalPlan = await PartyPlan.findByPk(plan.id);
        expect(finalPlan?.lifecycleStatus).toBe(PartyPlanLifecycleStatus.MATCH_CONFIRMED);
    });

    it('Scenario 5: Duplicate cancellation request while one is pending is rejected', async () => {
        const { plan } = await createConfirmedPartyPlan();

        // First request
        const res1 = await request(app)
            .post(`/api/mobile/plans/${plan.id}/cancellation-request`)
            .set('Authorization', `Bearer ${partnerToken}`)
            .send({
                userId: partner.id,
                reason: CancellationReason.MY_PLANS_CHANGED,
            });
        expect(res1.status).toBe(201);

        // Second request attempt while pending
        const res2 = await request(app)
            .post(`/api/mobile/plans/${plan.id}/cancellation-request`)
            .set('Authorization', `Bearer ${partnerToken}`)
            .send({
                userId: partner.id,
                reason: CancellationReason.FOUND_ANOTHER_PLAN,
            });
        expect(res2.status).toBe(400);
        expect(res2.body.message).toContain('already pending');
    });
});
