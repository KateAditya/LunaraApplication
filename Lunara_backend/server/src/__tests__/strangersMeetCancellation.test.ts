import request from 'supertest';
import app from '../server';
import User, { UserRole } from '../models/User';
import Venue, { VenueCategory } from '../models/Venue';
import StrangersMeetRequest, { StrangersMeetStatus, StrangersMeetPaymentStatus } from '../models/StrangersMeetRequest';
import StrangersMeetJoiner, { StrangersMeetJoinerPaymentStatus, StrangersMeetJoinerStatus } from '../models/StrangersMeetJoiner';
import StrangersMeetHostCancellationRequest, { HostCancellationStatus, HostCancellationRefundMethod } from '../models/StrangersMeetHostCancellationRequest';
import StrangersMeetMemberRefund, { MemberRefundStatus } from '../models/StrangersMeetMemberRefund';
import StrangersMeetCancellationRequest, { StrangersMeetCancellationStatus } from '../models/StrangersMeetCancellationRequest';
import Ticket, { TicketStatus, StorageCleanupStatus } from '../models/Ticket';
import SmartWallet from '../models/SmartWallet';
import WalletTransaction, { WalletTransactionType, WalletTransactionStatus } from '../models/WalletTransaction';
import PlanTimeLock from '../models/PlanTimeLock';
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

describe('Strangers Meet Cancellation & Refund Flow', () => {
    let host: User;
    let joiner1: User;
    let joiner2: User;
    let venue: Venue;

    let hostToken: string;

    beforeAll(async () => {
        await PlanTimeLock.destroy({ where: {} });

        const ts = Date.now();
        host = await User.create({
            firstName: 'Host',
            lastName: 'Tester',
            email: `sm_host_${ts}@example.com`,
            phone: `9800${ts.toString().slice(-6)}`,
            passwordHash: 'hashed',
            dateOfBirth: new Date('1995-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });
        hostToken = generateAccessToken({ userId: host.id, email: host.email, role: host.role });

        joiner1 = await User.create({
            firstName: 'Joiner1',
            lastName: 'Tester',
            email: `sm_joiner1_${ts}@example.com`,
            phone: `9801${ts.toString().slice(-6)}`,
            passwordHash: 'hashed',
            dateOfBirth: new Date('1996-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        joiner2 = await User.create({
            firstName: 'Joiner2',
            lastName: 'Tester',
            email: `sm_joiner2_${ts}@example.com`,
            phone: `9802${ts.toString().slice(-6)}`,
            passwordHash: 'hashed',
            dateOfBirth: new Date('1997-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        venue = await Venue.create({
            ownerId: host.id,
            name: 'Test Cancellation Lounge',
            slug: `test-cancel-lounge-${ts}`,
            addressLine1: '456 Party Blvd',
            area: 'Indiranagar',
            city: 'Bangalore',
            state: 'Karnataka',
            postalCode: '560038',
            category: VenueCategory.LOUNGE,
            phone: '9988776655',
            capacity: 50,
            openingTime: '10:00:00',
            closingTime: '23:30:00',
            daysOpen: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
        });
    });

    afterAll(async () => {
        if (venue) await Venue.destroy({ where: { id: venue.id } });
        if (host || joiner1 || joiner2) {
            await User.destroy({ where: { id: [host.id, joiner1.id, joiner2.id] } });
        }
    });

    describe('Scenario A: Participant-Initiated Cancellation and Wallet Refund', () => {
        let meetRequest: StrangersMeetRequest;
        let joinerRecord: StrangersMeetJoiner;
        let ticket: Ticket;

        beforeAll(async () => {
            const eventDate = new Date();
            eventDate.setDate(eventDate.getDate() + 3);
            eventDate.setHours(19, 0, 0, 0);

            meetRequest = await StrangersMeetRequest.create({
                userId: host.id,
                venueId: venue.id,
                subject: 'Participant Cancellation Test',
                tagline: 'Join for test',
                numberOfPersons: 25,
                mobileNumber: '9988776655',
                eventDateTime: eventDate,
                status: StrangersMeetStatus.APPROVED,
                paymentStatus: StrangersMeetPaymentStatus.PAID,
                slotsFilled: 1,
                chargesPerHead: 400.00,
            });

            joinerRecord = await StrangersMeetJoiner.create({
                strangersMeetRequestId: meetRequest.id,
                userId: joiner1.id,
                status: StrangersMeetJoinerStatus.PAID,
                paymentStatus: StrangersMeetJoinerPaymentStatus.PAID,
                paymentAmount: 400.00,
                razorpayPaymentId: 'pay_mock_p1',
            });

            const expiryDate = new Date(eventDate);
            expiryDate.setHours(expiryDate.getHours() + 4);

            ticket = await Ticket.create({
                userId: joiner1.id,
                ticketId: `TKT-${Date.now()}-P1`,
                bookingType: 'strangers_meet',
                bookingId: meetRequest.id,
                ticketStatus: TicketStatus.ACTIVE,
                eventStartAt: eventDate,
                eventEndAt: expiryDate,
                issuedAt: new Date(),
                expiresAt: expiryDate,
                storageDeletionAt: expiryDate,
                storageProvider: 'local',
                pdfVersion: 1,
                qrToken: `qr_${Date.now()}`,
                verificationToken: `vt_${Date.now()}`,
                storageCleanupStatus: StorageCleanupStatus.NOT_REQUIRED,
            });
        });

        it('should process participant cancellation approval, refund to wallet, and cancel ticket', async () => {
            // Joiner requests cancellation
            const cancelReq = await StrangersMeetCancellationRequest.create({
                meetId: meetRequest.id,
                joinerId: joinerRecord.id,
                userId: joiner1.id,
                hostUserId: host.id,
                paidAmount: 400.00,
                reason: 'Sudden scheduling conflict',
                status: StrangersMeetCancellationStatus.PENDING,
            });

            // Host approves cancellation via PATCH route
            const res = await request(app)
                .patch(`/api/mobile/strangers-meet/${meetRequest.id}/joiner-cancel-request/${cancelReq.id}`)
                .set('Authorization', `Bearer ${hostToken}`)
                .send({
                    action: 'accept',
                });

            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);

            // Ticket must be CANCELLED
            const updatedTicket = await Ticket.findByPk(ticket.id);
            expect(updatedTicket?.ticketStatus).toBe(TicketStatus.CANCELLED);

            // Joiner wallet balance must be at least 400.00
            const wallet = await SmartWallet.findOne({ where: { userId: joiner1.id } });
            expect(wallet).toBeDefined();
            expect(Number(wallet?.balance)).toBeGreaterThanOrEqual(400.00);

            // Transaction must be recorded
            const txn = await WalletTransaction.findOne({
                where: {
                    walletId: wallet!.id,
                    transactionType: WalletTransactionType.REFUND,
                    reference: `SM_CANCEL_REFUND_${cancelReq.id}`,
                },
            });
            expect(txn).toBeDefined();
            expect(Number(txn?.amount)).toBe(400.00);
            expect(txn?.status).toBe(WalletTransactionStatus.SUCCESS);

            // Joiner status must be REJECTED
            const updatedJoiner = await StrangersMeetJoiner.findByPk(joinerRecord.id);
            expect(updatedJoiner?.status).toBe(StrangersMeetJoinerStatus.REJECTED);
        });
    });

    describe('Scenario B: Host Cancellation with 0 Paid Participants', () => {
        let meetRequest: StrangersMeetRequest;

        beforeAll(async () => {
            const eventDate = new Date();
            eventDate.setDate(eventDate.getDate() + 4);

            meetRequest = await StrangersMeetRequest.create({
                userId: host.id,
                venueId: venue.id,
                subject: 'Empty Meet Cancellation',
                tagline: 'No members joined',
                numberOfPersons: 25,
                mobileNumber: '9988776655',
                eventDateTime: eventDate,
                status: StrangersMeetStatus.APPROVED,
                paymentStatus: StrangersMeetPaymentStatus.PAID,
                slotsFilled: 0,
                chargesPerHead: 500.00,
            });
        });

        it('should cancel meet cleanly with 0 refunds created', async () => {
            // Host requests cancellation via API
            const reqRes = await request(app)
                .post(`/api/mobile/strangers-meet/${meetRequest.id}/host-cancel-request`)
                .set('Authorization', `Bearer ${hostToken}`)
                .send({
                    reason: 'Host emergency with 0 participants',
                });

            expect(reqRes.status).toBe(200);
            expect(reqRes.body.success).toBe(true);
            const hostCancelId = reqRes.body.data.id;
            expect(Number(reqRes.body.data.totalCollectedAmount)).toBe(0);
            expect(Number(reqRes.body.data.totalMembersCount)).toBe(0);

            // Admin approves host cancellation via Admin API
            const approveRes = await request(app)
                .post(`/api/admin/strangers-meet/cancellations/${hostCancelId}/approve`)
                .send();

            expect(approveRes.status).toBe(200);
            expect(approveRes.body.success).toBe(true);
            expect(approveRes.body.data.status).toBe(HostCancellationStatus.COMPLETED);

            const updatedMeet = await StrangersMeetRequest.findByPk(meetRequest.id);
            expect(updatedMeet?.status).toBe(StrangersMeetStatus.CANCELLED);
        });
    });

    describe('Scenario C & D: Host Cancellation with Paid Members, Idempotency & Exclusion of Already-Refunded', () => {
        let meetRequest: StrangersMeetRequest;
        let paidJoiner: StrangersMeetJoiner;
        let paidTicket: Ticket;
        let hostCancelId: string;

        beforeAll(async () => {
            const eventDate = new Date();
            eventDate.setDate(eventDate.getDate() + 5);

            meetRequest = await StrangersMeetRequest.create({
                userId: host.id,
                venueId: venue.id,
                subject: 'Host Cancellation Multi Member',
                tagline: 'Multi members',
                numberOfPersons: 25,
                mobileNumber: '9988776655',
                eventDateTime: eventDate,
                status: StrangersMeetStatus.APPROVED,
                paymentStatus: StrangersMeetPaymentStatus.PAID,
                slotsFilled: 2,
                chargesPerHead: 350.00,
            });

            // Joiner 2: Active paid participant
            paidJoiner = await StrangersMeetJoiner.create({
                strangersMeetRequestId: meetRequest.id,
                userId: joiner2.id,
                status: StrangersMeetJoinerStatus.PAID,
                paymentStatus: StrangersMeetJoinerPaymentStatus.PAID,
                paymentAmount: 350.00,
                razorpayPaymentId: 'pay_mock_j2',
            });

            const expiryDate = new Date(eventDate);
            expiryDate.setHours(expiryDate.getHours() + 4);

            paidTicket = await Ticket.create({
                userId: joiner2.id,
                ticketId: `TKT-${Date.now()}-J2`,
                bookingType: 'strangers_meet',
                bookingId: meetRequest.id,
                ticketStatus: TicketStatus.ACTIVE,
                eventStartAt: eventDate,
                eventEndAt: expiryDate,
                issuedAt: new Date(),
                expiresAt: expiryDate,
                storageDeletionAt: expiryDate,
                storageProvider: 'local',
                pdfVersion: 1,
                qrToken: `qr_${Date.now()}_j2`,
                verificationToken: `vt_${Date.now()}_j2`,
                storageCleanupStatus: StorageCleanupStatus.NOT_REQUIRED,
            });

            // Joiner 1: Already cancelled/refunded prior to host cancel
            const alreadyRefundedJoiner = await StrangersMeetJoiner.create({
                strangersMeetRequestId: meetRequest.id,
                userId: joiner1.id,
                status: StrangersMeetJoinerStatus.REJECTED,
                paymentStatus: StrangersMeetJoinerPaymentStatus.PAID,
                paymentAmount: 350.00,
                razorpayPaymentId: 'pay_mock_j1_prev',
            });

            await StrangersMeetCancellationRequest.create({
                meetId: meetRequest.id,
                joinerId: alreadyRefundedJoiner.id,
                userId: joiner1.id,
                hostUserId: host.id,
                paidAmount: 350.00,
                reason: 'Pre-cancelled',
                status: StrangersMeetCancellationStatus.APPROVED,
            });
        });

        it('should only compute non-refunded participants in host cancellation request', async () => {
            const reqRes = await request(app)
                .post(`/api/mobile/strangers-meet/${meetRequest.id}/host-cancel-request`)
                .set('Authorization', `Bearer ${hostToken}`)
                .send({
                    reason: 'Host unable to attend multi-member meet',
                });

            expect(reqRes.status).toBe(200);
            expect(reqRes.body.success).toBe(true);
            hostCancelId = reqRes.body.data.id;
            // Only joiner2 is active paid, joiner1 was already refunded
            expect(Number(reqRes.body.data.totalMembersCount)).toBe(1);
            expect(Number(reqRes.body.data.totalCollectedAmount)).toBe(350.00);
        });

        it('should approve host cancellation, refund joiner2, cancel ticket, and be idempotent', async () => {
            const initialWallet = await SmartWallet.findOne({ where: { userId: joiner2.id } });
            const initialBal = Number(initialWallet?.balance || 0);

            const approveRes = await request(app)
                .post(`/api/admin/strangers-meet/cancellations/${hostCancelId}/approve`)
                .send();

            expect(approveRes.status).toBe(200);
            expect(approveRes.body.success).toBe(true);
            expect(approveRes.body.data.status).toBe(HostCancellationStatus.COMPLETED);

            // Verify joiner2 ticket is CANCELLED
            const updatedTicket = await Ticket.findByPk(paidTicket.id);
            expect(updatedTicket?.ticketStatus).toBe(TicketStatus.CANCELLED);

            // Verify joiner2 wallet balance increased by exactly 350.00
            const updatedWallet = await SmartWallet.findOne({ where: { userId: joiner2.id } });
            expect(Number(updatedWallet?.balance)).toBe(initialBal + 350.00);

            // Verify unique transaction exists
            const expectedRef = `SM_HOST_CANCEL_REFUND_${meetRequest.id}_${paidJoiner.id}`;
            const txn = await WalletTransaction.findOne({
                where: {
                    walletId: updatedWallet!.id,
                    reference: expectedRef,
                },
            });
            expect(txn).toBeDefined();
            expect(Number(txn?.amount)).toBe(350.00);

            // IDEMPOTENCY TEST: Calling approve again must not double refund!
            const repeatApprove = await request(app)
                .post(`/api/admin/strangers-meet/cancellations/${hostCancelId}/approve`)
                .send();
            expect(repeatApprove.status).toBe(200);
            expect(repeatApprove.body.data.status).toBe(HostCancellationStatus.COMPLETED);

            // Wallet balance must still be exactly initialBal + 350.00
            const repeatWallet = await SmartWallet.findOne({ where: { userId: joiner2.id } });
            expect(Number(repeatWallet?.balance)).toBe(initialBal + 350.00);

            // Only 1 transaction must exist with that reference
            const txnCount = await WalletTransaction.count({
                where: {
                    walletId: updatedWallet!.id,
                    reference: expectedRef,
                },
            });
            expect(txnCount).toBe(1);
        });
    });

    describe('Scenario E: Admin Member Refund Retry Endpoint', () => {
        let refundRecord: StrangersMeetMemberRefund;
        let hostCancelReq: StrangersMeetHostCancellationRequest;
        let meetRequest: StrangersMeetRequest;
        let joiner: StrangersMeetJoiner;

        beforeAll(async () => {
            const eventDate = new Date();
            eventDate.setDate(eventDate.getDate() + 6);

            meetRequest = await StrangersMeetRequest.create({
                userId: host.id,
                venueId: venue.id,
                subject: 'Retry Refund Test',
                tagline: 'Testing retry',
                numberOfPersons: 25,
                mobileNumber: '9988776655',
                eventDateTime: eventDate,
                status: StrangersMeetStatus.CANCELLED,
                paymentStatus: StrangersMeetPaymentStatus.PAID,
                slotsFilled: 1,
                chargesPerHead: 250.00,
            });

            joiner = await StrangersMeetJoiner.create({
                strangersMeetRequestId: meetRequest.id,
                userId: joiner1.id,
                status: StrangersMeetJoinerStatus.PAID,
                paymentStatus: StrangersMeetJoinerPaymentStatus.PAID,
                paymentAmount: 250.00,
                razorpayPaymentId: 'pay_mock_retry',
            });

            hostCancelReq = await StrangersMeetHostCancellationRequest.create({
                meetId: meetRequest.id,
                hostUserId: host.id,
                reason: 'Need retry test',
                status: HostCancellationStatus.REFUND_PROCESSING,
                totalCollectedAmount: 250.00,
                totalMembersCount: 1,
            });

            // Simulate a pending member refund
            refundRecord = await StrangersMeetMemberRefund.create({
                hostCancellationRequestId: hostCancelReq.id,
                meetId: meetRequest.id,
                joinerId: joiner.id,
                userId: joiner1.id,
                paidAmount: 250.00,
                refundPercentage: 100,
                refundAmount: 250.00,
                refundMethod: HostCancellationRefundMethod.WALLET,
                status: MemberRefundStatus.PENDING,
            });
        });

        it('should retry member wallet refund via admin endpoint successfully', async () => {
            const res = await request(app)
                .post(`/api/admin/strangers-meet/cancellations/member-refunds/${refundRecord.id}/retry-wallet`)
                .send();

            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.status).toBe(MemberRefundStatus.REFUND_PAID);
            expect(res.body.data.walletTransactionId).toBeDefined();

            const updatedRefund = await StrangersMeetMemberRefund.findByPk(refundRecord.id);
            expect(updatedRefund?.status).toBe(MemberRefundStatus.REFUND_PAID);

            // Verify parent cancellation request transitioned to COMPLETED
            const updatedCancel = await StrangersMeetHostCancellationRequest.findByPk(hostCancelReq.id);
            expect(updatedCancel?.status).toBe(HostCancellationStatus.COMPLETED);
        });
    });
});
