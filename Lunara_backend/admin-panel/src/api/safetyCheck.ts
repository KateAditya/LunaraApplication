import apiClient from './client';

export interface SafetyCheck {
    id: string;
    userId: string;
    partnerId: string;
    feltSafe: boolean;
    prebuiltAnswers: string[];
    opinion: string;
    adminFeedback?: string | null;
    createdAt: string;
    updatedAt: string;
    user?: {
        id: string;
        firstName: string;
        lastName: string;
        profileImageUrl?: string;
    };
    partner?: {
        id: string;
        firstName: string;
        lastName: string;
        profileImageUrl?: string;
    };
}

export const safetyCheckApi = {
    getSafetyChecks: (): Promise<{ success: boolean; data: SafetyCheck[] }> => {
        return apiClient.get('/api/admin/safety-checks');
    },

    submitFeedback: (id: string, feedback: string): Promise<{ success: boolean; data: SafetyCheck }> => {
        return apiClient.post(`/api/admin/safety-checks/${id}/feedback`, { feedback });
    },
};

export default safetyCheckApi;
