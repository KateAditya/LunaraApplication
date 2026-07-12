import { Model, DataTypes } from 'sequelize';
import sequelize from '../config/database';
import User from './User';

export enum UsagePeriod {
    DAILY = 'daily',
    WEEKLY = 'weekly',
    MONTHLY = 'monthly',
    LIFETIME = 'lifetime',
}

class SubscriptionUsage extends Model {
    public id!: string;
    public userId!: string;
    public featureKey!: string;
    public period!: UsagePeriod;
    public used!: number;
    public resetAt!: Date | null;

    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

SubscriptionUsage.init(
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
        featureKey: {
            type: DataTypes.STRING(100),
            allowNull: false,
            field: 'feature_key',
        },
        period: {
            type: DataTypes.STRING(20),
            allowNull: false,
        },
        used: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
        },
        resetAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'reset_at',
        },
    },
    {
        sequelize,
        modelName: 'SubscriptionUsage',
        tableName: 'SubscriptionUsage',
        timestamps: true,
        underscored: true,
        indexes: [
            {
                unique: true,
                fields: ['user_id', 'feature_key', 'period'],
            },
            {
                fields: ['user_id'],
            },
        ],
    }
);

SubscriptionUsage.belongsTo(User, { foreignKey: 'user_id', as: 'user' });

export default SubscriptionUsage;
