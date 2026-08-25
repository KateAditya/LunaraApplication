import request from 'supertest';
import { Op } from 'sequelize';
import app from '../server';
import User, { UserRole } from '../models/User';
import UserProfile from '../models/UserProfile';
import Venue, { VenueCategory } from '../models/Venue';
import PartyPlan, { PartyPlanStatus, PartyPlanLifecycleStatus, PartyPlanVisibility, PartyPlanPaymentStatus, PartyPlanPaymentType } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus, PartyPlanJoinerPaymentStatus } from '../models/PartyPlanRequest';
import Booking, { GoingMode } from '../models/Booking';
import Ticket, { TicketStatus } from '../models/Ticket';
import { CancellationReason } from '../models/PartyPlanCancellationRequest';
import { generateTicketForBookingHelper } from '../services/ticketService';
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

describe('Ticket Data Consistency Across Live Feed, Ticket Pocket, and All Entry Points', () => {
    let host: User;
    let partner: User;
    let stranger: User;
    let venue: Venue;

    let hostToken: string;
    let partnerToken: string;
    let strangerToken: string;

    let partyPlan: PartyPlan;
    let partyRequest: PartyPlanRequest;
    let booking: Booking;
    let canonicalTicketCode: string;

    beforeAll(async () => {
        const ts = Date.now();
        host = await User.create({
            firstName: 'Host',
            lastName: 'Consistent',
            email: `host_cons_${ts}@test.com`,
            phone: '9876544401',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1995-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
            walletBalance: 0,
        });
        await UserProfile.create({ userId: host.id, reliabilityScore: 100 });

        partner = await User.create({
            firstName: 'Partner',
            lastName: 'Consistent',
            email: `partner_cons_${ts}@test.com`,
            phone: '9876544402',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1996-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
            walletBalance: 0,
        });
        await UserProfile.create({ userId: partner.id, reliabilityScore: 100 });

        stranger = await User.create({
            firstName: 'Stranger',
            lastName: 'Consistent',
            email: `stranger_cons_${ts}@test.com`,
            phone: '9876544403',
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
            name: 'Consistent Lounge',
            slug: `cons-lounge-${ts}`,
            category: VenueCategory.CLUB,
            addressLine1: '100 Consistent Road',
            city: 'Pune',
            state: 'Maharashtra',
            country: 'India',
            postalCode: '411057',
            phone: '9876544401',
            capacity: 200,
            openingTime: '18:00:00',
            closingTime: '03:00:00',
            daysOpen: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
            isActive: true,
        });

        // 1. Create Party Plan
        const futureDate = new Date();
        futureDate.setDate(futureDate.getDate() + 3);

        partyPlan = await PartyPlan.create({
            userId: host.id,
            venueId: venue.id,
            mobileNumber: '9876544401',
            message: 'Consistent ticket test plan',
            planDateTime: futureDate,
            visibility: PartyPlanVisibility.PUBLIC,
            paymentType: PartyPlanPaymentType.SPLIT,
            depositAmount: 99.0,
            status: PartyPlanStatus.ACTIVE,
            lifecycleStatus: PartyPlanLifecycleStatus.HOST_PAYMENT_COMPLETED,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: false,
        });

        // 2. Partner requests to join
        partyRequest = await PartyPlanRequest.create({
            planId: partyPlan.id,
            requesterId: partner.id,
            status: PartyPlanRequestStatus.PENDING,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
        });

        // 3. Host accepts partner
        const acceptRes = await request(app)
            .post(`/api/mobile/party-plans/requests/${partyRequest.id}/accept`)
            .set('Authorization', `Bearer ${hostToken}`)
            .send({ userId: host.id });

        expect(acceptRes.status).toBe(200);

        // 4. Partner completes payment -> Plan confirmed
        const payRes = await request(app)
            .post(`/api/mobile/party-plans/requests/${partyRequest.id}/joiner-pay`)
            .set('Authorization', `Bearer ${partnerToken}`)
            .send({
                userId: partner.id,
                razorpay_order_id: 'order_mock_123',
                razorpay_payment_id: 'pay_mock_123',
                razorpay_signature: 'mock_signature',
            });

        expect(payRes.status).toBe(200);

        // Allow postCommit setImmediate to finish generating Ticket row
        await new Promise(resolve => setTimeout(resolve, 300));

        // Fetch refreshed plan and booking
        await partyPlan.reload();
        booking = (await Booking.findOne({
            where: {
                goingMode: { [Op.in]: [GoingMode.PLAN, GoingMode.PARTY_REQUEST] },
                specialRequests: { [Op.like]: `%"planId":"${partyPlan.id}"%` },
            },
        }))!;

        expect(booking).toBeTruthy();
        expect(booking.ticketCode).toBeTruthy();
        canonicalTicketCode = booking.ticketCode!;

        // Explicitly ensure ticket is generated if background microtask didn't execute in fake timer scope
        let ticketCheck = await Ticket.findOne({ where: { bookingId: booking.id } });
        if (!ticketCheck) {
            await generateTicketForBookingHelper(booking.id);
        }
    });

    test('1. Database has ONE authoritative Ticket record with canonical ticketId matching booking.ticketCode', async () => {
        const ticket = await Ticket.findOne({
            where: { bookingId: booking.id },
        });

        expect(ticket).toBeTruthy();
        expect(ticket!.ticketId).toBe(canonicalTicketCode);
        expect(ticket!.ticketStatus).toBe(TicketStatus.ACTIVE);
    });

    test('2. Ticket Pocket (GET /api/mobile/tickets) returns the EXACT same ticketId for Host and Partner', async () => {
        const hostTicketsRes = await request(app)
            .get('/api/mobile/tickets?tab=all')
            .set('Authorization', `Bearer ${hostToken}`);

        expect(hostTicketsRes.status).toBe(200);
        expect(hostTicketsRes.body.success).toBe(true);

        const hostPartyTickets = hostTicketsRes.body.data.filter((t: any) =>
            t.bookingType === 'party_plan' || t.category === 'party_plan' || t.isPartyPlan === true
        );
        expect(hostPartyTickets.length).toBeGreaterThan(0);
        const hostTicket = hostPartyTickets[0];
        expect(hostTicket.ticketId).toBe(canonicalTicketCode);
        expect(hostTicket.ticketCode).toBe(canonicalTicketCode);
        expect(['active', 'confirmed']).toContain(hostTicket.status?.toLowerCase());

        const partnerTicketsRes = await request(app)
            .get('/api/mobile/tickets?tab=all')
            .set('Authorization', `Bearer ${partnerToken}`);

        expect(partnerTicketsRes.status).toBe(200);
        expect(partnerTicketsRes.body.success).toBe(true);

        const partnerPartyTickets = partnerTicketsRes.body.data.filter((t: any) =>
            t.bookingType === 'party_plan' || t.category === 'party_plan' || t.isPartyPlan === true
        );
        expect(partnerPartyTickets.length).toBeGreaterThan(0);
        const partnerTicket = partnerPartyTickets[0];
        expect(partnerTicket.ticketId).toBe(canonicalTicketCode);
        expect(partnerTicket.ticketCode).toBe(canonicalTicketCode);
        expect(['active', 'confirmed']).toContain(partnerTicket.status?.toLowerCase());

        // Both Host and Partner must receive the EXACT same ticket identity
        expect(partnerTicket.ticketId).toBe(hostTicket.ticketId);
        expect(partnerTicket.ticketCode).toBe(hostTicket.ticketCode);
    });

    test('3. Party Plan ticket API resolves same ticket data for request.id, plan.id, booking.id, and ticketCode', async () => {
        // Fetch via request.id as Host
        const reqTicketHost = await request(app)
            .get(`/api/mobile/party-plans/requests/${partyRequest.id}/ticket`)
            .set('Authorization', `Bearer ${hostToken}`);

        expect(reqTicketHost.status).toBe(200);
        expect(reqTicketHost.body.success).toBe(true);
        expect(reqTicketHost.body.data.ticketCode).toBe(canonicalTicketCode);
        expect(reqTicketHost.body.data.ticketId).toBe(canonicalTicketCode);
        expect(reqTicketHost.body.data.bookingId).toBe(booking.id);

        // Fetch via request.id as Partner
        const reqTicketPartner = await request(app)
            .get(`/api/mobile/party-plans/requests/${partyRequest.id}/ticket`)
            .set('Authorization', `Bearer ${partnerToken}`);

        expect(reqTicketPartner.status).toBe(200);
        expect(reqTicketPartner.body.success).toBe(true);
        expect(reqTicketPartner.body.data.ticketCode).toBe(canonicalTicketCode);

        // Fetch via plan.id as Host
        const planTicketHost = await request(app)
            .get(`/api/mobile/party-plans/requests/${partyPlan.id}/ticket`)
            .set('Authorization', `Bearer ${hostToken}`);

        expect(planTicketHost.status).toBe(200);
        expect(planTicketHost.body.data.ticketCode).toBe(canonicalTicketCode);

        // Fetch via booking.id as Host
        const bookingTicketHost = await request(app)
            .get(`/api/mobile/party-plans/requests/${booking.id}/ticket`)
            .set('Authorization', `Bearer ${hostToken}`);

        expect(bookingTicketHost.status).toBe(200);
        expect(bookingTicketHost.body.data.ticketCode).toBe(canonicalTicketCode);

        // Fetch via ticketCode as Partner
        const codeTicketPartner = await request(app)
            .get(`/api/mobile/party-plans/requests/${canonicalTicketCode}/ticket`)
            .set('Authorization', `Bearer ${partnerToken}`);

        expect(codeTicketPartner.status).toBe(200);
        expect(codeTicketPartner.body.data.ticketCode).toBe(canonicalTicketCode);
    });

    test('4. GET /api/mobile/tickets/:id allows both Host and Partner to fetch ticket metadata by ticketCode and bookingId', async () => {
        // Fetch by ticketCode as Host
        const hostMetaRes = await request(app)
            .get(`/api/mobile/tickets/${canonicalTicketCode}`)
            .set('Authorization', `Bearer ${hostToken}`);

        expect(hostMetaRes.status).toBe(200);
        expect(hostMetaRes.body.success).toBe(true);
        expect(hostMetaRes.body.data.ticketId).toBe(canonicalTicketCode);
        expect(hostMetaRes.body.data.bookingId).toBe(booking.id);

        // Fetch by ticketCode as Partner
        const partnerMetaRes = await request(app)
            .get(`/api/mobile/tickets/${canonicalTicketCode}`)
            .set('Authorization', `Bearer ${partnerToken}`);

        expect(partnerMetaRes.status).toBe(200);
        expect(partnerMetaRes.body.success).toBe(true);
        expect(partnerMetaRes.body.data.ticketId).toBe(canonicalTicketCode);
        expect(partnerMetaRes.body.data.bookingId).toBe(booking.id);

        // Fetch by booking.id as Partner
        const partnerByBookingRes = await request(app)
            .get(`/api/mobile/tickets/${booking.id}`)
            .set('Authorization', `Bearer ${partnerToken}`);

        expect(partnerByBookingRes.status).toBe(200);
        expect(partnerByBookingRes.body.success).toBe(true);
        expect(partnerByBookingRes.body.data.ticketId).toBe(canonicalTicketCode);
    });

    test('5. Non-participant stranger is forbidden (403) from viewing ticket', async () => {
        const strangerTicketRes = await request(app)
            .get(`/api/mobile/party-plans/requests/${partyRequest.id}/ticket`)
            .set('Authorization', `Bearer ${strangerToken}`);

        expect(strangerTicketRes.status).toBe(403);
        expect(strangerTicketRes.body.success).toBe(false);

        const strangerMetaRes = await request(app)
            .get(`/api/mobile/tickets/${canonicalTicketCode}`)
            .set('Authorization', `Bearer ${strangerToken}`);

        expect(strangerMetaRes.status).toBe(403);
        expect(strangerMetaRes.body.success).toBe(false);
    });

    test('6. Mutual cancellation updates ticket status consistently to CANCELLED across all endpoints', async () => {
        // Host initiates cancellation
        const initRes = await request(app)
            .post(`/api/mobile/party-plans/${partyPlan.id}/cancellation-request`)
            .set('Authorization', `Bearer ${hostToken}`)
            .send({
                userId: host.id,
                reason: CancellationReason.PERSONAL_REASONS,
                otherReasonText: 'Personal reasons test'
            });

        expect(initRes.status).toBe(201);
        const cancellationId = initRes.body.cancellationRequest?.id || initRes.body.data?.id;

        // Partner confirms cancellation
        const confirmRes = await request(app)
            .post(`/api/mobile/party-plans/${partyPlan.id}/cancellation-response`)
            .set('Authorization', `Bearer ${partnerToken}`)
            .send({
                userId: partner.id,
                requestId: cancellationId,
                action: 'approve'
            });

        expect(confirmRes.status).toBe(200);

        // Check Party Plan ticket endpoint
        const cancelTicketRes = await request(app)
            .get(`/api/mobile/party-plans/requests/${partyRequest.id}/ticket`)
            .set('Authorization', `Bearer ${hostToken}`);

        expect(cancelTicketRes.status).toBe(200);
        expect(cancelTicketRes.body.data.status).toBe('CANCELLED');

        // Check Ticket Pocket for Host
        const hostPocketRes = await request(app)
            .get('/api/mobile/tickets?tab=all')
            .set('Authorization', `Bearer ${hostToken}`);

        expect(hostPocketRes.status).toBe(200);
        const hostPartyTickets = hostPocketRes.body.data.filter((t: any) =>
            t.ticketId === canonicalTicketCode || t.ticketCode === canonicalTicketCode
        );
        expect(hostPartyTickets.length).toBeGreaterThan(0);
        expect(hostPartyTickets[0].status?.toLowerCase()).toBe('cancelled');

        // Check Ticket Pocket for Partner
        const partnerPocketRes = await request(app)
            .get('/api/mobile/tickets?tab=all')
            .set('Authorization', `Bearer ${partnerToken}`);

        expect(partnerPocketRes.status).toBe(200);
        const partnerPartyTickets = partnerPocketRes.body.data.filter((t: any) =>
            t.ticketId === canonicalTicketCode || t.ticketCode === canonicalTicketCode
        );
        expect(partnerPartyTickets.length).toBeGreaterThan(0);
        expect(partnerPartyTickets[0].status?.toLowerCase()).toBe('cancelled');
    });
});
