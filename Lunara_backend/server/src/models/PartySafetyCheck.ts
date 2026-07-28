import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum SafetyStatus {
    NO_RESPONSE = 'NO_RESPONSE',
    SAFE = 'SAFE',
    EXTENDED = 'EXTENDED',
    NEED_HELP = 'NEED_HELP',
}

export interface PartySafetyCheckAttributes {
    id: string;
    planId: string;
    planType: string; // 'party_plan' | 'stranger_meet' | 'venue_booking' | 'group_party'
    userId: string;
    partnerUserId?: string;
    venueName: string;
    partyDate: Date;
    partyTime?: string;
    safetyStatus: SafetyStatus;
    notes?: string;
    locationLat?: number;
    locationLng?: number;
    alertTriggered: boolean;
    notificationSentAt: Date;
    respondedAt?: Date;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface PartySafetyCheckCreationAttributes
    extends Optional<PartySafetyCheckAttributes, 'id' | 'safetyStatus' | 'alertTriggered' | 'createdAt' | 'updatedAt'> { }

class PartySafetyCheck
    extends Model<PartySafetyCheckAttributes, PartySafetyCheckCreationAttributes>
    implements PartySafetyCheckAttributes {
    public id!: string;
    public planId!: string;
    public planType!: string;
    public userId!: string;
    public partnerUserId?: string;
    public venueName!: string;
    public partyDate!: Date;
    public partyTime?: string;
    public safetyStatus!: SafetyStatus;
    public notes?: string;
    public locationLat?: number;
    public locationLng?: number;
    public alertTriggered!: boolean;
    public notificationSentAt!: Date;
    public respondedAt?: Date;

    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

PartySafetyCheck.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        planId: {
            type: DataTypes.UUID,
            allowNull: false,
        },
        planType: {
            type: DataTypes.STRING(50),
            allowNull: false,
            defaultValue: 'party_plan',
        },
        userId: {
            type: DataTypes.UUID,
            allowNull: false,
        },
        partnerUserId: {
            type: DataTypes.UUID,
            allowNull: true,
        },
        venueName: {
            type: DataTypes.STRING(255),
            allowNull: false,
            defaultValue: 'Venue',
        },
        partyDate: {
            type: DataTypes.DATE,
            allowNull: false,
        },
        partyTime: {
            type: DataTypes.STRING(50),
            allowNull: true,
        },
        safetyStatus: {
            type: DataTypes.ENUM(...Object.values(SafetyStatus)),
            allowNull: false,
            defaultValue: SafetyStatus.NO_RESPONSE,
        },
        notes: {
            type: DataTypes.TEXT,
            allowNull: true,
        },
        locationLat: {
            type: DataTypes.FLOAT,
            allowNull: true,
        },
        locationLng: {
            type: DataTypes.FLOAT,
            allowNull: true,
        },
        alertTriggered: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
        },
        notificationSentAt: {
            type: DataTypes.DATE,
            allowNull: false,
            defaultValue: DataTypes.NOW,
        },
        respondedAt: {
            type: DataTypes.DATE,
            allowNull: true,
        },
    },
    {
        sequelize,
        tableName: 'party_safety_checks',
        timestamps: true,
        underscored: true,
    }
);

export default PartySafetyCheck;
