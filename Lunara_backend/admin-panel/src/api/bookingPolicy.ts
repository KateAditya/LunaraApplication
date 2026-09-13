import apiClient from './client';

export type BookingPolicyType = 'SOLO_BOOKING' | 'GROUP_PARTY' | 'STRANGERS_MEET' | 'LARGE_PARTY' | 'EVENT_BOOKING';

export interface BookingPolicyConfig {
  id: string;
  bookingType: BookingPolicyType;
  minBookingLeadTimeHours: number;
  cancellationCutoffHours: number;
  refundEnabled: boolean;
  refundPercentage: number;
  isActive: boolean;
  createdAt?: string;
  updatedAt?: string;
}

export interface UpdateBookingPolicyPayload {
  bookingType: BookingPolicyType;
  minBookingLeadTimeHours: number;
  cancellationCutoffHours: number;
  refundEnabled: boolean;
  refundPercentage: number;
  isActive: boolean;
}

export interface BookingPolicyResponse {
  success: boolean;
  data: {
    SOLO_BOOKING: BookingPolicyConfig;
    GROUP_PARTY: BookingPolicyConfig;
    STRANGERS_MEET?: BookingPolicyConfig;
    LARGE_PARTY?: BookingPolicyConfig;
    EVENT_BOOKING?: BookingPolicyConfig;
  };
  message?: string;
}

export const bookingPolicyApi = {
  getPolicies: async (): Promise<BookingPolicyResponse> => {
    return (await apiClient.get('/api/admin/settings/booking-policy')) as unknown as BookingPolicyResponse;
  },

  updatePolicy: async (
    payload: UpdateBookingPolicyPayload
  ): Promise<{ success: boolean; data: BookingPolicyConfig; message?: string }> => {
    return (await apiClient.put('/api/admin/settings/booking-policy', payload)) as unknown as {
      success: boolean;
      data: BookingPolicyConfig;
      message?: string;
    };
  },
};

export default bookingPolicyApi;
