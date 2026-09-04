import apiClient from './client';

export const getPartyEvents = async () => {
  const { data } = await apiClient.get('/admin/event-bookings/events');
  return data;
};

export const getEventSummary = async (eventId: string = 'all') => {
  const targetId = eventId || 'all';
  const { data } = await apiClient.get(`/admin/event-bookings/${targetId}/summary`);
  return data;
};

export const getEventBookings = async (
  eventId: string = 'all',
  params: {
    page?: number;
    limit?: number;
    search?: string;
    bookingStatus?: string;
    paymentStatus?: string;
    fromDate?: string;
    toDate?: string;
  }
) => {
  const targetId = eventId || 'all';
  const { data } = await apiClient.get(`/admin/event-bookings/${targetId}/bookings`, { params });
  return data;
};

