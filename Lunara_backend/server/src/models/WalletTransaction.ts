import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum WalletTransactionType {
    RECHARGE = 'recharge',
    BOOKING_PAYMENT = 'booking_payment',
    COMMITMENT_DEPOSIT = 'commitment_deposit',
    DEPOSIT_UNLOCK = 'deposit_unlock',
    REFUND = 'refund',
    CASHBACK = 'cashback',
    CASHBACK_CREDIT = 'cashback_credit',
    REWARD_CREDIT = 'reward_credit',
    REWARD_REDEMPTION = 'reward_redemption',
    VIP_PURCHASE = 'vip_purchase',
    MEMBERSHIP_RENEWAL = 'membership_renewal',
    MEMBERSHIP_UPGRADE = 'membership_upgrade',
    SUPER_LIKE_PURCHASE = 'super_like_purchase',
    PRIORITY_LIKE_PURCHASE = 'priority_like_purchase',
    BOOST_PURCHASE = 'boost_purchase',
    REFERRAL_REWARD = 'referral_reward',
    PROMOTIONAL_CREDIT = 'promotional_credit',
    ADMIN_CREDIT = 'admin_credit',
    ADMIN_DEBIT = 'admin_debit',
    CHARGEBACK = 'chargeback',
    REVERSAL = 'reversal',
    WALLET_DEDUCTION = 'wallet_deduction',
    WALLET_CREDIT = 'wallet_credit',
}

export enum WalletTransactionStatus {
    PENDING = 'pending',
    PROCESSING = 'processing',
    SUCCESS = 'success',
    FAILED = 'failed',
    LOCKED = 'locked',
    REFUNDED = 'refunded',
    CANCELLED = 'cancelled',
    EXPIRED = 'expired',
}

export interface WalletTransactionAttributes {
    id: string;
    walletId?: string | null;
    userId: string;
    bookingId?: string | null;
    partyPlanId?: string | null;
    amount: number;
    openingBalance: number;
    closingBalance: number;
    transactionType: WalletTransactionType;
    status: WalletTransactionStatus;
    reference?: string | null;
    source?: string | null;
    destination?: string | null;
    createdBy?: string | null;
    metadata?: object | null;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface WalletTransactionCreationAttributes
    extends Optional<WalletTransactionAttributes, 'id' | 'walletId' | 'status' | 'source' | 'destination' | 'createdBy' | 'createdAt' | 'updatedAt'> {}

class WalletTransaction
    extends Model<WalletTransactionAttributes, WalletTransactionCreationAttributes>
    implements WalletTransactionAttributes {
    public id!: string;
    public walletId?: string | null;
    public userId!: string;
    public bookingId?: string | null;
    public partyPlanId?: string | null;
    public amount!: number;
    public openingBalance!: number;
    public closingBalance!: number;
    public transactionType!: WalletTransactionType;
    public status!: WalletTransactionStatus;
    public reference?: string | null;
    public source?: string | null;
    public destination?: string | null;
    public createdBy?: string | null;
    public metadata?: object | null;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    public static async logTransaction(
        params: {
            walletId?: string | null;
            userId: string;
            bookingId?: string | null;
            partyPlanId?: string | null;
            amount: number;
            openingBalance: number;
            closingBalance: number;
            transactionType: WalletTransactionType;
            status?: WalletTransactionStatus;
            reference?: string | null;
            source?: string | null;
            destination?: string | null;
            createdBy?: string | null;
            metadata?: object | null;
        },
        options?: any
    ): Promise<WalletTransaction> {
        const createOptions = options ? (options.transaction ? options : { transaction: options }) : undefined;
        return (await WalletTransaction.create({
            ...params,
            status: params.status || WalletTransactionStatus.SUCCESS,
        }, createOptions)) as WalletTransaction;
    }
}

WalletTransaction.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        walletId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'wallet_id',
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
        source: {
            type: DataTypes.STRING(100),
            allowNull: true,
        },
        destination: {
            type: DataTypes.STRING(100),
            allowNull: true,
        },
        createdBy: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'created_by',
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
            { fields: ['status'] },
            { fields: ['created_at'] },
        ],
    }
);

export default WalletTransaction;
