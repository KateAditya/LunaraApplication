import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface WalletPromotionalCampaignAttributes {
    id: string;
    campaignCode: string;
    title: string;
    description?: string | null;
    creditAmount: number;
    expiryDays: number;
    maxUses: number;
    usedCount: number;
    isActive: boolean;
    startDate?: Date | null;
    endDate?: Date | null;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface WalletPromotionalCampaignCreationAttributes
    extends Optional<
        WalletPromotionalCampaignAttributes,
        'id' | 'description' | 'usedCount' | 'isActive' | 'startDate' | 'endDate' | 'createdAt' | 'updatedAt'
    > {}

class WalletPromotionalCampaign
    extends Model<WalletPromotionalCampaignAttributes, WalletPromotionalCampaignCreationAttributes>
    implements WalletPromotionalCampaignAttributes {
    public id!: string;
    public campaignCode!: string;
    public title!: string;
    public description?: string | null;
    public creditAmount!: number;
    public expiryDays!: number;
    public maxUses!: number;
    public usedCount!: number;
    public isActive!: boolean;
    public startDate?: Date | null;
    public endDate?: Date | null;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

WalletPromotionalCampaign.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        campaignCode: {
            type: DataTypes.STRING(50),
            allowNull: false,
            unique: true,
            field: 'campaign_code',
        },
        title: {
            type: DataTypes.STRING(200),
            allowNull: false,
        },
        description: {
            type: DataTypes.TEXT,
            allowNull: true,
        },
        creditAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            field: 'credit_amount',
            get() {
                const val = this.getDataValue('creditAmount');
                return val === null || val === undefined ? 0.00 : parseFloat(val.toString());
            },
        },
        expiryDays: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 30,
            field: 'expiry_days',
        },
        maxUses: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 1000,
            field: 'max_uses',
        },
        usedCount: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
            field: 'used_count',
        },
        isActive: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: true,
            field: 'is_active',
        },
        startDate: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'start_date',
        },
        endDate: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'end_date',
        },
    },
    {
        sequelize,
        tableName: 'wallet_promotional_campaigns',
        timestamps: true,
        indexes: [{ fields: ['campaign_code'] }, { fields: ['is_active'] }],
    }
);

export default WalletPromotionalCampaign;
