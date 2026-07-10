import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

// Venue category and status enums
export enum VenueCategory {
    PUB = 'pub',
    CLUB = 'club',
    HOTEL = 'hotel',
    LOUNGE = 'lounge',
    BAR = 'bar',
    CAFE = 'cafe',
    RESTAURANT = 'restaurant',
    ROOFTOP = 'rooftop',
}

export enum VenueStatus {
    // Legacy / admin-controlled
    PENDING = 'pending',
    APPROVED = 'approved',
    REJECTED = 'rejected',
    SUSPENDED = 'suspended',
    DEACTIVATED = 'deactivated',
    // Onboarding pipeline
    DRAFT = 'draft',
    SUBMITTED = 'submitted',
    PENDING_CONFIRMATION = 'pending_confirmation',
    LIVE = 'live',
}

// Venue attributes
export interface VenueAttributes {
    id: string;
    ownerId: string;
    name: string;
    slug: string;
    tagline?: string;
    description?: string;
    category: VenueCategory;
    tags?: string[];
    addressLine1: string;
    addressLine2?: string;
    area?: string;
    city: string;
    state: string;
    postalCode: string;
    country?: string;
    latitude?: number;
    longitude?: number;
    displayOrder: number;
    nearestLandmark?: string;
    directions?: string;
    phone: string;
    mobile?: string;
    whatsapp?: string;
    email?: string;
    website?: string;
    instagram?: string;
    facebook?: string;
    cpName?: string;
    cpDesignation?: string;
    cpMobile?: string;
    cpEmail?: string;
    altCpName?: string;
    altCpDesignation?: string;
    altCpMobile?: string;
    altCpEmail?: string;
    capacity: number;
    seatingCapacity?: number;
    standingCapacity?: number;
    openingTime?: string;
    closingTime?: string;
    daysOpen?: string[];
    closedDates?: string[]; // Array of YYYY-MM-DD strings for holidays/closed dates
    ageLimit?: number;
    coverChargeMale?: number;
    coverChargeFemale?: number;
    discountPercentage?: number;
    tableBookingCharges?: number;
    coupleEntryFee?: number;
    groupPartyChargePerPerson?: number;
    groupPartyDiscountPercentage?: number;
    dressCode?: string;
    cuisineTypes?: string[];
    musicTypes?: string[];
    amenities?: any;
    panNumber?: string;
    gstNumber?: string;
    fssaiLicense?: string;
    liquorLicense?: string;
    fireSafetyCert?: string;
    tradeLicense?: string;
    bankAccountNumber?: string;
    bankIFSC?: string;
    bankName?: string;
    averageRating: number;
    totalReviews: number;
    status: VenueStatus;
    featured: boolean;
    isActive: boolean;
    isVerified: boolean;
    isPremium: boolean;
    // Compliance / onboarding fields
    termsAcceptedAt?: Date;
    confirmationToken?: string;
    confirmationTokenExpiresAt?: Date;
    ownerEmailSentAt?: Date;
    ownerConfirmedAt?: Date;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface VenueCreationAttributes
    extends Optional<
        VenueAttributes,
        | 'id'
        | 'tagline'
        | 'description'
        | 'tags'
        | 'addressLine2'
        | 'area'
        | 'country'
        | 'latitude'
        | 'longitude'
        | 'displayOrder'
        | 'nearestLandmark'
        | 'directions'
        | 'mobile'
        | 'whatsapp'
        | 'email'
        | 'website'
        | 'instagram'
        | 'facebook'
        | 'cpName'
        | 'cpDesignation'
        | 'cpMobile'
        | 'cpEmail'
        | 'altCpName'
        | 'altCpDesignation'
        | 'altCpMobile'
        | 'altCpEmail'
        | 'seatingCapacity'
        | 'standingCapacity'
        | 'openingTime'
        | 'closingTime'
        | 'daysOpen'
        | 'closedDates'
        | 'ageLimit'
        | 'coverChargeMale'
        | 'coverChargeFemale'
        | 'discountPercentage'
        | 'tableBookingCharges'
        | 'coupleEntryFee'
        | 'groupPartyChargePerPerson'
        | 'groupPartyDiscountPercentage'
        | 'dressCode'
        | 'cuisineTypes'
        | 'musicTypes'
        | 'amenities'
        | 'panNumber'
        | 'gstNumber'
        | 'fssaiLicense'
        | 'liquorLicense'
        | 'fireSafetyCert'
        | 'tradeLicense'
        | 'bankAccountNumber'
        | 'bankIFSC'
        | 'bankName'
        | 'averageRating'
        | 'totalReviews'
        | 'status'
        | 'featured'
        | 'isActive'
        | 'isVerified'
        | 'isPremium'
        | 'termsAcceptedAt'
        | 'confirmationToken'
        | 'confirmationTokenExpiresAt'
        | 'ownerEmailSentAt'
        | 'ownerConfirmedAt'
        | 'createdAt'
        | 'updatedAt'
    > { }

class Venue extends Model<VenueAttributes, VenueCreationAttributes> implements VenueAttributes {
    public id!: string;
    public ownerId!: string;
    public name!: string;
    public slug!: string;
    public tagline?: string;
    public description?: string;
    public category!: VenueCategory;
    public tags?: string[];
    public addressLine1!: string;
    public addressLine2?: string;
    public area?: string;
    public city!: string;
    public state!: string;
    public postalCode!: string;
    public country?: string;
    public latitude?: number;
    public longitude?: number;
    public displayOrder!: number;
    public nearestLandmark?: string;
    public directions?: string;
    public phone!: string;
    public mobile?: string;
    public whatsapp?: string;
    public email?: string;
    public website?: string;
    public instagram?: string;
    public facebook?: string;
    public cpName?: string;
    public cpDesignation?: string;
    public cpMobile?: string;
    public cpEmail?: string;
    public altCpName?: string;
    public altCpDesignation?: string;
    public altCpMobile?: string;
    public altCpEmail?: string;
    public capacity!: number;
    public seatingCapacity?: number;
    public standingCapacity?: number;
    public openingTime?: string;
    public closingTime?: string;
    public daysOpen?: string[];
    public closedDates?: string[];
    public ageLimit?: number;
    public coverChargeMale?: number;
    public coverChargeFemale?: number;
    public discountPercentage?: number;
    public tableBookingCharges?: number;
    public coupleEntryFee?: number;
    public groupPartyChargePerPerson?: number;
    public groupPartyDiscountPercentage?: number;
    public dressCode?: string;
    public cuisineTypes?: string[];
    public musicTypes?: string[];
    public amenities?: any;
    public panNumber?: string;
    public gstNumber?: string;
    public fssaiLicense?: string;
    public liquorLicense?: string;
    public fireSafetyCert?: string;
    public tradeLicense?: string;
    public bankAccountNumber?: string;
    public bankIFSC?: string;
    public bankName?: string;
    public averageRating!: number;
    public totalReviews!: number;
    public status!: VenueStatus;
    public featured!: boolean;
    public isActive!: boolean;
    public isVerified!: boolean;
    public isPremium!: boolean;
    // Compliance tracking
    public termsAcceptedAt?: Date;
    public confirmationToken?: string;
    public confirmationTokenExpiresAt?: Date;
    public ownerEmailSentAt?: Date;
    public ownerConfirmedAt?: Date;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    // Instance methods
    public getFullAddress(): string {
        const parts = [
            this.addressLine1,
            this.addressLine2,
            this.area,
            this.city,
            this.state,
            this.postalCode,
            this.country,
        ].filter(Boolean);
        return parts.join(', ');
    }

    public isOpen(): boolean {
        return this.status === VenueStatus.APPROVED && this.isActive !== false;
    }

    public hasLocation(): boolean {
        return (this.latitude !== undefined && this.latitude !== null) && 
               (this.longitude !== undefined && this.longitude !== null);
    }
}

Venue.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        ownerId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'owner_id',
            references: {
                model: 'users',
                key: 'id',
            },
        },
        name: {
            type: DataTypes.STRING(255),
            allowNull: false,
        },
        slug: {
            type: DataTypes.STRING(255),
            allowNull: false,
            unique: true,
        },
        tagline: {
            type: DataTypes.STRING(255),
            allowNull: true,
        },
        description: {
            type: DataTypes.TEXT,
            allowNull: true,
        },
        category: {
            type: DataTypes.ENUM(...Object.values(VenueCategory)),
            allowNull: false,
        },
        tags: {
            type: DataTypes.JSONB,
            allowNull: true,
            defaultValue: [],
        },
        addressLine1: {
            type: DataTypes.STRING(255),
            allowNull: false,
            field: 'address_line1',
        },
        addressLine2: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'address_line2',
        },
        area: {
            type: DataTypes.STRING(100),
            allowNull: true,
        },
        city: {
            type: DataTypes.STRING(100),
            allowNull: false,
        },
        state: {
            type: DataTypes.STRING(100),
            allowNull: false,
        },
        postalCode: {
            type: DataTypes.STRING(10),
            allowNull: false,
            field: 'postal_code',
        },
        country: {
            type: DataTypes.STRING(100),
            allowNull: true,
            defaultValue: 'India',
        },
        latitude: {
            type: DataTypes.DECIMAL(10, 8),
            allowNull: true,
        },
        longitude: {
            type: DataTypes.DECIMAL(11, 8),
            allowNull: true,
        },
        displayOrder: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
            field: 'display_order',
        },
        nearestLandmark: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'nearest_landmark',
        },
        directions: {
            type: DataTypes.TEXT,
            allowNull: true,
        },
        phone: {
            type: DataTypes.STRING(20),
            allowNull: false,
        },
        mobile: {
            type: DataTypes.STRING(20),
            allowNull: true,
        },
        whatsapp: {
            type: DataTypes.STRING(20),
            allowNull: true,
        },
        email: {
            type: DataTypes.STRING(255),
            allowNull: true,
        },
        website: {
            type: DataTypes.STRING(255),
            allowNull: true,
        },
        instagram: {
            type: DataTypes.STRING(255),
            allowNull: true,
        },
        facebook: {
            type: DataTypes.STRING(255),
            allowNull: true,
        },
        cpName: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'cp_name',
        },
        cpDesignation: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'cp_designation',
        },
        cpMobile: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'cp_mobile',
        },
        cpEmail: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'cp_email',
        },
        altCpName: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'alt_cp_name',
        },
        altCpDesignation: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'alt_cp_designation',
        },
        altCpMobile: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'alt_cp_mobile',
        },
        altCpEmail: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'alt_cp_email',
        },
        capacity: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 100,
        },
        seatingCapacity: {
            type: DataTypes.INTEGER,
            allowNull: true,
            field: 'seating_capacity',
        },
        standingCapacity: {
            type: DataTypes.INTEGER,
            allowNull: true,
            field: 'standing_capacity',
        },
        openingTime: {
            type: DataTypes.TIME,
            allowNull: true,
            field: 'opening_time',
        },
        closingTime: {
            type: DataTypes.TIME,
            allowNull: true,
            field: 'closing_time',
        },
        daysOpen: {
            type: DataTypes.JSONB,
            allowNull: true,
            field: 'days_open',
            defaultValue: [],
        },
        closedDates: {
            type: DataTypes.JSONB,
            allowNull: true,
            field: 'closed_dates',
            defaultValue: [],
        },
        ageLimit: {
            type: DataTypes.INTEGER,
            allowNull: true,
            field: 'age_limit',
            defaultValue: 21,
        },
        coverChargeMale: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            field: 'cover_charge_male',
        },
        coverChargeFemale: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            field: 'cover_charge_female',
        },
        discountPercentage: {
            type: DataTypes.DECIMAL(5, 2),
            allowNull: true,
            defaultValue: 0,
            field: 'discount_percentage',
        },
        tableBookingCharges: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            defaultValue: 0,
            field: 'table_booking_charges',
        },
        groupPartyChargePerPerson: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            defaultValue: 0,
            field: 'group_party_charge_per_person',
        },
        groupPartyDiscountPercentage: {
            type: DataTypes.DECIMAL(5, 2),
            allowNull: true,
            defaultValue: 0,
            field: 'group_party_discount_percentage',
        },
        coupleEntryFee: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            defaultValue: 0,
            field: 'couple_entry_fee',
        },
        dressCode: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'dress_code',
        },
        cuisineTypes: {
            type: DataTypes.JSONB,
            allowNull: true,
            field: 'cuisine_types',
            defaultValue: [],
        },
        musicTypes: {
            type: DataTypes.JSONB,
            allowNull: true,
            field: 'music_types',
            defaultValue: [],
        },
        amenities: {
            type: DataTypes.JSONB,
            allowNull: true,
            defaultValue: {},
        },
        panNumber: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'pan_number',
        },
        gstNumber: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'gst_number',
        },
        fssaiLicense: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'fssai_license',
        },
        liquorLicense: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'liquor_license',
        },
        fireSafetyCert: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'fire_safety_cert',
        },
        tradeLicense: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'trade_license',
        },
        bankAccountNumber: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'bank_account_number',
        },
        bankIFSC: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'bank_ifsc',
        },
        bankName: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'bank_name',
        },
        averageRating: {
            type: DataTypes.DECIMAL(3, 2),
            defaultValue: 0,
            field: 'average_rating',
        },
        totalReviews: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'total_reviews',
        },
        status: {
            // Store as VARCHAR so new pipeline statuses can be added without
            // a PostgreSQL ALTER TYPE migration on an existing ENUM column.
            type: DataTypes.STRING(50),
            defaultValue: VenueStatus.PENDING,
        },
        termsAcceptedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'terms_accepted_at',
        },
        confirmationToken: {
            type: DataTypes.STRING(128),
            allowNull: true,
            unique: true,
            field: 'confirmation_token',
        },
        confirmationTokenExpiresAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'confirmation_token_expires_at',
        },
        ownerEmailSentAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'owner_email_sent_at',
        },
        ownerConfirmedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'owner_confirmed_at',
        },
        featured: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
        },
        isActive: {
            type: DataTypes.BOOLEAN,
            defaultValue: true,
            field: 'is_active',
        },
        isVerified: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_verified',
        },
        isPremium: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_premium',
        },
    },
    {
        sequelize,
        tableName: 'venues',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['owner_id'] },
            { fields: ['city'] },
            { fields: ['category'] },
            { fields: ['status'] },
            { fields: ['slug'], unique: true },
        ],
    }
);

// Hooks
Venue.beforeCreate((venue) => {
    if (!venue.slug && venue.name) {
        venue.slug = venue.name
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/^-+|-+$/g, '');
    }
});

export default Venue;
