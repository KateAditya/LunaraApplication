import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';
import User from './User';
import Venue from './Venue';

export enum TicketStatus {
    GENERATING = 'GENERATING',
    ISSUED = 'ISSUED',
    ACTIVE = 'ACTIVE',
    USED = 'USED',
    EXPIRED = 'EXPIRED',
    CANCELLED = 'CANCELLED',
    REFUNDED = 'REFUNDED',
    VOID = 'VOID',
}

export enum StorageCleanupStatus {
    NOT_REQUIRED = 'NOT_REQUIRED',
    PENDING = 'PENDING',
    PROCESSING = 'PROCESSING',
    DELETED = 'DELETED',
    FAILED = 'FAILED',
}

export interface TicketAttributes {
    id: string;
    ticketId: string;
    bookingId: string;
    bookingType: 'solo' | 'party_plan' | 'group_party' | 'strangers_meet';
    userId: string;
    venueId?: string | null;
    ticketStatus: TicketStatus;
    eventStartAt: Date;
    eventEndAt: Date;
    issuedAt: Date;
    expiresAt: Date;
    storageDeletionAt: Date;
    usedAt?: Date | null;
    cancelledAt?: Date | null;
    refundedAt?: Date | null;
    storageProvider: string;
    storageKey?: string | null;
    pdfUrl?: string | null;
    pdfVersion: number;
    qrToken: string;
    verificationToken: string;
    shareToken?: string | null;
    shareTokenExpiresAt?: Date | null;
    storageCleanupStatus: StorageCleanupStatus;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface TicketCreationAttributes
    extends Optional<
        TicketAttributes,
        | 'id'
        | 'venueId'
        | 'ticketStatus'
        | 'issuedAt'
        | 'usedAt'
        | 'cancelledAt'
        | 'refundedAt'
        | 'storageProvider'
        | 'storageKey'
        | 'pdfUrl'
        | 'pdfVersion'
        | 'shareToken'
        | 'shareTokenExpiresAt'
        | 'storageCleanupStatus'
        | 'createdAt'
        | 'updatedAt'
    > {}

class Ticket
    extends Model<TicketAttributes, TicketCreationAttributes>
    implements TicketAttributes {
    public id!: string;
    public ticketId!: string;
    public bookingId!: string;
    public bookingType!: 'solo' | 'party_plan' | 'group_party' | 'strangers_meet';
    public userId!: string;
    public venueId?: string | null;
    public ticketStatus!: TicketStatus;
    public eventStartAt!: Date;
    public eventEndAt!: Date;
    public issuedAt!: Date;
    public expiresAt!: Date;
    public storageDeletionAt!: Date;
    public usedAt?: Date | null;
    public cancelledAt?: Date | null;
    public refundedAt?: Date | null;
    public storageProvider!: string;
    public storageKey?: string | null;
    public pdfUrl?: string | null;
    public pdfVersion!: number;
    public qrToken!: string;
    public verificationToken!: string;
    public shareToken?: string | null;
    public shareTokenExpiresAt?: Date | null;
    public storageCleanupStatus!: StorageCleanupStatus;
    public venue?: Venue;
    public user?: User;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

Ticket.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        ticketId: {
            type: DataTypes.STRING(100),
            allowNull: false,
            unique: true,
            field: 'ticket_id',
        },
        bookingId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'booking_id',
        },
        bookingType: {
            type: DataTypes.STRING(50),
            allowNull: false,
            field: 'booking_type',
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
        venueId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'venue_id',
            references: {
                model: 'venues',
                key: 'id',
            },
            onDelete: 'SET NULL',
        },
        ticketStatus: {
            type: DataTypes.STRING(50),
            allowNull: false,
            defaultValue: TicketStatus.ACTIVE,
            field: 'ticket_status',
        },
        eventStartAt: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'event_start_at',
        },
        eventEndAt: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'event_end_at',
        },
        issuedAt: {
            type: DataTypes.DATE,
            allowNull: false,
            defaultValue: DataTypes.NOW,
            field: 'issued_at',
        },
        expiresAt: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'expires_at',
        },
        storageDeletionAt: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'storage_deletion_at',
        },
        usedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'used_at',
        },
        cancelledAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'cancelled_at',
        },
        refundedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'refunded_at',
        },
        storageProvider: {
            type: DataTypes.STRING(50),
            allowNull: false,
            defaultValue: 'local',
            field: 'storage_provider',
        },
        storageKey: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'storage_key',
        },
        pdfUrl: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'pdf_url',
        },
        pdfVersion: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 1,
            field: 'pdf_version',
        },
        qrToken: {
            type: DataTypes.TEXT,
            allowNull: false,
            field: 'qr_token',
        },
        verificationToken: {
            type: DataTypes.STRING(255),
            allowNull: false,
            field: 'verification_token',
        },
        shareToken: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'share_token',
        },
        shareTokenExpiresAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'share_token_expires_at',
        },
        storageCleanupStatus: {
            type: DataTypes.STRING(50),
            allowNull: false,
            defaultValue: StorageCleanupStatus.PENDING,
            field: 'storage_cleanup_status',
        },
        createdAt: {
            type: DataTypes.DATE,
            allowNull: false,
            defaultValue: DataTypes.NOW,
            field: 'created_at',
        },
        updatedAt: {
            type: DataTypes.DATE,
            allowNull: false,
            defaultValue: DataTypes.NOW,
            field: 'updated_at',
        },
    },
    {
        sequelize,
        tableName: 'tickets',
        timestamps: true,
        underscored: true,
        indexes: [
            { fields: ['ticket_id'], unique: true },
            { fields: ['booking_id'] },
            { fields: ['user_id'] },
            { fields: ['ticket_status'] },
            { fields: ['expires_at'] },
            { fields: ['storage_deletion_at', 'storage_cleanup_status'] },
            { fields: ['share_token'] },
        ],
    }
);

export default Ticket;
