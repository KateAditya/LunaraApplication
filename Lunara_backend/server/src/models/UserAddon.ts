import { Model, DataTypes } from 'sequelize';
import sequelize from '../config/database';

export enum UserAddonStatus {
    ACTIVE = 'ACTIVE',
    CONSUMED = 'CONSUMED',
    EXPIRED = 'EXPIRED',
    CANCELLED = 'CANCELLED'
}

export class UserAddon extends Model {
    public id!: string;
    public userId!: string;
    public addonPackageId?: string | null;
    public featureKey!: string; // 'superlike', 'profile_boost', 'party_creation', etc.
    public purchasedQuantity!: number;
    public usedQuantity!: number;
    public remainingQuantity!: number;
    public status!: UserAddonStatus;
    public expiresAt?: Date | null;
    public metadata?: Record<string, any> | null;

    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

UserAddon.init(
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
        addonPackageId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'addon_package_id',
            references: {
                model: 'SubscriptionAddonPackages',
                key: 'id',
            },
            onDelete: 'SET NULL',
        },
        featureKey: {
            type: DataTypes.STRING(50),
            allowNull: false,
            field: 'feature_key',
        },
        purchasedQuantity: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
            field: 'purchased_quantity',
        },
        usedQuantity: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
            field: 'used_quantity',
        },
        remainingQuantity: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
            field: 'remaining_quantity',
        },
        status: {
            type: DataTypes.ENUM(...Object.values(UserAddonStatus)),
            allowNull: false,
            defaultValue: UserAddonStatus.ACTIVE,
        },
        expiresAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'expires_at',
        },
        metadata: {
            type: DataTypes.JSON,
            allowNull: true,
        },
    },
    {
        sequelize,
        modelName: 'UserAddon',
        tableName: 'UserAddons',
        timestamps: true,
        indexes: [
            {
                name: 'idx_user_addons_user_feature_status',
                fields: ['user_id', 'feature_key', 'status'],
            },
            {
                name: 'idx_user_addons_status_remaining',
                fields: ['status', 'remaining_quantity'],
            },
        ],
    }
);

export default UserAddon;
