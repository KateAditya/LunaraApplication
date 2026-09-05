import apiClient from './client';

export const getPartyEvents = async (): Promise<any> => {
  return apiClient.get('/api/admin/event-bookings/events');
};

export const getEventSummary = async (eventId: string = 'all'): Promise<any> => {
  const targetId = eventId || 'all';
  return apiClient.get(`/api/admin/event-bookings/${targetId}/summary`);
};

export const getEventBookings = async (
  eventId: string = 'all',
  params?: {
    page?: number;
    limit?: number;
    search?: string;
    bookingStatus?: string;
    paymentStatus?: string;
    fromDate?: string;
    toDate?: string;
  }
): Promise<any> => {
  const targetId = eventId || 'all';
  return apiClient.get(`/api/admin/event-bookings/${targetId}/bookings`, { params });
};


