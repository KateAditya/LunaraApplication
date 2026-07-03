import api from './client';

export interface FeaturedVenue {
    id: string;
    name: string;
    type: string;
    image: string;
    promoted: boolean;
}

export interface PartyTonight {
    id: string;
    title: string;
    location: string;
    time: string;
    attendees: number;
    image: string;
}

export interface PartyPartner {
    id: string;
    name: string;
    vibe: string;
    image: string;
}

export interface NearbyVenue {
    id: string;
    name: string;
    distance: string;
    image: string;
}

interface DashboardResponse<T> {
    success: boolean;
    count: number;
    data: T[];
}

export const dashboardApi = {
    getFeaturedVenues: async (): Promise<DashboardResponse<FeaturedVenue>> => {
        const response = await api.get('/dashboard/featured');
        return response.data;
    },

    getPartyTonight: async (): Promise<DashboardResponse<PartyTonight>> => {
        const response = await api.get('/dashboard/tonight');
        return response.data;
    },

    getPartyPartners: async (): Promise<DashboardResponse<PartyPartner>> => {
        const response = await api.get('/dashboard/partners');
        return response.data;
    },

    getNearbyVenues: async (): Promise<DashboardResponse<NearbyVenue>> => {
        const response = await api.get('/dashboard/nearby');
        return response.data;
    }
};
