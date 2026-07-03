import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface UserPenaltyAttributes {
    id: string;
    userId: string;
    planId?: string;
    reason: string;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface UserPenaltyCreationAttributes
    extends Optional<UserPenaltyAttributes, 'id' | 'createdAt' | 'updatedAt'> {}

class UserPenalty
    extends Model<UserPenaltyAttributes, UserPenaltyCreationAttributes>
    implements UserPenaltyAttributes {
    public id!: string;
    public userId!: string;
    public planId?: string;
    public reason!: string;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

UserPenalty.init(
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
        planId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'plan_id',
        },
        reason: {
            type: DataTypes.STRING,
            allowNull: false,
        },
    },
    {
        sequelize,
        tableName: 'user_penalties',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['user_id'] },
        ],
    }
);

export default UserPenalty;
