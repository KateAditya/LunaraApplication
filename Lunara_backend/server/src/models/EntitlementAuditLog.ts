import { Model, DataTypes } from 'sequelize';
import sequelize from '../config/database';

export class EntitlementAuditLog extends Model {
    public id!: string;
    public userId!: string;
    public adminId?: string | null;
    public subscriptionId?: string | null;
    public addonId?: string | null;
    public feature!: string; // 'superlike', 'profile_boost', 'party_creation', 'daily_likes', 'backtrack'
    public action!: string; // 'PLAN_ENTITLEMENT_CONSUMED', 'ADDON_ENTITLEMENT_CONSUMED', 'ADDON_PURCHASED', 'ADMIN_ENTITLEMENT_ADJUSTED', 'PLAN_RENEWED', 'PLAN_EXPIRED'
    public source!: string; // 'PLAN', 'ADDON', 'ADMIN', 'SYSTEM'
    public quantity!: number; // e.g. -1, +5
    public oldValue?: Record<string, any> | null;
    public newValue?: Record<string, any> | null;
    public reason?: string | null;
    public requestId?: string | null;
    public metadata?: Record<string, any> | null;

    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

EntitlementAuditLog.init(
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
        adminId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'admin_id',
            references: {
                model: 'users',
                key: 'id',
            },
            onDelete: 'SET NULL',
        },
        subscriptionId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'subscription_id',
        },
        addonId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'addon_id',
        },
        feature: {
            type: DataTypes.STRING(50),
            allowNull: false,
        },
        action: {
            type: DataTypes.STRING(50),
            allowNull: false,
        },
        source: {
            type: DataTypes.STRING(20),
            allowNull: false,
            defaultValue: 'PLAN',
        },
        quantity: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 1,
        },
        oldValue: {
            type: DataTypes.JSON,
            allowNull: true,
            field: 'old_value',
        },
        newValue: {
            type: DataTypes.JSON,
            allowNull: true,
            field: 'new_value',
        },
        reason: {
            type: DataTypes.STRING(255),
            allowNull: true,
        },
        requestId: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'request_id',
        },
        metadata: {
            type: DataTypes.JSON,
            allowNull: true,
        },
    },
    {
        sequelize,
        modelName: 'EntitlementAuditLog',
        tableName: 'EntitlementAuditLogs',
        timestamps: true,
        indexes: [
            {
                name: 'idx_entitlement_audit_user_feature',
                fields: ['user_id', 'feature', 'created_at'],
            },
            {
                name: 'idx_entitlement_audit_action',
                fields: ['action', 'created_at'],
            },
        ],
    }
);

export default EntitlementAuditLog;
