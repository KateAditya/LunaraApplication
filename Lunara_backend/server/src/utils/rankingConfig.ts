export const RankingConfig = {
    // Priority Tier Base Scores
    TIER_1_BASE: 1000000, // Boost + VIP
    TIER_2_BASE: 100000,  // Boost
    TIER_3_BASE: 10000,   // VIP
    
    // Engagement Weights
    SUPER_LIKE_WEIGHT: 50,
    LIKE_WEIGHT: 10,
    PARTY_PLAN_WEIGHT: 20,

    // Time window for "recent" engagement (in days)
    RECENCY_WINDOW_DAYS: 30,

    // Base score applied to everyone
    BASE_USER_SCORE: 120,
};
