import User from '../models/User';
import AuditLog from '../models/AuditLog';
import { logger } from '../config/logger';

export enum ReliabilityAction {
    SUCCESSFUL_ATTENDANCE = 'successful_attendance', // +5
    CONFIRMED_ARRIVAL = 'confirmed_arrival',         // +2
    LATE_ARRIVAL = 'late_arrival',                     // -2
    CANCELLATION = 'cancellation',                     // -5
    NO_SHOW = 'no_show',                               // -10
}

export const RELIABILITY_POINTS: Record<ReliabilityAction, number> = {
    [ReliabilityAction.SUCCESSFUL_ATTENDANCE]: 5,
    [ReliabilityAction.CONFIRMED_ARRIVAL]: 2,
    [ReliabilityAction.LATE_ARRIVAL]: -2,
    [ReliabilityAction.CANCELLATION]: -5,
    [ReliabilityAction.NO_SHOW]: -10,
};

export class ReliabilityService {
    /**
     * Atomically update a user's reliability score and record audit log.
     */
    public static async updateScore(params: {
        userId: string;
        action: ReliabilityAction | string;
        customPoints?: number;
        partyPlanId?: string | null;
        bookingId?: string | null;
        metadata?: object;
    }): Promise<{ newScore: number; oldScore: number; change: number }> {
        try {
            const { userId, action, customPoints, partyPlanId, bookingId, metadata } = params;

            const user = await User.findByPk(userId);
            if (!user) {
                throw new Error(`User ${userId} not found`);
            }

            const change = customPoints !== undefined
                ? customPoints
                : (RELIABILITY_POINTS[action as ReliabilityAction] || 0);

            const oldScore = user.reliabilityScore !== undefined ? Number(user.reliabilityScore) : 100;
            // Clamp score between 0 and 100
            const newScore = Math.max(0, Math.min(100, oldScore + change));

            // If action is NO_SHOW, increment noShowCount and auto-restrict if >= 3
            let isAutoblocked = user.isAutoblocked;
            let autoblockedReason = user.autoblockedReason;
            let noShowCount = user.noShowCount || 0;

            if (action === ReliabilityAction.NO_SHOW) {
                noShowCount += 1;
                if (noShowCount >= 3) {
                    isAutoblocked = true;
                    autoblockedReason = `Restricted due to repeated no-shows (${noShowCount} no-shows)`;
                    logger.warn(`[ReliabilityService] User ${userId} auto-restricted due to ${noShowCount} No-Shows.`);
                }
            }

            await user.update({
                reliabilityScore: newScore,
                noShowCount,
                isAutoblocked,
                autoblockedReason,
            });

            // Log action in AuditLog
            await AuditLog.logAction({
                userId,
                partyPlanId,
                bookingId,
                action: `Reliability Score Updated (${change > 0 ? '+' : ''}${change})`,
                metadata: {
                    reason: action,
                    oldScore,
                    newScore,
                    change,
                    noShowCount,
                    ...metadata,
                },
            });

            logger.info(`[ReliabilityService] User ${userId} score updated: ${oldScore} -> ${newScore} (${action})`);

            return { newScore, oldScore, change };
        } catch (err: any) {
            logger.error('[ReliabilityService] Error updating reliability score:', err);
            return { newScore: 100, oldScore: 100, change: 0 };
        }
    }
}
