import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

// Payment enums
export enum PaymentMethod {
    RAZORPAY = 'razorpay',
    UPI = 'upi',
    CARD = 'card',
    WALLET = 'wallet',
}

export enum PaymentStatus {
    INITIATED = 'initiated',
    PROCESSING = 'processing',
    SUCCESSFUL = 'successful',
    FAILED = 'failed',
    REFUNDED = 'refunded',
}

// Payment attributes
export interface PaymentAttributes {
    id: string;
    transactionId: string;
    bookingId: string;
    userId: string;
    groupMemberId?: string;
    amount: number;
    currency: string;
    paymentMethod: PaymentMethod;
    paymentGateway: string;
    gatewayResponse?: any;
    status: PaymentStatus;
    failureReason?: string;
    refundAmount: number;
    refundedAt?: Date;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface PaymentCreationAttributes
    extends Optional<
        PaymentAttributes,
        | 'id'
        | 'groupMemberId'
        | 'currency'
        | 'paymentGateway'
        | 'gatewayResponse'
        | 'status'
        | 'failureReason'
        | 'refundAmount'
        | 'refundedAt'
        | 'createdAt'
        | 'updatedAt'
    > { }

class Payment extends Model<PaymentAttributes, PaymentCreationAttributes> implements PaymentAttributes {
    public id!: string;
    public transactionId!: string;
    public bookingId!: string;
    public userId!: string;
    public groupMemberId?: string;
    public amount!: number;
    public currency!: string;
    public paymentMethod!: PaymentMethod;
    public paymentGateway!: string;
    public gatewayResponse?: any;
    public status!: PaymentStatus;
    public failureReason?: string;
    public refundAmount!: number;
    public refundedAt?: Date;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    // Instance methods
    public isSuccessful(): boolean {
        return this.status === PaymentStatus.SUCCESSFUL;
    }

    public isFailed(): boolean {
        return this.status === PaymentStatus.FAILED;
    }

    public isRefunded(): boolean {
        return this.status === PaymentStatus.REFUNDED;
    }

    public getNetAmount(): number {
        return this.amount - this.refundAmount;
    }

    public canBeRefunded(): boolean {
        return (
            this.status === PaymentStatus.SUCCESSFUL &&
            this.refundAmount < this.amount
        );
    }
}

Payment.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        transactionId: {
            type: DataTypes.STRING(100),
            allowNull: false,
            unique: true,
            field: 'transaction_id',
        },
        bookingId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'booking_id',
            references: {
                model: 'bookings',
                key: 'id',
            },
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
        groupMemberId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'group_member_id',
        },
        amount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            validate: {
                min: 0,
            },
        },
        currency: {
            type: DataTypes.STRING(3),
            defaultValue: 'INR',
        },
        paymentMethod: {
            type: DataTypes.ENUM(...Object.values(PaymentMethod)),
            allowNull: false,
            field: 'payment_method',
        },
        paymentGateway: {
            type: DataTypes.STRING(50),
            defaultValue: 'razorpay',
            field: 'payment_gateway',
        },
        gatewayResponse: {
            type: DataTypes.JSONB,
            allowNull: true,
            field: 'gateway_response',
        },
        status: {
            type: DataTypes.ENUM(...Object.values(PaymentStatus)),
            defaultValue: PaymentStatus.INITIATED,
        },
        failureReason: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'failure_reason',
        },
        refundAmount: {
            type: DataTypes.DECIMAL(10, 2),
            defaultValue: 0,
            field: 'refund_amount',
        },
        refundedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'refunded_at',
        },
    },
    {
        sequelize,
        tableName: 'payments',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['booking_id'] },
            { fields: ['user_id'] },
            { fields: ['transaction_id'], unique: true },
            { fields: ['status'] },
        ],
    }
);

// Generate transactionId BEFORE validation (beforeCreate fires too late — after null checks)
Payment.beforeValidate((payment) => {
    if (!payment.transactionId) {
        const timestamp = Date.now().toString(36).toUpperCase();
        const random    = Math.random().toString(36).substring(2, 8).toUpperCase();
        payment.transactionId = `TXN${timestamp}${random}`;
    }
});

export default Payment;
