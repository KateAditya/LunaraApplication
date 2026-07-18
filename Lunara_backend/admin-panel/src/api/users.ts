import apiClient from './client';
import type { User } from '../types/user';

export interface GetUsersParams {
    page?: number;
    limit?: number;
    search?: string;
    role?: string;
    isVerified?: boolean;
    isActive?: boolean;
    sortBy?: string;
    sortOrder?: 'asc' | 'desc';
}

export interface GetUsersResponse {
    success: boolean;
    data: {
        users: User[];
        pagination: {
            page: number;
            limit: number;
            total: number;
            totalPages: number;
        };
    };
}

export interface UpdateUserData {
    firstName?: string;
    lastName?: string;
    phone?: string;
    role?: string;
    isActive?: boolean;
    isVerified?: boolean;
    email?: string;
    profile?: Partial<User['profile']>;
    preferences?: Partial<User['preferences']>;
}

export interface GetDeletedAccountsParams {
    page?: number;
    limit?: number;
    search?: string;
    from?: string;
    to?: string;
}

export const usersApi = {
    // ── Active Users ────────────────────────────────────────────────────────

    getUsers: (params: GetUsersParams): Promise<GetUsersResponse> => {
        return apiClient.get('/api/users', { params });
    },

    getUser: (id: string): Promise<{ success: boolean; data: User }> => {
        return apiClient.get(`/api/users/${id}`);
    },

    createUser: (data: any): Promise<{ success: boolean; data: User }> => {
        return apiClient.post('/api/users', data);
    },

    updateUser: (id: string, data: UpdateUserData): Promise<{ success: boolean; data: User }> => {
        return apiClient.put(`/api/users/${id}`, data);
    },

    deleteUser: (id: string): Promise<{ success: boolean; message: string }> => {
        return apiClient.delete(`/api/users/${id}`);
    },

    activateUser: (id: string): Promise<{ success: boolean; data: User }> => {
        return apiClient.post(`/api/users/${id}/activate`);
    },

    deactivateUser: (id: string): Promise<{ success: boolean; data: User }> => {
        return apiClient.post(`/api/users/${id}/deactivate`);
    },

    verifyEmail: (id: string): Promise<{ success: boolean; data: User }> => {
        return apiClient.post(`/api/users/${id}/verify-email`);
    },

    getAutoblockedUsers: (params?: { page?: number; limit?: number }): Promise<any> => {
        return apiClient.get('/api/users/autoblocked', { params });
    },

    unblockUser: (id: string): Promise<{ success: boolean; message: string; user?: any }> => {
        return apiClient.post(`/api/users/${id}/unblock`);
    },

    // ── Deleted Accounts Admin API ──────────────────────────────────────────

    getDeletedAccounts: (params?: GetDeletedAccountsParams): Promise<any> => {
        return apiClient.get('/api/users/deleted-accounts', { params });
    },

    getDeletedAccountById: (id: string): Promise<any> => {
        return apiClient.get(`/api/users/deleted-accounts/${id}`);
    },

    updateDeletedAccountNotes: (id: string, adminNotes: string): Promise<any> => {
        return apiClient.patch(`/api/users/deleted-accounts/${id}/notes`, { adminNotes });
    },

    restoreDeletedAccount: (id: string, adminNotes?: string): Promise<any> => {
        return apiClient.post(`/api/users/deleted-accounts/${id}/restore`, { adminNotes });
    },
};

export default usersApi;
