import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum StrangersMeetStatus {
    PENDING = 'pending',
    APPROVED = 'approved',
    REJECTED = 'rejected',
    COMPLETED = 'completed',
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
    razorpayOrderId?: string;
    razorpayPaymentId?: string;
    razorpaySignature?: string;
    settlementStatus?: 'none' | 'requested' | 'paid';
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
    public razorpayOrderId?: string;
    public razorpayPaymentId?: string;
    public razorpaySignature?: string;
    public settlementStatus?: 'none' | 'requested' | 'paid';
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
                notEmpty: { msg: 'Subject is required' },
                len: { args: [1, 200], msg: 'Subject must be between 1 and 200 characters' },
            },
        },
        tagline: {
            type: DataTypes.TEXT,
            allowNull: false,
            validate: {
                notEmpty: { msg: 'Tagline is required' },
            },
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
                min: { args: [21], msg: 'Minimum 21 persons required' },
                max: { args: [50], msg: 'Maximum 50 persons allowed' },
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
            type: DataTypes.ENUM(...Object.values(StrangersMeetStatus)),
            allowNull: false,
            defaultValue: StrangersMeetStatus.PENDING,
        },
        paymentAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            field: 'payment_amount',
        },
        paymentStatus: {
            type: DataTypes.ENUM(...Object.values(StrangersMeetPaymentStatus)),
            allowNull: false,
            defaultValue: StrangersMeetPaymentStatus.UNPAID,
            field: 'payment_status',
        },
        mobileNumber: {
            type: DataTypes.STRING(20),
            allowNull: false,
            defaultValue: '',
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
            unique: true,
            field: 'ticket_id',
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
            type: DataTypes.STRING(200),
            allowNull: true,
            field: 'razorpay_signature',
        },
        settlementStatus: {
            type: DataTypes.ENUM('none', 'requested', 'paid'),
            allowNull: false,
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
