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
import { PartyPlanStatus } from '../models/PartyPlan';
import { StrangersMeetStatus } from '../models/StrangersMeetRequest';
import { GroupPartyStatus } from '../models/GroupParty';
import { logger } from '../config/logger';
import apiCache from '../utils/apiCache';

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

        // Bound candidate scoring window to max 50 to prevent blocking the event loop or database pool
        const targetIds = candidateUserIds.length > 50 ? candidateUserIds.slice(0, 50) : candidateUserIds;

        const cacheKey = `rankings:${targetIds.length}:${targetIds.slice(0, 10).join('_')}`;
        const cached = apiCache.get<ScoreExplanation[]>(cacheKey);
        if (cached) {
            return cached;
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
                        user2Id: { [Op.in]: targetIds },
                        status: { [Op.in]: ['pending', 'connected'] },
                        createdAt: { [Op.gte]: thirtyDaysAgo },
                    },
                    group: ['user2Id'],
                }),
                UserLike.findAll({
                    attributes: ['targetUserId', [UserLike.sequelize!.fn('COUNT', UserLike.sequelize!.col('id')), 'count']],
                    where: {
                        targetUserId: { [Op.in]: targetIds },
                        actionType: 'superlike',
                        createdAt: { [Op.gte]: thirtyDaysAgo },
                    },
                    group: ['targetUserId'],
                }),
                PartyPlan.findAll({
                    attributes: ['userId', [PartyPlan.sequelize!.fn('COUNT', PartyPlan.sequelize!.col('id')), 'count']],
                    where: {
                        userId: { [Op.in]: targetIds },
                        status: { [Op.ne]: PartyPlanStatus.CANCELLED },
                    },
                    group: ['userId'],
                }),
                StrangersMeetRequest.findAll({
                    attributes: ['userId', [StrangersMeetRequest.sequelize!.fn('COUNT', StrangersMeetRequest.sequelize!.col('id')), 'count']],
                    where: {
                        userId: { [Op.in]: targetIds },
                        status: { [Op.notIn]: [StrangersMeetStatus.CANCELLED, StrangersMeetStatus.REJECTED] },
                    },
                    group: ['userId'],
                }),
                GroupParty.findAll({
                    attributes: ['userId', [GroupParty.sequelize!.fn('COUNT', GroupParty.sequelize!.col('id')), 'count']],
                    where: {
                        userId: { [Op.in]: targetIds },
                        status: { [Op.notIn]: [GroupPartyStatus.CANCELLED, GroupPartyStatus.REJECTED, GroupPartyStatus.EXPIRED] },
                    },
                    group: ['userId'],
                }),
                UserSubscription.findAll({
                    where: {
                        userId: { [Op.in]: targetIds },
                        status: SubscriptionStatus.ACTIVE,
                        endDate: { [Op.gt]: now },
                    },
                    include: [{ model: SubscriptionPackage, as: 'package', attributes: ['tier'] }],
                    order: [['createdAt', 'DESC']],
                }),
                ProfileBoost.findAll({
                    where: {
                        userId: { [Op.in]: targetIds },
                        status: ProfileBoostStatus.ACTIVE,
                        expiresAt: { [Op.gt]: now },
                    },
                }),
                User.findAll({
                    where: { id: { [Op.in]: targetIds } },
                    attributes: ['id', 'reliabilityScore', 'isVerified'],
                    include: [
                        { model: UserProfile, as: 'profile', attributes: ['bio', 'occupation', 'city'] },
                        { model: UserPhoto, as: 'photos', where: { isPrimary: true }, required: false, attributes: ['id'] },
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
            const rankings: ScoreExplanation[] = targetIds.map((userId) => {
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

                // 1st Priority: Boost bonus (Boosted profiles immediately jump to the top of discovery)
                const activeBoostScore = hasActiveBoost ? 5000000 : 0;

                // 2nd Priority: Activated Subscription Plan / Tier (ELITE > PRO > PLUS > CORE > FREE)
                // Tier scores: ELITE = 1,000,000, PRO = 750,000, PLUS = 500,000, CORE = 250,000, FREE = 0
                const vipTierScore = tierRank * 250000;

                // 3rd Priority: Likes, Superlikes, and Plans
                const engagementScore = (likes * 1000) + (superlikes * 500) + (plans * 250);

                // Reliability tie-breakers
                const reliabilityTieBreaker = reliabilityScore * 5;

                // Priority Tier categorization (1: Boosted / ELITE, 2: PRO, 3: PLUS, 4: CORE, 5: Base)
                let priorityTier = 5;
                if (hasActiveBoost) priorityTier = 1;
                else if (tierRank === 4) priorityTier = 1;
                else if (tierRank === 3) priorityTier = 2;
                else if (tierRank === 2) priorityTier = 3;
                else if (tierRank === 1) priorityTier = 4;
                else if (engagementScore > 1000) priorityTier = 4;

                // Balanced Final Ranking Score: Boost 1st (5M), Plan tier 2nd (0-1M), then likes, superlikes, plans
                const finalRankScore =
                    activeBoostScore +
                    vipTierScore +
                    engagementScore +
                    reliabilityTieBreaker +
                    profileQualityScore;

                return {
                    userId,
                    finalRankScore,
                    priorityTier,
                    breakdown: {
                        recencyEngagementScore: engagementScore,
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
            apiCache.set(cacheKey, rankings, 60);
            return rankings;
        } catch (err: any) {
            logger.error('[RankingService] Error computing rankings:', err);
            return targetIds.map((userId) => ({
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

    public static invalidateCache(): void {
        apiCache.invalidatePrefix('rankings');
    }
}

export default RankingService;
