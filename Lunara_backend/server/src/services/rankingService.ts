import { Op } from 'sequelize';
import {
    User,
    UserMatch,
    UserLike,
    PartyPlan,
    StrangersMeetRequest,
    GroupParty,
    UserSubscription,
    SubscriptionPackage,
    ProfileBoost,
    UserProfile,
    UserPhoto,
} from '../models';
import { SubscriptionStatus } from '../models/UserSubscription';
import { ProfileBoostStatus } from '../models/ProfileBoost';
import { logger } from '../config/logger';

export interface ScoreExplanation {
    userId: string;
    finalRankScore: number;
    priorityTier: number;
    breakdown: {
        recencyEngagementScore: number;
        reliabilityScore: number;
        profileQualityScore: number;
        activeBoostScore: number;
        vipTierScore: number;
    };
    rawMetrics: {
        likesCount: number;
        superlikesCount: number;
        plansCount: number;
        reliabilityScore: number;
        hasActiveBoost: boolean;
        vipTier: string;
    };
}

export class RankingService {
    private static tierRankMap: Record<string, number> = {
        FREE: 0,
        CORE: 1,
        PLUS: 2,
        PRO: 3,
        ELITE: 4,
    };

    /**
     * Compute discovery ranking for a list of candidate user IDs.
     * Implements 30-day recency decay, reliability score weighting, active boost influence,
     * profile completeness, and explainable breakdowns.
     */
    public static async computeRankings(candidateUserIds: string[]): Promise<ScoreExplanation[]> {
        if (!candidateUserIds || candidateUserIds.length === 0) {
            return [];
        }

        const now = new Date();
        const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

        try {
            // 1. Fetch recent likes & superlikes (with 30-day recency window)
            const [
                likesAgg,
                superlikesAgg,
                plansAgg,
                strangersMeetAgg,
                groupPartyAgg,
                activeSubs,
                activeBoosts,
                usersWithProfiles
            ] = await Promise.all([
                UserMatch.findAll({
                    attributes: ['user2Id', [UserMatch.sequelize!.fn('COUNT', UserMatch.sequelize!.col('id')), 'count']],
                    where: {
                        user2Id: { [Op.in]: candidateUserIds },
                        status: { [Op.in]: ['pending', 'connected'] },
                        createdAt: { [Op.gte]: thirtyDaysAgo },
                    },
                    group: ['user2Id'],
                }),
                UserLike.findAll({
                    attributes: ['targetUserId', [UserLike.sequelize!.fn('COUNT', UserLike.sequelize!.col('id')), 'count']],
                    where: {
                        targetUserId: { [Op.in]: candidateUserIds },
                        actionType: 'superlike',
                        createdAt: { [Op.gte]: thirtyDaysAgo },
                    },
                    group: ['targetUserId'],
                }),
                PartyPlan.findAll({
                    attributes: ['userId', [PartyPlan.sequelize!.fn('COUNT', PartyPlan.sequelize!.col('id')), 'count']],
                    where: {
                        userId: { [Op.in]: candidateUserIds },
                        status: { [Op.notIn]: ['cancelled', 'rejected'] },
                    },
                    group: ['userId'],
                }),
                StrangersMeetRequest.findAll({
                    attributes: ['userId', [StrangersMeetRequest.sequelize!.fn('COUNT', StrangersMeetRequest.sequelize!.col('id')), 'count']],
                    where: {
                        userId: { [Op.in]: candidateUserIds },
                        status: { [Op.notIn]: ['cancelled', 'rejected', 'expired'] },
                    },
                    group: ['userId'],
                }),
                GroupParty.findAll({
                    attributes: ['userId', [GroupParty.sequelize!.fn('COUNT', GroupParty.sequelize!.col('id')), 'count']],
                    where: {
                        userId: { [Op.in]: candidateUserIds },
                        status: { [Op.notIn]: ['cancelled', 'rejected'] },
                    },
                    group: ['userId'],
                }),
                UserSubscription.findAll({
                    where: {
                        userId: { [Op.in]: candidateUserIds },
                        status: SubscriptionStatus.ACTIVE,
                        endDate: { [Op.gt]: now },
                    },
                    include: [{ model: SubscriptionPackage, as: 'package', attributes: ['tier'] }],
                    order: [['createdAt', 'DESC']],
                }),
                ProfileBoost.findAll({
                    where: {
                        userId: { [Op.in]: candidateUserIds },
                        status: ProfileBoostStatus.ACTIVE,
                        expiresAt: { [Op.gt]: now },
                    },
                }),
                User.findAll({
                    where: { id: { [Op.in]: candidateUserIds } },
                    attributes: ['id', 'reliabilityScore', 'isVerified'],
                    include: [
                        { model: UserProfile, as: 'profile' },
                        { model: UserPhoto, as: 'photos', where: { isPrimary: true }, required: false },
                    ],
                }),
            ]);

            // Map data
            const likesMap = new Map<string, number>();
            likesAgg.forEach((r: any) => likesMap.set(r.getDataValue('user2Id'), parseInt(r.getDataValue('count')) || 0));

            const superlikesMap = new Map<string, number>();
            superlikesAgg.forEach((r: any) => superlikesMap.set(r.getDataValue('targetUserId'), parseInt(r.getDataValue('count')) || 0));

            const plansMap = new Map<string, number>();
            plansAgg.forEach((r: any) => plansMap.set(r.getDataValue('userId'), (plansMap.get(r.getDataValue('userId')) || 0) + (parseInt(r.getDataValue('count')) || 0)));
            strangersMeetAgg.forEach((r: any) => plansMap.set(r.getDataValue('userId'), (plansMap.get(r.getDataValue('userId')) || 0) + (parseInt(r.getDataValue('count')) || 0)));
            groupPartyAgg.forEach((r: any) => plansMap.set(r.getDataValue('userId'), (plansMap.get(r.getDataValue('userId')) || 0) + (parseInt(r.getDataValue('count')) || 0)));

            const vipTierMap = new Map<string, string>();
            const seenSubUsers = new Set<string>();
            for (const sub of activeSubs) {
                if (!seenSubUsers.has(sub.userId)) {
                    seenSubUsers.add(sub.userId);
                    vipTierMap.set(sub.userId, (sub as any).package?.tier || 'FREE');
                }
            }

            const activeBoostUsers = new Set<string>();
            activeBoosts.forEach((b: any) => activeBoostUsers.add(b.userId));

            const userMap = new Map<string, any>();
            usersWithProfiles.forEach((u: any) => userMap.set(u.id, u));

            // Calculate score per user
            const rankings: ScoreExplanation[] = candidateUserIds.map((userId) => {
                const u = userMap.get(userId);
                const likes = likesMap.get(userId) || 0;
                const superlikes = superlikesMap.get(userId) || 0;
                const plans = plansMap.get(userId) || 0;
                const vipTier = vipTierMap.get(userId) || 'FREE';
                const tierRank = this.tierRankMap[vipTier] || 0;
                const hasActiveBoost = activeBoostUsers.has(userId);

                const reliabilityScore = u?.reliabilityScore !== undefined ? Number(u.reliabilityScore) : 70;

                // Profile Quality calculation (photos, bio, verified)
                let profileQualityScore = 20;
                if (u?.profile?.bio && u.profile.bio.length > 20) profileQualityScore += 20;
                if (u?.profile?.occupation) profileQualityScore += 10;
                if (u?.profile?.city) profileQualityScore += 10;
                if (u?.photos && u.photos.length > 0) profileQualityScore += 20;
                if (u?.isVerified) profileQualityScore += 20;

                // Recency Engagement score
                const recencyEngagementScore = (likes * 15) + (superlikes * 40) + (plans * 25);

                // Active Boost Score (granted ONLY when an active boost is running)
                const activeBoostScore = hasActiveBoost ? 5000 : 0;

                // VIP Tier Score
                const vipTierScore = tierRank * 500;

                // Priority Tier categorization (1: Boost+VIP, 2: Boost, 3: VIP, 4: Organic High, 5: Base)
                let priorityTier = 5;
                if (hasActiveBoost && tierRank > 0) priorityTier = 1;
                else if (hasActiveBoost) priorityTier = 2;
                else if (tierRank > 0) priorityTier = 3;
                else if (recencyEngagementScore > 60) priorityTier = 4;

                // Balanced Final Ranking Score
                const finalRankScore =
                    (priorityTier === 1 ? 20000 : (priorityTier === 2 ? 10000 : (priorityTier === 3 ? 2000 : 0))) +
                    recencyEngagementScore +
                    (reliabilityScore * 5) +
                    profileQualityScore +
                    activeBoostScore +
                    vipTierScore;

                return {
                    userId,
                    finalRankScore,
                    priorityTier,
                    breakdown: {
                        recencyEngagementScore,
                        reliabilityScore: reliabilityScore * 5,
                        profileQualityScore,
                        activeBoostScore,
                        vipTierScore,
                    },
                    rawMetrics: {
                        likesCount: likes,
                        superlikesCount: superlikes,
                        plansCount: plans,
                        reliabilityScore,
                        hasActiveBoost,
                        vipTier,
                    },
                };
            });

            // Sort descending by finalRankScore
            rankings.sort((a, b) => b.finalRankScore - a.finalRankScore);
            return rankings;
        } catch (err: any) {
            logger.error('[RankingService] Error computing rankings:', err);
            return candidateUserIds.map((userId) => ({
                userId,
                finalRankScore: 100,
                priorityTier: 5,
                breakdown: {
                    recencyEngagementScore: 0,
                    reliabilityScore: 350,
                    profileQualityScore: 20,
                    activeBoostScore: 0,
                    vipTierScore: 0,
                },
                rawMetrics: {
                    likesCount: 0,
                    superlikesCount: 0,
                    plansCount: 0,
                    reliabilityScore: 70,
                    hasActiveBoost: false,
                    vipTier: 'FREE',
                },
            }));
        }
    }
}

export default RankingService;
