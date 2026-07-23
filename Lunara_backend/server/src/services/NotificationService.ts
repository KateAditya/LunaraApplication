import Notification from '../models/Notification';
import User from '../models/User';
import UserProfile from '../models/UserProfile';
import { NotificationPayload, NotificationCategory } from '../types/NotificationEventTypes';
import { sendPushNotification } from './fcmService';
import { logger } from '../config/logger';

export class NotificationService {
    /**
     * Dispatch an authoritative notification across DB, Socket.io, and FCM Push
     */
    public static async dispatch(payload: NotificationPayload): Promise<Notification | null> {
        try {
            const {
                recipientUserId,
                actorUserId,
                eventType,
                category = 'system',
                entityType,
                entityId,
                title,
                body,
                imageUrl,
                actionType,
                deepLink,
                priority = 'NORMAL',
                idempotencyKey,
                metadata,
                expiresAt,
            } = payload;

            if (!recipientUserId) {
                logger.warn('[NotificationService] Missing recipientUserId for dispatch');
                return null;
            }

            // 1. Idempotency Guard
            if (idempotencyKey) {
                const existing = await Notification.findOne({ where: { idempotencyKey } });
                if (existing) {
                    logger.info(`[NotificationService] Idempotent hit for key: ${idempotencyKey}`);
                    return existing;
                }
            }

            // 2. Fetch Actor Profile Image if not specified
            let resolvedImageUrl = imageUrl;
            if (!resolvedImageUrl && actorUserId) {
                const actorUser = await User.findByPk(actorUserId, { attributes: ['profileImageUrl'] });
                resolvedImageUrl = actorUser?.profileImageUrl || undefined;
            }

            // 3. Persist Notification in Database
            const notification = await Notification.create({
                recipientUserId,
                actorUserId,
                eventType: String(eventType),
                category,
                entityType,
                entityId,
                title,
                body,
                imageUrl: resolvedImageUrl,
                actionType,
                deepLink,
                priority,
                idempotencyKey,
                metadata,
                expiresAt,
                isRead: false,
            });

            // 4. Dispatch Asynchronous Socket.io Event (Non-blocking)
            setImmediate(async () => {
                try {
                    const { io } = require('../server');
                    if (io) {
                        const targetRoom = `user_${recipientUserId}`;
                        io.to(targetRoom).emit('notification_received', {
                            notification: notification.toJSON(),
                        });

                        // Emit updated unread count
                        const unreadCount = await Notification.count({
                            where: { recipientUserId, isRead: false },
                        });
                        io.to(targetRoom).emit('badge_updated', { unreadCount });
                    }
                } catch (socketErr) {
                    logger.warn(`[NotificationService] Socket dispatch error: ${socketErr}`);
                }
            });

            // 5. Dispatch Asynchronous FCM Push Notification (Non-blocking)
            setImmediate(async () => {
                try {
                    const recipient = await User.findByPk(recipientUserId, { attributes: ['fcmToken'] });
                    if (recipient?.fcmToken) {
                        await sendPushNotification(recipient.fcmToken, {
                            title,
                            body,
                            data: {
                                notificationId: notification.id,
                                eventType: String(eventType),
                                category,
                                entityType: entityType || '',
                                entityId: entityId || '',
                                deepLink: deepLink || '',
                                actionType: actionType || '',
                                imageUrl: resolvedImageUrl || '',
                            },
                        });
                    }
                } catch (pushErr) {
                    logger.warn(`[NotificationService] Push notification error: ${pushErr}`);
                }
            });

            return notification;
        } catch (error: any) {
            logger.error('[NotificationService] Dispatch error:', error);
            return null;
        }
    }

    /**
     * Get paginated notifications for a recipient
     */
    public static async getNotifications(
        recipientUserId: string,
        options: {
            category?: NotificationCategory | 'all';
            limit?: number;
            offset?: number;
        } = {}
    ) {
        const { category = 'all', limit = 30, offset = 0 } = options;
        const whereClause: any = { recipientUserId };

        if (category && category !== 'all') {
            whereClause.category = category;
        }

        const { rows, count } = await Notification.findAndCountAll({
            where: whereClause,
            order: [['createdAt', 'DESC']],
            limit,
            offset,
            include: [
                {
                    model: User,
                    as: 'actor',
                    attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                    include: [
                        {
                            model: UserProfile,
                            as: 'profile',
                            attributes: ['city'],
                        },
                    ],
                },
            ],
        });

        const unreadCount = await Notification.count({
            where: { recipientUserId, isRead: false },
        });

        return {
            notifications: rows,
            totalCount: count,
            unreadCount,
        };
    }

    /**
     * Mark single notification as read
     */
    public static async markAsRead(notificationId: string, recipientUserId: string): Promise<boolean> {
        const [updatedCount] = await Notification.update(
            { isRead: true, readAt: new Date() },
            { where: { id: notificationId, recipientUserId } }
        );
        return updatedCount > 0;
    }

    /**
     * Mark all notifications as read for a recipient
     */
    public static async markAllAsRead(recipientUserId: string): Promise<boolean> {
        await Notification.update(
            { isRead: true, readAt: new Date() },
            { where: { recipientUserId, isRead: false } }
        );
        return true;
    }

    /**
     * Get unread count
     */
    public static async getUnreadCount(recipientUserId: string): Promise<number> {
        return await Notification.count({
            where: { recipientUserId, isRead: false },
        });
    }
}
