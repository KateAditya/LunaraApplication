import { Request, Response } from 'express';
import Notification from '../models/Notification';
import StrangersMeetJoiner from '../models/StrangersMeetJoiner';
import { NotificationService } from '../services/NotificationService';
import { NightPartnerService } from '../services/NightPartnerService';
import { logger } from '../config/logger';
import { acceptPartyPlanRequest, rejectPartyPlanRequest } from './partyPlanController';

export class NotificationActionController {
    /**
     * POST /api/mobile/notifications/:id/action
     * Execute an action on a notification (e.g., ACCEPT, DECLINE, PAY)
     */
    public static async handleAction(req: Request, res: Response): Promise<Response> {
        try {
            const { id } = req.params;
            const { action } = req.body;
            const currentUserId = req.user?.id || req.body.userId || req.query.userId;

            if (!currentUserId) {
                return res.status(401).json({ success: false, message: 'Unauthorized' });
            }

            const notification = await Notification.findByPk(id);
            if (!notification) {
                return res.status(404).json({ success: false, message: 'Notification not found' });
            }

            if (notification.recipientUserId !== currentUserId) {
                return res.status(403).json({ success: false, message: 'Access denied to this notification' });
            }

            // Mark as read when action is taken
            notification.isRead = true;
            notification.readAt = new Date();

            let actionResult: any = { status: 'ACTIONED', actionExecuted: action };

            // Handle domain entity specific actions
            const upperAction = action.toUpperCase();
            if (['ACCEPT', 'DECLINE', 'REJECT', 'ACCEPT_REQUEST', 'DECLINE_REQUEST', 'ACCEPT_CANCELLATION', 'REJECT_CANCELLATION'].includes(upperAction)) {
                const isPartyPlanEntity = notification.entityType === 'PartyPlanRequest' || 
                                          notification.entityType === 'party_plan_request' || 
                                          notification.entityType === 'party_plan';
                
                if (isPartyPlanEntity) {
                    const isCancellationNotif = notification.eventType === 'party_plan_cancellation_requested' || 
                                               Boolean(notification.metadata?.cancellationId) ||
                                               (notification.title && notification.title.toLowerCase().includes('cancellation')) ||
                                               upperAction.includes('CANCELLATION');

                    if (isCancellationNotif) {
                        const planId = notification.entityId || notification.metadata?.planId;
                        const cancellationReqId = notification.metadata?.requestId || notification.metadata?.cancellationId;

                        if (planId) {
                            const { respondToCancellationRequest } = await import('./cancellationController');
                            const mockReq: any = {
                                params: { id: planId },
                                body: {
                                    requestId: cancellationReqId,
                                    action: (upperAction === 'ACCEPT' || upperAction === 'ACCEPT_CANCELLATION') ? 'approve' : 'reject',
                                    userId: currentUserId,
                                },
                                user: { id: currentUserId },
                            };
                            let mockStatus = 200;
                            let mockJsonPayload: any = null;
                            const mockRes: any = {
                                status: (code: number) => { mockStatus = code; return mockRes; },
                                json: (data: any) => { mockJsonPayload = data; return mockRes; },
                            };
                            await respondToCancellationRequest(mockReq, mockRes);
                            actionResult = { status: mockStatus === 200 ? 'ACTIONED' : 'FAILED', actionExecuted: action, response: mockJsonPayload };
                        }
                    } else {
                        const requestId = notification.metadata?.requestId || 
                                         (notification.entityType === 'PartyPlanRequest' || notification.entityType === 'party_plan_request' ? notification.entityId : null);

                        if (upperAction === 'ACCEPT' && requestId) {
                            const mockReq: any = {
                                params: { reqId: requestId },
                                body: { userId: currentUserId },
                            };
                            let mockStatus = 200;
                            let mockJsonPayload: any = null;
                            const mockRes: any = {
                                status: (code: number) => { mockStatus = code; return mockRes; },
                                json: (data: any) => { mockJsonPayload = data; return mockRes; },
                            };
                            await acceptPartyPlanRequest(mockReq, mockRes);
                            actionResult = { status: mockStatus === 200 ? 'ACTIONED' : 'FAILED', actionExecuted: action, response: mockJsonPayload };
                        } else if ((upperAction === 'DECLINE' || upperAction === 'REJECT') && requestId) {
                            const mockReq: any = {
                                params: { reqId: requestId },
                                body: { userId: currentUserId },
                            };
                            let mockStatus = 200;
                            let mockJsonPayload: any = null;
                            const mockRes: any = {
                                status: (code: number) => { mockStatus = code; return mockRes; },
                                json: (data: any) => { mockJsonPayload = data; return mockRes; },
                            };
                            await rejectPartyPlanRequest(mockReq, mockRes);
                            actionResult = { status: mockStatus === 200 ? 'ACTIONED' : 'FAILED', actionExecuted: action, response: mockJsonPayload };
                        }
                    }
                } else if ((notification.entityType === 'StrangersMeetRequest' || notification.entityType === 'StrangersMeetJoiner' || notification.entityType === 'strangers_meet') && notification.entityId) {
                    const joinerId = notification.metadata?.joinerId || notification.entityId;
                    let joiner = await StrangersMeetJoiner.findByPk(joinerId);
                    
                    if (!joiner && notification.entityId) {
                        joiner = await StrangersMeetJoiner.findOne({
                            where: { strangersMeetRequestId: notification.entityId, status: 'pending' },
                            order: [['createdAt', 'ASC']],
                        });
                    }

                    if (joiner) {
                        const { handleJoinRequest } = await import('./strangersMeetController');
                        const mockReq: any = {
                            params: { id: joiner.strangersMeetRequestId, joinerId: joiner.id },
                            body: { action: action.toLowerCase() === 'accept' ? 'accept' : 'reject' },
                            user: { id: currentUserId },
                        };
                        let mockStatus = 200;
                        let mockJsonPayload: any = null;
                        const mockRes: any = {
                            status: (code: number) => { mockStatus = code; return mockRes; },
                            json: (data: any) => { mockJsonPayload = data; return mockRes; },
                        };
                        await handleJoinRequest(mockReq, mockRes);
                        actionResult = { status: mockStatus === 200 ? 'ACTIONED' : 'FAILED', actionExecuted: action, response: mockJsonPayload };
                    }
                } else if ((notification.entityType === 'night_partner' || notification.entityType === 'NightPartnerRequest' || notification.entityType === 'NightPartnerMatch' || notification.eventType === 'PARTNER_REQUEST_SENT' || notification.eventType === 'PARTNER_REQUEST_RECEIVED' || (notification as any).type === 'PARTNER_REQUEST_SENT' || (notification as any).type === 'PARTNER_REQUEST_RECEIVED') && (notification.entityId || notification.metadata?.requestId)) {
                    const cleanEntityId = (notification.metadata?.requestId || notification.entityId || '')
                        .replace(/^(upcoming_night_timeline_|party_plan_timeline_|night_partner_|party_plan_|match_|req_|request_|pp_)/i, '')
                        .trim();
                    if (upperAction === 'ACCEPT_CANCELLATION' || upperAction === 'REJECT_CANCELLATION') {
                        try {
                            const result = await NightPartnerService.cancelUpcomingNight(
                                cleanEntityId,
                                currentUserId,
                                upperAction === 'ACCEPT_CANCELLATION' ? 'Cancellation confirmed by partner' : 'Cancellation declined by partner',
                                upperAction === 'ACCEPT_CANCELLATION' ? 'approve' : 'reject'
                            );
                            actionResult = { status: 'ACTIONED', actionExecuted: action, result };
                        } catch (partnerErr: any) {
                            logger.error('[NotificationActionController] NightPartner cancellation action error:', partnerErr);
                            actionResult = { status: 'ACTIONED', actionExecuted: action, note: partnerErr.message };
                        }
                    } else {
                        const act = (upperAction === 'ACCEPT' || upperAction === 'ACCEPT_REQUEST') ? 'accept' : 'decline';
                        try {
                            const result = await NightPartnerService.respondToRequest(cleanEntityId, currentUserId, act);
                            actionResult = { status: 'ACTIONED', actionExecuted: action, result };
                        } catch (partnerErr: any) {
                            logger.error('[NotificationActionController] NightPartner action error:', partnerErr);
                            const isSlotFilled = partnerErr.message === 'MATCH_SLOT_FILLED';
                            const isExpired = partnerErr.message === 'REQUEST_EXPIRED';
                            const isNotFound = partnerErr.message === 'REQUEST_NOT_FOUND' || partnerErr.message === 'REQUEST_ALREADY_PROCESSED';
                            const friendlyMsg = isSlotFilled
                                ? 'This invitation is no longer available as the host is already matched with another guest.'
                                : (isExpired
                                    ? 'This invitation has expired.'
                                    : (isNotFound
                                        ? 'This invitation is no longer available.'
                                        : (partnerErr.message || 'Failed to process invitation.')));
                            actionResult = {
                                status: 'ACTIONED',
                                actionExecuted: action,
                                notAvailable: isSlotFilled || isExpired || isNotFound,
                                note: friendlyMsg,
                            };
                        }
                    }
                }
            }

            // Update notification metadata state
            const currentMetadata = notification.metadata || {};
            notification.metadata = { ...currentMetadata, ...actionResult, actionTakenAt: new Date() };
            await notification.save();

            // Emit socket badge update
            const unreadCount = await NotificationService.getUnreadCount(currentUserId);
            const { io } = require('../server');
            if (io) {
                io.to(`user_${currentUserId}`).emit('badge_updated', { unreadCount });
                io.to(`user_${currentUserId}`).emit('notification_updated', { notification: notification.toJSON() });
            }

            return res.status(200).json({
                success: true,
                message: 'Notification action processed successfully',
                notification,
                actionResult,
            });
        } catch (error: any) {
            logger.error('[NotificationActionController] Action error:', error);
            return res.status(500).json({ success: false, message: error.message || 'Internal server error' });
        }
    }

    /**
     * POST /api/mobile/notifications/mark-all-read
     */
    public static async markAllAsRead(req: Request, res: Response): Promise<Response> {
        try {
            const currentUserId = req.user?.id || req.body?.userId || req.query?.userId;
            if (!currentUserId) {
                return res.status(401).json({ success: false, message: 'Unauthorized' });
            }

            await NotificationService.markAllAsRead(currentUserId);

            // Socket badge emission & multi-session broadcast
            const { io } = require('../server');
            if (io) {
                io.to(`user_${currentUserId}`).emit('badge_updated', {
                    unreadCount: 0,
                    liveFeedCount: 0,
                    totalCount: 0,
                });
                io.to(`user_${currentUserId}`).emit('notifications_read_all', {
                    userId: currentUserId,
                    unreadCount: 0,
                    clearedAt: new Date().toISOString(),
                });
            }

            return res.status(200).json({
                success: true,
                unreadCount: 0,
                message: 'All notifications marked as read',
            });
        } catch (error: any) {
            logger.error('[NotificationActionController] markAllAsRead error:', error);
            return res.status(500).json({ success: false, message: error.message || 'Internal server error' });
        }
    }

    /**
     * POST /api/mobile/notifications/clear-all
     */
    public static async clearAll(req: Request, res: Response): Promise<Response> {
        try {
            const currentUserId = req.user?.id || req.body?.userId || req.query?.userId;
            if (!currentUserId) {
                return res.status(401).json({ success: false, message: 'Unauthorized' });
            }

            await NotificationService.markAllAsRead(currentUserId);

            // Socket badge emission & multi-session broadcast
            const { io } = require('../server');
            if (io) {
                io.to(`user_${currentUserId}`).emit('badge_updated', {
                    unreadCount: 0,
                    liveFeedCount: 0,
                    totalCount: 0,
                });
                io.to(`user_${currentUserId}`).emit('notifications_read_all', {
                    userId: currentUserId,
                    unreadCount: 0,
                    clearedAt: new Date().toISOString(),
                });
            }

            return res.status(200).json({
                success: true,
                unreadCount: 0,
                message: 'Notification center cleared',
            });
        } catch (error: any) {
            logger.error('[NotificationActionController] clearAll error:', error);
            return res.status(500).json({ success: false, message: error.message || 'Internal server error' });
        }
    }

    /**
     * GET /api/mobile/notifications/unread-count
     */
    public static async getUnreadCount(req: Request, res: Response): Promise<Response> {
        try {
            const currentUserId = req.user?.id || req.query.userId as string;
            if (!currentUserId) {
                return res.status(200).json({ success: true, unreadCount: 0 });
            }

            const unreadCount = await NotificationService.getUnreadCount(currentUserId);
            return res.status(200).json({ success: true, unreadCount });
        } catch (error: any) {
            logger.error('[NotificationActionController] getUnreadCount error:', error);
            return res.status(500).json({ success: false, unreadCount: 0 });
        }
    }
}
