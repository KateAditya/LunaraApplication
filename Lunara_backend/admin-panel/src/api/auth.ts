import apiClient from './client';
import type { User } from '../types/user';

export interface LoginCredentials {
    email: string;
    password: string;
}

export interface AuthResponse {
    success: boolean;
    message: string;
    data: {
        user: {
            id: string;
            email: string;
            firstName: string;
            lastName: string;
            role: string;
        };
        accessToken: string;
        refreshToken: string;
    };
}

export const authApi = {
    login: (credentials: LoginCredentials): Promise<AuthResponse> => {
        return apiClient.post('/api/auth/login', credentials);
    },

    getCurrentUser: (): Promise<{ success: boolean; data: User }> => {
        return apiClient.get('/api/auth/me');
    },

    logout: (): Promise<void> => {
        // Clear local storage
        localStorage.removeItem('accessToken');
        localStorage.removeItem('refreshToken');
        return Promise.resolve();
    },
};

export default authApi;
