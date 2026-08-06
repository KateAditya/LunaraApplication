import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface SmartWalletConfigAttributes {
    id: string;
    scope: string;
    minRechargeAmount: number;
    maxRechargeAmount: number;
    suggestedAmounts: number[];
    dailyRechargeLimit: number;
    monthlyRechargeLimit: number;
    isWalletActive: boolean;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface SmartWalletConfigCreationAttributes
    extends Optional<
        SmartWalletConfigAttributes,
        | 'id'
        | 'scope'
        | 'minRechargeAmount'
        | 'maxRechargeAmount'
        | 'suggestedAmounts'
        | 'dailyRechargeLimit'
        | 'monthlyRechargeLimit'
        | 'isWalletActive'
        | 'createdAt'
        | 'updatedAt'
    > {}

class SmartWalletConfig
    extends Model<SmartWalletConfigAttributes, SmartWalletConfigCreationAttributes>
    implements SmartWalletConfigAttributes {
    public id!: string;
    public scope!: string;
    public minRechargeAmount!: number;
    public maxRechargeAmount!: number;
    public suggestedAmounts!: number[];
    public dailyRechargeLimit!: number;
    public monthlyRechargeLimit!: number;
    public isWalletActive!: boolean;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

SmartWalletConfig.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        scope: {
            type: DataTypes.STRING(50),
            allowNull: false,
            unique: true,
            defaultValue: 'global',
        },
        minRechargeAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 100.00,
            field: 'min_recharge_amount',
            get() {
                const val = this.getDataValue('minRechargeAmount');
                return val === null || val === undefined ? 100.00 : parseFloat(val.toString());
            },
        },
        maxRechargeAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 50000.00,
            field: 'max_recharge_amount',
            get() {
                const val = this.getDataValue('maxRechargeAmount');
                return val === null || val === undefined ? 50000.00 : parseFloat(val.toString());
            },
        },
        suggestedAmounts: {
            type: DataTypes.JSONB,
            allowNull: false,
            defaultValue: [100, 250, 500, 1000, 2000],
            field: 'suggested_amounts',
        },
        dailyRechargeLimit: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 100000.00,
            field: 'daily_recharge_limit',
            get() {
                const val = this.getDataValue('dailyRechargeLimit');
                return val === null || val === undefined ? 100000.00 : parseFloat(val.toString());
            },
        },
        monthlyRechargeLimit: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 500000.00,
            field: 'monthly_recharge_limit',
            get() {
                const val = this.getDataValue('monthlyRechargeLimit');
                return val === null || val === undefined ? 500000.00 : parseFloat(val.toString());
            },
        },
        isWalletActive: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: true,
            field: 'is_wallet_active',
        },
    },
    {
        sequelize,
        tableName: 'smart_wallet_configs',
        timestamps: true,
        indexes: [{ fields: ['scope'] }],
    }
);

export default SmartWalletConfig;
