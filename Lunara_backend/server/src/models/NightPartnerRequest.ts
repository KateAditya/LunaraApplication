import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum NightPartnerRequestStatus {
    PENDING = 'PENDING',
    ACCEPTED = 'ACCEPTED',
    DECLINED = 'DECLINED',
    CANCELLED = 'CANCELLED',
    EXPIRED = 'EXPIRED',
}

export interface NightPartnerRequestAttributes {
    id: string;
    hostId: string;
    partnerId: string;
    venueId: string;
    eventDate: Date;
    eventTime?: string;
    status: NightPartnerRequestStatus;
    expiresAt: Date;
    nightInterestId?: string;
    reminder2hSent?: boolean;
    reminder1hSent?: boolean;
    reminder30mSent?: boolean;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface NightPartnerRequestCreationAttributes
    extends Optional<
        NightPartnerRequestAttributes,
        'id' | 'eventTime' | 'status' | 'nightInterestId' | 'createdAt' | 'updatedAt' | 'reminder2hSent' | 'reminder1hSent' | 'reminder30mSent'
    > {}

class NightPartnerRequest
    extends Model<NightPartnerRequestAttributes, NightPartnerRequestCreationAttributes>
    implements NightPartnerRequestAttributes {
    public id!: string;
    public hostId!: string;
    public partnerId!: string;
    public venueId!: string;
    public eventDate!: Date;
    public eventTime?: string;
    public status!: NightPartnerRequestStatus;
    public expiresAt!: Date;
    public nightInterestId?: string;
    public reminder2hSent!: boolean;
    public reminder1hSent!: boolean;
    public reminder30mSent!: boolean;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

NightPartnerRequest.init(
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
        status: {
            type: DataTypes.ENUM(...Object.values(NightPartnerRequestStatus)),
            defaultValue: NightPartnerRequestStatus.PENDING,
        },
        expiresAt: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'expires_at',
        },
        nightInterestId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'night_interest_id',
            references: { model: 'night_interests', key: 'id' },
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
        tableName: 'night_partner_requests',
        underscored: true,
        timestamps: true,
        indexes: [
            {
                unique: true,
                fields: ['host_id', 'partner_id', 'venue_id', 'event_date'],
                name: 'unique_host_partner_night_request',
            },
            {
                fields: ['host_id', 'status'],
            },
            {
                fields: ['partner_id', 'status'],
            },
        ],
    }
);

export default NightPartnerRequest;
