import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum RewardPointType {
    EARN = 'earn',
    REDEEM = 'redeem',
}

export interface RewardPointLedgerAttributes {
    id: string;
    userId: string;
    points: number;
    type: RewardPointType;
    balanceAfter: number;
    reason: string;
    reference?: string | null;
    metadata?: object | null;
    createdAt?: Date;
}

export interface RewardPointLedgerCreationAttributes
    extends Optional<RewardPointLedgerAttributes, 'id' | 'createdAt'> {}

class RewardPointLedger
    extends Model<RewardPointLedgerAttributes, RewardPointLedgerCreationAttributes>
    implements RewardPointLedgerAttributes {
    public id!: string;
    public userId!: string;
    public points!: number;
    public type!: RewardPointType;
    public balanceAfter!: number;
    public reason!: string;
    public reference?: string | null;
    public metadata?: object | null;
    public readonly createdAt!: Date;
}

RewardPointLedger.init(
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
        points: {
            type: DataTypes.INTEGER,
            allowNull: false,
        },
        type: {
            type: DataTypes.ENUM(...Object.values(RewardPointType)),
            allowNull: false,
        },
        balanceAfter: {
            type: DataTypes.INTEGER,
            allowNull: false,
            field: 'balance_after',
        },
        reason: {
            type: DataTypes.STRING(255),
            allowNull: false,
        },
        reference: {
            type: DataTypes.STRING(255),
            allowNull: true,
        },
        metadata: {
            type: DataTypes.JSONB,
            allowNull: true,
        },
    },
    {
        sequelize,
        tableName: 'reward_point_ledgers',
        timestamps: true,
        updatedAt: false,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['created_at'] },
        ],
    }
);

export default RewardPointLedger;
