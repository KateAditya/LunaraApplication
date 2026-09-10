import { NightPartnerService } from '../services/NightPartnerService';
import NightPartnerRequest, { NightPartnerRequestStatus } from '../models/NightPartnerRequest';
import NightPartnerMatch, { NightPartnerMatchStatus, NightPartnerCancellationStatus } from '../models/NightPartnerMatch';
import Booking, { BookingStatus } from '../models/Booking';
import User from '../models/User';
import Venue from '../models/Venue';
import SmartWallet from '../models/SmartWallet';
import WalletTransaction from '../models/WalletTransaction';

describe('Event Invite, Payment Gating, Concurrency, Cancellation & Refund Master Suite', () => {
    const hostId = '00000000-0000-0000-0000-000000000001';
    const partnerAId = '00000000-0000-0000-0000-000000000002';
    const partnerBId = '00000000-0000-0000-0000-000000000003';
    const venueId = '00000000-0000-0000-0000-000000000010';
    const eventDate = '2026-10-25';

    beforeEach(() => {
        jest.clearAllMocks();
        const { EventTimeLockService } = require('../services/EventTimeLockService');
        jest.spyOn(EventTimeLockService, 'validateFourHourGap').mockResolvedValue({ allowed: true, message: 'OK' } as any);
        jest.spyOn(NightPartnerService as any, 'emitNotification').mockResolvedValue(true as any);
    });

    describe('1. Payment-Gated Invitation Flow (Self Pay vs Split)', () => {
        it('should initiate invite order with correct ticket pricing for SELF_PAY (both tickets)', async () => {
            jest.spyOn(Venue, 'findByPk').mockResolvedValue({ id: venueId, name: 'Club Cyber' } as any);
            const order = await NightPartnerService.initiateInviteOrder(hostId, venueId, eventDate, 'SELF_PAY');

            expect(order).toBeDefined();
            expect(order.amountToPay).toBeGreaterThan(0);
            expect(order.razorpayOrderId).toBeDefined();
        });

        it('should initiate invite order with 50% pricing for SPLIT (one ticket)', async () => {
            jest.spyOn(Venue, 'findByPk').mockResolvedValue({ id: venueId, name: 'Club Cyber' } as any);
            const selfPayOrder = await NightPartnerService.initiateInviteOrder(hostId, venueId, eventDate, 'SELF_PAY');
            const splitOrder = await NightPartnerService.initiateInviteOrder(hostId, venueId, eventDate, 'SPLIT');

            expect(splitOrder.amountToPay).toBe(selfPayOrder.amountToPay / 2);
        });

        it('should create and dispatch invitation only after verified payment', async () => {
            jest.spyOn(Venue, 'findByPk').mockResolvedValue({ id: venueId, name: 'Club Cyber' } as any);
            jest.spyOn(NightPartnerMatch, 'findOne').mockResolvedValue(null);
            jest.spyOn(User, 'findByPk').mockResolvedValue({ id: hostId, firstName: 'HostUser', isVerified: true } as any);

            const mockRequest: any = {
                id: 'req_101',
                hostId,
                partnerId: partnerAId,
                venueId,
                eventDate: new Date(eventDate),
                paymentMode: 'SELF_PAY',
                hostPaid: true,
                hostAmount: 1000,
                status: NightPartnerRequestStatus.PENDING,
                expiresAt: new Date(Date.now() + 86400000),
                update: jest.fn().mockResolvedValue(true),
            };

            jest.spyOn(NightPartnerRequest, 'findOrCreate').mockResolvedValue([mockRequest, true]);

            const createdReq = await NightPartnerService.verifyInvitePaymentAndSend({
                hostId,
                partnerId: partnerAId,
                venueId,
                eventDate,
                paymentMode: 'SELF_PAY',
                razorpayOrderId: 'order_mock_123',
                razorpayPaymentId: 'pay_mock_123',
                razorpaySignature: 'mock_signature',
            });

            expect(createdReq).toBeDefined();
            expect(createdReq.hostPaid).toBe(true);
            expect(createdReq.status).toBe(NightPartnerRequestStatus.PENDING);
        });

        it('should dispatch invitations to multiple selected partners after verified payment', async () => {
            jest.spyOn(Venue, 'findByPk').mockResolvedValue({ id: venueId, name: 'Club Cyber' } as any);
            jest.spyOn(NightPartnerMatch, 'findOne').mockResolvedValue(null);
            jest.spyOn(User, 'findByPk').mockResolvedValue({ id: hostId, firstName: 'HostUser', isVerified: true } as any);

            const createdRequests: any[] = [];
            jest.spyOn(NightPartnerRequest, 'findOrCreate').mockImplementation(((opts: any) => {
                const req = {
                    id: `req_${opts.where.partnerId}`,
                    hostId,
                    partnerId: opts.where.partnerId,
                    venueId,
                    eventDate: new Date(eventDate),
                    paymentMode: 'SELF_PAY',
                    hostPaid: true,
                    hostAmount: 1000,
                    status: NightPartnerRequestStatus.PENDING,
                    expiresAt: new Date(Date.now() + 86400000),
                    update: jest.fn().mockResolvedValue(true),
                };
                createdRequests.push(req);
                return Promise.resolve([req, true]);
            }) as any);

            const partnerIds = [partnerAId, partnerBId];
            const primaryReq = await NightPartnerService.verifyInvitePaymentAndSend({
                hostId,
                partnerIds,
                venueId,
                eventDate,
                paymentMode: 'SELF_PAY',
                razorpayOrderId: 'order_mock_multi',
                razorpayPaymentId: 'pay_mock_multi',
                razorpaySignature: 'mock_signature',
            });

            expect(primaryReq).toBeDefined();
            expect(createdRequests.length).toBe(2);
            expect(createdRequests.map(r => r.partnerId)).toEqual([partnerAId, partnerBId]);
        });
    });

    describe('2. Critical Concurrency Test: 4 Invitations, Concurrent Accepts', () => {
        it('should deterministically allow only ONE partner to claim the slot and fail the other with MATCH_SLOT_FILLED', async () => {
            let confirmedPartner: string | null = null;
            let matchCount = 0;

            const reqA: any = {
                id: 'req_A',
                hostId,
                partnerId: partnerAId,
                venueId,
                eventDate: new Date(eventDate),
                paymentMode: 'SELF_PAY',
                hostPaid: true,
                hostAmount: 1000,
                status: NightPartnerRequestStatus.PENDING,
                expiresAt: new Date(Date.now() + 86400000),
                update: jest.fn().mockImplementation((updates: any) => {
                    reqA.status = updates.status;
                    return Promise.resolve(reqA);
                }),
            };

            const reqB: any = {
                id: 'req_B',
                hostId,
                partnerId: partnerBId,
                venueId,
                eventDate: new Date(eventDate),
                paymentMode: 'SELF_PAY',
                hostPaid: true,
                hostAmount: 1000,
                status: NightPartnerRequestStatus.PENDING,
                expiresAt: new Date(Date.now() + 86400000),
                update: jest.fn().mockImplementation((updates: any) => {
                    reqB.status = updates.status;
                    return Promise.resolve(reqB);
                }),
            };

            jest.spyOn(NightPartnerRequest, 'findByPk').mockImplementation((id: any) => {
                if (id === 'req_A') return Promise.resolve(reqA);
                if (id === 'req_B') return Promise.resolve(reqB);
                return Promise.resolve(null);
            });

            jest.spyOn(NightPartnerMatch, 'findOne').mockImplementation(() => {
                if (confirmedPartner) {
                    return Promise.resolve({ id: 'match_1', hostId, partnerId: confirmedPartner, status: NightPartnerMatchStatus.CONFIRMED } as any);
                }
                return Promise.resolve(null);
            });

            jest.spyOn(NightPartnerMatch, 'create').mockImplementation((data: any) => {
                confirmedPartner = data.partnerId;
                matchCount++;
                return Promise.resolve({ id: 'match_1', ...data } as any);
            });

            jest.spyOn(Booking, 'create').mockResolvedValue({ id: 'booking_1', status: BookingStatus.CONFIRMED } as any);
            jest.spyOn(NightPartnerRequest, 'findAll').mockResolvedValue([]);
            jest.spyOn(Venue, 'findByPk').mockResolvedValue({ id: venueId, name: 'Club Cyber' } as any);
            const Conversation = (require('../models/Conversation')).default;
            jest.spyOn(Conversation, 'findOne').mockResolvedValue(null);
            jest.spyOn(Conversation, 'create').mockResolvedValue({ id: 'conv_1' } as any);

            // Simulate simultaneous acceptance from User A and User B
            const acceptPromiseA = NightPartnerService.respondToRequest('req_A', partnerAId, 'accept');
            const acceptPromiseB = NightPartnerService.respondToRequest('req_B', partnerBId, 'accept');

            const results = await Promise.allSettled([acceptPromiseA, acceptPromiseB]);

            const fulfilled = results.filter(r => r.status === 'fulfilled');
            const rejected = results.filter(r => r.status === 'rejected');

            expect(fulfilled.length).toBe(1);
            expect(rejected.length).toBe(1);
            expect(matchCount).toBe(1);
            expect(confirmedPartner).toBeDefined();

            const rejectionReason = (rejected[0] as PromiseRejectedResult).reason;
            expect(rejectionReason.message).toBe('MATCH_SLOT_FILLED');
        });

        it('should deterministically allow strictly ONE partner when 4 recipients accept concurrently, verified across 100 repeated trials', async () => {
            const partnerIds = [
                '00000000-0000-0000-0000-000000000002',
                '00000000-0000-0000-0000-000000000003',
                '00000000-0000-0000-0000-000000000004',
                '00000000-0000-0000-0000-000000000005',
            ];

            for (let trial = 0; trial < 100; trial++) {
                let activeMatch: any = null;
                let matchCount = 0;

                const requests: Record<string, any> = {};
                for (let i = 0; i < 4; i++) {
                    const pId = partnerIds[i];
                    const rId = `req_${i}_${trial}`;
                    requests[rId] = {
                        id: rId,
                        hostId,
                        partnerId: pId,
                        venueId,
                        eventDate: new Date(eventDate),
                        paymentMode: 'SELF_PAY',
                        hostPaid: true,
                        hostAmount: 1000,
                        status: NightPartnerRequestStatus.PENDING,
                        expiresAt: new Date(Date.now() + 86400000),
                        update: jest.fn().mockImplementation((updates: any) => {
                            requests[rId].status = updates.status;
                            return Promise.resolve(requests[rId]);
                        }),
                    };
                }

                jest.spyOn(NightPartnerRequest, 'findByPk').mockImplementation((id: any) => {
                    return Promise.resolve(requests[id] || null);
                });

                jest.spyOn(NightPartnerMatch, 'findOne').mockImplementation(() => {
                    return Promise.resolve(activeMatch);
                });

                jest.spyOn(NightPartnerMatch, 'create').mockImplementation((data: any) => {
                    matchCount++;
                    activeMatch = { id: `match_${trial}`, ...data, status: NightPartnerMatchStatus.CONFIRMED };
                    return Promise.resolve(activeMatch);
                });

                jest.spyOn(Booking, 'create').mockResolvedValue({ id: `booking_${trial}`, status: BookingStatus.CONFIRMED } as any);
                jest.spyOn(NightPartnerRequest, 'findAll').mockResolvedValue([]);
                jest.spyOn(Venue, 'findByPk').mockResolvedValue({ id: venueId, name: 'Club Cyber' } as any);
                const Conversation = (require('../models/Conversation')).default;
                jest.spyOn(Conversation, 'findOne').mockResolvedValue(null);
                jest.spyOn(Conversation, 'create').mockResolvedValue({ id: `conv_${trial}` } as any);

                // Concurrently trigger accept from all 4 recipients
                const acceptPromises = partnerIds.map((pId, idx) => 
                    NightPartnerService.respondToRequest(`req_${idx}_${trial}`, pId, 'accept')
                );

                const results = await Promise.allSettled(acceptPromises);
                const fulfilled = results.filter(r => r.status === 'fulfilled');
                const rejected = results.filter(r => r.status === 'rejected');

                expect(fulfilled.length).toBe(1);
                expect(rejected.length).toBe(3);
                expect(matchCount).toBe(1);
                expect(activeMatch).toBeDefined();

                // Check that rejected promises have MATCH_SLOT_FILLED
                for (const rej of rejected) {
                    expect((rej as PromiseRejectedResult).reason.message).toBe('MATCH_SLOT_FILLED');
                }
            }
        });
    });

    describe('3. Pending Cancellation (Direct, No Approval) vs Confirmed Cancellation (Mutual)', () => {
        it('should allow host to directly cancel pending invite and refund host wallet without recipient approval', async () => {
            const pendingReq: any = {
                id: 'req_pending',
                hostId,
                partnerId: partnerAId,
                venueId,
                eventDate: new Date(eventDate),
                paymentMode: 'SELF_PAY',
                hostPaid: true,
                hostAmount: 1000,
                status: NightPartnerRequestStatus.PENDING,
                update: jest.fn().mockImplementation((updates) => {
                    pendingReq.status = updates.status;
                    return Promise.resolve(pendingReq);
                }),
            };

            jest.spyOn(NightPartnerRequest, 'findByPk').mockResolvedValue(pendingReq);
            const mockWallet: any = { id: 'wallet_1', userId: hostId, balance: 500, increment: jest.fn().mockResolvedValue(true) };
            jest.spyOn(SmartWallet, 'findOne').mockResolvedValue(mockWallet);
            jest.spyOn(WalletTransaction, 'create').mockResolvedValue({ id: 'tx_1' } as any);

            const result = await NightPartnerService.cancelRequest('req_pending', hostId);

            expect(result).toBe(true);
            expect(pendingReq.status).toBe(NightPartnerRequestStatus.CANCELLED);
            expect(mockWallet.increment).toHaveBeenCalledWith('balance', { by: 1000, transaction: expect.anything() });
        });

        it('should require mutual approval flow for confirmed partner cancellation', async () => {
            const confirmedMatch: any = {
                id: 'match_conf',
                hostId,
                partnerId: partnerAId,
                venueId,
                eventDate: new Date(eventDate),
                status: NightPartnerMatchStatus.CONFIRMED,
                cancellationStatus: NightPartnerCancellationStatus.NONE,
                bookingId: 'booking_1',
                hostPaid: true,
                partnerPaid: false,
                hostAmount: 1000,
                update: jest.fn().mockImplementation((updates) => {
                    Object.assign(confirmedMatch, updates);
                    return Promise.resolve(confirmedMatch);
                }),
            };

            jest.spyOn(NightPartnerMatch, 'findByPk').mockResolvedValue(confirmedMatch);
            jest.spyOn(NightPartnerRequest, 'findByPk').mockResolvedValue(null);

            // Step 1: Host requests cancellation
            const requestResult = await NightPartnerService.cancelUpcomingNight('match_conf', hostId, 'Need to reschedule', 'request');
            expect(requestResult.success).toBe(true);
            expect(confirmedMatch.cancellationStatus).toBe(NightPartnerCancellationStatus.REQUESTED);

            // Step 2: Partner approves cancellation
            const mockWallet: any = { id: 'wallet_1', userId: hostId, balance: 500, increment: jest.fn().mockResolvedValue(true) };
            jest.spyOn(SmartWallet, 'findOne').mockResolvedValue(mockWallet);
            jest.spyOn(WalletTransaction, 'create').mockResolvedValue({ id: 'tx_ref_1' } as any);
            jest.spyOn(Booking, 'findByPk').mockResolvedValue({ id: 'booking_1', update: jest.fn().mockResolvedValue(true) } as any);

            const approveResult = await NightPartnerService.cancelUpcomingNight('match_conf', partnerAId, 'Approved', 'approve');
            expect(approveResult.success).toBe(true);
            expect(confirmedMatch.status).toBe(NightPartnerMatchStatus.CANCELLED);
            expect(confirmedMatch.cancellationStatus).toBe(NightPartnerCancellationStatus.APPROVED);
        });
    });

    describe('4. Refund Idempotency & Precision', () => {
        it('should correctly refund Split payments to host and partner individually without cross-crediting', async () => {
            const splitMatch: any = {
                id: 'match_split',
                hostId,
                partnerId: partnerAId,
                venueId,
                eventDate: new Date(eventDate),
                status: NightPartnerMatchStatus.CONFIRMED,
                cancellationStatus: NightPartnerCancellationStatus.REQUESTED,
                cancelledBy: hostId,
                bookingId: 'booking_split',
                hostPaid: true,
                partnerPaid: true,
                hostAmount: 500,
                partnerAmount: 500,
                update: jest.fn().mockImplementation((updates) => {
                    Object.assign(splitMatch, updates);
                    return Promise.resolve(splitMatch);
                }),
            };

            jest.spyOn(NightPartnerMatch, 'findByPk').mockResolvedValue(splitMatch);
            jest.spyOn(NightPartnerRequest, 'findByPk').mockResolvedValue(null);

            const hostWallet: any = { id: 'w_host', userId: hostId, balance: 100, increment: jest.fn().mockResolvedValue(true) };
            const partnerWallet: any = { id: 'w_partner', userId: partnerAId, balance: 200, increment: jest.fn().mockResolvedValue(true) };

            jest.spyOn(SmartWallet, 'findOne').mockImplementation((opts: any) => {
                if (opts?.where?.userId === hostId) return Promise.resolve(hostWallet);
                if (opts?.where?.userId === partnerAId) return Promise.resolve(partnerWallet);
                return Promise.resolve(null);
            });
            jest.spyOn(WalletTransaction, 'create').mockResolvedValue({ id: 'tx_split' } as any);
            jest.spyOn(Booking, 'findByPk').mockResolvedValue({ id: 'booking_split', update: jest.fn().mockResolvedValue(true) } as any);

            const result = await NightPartnerService.cancelUpcomingNight('match_split', partnerAId, 'Split refund', 'approve');

            expect(result.success).toBe(true);
            expect(hostWallet.increment).toHaveBeenCalledWith('balance', { by: 500, transaction: expect.anything() });
            expect(partnerWallet.increment).toHaveBeenCalledWith('balance', { by: 500, transaction: expect.anything() });
        });
    });
});
