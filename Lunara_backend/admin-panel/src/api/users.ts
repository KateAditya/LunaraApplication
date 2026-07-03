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

export const usersApi = {
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
        return apiClient.post(`/api/users/${id}/activate`); // Assuming custom endpoint or handled by update
    },

    deactivateUser: (id: string): Promise<{ success: boolean; data: User }> => {
        return apiClient.post(`/api/users/${id}/deactivate`);
    },

    verifyEmail: (id: string): Promise<{ success: boolean; data: User }> => {
        return apiClient.post(`/api/users/${id}/verify-email`);
    },
};

export default usersApi;
