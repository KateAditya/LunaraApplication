import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum ProfileBoostStatus {
    ACTIVE = 'ACTIVE',
    EXPIRED = 'EXPIRED',
    CANCELLED = 'CANCELLED',
}

export interface ProfileBoostAttributes {
    id: string;
    userId: string;
    startedAt: Date;
    expiresAt: Date;
    status: ProfileBoostStatus | string;
    durationMinutes: number;
    transactionId?: string | null;
    metadata?: object | null;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface ProfileBoostCreationAttributes
    extends Optional<ProfileBoostAttributes, 'id' | 'createdAt' | 'updatedAt'> {}

class ProfileBoost
    extends Model<ProfileBoostAttributes, ProfileBoostCreationAttributes>
    implements ProfileBoostAttributes {
    public id!: string;
    public userId!: string;
    public startedAt!: Date;
    public expiresAt!: Date;
    public status!: ProfileBoostStatus | string;
    public durationMinutes!: number;
    public transactionId?: string | null;
    public metadata?: object | null;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

ProfileBoost.init(
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
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        startedAt: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'started_at',
            defaultValue: DataTypes.NOW,
        },
        expiresAt: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'expires_at',
        },
        status: {
            type: DataTypes.STRING(20),
            allowNull: false,
            defaultValue: ProfileBoostStatus.ACTIVE,
        },
        durationMinutes: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 30,
            field: 'duration_minutes',
        },
        transactionId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'transaction_id',
        },
        metadata: {
            type: DataTypes.JSONB,
            allowNull: true,
        },
    },
    {
        sequelize,
        tableName: 'profile_boosts',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['user_id', 'status'] },
            { fields: ['expires_at'] },
            { fields: ['status', 'expires_at'] },
        ],
    }
);

export default ProfileBoost;
