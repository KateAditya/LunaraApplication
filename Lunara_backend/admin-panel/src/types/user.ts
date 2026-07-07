export interface UserProfile {
    id: string;
    userId: string;
    displayName?: string;
    bio?: string;
    gender?: string;
    city?: string;
    occupation?: string;
    company?: string;
    education?: string;
    relationshipStatus?: string;
    lookingFor?: string[];
    instagramHandle?: string;
    spotifyProfile?: string;
}

export interface UserIdentity {
    panNumber: string;
    aadhaarNumber?: string;
    dob: string;
    gender: string;
    nationality: string;
}

export interface UserSocial {
    bio?: string;
    interests?: string[];
    vibes?: string[];
    languages?: string[];
    profilePhotos?: string[];
}

export interface UserPreference {
    id: string;
    userId: string;
    preferredVenues?: string[];
    preferredCrowdSize?: string;
    musicPreference?: string[];
    drinkPreference?: string[];
    smokingPreference?: string;
    preferredGenders?: string[];
    minAgePreference?: number;
    maxAgePreference?: number;
    budgetRange?: string;
    partyTimePreference?: string;
    groupSizePreference?: string;
    matchDistanceKm: number;
    showMeInMatching: boolean;
}

export interface UserSecurity {
    mfaEnabled: boolean;
    lastPasswordChange: string;
    forcePasswordChange: boolean;
    loginHistory: {
        timestamp: string;
        ip: string;
        device: string;
        location: string;
    }[];
}

export interface UserHistory {
    bookings: {
        id: string;
        venueName: string;
        date: string;
        status: string;
        amount: number;
    }[];
    payments: {
        id: string;
        amount: number;
        status: string;
        date: string;
        method: string;
    }[];
    reviews: {
        id: string;
        venueName: string;
        rating: number;
        comment: string;
        date: string;
    }[];
}

export interface User {
    id: string;
    firstName: string;
    lastName: string;
    email: string;
    phone: string;
    role: 'customer' | 'venue_owner' | 'admin' | 'promoter';
    avatarUrl?: string;
    isActive: boolean;
    isVerified: boolean;
    isPhoneVerified: boolean;
    isEmailVerified: boolean;
    createdAt: string;
    updatedAt: string;
    lastLoginAt: string | null;
    identity: UserIdentity;
    social: UserSocial;
    profile?: UserProfile;
    preferences?: UserPreference;
    security: UserSecurity;
    history: UserHistory;
    blockCount?: number;
    isAutoblocked?: boolean;
    autoblockedReason?: string | null;
}

export const INTERESTS_OPTIONS = [
    'Techno', 'House', 'Hip Hop', 'EDM', 'Cocktails', 'Beer', 'Wine',
    'Fine Dining', 'Fast Food', 'Rooftops', 'Lounges', 'Clubs',
    'Live Music', 'Karaoke', 'Gaming', 'Shisha'
];

export const VIBES_OPTIONS = [
    'Chill', 'Energetic', 'Social', 'Romantic', 'Professional',
    'Underground', 'Luxury', 'Casual'
];
