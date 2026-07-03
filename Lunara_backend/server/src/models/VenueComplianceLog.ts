import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum ComplianceEventType {
    TERMS_ACCEPTED = 'terms_accepted',
    CONFIRMATION_EMAIL_SENT = 'confirmation_email_sent',
    OWNER_CONFIRMED = 'owner_confirmed',
    VENUE_LIVE = 'venue_live',
    STATUS_CHANGED = 'status_changed',
}

export interface VenueComplianceLogAttributes {
    id: string;
    venueId: string;
    eventType: ComplianceEventType;
    actorEmail?: string;
    ipAddress?: string;
    metadata?: Record<string, any>;
    createdAt?: Date;
}

export interface VenueComplianceLogCreationAttributes
    extends Optional<VenueComplianceLogAttributes, 'id' | 'actorEmail' | 'ipAddress' | 'metadata' | 'createdAt'> {}

class VenueComplianceLog
    extends Model<VenueComplianceLogAttributes, VenueComplianceLogCreationAttributes>
    implements VenueComplianceLogAttributes {
    public id!: string;
    public venueId!: string;
    public eventType!: ComplianceEventType;
    public actorEmail?: string;
    public ipAddress?: string;
    public metadata?: Record<string, any>;
    public readonly createdAt!: Date;
}

VenueComplianceLog.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        venueId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'venue_id',
            references: { model: 'venues', key: 'id' },
            onDelete: 'CASCADE',
        },
        eventType: {
            // VARCHAR avoids ALTER TYPE migrations when adding new event kinds
            type: DataTypes.STRING(50),
            allowNull: false,
            field: 'event_type',
            validate: {
                isIn: [Object.values(ComplianceEventType)],
            },
        },
        actorEmail: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'actor_email',
        },
        ipAddress: {
            type: DataTypes.STRING(45), // supports IPv6
            allowNull: true,
            field: 'ip_address',
        },
        metadata: {
            type: DataTypes.JSONB,
            allowNull: true,
        },
    },
    {
        sequelize,
        tableName: 'venue_compliance_logs',
        underscored: true,
        // Only createdAt — these records are immutable audit entries
        timestamps: true,
        updatedAt: false,
        indexes: [
            { fields: ['venue_id'] },
            { fields: ['event_type'] },
            { fields: ['venue_id', 'event_type'] },
        ],
    }
);

export default VenueComplianceLog;
