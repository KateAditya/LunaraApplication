import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface PlanTimeLockConfigHistoryAttributes {
    id: string;
    configId: string;
    adminUserId: string;
    scope: string;
    previousValue: any;
    newValue: any;
    changeReason?: string;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface PlanTimeLockConfigHistoryCreationAttributes
    extends Optional<PlanTimeLockConfigHistoryAttributes, 'id' | 'changeReason' | 'createdAt' | 'updatedAt'> {}

class PlanTimeLockConfigHistory
    extends Model<PlanTimeLockConfigHistoryAttributes, PlanTimeLockConfigHistoryCreationAttributes>
    implements PlanTimeLockConfigHistoryAttributes
{
    public id!: string;
    public configId!: string;
    public adminUserId!: string;
    public scope!: string;
    public previousValue!: any;
    public newValue!: any;
    public changeReason?: string;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

PlanTimeLockConfigHistory.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        configId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'config_id',
        },
        adminUserId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'admin_user_id',
        },
        scope: {
            type: DataTypes.STRING,
            allowNull: false,
        },
        previousValue: {
            type: DataTypes.JSON,
            allowNull: false,
            field: 'previous_value',
        },
        newValue: {
            type: DataTypes.JSON,
            allowNull: false,
            field: 'new_value',
        },
        changeReason: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'change_reason',
        },
    },
    {
        sequelize,
        modelName: 'PlanTimeLockConfigHistory',
        tableName: 'plan_time_lock_config_histories',
    }
);

export default PlanTimeLockConfigHistory;
