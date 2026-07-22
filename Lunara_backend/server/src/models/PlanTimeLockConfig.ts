import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface PlanTimeLockConfigAttributes {
    id: string;
    scope: string; // 'global' | 'subscription:FREE' | 'subscription:CORE' ... | 'role:customer' ... | 'plan_type:party_plan' ... | 'user:UUID'
    timeLockEnabled: boolean;
    defaultCooldownHours: number;
    maxActivePlans: number;
    maxDailyPlans: number;
    maxWeeklyPlans: number;
    allowOverlappingPlans: boolean;
    allowSameVenue: boolean;
    allowDifferentVenue: boolean;
    allowFuturePlans: boolean;
    allowEmergencyOverride: boolean;
    overlapPolicy: 'NO_OVERLAP' | 'ALLOW_TOUCHING_BOUNDARIES' | 'ALLOW_OVERLAP_WITH_DIFFERENT_PLAN_TYPES' | 'ALLOW_OVERLAP_FOR_PREMIUM_USERS';
    createdAt?: Date;
    updatedAt?: Date;
}

export interface PlanTimeLockConfigCreationAttributes
    extends Optional<
        PlanTimeLockConfigAttributes,
        | 'id'
        | 'timeLockEnabled'
        | 'defaultCooldownHours'
        | 'maxActivePlans'
        | 'maxDailyPlans'
        | 'maxWeeklyPlans'
        | 'allowOverlappingPlans'
        | 'allowSameVenue'
        | 'allowDifferentVenue'
        | 'allowFuturePlans'
        | 'allowEmergencyOverride'
        | 'overlapPolicy'
        | 'createdAt'
        | 'updatedAt'
    > {}

class PlanTimeLockConfig
    extends Model<PlanTimeLockConfigAttributes, PlanTimeLockConfigCreationAttributes>
    implements PlanTimeLockConfigAttributes
{
    public id!: string;
    public scope!: string;
    public timeLockEnabled!: boolean;
    public defaultCooldownHours!: number;
    public maxActivePlans!: number;
    public maxDailyPlans!: number;
    public maxWeeklyPlans!: number;
    public allowOverlappingPlans!: boolean;
    public allowSameVenue!: boolean;
    public allowDifferentVenue!: boolean;
    public allowFuturePlans!: boolean;
    public allowEmergencyOverride!: boolean;
    public overlapPolicy!: 'NO_OVERLAP' | 'ALLOW_TOUCHING_BOUNDARIES' | 'ALLOW_OVERLAP_WITH_DIFFERENT_PLAN_TYPES' | 'ALLOW_OVERLAP_FOR_PREMIUM_USERS';
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

PlanTimeLockConfig.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        scope: {
            type: DataTypes.STRING,
            allowNull: false,
            unique: true,
        },
        timeLockEnabled: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: true,
            field: 'time_lock_enabled',
        },
        defaultCooldownHours: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 4,
            field: 'default_cooldown_hours',
        },
        maxActivePlans: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 1,
            field: 'max_active_plans',
        },
        maxDailyPlans: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 3,
            field: 'max_daily_plans',
        },
        maxWeeklyPlans: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 10,
            field: 'max_weekly_plans',
        },
        allowOverlappingPlans: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'allow_overlapping_plans',
        },
        allowSameVenue: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'allow_same_venue',
        },
        allowDifferentVenue: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'allow_different_venue',
        },
        allowFuturePlans: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: true,
            field: 'allow_future_plans',
        },
        allowEmergencyOverride: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'allow_emergency_override',
        },
        overlapPolicy: {
            type: DataTypes.ENUM('NO_OVERLAP', 'ALLOW_TOUCHING_BOUNDARIES', 'ALLOW_OVERLAP_WITH_DIFFERENT_PLAN_TYPES', 'ALLOW_OVERLAP_FOR_PREMIUM_USERS'),
            allowNull: false,
            defaultValue: 'NO_OVERLAP',
            field: 'overlap_policy',
        },
    },
    {
        sequelize,
        modelName: 'PlanTimeLockConfig',
        tableName: 'plan_time_lock_configs',
    }
);

export default PlanTimeLockConfig;
