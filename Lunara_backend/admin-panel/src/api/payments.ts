import apiClient from './client';

export interface PaymentSummary {
    totalRevenue: number;
    totalTransactions: number;
    successfulCount: number;
    failedCount: number;
    pendingCount: number;
    averageTransactionValue: number;
    paymentMethods: Array<{ paymentMethod: string; count: string | number }>;
    revenueOverTime: Array<{ date: string; revenue: string | number }>;
}

export interface Payment {
    id: string;
    transactionId: string;
    bookingId: string;
    userId: string;
    amount: number;
    currency: string;
    paymentMethod: string;
    status: string;
    createdAt: string;
    payer?: {
        id: string;
        firstName: string;
        lastName: string;
        email: string;
        profileImageUrl?: string;
    };
}

export interface PaginatedResponse<T> {
    success: boolean;
    data: T[];
    pagination: {
        total: number;
        page: number;
        limit: number;
        totalPages: number;
    };
}

export interface ApiResponse<T> {
    success: boolean;
    data: T;
}

export const paymentsApi = {
    getSummary: async (params?: { startDate?: string; endDate?: string }): Promise<ApiResponse<PaymentSummary>> => {
        return apiClient.get('/api/admin/payments/summary', { params });
    },

    getPayments: async (params?: {
        page?: number;
        limit?: number;
        status?: string;
        search?: string;
        startDate?: string;
        endDate?: string;
    }): Promise<PaginatedResponse<Payment>> => {
        return apiClient.get('/api/admin/payments', { params });
    },
};
