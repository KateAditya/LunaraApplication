import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface SocialLink {
    platform: string;
    url: string;
}

export interface AdAttributes {
    id: string;
    type: 'Ads' | 'Party';
    venueId: string;
    city: string;
    area: string;
    title?: string;
    imagePath: string;
    fromDate: Date;
    toDate: Date;
    isActive: boolean;
    socialLinks: SocialLink[];
    aboutEvent?: string;
    eventDate?: Date;
    entryPrice?: number;
    seatLimit?: number;
    isUnlimited?: boolean;
    filledSeats?: number;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface AdCreationAttributes extends Optional<AdAttributes, 'id' | 'isActive' | 'socialLinks' | 'title' | 'aboutEvent' | 'createdAt' | 'updatedAt'> {}

class Ad extends Model<AdAttributes, AdCreationAttributes> implements AdAttributes {
    public id!: string;
    public type!: 'Ads' | 'Party';
    public venueId!: string;
    public city!: string;
    public area!: string;
    public title?: string;
    public imagePath!: string;
    public fromDate!: Date;
    public toDate!: Date;
    public isActive!: boolean;
    public socialLinks!: SocialLink[];
    public aboutEvent?: string;

    public eventDate?: Date;
    public entryPrice?: number;
    public seatLimit?: number;
    public isUnlimited!: boolean;
    public filledSeats!: number;

    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

Ad.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        type: {
            type: DataTypes.ENUM('Ads', 'Party'),
            allowNull: false,
            defaultValue: 'Ads',
        },
        venueId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'venue_id',
        },
        city: {
            type: DataTypes.STRING,
            allowNull: true,
        },
        area: {
            type: DataTypes.STRING,
            allowNull: true,
        },
        title: {
            type: DataTypes.STRING,
            allowNull: true,
        },
        imagePath: {
            type: DataTypes.STRING,
            allowNull: false,
            field: 'image_path',
        },
        fromDate: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'from_date',
        },
        toDate: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'to_date',
        },
        isActive: {
            type: DataTypes.BOOLEAN,
            defaultValue: true,
            field: 'is_active',
        },
        socialLinks: {
            type: DataTypes.JSONB,
            defaultValue: [],
            field: 'social_links',
        },
        aboutEvent: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'about_event',
        },
        eventDate: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'event_date',
        },
        entryPrice: {
            type: DataTypes.INTEGER,
            allowNull: true,
            field: 'entry_price',
        },
        seatLimit: {
            type: DataTypes.INTEGER,
            allowNull: true,
            field: 'seat_limit',
        },
        isUnlimited: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_unlimited',
        },
        filledSeats: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'filled_seats',
        },
    },
    {
        sequelize,
        tableName: 'ads',
        timestamps: true,
        indexes: [
            {
                fields: ['city', 'area', 'type'],
            },
            {
                fields: ['is_active', 'from_date', 'to_date'],
            },
            {
                fields: ['venue_id'],
            }
        ],
    }
);

export default Ad;
