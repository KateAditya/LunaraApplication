import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum TablePackageName {
    SILVER   = 'silver',
    GOLD     = 'gold',
    PLATINUM = 'platinum',
}

export interface BookingTablePackageAttributes {
    id: string;
    venueId: string;
    name: TablePackageName;
    label: string;
    description: string;
    price: number;
    maxGuests: number;
    bottlesIncluded: number;
    isActive: boolean;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface BookingTablePackageCreationAttributes
    extends Optional<
        BookingTablePackageAttributes,
        'id' | 'bottlesIncluded' | 'isActive' | 'createdAt' | 'updatedAt'
    > {}

class BookingTablePackage
    extends Model<BookingTablePackageAttributes, BookingTablePackageCreationAttributes>
    implements BookingTablePackageAttributes {
    public id!: string;
    public venueId!: string;
    public name!: TablePackageName;
    public label!: string;
    public description!: string;
    public price!: number;
    public maxGuests!: number;
    public bottlesIncluded!: number;
    public isActive!: boolean;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

BookingTablePackage.init(
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
        },
        name: {
            type: DataTypes.ENUM(...Object.values(TablePackageName)),
            allowNull: false,
        },
        label: {
            type: DataTypes.STRING(100),
            allowNull: false,
        },
        description: {
            type: DataTypes.STRING(200),
            allowNull: false,
        },
        price: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
        },
        maxGuests: {
            type: DataTypes.INTEGER,
            allowNull: false,
            field: 'max_guests',
        },
        bottlesIncluded: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'bottles_included',
        },
        isActive: {
            type: DataTypes.BOOLEAN,
            defaultValue: true,
            field: 'is_active',
        },
    },
    {
        sequelize,
        tableName: 'booking_table_packages',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['venue_id'] },
            { fields: ['venue_id', 'name'], unique: true },
        ],
    }
);

export default BookingTablePackage;
