import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface ReliabilityHistoryAttributes {
    id: string;
    userId: string;
    oldScore: number;
    newScore: number;
    change: number;
    reason: string;
    action: string;
    bookingId?: string | null;
    partyPlanId?: string | null;
    metadata?: object | null;
    createdAt?: Date;
}

export interface ReliabilityHistoryCreationAttributes
    extends Optional<ReliabilityHistoryAttributes, 'id' | 'createdAt'> {}

class ReliabilityHistory
    extends Model<ReliabilityHistoryAttributes, ReliabilityHistoryCreationAttributes>
    implements ReliabilityHistoryAttributes {
    public id!: string;
    public userId!: string;
    public oldScore!: number;
    public newScore!: number;
    public change!: number;
    public reason!: string;
    public action!: string;
    public bookingId?: string | null;
    public partyPlanId?: string | null;
    public metadata?: object | null;
    public readonly createdAt!: Date;
}

ReliabilityHistory.init(
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
        oldScore: {
            type: DataTypes.INTEGER,
            allowNull: false,
            field: 'old_score',
        },
        newScore: {
            type: DataTypes.INTEGER,
            allowNull: false,
            field: 'new_score',
        },
        change: {
            type: DataTypes.INTEGER,
            allowNull: false,
        },
        reason: {
            type: DataTypes.STRING(255),
            allowNull: false,
        },
        action: {
            type: DataTypes.STRING(255),
            allowNull: false,
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
        metadata: {
            type: DataTypes.JSONB,
            allowNull: true,
        },
    },
    {
        sequelize,
        tableName: 'reliability_history',
        timestamps: true,
        updatedAt: false,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['created_at'] },
        ],
    }
);

export default ReliabilityHistory;
