import { Request, Response } from 'express';
import Notification from '../models/Notification';
import StrangersMeetJoiner, { StrangersMeetJoinerStatus } from '../models/StrangersMeetJoiner';
import User from '../models/User';
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
            if (action === 'ACCEPT' || action === 'DECLINE' || action === 'REJECT') {
                const isPartyPlanEntity = notification.entityType === 'PartyPlanRequest' || 
                                          notification.entityType === 'party_plan_request' || 
                                          notification.entityType === 'party_plan';
                
                if (isPartyPlanEntity) {
                    const requestId = notification.metadata?.requestId || 
                                     (notification.entityType === 'PartyPlanRequest' || notification.entityType === 'party_plan_request' ? notification.entityId : null);

                    if (action === 'ACCEPT' && requestId) {
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
                    } else if ((action === 'DECLINE' || action === 'REJECT') && requestId) {
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
                } else if ((notification.entityType === 'StrangersMeetRequest' || notification.entityType === 'StrangersMeetJoiner') && notification.entityId) {
                    const reqItem = await StrangersMeetJoiner.findByPk(notification.entityId);
                    if (reqItem) {
                        reqItem.status = action === 'ACCEPT' ? StrangersMeetJoinerStatus.ACCEPTED : StrangersMeetJoinerStatus.REJECTED;
                        await reqItem.save();

                        // Notify counterpart
                        const targetUser = reqItem.userId;
                        await NotificationService.dispatch({
                            recipientUserId: targetUser,
                            actorUserId: currentUserId,
                            eventType: action === 'ACCEPT' ? 'STRANGER_MEET_ACCEPTED' : 'STRANGER_MEET_DECLINED',
                            category: 'requests',
                            entityType: 'StrangersMeetJoiner',
                            entityId: reqItem.id,
                            title: action === 'ACCEPT' ? '🟢 Join Request Accepted' : '🔴 Request Declined',
                            body: action === 'ACCEPT'
                                ? 'Your request to join the Stranger Meet was accepted!'
                                : 'Your request to join was declined.',
                            actionType: action === 'ACCEPT' ? 'VIEW_DETAILS' : 'VIEW_EVENTS',
                            deepLink: `/stranger-meets/${reqItem.strangersMeetRequestId}`,
                            priority: 'HIGH',
                        });
                    }
                } else if ((notification.entityType === 'night_partner' || notification.entityType === 'NightPartnerRequest') && notification.entityId) {
                    const act = action.toUpperCase() === 'ACCEPT' ? 'accept' : 'decline';
                    try {
                        const result = await NightPartnerService.respondToRequest(notification.entityId, currentUserId, act);
                        actionResult = { status: 'ACTIONED', actionExecuted: action, result };
                    } catch (partnerErr: any) {
                        logger.error('[NotificationActionController] NightPartner action error:', partnerErr);
                        actionResult = { status: 'ACTIONED', actionExecuted: action, note: partnerErr.message };
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
            const currentUserId = req.user?.id || req.body.userId || req.query.userId;
            if (!currentUserId) {
                return res.status(401).json({ success: false, message: 'Unauthorized' });
            }

            await NotificationService.markAllAsRead(currentUserId);

            // Socket badge emission
            const { io } = require('../server');
            if (io) {
                io.to(`user_${currentUserId}`).emit('badge_updated', { unreadCount: 0 });
            }

            return res.status(200).json({
                success: true,
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
            const currentUserId = req.user?.id || req.body.userId || req.query.userId;
            if (!currentUserId) {
                return res.status(401).json({ success: false, message: 'Unauthorized' });
            }

            // Update user clearedNotificationsAt timestamp
            await User.update(
                { clearedNotificationsAt: new Date() },
                { where: { id: currentUserId } }
            );

            // Also mark active notifications as read
            await NotificationService.markAllAsRead(currentUserId);

            // Socket badge emission
            const { io } = require('../server');
            if (io) {
                io.to(`user_${currentUserId}`).emit('badge_updated', { unreadCount: 0 });
            }

            return res.status(200).json({
                success: true,
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
