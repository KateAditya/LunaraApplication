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

            // 3. Persist / In-Place Upsert Notification in Database
            let notification: Notification | null = null;

            const targetEntityId = entityId || (metadata ? (metadata.requestId || metadata.partyPlanId || metadata.strangersMeetId || metadata.bookingId) : undefined);

            if (targetEntityId) {
                const existing = await Notification.findOne({
                    where: {
                        recipientUserId,
                        entityId: String(targetEntityId),
                    },
                });

                if (existing) {
                    await existing.update({
                        actorUserId: actorUserId || existing.actorUserId,
                        eventType: String(eventType),
                        category: category || existing.category,
                        entityType: entityType || existing.entityType,
                        title,
                        body,
                        imageUrl: resolvedImageUrl || existing.imageUrl,
                        actionType: actionType || existing.actionType,
                        deepLink: deepLink || existing.deepLink,
                        priority: priority || existing.priority,
                        metadata: { ...(existing.metadata || {}), ...metadata },
                        isRead: false,
                        updatedAt: new Date(),
                    });
                    notification = existing;
                }
            }

            if (!notification) {
                notification = await Notification.create({
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
            }

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
                        const fcmData: Record<string, string> = {
                            notificationId: String(notification.id),
                            eventType: String(eventType),
                            category: String(category || ''),
                            entityType: String(entityType || ''),
                            entityId: String(entityId || ''),
                            deepLink: String(deepLink || ''),
                            actionType: String(actionType || ''),
                            imageUrl: String(resolvedImageUrl || ''),
                        };

                        if (metadata && typeof metadata === 'object') {
                            for (const [key, value] of Object.entries(metadata)) {
                                if (value !== undefined && value !== null) {
                                    fcmData[key] = typeof value === 'object' ? JSON.stringify(value) : String(value);
                                }
                            }
                        }

                        await sendPushNotification(recipient.fcmToken, {
                            title,
                            body,
                            data: fcmData,
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

    /**
     * Dispatch specialized pending payment notification with high priority and actionType: pay_now
     */
    public static async dispatchPendingPaymentNotification(params: {
        recipientUserId: string;
        entityType: 'booking' | 'party_plan' | 'group_party' | 'stranger_meet';
        entityId: string;
        venueName: string;
        amount: number;
        title?: string;
        body?: string;
        metadata?: Record<string, any>;
    }): Promise<Notification | null> {
        const { recipientUserId, entityType, entityId, venueName, amount, metadata } = params;
        const title = params.title || '💳 Reservation Payment Pending';
        const body = params.body || `Your reservation at ${venueName} is awaiting payment (₹${amount}). Complete payment now to confirm your spot!`;

        return await this.dispatch({
            recipientUserId,
            eventType: 'PAYMENT_REQUIRED' as any,
            category: 'payments',
            entityType,
            entityId,
            title,
            body,
            actionType: 'pay_now',
            priority: 'HIGH',
            metadata: {
                ...metadata,
                amount,
                venueName,
                entityId,
                entityType,
                actionRequired: true,
                paymentStatus: 'pending'
            }
        });
    }

    /**
     * Dispatch specialized schedule unlocked notification when an active event is cancelled
     */
    public static async sendScheduleUnlockedNotification(params: {
        recipientUserId: string;
        eventTitle: string;
        eventTimeStr: string;
        venueName?: string;
        entityType: 'party_plan' | 'group_party' | 'stranger_meet' | 'booking';
        entityId: string;
    }): Promise<Notification | null> {
        const { recipientUserId, eventTitle, eventTimeStr, venueName, entityType, entityId } = params;
        const venueInfo = venueName ? ` at ${venueName}` : '';
        const title = '🔓 Schedule Unlocked';
        const body = `Your cancelled ${eventTitle}${venueInfo} (${eventTimeStr}) no longer blocks this time slot. You can now create or join another plan.`;

        return await this.dispatch({
            recipientUserId,
            eventType: 'SCHEDULE_UNLOCKED' as any,
            category: 'activity',
            entityType,
            entityId,
            title,
            body,
            priority: 'NORMAL',
            metadata: {
                eventTitle,
                eventTimeStr,
                venueName,
                unlockedAt: new Date().toISOString(),
            }
        });
    }
}
