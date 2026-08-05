import User from '../models/User';
import PartyPlan from '../models/PartyPlan';
import WalletTransaction from '../models/WalletTransaction';
import { logger } from '../config/logger';

export interface UserRiskAssessment {
    userId: string;
    riskScore: number; // 0 to 100
    riskLevel: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
    flags: string[];
    details: {
        noShowCount: number;
        reliabilityScore: number;
        cancelledPlansCount: number;
        failedWalletTxnCount: number;
        isAutoblocked: boolean;
    };
}

export class FraudDetectionService {
    /**
     * Calculates the dynamic risk score and security flags for a given user.
     */
    public static async evaluateUserRisk(userId: string): Promise<UserRiskAssessment> {
        try {
            const user = await User.findByPk(userId);
            if (!user) {
                return {
                    userId,
                    riskScore: 0,
                    riskLevel: 'LOW',
                    flags: ['USER_NOT_FOUND'],
                    details: { noShowCount: 0, reliabilityScore: 100, cancelledPlansCount: 0, failedWalletTxnCount: 0, isAutoblocked: false }
                };
            }

            let riskScore = 0;
            const flags: string[] = [];

            // 1. Check No-Show History
            const noShowCount = user.noShowCount || 0;
            if (noShowCount >= 2) {
                riskScore += 45;
                flags.push('REPEATED_NO_SHOWS');
            } else if (noShowCount === 1) {
                riskScore += 20;
                flags.push('SINGLE_NO_SHOW');
            }

            // 2. Check Reliability Score
            const relScore = user.reliabilityScore !== undefined ? Number(user.reliabilityScore) : 100;
            if (relScore < 40) {
                riskScore += 35;
                flags.push('CRITICAL_RELIABILITY_SCORE');
            } else if (relScore < 70) {
                riskScore += 15;
                flags.push('LOW_RELIABILITY_SCORE');
            }

            // 3. Check Cancellation Frequency
            const cancelledPlansCount = await PartyPlan.count({
                where: { userId, status: 'cancelled' as any }
            });
            if (cancelledPlansCount >= 3) {
                riskScore += 20;
                flags.push('HIGH_CANCELLATION_RATE');
            }

            // 4. Check Failed Wallet Transactions
            const failedWalletTxnCount = await WalletTransaction.count({
                where: { userId, status: 'failed' as any }
            });
            if (failedWalletTxnCount >= 3) {
                riskScore += 15;
                flags.push('REPEATED_PAYMENT_FAILURES');
            }

            // 5. Auto-blocked Check
            if (user.isAutoblocked) {
                riskScore += 30;
                flags.push('AUTOBLOCKED_USER');
            }

            // Clamp Risk Score (0-100)
            riskScore = Math.min(100, riskScore);

            let riskLevel: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL' = 'LOW';
            if (riskScore >= 75) riskLevel = 'CRITICAL';
            else if (riskScore >= 50) riskLevel = 'HIGH';
            else if (riskScore >= 25) riskLevel = 'MEDIUM';

            if (riskScore >= 50) {
                logger.warn(`[FraudDetectionService] High risk user detected: ${userId} (Score: ${riskScore}, Level: ${riskLevel})`);
            }

            return {
                userId,
                riskScore,
                riskLevel,
                flags,
                details: {
                    noShowCount,
                    reliabilityScore: relScore,
                    cancelledPlansCount,
                    failedWalletTxnCount,
                    isAutoblocked: Boolean(user.isAutoblocked),
                }
            };
        } catch (err: any) {
            logger.error('[FraudDetectionService] Error evaluating risk:', err);
            return {
                userId,
                riskScore: 0,
                riskLevel: 'LOW',
                flags: ['EVALUATION_ERROR'],
                details: { noShowCount: 0, reliabilityScore: 100, cancelledPlansCount: 0, failedWalletTxnCount: 0, isAutoblocked: false }
            };
        }
    }

    /**
     * Scans for top high-risk users across the platform.
     */
    public static async getFlaggedRiskUsers(limit: number = 20): Promise<UserRiskAssessment[]> {
        try {
            const highNoShowUsers = await User.findAll({
                where: {
                    isAutoblocked: true,
                },
                limit,
            });

            const assessments: UserRiskAssessment[] = [];
            for (const u of highNoShowUsers) {
                const evalData = await this.evaluateUserRisk(u.id);
                assessments.push(evalData);
            }
            return assessments;
        } catch (err: any) {
            logger.error('[FraudDetectionService] Error fetching flagged risk users:', err);
            return [];
        }
    }
}
