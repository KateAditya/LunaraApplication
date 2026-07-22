import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface PlanTimeLockAttributes {
    id: string;
    userId: string;
    sourcePlanId: string;
    sourcePlanType: string;
    lockStartAt: Date;
    lockEndAt: Date;
    status: 'active' | 'cancelled' | 'expired';
    reason?: string;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface PlanTimeLockCreationAttributes
    extends Optional<PlanTimeLockAttributes, 'id' | 'status' | 'reason' | 'createdAt' | 'updatedAt'> {}

class PlanTimeLock
    extends Model<PlanTimeLockAttributes, PlanTimeLockCreationAttributes>
    implements PlanTimeLockAttributes
{
    public id!: string;
    public userId!: string;
    public sourcePlanId!: string;
    public sourcePlanType!: string;
    public lockStartAt!: Date;
    public lockEndAt!: Date;
    public status!: 'active' | 'cancelled' | 'expired';
    public reason?: string;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

PlanTimeLock.init(
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
        sourcePlanId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'source_plan_id',
        },
        sourcePlanType: {
            type: DataTypes.STRING,
            allowNull: false,
            field: 'source_plan_type',
        },
        lockStartAt: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'lock_start_at',
        },
        lockEndAt: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'lock_end_at',
        },
        status: {
            type: DataTypes.ENUM('active', 'cancelled', 'expired'),
            allowNull: false,
            defaultValue: 'active',
        },
        reason: {
            type: DataTypes.STRING,
            allowNull: true,
        },
    },
    {
        sequelize,
        modelName: 'PlanTimeLock',
        tableName: 'plan_time_locks',
        indexes: [
            { fields: ['user_id', 'status'] },
            { fields: ['user_id', 'lock_start_at', 'lock_end_at'] },
            { fields: ['user_id', 'lock_end_at'] },
            { fields: ['source_plan_id'] },
        ],
    }
);

export default PlanTimeLock;
