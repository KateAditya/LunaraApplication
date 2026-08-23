import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum PartyPlanStatus {
    ACTIVE = 'active',
    INACTIVE = 'inactive',
    CANCELLED = 'cancelled',
}

export enum PartyPlanVisibility {
    PUBLIC = 'public',
    PRIVATE = 'private',
    BOTH = 'both',
}

export enum PartyPlanPaymentStatus {
    UNPAID = 'unpaid',
    PAID = 'paid',
    REFUNDED = 'refunded',
}

export enum PartyPlanPaymentType {
    SPLIT = 'split',
    SELF_PAY = 'self_pay',
}

// ─────────────────────────────────────────────────────────────────────────────
// Master Lifecycle State Machine
// This is the single source of truth for every Party Plan's current state.
// ─────────────────────────────────────────────────────────────────────────────
export enum PartyPlanLifecycleStatus {
    DRAFT                   = 'draft',
    POSTED                  = 'posted',
    REQUEST_RECEIVED        = 'request_received',
    HOST_REVIEWING          = 'host_reviewing',
    USER_ACCEPTED           = 'user_accepted',
    PAYMENT_PENDING         = 'payment_pending',
    HOST_PAYMENT_COMPLETED  = 'host_payment_completed',
    GUEST_PAYMENT_COMPLETED = 'guest_payment_completed',
    MATCH_CONFIRMED         = 'match_confirmed',
    CHAT_ENABLED            = 'chat_enabled',
    EVENT_UPCOMING          = 'event_upcoming',
    EVENT_REMINDER          = 'event_reminder',
    ONE_HOUR_REMINDER       = 'one_hour_reminder',
    THIRTY_MIN_REMINDER     = 'thirty_min_reminder',
    TEN_MIN_CONFIRMATION    = 'ten_min_confirmation',
    ARRIVAL_PENDING         = 'arrival_pending',
    ARRIVAL_CONFIRMATION    = 'arrival_confirmation',
    ARRIVAL_VERIFIED        = 'arrival_verified',
    WALLET_CREDIT_PROCESSED = 'wallet_credit_processed',
    PLAN_COMPLETED          = 'plan_completed',
    COMPLETED               = 'completed',
    ARCHIVED                = 'archived',
    CANCELLATION_REQUESTED  = 'cancellation_requested',
    CANCELLED               = 'cancelled',
    EXPIRED                 = 'expired',
    FAILED                  = 'failed',
}

export interface PartyPlanAttributes {
    id: string;
    userId: string;           // Who created the plan
    venueId: string;          // Selected venue
    message: string;          // Party message / description
    planDateTime: Date;       // Combined date + time of the party
    status: PartyPlanStatus;
    lifecycleStatus: PartyPlanLifecycleStatus;  // Master state machine field
    visibility: PartyPlanVisibility;
    selectedUsers?: string[];
    depositAmount: number;
    hostPaymentStatus: PartyPlanPaymentStatus;
    hostRazorpayOrderId?: string;
    hostRazorpayPaymentId?: string;
    isLive: boolean;
    expiresAt?: Date;
    hostLatLangCheckIn: boolean;
    paymentStatus: string;
    mobileNumber: string;
    optionalMobileNumber?: string;
    foodPreference?: string;
    drinkPreference?: string;
    paymentType?: PartyPlanPaymentType;
    showProfilePhoto?: boolean;
    showHostName?: boolean;
    showVenueDetails?: boolean;
    showDateDetails?: boolean;
    hostArrivalConfirmed?: boolean;
    hostArrivalTime?: Date | null;
    hostFirstCheckStatus?: string | null;
    hostFirstCheckRespondedAt?: Date | null;
    hostFinalCheckStatus?: string | null;
    hostFinalCheckRespondedAt?: Date | null;
    reachVerificationStage?: string | null;
    attendanceDecision?: string | null;
    reachRefundDecision?: string | null;
    verificationExpiryAt?: Date | null;
    reminder24hSent?: boolean;
    reminder3hSent?: boolean;
    reminder1hSent?: boolean;
    reminder30mSent?: boolean;
    reminder2hSent?: boolean;
    reminder20mSent?: boolean;
    reminder10mSent?: boolean;
    reminder5mSent?: boolean;
    reminderOnTimeSent?: boolean;
    reminderPost5mSent?: boolean;
    reminderPost10mSent?: boolean;
    reminderPost30mSent?: boolean;
    expiredNoShowCancelled?: boolean;
    // ── Lifecycle Timestamps ──────────────────────────────────────────────────
    acceptedAt?: Date | null;       // When host accepted a requester
    paymentDeadlineAt?: Date | null; // Canonical 30-min payment deadline
    matchedRequestId?: string | null; // FK to the currently accepted PartyPlanRequest
    createdAt?: Date;
    updatedAt?: Date;
}

export interface PartyPlanCreationAttributes
    extends Optional<
        PartyPlanAttributes,
        'id' | 'status' | 'lifecycleStatus' | 'visibility' | 'createdAt' | 'updatedAt' | 'selectedUsers' | 'depositAmount' | 'hostPaymentStatus' | 'isLive' | 'expiresAt' | 'hostLatLangCheckIn' | 'paymentStatus' | 'optionalMobileNumber' | 'foodPreference' | 'drinkPreference' | 'paymentType' | 'showProfilePhoto' | 'showHostName' | 'showVenueDetails' | 'showDateDetails' | 'acceptedAt' | 'paymentDeadlineAt' | 'matchedRequestId'
    > { }

class PartyPlan
    extends Model<PartyPlanAttributes, PartyPlanCreationAttributes>
    implements PartyPlanAttributes {
    public id!: string;
    public userId!: string;
    public venueId!: string;
    public message!: string;
    public planDateTime!: Date;
    public status!: PartyPlanStatus;
    public lifecycleStatus!: PartyPlanLifecycleStatus;
    public visibility!: PartyPlanVisibility;
    public selectedUsers?: string[];
    public depositAmount!: number;
    public hostPaymentStatus!: PartyPlanPaymentStatus;
    public hostRazorpayOrderId?: string;
    public hostRazorpayPaymentId?: string;
    public isLive!: boolean;
    public expiresAt?: Date;
    public hostLatLangCheckIn!: boolean;
    public paymentStatus!: string;
    public mobileNumber!: string;
    public optionalMobileNumber?: string;
    public foodPreference?: string;
    public drinkPreference?: string;
    public paymentType!: PartyPlanPaymentType;
    public showProfilePhoto!: boolean;
    public showHostName!: boolean;
    public showVenueDetails!: boolean;
    public showDateDetails!: boolean;
    public hostArrivalConfirmed!: boolean;
    public hostArrivalTime?: Date | null;
    public hostFirstCheckStatus?: string | null;
    public hostFirstCheckRespondedAt?: Date | null;
    public hostFinalCheckStatus?: string | null;
    public hostFinalCheckRespondedAt?: Date | null;
    public reachVerificationStage?: string | null;
    public attendanceDecision?: string | null;
    public reachRefundDecision?: string | null;
    public verificationExpiryAt?: Date | null;
    public reminder24hSent!: boolean;
    public reminder3hSent!: boolean;
    public reminder1hSent!: boolean;
    public reminder30mSent!: boolean;
    public reminder2hSent!: boolean;
    public reminder20mSent!: boolean;
    public reminder10mSent!: boolean;
    public reminder5mSent!: boolean;
    public reminderOnTimeSent!: boolean;
    public reminderPost5mSent!: boolean;
    public reminderPost10mSent!: boolean;
    public reminderPost30mSent!: boolean;
    public expiredNoShowCancelled!: boolean;
    public acceptedAt?: Date | null;
    public paymentDeadlineAt?: Date | null;
    public matchedRequestId?: string | null;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

PartyPlan.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        userId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'user_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        venueId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'venue_id',
            references: { model: 'venues', key: 'id' },
            onDelete: 'CASCADE',
        },
        message: {
            type: DataTypes.TEXT,
            allowNull: false,
            validate: {
                notEmpty: { msg: 'Party message is required' },
                len: { args: [1, 500], msg: 'Message must be between 1 and 500 characters' },
            },
        },
        planDateTime: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'plan_date_time',
            validate: {
                isDate: { msg: 'planDateTime must be a valid date/time', args: true },
            },
        },
        status: {
            type: DataTypes.ENUM(...Object.values(PartyPlanStatus)),
            allowNull: false,
            defaultValue: PartyPlanStatus.ACTIVE,
        },
        lifecycleStatus: {
            type: DataTypes.ENUM(...Object.values(PartyPlanLifecycleStatus)),
            allowNull: false,
            defaultValue: PartyPlanLifecycleStatus.POSTED,
            field: 'lifecycle_status',
        },
        visibility: {
            type: DataTypes.ENUM(...Object.values(PartyPlanVisibility)),
            allowNull: false,
            defaultValue: PartyPlanVisibility.PUBLIC,
        },
        paymentType: {
            type: DataTypes.ENUM(...Object.values(PartyPlanPaymentType)),
            allowNull: false,
            defaultValue: PartyPlanPaymentType.SPLIT,
            field: 'payment_type',
        },
        selectedUsers: {
            type: DataTypes.ARRAY(DataTypes.UUID),
            allowNull: true,
            field: 'selected_users',
        },
        depositAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 99.00,
            field: 'deposit_amount',
        },
        hostPaymentStatus: {
            type: DataTypes.ENUM(...Object.values(PartyPlanPaymentStatus)),
            allowNull: false,
            defaultValue: PartyPlanPaymentStatus.UNPAID,
            field: 'host_payment_status',
        },
        hostRazorpayOrderId: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'host_razorpay_order_id',
        },
        hostRazorpayPaymentId: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'host_razorpay_payment_id',
        },
        isLive: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_live',
        },
        expiresAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'expires_at',
        },
        hostLatLangCheckIn: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'host_lat_lang_check_in',
        },
        paymentStatus: {
            type: DataTypes.STRING,
            allowNull: false,
            defaultValue: 'pending',
            field: 'payment_status',
        },
        mobileNumber: {
            type: DataTypes.STRING,
            allowNull: true,
            defaultValue: '',
            field: 'mobile_number',
        },
        optionalMobileNumber: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'optional_mobile_number',
        },
        foodPreference: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'food_preference',
        },
        drinkPreference: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'drink_preference',
        },
        showProfilePhoto: {
            type: DataTypes.BOOLEAN,
            defaultValue: true,
            field: 'show_profile_photo',
        },
        showHostName: {
            type: DataTypes.BOOLEAN,
            defaultValue: true,
            field: 'show_host_name',
        },
        showVenueDetails: {
            type: DataTypes.BOOLEAN,
            defaultValue: true,
            field: 'show_venue_details',
        },
        showDateDetails: {
            type: DataTypes.BOOLEAN,
            defaultValue: true,
            field: 'show_date_details',
        },
        hostArrivalConfirmed: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'host_arrival_confirmed',
        },
        hostArrivalTime: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'host_arrival_time',
        },
        hostFirstCheckStatus: {
            type: DataTypes.STRING(30),
            defaultValue: 'pending',
            field: 'host_first_check_status',
        },
        hostFirstCheckRespondedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'host_first_check_responded_at',
        },
        hostFinalCheckStatus: {
            type: DataTypes.STRING(30),
            defaultValue: 'pending',
            field: 'host_final_check_status',
        },
        hostFinalCheckRespondedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'host_final_check_responded_at',
        },
        reachVerificationStage: {
            type: DataTypes.STRING(30),
            defaultValue: 'pre_event_check',
            field: 'reach_verification_stage',
        },
        attendanceDecision: {
            type: DataTypes.STRING(40),
            defaultValue: 'pending',
            field: 'attendance_decision',
        },
        reachRefundDecision: {
            type: DataTypes.STRING(40),
            defaultValue: 'pending',
            field: 'reach_refund_decision',
        },
        verificationExpiryAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'verification_expiry_at',
        },
        reminder24hSent: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'reminder_24h_sent',
        },
        reminder3hSent: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'reminder_3h_sent',
        },
        reminder1hSent: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'reminder_1h_sent',
        },
        reminder30mSent: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'reminder_30m_sent',
        },
        reminder2hSent: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'reminder_2h_sent',
        },
        reminder20mSent: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'reminder_20m_sent',
        },
        reminder10mSent: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'reminder_10m_sent',
        },
        reminder5mSent: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'reminder_5m_sent',
        },
        reminderOnTimeSent: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'reminder_on_time_sent',
        },
        reminderPost5mSent: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'reminder_post_5m_sent',
        },
        reminderPost10mSent: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'reminder_post_10m_sent',
        },
        reminderPost30mSent: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'reminder_post_30m_sent',
        },
        expiredNoShowCancelled: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'expired_no_show_cancelled',
        },
        // ── Lifecycle Timestamps ────────────────────────────────────────────────
        acceptedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'accepted_at',
        },
        paymentDeadlineAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'payment_deadline_at',
        },
        matchedRequestId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'matched_request_id',
        },
    },
    {
        sequelize,
        tableName: 'party_plans',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['venue_id'] },
            { fields: ['status'] },
            { fields: ['lifecycle_status'] },
            { fields: ['plan_date_time'] },
            { fields: ['created_at'] },
        ],
    }
);

export default PartyPlan;
