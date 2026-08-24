import { Model, DataTypes } from 'sequelize';
import sequelize from '../config/database';

export class SubscriptionAddonPackage extends Model {
    public id!: string;
    public name!: string;
    public featureKey!: string; // 'superlike', 'profile_boost', 'party_creation', 'likes', 'backtrack'
    public quantity!: number; // e.g. 5, 10, 1, 3
    public price!: number; // e.g. 49.00, 99.00, 149.00
    public currency!: string; // 'INR'
    public isActive!: boolean;
    public badge?: string | null; // 'POPULAR', 'BEST VALUE', 'LIGHTNING'
    public description?: string | null;
    public displayOrder!: number;

    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

SubscriptionAddonPackage.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        name: {
            type: DataTypes.STRING(100),
            allowNull: false,
        },
        featureKey: {
            type: DataTypes.STRING(50),
            allowNull: false,
            field: 'feature_key',
        },
        quantity: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 1,
        },
        price: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.0,
        },
        currency: {
            type: DataTypes.STRING(10),
            allowNull: false,
            defaultValue: 'INR',
        },
        isActive: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: true,
            field: 'is_active',
        },
        badge: {
            type: DataTypes.STRING(50),
            allowNull: true,
        },
        description: {
            type: DataTypes.TEXT,
            allowNull: true,
        },
        displayOrder: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
            field: 'display_order',
        },
    },
    {
        sequelize,
        modelName: 'SubscriptionAddonPackage',
        tableName: 'SubscriptionAddonPackages',
        timestamps: true,
        indexes: [
            {
                name: 'idx_addon_pkgs_active_feature',
                fields: ['is_active', 'feature_key'],
            },
        ],
    }
);

export default SubscriptionAddonPackage;
