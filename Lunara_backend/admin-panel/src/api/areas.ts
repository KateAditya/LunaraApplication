import apiClient from './client';

export interface AreaResponse {
    success: boolean;
    data: string[];
    details?: Array<{
        id: string;
        name: string;
        city: string | null;
    }>;
}

export interface CreateAreaResponse {
    success: boolean;
    data: {
        id: string;
        name: string;
        city: string | null;
    };
    created: boolean;
    message?: string;
}

export const areasApi = {
    getAreas: (): Promise<AreaResponse> =>
        apiClient.get('/api/areas'),

    createArea: (name: string, city?: string): Promise<CreateAreaResponse> =>
        apiClient.post('/api/areas', { name, city }),
};

export default areasApi;
