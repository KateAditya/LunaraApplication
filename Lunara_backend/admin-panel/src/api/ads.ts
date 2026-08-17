import apiClient from './client';

export interface SocialLink {
    platform: string;
    url: string;
}

export interface Ad {
    id: string;
    type: 'Ads' | 'Party';
    venueId: string | null;
    city: string | null;
    area: string | null;
    title?: string;
    imagePath: string;
    fromDate: string;
    toDate: string;
    bannerFromDate?: string;
    bannerToDate?: string;
    eventDate?: string;
    entryPrice?: number;
    seatLimit?: number;
    isUnlimited?: boolean;
    filledSeats?: number;
    remainingSeats?: number | null;
    isActive: boolean;
    socialLinks: SocialLink[];
    aboutEvent?: string;
    createdAt: string;
    updatedAt: string;
    venue?: {
        id: string;
        name: string;
    };
}

export const adsApi = {
    getAds: (): Promise<{ success: boolean; data: Ad[] }> =>
        apiClient.get('/api/ads'),

    createAd: (formData: FormData): Promise<{ success: boolean; data: Ad }> =>
        apiClient.post('/api/ads', formData),

    updateAd: (id: string, formData: FormData): Promise<{ success: boolean; data: Ad }> =>
        apiClient.put(`/api/ads/${id}`, formData),

    deleteAd: (id: string): Promise<{ success: boolean; message: string }> =>
        apiClient.delete(`/api/ads/${id}`),
};

export default adsApi;
