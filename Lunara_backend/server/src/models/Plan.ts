import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum PlanStatus {
    ACTIVE    = 'active',     // Posted, accepting joiners
    FULL      = 'full',       // Max joiners reached
    SECURED   = 'secured',    // Reservation confirmed
    CANCELLED = 'cancelled',
}

export enum PlanPaymentOption {
    FULL  = 'full',   // Host pays full amount upfront
    SPLIT = 'split',  // Amount split between host + joiners
}

export interface PlanAttributes {
    id: string;
    userId: string;             // Plan poster / host
    venueId: string;
    planDate: Date;
    startTime: string;
    tablePackage: string;       // silver | gold | platinum
    paymentOption: PlanPaymentOption;
    totalAmount: number;
    maxJoiners: number;
    currentJoiners: number;
    status: PlanStatus;
    description?: string;
    bookingId?: string;         // Set when secured
    hostPaymentStatus: string;  // pending | paid
    hostTransactionId?: string;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface PlanCreationAttributes
    extends Optional<
        PlanAttributes,
        | 'id'
        | 'currentJoiners'
        | 'status'
        | 'description'
        | 'bookingId'
        | 'hostPaymentStatus'
        | 'hostTransactionId'
        | 'createdAt'
        | 'updatedAt'
    > {}

class Plan extends Model<PlanAttributes, PlanCreationAttributes> implements PlanAttributes {
    public id!: string;
    public userId!: string;
    public venueId!: string;
    public planDate!: Date;
    public startTime!: string;
    public tablePackage!: string;
    public paymentOption!: PlanPaymentOption;
    public totalAmount!: number;
    public maxJoiners!: number;
    public currentJoiners!: number;
    public status!: PlanStatus;
    public description?: string;
    public bookingId?: string;
    public hostPaymentStatus!: string;
    public hostTransactionId?: string;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    public isFull(): boolean {
        return this.currentJoiners >= this.maxJoiners;
    }

    public getShareAmount(): number {
        const total = this.currentJoiners + 1; // host + current joiners
        return Math.round((this.totalAmount / total) * 100) / 100;
    }
}

Plan.init(
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
        planDate: {
            type: DataTypes.DATEONLY,
            allowNull: false,
            field: 'plan_date',
        },
        startTime: {
            type: DataTypes.STRING(10),
            allowNull: false,
            field: 'start_time',
        },
        tablePackage: {
            type: DataTypes.STRING(20),
            allowNull: false,
            field: 'table_package',
        },
        paymentOption: {
            type: DataTypes.ENUM(...Object.values(PlanPaymentOption)),
            allowNull: false,
            field: 'payment_option',
        },
        totalAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            field: 'total_amount',
        },
        maxJoiners: {
            type: DataTypes.INTEGER,
            allowNull: false,
            field: 'max_joiners',
        },
        currentJoiners: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'current_joiners',
        },
        status: {
            type: DataTypes.ENUM(...Object.values(PlanStatus)),
            defaultValue: PlanStatus.ACTIVE,
        },
        description: {
            type: DataTypes.TEXT,
            allowNull: true,
        },
        bookingId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'booking_id',
        },
        hostPaymentStatus: {
            type: DataTypes.STRING(20),
            defaultValue: 'pending',
            field: 'host_payment_status',
        },
        hostTransactionId: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'host_transaction_id',
        },
    },
    {
        sequelize,
        tableName: 'plans',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['venue_id'] },
            { fields: ['plan_date'] },
            { fields: ['status'] },
        ],
    }
);

export default Plan;
