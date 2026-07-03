import apiClient from './client';

// ── Types matching the flat DB shape returned by the server ────────────────
export interface Venue {
    id: string;
    name: string;
    slug: string;
    category: string;
    addressLine1: string;
    addressLine2?: string;
    area?: string;
    city: string;
    state: string;
    postalCode: string;
    latitude?: number;
    longitude?: number;
    phone: string;
    email?: string;
    capacity: number;
    openingTime?: string;
    closingTime?: string;
    averageRating: number;
    totalReviews: number;
    status: string;
    featured: boolean;
    ownerId: string;
    createdAt: string;
    updatedAt: string;
    images?: any[];
}

export interface CreateVenueData {
    name: string;
    category: string;
    description?: string;
    addressLine1: string;
    city: string;
    state: string;
    pincode: string;
    latitude?: number;
    longitude?: number;
    mobile: string;
    email?: string;
    capacity?: number;
    openingTime?: string;
    closingTime?: string;
    amenities?: Record<string, boolean>;
    ownerId?: string;
}

// ── API calls (all pointing at the real /api/venues routes) ────────────────
export const venuesApi = {
    getVenues: (): Promise<{ success: boolean; venues: Venue[] }> =>
        apiClient.get('/api/venues'),

    getVenue: (id: string): Promise<{ success: boolean; venue: Venue; images: any[] }> =>
        apiClient.get(`/api/venues/${id}`),

    createVenue: (formData: FormData): Promise<{ success: boolean; venue: Venue }> =>
        apiClient.post('/api/venues', formData, {
            headers: { 'Content-Type': 'multipart/form-data' },
        }),

    updateVenue: (id: string, formData: FormData): Promise<{ success: boolean; venue: Venue }> =>
        apiClient.put(`/api/venues/${id}`, formData, {
            headers: { 'Content-Type': 'multipart/form-data' },
        }),

    deleteVenue: (id: string): Promise<{ success: boolean; message: string }> =>
        apiClient.delete(`/api/venues/${id}`),

    // TODO: Backend routes for these actions don't exist yet — add when ready:
    // approveVenue, rejectVenue, activateVenue, deactivateVenue
};

export default venuesApi;