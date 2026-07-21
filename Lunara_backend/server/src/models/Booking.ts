import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

// Booking status enums
export enum BookingStatus {
    PENDING   = 'pending',
    CONFIRMED = 'confirmed',
    CANCELLED = 'cancelled',
    COMPLETED = 'completed',
    NO_SHOW   = 'no_show',
}

export enum PaymentStatus {
    PENDING        = 'pending',
    PAID           = 'paid',
    PARTIALLY_PAID = 'partially_paid',
    REFUNDED       = 'refunded',
}

// New enums for mobile booking flow
export enum GoingMode {
    SOLO = 'solo',
    PLAN = 'plan',
    PARTY_REQUEST = 'party_request',
}

export enum AdminApprovalStatus {
    PENDING = 'pending',
    APPROVED = 'approved',
    REJECTED = 'rejected',
    PAYMENT_SENT = 'payment_sent',
    PAYMENT_DONE = 'payment_done',
}

export enum BookingPaymentMode {
    PAY_NOW    = 'pay_now',
    SPLIT_BILL = 'split_bill',
}

// Booking attributes
export interface BookingAttributes {
    id: string;
    bookingNumber: string;
    userId: string;
    venueId: string;
    bookingDate: Date;
    startTime: string;
    endTime?: string;
    numberOfGuests: number;
    totalAmount: number;
    depositAmount: number;
    commissionAmount: number;
    status: BookingStatus;
    paymentStatus: PaymentStatus;
    isGroupBooking: boolean;
    cancellationReason?: string;
    cancelledAt?: Date;
    specialRequests?: string;
    // Mobile booking flow fields
    goingMode?: GoingMode;
    tablePackage?: string;
    paymentMode?: BookingPaymentMode;
    ticketCode?: string;
    ticketUrl?: string;
    addedToWallet?: boolean;
    // Large party request fields
    partySubject?: string;
    partyRequirement?: string;
    partyDescription?: string;
    isLargePartyRequest?: boolean;
    isUpcomingNight?: boolean;
    adminApprovalStatus?: AdminApprovalStatus;
    // Contact details for large party
    mobileNumber?: string;
    optionalMobileNumber?: string;
    // Admin-sent payment link
    adminPaymentLink?: string;
    adminPaymentAmount?: number;
    razorpayOrderId?: string;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface BookingCreationAttributes
    extends Optional<
        BookingAttributes,
        | 'id'
        | 'bookingNumber'
        | 'endTime'
        | 'depositAmount'
        | 'status'
        | 'paymentStatus'
        | 'isGroupBooking'
        | 'cancellationReason'
        | 'cancelledAt'
        | 'specialRequests'
        | 'goingMode'
        | 'tablePackage'
        | 'paymentMode'
        | 'ticketCode'
        | 'ticketUrl'
        | 'addedToWallet'
        | 'partySubject'
        | 'partyRequirement'
        | 'partyDescription'
        | 'isLargePartyRequest'
        | 'isUpcomingNight'
        | 'adminApprovalStatus'
        | 'mobileNumber'
        | 'optionalMobileNumber'
        | 'adminPaymentLink'
        | 'adminPaymentAmount'
        | 'razorpayOrderId'
        | 'createdAt'
        | 'updatedAt'
    > { }

class Booking extends Model<BookingAttributes, BookingCreationAttributes> implements BookingAttributes {
    public id!: string;
    public bookingNumber!: string;
    public userId!: string;
    public venueId!: string;
    public bookingDate!: Date;
    public startTime!: string;
    public endTime?: string;
    public numberOfGuests!: number;
    public totalAmount!: number;
    public depositAmount!: number;
    public commissionAmount!: number;
    public status!: BookingStatus;
    public paymentStatus!: PaymentStatus;
    public isGroupBooking!: boolean;
    public cancellationReason?: string;
    public cancelledAt?: Date;
    public specialRequests?: string;
    // Mobile booking flow
    public goingMode?: GoingMode;
    public tablePackage?: string;
    public paymentMode?: BookingPaymentMode;
    public ticketCode?: string;
    public ticketUrl?: string;
    public addedToWallet?: boolean;
    // Large party request
    public partySubject?: string;
    public partyRequirement?: string;
    public partyDescription?: string;
    public isLargePartyRequest?: boolean;
    public isUpcomingNight?: boolean;
    public adminApprovalStatus?: AdminApprovalStatus;
    public mobileNumber?: string;
    public optionalMobileNumber?: string;
    public adminPaymentLink?: string;
    public adminPaymentAmount?: number;
    public razorpayOrderId?: string;
    
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    // Instance methods
    public canBeCancelled(): boolean {
        const now = new Date();
        const bookingDateTime = new Date(`${this.bookingDate} ${this.startTime}`);
        const hoursDifference = (bookingDateTime.getTime() - now.getTime()) / (1000 * 60 * 60);

        return (
            this.status === BookingStatus.CONFIRMED &&
            hoursDifference > 24 // Can cancel if more than 24 hours before booking
        );
    }

    public isPaid(): boolean {
        return this.paymentStatus === PaymentStatus.PAID;
    }

    public getVenueAmount(): number {
        return this.totalAmount - this.commissionAmount;
    }

    public isUpcoming(): boolean {
        const now = new Date();
        const bookingDateTime = new Date(`${this.bookingDate} ${this.startTime}`);
        return bookingDateTime > now && this.status === BookingStatus.CONFIRMED;
    }
}

Booking.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        bookingNumber: {
            type: DataTypes.STRING(20),
            allowNull: false,
            unique: true,
            field: 'booking_number',
        },
        userId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'user_id',
            references: {
                model: 'users',
                key: 'id',
            },
        },
        venueId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'venue_id',
            references: {
                model: 'venues',
                key: 'id',
            },
        },
        bookingDate: {
            type: DataTypes.DATEONLY,
            allowNull: false,
            field: 'booking_date',
        },
        startTime: {
            type: DataTypes.TIME,
            allowNull: false,
            field: 'start_time',
        },
        endTime: {
            type: DataTypes.TIME,
            allowNull: true,
            field: 'end_time',
        },
        numberOfGuests: {
            type: DataTypes.INTEGER,
            allowNull: false,
            field: 'number_of_guests',
            validate: {
                min: 1,
            },
        },
        totalAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            field: 'total_amount',
            validate: {
                min: 0,
            },
        },
        depositAmount: {
            type: DataTypes.DECIMAL(10, 2),
            defaultValue: 0,
            field: 'deposit_amount',
        },
        commissionAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            field: 'commission_amount',
            validate: {
                min: 0,
            },
        },
        status: {
            type: DataTypes.ENUM(...Object.values(BookingStatus)),
            defaultValue: BookingStatus.PENDING,
        },
        paymentStatus: {
            type: DataTypes.ENUM(...Object.values(PaymentStatus)),
            defaultValue: PaymentStatus.PENDING,
            field: 'payment_status',
        },
        isGroupBooking: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_group_booking',
        },
        cancellationReason: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'cancellation_reason',
        },
        cancelledAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'cancelled_at',
        },
        specialRequests: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'special_requests',
        },
        // Mobile booking flow fields
        goingMode: {
            type: DataTypes.ENUM(...Object.values(GoingMode)),
            allowNull: true,
            defaultValue: GoingMode.SOLO,
            field: 'going_mode',
        },
        tablePackage: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'table_package',
        },
        paymentMode: {
            type: DataTypes.ENUM(...Object.values(BookingPaymentMode)),
            allowNull: true,
            field: 'payment_mode',
        },
        ticketCode: {
            type: DataTypes.STRING(100),
            allowNull: true,
            unique: true,
            field: 'ticket_code',
        },
        ticketUrl: {
            type: DataTypes.STRING(500),
            allowNull: true,
            field: 'ticket_url',
        },
        addedToWallet: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'added_to_wallet',
        },
        // Large Party fields
        partySubject: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'party_subject',
        },
        partyRequirement: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'party_requirement',
        },
        partyDescription: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'party_description',
        },
        isLargePartyRequest: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_large_party_request',
        },
        isUpcomingNight: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_upcoming_night',
        },
        adminApprovalStatus: {
            type: DataTypes.ENUM(...Object.values(AdminApprovalStatus)),
            allowNull: true,
            field: 'admin_approval_status',
        },
        mobileNumber: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'mobile_number',
        },
        optionalMobileNumber: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'optional_mobile_number',
        },
        adminPaymentLink: {
            type: DataTypes.STRING(500),
            allowNull: true,
            field: 'admin_payment_link',
        },
        adminPaymentAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            field: 'admin_payment_amount',
        },
        razorpayOrderId: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'razorpay_order_id',
        },
    },
    {
        sequelize,
        tableName: 'bookings',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['venue_id'] },
            { fields: ['booking_date'] },
            { fields: ['status'] },
            { fields: ['booking_number'], unique: true },
        ],
    }
);

// Generate bookingNumber BEFORE validation (beforeCreate fires too late — after null checks)
Booking.beforeValidate((booking) => {
    if (!booking.bookingNumber) {
        const timestamp = Date.now().toString(36).toUpperCase();
        const random    = Math.random().toString(36).substring(2, 6).toUpperCase();
        booking.bookingNumber = `BK${timestamp}${random}`;
    }
});

export default Booking;
