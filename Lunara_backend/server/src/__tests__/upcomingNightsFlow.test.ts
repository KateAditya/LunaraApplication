import { NotificationActionController } from '../controllers/NotificationActionController';
import Notification from '../models/Notification';
import NightPartnerMatch, {
    NightPartnerMatchStatus,
    NightPartnerCancellationStatus,
} from '../models/NightPartnerMatch';
import { NightPartnerService } from '../services/NightPartnerService';
import { NotificationService } from '../services/NotificationService';

describe('Upcoming Nights & Event Booking Complete Flow Suite', () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    describe('NotificationActionController Night Partner Actions', () => {
        it('should execute ACCEPT action for night_partner request notification', async () => {
            const mockNotification = {
                id: 'notif_1',
                recipientUserId: 'user_recipient',
                entityType: 'NightPartnerRequest',
                entityId: 'req_100',
                eventType: 'partner_request_created',
                isRead: false,
                readAt: null,
                metadata: {},
                save: jest.fn().mockResolvedValue(true),
                toJSON: jest.fn().mockReturnValue({ id: 'notif_1' }),
            };

            jest.spyOn(Notification, 'findByPk').mockResolvedValue(mockNotification as any);
            jest.spyOn(NightPartnerService, 'respondToRequest').mockResolvedValue({
                success: true,
                matchId: 'match_100',
                status: 'MATCHED',
            } as any);
            jest.spyOn(NotificationService, 'getUnreadCount').mockResolvedValue(0);

            const mockReq: any = {
                params: { id: 'notif_1' },
                body: { action: 'ACCEPT' },
                user: { id: 'user_recipient' },
            };

            let responseStatus = 200;
            let responseBody: any = null;
            const mockRes: any = {
                status: (code: number) => {
                    responseStatus = code;
                    return mockRes;
                },
                json: (data: any) => {
                    responseBody = data;
                    return mockRes;
                },
            };

            await NotificationActionController.handleAction(mockReq, mockRes);

            expect(responseStatus).toBe(200);
            expect(responseBody.success).toBe(true);
            expect(NightPartnerService.respondToRequest).toHaveBeenCalledWith('req_100', 'user_recipient', 'accept');
            expect(mockNotification.isRead).toBe(true);
            expect(mockNotification.save).toHaveBeenCalled();
        });

        it('should execute DECLINE action for night_partner request notification', async () => {
            const mockNotification = {
                id: 'notif_2',
                recipientUserId: 'user_recipient',
                entityType: 'night_partner',
                entityId: 'req_100',
                eventType: 'partner_request_created',
                isRead: false,
                readAt: null,
                metadata: {},
                save: jest.fn().mockResolvedValue(true),
                toJSON: jest.fn().mockReturnValue({ id: 'notif_2' }),
            };

            jest.spyOn(Notification, 'findByPk').mockResolvedValue(mockNotification as any);
            jest.spyOn(NightPartnerService, 'respondToRequest').mockResolvedValue({
                success: true,
                status: 'DECLINED',
            } as any);
            jest.spyOn(NotificationService, 'getUnreadCount').mockResolvedValue(0);

            const mockReq: any = {
                params: { id: 'notif_2' },
                body: { action: 'DECLINE' },
                user: { id: 'user_recipient' },
            };

            let responseStatus = 200;
            let responseBody: any = null;
            const mockRes: any = {
                status: (code: number) => {
                    responseStatus = code;
                    return mockRes;
                },
                json: (data: any) => {
                    responseBody = data;
                    return mockRes;
                },
            };

            await NotificationActionController.handleAction(mockReq, mockRes);

            expect(responseStatus).toBe(200);
            expect(responseBody.success).toBe(true);
            expect(NightPartnerService.respondToRequest).toHaveBeenCalledWith('req_100', 'user_recipient', 'decline');
        });

        it('should execute ACCEPT_CANCELLATION action on match cancellation notification', async () => {
            const mockNotification = {
                id: 'notif_3',
                recipientUserId: 'user_partner',
                entityType: 'NightPartnerMatch',
                entityId: 'match_100',
                eventType: 'upcoming_night_cancellation_requested',
                isRead: false,
                readAt: null,
                metadata: {},
                save: jest.fn().mockResolvedValue(true),
                toJSON: jest.fn().mockReturnValue({ id: 'notif_3' }),
            };

            jest.spyOn(Notification, 'findByPk').mockResolvedValue(mockNotification as any);
            jest.spyOn(NightPartnerService, 'cancelUpcomingNight').mockResolvedValue({
                success: true,
                status: 'CANCELLED',
                refundStatus: 'FULL_REFUND',
            } as any);
            jest.spyOn(NotificationService, 'getUnreadCount').mockResolvedValue(0);

            const mockReq: any = {
                params: { id: 'notif_3' },
                body: { action: 'ACCEPT_CANCELLATION' },
                user: { id: 'user_partner' },
            };

            let responseStatus = 200;
            let responseBody: any = null;
            const mockRes: any = {
                status: (code: number) => {
                    responseStatus = code;
                    return mockRes;
                },
                json: (data: any) => {
                    responseBody = data;
                    return mockRes;
                },
            };

            await NotificationActionController.handleAction(mockReq, mockRes);

            expect(responseStatus).toBe(200);
            expect(responseBody.success).toBe(true);
            expect(NightPartnerService.cancelUpcomingNight).toHaveBeenCalledWith(
                'match_100',
                'user_partner',
                'Cancellation confirmed by partner',
                'approve'
            );
        });

        it('should execute REJECT_CANCELLATION action on match cancellation notification', async () => {
            const mockNotification = {
                id: 'notif_4',
                recipientUserId: 'user_partner',
                entityType: 'NightPartnerMatch',
                entityId: 'match_100',
                eventType: 'upcoming_night_cancellation_requested',
                isRead: false,
                readAt: null,
                metadata: {},
                save: jest.fn().mockResolvedValue(true),
                toJSON: jest.fn().mockReturnValue({ id: 'notif_4' }),
            };

            jest.spyOn(Notification, 'findByPk').mockResolvedValue(mockNotification as any);
            jest.spyOn(NightPartnerService, 'cancelUpcomingNight').mockResolvedValue({
                success: true,
                status: 'REJECTED',
            } as any);
            jest.spyOn(NotificationService, 'getUnreadCount').mockResolvedValue(0);

            const mockReq: any = {
                params: { id: 'notif_4' },
                body: { action: 'REJECT_CANCELLATION' },
                user: { id: 'user_partner' },
            };

            let responseStatus = 200;
            let responseBody: any = null;
            const mockRes: any = {
                status: (code: number) => {
                    responseStatus = code;
                    return mockRes;
                },
                json: (data: any) => {
                    responseBody = data;
                    return mockRes;
                },
            };

            await NotificationActionController.handleAction(mockReq, mockRes);

            expect(responseStatus).toBe(200);
            expect(responseBody.success).toBe(true);
            expect(NightPartnerService.cancelUpcomingNight).toHaveBeenCalledWith(
                'match_100',
                'user_partner',
                'Cancellation declined by partner',
                'reject'
            );
        });
    });

    describe('Live Feed Timeline Card Enrichment for Cancellation', () => {
        it('should display proper action buttons for partner receiving cancellation request', async () => {
            const mockMatch = {
                id: 'match_mutual_req',
                hostId: 'host_1',
                partnerId: 'partner_2',
                eventDate: new Date('2026-09-15'),
                status: NightPartnerMatchStatus.CONFIRMED,
                cancellationStatus: NightPartnerCancellationStatus.REQUESTED,
                cancellationReason: 'Need to reschedule',
                cancelledBy: 'host_1',
                venue: { name: 'Dragonfly Club' },
                updatedAt: new Date(),
            };

            jest.spyOn(NightPartnerMatch, 'findByPk').mockResolvedValue(mockMatch as any);

            const card = await NightPartnerService.enrichUpcomingNightNotificationCard('match_mutual_req', 'partner_2');
            expect(card).not.toBeNull();
            expect(card.title).toContain('Partner Requested Cancellation');
            expect(card.data.cancellationStatus).toBe('REQUESTED');
            expect(card.data.cancelledBy).toBe('host_1');
            expect(card.data.cancellationReason).toBe('Need to reschedule');

            const actionNames = card.data.actionButtons.map((a: any) => a.action);
            expect(actionNames).toContain('ACCEPT_CANCELLATION');
            expect(actionNames).toContain('REJECT_CANCELLATION');
        });

        it('should show pending partner confirmation for requester host', async () => {
            const mockMatch = {
                id: 'match_mutual_req',
                hostId: 'host_1',
                partnerId: 'partner_2',
                eventDate: new Date('2026-09-15'),
                status: NightPartnerMatchStatus.CONFIRMED,
                cancellationStatus: NightPartnerCancellationStatus.REQUESTED,
                cancellationReason: 'Need to reschedule',
                cancelledBy: 'host_1',
                venue: { name: 'Dragonfly Club' },
                updatedAt: new Date(),
            };

            jest.spyOn(NightPartnerMatch, 'findByPk').mockResolvedValue(mockMatch as any);

            const card = await NightPartnerService.enrichUpcomingNightNotificationCard('match_mutual_req', 'host_1');
            expect(card).not.toBeNull();
            expect(card.title).toContain('Cancellation Requested');
            expect(card.data.statusText).toBe('Pending Partner Confirmation');
            const hostActions = card.data.actionButtons.map((b: any) => b.action);
            expect(hostActions).not.toContain('ACCEPT_CANCELLATION');
            expect(hostActions).not.toContain('REJECT_CANCELLATION');
            expect(hostActions).toContain('VIEW_DETAILS');
        });
    });
});
