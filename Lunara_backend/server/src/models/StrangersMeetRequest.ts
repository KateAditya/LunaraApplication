import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum StrangersMeetStatus {
    PENDING = 'pending',
    APPROVED = 'approved',
    START_CONFIRMATION_PENDING = 'start_confirmation_pending',
    IN_PROGRESS = 'in_progress',
    END_CONFIRMATION_PENDING = 'end_confirmation_pending',
    HOST_CONFIRMED_ENDED = 'host_confirmed_ended',
    ADMIN_CONFIRMED_ENDED = 'admin_confirmed_ended',
    SETTLED = 'settled',
    COMPLETED = 'completed',
    REJECTED = 'rejected',
    NOT_STARTED = 'not_started',
    NEEDS_HOST_CONTACT = 'needs_host_contact',
    CANCELLED = 'cancelled',
    ADMIN_RESOLVED = 'admin_resolved',
}

export enum StrangersMeetPaymentStatus {
    UNPAID = 'unpaid',
    PAID = 'paid',
}

export interface StrangersMeetRequestAttributes {
    id: string;
    userId: string;
    venueId: string;
    subject: string;
    tagline: string;
    eventDateTime: Date;
    numberOfPersons: number;
    chargesPerHead: number;          // Set by user on creation
    slotsFilled: number;             // Number of joined users
    status: StrangersMeetStatus;
    paymentAmount?: number;          // Set by admin on approval (deposit request)
    paymentStatus: StrangersMeetPaymentStatus;
    mobileNumber: string;
    alternateMobileNumber?: string;
    adminNotes?: string;
    ticketId?: string;               // Generated on payment
    ticketUrl?: string;              // Generated PDF url
    razorpayOrderId?: string;
    razorpayPaymentId?: string;
    razorpaySignature?: string;
    settlementStatus?: 'none' | 'requested' | 'approved' | 'settlement_pending' | 'paid' | 'settled';
    bankDetails?: string;         // Legacy text field (kept for backward compat)
    // v2: Structured bank payment fields (collected at creation)
    bankName?: string;
    accountNumber?: string;
    accountHolderName?: string;
    ifscCode?: string;
    upiId?: string;
    upiNumber?: string;
    platformChargePerSeat?: number; // Auto-calc'd by admin: paymentAmount / numberOfPersons
    settlementTransactionId?: string;
    settlementAmount?: number;
    settlementDate?: Date;
    settlementMethod?: string;
    foodPreference?: string;
    drinkPreference?: string;
    reminder2hSent?: boolean;
    reminder1hSent?: boolean;
    reminder30mSent?: boolean;
    // Lifecycle additions
    startedAt?: Date;
    startedBy?: string;
    durationHours?: number;
    expectedEndAt?: Date;
    endedAt?: Date;
    endedConfirmedBy?: string;
    endedConfirmedAt?: Date;
    adminConfirmedEndedAt?: Date;
    adminConfirmedBy?: string;
    settlementOverdue?: boolean;
    // Escalation & Fallback fields
    escalatedAt?: Date;
    escalationReason?: string;
    adminResolution?: string;
    adminResolutionNotes?: string;
    adminResolvedAt?: Date;
    adminResolvedBy?: string;
    hostNotStartedAt?: Date;
    hostNotStartedReason?: string;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface StrangersMeetRequestCreationAttributes
    extends Optional<
        StrangersMeetRequestAttributes,
        | 'id'
        | 'status'
        | 'slotsFilled'
        | 'paymentAmount'
        | 'paymentStatus'
        | 'alternateMobileNumber'
        | 'adminNotes'
        | 'ticketId'
        | 'ticketUrl'
        | 'razorpayOrderId'
        | 'razorpayPaymentId'
        | 'razorpaySignature'
        | 'settlementStatus'
        | 'bankDetails'
        | 'bankName'
        | 'accountNumber'
        | 'accountHolderName'
        | 'ifscCode'
        | 'upiId'
        | 'upiNumber'
        | 'platformChargePerSeat'
        | 'settlementTransactionId'
        | 'settlementAmount'
        | 'settlementDate'
        | 'settlementMethod'
        | 'foodPreference'
        | 'drinkPreference'
        | 'reminder2hSent'
        | 'reminder1hSent'
        | 'reminder30mSent'
        | 'startedAt'
        | 'startedBy'
        | 'durationHours'
        | 'expectedEndAt'
        | 'endedAt'
        | 'endedConfirmedBy'
        | 'endedConfirmedAt'
        | 'adminConfirmedEndedAt'
        | 'adminConfirmedBy'
        | 'settlementOverdue'
        | 'escalatedAt'
        | 'escalationReason'
        | 'adminResolution'
        | 'adminResolutionNotes'
        | 'adminResolvedAt'
        | 'adminResolvedBy'
        | 'hostNotStartedAt'
        | 'hostNotStartedReason'
        | 'createdAt'
        | 'updatedAt'
    > { }

class StrangersMeetRequest
    extends Model<StrangersMeetRequestAttributes, StrangersMeetRequestCreationAttributes>
    implements StrangersMeetRequestAttributes {
    public id!: string;
    public userId!: string;
    public venueId!: string;
    public subject!: string;
    public tagline!: string;
    public eventDateTime!: Date;
    public numberOfPersons!: number;
    public chargesPerHead!: number;
    public slotsFilled!: number;
    public status!: StrangersMeetStatus;
    public paymentAmount?: number;
    public paymentStatus!: StrangersMeetPaymentStatus;
    public mobileNumber!: string;
    public alternateMobileNumber?: string;
    public adminNotes?: string;
    public ticketId?: string;
    public ticketUrl?: string;
    public razorpayOrderId?: string;
    public razorpayPaymentId?: string;
    public razorpaySignature?: string;
    public settlementStatus?: 'none' | 'requested' | 'approved' | 'settlement_pending' | 'paid' | 'settled';
    public bankDetails?: string;
    public bankName?: string;
    public accountNumber?: string;
    public accountHolderName?: string;
    public ifscCode?: string;
    public upiId?: string;
    public upiNumber?: string;
    public platformChargePerSeat?: number;
    public settlementTransactionId?: string;
    public settlementAmount?: number;
    public settlementDate?: Date;
    public settlementMethod?: string;
    public foodPreference?: string;
    public drinkPreference?: string;
    public reminder2hSent!: boolean;
    public reminder1hSent!: boolean;
    public reminder30mSent!: boolean;
    public startedAt?: Date;
    public startedBy?: string;
    public durationHours?: number;
    public expectedEndAt?: Date;
    public endedAt?: Date;
    public endedConfirmedBy?: string;
    public endedConfirmedAt?: Date;
    public adminConfirmedEndedAt?: Date;
    public adminConfirmedBy?: string;
    public settlementOverdue!: boolean;
    public escalatedAt?: Date;
    public escalationReason?: string;
    public adminResolution?: string;
    public adminResolutionNotes?: string;
    public adminResolvedAt?: Date;
    public adminResolvedBy?: string;
    public hostNotStartedAt?: Date;
    public hostNotStartedReason?: string;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

StrangersMeetRequest.init(
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
        subject: {
            type: DataTypes.STRING(200),
            allowNull: false,
            validate: {
                len: [1, 200],
            },
        },
        tagline: {
            type: DataTypes.TEXT,
            allowNull: false,
        },
        eventDateTime: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'event_date_time',
        },
        numberOfPersons: {
            type: DataTypes.INTEGER,
            allowNull: false,
            field: 'number_of_persons',
            validate: {
                min: 21,
                max: 50,
            },
        },
        chargesPerHead: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.0,
            field: 'charges_per_head',
        },
        slotsFilled: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
            field: 'slots_filled',
        },
        status: {
            type: DataTypes.ENUM(
                'pending',
                'approved',
                'start_confirmation_pending',
                'in_progress',
                'end_confirmation_pending',
                'host_confirmed_ended',
                'admin_confirmed_ended',
                'settled',
                'completed',
                'rejected',
                'not_started',
                'needs_host_contact',
                'cancelled',
                'admin_resolved'
            ),
            allowNull: false,
            defaultValue: 'pending',
        },
        paymentAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            field: 'payment_amount',
        },
        paymentStatus: {
            type: DataTypes.ENUM('unpaid', 'paid'),
            allowNull: false,
            defaultValue: 'unpaid',
            field: 'payment_status',
        },
        mobileNumber: {
            type: DataTypes.STRING(20),
            allowNull: false,
            field: 'mobile_number',
        },
        alternateMobileNumber: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'alternate_mobile_number',
        },
        adminNotes: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'admin_notes',
        },
        ticketId: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'ticket_id',
        },
        ticketUrl: {
            type: DataTypes.STRING(500),
            allowNull: true,
            field: 'ticket_url',
        },
        razorpayOrderId: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'razorpay_order_id',
        },
        razorpayPaymentId: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'razorpay_payment_id',
        },
        razorpaySignature: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'razorpay_signature',
        },
        settlementStatus: {
            type: DataTypes.ENUM('none', 'requested', 'approved', 'settlement_pending', 'paid', 'settled'),
            allowNull: true,
            defaultValue: 'none',
            field: 'settlement_status',
        },
        bankDetails: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'bank_details',
        },
        bankName: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'bank_name',
        },
        accountNumber: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'account_number',
        },
        accountHolderName: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'account_holder_name',
        },
        ifscCode: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'ifsc_code',
        },
        upiId: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'upi_id',
        },
        upiNumber: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'upi_number',
        },
        platformChargePerSeat: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            defaultValue: 0,
            field: 'platform_charge_per_seat',
        },
        settlementTransactionId: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'settlement_transaction_id',
        },
        settlementAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            field: 'settlement_amount',
        },
        settlementDate: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'settlement_date',
        },
        settlementMethod: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'settlement_method',
        },
        foodPreference: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'food_preference',
        },
        drinkPreference: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'drink_preference',
        },
        reminder2hSent: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'reminder_2h_sent',
        },
        reminder1hSent: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'reminder_1h_sent',
        },
        reminder30mSent: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'reminder_30m_sent',
        },
        startedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'started_at',
        },
        startedBy: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'started_by',
        },
        durationHours: {
            type: DataTypes.FLOAT,
            allowNull: true,
            field: 'duration_hours',
        },
        expectedEndAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'expected_end_at',
        },
        endedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'ended_at',
        },
        endedConfirmedBy: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'ended_confirmed_by',
        },
        endedConfirmedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'ended_confirmed_at',
        },
        adminConfirmedEndedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'admin_confirmed_ended_at',
        },
        adminConfirmedBy: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'admin_confirmed_by',
        },
        settlementOverdue: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'settlement_overdue',
        },
        escalatedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'escalated_at',
        },
        escalationReason: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'escalation_reason',
        },
        adminResolution: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'admin_resolution',
        },
        adminResolutionNotes: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'admin_resolution_notes',
        },
        adminResolvedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'admin_resolved_at',
        },
        adminResolvedBy: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'admin_resolved_by',
        },
        hostNotStartedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'host_not_started_at',
        },
        hostNotStartedReason: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'host_not_started_reason',
        },
    },
    {
        sequelize,
        tableName: 'strangers_meet_requests',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['venue_id'] },
            { fields: ['status'] },
            { fields: ['payment_status'] },
            { fields: ['created_at'] },
        ],
    }
);

export default StrangersMeetRequest;
