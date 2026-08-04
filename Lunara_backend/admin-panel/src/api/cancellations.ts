import apiClient from './client';

// ── Types ──────────────────────────────────────────────────────────────────

export interface CancellationUserInfo {
    id: string;
    firstName: string;
    lastName: string;
    email: string;
    phone?: string;
    photo?: string;
    profile?: { reliabilityScore?: number; bio?: string };
}

export interface CancellationRecord {
    id: string;
    planId: string;
    bookingId?: string;
    requestedById: string;
    recipientUserId: string;
    status: 'pending' | 'approved' | 'rejected' | 'expired' | 'auto_approved';
    reason: string;
    otherReasonText?: string;
    requestedAt: string;
    expiresAt: string;
    respondedAt?: string;
    respondedById?: string;
    autoApprovalEligible: boolean;
    hostDepositAmount: number;
    joinerDepositAmount: number;
    hostWalletTransactionId?: string;
    joinerWalletTransactionId?: string;
    reliabilityImpact: number;
    plan?: {
        id: string;
        planTitle?: string;
        planDateTime: string;
        status: string;
        venue?: { id: string; name: string; address?: string; city?: string; imageUrl?: string };
    };
    requester?: CancellationUserInfo;
    recipient?: CancellationUserInfo;
    booking?: {
        id: string;
        status: string;
        totalAmount: number;
        paymentStatus: string;
    };
}

export interface CancellationTimeline {
    time: string;
    event: string;
    detail?: string;
    icon: string;
}

export interface CancellationDetail {
    cancellation: CancellationRecord;
    ticket?: {
        id: string;
        status: string;
        qrCode?: string;
        issuedAt?: string;
        expiresAt?: string;
    };
    chatSubscription?: {
        id: string;
        status: string;
        updatedAt: string;
    };
    walletTransactions: any[];
    timeline: CancellationTimeline[];
    reasonLabel: string;
    hoursBeforeEvent?: number;
}

export interface KPIs {
    totalCancelled: number;
    today: number;
    thisWeek: number;
    thisMonth: number;
    pending: number;
    approved: number;
    rejected: number;
    expired: number;
    avgApprovalTimeMinutes: number;
    totalWalletCredits: number;
    avgReliabilityReduction: number;
    avgHoursBeforeCancellation: number;
    hostRequested: number;
    participantRequested: number;
}

export interface CancellationAnalytics {
    kpis: KPIs;
    charts: {
        dailyTrend: Array<{ date: string; count: number }>;
        monthlyTrend: Array<{ month: string; count: number }>;
        reasonDistribution: Array<{ reason: string; count: number }>;
    };
    topReasons: Array<{ reason: string; count: number }>;
    fraudFlags: Array<{
        userId: string;
        user?: CancellationUserInfo;
        cancellations?: number;
        hoursRemaining?: number;
        lastRequest?: string;
        requestId?: string;
        flagType: string;
    }>;
}

export interface Pagination {
    total: number;
    page: number;
    limit: number;
    totalPages: number;
}

export interface ListFilters {
    page?: number;
    limit?: number;
    status?: string;
    reason?: string;
    requestedBy?: string;
    startDate?: string;
    endDate?: string;
    search?: string;
    venueId?: string;
}

// ── API calls ──────────────────────────────────────────────────────────────

const cancellationsApi = {
    /** Get paginated, filtered list of all cancellation requests */
    getList: (filters: ListFilters = {}): Promise<{ success: boolean; data: CancellationRecord[]; pagination: Pagination }> => {
        const params = new URLSearchParams();
        Object.entries(filters).forEach(([k, v]) => {
            if (v !== undefined && v !== '' && v !== 'all') params.set(k, String(v));
        });
        return apiClient.get(`/api/admin/party-plans/cancellations?${params.toString()}`);
    },

    /** Get full detail of a single cancellation request */
    getDetail: (id: string): Promise<{ success: boolean; data: CancellationDetail }> =>
        apiClient.get(`/api/admin/party-plans/cancellations/${id}`),

    /** Get analytics KPIs, charts, and fraud flags */
    getAnalytics: (): Promise<{ success: boolean } & CancellationAnalytics> =>
        apiClient.get('/api/admin/party-plans/cancellations/analytics'),

    /** Flag a cancellation for investigation */
    markForInvestigation: (id: string, notes: string, adminId: string): Promise<{ success: boolean; message: string }> =>
        apiClient.post(`/api/admin/party-plans/cancellations/${id}/investigate`, { notes, adminId }),

    /** Emergency booking restore */
    restoreBooking: (id: string, reason: string, adminId: string): Promise<{ success: boolean; message: string }> =>
        apiClient.post(`/api/admin/party-plans/cancellations/${id}/restore`, { reason, adminId }),

    /** Export cancellations data (returns JSON, client converts to CSV/Excel) */
    exportData: (filters: { startDate?: string; endDate?: string; status?: string } = {}): Promise<{ success: boolean; data: any[]; total: number; exportedAt: string }> => {
        const params = new URLSearchParams();
        Object.entries(filters).forEach(([k, v]) => {
            if (v) params.set(k, v);
        });
        return apiClient.get(`/api/admin/party-plans/cancellations/export?${params.toString()}`);
    },
};

export default cancellationsApi;
