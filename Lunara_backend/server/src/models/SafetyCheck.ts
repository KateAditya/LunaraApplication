import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface SafetyCheckAttributes {
    id: string;
    userId: string;
    partnerId: string;
    feltSafe: boolean;
    prebuiltAnswers?: string;
    opinion?: string;
    adminFeedback?: string;
    status: 'pending' | 'reviewed' | 'resolved';
    createdAt?: Date;
    updatedAt?: Date;
}

export interface SafetyCheckCreationAttributes
    extends Optional<SafetyCheckAttributes, 'id' | 'prebuiltAnswers' | 'opinion' | 'adminFeedback' | 'status' | 'createdAt' | 'updatedAt'> {}

class SafetyCheck
    extends Model<SafetyCheckAttributes, SafetyCheckCreationAttributes>
    implements SafetyCheckAttributes {
    public id!: string;
    public userId!: string;
    public partnerId!: string;
    public feltSafe!: boolean;
    public prebuiltAnswers?: string;
    public opinion?: string;
    public adminFeedback?: string;
    public status!: 'pending' | 'reviewed' | 'resolved';
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

SafetyCheck.init(
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
        partnerId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'partner_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        feltSafe: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            field: 'felt_safe',
        },
        prebuiltAnswers: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'prebuilt_answers',
        },
        opinion: {
            type: DataTypes.TEXT,
            allowNull: true,
        },
        adminFeedback: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'admin_feedback',
        },
        status: {
            type: DataTypes.ENUM('pending', 'reviewed', 'resolved'),
            defaultValue: 'pending',
            allowNull: false,
        },
    },
    {
        sequelize,
        tableName: 'safety_checks',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['partner_id'] },
            { fields: ['status'] },
        ],
    }
);

export default SafetyCheck;
