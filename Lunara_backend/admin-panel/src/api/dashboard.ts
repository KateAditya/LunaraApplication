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
        return await api.get('/api/dashboard/featured');
    },

    getPartyTonight: async (): Promise<DashboardResponse<PartyTonight>> => {
        return await api.get('/api/dashboard/tonight');
    },

    getPartyPartners: async (): Promise<DashboardResponse<PartyPartner>> => {
        return await api.get('/api/dashboard/partners');
    },

    getNearbyVenues: async (): Promise<DashboardResponse<NearbyVenue>> => {
        return await api.get('/api/dashboard/nearby');
    }
};
