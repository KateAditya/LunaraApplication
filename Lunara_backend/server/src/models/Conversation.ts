import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum ConversationStatus {
    ACTIVE   = 'active',
    ARCHIVED = 'archived',
    BLOCKED  = 'blocked',
}

export interface ConversationAttributes {
    id: string;
    participantOne: string;   // userId of first participant
    participantTwo: string;   // userId of second participant
    lastMessageId?: string;
    lastMessageAt?: Date;
    lastMessagePreview?: string;
    unreadOne: number;        // unread count for participantOne
    unreadTwo: number;        // unread count for participantTwo
    status: ConversationStatus;
    clearedAtOne?: Date;      // Timestamp when participantOne cleared or deleted the chat
    clearedAtTwo?: Date;      // Timestamp when participantTwo cleared or deleted the chat
    deletedByOne?: boolean;   // Whether participantOne has deleted the conversation from their chat list
    deletedByTwo?: boolean;   // Whether participantTwo has deleted the conversation from their chat list
    // Optional context linking (plan/booking that started the chat)
    contextType?: string;     // 'plan' | 'booking' | null
    contextId?: string;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface ConversationCreationAttributes
    extends Optional<
        ConversationAttributes,
        | 'id'
        | 'lastMessageId'
        | 'lastMessageAt'
        | 'lastMessagePreview'
        | 'unreadOne'
        | 'unreadTwo'
        | 'status'
        | 'clearedAtOne'
        | 'clearedAtTwo'
        | 'deletedByOne'
        | 'deletedByTwo'
        | 'contextType'
        | 'contextId'
        | 'createdAt'
        | 'updatedAt'
    > {}

class Conversation
    extends Model<ConversationAttributes, ConversationCreationAttributes>
    implements ConversationAttributes {
    public id!: string;
    public participantOne!: string;
    public participantTwo!: string;
    public lastMessageId?: string;
    public lastMessageAt?: Date;
    public lastMessagePreview?: string;
    public unreadOne!: number;
    public unreadTwo!: number;
    public status!: ConversationStatus;
    public clearedAtOne?: Date;
    public clearedAtTwo?: Date;
    public deletedByOne?: boolean;
    public deletedByTwo?: boolean;
    public contextType?: string;
    public contextId?: string;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    /** Returns the unread count for a given userId */
    public getUnreadFor(userId: string): number {
        if (!userId) return 0;
        const target = userId.toLowerCase();
        if (target === this.participantOne.toLowerCase()) return this.unreadOne;
        if (target === this.participantTwo.toLowerCase()) return this.unreadTwo;
        return 0;
    }

    /** Returns the other participant's userId */
    public getOtherParticipant(userId: string): string {
        if (!userId) return this.participantTwo;
        const target = userId.toLowerCase();
        return target === this.participantOne.toLowerCase() ? this.participantTwo : this.participantOne;
    }
}

Conversation.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        participantOne: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'participant_one',
            references: { model: 'users', key: 'id' },
        },
        participantTwo: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'participant_two',
            references: { model: 'users', key: 'id' },
        },
        lastMessageId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'last_message_id',
        },
        lastMessageAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'last_message_at',
        },
        lastMessagePreview: {
            type: DataTypes.STRING(200),
            allowNull: true,
            field: 'last_message_preview',
        },
        unreadOne: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'unread_one',
        },
        unreadTwo: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'unread_two',
        },
        status: {
            type: DataTypes.ENUM(...Object.values(ConversationStatus)),
            defaultValue: ConversationStatus.ACTIVE,
        },
        clearedAtOne: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'cleared_at_one',
        },
        clearedAtTwo: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'cleared_at_two',
        },
        deletedByOne: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'deleted_by_one',
        },
        deletedByTwo: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'deleted_by_two',
        },
        contextType: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'context_type',
        },
        contextId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'context_id',
        },
    },
    {
        sequelize,
        tableName: 'conversations',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['participant_one'] },
            { fields: ['participant_two'] },
            { fields: ['last_message_at'] },
            // Unique pair — only one conversation per two users
            { unique: true, fields: ['participant_one', 'participant_two'] },
        ],
    }
);

export default Conversation;
