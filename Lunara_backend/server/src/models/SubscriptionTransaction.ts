import { Model, DataTypes } from 'sequelize';
import sequelize from '../config/database';
import User from './User';
import SubscriptionPackage from './SubscriptionPackage';

export enum TransactionType {
    PURCHASE = 'purchase',
    UPGRADE = 'upgrade',
    DOWNGRADE = 'downgrade',
    RENEW = 'renew',
    CANCEL = 'cancel',
    EXPIRE = 'expire',
    BOOST = 'boost',
    REFUND = 'refund',
    TRIAL = 'trial',
}

export enum TransactionStatus {
    PENDING = 'pending',
    SUCCESS = 'success',
    FAILED = 'failed',
    REFUNDED = 'refunded',
    CANCELLED = 'cancelled',
}

class SubscriptionTransaction extends Model {
    public id!: string;
    public userId!: string;
    public packageId!: string | null;
    public type!: TransactionType;
    public amount!: number;
    public currency!: string;
    public paymentMethod!: string | null;
    public paymentGateway!: string;
    public gatewayOrderId!: string | null;
    public gatewayPaymentId!: string | null;
    public status!: TransactionStatus;
    public invoiceNumber!: string | null;
    public refundAmount!: number;
    public refundedAt!: Date | null;
    public metadata!: object | null;

    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    // Associations
    public readonly user?: User;
    public readonly package?: SubscriptionPackage;
}

SubscriptionTransaction.init(
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
            references: {
                model: 'users',
                key: 'id',
            },
            onDelete: 'CASCADE',
        },
        packageId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'package_id',
            references: {
                model: 'SubscriptionPackages',
                key: 'id',
            },
        },
        type: {
            type: DataTypes.STRING(30),
            allowNull: false,
        },
        amount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0,
        },
        currency: {
            type: DataTypes.STRING(5),
            allowNull: false,
            defaultValue: 'INR',
        },
        paymentMethod: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'payment_method',
        },
        paymentGateway: {
            type: DataTypes.STRING(50),
            allowNull: false,
            defaultValue: 'razorpay',
            field: 'payment_gateway',
        },
        gatewayOrderId: {
            type: DataTypes.STRING(200),
            allowNull: true,
            field: 'gateway_order_id',
        },
        gatewayPaymentId: {
            type: DataTypes.STRING(200),
            allowNull: true,
            field: 'gateway_payment_id',
        },
        status: {
            type: DataTypes.STRING(20),
            allowNull: false,
            defaultValue: TransactionStatus.PENDING,
        },
        invoiceNumber: {
            type: DataTypes.STRING(50),
            allowNull: true,
            unique: true,
            field: 'invoice_number',
        },
        refundAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0,
            field: 'refund_amount',
        },
        refundedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'refunded_at',
        },
        metadata: {
            type: DataTypes.JSONB,
            allowNull: true,
        },
    },
    {
        sequelize,
        modelName: 'SubscriptionTransaction',
        tableName: 'SubscriptionTransactions',
        timestamps: true,
        underscored: true,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['package_id'] },
            { fields: ['status'] },
            { fields: ['type'] },
            { fields: ['created_at'] },
        ],
    }
);

SubscriptionTransaction.belongsTo(User, { foreignKey: 'user_id', as: 'user' });
SubscriptionTransaction.belongsTo(SubscriptionPackage, { foreignKey: 'package_id', as: 'package' });
User.hasMany(SubscriptionTransaction, { foreignKey: 'user_id', as: 'subscriptionTransactions' });

export default SubscriptionTransaction;
