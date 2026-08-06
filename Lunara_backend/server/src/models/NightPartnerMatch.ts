import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum NightPartnerMatchStatus {
    MATCHED = 'MATCHED',
    PAYMENT_PENDING = 'PAYMENT_PENDING',
    PAYMENT_FAILED = 'PAYMENT_FAILED',
    CONFIRMED = 'CONFIRMED',
    CANCELLED = 'CANCELLED',
    EXPIRED = 'EXPIRED',
}

export interface NightPartnerMatchAttributes {
    id: string;
    hostId: string;
    partnerId: string;
    venueId: string;
    eventDate: Date;
    eventTime?: string;
    requestId: string;
    status: NightPartnerMatchStatus;
    bookingId?: string;
    conversationId?: string;
    totalAmount?: number;
    razorpayOrderId?: string;
    maxPartners: number;
    paymentExpiresAt?: Date;
    reminder2hSent?: boolean;
    reminder1hSent?: boolean;
    reminder30mSent?: boolean;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface NightPartnerMatchCreationAttributes
    extends Optional<
        NightPartnerMatchAttributes,
        | 'id'
        | 'eventTime'
        | 'status'
        | 'bookingId'
        | 'conversationId'
        | 'totalAmount'
        | 'razorpayOrderId'
        | 'maxPartners'
        | 'paymentExpiresAt'
        | 'reminder2hSent'
        | 'reminder1hSent'
        | 'reminder30mSent'
        | 'createdAt'
        | 'updatedAt'
    > {}

class NightPartnerMatch
    extends Model<NightPartnerMatchAttributes, NightPartnerMatchCreationAttributes>
    implements NightPartnerMatchAttributes {
    public id!: string;
    public hostId!: string;
    public partnerId!: string;
    public venueId!: string;
    public eventDate!: Date;
    public eventTime?: string;
    public requestId!: string;
    public status!: NightPartnerMatchStatus;
    public bookingId?: string;
    public conversationId?: string;
    public totalAmount?: number;
    public razorpayOrderId?: string;
    public maxPartners!: number;
    public paymentExpiresAt?: Date;
    public reminder2hSent!: boolean;
    public reminder1hSent!: boolean;
    public reminder30mSent!: boolean;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

NightPartnerMatch.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        hostId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'host_id',
            references: { model: 'users', key: 'id' },
        },
        partnerId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'partner_id',
            references: { model: 'users', key: 'id' },
        },
        venueId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'venue_id',
            references: { model: 'venues', key: 'id' },
        },
        eventDate: {
            type: DataTypes.DATEONLY,
            allowNull: false,
            field: 'event_date',
        },
        eventTime: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'event_time',
        },
        requestId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'request_id',
            references: { model: 'night_partner_requests', key: 'id' },
        },
        status: {
            type: DataTypes.ENUM(...Object.values(NightPartnerMatchStatus)),
            defaultValue: NightPartnerMatchStatus.MATCHED,
        },
        bookingId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'booking_id',
            references: { model: 'bookings', key: 'id' },
        },
        conversationId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'conversation_id',
            references: { model: 'conversations', key: 'id' },
        },
        totalAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            field: 'total_amount',
        },
        razorpayOrderId: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'razorpay_order_id',
        },
        maxPartners: {
            type: DataTypes.INTEGER,
            defaultValue: 1,
            field: 'max_partners',
        },
        paymentExpiresAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'payment_expires_at',
        },
        reminder2hSent: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'reminder_2h_sent',
        },
        reminder1hSent: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'reminder_1h_sent',
        },
        reminder30mSent: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'reminder_30m_sent',
        },
    },
    {
        sequelize,
        tableName: 'night_partner_matches',
        underscored: true,
        timestamps: true,
        indexes: [
            {
                unique: true,
                fields: ['host_id', 'venue_id', 'event_date'],
                name: 'unique_host_night_match',
            },
            {
                fields: ['partner_id', 'status'],
            },
        ],
    }
);

export default NightPartnerMatch;
