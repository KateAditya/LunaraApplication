import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum WalletTransactionType {
    RECHARGE = 'recharge',
    REFUND = 'refund',
    COMMITMENT_DEPOSIT = 'commitment_deposit',
    VIP_PURCHASE = 'vip_purchase',
    BOOKING_PAYMENT = 'booking_payment',
    WALLET_DEDUCTION = 'wallet_deduction',
    WALLET_CREDIT = 'wallet_credit',
}

export enum WalletTransactionStatus {
    PENDING = 'pending',
    SUCCESS = 'success',
    FAILED = 'failed',
}

export interface WalletTransactionAttributes {
    id: string;
    userId: string;
    bookingId?: string | null;
    partyPlanId?: string | null;
    amount: number;
    openingBalance: number;
    closingBalance: number;
    transactionType: WalletTransactionType;
    status: WalletTransactionStatus;
    reference?: string | null;
    metadata?: object | null;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface WalletTransactionCreationAttributes
    extends Optional<WalletTransactionAttributes, 'id' | 'status' | 'createdAt' | 'updatedAt'> {}

class WalletTransaction
    extends Model<WalletTransactionAttributes, WalletTransactionCreationAttributes>
    implements WalletTransactionAttributes {
    public id!: string;
    public userId!: string;
    public bookingId?: string | null;
    public partyPlanId?: string | null;
    public amount!: number;
    public openingBalance!: number;
    public closingBalance!: number;
    public transactionType!: WalletTransactionType;
    public status!: WalletTransactionStatus;
    public reference?: string | null;
    public metadata?: object | null;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    public static async logTransaction(params: {
        userId: string;
        bookingId?: string | null;
        partyPlanId?: string | null;
        amount: number;
        openingBalance: number;
        closingBalance: number;
        transactionType: WalletTransactionType;
        status?: WalletTransactionStatus;
        reference?: string | null;
        metadata?: object | null;
    }): Promise<WalletTransaction> {
        return await WalletTransaction.create({
            ...params,
            status: params.status || WalletTransactionStatus.SUCCESS,
        });
    }
}

WalletTransaction.init(
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
        bookingId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'booking_id',
        },
        partyPlanId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'party_plan_id',
        },
        amount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            get() {
                const val = this.getDataValue('amount');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        openingBalance: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            field: 'opening_balance',
            get() {
                const val = this.getDataValue('openingBalance');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        closingBalance: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            field: 'closing_balance',
            get() {
                const val = this.getDataValue('closingBalance');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        transactionType: {
            type: DataTypes.ENUM(...Object.values(WalletTransactionType)),
            allowNull: false,
            field: 'transaction_type',
        },
        status: {
            type: DataTypes.ENUM(...Object.values(WalletTransactionStatus)),
            allowNull: false,
            defaultValue: WalletTransactionStatus.SUCCESS,
        },
        reference: {
            type: DataTypes.STRING(255),
            allowNull: true,
        },
        metadata: {
            type: DataTypes.JSONB,
            allowNull: true,
        },
    },
    {
        sequelize,
        tableName: 'wallet_transactions',
        timestamps: true,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['transaction_type'] },
            { fields: ['created_at'] },
        ],
    }
);

export default WalletTransaction;
