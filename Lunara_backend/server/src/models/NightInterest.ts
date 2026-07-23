import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum NightInterestStatus {
    INTERESTED = 'interested',
    REMOVED = 'removed',
}

export interface NightInterestAttributes {
    id: string;
    userId: string;
    venueId: string;
    eventDate: Date;
    eventTime?: string;
    status: NightInterestStatus;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface NightInterestCreationAttributes
    extends Optional<
        NightInterestAttributes,
        'id' | 'eventTime' | 'status' | 'createdAt' | 'updatedAt'
    > {}

class NightInterest
    extends Model<NightInterestAttributes, NightInterestCreationAttributes>
    implements NightInterestAttributes {
    public id!: string;
    public userId!: string;
    public venueId!: string;
    public eventDate!: Date;
    public eventTime?: string;
    public status!: NightInterestStatus;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

NightInterest.init(
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
            type: DataTypes.ENUM(...Object.values(NightInterestStatus)),
            defaultValue: NightInterestStatus.INTERESTED,
        },
    },
    {
        sequelize,
        tableName: 'night_interests',
        underscored: true,
        timestamps: true,
        indexes: [
            {
                unique: true,
                fields: ['user_id', 'venue_id', 'event_date'],
                name: 'unique_user_night_interest',
            },
            {
                fields: ['venue_id', 'event_date', 'status'],
            },
        ],
    }
);

export default NightInterest;
