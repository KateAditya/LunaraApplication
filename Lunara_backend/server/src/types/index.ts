export interface User {
    id: string;
    email: string;
    phone: string;
    firstName: string;
    lastName: string;
    role: 'customer' | 'venue_owner' | 'admin';
    isVerified: boolean;
    createdAt: Date;
    updatedAt: Date;
}

export interface Venue {
    id: string;
    name: string;
    description: string;
    category: 'pub' | 'club' | 'hotel' | 'lounge';
    address: string;
    city: string;
    state: string;
    latitude: number;
    longitude: number;
    capacity: number;
    ownerId: string;
    status: 'pending' | 'approved' | 'rejected' | 'suspended';
    createdAt: Date;
    updatedAt: Date;
}

export interface Booking {
    id: string;
    userId: string;
    venueId: string;
    bookingDate: Date;
    startTime: string;
    endTime: string;
    numberOfGuests: number;
    totalAmount: number;
    status: 'pending' | 'confirmed' | 'cancelled' | 'completed';
    paymentStatus: 'pending' | 'paid' | 'refunded';
    isGroupBooking: boolean;
    createdAt: Date;
    updatedAt: Date;
}

export interface ApiResponse<T = any> {
    success: boolean;
    message: string;
    data?: T;
    error?: string;
}

export interface PaginatedResponse<T> extends ApiResponse<T[]> {
    pagination: {
        page: number;
        limit: number;
        total: number;
        totalPages: number;
    };
}
