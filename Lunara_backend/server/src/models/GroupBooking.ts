import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

// Split type enum
export enum SplitType {
    EQUAL = 'equal',
    CUSTOM = 'custom',
    PERCENTAGE = 'percentage',
}

// GroupBooking attributes
export interface GroupBookingAttributes {
    id: string;
    bookingId: string;
    organizerId: string;
    groupName?: string;
    splitPaymentEnabled: boolean;
    splitType: SplitType;
    totalMembers: number;
    confirmedMembers: number;
    paidMembers: number;
    invitationCode: string;
    invitationExpiresAt?: Date;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface GroupBookingCreationAttributes
    extends Optional<
        GroupBookingAttributes,
        | 'id'
        | 'groupName'
        | 'splitPaymentEnabled'
        | 'splitType'
        | 'confirmedMembers'
        | 'paidMembers'
        | 'invitationCode'
        | 'invitationExpiresAt'
        | 'createdAt'
        | 'updatedAt'
    > { }

class GroupBooking
    extends Model<GroupBookingAttributes, GroupBookingCreationAttributes>
    implements GroupBookingAttributes {
    public id!: string;
    public bookingId!: string;
    public organizerId!: string;
    public groupName?: string;
    public splitPaymentEnabled!: boolean;
    public splitType!: SplitType;
    public totalMembers!: number;
    public confirmedMembers!: number;
    public paidMembers!: number;
    public invitationCode!: string;
    public invitationExpiresAt?: Date;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    // Instance methods
    public isFullyPaid(): boolean {
        return this.paidMembers === this.totalMembers;
    }

    public isFullyConfirmed(): boolean {
        return this.confirmedMembers === this.totalMembers;
    }

    public isInvitationValid(): boolean {
        if (!this.invitationExpiresAt) return true;
        return new Date() < this.invitationExpiresAt;
    }

    public getPaymentProgress(): number {
        return (this.paidMembers / this.totalMembers) * 100;
    }
}

GroupBooking.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        bookingId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'booking_id',
            references: {
                model: 'bookings',
                key: 'id',
            },
        },
        organizerId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'organizer_id',
            references: {
                model: 'users',
                key: 'id',
            },
        },
        groupName: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'group_name',
        },
        splitPaymentEnabled: {
            type: DataTypes.BOOLEAN,
            defaultValue: true,
            field: 'split_payment_enabled',
        },
        splitType: {
            type: DataTypes.ENUM(...Object.values(SplitType)),
            defaultValue: SplitType.EQUAL,
            field: 'split_type',
        },
        totalMembers: {
            type: DataTypes.INTEGER,
            allowNull: false,
            field: 'total_members',
            validate: {
                min: 2,
            },
        },
        confirmedMembers: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'confirmed_members',
        },
        paidMembers: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'paid_members',
        },
        invitationCode: {
            type: DataTypes.STRING(20),
            allowNull: false,
            unique: true,
            field: 'invitation_code',
        },
        invitationExpiresAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'invitation_expires_at',
        },
    },
    {
        sequelize,
        tableName: 'group_bookings',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['booking_id'] },
            { fields: ['organizer_id'] },
            { fields: ['invitation_code'], unique: true },
        ],
    }
);

// Generate invitationCode BEFORE validation (beforeCreate fires too late — after null checks)
GroupBooking.beforeValidate((groupBooking) => {
    if (!groupBooking.invitationCode) {
        groupBooking.invitationCode = Math.random().toString(36).substring(2, 10).toUpperCase();
    }

    if (!groupBooking.invitationExpiresAt) {
        const expiryDate = new Date();
        expiryDate.setDate(expiryDate.getDate() + 7);
        groupBooking.invitationExpiresAt = expiryDate;
    }
});

export default GroupBooking;
