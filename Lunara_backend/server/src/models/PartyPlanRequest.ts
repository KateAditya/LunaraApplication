import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum PartyPlanRequestStatus {
    PENDING = 'pending',
    PAYMENT_PENDING = 'payment_pending',
    ACCEPTED = 'accepted',
    REJECTED = 'rejected',
    CANCELLED = 'cancelled',
    PAYMENT_FAILED = 'payment_failed',
}

export enum PartyPlanJoinerPaymentStatus {
    UNPAID = 'unpaid',
    PAID = 'paid',
    REFUNDED = 'refunded',
}

export interface PartyPlanRequestAttributes {
    id: string;
    planId: string;
    requesterId: string;
    status: PartyPlanRequestStatus;
    joinerPaymentStatus: PartyPlanJoinerPaymentStatus;
    joinerRazorpayOrderId?: string;
    joinerRazorpayPaymentId?: string;
    paymentTimeoutAt?: Date;
    latLangCheckIn: boolean;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface PartyPlanRequestCreationAttributes
    extends Optional<
        PartyPlanRequestAttributes,
        'id' | 'status' | 'joinerPaymentStatus' | 'latLangCheckIn' | 'createdAt' | 'updatedAt'
    > {}

class PartyPlanRequest
    extends Model<PartyPlanRequestAttributes, PartyPlanRequestCreationAttributes>
    implements PartyPlanRequestAttributes {
    public id!: string;
    public planId!: string;
    public requesterId!: string;
    public status!: PartyPlanRequestStatus;
    public joinerPaymentStatus!: PartyPlanJoinerPaymentStatus;
    public joinerRazorpayOrderId?: string;
    public joinerRazorpayPaymentId?: string;
    public paymentTimeoutAt?: Date;
    public latLangCheckIn!: boolean;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

PartyPlanRequest.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        planId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'plan_id',
            references: { model: 'party_plans', key: 'id' },
            onDelete: 'CASCADE',
        },
        requesterId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'requester_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        status: {
            type: DataTypes.ENUM(...Object.values(PartyPlanRequestStatus)),
            allowNull: false,
            defaultValue: PartyPlanRequestStatus.PENDING,
        },
        joinerPaymentStatus: {
            type: DataTypes.ENUM(...Object.values(PartyPlanJoinerPaymentStatus)),
            allowNull: false,
            defaultValue: PartyPlanJoinerPaymentStatus.UNPAID,
            field: 'joiner_payment_status',
        },
        joinerRazorpayOrderId: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'joiner_razorpay_order_id',
        },
        joinerRazorpayPaymentId: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'joiner_razorpay_payment_id',
        },
        paymentTimeoutAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'payment_timeout_at',
        },
        latLangCheckIn: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'lat_lang_check_in',
        },
    },
    {
        sequelize,
        tableName: 'party_plan_requests',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['plan_id'] },
            { fields: ['requester_id'] },
            { fields: ['status'] },
        ],
    }
);

export default PartyPlanRequest;
