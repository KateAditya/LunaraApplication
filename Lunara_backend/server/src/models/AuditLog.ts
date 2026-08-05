import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface AuditLogAttributes {
    id: string;
    userId?: string | null;
    bookingId?: string | null;
    partyPlanId?: string | null;
    action: string;
    metadata?: object | null;
    ipAddress?: string | null;
    deviceId?: string | null;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface AuditLogCreationAttributes
    extends Optional<AuditLogAttributes, 'id' | 'createdAt' | 'updatedAt'> {}

class AuditLog
    extends Model<AuditLogAttributes, AuditLogCreationAttributes>
    implements AuditLogAttributes {
    public id!: string;
    public userId?: string | null;
    public bookingId?: string | null;
    public partyPlanId?: string | null;
    public action!: string;
    public metadata?: object | null;
    public ipAddress?: string | null;
    public deviceId?: string | null;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    public static async logAction(params: {
        userId?: string | null;
        bookingId?: string | null;
        partyPlanId?: string | null;
        action: string;
        metadata?: object | null;
        ipAddress?: string | null;
        deviceId?: string | null;
    }): Promise<AuditLog> {
        try {
            return await AuditLog.create(params);
        } catch (err) {
            console.error('[AuditLog] Failed to record audit log:', err);
            return null as any;
        }
    }
}

AuditLog.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        userId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'user_id',
        },
        bookingId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'booking_id',
        },
        partyPlanId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'party_plan_id',
        },
        action: {
            type: DataTypes.STRING(100),
            allowNull: false,
        },
        metadata: {
            type: DataTypes.JSONB,
            allowNull: true,
        },
        ipAddress: {
            type: DataTypes.STRING(45),
            allowNull: true,
            field: 'ip_address',
        },
        deviceId: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'device_id',
        },
    },
    {
        sequelize,
        tableName: 'audit_logs',
        timestamps: true,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['party_plan_id'] },
            { fields: ['booking_id'] },
            { fields: ['action'] },
            { fields: ['created_at'] },
        ],
    }
);

export default AuditLog;
