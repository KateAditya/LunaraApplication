import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface NotificationJobAttributes {
    id: string;
    userId: string;
    sendAt: Date;
    title: string;
    body: string;
    status: 'pending' | 'sent' | 'failed';
    createdAt?: Date;
    updatedAt?: Date;
}

export interface NotificationJobCreationAttributes
    extends Optional<NotificationJobAttributes, 'id' | 'status' | 'createdAt' | 'updatedAt'> {}

class NotificationJob
    extends Model<NotificationJobAttributes, NotificationJobCreationAttributes>
    implements NotificationJobAttributes
{
    public id!: string;
    public userId!: string;
    public sendAt!: Date;
    public title!: string;
    public body!: string;
    public status!: 'pending' | 'sent' | 'failed';
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

NotificationJob.init(
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
        sendAt: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'send_at',
        },
        title: {
            type: DataTypes.STRING,
            allowNull: false,
        },
        body: {
            type: DataTypes.STRING,
            allowNull: false,
        },
        status: {
            type: DataTypes.ENUM('pending', 'sent', 'failed'),
            allowNull: false,
            defaultValue: 'pending',
        },
    },
    {
        sequelize,
        modelName: 'NotificationJob',
        tableName: 'notification_jobs',
        indexes: [
            { fields: ['status', 'send_at'] },
        ],
    }
);

export default NotificationJob;
