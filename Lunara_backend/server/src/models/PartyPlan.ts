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

export interface PartyPlanAttributes {
    id: string;
    userId: string;           // Who created the plan
    venueId: string;          // Selected venue
    message: string;          // Party message / description
    planDateTime: Date;       // Combined date + time of the party
    status: PartyPlanStatus;
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
    createdAt?: Date;
    updatedAt?: Date;
}

export interface PartyPlanCreationAttributes
    extends Optional<
        PartyPlanAttributes,
        'id' | 'status' | 'visibility' | 'createdAt' | 'updatedAt' | 'selectedUsers' | 'depositAmount' | 'hostPaymentStatus' | 'isLive' | 'expiresAt' | 'hostLatLangCheckIn' | 'paymentStatus' | 'optionalMobileNumber' | 'foodPreference' | 'drinkPreference'
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
        visibility: {
            type: DataTypes.ENUM(...Object.values(PartyPlanVisibility)),
            allowNull: false,
            defaultValue: PartyPlanVisibility.PUBLIC,
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
            { fields: ['plan_date_time'] },
            { fields: ['created_at'] },
        ],
    }
);

export default PartyPlan;
