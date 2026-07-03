import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum MemberPaymentStatus {
    PENDING = 'pending',
    PAID    = 'paid',
}

export interface BookingMemberAttributes {
    id: string;
    groupBookingId: string;
    userId?: string;
    displayName: string;
    shareAmount: number;
    paymentStatus: MemberPaymentStatus;
    paidAt?: Date;
    transactionId?: string;
    isOrganizer: boolean;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface BookingMemberCreationAttributes
    extends Optional<
        BookingMemberAttributes,
        | 'id'
        | 'userId'
        | 'paymentStatus'
        | 'paidAt'
        | 'transactionId'
        | 'isOrganizer'
        | 'createdAt'
        | 'updatedAt'
    > {}

class BookingMember
    extends Model<BookingMemberAttributes, BookingMemberCreationAttributes>
    implements BookingMemberAttributes {
    public id!: string;
    public groupBookingId!: string;
    public userId?: string;
    public displayName!: string;
    public shareAmount!: number;
    public paymentStatus!: MemberPaymentStatus;
    public paidAt?: Date;
    public transactionId?: string;
    public isOrganizer!: boolean;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

BookingMember.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        groupBookingId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'group_booking_id',
            references: { model: 'group_bookings', key: 'id' },
        },
        userId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'user_id',
        },
        displayName: {
            type: DataTypes.STRING(100),
            allowNull: false,
            field: 'display_name',
        },
        shareAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            field: 'share_amount',
        },
        paymentStatus: {
            type: DataTypes.ENUM(...Object.values(MemberPaymentStatus)),
            defaultValue: MemberPaymentStatus.PENDING,
            field: 'payment_status',
        },
        paidAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'paid_at',
        },
        transactionId: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'transaction_id',
        },
        isOrganizer: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_organizer',
        },
    },
    {
        sequelize,
        tableName: 'booking_members',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['group_booking_id'] },
            { fields: ['user_id'] },
        ],
    }
);

export default BookingMember;
