import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum CashbackTriggerType {
    RECHARGE = 'recharge',
    VIP_PURCHASE = 'vip_purchase',
    SUPER_LIKE_PURCHASE = 'super_like_purchase',
    BOOST_PURCHASE = 'boost_purchase',
    SPECIAL_CAMPAIGN = 'special_campaign',
}

export enum CashbackType {
    FLAT = 'flat',
    PERCENTAGE = 'percentage',
}

export interface WalletCashbackRuleAttributes {
    id: string;
    ruleName: string;
    triggerType: CashbackTriggerType;
    minSpend: number;
    cashbackType: CashbackType;
    cashbackValue: number;
    maxCashback: number;
    isActive: boolean;
    expiryDays: number;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface WalletCashbackRuleCreationAttributes
    extends Optional<
        WalletCashbackRuleAttributes,
        'id' | 'minSpend' | 'maxCashback' | 'isActive' | 'expiryDays' | 'createdAt' | 'updatedAt'
    > {}

class WalletCashbackRule
    extends Model<WalletCashbackRuleAttributes, WalletCashbackRuleCreationAttributes>
    implements WalletCashbackRuleAttributes {
    public id!: string;
    public ruleName!: string;
    public triggerType!: CashbackTriggerType;
    public minSpend!: number;
    public cashbackType!: CashbackType;
    public cashbackValue!: number;
    public maxCashback!: number;
    public isActive!: boolean;
    public expiryDays!: number;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

WalletCashbackRule.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        ruleName: {
            type: DataTypes.STRING(200),
            allowNull: false,
            field: 'rule_name',
        },
        triggerType: {
            type: DataTypes.ENUM(...Object.values(CashbackTriggerType)),
            allowNull: false,
            field: 'trigger_type',
        },
        minSpend: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.00,
            field: 'min_spend',
            get() {
                const val = this.getDataValue('minSpend');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        cashbackType: {
            type: DataTypes.ENUM(...Object.values(CashbackType)),
            allowNull: false,
            defaultValue: CashbackType.PERCENTAGE,
            field: 'cashback_type',
        },
        cashbackValue: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            field: 'cashback_value',
            get() {
                const val = this.getDataValue('cashbackValue');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        maxCashback: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 500.00,
            field: 'max_cashback',
            get() {
                const val = this.getDataValue('maxCashback');
                return val === null || val === undefined ? 500.00 : parseFloat(val.toString());
            },
        },
        isActive: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: true,
            field: 'is_active',
        },
        expiryDays: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 30,
            field: 'expiry_days',
        },
    },
    {
        sequelize,
        tableName: 'wallet_cashback_rules',
        timestamps: true,
        indexes: [{ fields: ['trigger_type'] }, { fields: ['is_active'] }],
    }
);

export default WalletCashbackRule;
