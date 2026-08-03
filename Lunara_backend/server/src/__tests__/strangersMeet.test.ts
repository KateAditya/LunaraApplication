import request from 'supertest';
import app from '../server';
import User, { UserRole } from '../models/User';
import Venue, { VenueCategory } from '../models/Venue';
import StrangersMeetRequest from '../models/StrangersMeetRequest';
import StrangersMeetJoiner, { StrangersMeetJoinerPaymentStatus, StrangersMeetJoinerStatus } from '../models/StrangersMeetJoiner';
import PlanTimeLock from '../models/PlanTimeLock';

jest.mock('razorpay', () => {
    return jest.fn().mockImplementation(() => {
        return {
            orders: {
                create: jest.fn().mockImplementation((options) => {
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

describe('Strangers Meet Workflow Endpoints', () => {
    let hostId = '';
    let joinerId = '';
    let venueId = '';
    let requestId = '';
    let joinerRecordId = '';

    beforeAll(async () => {
        await PlanTimeLock.destroy({ where: {} });

        // Create users
        const host = await User.create({
            firstName: 'Host',
            lastName: 'User',
            email: `host_${Date.now()}@example.com`,
            phone: '7876543210',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1995-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });
        hostId = host.id;

        const joinerUser = await User.create({
            firstName: 'Joiner',
            lastName: 'User',
            email: `joiner_${Date.now()}@example.com`,
            phone: '7876543211',
            passwordHash: 'hashed',
            dateOfBirth: new Date('1997-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });
        joinerId = joinerUser.id;

        // Create venue
        const venue = await Venue.create({
            ownerId: hostId,
            name: 'Test Bar & Grill',
            slug: `test-bar-grill-${Date.now()}`,
            addressLine1: '123 Main St',
            area: 'Downtown',
            city: 'Bangalore',
            state: 'Karnataka',
            postalCode: '560001',
            category: VenueCategory.BAR,
            phone: '1234567890',
            capacity: 100,
            openingTime: '10:00:00',
            closingTime: '23:30:00',
            daysOpen: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
        });
        venueId = venue.id;
    });

    afterAll(async () => {
        // Cleanup
        await PlanTimeLock.destroy({ where: {} });
        await StrangersMeetJoiner.destroy({ where: {} });
        await StrangersMeetRequest.destroy({ where: {} });
        await Venue.destroy({ where: { id: venueId } });
        await User.destroy({ where: { id: [hostId, joinerId] } });
    });

    it('should create a Strangers Meet request and ignore chargesPerHead', async () => {
        const eventDate = new Date();
        eventDate.setDate(eventDate.getDate() + 5); // 5 days in the future
        eventDate.setHours(18, 0, 0, 0); // 6:00 PM (within venue opening hours)

        const res = await request(app)
            .post('/api/mobile/strangers-meet')
            .send({
                userId: hostId,
                venueId,
                subject: 'Weekend Drinks Club',
                tagline: 'Bring good vibes!',
                eventDateTime: eventDate.toISOString(),
                numberOfPersons: 25,
                chargesPerHead: 499.00, // Should be ignored by the controller
                mobileNumber: '7876543210',
            });

        expect(res.status).toBe(201);
        expect(res.body.success).toBe(true);
        expect(res.body.data.status).toBe('pending');
        expect(Number(res.body.data.chargesPerHead)).toBe(0.0); // Verifies chargesPerHead is set to 0 on creation

        requestId = res.body.data.id;
    });

    it('should allow admin to approve a Strangers Meet request and set chargesPerHead', async () => {
        const res = await request(app)
            .patch(`/api/admin/strangers-meet/${requestId}/approve`)
            .send({
                chargesPerHead: 350.00,
                paymentAmount: 99.00,
                adminNotes: 'Approved for Saturday night',
            });

        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.status).toBe('approved');
        expect(Number(res.body.data.chargesPerHead)).toBe(350.00);
        expect(Number(res.body.data.paymentAmount)).toBe(99.00);

        const reqDb = await StrangersMeetRequest.findByPk(requestId);
        expect(Number(reqDb?.chargesPerHead)).toBe(350.00);
        expect(Number(reqDb?.paymentAmount)).toBe(99.00);
    });

    it('should allow host to publish Strangers Meet via deposit payment', async () => {
        // First initiate payment
        const resInit = await request(app)
            .post(`/api/mobile/strangers-meet/${requestId}/initiate-payment`)
            .send({ userId: hostId });

        expect(resInit.status).toBe(200);
        expect(resInit.body.success).toBe(true);
        expect(resInit.body.razorpayOrderId).toBeDefined();

        // Confirm payment
        const resConfirm = await request(app)
            .post(`/api/mobile/strangers-meet/${requestId}/pay`)
            .send({
                userId: hostId,
                razorpay_order_id: resInit.body.razorpayOrderId,
                razorpay_payment_id: 'pay_host_mock_123',
                razorpay_signature: 'mock_signature',
            });

        expect(resConfirm.status).toBe(200);
        expect(resConfirm.body.success).toBe(true);
        expect(resConfirm.body.data.paymentStatus).toBe('paid');

        const reqDb = await StrangersMeetRequest.findByPk(requestId);
        expect(reqDb?.paymentStatus).toBe('paid');
    });

    it('should allow participant to send a join request', async () => {
        const res = await request(app)
            .post(`/api/mobile/strangers-meet/${requestId}/join-request`)
            .send({ userId: joinerId });

        expect(res.status).toBe(201);
        expect(res.body.success).toBe(true);
        expect(res.body.data.status).toBe('pending');

        joinerRecordId = res.body.data.id;
    });

    it('should allow host to accept a join request', async () => {
        const res = await request(app)
            .patch(`/api/mobile/strangers-meet/${requestId}/join-request/${joinerRecordId}`)
            .send({
                userId: hostId,
                action: 'accept',
            });

        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.status).toBe('accepted');
    });

    it('should allow accepted participant to pay and complete join', async () => {
        // Initiate join payment
        const resInit = await request(app)
            .post(`/api/mobile/strangers-meet/${requestId}/join/initiate-payment`)
            .send({ userId: joinerId });

        expect(resInit.status).toBe(200);
        expect(resInit.body.success).toBe(true);

        // Confirm join payment
        const resConfirm = await request(app)
            .post(`/api/mobile/strangers-meet/${requestId}/join/confirm`)
            .send({
                userId: joinerId,
                razorpay_order_id: resInit.body.razorpayOrderId,
                razorpay_payment_id: 'pay_joiner_mock_123',
                razorpay_signature: 'mock_signature',
            });

        expect(resConfirm.status).toBe(200);
        expect(resConfirm.body.success).toBe(true);

        const joinDb = await StrangersMeetJoiner.findByPk(joinerRecordId);
        expect(joinDb?.status).toBe(StrangersMeetJoinerStatus.PAID);
        expect(joinDb?.paymentStatus).toBe(StrangersMeetJoinerPaymentStatus.PAID);

        // Verify slotsFilled has incremented
        const reqDb = await StrangersMeetRequest.findByPk(requestId);
        expect(reqDb?.slotsFilled).toBe(1);
    });

    it('should allow host to request settlement after event date passed', async () => {
        // Fake past event date in database
        const pastDate = new Date();
        pastDate.setDate(pastDate.getDate() - 1);
        await StrangersMeetRequest.update({ eventDateTime: pastDate }, { where: { id: requestId } });

        const res = await request(app)
            .post(`/api/mobile/strangers-meet/${requestId}/settlement-request`)
            .send({
                userId: hostId,
                bankDetails: 'UPI ID: host@upi',
            });

        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.settlementStatus).toBe('requested');
        expect(res.body.data.bankDetails).toBe('UPI ID: host@upi');
    });

    it('should allow admin to pay settlement', async () => {
        const res = await request(app)
            .post(`/api/admin/strangers-meet/${requestId}/pay-settlement`)
            .send({
                transactionId: 'TXN123456789',
                amount: 350.00,
                paymentMethod: 'UPI Payout',
            });

        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.settlementStatus).toBe('paid');
        expect(res.body.data.settlementTransactionId).toBe('TXN123456789');

        const reqDb = await StrangersMeetRequest.findByPk(requestId);
        expect(reqDb?.settlementStatus).toBe('paid');
        expect(reqDb?.settlementTransactionId).toBe('TXN123456789');
    });
});
