import { Model, DataTypes } from 'sequelize';
import sequelize from '../config/database';

export enum FeatureValueType {
    BOOLEAN = 'boolean',
    INTEGER = 'integer',
    DECIMAL = 'decimal',
    UNLIMITED = 'unlimited',
    TEXT = 'text',
}

export enum FeatureCategory {
    MATCHING = 'matching',
    SOCIAL = 'social',
    VISIBILITY = 'visibility',
    PRIVACY = 'privacy',
    BADGE = 'badge',
    INSIGHTS = 'insights',
    AI = 'ai',
    COMMUNICATION = 'communication',
    EVENTS = 'events',
    DISCOVERY = 'discovery',
    STORAGE = 'storage',
    GENERAL = 'general',
}

class SubscriptionFeature extends Model {
    public id!: string;
    public key!: string;
    public name!: string;
    public description!: string | null;
    public category!: string;
    public valueType!: string;
    public displayOrder!: number;
    public isActive!: boolean;
    public icon!: string | null;

    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

SubscriptionFeature.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        key: {
            type: DataTypes.STRING(100),
            allowNull: false,
            unique: true,
        },
        name: {
            type: DataTypes.STRING(200),
            allowNull: false,
        },
        description: {
            type: DataTypes.TEXT,
            allowNull: true,
        },
        category: {
            type: DataTypes.STRING(50),
            allowNull: false,
            defaultValue: FeatureCategory.GENERAL,
        },
        valueType: {
            type: DataTypes.STRING(20),
            allowNull: false,
            defaultValue: FeatureValueType.BOOLEAN,
            field: 'value_type',
        },
        displayOrder: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
            field: 'display_order',
        },
        isActive: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: true,
            field: 'is_active',
        },
        icon: {
            type: DataTypes.STRING(50),
            allowNull: true,
        },
    },
    {
        sequelize,
        modelName: 'SubscriptionFeature',
        tableName: 'SubscriptionFeatures',
        timestamps: true,
        underscored: true,
    }
);

export default SubscriptionFeature;
