import { Model, DataTypes } from 'sequelize';
import sequelize from '../config/database';
import SubscriptionPackage from './SubscriptionPackage';
import SubscriptionFeature from './SubscriptionFeature';

class SubscriptionPlanFeature extends Model {
    public id!: string;
    public packageId!: string;
    public featureId!: string;
    // JSONB value that stores the feature config, e.g.:
    //   { "enabled": true }                    — for boolean features
    //   { "enabled": true, "value": 10 }       — for integer/decimal features
    //   { "enabled": true, "value": "unlimited" } — for unlimited features
    //   { "enabled": true, "value": "5 GB" }   — for text features
    public value!: object;
    public isEnabled!: boolean;

    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    // Associations
    public readonly package?: SubscriptionPackage;
    public readonly feature?: SubscriptionFeature;
}

SubscriptionPlanFeature.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        packageId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'package_id',
            references: {
                model: 'SubscriptionPackages',
                key: 'id',
            },
            onDelete: 'CASCADE',
        },
        featureId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'feature_id',
            references: {
                model: 'SubscriptionFeatures',
                key: 'id',
            },
            onDelete: 'CASCADE',
        },
        value: {
            type: DataTypes.JSONB,
            allowNull: false,
            defaultValue: { enabled: false },
        },
        isEnabled: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: true,
            field: 'is_enabled',
        },
    },
    {
        sequelize,
        modelName: 'SubscriptionPlanFeature',
        tableName: 'SubscriptionPlanFeatures',
        timestamps: true,
        underscored: true,
        indexes: [
            {
                unique: true,
                fields: ['package_id', 'feature_id'],
            },
        ],
    }
);

// Associations
SubscriptionPlanFeature.belongsTo(SubscriptionPackage, { foreignKey: 'package_id', as: 'package' });
SubscriptionPlanFeature.belongsTo(SubscriptionFeature, { foreignKey: 'feature_id', as: 'feature' });
SubscriptionPackage.hasMany(SubscriptionPlanFeature, { foreignKey: 'package_id', as: 'planFeatures' });
SubscriptionFeature.hasMany(SubscriptionPlanFeature, { foreignKey: 'feature_id', as: 'planFeatures' });

export default SubscriptionPlanFeature;
