import apiClient from './client';

export const getPartyEvents = async () => {
  const { data } = await apiClient.get('/admin/event-bookings/events');
  return data;
};

export const getEventSummary = async (eventId: string) => {
  const { data } = await apiClient.get(`/admin/event-bookings/${eventId}/summary`);
  return data;
};

export const getEventBookings = async (
  eventId: string,
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
  const { data } = await apiClient.get(`/admin/event-bookings/${eventId}/bookings`, { params });
  return data;
};
