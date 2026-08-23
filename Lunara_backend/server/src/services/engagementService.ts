import UserEngagementEvent, { EngagementEventType } from '../models/UserEngagementEvent';
import { logger } from '../config/logger';

export class EngagementService {
    /**
     * Atomically log an engagement event with optional idempotency key.
     */
    public static async logEvent(params: {
        userId: string;
        targetUserId?: string | null;
        eventType: EngagementEventType | string;
        entityType?: string;
        entityId?: string;
        idempotencyKey?: string;
        metadata?: object;
    }): Promise<UserEngagementEvent | null> {
        try {
            const { userId, targetUserId, eventType, entityType, entityId, idempotencyKey, metadata } = params;

            if (idempotencyKey) {
                const existing = await UserEngagementEvent.findOne({ where: { idempotencyKey } });
                if (existing) {
                    return existing;
                }
            }

            const event = await UserEngagementEvent.create({
                userId,
                targetUserId: targetUserId || null,
                eventType,
                entityType: entityType || null,
                entityId: entityId || null,
                idempotencyKey: idempotencyKey || null,
                metadata: metadata || null,
            });

            logger.info(`[EngagementService] Logged ${eventType} for user ${userId}${targetUserId ? ` -> ${targetUserId}` : ''}`);
            return event;
        } catch (err: any) {
            // Handle unique constraint on idempotencyKey gracefully
            if (err.name === 'SequelizeUniqueConstraintError' && params.idempotencyKey) {
                return UserEngagementEvent.findOne({ where: { idempotencyKey: params.idempotencyKey } });
            }
            logger.warn('[EngagementService] Error logging event:', err);
            return null;
        }
    }

    public static async logLikeSent(userId: string, targetUserId: string, isSuperlike: boolean, matchId?: string): Promise<UserEngagementEvent | null> {
        const eventType = isSuperlike ? EngagementEventType.SUPERLIKE_SENT : EngagementEventType.LIKE_SENT;
        const key = isSuperlike ? `superlike_${userId}_${targetUserId}` : `like_${userId}_${targetUserId}`;
        return this.logEvent({
            userId,
            targetUserId,
            eventType,
            entityType: 'user_match',
            entityId: matchId,
            idempotencyKey: key,
            metadata: { isSuperlike },
        });
    }

    public static async logLikeRemoved(userId: string, targetUserId: string): Promise<UserEngagementEvent | null> {
        return this.logEvent({
            userId,
            targetUserId,
            eventType: EngagementEventType.LIKE_REMOVED,
            entityType: 'user_match',
            metadata: { action: 'unlike' },
        });
    }

    public static async logBoostStarted(userId: string, boostId: string, durationMinutes: number): Promise<UserEngagementEvent | null> {
        return this.logEvent({
            userId,
            eventType: EngagementEventType.PROFILE_BOOST_STARTED,
            entityType: 'profile_boost',
            entityId: boostId,
            idempotencyKey: `boost_start_${boostId}`,
            metadata: { durationMinutes },
        });
    }

    public static async logBoostExpired(userId: string, boostId: string): Promise<UserEngagementEvent | null> {
        return this.logEvent({
            userId,
            eventType: EngagementEventType.PROFILE_BOOST_EXPIRED,
            entityType: 'profile_boost',
            entityId: boostId,
            idempotencyKey: `boost_expire_${boostId}`,
        });
    }

    public static async logReliabilityChanged(userId: string, oldScore: number, newScore: number, change: number, reason: string): Promise<UserEngagementEvent | null> {
        return this.logEvent({
            userId,
            eventType: EngagementEventType.RELIABILITY_CHANGED,
            entityType: 'reliability',
            metadata: { oldScore, newScore, change, reason },
        });
    }
}

export default EngagementService;
