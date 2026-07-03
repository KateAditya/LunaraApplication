import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum ChatSubscriptionStatus {
    ACTIVE   = 'active',
    EXPIRED  = 'expired',
}

export enum ChatSubscriptionType {
    FREE      = 'free',       // initial free days on match
    PAID      = 'paid',       // paid extension by self
    PAY_REQ   = 'pay_req',    // paid extension triggered by other user's request
}

export interface ChatSubscriptionAttributes {
    id: string;
    conversationId: string;
    paidById: string;            // user who paid (or was granted free access)
    amount: number;              // 0 for free, actual amount for paid
    daysGranted: number;
    validUntil: Date;
    status: ChatSubscriptionStatus;
    subscriptionType: ChatSubscriptionType;
    requestedById?: string;      // who requested the other to pay (if applicable)
    createdAt?: Date;
    updatedAt?: Date;
}

export interface ChatSubscriptionCreationAttributes
    extends Optional<
        ChatSubscriptionAttributes,
        'id' | 'status' | 'subscriptionType' | 'requestedById' | 'createdAt' | 'updatedAt'
    > {}

class ChatSubscription
    extends Model<ChatSubscriptionAttributes, ChatSubscriptionCreationAttributes>
    implements ChatSubscriptionAttributes {
    public id!: string;
    public conversationId!: string;
    public paidById!: string;
    public amount!: number;
    public daysGranted!: number;
    public validUntil!: Date;
    public status!: ChatSubscriptionStatus;
    public subscriptionType!: ChatSubscriptionType;
    public requestedById?: string;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    public isActive(): boolean {
        return this.status === ChatSubscriptionStatus.ACTIVE && new Date() < this.validUntil;
    }

    public daysRemaining(): number {
        const diff = this.validUntil.getTime() - Date.now();
        return Math.max(0, Math.ceil(diff / (1000 * 60 * 60 * 24)));
    }
}

ChatSubscription.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        conversationId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'conversation_id',
            references: { model: 'conversations', key: 'id' },
        },
        paidById: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'paid_by_id',
            references: { model: 'users', key: 'id' },
        },
        amount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0,
        },
        daysGranted: {
            type: DataTypes.INTEGER,
            allowNull: false,
            field: 'days_granted',
        },
        validUntil: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'valid_until',
        },
        status: {
            type: DataTypes.ENUM(...Object.values(ChatSubscriptionStatus)),
            defaultValue: ChatSubscriptionStatus.ACTIVE,
        },
        subscriptionType: {
            type: DataTypes.ENUM(...Object.values(ChatSubscriptionType)),
            defaultValue: ChatSubscriptionType.FREE,
            field: 'subscription_type',
        },
        requestedById: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'requested_by_id',
            references: { model: 'users', key: 'id' },
        },
    },
    {
        sequelize,
        tableName: 'chat_subscriptions',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['conversation_id'] },
            { fields: ['paid_by_id'] },
            { fields: ['valid_until'] },
            { fields: ['status'] },
        ],
    }
);

export default ChatSubscription;
