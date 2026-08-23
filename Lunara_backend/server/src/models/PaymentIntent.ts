import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum PaymentIntentEntityType {
    PARTY_PLAN = 'party_plan',
    GROUP_PARTY = 'group_party',
    LARGE_PARTY = 'large_party',
    STRANGERS_MEET = 'strangers_meet',
    BOOST = 'boost',
    VIP_SUBSCRIPTION = 'vip_subscription',
    WALLET_RECHARGE = 'wallet_recharge',
    BOOKING = 'booking',
}

export enum PaymentIntentStatus {
    INITIATED = 'initiated',
    PENDING = 'pending',
    PROCESSING = 'processing',
    SUCCESS = 'success',
    FAILED = 'failed',
    CANCELLED = 'cancelled',
    EXPIRED = 'expired',
    REFUNDED = 'refunded',
}

export enum PaymentIntentMethod {
    WALLET = 'wallet',
    RAZORPAY = 'razorpay',
    HYBRID = 'hybrid',
    FREE = 'free',
}

export interface PaymentIntentAttributes {
    id: string;
    paymentReference: string;
    userId: string;
    entityType: PaymentIntentEntityType;
    entityId: string;
    amount: number;
    walletAmountUsed: number;
    razorpayAmount: number;
    currency: string;
    status: PaymentIntentStatus;
    paymentMethod: PaymentIntentMethod;
    razorpayOrderId?: string;
    razorpayPaymentId?: string;
    razorpaySignature?: string;
    expiresAt?: Date;
    failureReason?: string;
    metadata?: any;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface PaymentIntentCreationAttributes
    extends Optional<
        PaymentIntentAttributes,
        | 'id'
        | 'paymentReference'
        | 'walletAmountUsed'
        | 'razorpayAmount'
        | 'currency'
        | 'status'
        | 'paymentMethod'
        | 'razorpayOrderId'
        | 'razorpayPaymentId'
        | 'razorpaySignature'
        | 'expiresAt'
        | 'failureReason'
        | 'metadata'
        | 'createdAt'
        | 'updatedAt'
    > { }

class PaymentIntent extends Model<PaymentIntentAttributes, PaymentIntentCreationAttributes> implements PaymentIntentAttributes {
    public id!: string;
    public paymentReference!: string;
    public userId!: string;
    public entityType!: PaymentIntentEntityType;
    public entityId!: string;
    public amount!: number;
    public walletAmountUsed!: number;
    public razorpayAmount!: number;
    public currency!: string;
    public status!: PaymentIntentStatus;
    public paymentMethod!: PaymentIntentMethod;
    public razorpayOrderId?: string;
    public razorpayPaymentId?: string;
    public razorpaySignature?: string;
    public expiresAt?: Date;
    public failureReason?: string;
    public metadata?: any;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    public isSuccessful(): boolean {
        return this.status === PaymentIntentStatus.SUCCESS;
    }
}

PaymentIntent.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        paymentReference: {
            type: DataTypes.STRING(100),
            allowNull: false,
            unique: true,
            field: 'payment_reference',
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
        entityType: {
            type: DataTypes.STRING(50),
            allowNull: false,
            field: 'entity_type',
        },
        entityId: {
            type: DataTypes.STRING(100),
            allowNull: false,
            field: 'entity_id',
        },
        amount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
        },
        walletAmountUsed: {
            type: DataTypes.DECIMAL(10, 2),
            defaultValue: 0,
            field: 'wallet_amount_used',
        },
        razorpayAmount: {
            type: DataTypes.DECIMAL(10, 2),
            defaultValue: 0,
            field: 'razorpay_amount',
        },
        currency: {
            type: DataTypes.STRING(3),
            defaultValue: 'INR',
        },
        status: {
            type: DataTypes.STRING(30),
            defaultValue: PaymentIntentStatus.INITIATED,
        },
        paymentMethod: {
            type: DataTypes.STRING(30),
            defaultValue: PaymentIntentMethod.RAZORPAY,
            field: 'payment_method',
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
        expiresAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'expires_at',
        },
        failureReason: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'failure_reason',
        },
        metadata: {
            type: DataTypes.JSONB,
            allowNull: true,
        },
    },
    {
        sequelize,
        tableName: 'payment_intents',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['payment_reference'], unique: true },
            { fields: ['user_id'] },
            { fields: ['entity_type', 'entity_id'] },
            { fields: ['razorpay_order_id'] },
            { fields: ['status'] },
        ],
    }
);

PaymentIntent.beforeValidate((intent) => {
    if (!intent.paymentReference) {
        const timestamp = Date.now().toString(36).toUpperCase();
        const random = Math.random().toString(36).substring(2, 8).toUpperCase();
        intent.paymentReference = `LUNARA-PAY-${timestamp}${random}`;
    }
});

export default PaymentIntent;
