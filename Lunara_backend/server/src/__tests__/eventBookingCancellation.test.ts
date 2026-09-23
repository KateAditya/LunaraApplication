import request from 'supertest';
import app from '../server';
import User, { UserRole } from '../models/User';
import UserProfile from '../models/UserProfile';
import Venue, { VenueCategory, VenueStatus } from '../models/Venue';
import Ad from '../models/Ad';
import PartyPlan, { PartyPlanStatus, PartyPlanLifecycleStatus, PartyPlanVisibility, PartyPlanPaymentStatus, PartyPlanPaymentType } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus, PartyPlanJoinerPaymentStatus } from '../models/PartyPlanRequest';
import PartyPlanCancellationRequest, { CancellationRequestStatus, CancellationReason } from '../models/PartyPlanCancellationRequest';
import Booking, { BookingStatus } from '../models/Booking';
import SmartWallet from '../models/SmartWallet';
import { EventSeatService } from '../services/EventSeatService';
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

describe('Event Booking / Upcoming Night Party Plan Cancellation & Refund Suite', () => {
    let host: User;
    let joiner: User;
    let venue: Venue;
    let eventAd: Ad;
    let hostToken: string;
    let joinerToken: string;

    beforeAll(async () => {
        const ts = Date.now();
        host = await User.create({
            firstName: 'EventHost',
            lastName: 'User',
            email: `event_host_${ts}@test.com`,
            phone: `987654${Math.floor(1000 + Math.random() * 9000)}`,
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

        joiner = await User.create({
            firstName: 'EventJoiner',
            lastName: 'User',
            email: `event_joiner_${ts}@test.com`,
            phone: `987655${Math.floor(1000 + Math.random() * 9000)}`,
            passwordHash: 'hashed',
            dateOfBirth: new Date('1996-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
            walletBalance: 0,
        });

        await UserProfile.create({
            userId: joiner.id,
            reliabilityScore: 100,
        });

        hostToken = generateAccessToken({ userId: host.id, email: host.email, role: host.role });
        joinerToken = generateAccessToken({ userId: joiner.id, email: joiner.email, role: joiner.role });

        venue = await Venue.create({
            ownerId: host.id,
            name: 'Favela ONYX',
            slug: `favela-onyx-${ts}`,
            addressLine1: 'Hinjawadi, Pune',
            city: 'Pune',
            state: 'Maharashtra',
            country: 'India',
            postalCode: '411057',
            phone: '9876544001',
            category: VenueCategory.CLUB,
            status: VenueStatus.APPROVED,
            isActive: true,
            displayOrder: 1,
            capacity: 200,
        } as any);

        eventAd = await Ad.create({
            venueId: venue.id,
            city: 'Pune',
            area: 'Hinjawadi',
            type: 'Party',
            title: 'Velvet Nights Party',
            imagePath: '/uploads/velvet.jpg',
            fromDate: new Date(),
            toDate: new Date(Date.now() + 14 * 24 * 60 * 60 * 1000),
            isActive: true,
            socialLinks: [],
            entryPrice: 500.0,
            seatLimit: 50,
            isUnlimited: false,
            filledSeats: 0,
            eventDate: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
        });
    });

    beforeEach(async () => {
        // Reset wallet balances before each test
        await SmartWallet.update({ balance: 0 }, { where: { userId: [host.id, joiner.id] } });
        await User.update({ walletBalance: 0 }, { where: { id: [host.id, joiner.id] } });
    });

    it('1. Unmatched Event Plan: Host self-pays 2 seats (₹1000) -> Cancels plan -> Full ₹1000 refunded & seats released', async () => {
        await eventAd.reload();
        const initialBooked = eventAd.filledSeats || 0;

        // Reserve 2 seats
        await EventSeatService.reserve(eventAd.id, 2);
        await eventAd.reload();
        expect(eventAd.filledSeats).toBe(initialBooked + 2);

        // 1. Create self-pay event plan
        const plan = await PartyPlan.create({
            userId: host.id,
            venueId: venue.id,
            partyEventId: eventAd.id,
            eventSeatsReserved: 2,
            message: 'Looking for a party partner for Velvet Nights!',
            planDateTime: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
            status: PartyPlanStatus.ACTIVE,
            lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
            visibility: PartyPlanVisibility.PUBLIC,
            paymentType: PartyPlanPaymentType.SELF_PAY,
            depositAmount: 500.0,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
            mobileNumber: '9876544001',
            showProfilePhoto: true,
            showHostName: true,
            showVenueDetails: true,
            showDateDetails: true,
            hostArrivalConfirmed: false,
            reminder24hSent: false,
            reminder3hSent: false,
            reminder1hSent: false,
            reminder30mSent: false,
            reminder2hSent: false,
            reminder20mSent: false,
            reminder10mSent: false,
            reminder5mSent: false,
            reminderOnTimeSent: false,
            reminderPost5mSent: false,
            reminderPost10mSent: false,
            reminderPost30mSent: false,
            expiredNoShowCancelled: false,
        });

        // 2. Host cancels the unmatched plan
        const cancelRes = await request(app)
            .post(`/api/mobile/party-plans/${plan.id}/cancel`)
            .set('Authorization', `Bearer ${hostToken}`)
            .send({ userId: host.id, reason: 'Plans changed' });

        expect(cancelRes.status).toBe(200);
        expect(cancelRes.body.success).toBe(true);

        // 3. Verify plan is cancelled
        const updatedPlan = await PartyPlan.findByPk(plan.id);
        expect(updatedPlan?.status).toBe(PartyPlanStatus.CANCELLED);
        expect(updatedPlan?.lifecycleStatus).toBe(PartyPlanLifecycleStatus.CANCELLED);
        expect(updatedPlan?.isLive).toBe(false);

        // 4. Verify host wallet received refund for both tickets per EVENT_BOOKING policy
        // Policy: 80% refund → 2 × ₹500 × 80% = ₹800
        const hostWallet = await SmartWallet.findOne({ where: { userId: host.id } });
        expect(Number(hostWallet?.balance)).toBe(800.0);

        // 5. Verify event seats released back
        await eventAd.reload();
        expect(eventAd.filledSeats).toBe(initialBooked);
    });

    it('2. Unmatched Event Plan: Host chooses "Go Solo" -> Converts to 1-person booking & refunds 1 unused seat (₹500)', async () => {
        await eventAd.reload();
        const initialBooked = eventAd.filledSeats || 0;

        // Reserve 2 seats
        await EventSeatService.reserve(eventAd.id, 2);
        await eventAd.reload();
        expect(eventAd.filledSeats).toBe(initialBooked + 2);

        // 1. Create self-pay event plan (holding 2 seats)
        const plan = await PartyPlan.create({
            userId: host.id,
            venueId: venue.id,
            partyEventId: eventAd.id,
            eventSeatsReserved: 2,
            message: 'Looking for a party partner for Velvet Nights!',
            planDateTime: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
            status: PartyPlanStatus.ACTIVE,
            lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
            visibility: PartyPlanVisibility.PUBLIC,
            paymentType: PartyPlanPaymentType.SELF_PAY,
            depositAmount: 500.0,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
            mobileNumber: '9876544001',
            showProfilePhoto: true,
            showHostName: true,
            showVenueDetails: true,
            showDateDetails: true,
            hostArrivalConfirmed: false,
            reminder24hSent: false,
            reminder3hSent: false,
            reminder1hSent: false,
            reminder30mSent: false,
            reminder2hSent: false,
            reminder20mSent: false,
            reminder10mSent: false,
            reminder5mSent: false,
            reminderOnTimeSent: false,
            reminderPost5mSent: false,
            reminderPost10mSent: false,
            reminderPost30mSent: false,
            expiredNoShowCancelled: false,
            eventNoMatchNotifiedAt: new Date(Date.now() - 3600000),
        });

        // 2. Host responds with "solo" action
        const soloRes = await request(app)
            .post(`/api/mobile/party-plans/${plan.id}/no-match-response`)
            .set('Authorization', `Bearer ${hostToken}`)
            .send({ action: 'solo' });

        expect(soloRes.status).toBe(200);
        expect(soloRes.body.success).toBe(true);
        expect(soloRes.body.data.bookingId).toBeDefined();
        expect(soloRes.body.data.refundAmount).toBe(500.0);

        // 3. Verify plan updated to completed/inactive
        const updatedPlan = await PartyPlan.findByPk(plan.id);
        expect(updatedPlan?.status).toBe(PartyPlanStatus.INACTIVE);
        expect(updatedPlan?.lifecycleStatus).toBe(PartyPlanLifecycleStatus.COMPLETED);
        expect(updatedPlan?.isLive).toBe(false);

        // 4. Verify solo booking created for host
        const booking = await Booking.findByPk(soloRes.body.data.bookingId);
        expect(booking?.userId).toBe(host.id);
        expect(booking?.partyEventId).toBe(eventAd.id);
        expect(booking?.numberOfGuests).toBe(1);
        expect(booking?.status).toBe(BookingStatus.CONFIRMED);

        // 5. Verify 1 unused ticket (₹500) refunded to host wallet
        const hostWallet = await SmartWallet.findOne({ where: { userId: host.id } });
        expect(Number(hostWallet?.balance)).toBe(500.0);

        // 6. Verify 1 seat released back to event capacity (1 kept for solo host)
        await eventAd.reload();
        expect(eventAd.filledSeats).toBe(initialBooked + 1);
    });

    it('3. Matched Event Plan: Host & Joiner matched on split plan -> Mutual cancellation approved -> Both refunded ₹500', async () => {
        // 1. Create split event plan
        const plan = await PartyPlan.create({
            userId: host.id,
            venueId: venue.id,
            partyEventId: eventAd.id,
            eventSeatsReserved: 2,
            message: 'Looking for a split partner for Velvet Nights!',
            planDateTime: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
            status: PartyPlanStatus.ACTIVE,
            lifecycleStatus: PartyPlanLifecycleStatus.MATCH_CONFIRMED,
            visibility: PartyPlanVisibility.PUBLIC,
            paymentType: PartyPlanPaymentType.SPLIT,
            depositAmount: 500.0,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
            mobileNumber: '9876544001',
            showProfilePhoto: true,
            showHostName: true,
            showVenueDetails: true,
            showDateDetails: true,
            hostArrivalConfirmed: false,
            reminder24hSent: false,
            reminder3hSent: false,
            reminder1hSent: false,
            reminder30mSent: false,
            reminder2hSent: false,
            reminder20mSent: false,
            reminder10mSent: false,
            reminder5mSent: false,
            reminderOnTimeSent: false,
            reminderPost5mSent: false,
            reminderPost10mSent: false,
            reminderPost30mSent: false,
            expiredNoShowCancelled: false,
        });

        // 2. Joiner request matched & paid
        const joinRequest = await PartyPlanRequest.create({
            planId: plan.id,
            requesterId: joiner.id,
            status: PartyPlanRequestStatus.ACCEPTED,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
            latLangCheckIn: false,
        });

        await plan.update({ matchedRequestId: joinRequest.id });

        // 3. Joiner requests mutual cancellation
        const cancelReqRes = await request(app)
            .post(`/api/mobile/plans/${plan.id}/cancellation-request`)
            .set('Authorization', `Bearer ${joinerToken}`)
            .send({
                userId: joiner.id,
                reason: CancellationReason.MY_PLANS_CHANGED,
            });

        expect(cancelReqRes.status).toBe(201);
        const cancellationReqId = cancelReqRes.body.cancellationRequest.id;

        // 4. Host approves cancellation
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

        // 5. Verify plan is cancelled
        const finalPlan = await PartyPlan.findByPk(plan.id);
        expect(finalPlan?.status).toBe(PartyPlanStatus.CANCELLED);
        expect(finalPlan?.lifecycleStatus).toBe(PartyPlanLifecycleStatus.CANCELLED);

        // 6. Verify joiner request status updated
        const finalJoinReq = await PartyPlanRequest.findByPk(joinRequest.id);
        expect(finalJoinReq?.status).toBe(PartyPlanRequestStatus.CANCELLED);
        expect(finalJoinReq?.joinerPaymentStatus).toBe(PartyPlanJoinerPaymentStatus.REFUNDED);

        // 7. Verify both Host and Joiner received their ₹500 refunds in wallet
        const hostWallet = await SmartWallet.findOne({ where: { userId: host.id } });
        expect(Number(hostWallet?.balance)).toBe(500.0);

        const joinerWallet = await SmartWallet.findOne({ where: { userId: joiner.id } });
        expect(Number(joinerWallet?.balance)).toBe(500.0);
    });

    it('4. Matched Event Plan: Joiner requests cancellation -> Host rejects -> Plan stays active & confirmed', async () => {
        // 1. Create matched split plan
        const plan = await PartyPlan.create({
            userId: host.id,
            venueId: venue.id,
            partyEventId: eventAd.id,
            eventSeatsReserved: 2,
            message: 'Looking for a split partner!',
            planDateTime: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
            status: PartyPlanStatus.ACTIVE,
            lifecycleStatus: PartyPlanLifecycleStatus.MATCH_CONFIRMED,
            visibility: PartyPlanVisibility.PUBLIC,
            paymentType: PartyPlanPaymentType.SPLIT,
            depositAmount: 500.0,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
            mobileNumber: '9876544001',
            showProfilePhoto: true,
            showHostName: true,
            showVenueDetails: true,
            showDateDetails: true,
            hostArrivalConfirmed: false,
            reminder24hSent: false,
            reminder3hSent: false,
            reminder1hSent: false,
            reminder30mSent: false,
            reminder2hSent: false,
            reminder20mSent: false,
            reminder10mSent: false,
            reminder5mSent: false,
            reminderOnTimeSent: false,
            reminderPost5mSent: false,
            reminderPost10mSent: false,
            reminderPost30mSent: false,
            expiredNoShowCancelled: false,
        });

        const joinRequest = await PartyPlanRequest.create({
            planId: plan.id,
            requesterId: joiner.id,
            status: PartyPlanRequestStatus.ACCEPTED,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
            latLangCheckIn: false,
        });

        await plan.update({ matchedRequestId: joinRequest.id });

        // 2. Joiner initiates cancellation request
        const cancelReqRes = await request(app)
            .post(`/api/mobile/plans/${plan.id}/cancellation-request`)
            .set('Authorization', `Bearer ${joinerToken}`)
            .send({
                userId: joiner.id,
                reason: CancellationReason.NOT_AVAILABLE,
            });

        expect(cancelReqRes.status).toBe(201);
        const cancellationReqId = cancelReqRes.body.cancellationRequest.id;

        // 3. Host rejects cancellation
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

        // 4. Verify plan remains MATCH_CONFIRMED and ACTIVE
        const finalPlan = await PartyPlan.findByPk(plan.id);
        expect(finalPlan?.status).toBe(PartyPlanStatus.ACTIVE);
        expect(finalPlan?.lifecycleStatus).toBe(PartyPlanLifecycleStatus.MATCH_CONFIRMED);

        const cancellationReq = await PartyPlanCancellationRequest.findByPk(cancellationReqId);
        expect(cancellationReq?.status).toBe(CancellationRequestStatus.REJECTED);
    });
});
