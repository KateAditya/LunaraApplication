import { initializeApp, getApps, App, cert, applicationDefault } from 'firebase-admin/app';
import { getMessaging, Message, MulticastMessage } from 'firebase-admin/messaging';
import { logger } from '../config/logger';

// ── Initialise Firebase Admin SDK once ───────────────────────────────────────
let _app: App | null = null;

function getApp(): App | null {
    // Return existing app if already initialised
    if (_app) return _app;
    if (getApps().length > 0) {
        _app = getApps()[0];
        return _app;
    }

    try {
        // Option A – service-account JSON string in env var (production-friendly)
        const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
        if (raw) {
            const serviceAccount = JSON.parse(raw);
            _app = initializeApp({ credential: cert(serviceAccount) });
            logger.info('Firebase Admin SDK initialised (from env JSON).');
            return _app;
        }

        // Option B – path provided via GOOGLE_APPLICATION_CREDENTIALS
        if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
            _app = initializeApp({ credential: applicationDefault() });
            logger.info('Firebase Admin SDK initialised (applicationDefault).');
            return _app;
        }

        logger.warn(
            'Firebase Admin SDK NOT initialised: set FIREBASE_SERVICE_ACCOUNT_JSON or ' +
            'GOOGLE_APPLICATION_CREDENTIALS to enable push notifications.'
        );
        return null;
    } catch (err: any) {
        logger.error('Firebase Admin SDK init error:', err.message);
        return null;
    }
}

export interface FcmPayload {
    title: string;
    body: string;
    data?: Record<string, string>;
    imageUrl?: string;
}

/**
 * Send a push notification to a single FCM token.
 * Silently swallows errors so a notification failure never breaks the API response.
 */
export async function sendPushNotification(
    fcmToken: string,
    payload: FcmPayload
): Promise<void> {
    const app = getApp();
    if (!app) return;
    if (!fcmToken || fcmToken.trim() === '') return;

    try {
        const message: Message = {
            token: fcmToken,
            notification: {
                title: payload.title,
                body: payload.body,
                ...(payload.imageUrl ? { imageUrl: payload.imageUrl } : {}),
            },
            data: payload.data ?? {},
            android: {
                priority: 'high',
                notification: {
                    channelId: 'lunara_high_importance',
                    sound: 'default',
                },
            },
            apns: {
                payload: {
                    aps: {
                        sound: 'default',
                        badge: 1,
                    },
                },
            },
        };

        const response = await getMessaging(app).send(message);
        logger.debug(`FCM notification sent: ${response}`);
    } catch (err: any) {
        // Don't re-throw — notification failure must not break the API
        logger.warn(`FCM send failed for token ${fcmToken.substring(0, 20)}...: ${err.message}`);
    }
}

/**
 * Send push notifications to multiple FCM tokens.
 * Invalid / expired tokens are silently ignored.
 */
export async function sendMulticastPushNotification(
    fcmTokens: string[],
    payload: FcmPayload
): Promise<void> {
    const app = getApp();
    if (!app) return;

    const validTokens = fcmTokens.filter(t => t && t.trim() !== '');
    if (validTokens.length === 0) return;

    try {
        const message: MulticastMessage = {
            tokens: validTokens,
            notification: {
                title: payload.title,
                body: payload.body,
                ...(payload.imageUrl ? { imageUrl: payload.imageUrl } : {}),
            },
            data: payload.data ?? {},
            android: {
                priority: 'high',
                notification: {
                    channelId: 'lunara_high_importance',
                    sound: 'default',
                },
            },
            apns: {
                payload: {
                    aps: {
                        sound: 'default',
                        badge: 1,
                    },
                },
            },
        };

        const response = await getMessaging(app).sendEachForMulticast(message);
        logger.debug(
            `FCM multicast: ${response.successCount} sent, ${response.failureCount} failed`
        );
    } catch (err: any) {
        logger.warn(`FCM multicast failed: ${err.message}`);
    }
}

/**
 * Helper to fetch all eligible users for notification:
 * - Excludes the creator/host of the event
 * - Filters for users in the same city as the venue (case-insensitive)
 * - Excludes users who have blocked the creator, or whom the creator has blocked
 * - Only includes active users with customer role and a valid FCM token
 */
export async function getEligibleUsersForEventNotification(
    creatorId: string,
    venueCity: string,
    additionalExcludedIds: string[] = []
): Promise<string[]> {
    if (!venueCity || venueCity.trim() === '') return [];

    try {
        // Import models dynamically to avoid circular dependencies
        const { default: User } = require('../models/User');
        const { default: UserProfile } = require('../models/UserProfile');
        const { default: SocialConnection } = require('../models/SocialConnection');
        const { ConnectionStatus } = require('../models/SocialConnection');
        const { Op } = require('sequelize');

        // 1. Fetch blocked user IDs (either blocked by creator or blocked the creator)
        const blockedConnections = await SocialConnection.findAll({
            where: {
                status: ConnectionStatus.BLOCKED,
                [Op.or]: [
                    { requesterId: creatorId },
                    { receiverId: creatorId }
                ]
            },
            attributes: ['requesterId', 'receiverId']
        });

        const blockedUserIds = new Set<string>();
        for (const conn of blockedConnections) {
            if (conn.requesterId !== creatorId) blockedUserIds.add(conn.requesterId);
            if (conn.receiverId !== creatorId) blockedUserIds.add(conn.receiverId);
        }

        const excludedIds = Array.from(blockedUserIds).concat(creatorId).concat(additionalExcludedIds);

        // 2. Fetch all other users in the same city with a valid FCM token
        const eligibleUsers = await User.findAll({
            where: {
                id: {
                    [Op.notIn]: excludedIds
                },
                fcmToken: {
                    [Op.and]: [
                        { [Op.ne]: null },
                        { [Op.ne]: '' }
                    ]
                },
                role: 'customer',
                isActive: true
            },
            include: [{
                model: UserProfile,
                as: 'profile',
                where: {
                    city: {
                        [Op.iLike]: venueCity.trim()
                    }
                },
                required: true
            }],
            attributes: ['fcmToken']
        });

        return eligibleUsers.map((u: any) => u.fcmToken).filter(Boolean);
    } catch (err: any) {
        logger.error('Error fetching eligible users for notification:', err.message);
        return [];
    }
}

