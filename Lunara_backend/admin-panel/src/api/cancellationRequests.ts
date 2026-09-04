import apiClient from './client';

// ── Types ──────────────────────────────────────────────────────────────────

export interface PayoutDetails {
    refundMethod?: 'UPI' | 'BANK' | 'WALLET' | string;
    upiId?: string;
    upiPhoneNumber?: string;
    accountNumber?: string;
    ifscCode?: string;
    accountHolderName?: string;
    bankName?: string;
    [key: string]: any;
}

export interface UserSummary {
    id: string;
    firstName: string;
    lastName: string;
    email: string;
    phone: string;
    avatar?: string;
    photoUrl?: string;
}

export interface VenueSummary {
    id: string;
    name: string;
    city?: string;
    area?: string;
    imageUrl?: string;
}

// ── Group Party Cancellation Type ──
export interface GroupPartyCancellationItem {
    id: string;
    type: 'group_party' | 'with_friends';
    partyTitle: string;
    numberOfFriends: number;
    totalAmount: number;
    refundAmount: number;
    refundStatus: 'PENDING_PAYOUT' | 'COMPLETED' | 'REJECTED' | 'NOT_APPLICABLE' | string;
    cancellationStatus?: string;
    cancellationReason?: string;
    refundPayoutDetails?: PayoutDetails;
    refundTransactionReference?: string;
    refundPaidAt?: string;
    refundNotes?: string;
    cancelledAt?: string;
    partyDate?: string;
    venue?: VenueSummary;
    creator?: UserSummary;
}

// ── Large Party Cancellation Type ──
export interface LargePartyCancellationItem {
    id: string;
    bookingId: string;
    userId: string;
    status: 'PENDING_ADMIN_REVIEW' | 'APPROVED' | 'REFUND_PROCESSING' | 'COMPLETED' | 'REJECTED' | string;
    reasonCategory: string;
    reasonDetails?: string;
    totalGuests: number;
    bookingAmount: number;
    eligibleRefundPercentage?: number;
    approvedRefundPercentage?: number;
    refundAmount: number;
    refundMethod?: 'UPI' | 'BANK' | 'WALLET' | string;
    payoutDetails?: PayoutDetails;
    paymentReference?: string;
    paymentNotes?: string;
    paidAt?: string;
    rejectionReason?: string;
    adminNotes?: string;
    createdAt: string;
    booking?: {
        id: string;
        bookingNumber?: string;
        venue?: VenueSummary;
        eventDate?: string;
        startTime?: string;
        guestCount?: number;
        totalAmount?: number;
    };
    user?: UserSummary;
}

// ── Stranger Meet Cancellation Type ──
export interface StrangerMeetMemberRefund {
    id: string;
    cancellationRequestId: string;
    meetMemberId?: string;
    userId: string;
    amountPaid: number;
    refundPercentage: number;
    refundAmount: number;
    refundStatus: 'PENDING' | 'WALLET_CREDITED' | 'PAID' | 'FAILED' | string;
    destinationType: 'WALLET' | 'BANK' | 'UPI' | string;
    payoutDetails?: PayoutDetails;
    transactionReference?: string;
    processedAt?: string;
    processedBy?: string;
    user?: {
        id: string;
        firstName: string;
        lastName: string;
        phone: string;
        email?: string;
    };
}

export interface StrangerMeetCancellationItem {
    id: string;
    meetId: string;
    hostUserId: string;
    reasonCategory: string;
    reasonText?: string;
    status: 'PENDING_ADMIN_REVIEW' | 'APPROVED' | 'REFUND_PROCESSING' | 'COMPLETED' | 'REJECTED' | string;
    totalMembersCount: number;
    totalCollectedAmount: number;
    refundPolicyPercentage?: number;
    refundMethod?: 'WALLET' | 'MANUAL_PAYOUT' | string;
    totalRefundAmount?: number;
    adminReviewedBy?: string;
    adminReviewedAt?: string;
    adminNotes?: string;
    hostDepositAmount?: number;
    hostRefundType?: 'FULL' | 'PARTIAL' | 'CUSTOM' | 'NO_REFUND' | string;
    hostRefundPercentage?: number;
    hostRefundAmount?: number;
    hostRefundDestination?: 'WALLET' | 'UPI' | 'BANK' | 'NONE' | string;
    hostRefundStatus?: 'NONE' | 'WALLET_CREDITED' | 'HOST_REFUND_PENDING_SETTLEMENT' | 'PAID' | string;
    hostPayoutDetails?: PayoutDetails;
    hostSettlementTransactionId?: string;
    hostSettledAt?: string;
    hostSettlementNotes?: string;
    createdAt: string;
    host?: UserSummary;
    meet?: {
        id: string;
        subject: string;
        eventDateTime: string;
        numberOfPersons: number;
        paymentAmount: number;
        chargesPerHead?: number;
        venue?: VenueSummary;
    };
    memberRefunds?: StrangerMeetMemberRefund[];
}

export interface ListParams {
    page?: number;
    limit?: number;
    status?: string;
    search?: string;
}

// ── API Methods ────────────────────────────────────────────────────────────

export const cancellationRequestsApi = {
    // ── 1. Group Party Cancellations (> ₹1,500) ──
    getGroupPartyCancellations: (params?: ListParams): Promise<{
        success: boolean;
        data: GroupPartyCancellationItem[];
        total: number;
        page: number;
        limit: number;
    }> => {
        const queryParams = new URLSearchParams();
        if (params?.page) queryParams.set('page', String(params.page));
        if (params?.limit) queryParams.set('limit', String(params.limit));
        if (params?.status && params.status !== 'all') queryParams.set('status', params.status);
        if (params?.search) queryParams.set('search', params.search);
        return apiClient.get(`/api/admin/bookings/group-party-cancellations?${queryParams.toString()}`);
    },

    getGroupPartyCancellationDetail: (id: string): Promise<{ success: boolean; data: GroupPartyCancellationItem }> => {
        return apiClient.get(`/api/admin/bookings/group-party-cancellations/${id}`);
    },

    markGroupPartyRefundPaid: (id: string, data: { paymentReference: string; notes?: string }): Promise<{
        success: boolean;
        message: string;
        data: any;
    }> => {
        return apiClient.post(`/api/admin/bookings/group-party-cancellations/${id}/mark-paid`, data);
    },

    // ── 2. Large Party Cancellations (> 20 Guests) ──
    getLargePartyCancellations: (params?: ListParams): Promise<{
        success: boolean;
        items: LargePartyCancellationItem[];
        total: number;
        page: number;
        limit: number;
        totalPages: number;
    }> => {
        const queryParams = new URLSearchParams();
        if (params?.page) queryParams.set('page', String(params.page));
        if (params?.limit) queryParams.set('limit', String(params.limit));
        if (params?.status && params.status !== 'all') queryParams.set('status', params.status);
        if (params?.search) queryParams.set('search', params.search);
        return apiClient.get(`/api/admin/bookings/large-party-cancellations?${queryParams.toString()}`);
    },

    getLargePartyCancellationDetail: (id: string): Promise<{ success: boolean; data: LargePartyCancellationItem }> => {
        return apiClient.get(`/api/admin/bookings/large-party-cancellations/${id}`);
    },

    approveLargePartyCancellation: (id: string, data: {
        refundPercentage: number;
        refundMethod?: string;
        adminNotes?: string;
    }): Promise<{ success: boolean; message: string; data: any }> => {
        return apiClient.post(`/api/admin/bookings/large-party-cancellations/${id}/approve`, data);
    },

    rejectLargePartyCancellation: (id: string, data: {
        rejectionReason: string;
    }): Promise<{ success: boolean; message: string; data: any }> => {
        return apiClient.post(`/api/admin/bookings/large-party-cancellations/${id}/reject`, data);
    },

    markLargePartyRefundPaid: (id: string, data: {
        paymentReference: string;
        paymentNotes?: string;
    }): Promise<{ success: boolean; message: string; data: any }> => {
        return apiClient.post(`/api/admin/bookings/large-party-cancellations/${id}/mark-paid`, data);
    },

    // ── 3. Stranger Meet Cancellations ──
    getStrangerMeetCancellations: (params?: ListParams): Promise<{
        success: boolean;
        data: {
            cancellations: StrangerMeetCancellationItem[];
            total: number;
            page: number;
            limit: number;
            totalPages: number;
        };
    }> => {
        const queryParams = new URLSearchParams();
        if (params?.page) queryParams.set('page', String(params.page));
        if (params?.limit) queryParams.set('limit', String(params.limit));
        if (params?.status && params.status !== 'all') queryParams.set('status', params.status);
        if (params?.search) queryParams.set('search', params.search);
        return apiClient.get(`/api/admin/strangers-meet/cancellations?${queryParams.toString()}`);
    },

    getStrangerMeetCancellationDetail: (id: string): Promise<{ success: boolean; data: StrangerMeetCancellationItem }> => {
        return apiClient.get(`/api/admin/strangers-meet/cancellations/${id}`);
    },

    approveStrangerMeetCancellation: (id: string, data: {
        refundPercentage?: number;
        refundMethod?: string;
        adminNotes?: string;
        hostRefundDecision?: string;
        hostRefundPercentage?: number;
        hostRefundCustomAmount?: number;
        hostRefundDestination?: string;
    }): Promise<{ success: boolean; message: string; data: any }> => {
        return apiClient.post(`/api/admin/strangers-meet/cancellations/${id}/approve`, data);
    },

    rejectStrangerMeetCancellation: (id: string, data: {
        reason: string;
    }): Promise<{ success: boolean; message: string; data: any }> => {
        return apiClient.post(`/api/admin/strangers-meet/cancellations/${id}/reject`, data);
    },

    settleStrangerMeetHostRefund: (id: string, data: {
        paymentReference: string;
        paymentMethod?: string;
        notes?: string;
    }): Promise<{ success: boolean; message: string; data: any }> => {
        return apiClient.post(`/api/admin/strangers-meet/cancellations/${id}/settle-host-refund`, data);
    },

    markStrangerMeetMemberRefundPaid: (refundId: string, data: {
        paymentReference: string;
        paymentMethod?: string;
    }): Promise<{ success: boolean; message: string; data: any }> => {
        return apiClient.post(`/api/admin/strangers-meet/cancellations/member-refunds/${refundId}/mark-paid`, data);
    },

    retryStrangerMeetMemberWalletRefund: (refundId: string): Promise<{ success: boolean; message: string; data: any }> => {
        return apiClient.post(`/api/admin/strangers-meet/cancellations/member-refunds/${refundId}/retry-wallet`);
    },
};

export default cancellationRequestsApi;
