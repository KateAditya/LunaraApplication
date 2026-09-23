import { verifyInvitePaymentAndSend, sendPartnerRequest } from '../controllers/mobileNightPartnerController';
import { NightPartnerService } from '../services/NightPartnerService';
import { NightPartnerRequestStatus } from '../models/NightPartnerRequest';
import User from '../models/User';

describe('Upcoming Night Flow - Notification Timing & Controller Decoupling Suite', () => {
    const hostId = '00000000-0000-0000-0000-000000000001';
    const partnerId1 = '00000000-0000-0000-0000-000000000002';
    const partnerId2 = '00000000-0000-0000-0000-000000000003';
    const venueId = '00000000-0000-0000-0000-000000000010';
    const eventDate = '2026-11-15';
    const eventTime = '21:00';

    beforeEach(() => {
        jest.clearAllMocks();
    });

    describe('1. Controller verifyInvitePaymentAndSend - Immediate Response & Decoupled Notification', () => {
        it('should return 201 HTTP response to host and asynchronously trigger dispatchInviteNotifications', async () => {
            const mockRequestData = {
                id: 'req_101',
                hostId,
                partnerId: partnerId1,
                venueId,
                eventDate: new Date(eventDate),
                paymentMode: 'SELF_PAY',
                status: NightPartnerRequestStatus.PENDING,
            };

            const mockServiceResult = {
                request: mockRequestData,
                allRequests: [
                    mockRequestData,
                    { ...mockRequestData, id: 'req_102', partnerId: partnerId2 },
                ],
                venue: { id: venueId, name: 'Skybar Club' },
                hostId,
                eventDate,
                eventTime,
                paymentMode: 'SELF_PAY',
            };

            jest.spyOn(NightPartnerService, 'verifyInvitePaymentAndSend').mockResolvedValue(mockServiceResult as any);
            const dispatchSpy = jest.spyOn(NightPartnerService, 'dispatchInviteNotifications').mockResolvedValue(undefined);

            const req: any = {
                user: { id: hostId },
                body: {
                    partnerIds: [partnerId1, partnerId2],
                    venueId,
                    eventDate,
                    eventTime,
                    paymentMode: 'SELF_PAY',
                    razorpayOrderId: 'order_123',
                    razorpayPaymentId: 'pay_123',
                    razorpaySignature: 'sig_123',
                },
            };

            let statusCode = 0;
            let responseJson: any = null;
            const res: any = {
                status: (code: number) => {
                    statusCode = code;
                    return res;
                },
                json: (data: any) => {
                    responseJson = data;
                    return res;
                },
            };

            await verifyInvitePaymentAndSend(req, res);

            // Verify HTTP Response sent synchronously
            expect(statusCode).toBe(201);
            expect(responseJson.success).toBe(true);
            expect(responseJson.data).toEqual(mockRequestData);

            // Verify notification dispatch called with correct payload
            expect(dispatchSpy).toHaveBeenCalledTimes(1);
            expect(dispatchSpy).toHaveBeenCalledWith({
                requests: mockServiceResult.allRequests,
                hostId,
                venue: mockServiceResult.venue,
                eventDate,
                eventTime,
                paymentMode: 'SELF_PAY',
            });
        });

        it('should reject with 400 if required parameters are missing and NOT call dispatch', async () => {
            const dispatchSpy = jest.spyOn(NightPartnerService, 'dispatchInviteNotifications').mockResolvedValue(undefined);

            const req: any = {
                user: { id: hostId },
                body: {
                    // missing partnerIds and venueId
                    eventDate,
                },
            };

            let statusCode = 0;
            let responseJson: any = null;
            const res: any = {
                status: (code: number) => {
                    statusCode = code;
                    return res;
                },
                json: (data: any) => {
                    responseJson = data;
                    return res;
                },
            };

            await verifyInvitePaymentAndSend(req, res);

            expect(statusCode).toBe(400);
            expect(responseJson.success).toBe(false);
            expect(dispatchSpy).not.toHaveBeenCalled();
        });

        it('should return 400 error on FOUR_HOUR_TIME_LOCK without dispatching notifications', async () => {
            const timeLockError: any = new Error('FOUR_HOUR_TIME_LOCK');
            timeLockError.code = 'FOUR_HOUR_TIME_LOCK';
            timeLockError.timeLock = {
                lockedUntil: '2026-11-15T23:00:00.000Z',
                existingEvent: 'Dinner with Sarah',
            };

            jest.spyOn(NightPartnerService, 'verifyInvitePaymentAndSend').mockRejectedValue(timeLockError);
            const dispatchSpy = jest.spyOn(NightPartnerService, 'dispatchInviteNotifications').mockResolvedValue(undefined);

            const req: any = {
                user: { id: hostId },
                body: {
                    partnerId: partnerId1,
                    venueId,
                    eventDate,
                    eventTime,
                    paymentMode: 'SELF_PAY',
                    razorpayOrderId: 'order_123',
                    razorpayPaymentId: 'pay_123',
                    razorpaySignature: 'sig_123',
                },
            };

            let statusCode = 0;
            let responseJson: any = null;
            const res: any = {
                status: (code: number) => {
                    statusCode = code;
                    return res;
                },
                json: (data: any) => {
                    responseJson = data;
                    return res;
                },
            };

            await verifyInvitePaymentAndSend(req, res);

            expect(statusCode).toBe(400);
            expect(responseJson.success).toBe(false);
            expect(responseJson.code).toBe('FOUR_HOUR_TIME_LOCK');
            expect(responseJson.lockedUntil).toBe('2026-11-15T23:00:00.000Z');
            expect(dispatchSpy).not.toHaveBeenCalled();
        });
    });

    describe('2. Controller sendPartnerRequest - Immediate Response & Decoupled Notification', () => {
        it('should return 201 HTTP response to host and asynchronously trigger dispatchPartnerRequestNotification', async () => {
            const mockRequestData = {
                id: 'req_201',
                hostId,
                partnerId: partnerId1,
                venueId,
                eventDate: new Date(eventDate),
                paymentMode: 'SELF_PAY',
                status: NightPartnerRequestStatus.PENDING,
            };

            const mockServiceResult = {
                request: mockRequestData,
                venue: { id: venueId, name: 'Dragonfly Lounge' },
                hostId,
                partnerId: partnerId1,
                eventDate,
                eventTime,
            };

            jest.spyOn(NightPartnerService, 'sendPartnerRequest').mockResolvedValue(mockServiceResult as any);
            const dispatchSpy = jest.spyOn(NightPartnerService, 'dispatchPartnerRequestNotification').mockResolvedValue(undefined);

            const req: any = {
                user: { id: hostId },
                body: {
                    partnerId: partnerId1,
                    venueId,
                    eventDate,
                    eventTime,
                    paymentMode: 'SELF_PAY',
                },
            };

            let statusCode = 0;
            let responseJson: any = null;
            const res: any = {
                status: (code: number) => {
                    statusCode = code;
                    return res;
                },
                json: (data: any) => {
                    responseJson = data;
                    return res;
                },
            };

            await sendPartnerRequest(req, res);

            expect(statusCode).toBe(201);
            expect(responseJson.success).toBe(true);
            expect(responseJson.data).toEqual(mockRequestData);

            expect(dispatchSpy).toHaveBeenCalledTimes(1);
            expect(dispatchSpy).toHaveBeenCalledWith({
                request: mockRequestData,
                hostId,
                partnerId: partnerId1,
                venue: mockServiceResult.venue,
                eventDate,
                eventTime,
            });
        });
    });

    describe('3. Service Dispatch Methods - Payload Construction & Delivery', () => {
        it('dispatchInviteNotifications should emit PARTNER_REQUEST_SENT notification for all invitees', async () => {
            const emitSpy = jest.spyOn(NightPartnerService as any, 'emitNotification').mockResolvedValue(true as any);
            jest.spyOn(User, 'findByPk').mockResolvedValue({
                id: hostId,
                firstName: 'Alex',
                lastName: 'V',
                isVerified: true,
                photos: [{ isPrimary: true, filePath: 'https://img.lunara.app/alex.jpg' }],
            } as any);

            const mockRequests: any[] = [
                { id: 'req_1', partnerId: partnerId1, eventTime: '20:00' },
                { id: 'req_2', partnerId: partnerId2, eventTime: '20:00' },
            ];

            await NightPartnerService.dispatchInviteNotifications({
                requests: mockRequests,
                hostId,
                venue: { id: venueId, name: 'Club Velvet' } as any,
                eventDate: '2026-11-15',
                eventTime: '20:00',
                paymentMode: 'SELF_PAY',
            });

            expect(emitSpy).toHaveBeenCalledTimes(2);
            expect(emitSpy).toHaveBeenNthCalledWith(1, partnerId1, expect.objectContaining({
                type: 'PARTNER_REQUEST_SENT',
                actorUserId: hostId,
                title: 'Invite for Party Event 🌙',
                data: expect.objectContaining({
                    requestId: 'req_1',
                    venueName: 'Club Velvet',
                    paymentMode: 'SELF_PAY',
                    actor: expect.objectContaining({
                        firstName: 'Alex',
                        isVerified: true,
                    }),
                }),
            }));
            expect(emitSpy).toHaveBeenNthCalledWith(2, partnerId2, expect.objectContaining({
                type: 'PARTNER_REQUEST_SENT',
                actorUserId: hostId,
                data: expect.objectContaining({
                    requestId: 'req_2',
                    recipientUserId: partnerId2,
                }),
            }));
        });

        it('dispatchPartnerRequestNotification should emit notification for single partner direct request', async () => {
            const emitSpy = jest.spyOn(NightPartnerService as any, 'emitNotification').mockResolvedValue(true as any);
            jest.spyOn(User, 'findByPk').mockResolvedValue({
                id: hostId,
                firstName: 'Jessica',
                lastName: 'M',
                isVerified: true,
                photos: [{ isPrimary: true, filePath: 'https://img.lunara.app/jessica.jpg' }],
            } as any);

            const mockReq: any = { id: 'req_single_1', eventTime: '21:30' };

            await NightPartnerService.dispatchPartnerRequestNotification({
                request: mockReq,
                hostId,
                partnerId: partnerId1,
                venue: { id: venueId, name: 'Neon Lounge' } as any,
                eventDate: '2026-11-15',
                eventTime: '21:30',
            });

            expect(emitSpy).toHaveBeenCalledTimes(1);
            expect(emitSpy).toHaveBeenCalledWith(partnerId1, expect.objectContaining({
                type: 'PARTNER_REQUEST_SENT',
                actorUserId: hostId,
                title: 'Invite for Party Event 🌙',
                body: 'Jessica invited you to join for Upcoming Night at Neon Lounge!',
                data: expect.objectContaining({
                    requestId: 'req_single_1',
                    venueName: 'Neon Lounge',
                    status: 'PENDING',
                    actor: expect.objectContaining({
                        firstName: 'Jessica',
                    }),
                }),
            }));
        });
    });
});
