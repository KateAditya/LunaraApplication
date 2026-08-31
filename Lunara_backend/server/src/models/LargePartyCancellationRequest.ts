import { DataTypes, Model, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum LargePartyCancellationStatus {
    PENDING_ADMIN_REVIEW = 'PENDING_ADMIN_REVIEW',
    APPROVED = 'APPROVED',
    REJECTED = 'REJECTED',
    REFUND_PROCESSING = 'REFUND_PROCESSING',
    REFUND_PAID = 'REFUND_PAID',
    COMPLETED = 'COMPLETED',
}

export enum LargePartyRefundMethod {
    WALLET = 'WALLET',
    MANUAL_PAYOUT = 'MANUAL_PAYOUT',
}

export interface LargePartyCancellationRequestAttributes {
    id: string;
    bookingId: string;
    userId: string;
    venueId?: string;
    originalPaidAmount: number;
    refundPercentage?: number;
    refundAmount?: number;
    nonRefundableAmount?: number;
    refundMethod?: LargePartyRefundMethod;
    reason: string;
    reasonDetails?: string;
    upiId?: string;
    mobileNumber?: string;
    accountHolderName?: string;
    accountNumber?: string;
    ifscCode?: string;
    status: LargePartyCancellationStatus;
    adminReviewedBy?: string;
    adminReviewedAt?: Date;
    adminNotes?: string;
    paymentReference?: string;
    paidByAdminId?: string;
    paidAt?: Date;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface LargePartyCancellationRequestCreationAttributes
    extends Optional<
        LargePartyCancellationRequestAttributes,
        | 'id'
        | 'venueId'
        | 'refundPercentage'
        | 'refundAmount'
        | 'nonRefundableAmount'
        | 'refundMethod'
        | 'reasonDetails'
        | 'upiId'
        | 'mobileNumber'
        | 'accountHolderName'
        | 'accountNumber'
        | 'ifscCode'
        | 'status'
        | 'adminReviewedBy'
        | 'adminReviewedAt'
        | 'adminNotes'
        | 'paymentReference'
        | 'paidByAdminId'
        | 'paidAt'
        | 'createdAt'
        | 'updatedAt'
    > {}

export class LargePartyCancellationRequest
    extends Model<
        LargePartyCancellationRequestAttributes,
        LargePartyCancellationRequestCreationAttributes
    >
    implements LargePartyCancellationRequestAttributes
{
    public id!: string;
    public bookingId!: string;
    public userId!: string;
    public venueId?: string;
    public originalPaidAmount!: number;
    public refundPercentage?: number;
    public refundAmount?: number;
    public nonRefundableAmount?: number;
    public refundMethod?: LargePartyRefundMethod;
    public reason!: string;
    public reasonDetails?: string;
    public upiId?: string;
    public mobileNumber?: string;
    public accountHolderName?: string;
    public accountNumber?: string;
    public ifscCode?: string;
    public status!: LargePartyCancellationStatus;
    public adminReviewedBy?: string;
    public adminReviewedAt?: Date;
    public adminNotes?: string;
    public paymentReference?: string;
    public paidByAdminId?: string;
    public paidAt?: Date;

    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

LargePartyCancellationRequest.init(
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
            onDelete: 'CASCADE',
        },
        userId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'user_id',
            references: {
                model: 'users',
                key: 'id',
            },
            onDelete: 'CASCADE',
        },
        venueId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'venue_id',
            references: {
                model: 'venues',
                key: 'id',
            },
            onDelete: 'SET NULL',
        },
        originalPaidAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.0,
            field: 'original_paid_amount',
            get() {
                const val = this.getDataValue('originalPaidAmount');
                return val === null ? 0 : parseFloat(val as any);
            },
        },
        refundPercentage: {
            type: DataTypes.INTEGER,
            allowNull: true,
            field: 'refund_percentage',
        },
        refundAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            field: 'refund_amount',
            get() {
                const val = this.getDataValue('refundAmount');
                return val === null ? null : parseFloat(val as any);
            },
        },
        nonRefundableAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            field: 'non_refundable_amount',
            get() {
                const val = this.getDataValue('nonRefundableAmount');
                return val === null ? null : parseFloat(val as any);
            },
        },
        refundMethod: {
            type: DataTypes.STRING(30),
            allowNull: true,
            field: 'refund_method',
        },
        reason: {
            type: DataTypes.TEXT,
            allowNull: false,
            field: 'reason',
        },
        reasonDetails: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'reason_details',
        },
        upiId: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'upi_id',
        },
        mobileNumber: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'mobile_number',
        },
        accountHolderName: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'account_holder_name',
        },
        accountNumber: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'account_number',
        },
        ifscCode: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'ifsc_code',
        },
        status: {
            type: DataTypes.STRING(50),
            allowNull: false,
            field: 'status',
            defaultValue: LargePartyCancellationStatus.PENDING_ADMIN_REVIEW,
        },
        adminReviewedBy: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'admin_reviewed_by',
            references: {
                model: 'users',
                key: 'id',
            },
            onDelete: 'SET NULL',
        },
        adminReviewedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'admin_reviewed_at',
        },
        adminNotes: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'admin_notes',
        },
        paymentReference: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'payment_reference',
        },
        paidByAdminId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'paid_by_admin_id',
            references: {
                model: 'users',
                key: 'id',
            },
            onDelete: 'SET NULL',
        },
        paidAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'paid_at',
        },
    },
    {
        sequelize,
        tableName: 'large_party_cancellation_requests',
        modelName: 'LargePartyCancellationRequest',
        timestamps: true,
        underscored: true,
        indexes: [
            {
                name: 'idx_lp_cancel_booking_id',
                fields: ['booking_id'],
            },
            {
                name: 'idx_lp_cancel_user_id',
                fields: ['user_id'],
            },
            {
                name: 'idx_lp_cancel_status',
                fields: ['status'],
            },
        ],
    }
);

export default LargePartyCancellationRequest;
