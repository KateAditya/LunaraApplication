import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum MessageType {
    TEXT       = 'text',
    IMAGE      = 'image',
    STICKER    = 'sticker',
    INVITATION = 'invitation',  // Plan/Booking invitation card
    ICEBREAKER = 'icebreaker',  // Pre-defined starter message
    VOICE      = 'voice',       // Voice audio note message
}

export enum MessageStatus {
    SENT      = 'sent',
    DELIVERED = 'delivered',
    READ      = 'read',
}

export enum InvitationStatus {
    PENDING  = 'pending',
    ACCEPTED = 'accepted',
    DECLINED = 'declined',
}

export interface MessageAttributes {
    id: string;
    conversationId: string;
    senderId: string;
    clientMessageId?: string;     // Idempotency key from client
    type: MessageType;
    content?: string;             // Text content / icebreaker text
    mediaUrl?: string;            // For image / sticker / voice audio URL
    mediaMimeType?: string;       // e.g. 'image/jpeg', 'audio/mp4', 'audio/aac'
    duration?: number;            // Voice recording duration in seconds
    fileSize?: number;            // Media file size in bytes
    waveformData?: string;        // Visual audio waveform amplitude JSON array
    replyToMessageId?: string;    // Parent message ID for reply thread
    // Invitation-specific fields
    invitationRef?: string;       // planId or bookingId
    invitationRefType?: string;   // 'plan' | 'booking'
    invitationTime?: string;      // Human-readable time e.g. "Tonight, 10:30 PM"
    invitationStatus?: InvitationStatus;
    // Delivery tracking
    status: MessageStatus;
    readAt?: Date;
    deletedAt?: Date;             // Soft delete
    createdAt?: Date;
    updatedAt?: Date;
}

export interface MessageCreationAttributes
    extends Optional<
        MessageAttributes,
        | 'id'
        | 'clientMessageId'
        | 'content'
        | 'mediaUrl'
        | 'mediaMimeType'
        | 'duration'
        | 'fileSize'
        | 'waveformData'
        | 'replyToMessageId'
        | 'invitationRef'
        | 'invitationRefType'
        | 'invitationTime'
        | 'invitationStatus'
        | 'status'
        | 'readAt'
        | 'deletedAt'
        | 'createdAt'
        | 'updatedAt'
    > {}

class Message
    extends Model<MessageAttributes, MessageCreationAttributes>
    implements MessageAttributes {
    public id!: string;
    public conversationId!: string;
    public senderId!: string;
    public clientMessageId?: string;
    public type!: MessageType;
    public content?: string;
    public mediaUrl?: string;
    public mediaMimeType?: string;
    public duration?: number;
    public fileSize?: number;
    public waveformData?: string;
    public replyToMessageId?: string;
    public invitationRef?: string;
    public invitationRefType?: string;
    public invitationTime?: string;
    public invitationStatus?: InvitationStatus;
    public status!: MessageStatus;
    public readAt?: Date;
    public deletedAt?: Date;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    public isInvitation(): boolean {
        return this.type === MessageType.INVITATION;
    }

    /** Safe display preview for the chat list */
    public getPreview(): string {
        switch (this.type) {
            case MessageType.TEXT:       return this.content?.slice(0, 80) ?? '';
            case MessageType.IMAGE:      return '📷 Photo';
            case MessageType.STICKER:    return '😄 Sticker';
            case MessageType.VOICE:      return this.duration ? `🎙 Voice message (${Math.floor(this.duration / 60)}:${(this.duration % 60).toString().padStart(2, '0')})` : '🎙 Voice message';
            case MessageType.INVITATION: return `📅 Invitation · ${this.invitationTime ?? ''}`;
            case MessageType.ICEBREAKER: return `⚡ ${this.content?.slice(0, 60) ?? ''}`;
            default:                     return '';
        }
    }
}

Message.init(
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
        senderId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'sender_id',
            references: { model: 'users', key: 'id' },
        },
        clientMessageId: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'client_message_id',
        },
        type: {
            type: DataTypes.ENUM(...Object.values(MessageType)),
            allowNull: false,
            defaultValue: MessageType.TEXT,
        },
        content: {
            type: DataTypes.TEXT,
            allowNull: true,
        },
        mediaUrl: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'media_url',
        },
        mediaMimeType: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'media_mime_type',
        },
        duration: {
            type: DataTypes.INTEGER,
            allowNull: true,
            field: 'duration',
        },
        fileSize: {
            type: DataTypes.INTEGER,
            allowNull: true,
            field: 'file_size',
        },
        waveformData: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'waveform_data',
        },
        replyToMessageId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'reply_to_message_id',
        },
        invitationRef: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'invitation_ref',
        },
        invitationRefType: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'invitation_ref_type',
        },
        invitationTime: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'invitation_time',
        },
        invitationStatus: {
            type: DataTypes.ENUM(...Object.values(InvitationStatus)),
            allowNull: true,
            field: 'invitation_status',
        },
        status: {
            type: DataTypes.ENUM(...Object.values(MessageStatus)),
            defaultValue: MessageStatus.SENT,
        },
        readAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'read_at',
        },
        deletedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'deleted_at',
        },
    },
    {
        sequelize,
        tableName: 'messages',
        underscored: true,
        timestamps: true,
        paranoid: false, // using manual soft-delete via deletedAt field
        indexes: [
            { fields: ['conversation_id'] },
            { fields: ['sender_id'] },
            { fields: ['client_message_id'] },
            { fields: ['created_at'] },
            { fields: ['type'] },
        ],
    }
);

export default Message;
