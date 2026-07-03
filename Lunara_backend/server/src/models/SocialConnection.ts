import { Model, DataTypes, Optional, Op } from 'sequelize';
import sequelize from '../config/database';

// Connection status enum
export enum ConnectionStatus {
    PENDING = 'pending',
    ACCEPTED = 'accepted',
    REJECTED = 'rejected',
    BLOCKED = 'blocked',
}

// SocialConnection attributes
export interface SocialConnectionAttributes {
    id: string;
    requesterId: string;
    receiverId: string;
    status: ConnectionStatus;
    connectedAt?: Date;
    createdAt?: Date;
}

export interface SocialConnectionCreationAttributes
    extends Optional<SocialConnectionAttributes, 'id' | 'status' | 'connectedAt' | 'createdAt'> { }

class SocialConnection
    extends Model<SocialConnectionAttributes, SocialConnectionCreationAttributes>
    implements SocialConnectionAttributes {
    public id!: string;
    public requesterId!: string;
    public receiverId!: string;
    public status!: ConnectionStatus;
    public connectedAt?: Date;
    public readonly createdAt!: Date;

    // Instance methods
    public async accept(): Promise<void> {
        this.status = ConnectionStatus.ACCEPTED;
        this.connectedAt = new Date();
        await this.save();
    }

    public async reject(): Promise<void> {
        this.status = ConnectionStatus.REJECTED;
        await this.save();
    }

    public async block(): Promise<void> {
        this.status = ConnectionStatus.BLOCKED;
        await this.save();
    }

    // Static methods
    public static async areConnected(user1Id: string, user2Id: string): Promise<boolean> {
        const connection = await SocialConnection.findOne({
            where: {
                status: ConnectionStatus.ACCEPTED,
                [Op.or]: [
                    { requesterId: user1Id, receiverId: user2Id },
                    { requesterId: user2Id, receiverId: user1Id },
                ],
            },
        });

        return connection !== null;
    }

    public static async getConnectionStatus(
        user1Id: string,
        user2Id: string
    ): Promise<ConnectionStatus | null> {
        const connection = await SocialConnection.findOne({
            where: {
                [Op.or]: [
                    { requesterId: user1Id, receiverId: user2Id },
                    { requesterId: user2Id, receiverId: user1Id },
                ],
            },
            order: [['created_at', 'DESC']],
        });

        return connection ? connection.status : null;
    }
}

SocialConnection.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        requesterId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'requester_id',
            references: {
                model: 'users',
                key: 'id',
            },
        },
        receiverId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'receiver_id',
            references: {
                model: 'users',
                key: 'id',
            },
        },
        status: {
            type: DataTypes.ENUM(...Object.values(ConnectionStatus)),
            defaultValue: ConnectionStatus.PENDING,
        },
        connectedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'connected_at',
        },
    },
    {
        sequelize,
        tableName: 'social_connections',
        underscored: true,
        timestamps: true,
        updatedAt: false,
        indexes: [
            { fields: ['requester_id'] },
            { fields: ['receiver_id'] },
            { fields: ['status'] },
        ],
    }
);

export default SocialConnection;
