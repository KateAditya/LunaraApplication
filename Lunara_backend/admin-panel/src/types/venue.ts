// Comprehensive Venue Data Types for Nightlife/Entertainment Industry

export interface VenueLocation {
    addressLine1: string;
    addressLine2?: string;
    area: string;
    city: string;
    state: string;
    pincode: string;
    country: string;
    latitude: number;
    longitude: number;
    nearestLandmark: string;
    directions?: string;
}

export interface VenueContact {
    phone?: string;
    mobile: string;
    whatsapp?: string;
    email: string;
    website?: string;
    instagram?: string;
    facebook?: string;
}

export interface ContactPerson {
    name: string;
    designation: string;
    mobile: string;
    email: string;
}

export interface BusinessDetails {
    panNumber: string;
    gstNumber: string;
    fssaiLicense?: string;
    liquorLicense?: string;
    fireSafetyCert?: string;
    tradeLicense?: string;
    bankAccountNumber?: string;
    bankIFSC?: string;
    bankName?: string;
}

export interface OperationalDetails {
    openingTime?: string;
    closingTime?: string;
    daysOpen?: string[];
    closedDates?: string[];
    seatingCapacity?: number;
    standingCapacity?: number;
    coverChargeMale?: number;
    coverChargeFemale?: number;
    discountPercentage?: number;
    tableBookingCharges?: number;
    coupleEntryFee?: number;
    ageLimit: number;
    dressCode?: string;
    cuisineTypes: string[];
    musicTypes: string[];
}

export interface VenueAmenities {
    hasWifi: boolean;
    hasAC: boolean;
    hasParking: boolean;
    hasValetParking: boolean;
    hasSmokingZone: boolean;
    hasDanceFloor: boolean;
    hasOutdoorSeating: boolean;
    hasRooftop: boolean;
    hasPool: boolean;
    hasVIPSection: boolean;
    hasBottleService: boolean;
    hasLiveMusic: boolean;
    hasDJ: boolean;
    hasHappyHours: boolean;
    hasPrivateDining: boolean;
}

export interface VenueMedia {
    logo?: string;
    coverImage: string;
    photos: string[];
    menus?: string[];
    foodMenus?: string[];
    barMenus?: string[];
    beverageMenus?: string[];
    partyPackages?: string[];
    videos?: string[];
}

export interface VenueStats {
    averageRating: number;
    totalReviews: number;
    totalBookings: number;
    monthlyBookings: number;
    totalRevenue: number;
}

export type VenueCategory = 'club' | 'pub' | 'lounge' | 'cafe' | 'hotel' | 'restaurant' | 'rooftop' | 'bar';
export type VenueStatus = 'pending' | 'approved' | 'live' | 'suspended' | 'deactivated';

export interface Venue {
    id: string;
    name: string;
    tagline?: string;
    description: string;
    category: VenueCategory;
    tags: string[];
    location: VenueLocation;
    contact: VenueContact;
    contactPerson: ContactPerson;
    altContactPerson?: ContactPerson;
    business: BusinessDetails;
    operations: OperationalDetails;
    amenities: VenueAmenities;
    media: VenueMedia;
    stats: VenueStats;
    displayOrder: number;
    status: VenueStatus;
    isActive: boolean;
    isVerified: boolean;
    isFeatured: boolean;
    isPremium: boolean;
    createdAt: string;
    updatedAt: string;
    ownerId: string;
    ownerName: string;
}

export const AMENITY_CONFIG: Record<keyof VenueAmenities, { label: string; icon: string }> = {
    hasWifi: { label: 'WiFi', icon: '📶' },
    hasAC: { label: 'Air Conditioned', icon: '❄️' },
    hasParking: { label: 'Parking', icon: '🅿️' },
    hasValetParking: { label: 'Valet Parking', icon: '🚗' },
    hasSmokingZone: { label: 'Smoking Zone', icon: '🚬' },
    hasDanceFloor: { label: 'Dance Floor', icon: '💃' },
    hasOutdoorSeating: { label: 'Outdoor Seating', icon: '🌳' },
    hasRooftop: { label: 'Rooftop', icon: '🏙️' },
    hasPool: { label: 'Pool', icon: '🏊' },
    hasVIPSection: { label: 'VIP Section', icon: '👑' },
    hasBottleService: { label: 'Bottle Service', icon: '🍾' },
    hasLiveMusic: { label: 'Live Music', icon: '🎵' },
    hasDJ: { label: 'DJ', icon: '🎧' },
    hasHappyHours: { label: 'Happy Hours', icon: '🍺' },
    hasPrivateDining: { label: 'Private Dining', icon: '🍽️' },
};

export const CATEGORY_CONFIG: Record<VenueCategory, { label: string; color: string; bg: string }> = {
    club: { label: 'Club', color: '#f72585', bg: 'rgba(247, 37, 133, 0.15)' },
    pub: { label: 'Pub', color: '#fee440', bg: 'rgba(254, 228, 64, 0.15)' },
    lounge: { label: 'Lounge', color: '#9d4edd', bg: 'rgba(123, 44, 191, 0.15)' },
    cafe: { label: 'Cafe', color: '#ff9f1c', bg: 'rgba(255, 159, 28, 0.15)' },
    hotel: { label: 'Hotel', color: '#00f5d4', bg: 'rgba(0, 245, 212, 0.15)' },
    restaurant: { label: 'Restaurant', color: '#4cc9f0', bg: 'rgba(76, 201, 240, 0.15)' },
    rooftop: { label: 'Rooftop', color: '#7209b7', bg: 'rgba(114, 9, 183, 0.15)' },
    bar: { label: 'Bar', color: '#f77f00', bg: 'rgba(247, 127, 0, 0.15)' },
};
