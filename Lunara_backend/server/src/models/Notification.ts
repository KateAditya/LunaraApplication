import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';
import { NotificationCategory, NotificationPriority } from '../types/NotificationEventTypes';
import apiCache from '../utils/apiCache';

export interface NotificationAttributes {
    id: string;
    recipientUserId: string;
    actorUserId?: string;
    eventType: string;
    category: NotificationCategory;
    entityType?: string;
    entityId?: string;
    title: string;
    body: string;
    imageUrl?: string;
    actionType?: string;
    deepLink?: string;
    isRead: boolean;
    readAt?: Date;
    expiresAt?: Date;
    priority: NotificationPriority;
    idempotencyKey?: string;
    metadata?: Record<string, any>;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface NotificationCreationAttributes
    extends Optional<
        NotificationAttributes,
        | 'id'
        | 'actorUserId'
        | 'entityType'
        | 'entityId'
        | 'imageUrl'
        | 'actionType'
        | 'deepLink'
        | 'isRead'
        | 'readAt'
        | 'expiresAt'
        | 'priority'
        | 'idempotencyKey'
        | 'metadata'
        | 'createdAt'
        | 'updatedAt'
    > {}

class Notification
    extends Model<NotificationAttributes, NotificationCreationAttributes>
    implements NotificationAttributes
{
    public id!: string;
    public recipientUserId!: string;
    public actorUserId?: string;
    public eventType!: string;
    public category!: NotificationCategory;
    public entityType?: string;
    public entityId?: string;
    public title!: string;
    public body!: string;
    public imageUrl?: string;
    public actionType?: string;
    public deepLink?: string;
    public isRead!: boolean;
    public readAt?: Date;
    public expiresAt?: Date;
    public priority!: NotificationPriority;
    public idempotencyKey?: string;
    public metadata?: Record<string, any>;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

Notification.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        recipientUserId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'recipient_user_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        actorUserId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'actor_user_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'SET NULL',
        },
        eventType: {
            type: DataTypes.STRING,
            allowNull: false,
            field: 'event_type',
        },
        category: {
            type: DataTypes.STRING,
            allowNull: false,
            defaultValue: 'system',
        },
        entityType: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'entity_type',
        },
        entityId: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'entity_id',
        },
        title: {
            type: DataTypes.STRING,
            allowNull: false,
        },
        body: {
            type: DataTypes.TEXT,
            allowNull: false,
        },
        imageUrl: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'image_url',
        },
        actionType: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'action_type',
        },
        deepLink: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'deep_link',
        },
        isRead: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'is_read',
        },
        readAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'read_at',
        },
        expiresAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'expires_at',
        },
        priority: {
            type: DataTypes.STRING,
            allowNull: false,
            defaultValue: 'NORMAL',
        },
        idempotencyKey: {
            type: DataTypes.STRING,
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
        modelName: 'Notification',
        tableName: 'notifications',
        indexes: [
            { fields: ['recipient_user_id', 'is_read'] },
            { fields: ['recipient_user_id', 'created_at'] },
            { fields: ['recipient_user_id', 'category'] },
            { fields: ['idempotency_key'] },
        ],
    }
);

// ─── Cache invalidation ──────────────────────────────────────────────────────
// The mobile notifications endpoint caches its (expensive) enriched response
// per user. Any write to this table must drop that user's entry so the next
// read reflects the change immediately. Hooking the model rather than each
// call site means every existing and future write path is covered, and no
// calling code has to change.
const invalidateNotificationCache = (recipientUserId?: string | null): void => {
    if (!recipientUserId || typeof recipientUserId !== 'string') return;
    apiCache.invalidatePrefix(`notif:${recipientUserId}:`);
    // Badge counts are derived from the same rows, so they go stale together.
    apiCache.invalidatePrefix(`badge:${recipientUserId}:`);
};

Notification.addHook('afterCreate', (instance: any) => {
    invalidateNotificationCache(instance?.recipientUserId);
});

Notification.addHook('afterUpdate', (instance: any) => {
    invalidateNotificationCache(instance?.recipientUserId);
});

Notification.addHook('afterDestroy', (instance: any) => {
    invalidateNotificationCache(instance?.recipientUserId);
});

Notification.addHook('afterBulkCreate', (instances: any[]) => {
    for (const instance of instances || []) {
        invalidateNotificationCache(instance?.recipientUserId);
    }
});

// Bulk update/destroy do not yield instances, so derive the owner from the
// WHERE clause. Callers always scope these by recipientUserId.
Notification.addHook('afterBulkUpdate', (options: any) => {
    invalidateNotificationCache(options?.where?.recipientUserId);
});

Notification.addHook('afterBulkDestroy', (options: any) => {
    invalidateNotificationCache(options?.where?.recipientUserId);
});

/** Drops every cached notifications response for one user. */
export const invalidateNotificationsFor = invalidateNotificationCache;

export default Notification;

