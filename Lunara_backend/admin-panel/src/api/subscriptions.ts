import apiClient from './client';

// ─── Types ────────────────────────────────────────────────────────────────────

export interface SubscriptionPlan {
    id: string;
    name: string;
    displayName?: string;
    description?: string;
    tier: string;
    price: number;
    durationDays: number;
    currency: string;
    themeColor?: string;
    badge?: string;
    icon?: string;
    isActive: boolean;
    isArchived?: boolean;
    isPopular?: boolean;
    isRecommended?: boolean;
    displayOrder: number;
    dailyMatchRequests: number;
    dailyLikes: number;
    dailyPosts: number;
    superlikesPerCycle: number;
    boostsPerCycle: number;
    hasHideProfile: boolean;
    hasPriorityVisibility: boolean;
    hasTrustBadge: boolean;
    hasEliteBadge: boolean;
    canSeeWhoLiked: boolean;
    trialDays?: number;
    gracePeriodDays?: number;
    discountPercent?: number;
    visibility?: string;
    // Computed
    activeSubscribers?: number;
    totalRevenue?: number;
    createdAt: string;
    updatedAt: string;
}

export interface SubscriptionFeature {
    id: string;
    key: string;
    name: string;
    description?: string;
    category: string;
    valueType: 'boolean' | 'integer' | 'decimal' | 'unlimited' | 'text';
    displayOrder: number;
    isActive: boolean;
    icon?: string;
    createdAt: string;
    updatedAt: string;
}

export interface PlanFeature {
    id: string;
    packageId: string;
    featureId: string;
    value: Record<string, any>;
    isEnabled: boolean;
    feature?: SubscriptionFeature;
}

export interface SubscriptionTransaction {
    id: string;
    userId: string;
    packageId?: string;
    type: string;
    amount: number;
    currency: string;
    paymentMethod?: string;
    paymentGateway: string;
    gatewayOrderId?: string;
    gatewayPaymentId?: string;
    status: string;
    invoiceNumber?: string;
    refundAmount: number;
    refundedAt?: string;
    metadata?: Record<string, any>;
    user?: { id: string; firstName: string; lastName: string; email: string };
    package?: { id: string; name: string; tier: string };
    createdAt: string;
    updatedAt: string;
}

export interface AnalyticsOverview {
    stats: {
        totalPlans: number;
        activeSubscribers: number;
        expiredCount: number;
        monthlyRevenue: number;
        lastMonthRevenue: number;
        totalRevenue: number;
        trialUsers: number;
        popularPlan: string;
        revenueGrowth: number | string;
    };
    planDistribution: { planName: string; count: number; tier: string }[];
    growthData: { month: string; subscribers: number; revenue: number }[];
}

// ─── API Object ───────────────────────────────────────────────────────────────

export const subscriptionsApi = {

    // ── Plans ──────────────────────────────────────────────────────────────────

    getPlans: (): Promise<{ success: boolean; data: SubscriptionPlan[] }> =>
        apiClient.get('/api/admin/subscriptions'),

    createPlan: (data: Partial<SubscriptionPlan>): Promise<{ success: boolean; data: SubscriptionPlan; message: string }> =>
        apiClient.post('/api/admin/subscriptions', data),

    updatePlan: (id: string, data: Partial<SubscriptionPlan>): Promise<{ success: boolean; data: SubscriptionPlan; message: string }> =>
        apiClient.put(`/api/admin/subscriptions/${id}`, data),

    deletePlan: (id: string): Promise<{ success: boolean; message: string }> =>
        apiClient.delete(`/api/admin/subscriptions/${id}`),

    duplicatePlan: (id: string): Promise<{ success: boolean; data: SubscriptionPlan; message: string }> =>
        apiClient.post(`/api/admin/subscriptions/${id}/duplicate`),

    archivePlan: (id: string): Promise<{ success: boolean; message: string }> =>
        apiClient.patch(`/api/admin/subscriptions/${id}/archive`),

    togglePlanStatus: (id: string): Promise<{ success: boolean; data: { isActive: boolean }; message: string }> =>
        apiClient.patch(`/api/admin/subscriptions/${id}/toggle-status`),

    seedDefaults: (): Promise<{ success: boolean; message: string }> =>
        apiClient.post('/api/admin/subscriptions/seed'),

    // ── Plan Features ──────────────────────────────────────────────────────────

    getPlanFeatures: (planId: string): Promise<{ success: boolean; data: PlanFeature[] }> =>
        apiClient.get(`/api/admin/subscriptions/${planId}/features`),

    updatePlanFeatures: (planId: string, features: Array<{ featureId: string; value: any; isEnabled: boolean }>): Promise<{ success: boolean; message: string }> =>
        apiClient.put(`/api/admin/subscriptions/${planId}/features`, { features }),

    // ── Feature Catalog ────────────────────────────────────────────────────────

    getFeatures: (): Promise<{ success: boolean; data: SubscriptionFeature[] }> =>
        apiClient.get('/api/admin/subscriptions/features'),

    createFeature: (data: Partial<SubscriptionFeature>): Promise<{ success: boolean; data: SubscriptionFeature; message: string }> =>
        apiClient.post('/api/admin/subscriptions/features', data),

    updateFeature: (id: string, data: Partial<SubscriptionFeature>): Promise<{ success: boolean; data: SubscriptionFeature; message: string }> =>
        apiClient.put(`/api/admin/subscriptions/features/${id}`, data),

    deleteFeature: (id: string): Promise<{ success: boolean; message: string }> =>
        apiClient.delete(`/api/admin/subscriptions/features/${id}`),

    // ── Analytics ──────────────────────────────────────────────────────────────

    getAnalytics: (): Promise<{ success: boolean; data: AnalyticsOverview }> =>
        apiClient.get('/api/admin/subscriptions/analytics/overview'),

    // ── Transactions ───────────────────────────────────────────────────────────

    getTransactions: (params?: { page?: number; limit?: number; status?: string; type?: string }): Promise<{
        success: boolean;
        data: {
            transactions: SubscriptionTransaction[];
            pagination: { page: number; limit: number; total: number; totalPages: number };
        };
    }> => apiClient.get('/api/admin/subscriptions/transactions', { params }),

    // ── Subscribed Users ───────────────────────────────────────────────────────

    getSubscribedUsers: (params?: { page?: number; limit?: number }): Promise<any> =>
        apiClient.get('/api/admin/subscriptions/users', { params }),
};

export default subscriptionsApi;
