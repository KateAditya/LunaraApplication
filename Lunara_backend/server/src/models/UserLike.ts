import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum ProfileLikeAction {
    LIKE = 'like',
    SUPERLIKE = 'superlike',
    BACKTRACK = 'backtrack',
}

export interface UserLikeAttributes {
    id: string;
    userId: string;
    targetUserId: string;
    actionType: ProfileLikeAction | string;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface UserLikeCreationAttributes
    extends Optional<UserLikeAttributes, 'id' | 'createdAt' | 'updatedAt'> {}

class UserLike
    extends Model<UserLikeAttributes, UserLikeCreationAttributes>
    implements UserLikeAttributes {
    public id!: string;
    public userId!: string;
    public targetUserId!: string;
    public actionType!: ProfileLikeAction | string;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

UserLike.init(
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
        targetUserId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'target_user_id',
            references: {
                model: 'users',
                key: 'id',
            },
            onDelete: 'CASCADE',
        },
        actionType: {
            type: DataTypes.STRING(30),
            allowNull: false,
            defaultValue: 'like',
            field: 'action_type',
        },
    },
    {
        sequelize,
        tableName: 'user_likes',
        underscored: true,
        timestamps: true,
        indexes: [
            {
                unique: true,
                fields: ['user_id', 'target_user_id'],
                name: 'idx_user_target_like_unique',
            },
            {
                fields: ['user_id', 'action_type'],
            },
            {
                fields: ['created_at'],
            },
        ],
    }
);

export default UserLike;
