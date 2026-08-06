import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface SmartWalletAttributes {
    id: string;
    userId: string;
    balance: number;
    lockedBalance: number;
    pendingBalance: number;
    promotionalBalance: number;
    cashbackBalance: number;
    rewardBalance: number;
    lifetimeRecharged: number;
    lifetimeSpent: number;
    lifetimePromotional: number;
    lifetimeCashback: number;
    lifetimeRewards: number;
    lifetimeRefunds: number;
    isFrozen: boolean;
    frozenReason?: string | null;
    frozenAt?: Date | null;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface SmartWalletCreationAttributes
    extends Optional<
        SmartWalletAttributes,
        | 'id'
        | 'balance'
        | 'lockedBalance'
        | 'pendingBalance'
        | 'promotionalBalance'
        | 'cashbackBalance'
        | 'rewardBalance'
        | 'lifetimeRecharged'
        | 'lifetimeSpent'
        | 'lifetimePromotional'
        | 'lifetimeCashback'
        | 'lifetimeRewards'
        | 'lifetimeRefunds'
        | 'isFrozen'
        | 'frozenReason'
        | 'frozenAt'
        | 'createdAt'
        | 'updatedAt'
    > {}

class SmartWallet
    extends Model<SmartWalletAttributes, SmartWalletCreationAttributes>
    implements SmartWalletAttributes {
    public id!: string;
    public userId!: string;
    public balance!: number;
    public lockedBalance!: number;
    public pendingBalance!: number;
    public promotionalBalance!: number;
    public cashbackBalance!: number;
    public rewardBalance!: number;
    public lifetimeRecharged!: number;
    public lifetimeSpent!: number;
    public lifetimePromotional!: number;
    public lifetimeCashback!: number;
    public lifetimeRewards!: number;
    public lifetimeRefunds!: number;
    public isFrozen!: boolean;
    public frozenReason?: string | null;
    public frozenAt?: Date | null;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    public get totalAvailableBalance(): number {
        return (
            Number(this.balance || 0) +
            Number(this.promotionalBalance || 0) +
            Number(this.cashbackBalance || 0) +
            Number(this.rewardBalance || 0)
        );
    }
}

SmartWallet.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        userId: {
            type: DataTypes.UUID,
            allowNull: false,
            unique: true,
            field: 'user_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        balance: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.00,
            get() {
                const val = this.getDataValue('balance');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        lockedBalance: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.00,
            field: 'locked_balance',
            get() {
                const val = this.getDataValue('lockedBalance');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        pendingBalance: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.00,
            field: 'pending_balance',
            get() {
                const val = this.getDataValue('pendingBalance');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        promotionalBalance: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.00,
            field: 'promotional_balance',
            get() {
                const val = this.getDataValue('promotionalBalance');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        cashbackBalance: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.00,
            field: 'cashback_balance',
            get() {
                const val = this.getDataValue('cashbackBalance');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        rewardBalance: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.00,
            field: 'reward_balance',
            get() {
                const val = this.getDataValue('rewardBalance');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        lifetimeRecharged: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.00,
            field: 'lifetime_recharged',
            get() {
                const val = this.getDataValue('lifetimeRecharged');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        lifetimeSpent: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.00,
            field: 'lifetime_spent',
            get() {
                const val = this.getDataValue('lifetimeSpent');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        lifetimePromotional: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.00,
            field: 'lifetime_promotional',
            get() {
                const val = this.getDataValue('lifetimePromotional');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        lifetimeCashback: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.00,
            field: 'lifetime_cashback',
            get() {
                const val = this.getDataValue('lifetimeCashback');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        lifetimeRewards: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.00,
            field: 'lifetime_rewards',
            get() {
                const val = this.getDataValue('lifetimeRewards');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        lifetimeRefunds: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.00,
            field: 'lifetime_refunds',
            get() {
                const val = this.getDataValue('lifetimeRefunds');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        isFrozen: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'is_frozen',
        },
        frozenReason: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'frozen_reason',
        },
        frozenAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'frozen_at',
        },
    },
    {
        sequelize,
        tableName: 'smart_wallets',
        timestamps: true,
        indexes: [{ fields: ['user_id'] }, { fields: ['is_frozen'] }],
    }
);

export default SmartWallet;
