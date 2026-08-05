import apiClient from './client';

export interface NotificationCounts {
    bookings: number;
    partyRequests: number;
    groupParties: number;
    strangersMeet: number;
    totalPending: number;
}

export interface ActivityItem {
    id: string;
    type: 'booking' | 'party_request' | 'group_party' | 'strangers_meet';
    title: string;
    subtitle: string;
    path: string;
    status: string;
    isPending: boolean;
    createdAt: string;
}

export const adminNotificationsApi = {
    getSummary: (): Promise<{ success: boolean; data: NotificationCounts }> =>
        apiClient.get('/api/admin/notifications/summary'),

    getActivity: (): Promise<{ success: boolean; data: ActivityItem[] }> =>
        apiClient.get('/api/admin/notifications/activity'),
};

export default adminNotificationsApi;
