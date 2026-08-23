import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum EngagementEventType {
    LIKE_SENT = 'LIKE_SENT',
    LIKE_REMOVED = 'LIKE_REMOVED',
    SUPERLIKE_SENT = 'SUPERLIKE_SENT',
    PARTY_PLAN_CREATED = 'PARTY_PLAN_CREATED',
    PARTY_PLAN_COMPLETED = 'PARTY_PLAN_COMPLETED',
    PROFILE_BOOST_STARTED = 'PROFILE_BOOST_STARTED',
    PROFILE_BOOST_EXPIRED = 'PROFILE_BOOST_EXPIRED',
    RELIABILITY_CHANGED = 'RELIABILITY_CHANGED',
}

export interface UserEngagementEventAttributes {
    id: string;
    userId: string;
    targetUserId?: string | null;
    eventType: EngagementEventType | string;
    entityType?: string | null;
    entityId?: string | null;
    idempotencyKey?: string | null;
    metadata?: object | null;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface UserEngagementEventCreationAttributes
    extends Optional<UserEngagementEventAttributes, 'id' | 'createdAt' | 'updatedAt'> {}

class UserEngagementEvent
    extends Model<UserEngagementEventAttributes, UserEngagementEventCreationAttributes>
    implements UserEngagementEventAttributes {
    public id!: string;
    public userId!: string;
    public targetUserId?: string | null;
    public eventType!: EngagementEventType | string;
    public entityType?: string | null;
    public entityId?: string | null;
    public idempotencyKey?: string | null;
    public metadata?: object | null;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

UserEngagementEvent.init(
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
        targetUserId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'target_user_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'SET NULL',
        },
        eventType: {
            type: DataTypes.STRING(50),
            allowNull: false,
            field: 'event_type',
        },
        entityType: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'entity_type',
        },
        entityId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'entity_id',
        },
        idempotencyKey: {
            type: DataTypes.STRING(255),
            allowNull: true,
            unique: true,
            field: 'idempotency_key',
        },
        metadata: {
            type: DataTypes.JSONB,
            allowNull: true,
        },
    },
    {
        sequelize,
        tableName: 'user_engagement_events',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['target_user_id'] },
            { fields: ['event_type'] },
            { fields: ['created_at'] },
        ],
    }
);

export default UserEngagementEvent;
