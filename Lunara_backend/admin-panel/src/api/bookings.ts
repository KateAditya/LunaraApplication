import apiClient from './client';

export interface Booking {
    id: string;
    bookingNumber: string;
    userId: string;
    venueId: string;
    userName?: string;
    venueName?: string;
    bookingDate: string;
    timeSlot: string;
    partySize: number;
    tableType?: string;
    status: 'pending' | 'confirmed' | 'cancelled' | 'completed' | 'no_show';
    totalAmount: number;
    advanceAmount?: number;
    paymentStatus: 'pending' | 'partial' | 'paid' | 'refunded';
    specialRequests?: string;
    isGroupBooking: boolean;
    createdAt: string;
}

export interface GetBookingsParams {
    page?: number;
    limit?: number;
    search?: string;
    status?: string;
    paymentStatus?: string;
    venueId?: string;
    startDate?: string;
    endDate?: string;
    sortBy?: string;
    sortOrder?: 'asc' | 'desc';
}

export interface GetBookingsResponse {
    success: boolean;
    data: {
        bookings: Booking[];
        pagination: {
            page: number;
            limit: number;
            total: number;
            totalPages: number;
        };
    };
}

export const bookingsApi = {
    getBookings: (params: GetBookingsParams): Promise<GetBookingsResponse> => {
        return apiClient.get('/api/admin/bookings', { params });
    },

    getBooking: (id: string): Promise<{ success: boolean; data: Booking }> => {
        return apiClient.get(`/api/admin/bookings/${id}`);
    },

    confirmBooking: (id: string): Promise<{ success: boolean; data: Booking }> => {
        return apiClient.post(`/api/admin/bookings/${id}/confirm`);
    },

    cancelBooking: (id: string, reason: string): Promise<{ success: boolean; data: Booking }> => {
        return apiClient.post(`/api/admin/bookings/${id}/cancel`, { reason });
    },

    markCompleted: (id: string): Promise<{ success: boolean; data: Booking }> => {
        return apiClient.post(`/api/admin/bookings/${id}/complete`);
    },

    markNoShow: (id: string): Promise<{ success: boolean; data: Booking }> => {
        return apiClient.post(`/api/admin/bookings/${id}/no-show`);
    },

    processRefund: (id: string, amount: number): Promise<{ success: boolean; message: string }> => {
        return apiClient.post(`/api/admin/bookings/${id}/refund`, { amount });
    },

    getBookingStats: (): Promise<{
        success: boolean;
        data: {
            totalBookings: number;
            pendingBookings: number;
            confirmedBookings: number;
            totalRevenue: number;
        };
    }> => {
        return apiClient.get('/api/admin/bookings/stats');
    },

    getLargePartyRequests: (): Promise<{ success: boolean; data: any[] }> => {
        return apiClient.get('/api/admin/bookings/large-party-requests');
    },

    approveLargePartyRequest: (id: string, status: 'approved' | 'rejected', totalAmount?: number): Promise<{ success: boolean; data: any }> => {
        return apiClient.post(`/api/admin/bookings/${id}/approve-party-request`, { status, totalAmount });
    },
};

export default bookingsApi;
