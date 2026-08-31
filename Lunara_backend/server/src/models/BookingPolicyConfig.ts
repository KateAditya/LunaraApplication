import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum BookingPolicyType {
    SOLO_BOOKING = 'SOLO_BOOKING',
    GROUP_PARTY = 'GROUP_PARTY',
}

export interface BookingPolicyConfigAttributes {
    id: string;
    bookingType: BookingPolicyType;
    minBookingLeadTimeHours: number;
    cancellationCutoffHours: number;
    refundEnabled: boolean;
    refundPercentage: number;
    isActive: boolean;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface BookingPolicyConfigCreationAttributes
    extends Optional<BookingPolicyConfigAttributes, 'id' | 'minBookingLeadTimeHours' | 'cancellationCutoffHours' | 'refundEnabled' | 'refundPercentage' | 'isActive' | 'createdAt' | 'updatedAt'> { }

export class BookingPolicyConfig
    extends Model<BookingPolicyConfigAttributes, BookingPolicyConfigCreationAttributes>
    implements BookingPolicyConfigAttributes {
    public id!: string;
    public bookingType!: BookingPolicyType;
    public minBookingLeadTimeHours!: number;
    public cancellationCutoffHours!: number;
    public refundEnabled!: boolean;
    public refundPercentage!: number;
    public isActive!: boolean;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

BookingPolicyConfig.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        bookingType: {
            type: DataTypes.STRING(50),
            allowNull: false,
            unique: true,
            field: 'booking_type',
        },
        minBookingLeadTimeHours: {
            type: DataTypes.DECIMAL(5, 2),
            allowNull: false,
            defaultValue: 2.0,
            field: 'min_booking_lead_time_hours',
            get() {
                const val = this.getDataValue('minBookingLeadTimeHours');
                return val === null || val === undefined ? 2.0 : parseFloat(val.toString());
            },
        },
        cancellationCutoffHours: {
            type: DataTypes.DECIMAL(5, 2),
            allowNull: false,
            defaultValue: 2.0,
            field: 'cancellation_cutoff_hours',
            get() {
                const val = this.getDataValue('cancellationCutoffHours');
                return val === null || val === undefined ? 2.0 : parseFloat(val.toString());
            },
        },
        refundEnabled: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: true,
            field: 'refund_enabled',
        },
        refundPercentage: {
            type: DataTypes.DECIMAL(5, 2),
            allowNull: false,
            defaultValue: 80.0,
            field: 'refund_percentage',
            get() {
                const val = this.getDataValue('refundPercentage');
                return val === null || val === undefined ? 80.0 : parseFloat(val.toString());
            },
        },
        isActive: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: true,
            field: 'is_active',
        },
    },
    {
        sequelize,
        modelName: 'BookingPolicyConfig',
        tableName: 'booking_policy_configs',
        timestamps: true,
        indexes: [
            {
                name: 'idx_booking_policy_configs_type',
                unique: true,
                fields: ['booking_type'],
            },
        ],
    }
);

export default BookingPolicyConfig;
