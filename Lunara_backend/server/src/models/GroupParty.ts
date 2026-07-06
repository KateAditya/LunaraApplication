import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum GroupPartyStatus {
    PENDING = 'pending',
    CONFIRMED = 'confirmed',
    CANCELLED = 'cancelled',
}

export enum GroupPartyPaymentStatus {
    PENDING = 'pending',
    PAID = 'paid',
    FAILED = 'failed',
}

export interface GroupPartyAttributes {
    id: string;
    userId: string;
    venueId: string;
    numberOfFriends: number;
    tableBookingCharge: number;
    discountAmount: number;
    totalAmount: number;
    status: GroupPartyStatus;
    paymentStatus: GroupPartyPaymentStatus;
    paymentId?: string;
    partyDate: Date;
<<<<<<< HEAD
=======
    mobileNumber: string;
    optionalMobileNumber?: string;
>>>>>>> origin/main
    createdAt?: Date;
    updatedAt?: Date;
}

export interface GroupPartyCreationAttributes
    extends Optional<
        GroupPartyAttributes,
<<<<<<< HEAD
        'id' | 'status' | 'paymentStatus' | 'paymentId' | 'createdAt' | 'updatedAt'
=======
        'id' | 'status' | 'paymentStatus' | 'paymentId' | 'createdAt' | 'updatedAt' | 'optionalMobileNumber'
>>>>>>> origin/main
    > {}

class GroupParty
    extends Model<GroupPartyAttributes, GroupPartyCreationAttributes>
    implements GroupPartyAttributes {
    public id!: string;
    public userId!: string;
    public venueId!: string;
    public numberOfFriends!: number;
    public tableBookingCharge!: number;
    public discountAmount!: number;
    public totalAmount!: number;
    public status!: GroupPartyStatus;
    public paymentStatus!: GroupPartyPaymentStatus;
    public paymentId?: string;
    public partyDate!: Date;
<<<<<<< HEAD
=======
    public mobileNumber!: string;
    public optionalMobileNumber?: string;
>>>>>>> origin/main
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

GroupParty.init(
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
            onDelete: 'CASCADE',
        },
        venueId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'venue_id',
            references: { model: 'venues', key: 'id' },
            onDelete: 'CASCADE',
        },
        numberOfFriends: {
            type: DataTypes.INTEGER,
            allowNull: false,
            field: 'number_of_friends',
            validate: {
                min: 1,
                max: 20,
            },
        },
        tableBookingCharge: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            field: 'table_booking_charge',
        },
        discountAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            field: 'discount_amount',
        },
        totalAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            field: 'total_amount',
        },
        status: {
            type: DataTypes.ENUM(...Object.values(GroupPartyStatus)),
            allowNull: false,
            defaultValue: GroupPartyStatus.PENDING,
        },
        paymentStatus: {
            type: DataTypes.ENUM(...Object.values(GroupPartyPaymentStatus)),
            allowNull: false,
            defaultValue: GroupPartyPaymentStatus.PENDING,
            field: 'payment_status',
        },
        paymentId: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'payment_id',
        },
        partyDate: {
            type: DataTypes.DATEONLY,
            allowNull: false,
            field: 'party_date',
        },
<<<<<<< HEAD
=======
        mobileNumber: {
            type: DataTypes.STRING,
            allowNull: false,
            field: 'mobile_number',
        },
        optionalMobileNumber: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'optional_mobile_number',
        },
>>>>>>> origin/main
    },
    {
        sequelize,
        tableName: 'group_parties',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['venue_id'] },
            { fields: ['status'] },
            { fields: ['payment_status'] },
            { fields: ['party_date'] },
        ],
    }
);

export default GroupParty;
