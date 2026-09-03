import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum HostCancellationStatus {
    PENDING_ADMIN_REVIEW = 'PENDING_ADMIN_REVIEW',
    APPROVED = 'APPROVED',
    REJECTED = 'REJECTED',
    REFUND_PROCESSING = 'REFUND_PROCESSING',
    REFUNDED = 'REFUNDED',
    COMPLETED = 'COMPLETED',
}

export enum HostCancellationRefundMethod {
    WALLET = 'WALLET',
    MANUAL_PAYOUT = 'MANUAL_PAYOUT',
    NONE = 'NONE',
}

export enum HostRefundStatus {
    NONE = 'NONE',
    WALLET_CREDITED = 'WALLET_CREDITED',
    HOST_REFUND_PENDING_SETTLEMENT = 'HOST_REFUND_PENDING_SETTLEMENT',
    PAID = 'PAID',
}

export interface StrangersMeetHostCancellationRequestAttributes {
    id: string;
    meetId: string;
    hostUserId: string;
    reason: string;
    reasonText?: string | null;
    status: HostCancellationStatus;
    refundPolicyPercentage?: number | null;
    refundMethod?: HostCancellationRefundMethod | null;
    totalCollectedAmount: number;
    totalRefundAmount?: number | null;
    totalMembersCount: number;
    adminReviewedBy?: string | null;
    adminReviewedAt?: Date | null;
    adminNotes?: string | null;
    hostDepositAmount?: number;
    hostRefundType?: 'FULL' | 'PARTIAL' | 'CUSTOM' | 'NO_REFUND' | null;
    hostRefundPercentage?: number | null;
    hostRefundAmount?: number;
    hostRefundDestination?: 'WALLET' | 'UPI' | 'BANK' | 'NONE' | null;
    hostRefundStatus?: HostRefundStatus | string | null;
    hostPayoutDetails?: any;
    hostSettlementTransactionId?: string | null;
    hostSettledAt?: Date | null;
    hostSettledBy?: string | null;
    hostSettlementNotes?: string | null;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface StrangersMeetHostCancellationRequestCreationAttributes
    extends Optional<
        StrangersMeetHostCancellationRequestAttributes,
        | 'id'
        | 'reasonText'
        | 'status'
        | 'refundPolicyPercentage'
        | 'refundMethod'
        | 'totalCollectedAmount'
        | 'totalRefundAmount'
        | 'totalMembersCount'
        | 'adminReviewedBy'
        | 'adminReviewedAt'
        | 'adminNotes'
        | 'hostDepositAmount'
        | 'hostRefundType'
        | 'hostRefundPercentage'
        | 'hostRefundAmount'
        | 'hostRefundDestination'
        | 'hostRefundStatus'
        | 'hostPayoutDetails'
        | 'hostSettlementTransactionId'
        | 'hostSettledAt'
        | 'hostSettledBy'
        | 'hostSettlementNotes'
        | 'createdAt'
        | 'updatedAt'
    > { }

export class StrangersMeetHostCancellationRequest
    extends Model<StrangersMeetHostCancellationRequestAttributes, StrangersMeetHostCancellationRequestCreationAttributes>
    implements StrangersMeetHostCancellationRequestAttributes {
    public id!: string;
    public meetId!: string;
    public hostUserId!: string;
    public reason!: string;
    public reasonText?: string | null;
    public status!: HostCancellationStatus;
    public refundPolicyPercentage?: number | null;
    public refundMethod?: HostCancellationRefundMethod | null;
    public totalCollectedAmount!: number;
    public totalRefundAmount?: number | null;
    public totalMembersCount!: number;
    public adminReviewedBy?: string | null;
    public adminReviewedAt?: Date | null;
    public adminNotes?: string | null;
    public hostDepositAmount!: number;
    public hostRefundType?: 'FULL' | 'PARTIAL' | 'CUSTOM' | 'NO_REFUND' | null;
    public hostRefundPercentage?: number | null;
    public hostRefundAmount!: number;
    public hostRefundDestination?: 'WALLET' | 'UPI' | 'BANK' | 'NONE' | null;
    public hostRefundStatus?: HostRefundStatus | string | null;
    public hostPayoutDetails?: any;
    public hostSettlementTransactionId?: string | null;
    public hostSettledAt?: Date | null;
    public hostSettledBy?: string | null;
    public hostSettlementNotes?: string | null;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

StrangersMeetHostCancellationRequest.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        meetId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'meet_id',
            references: { model: 'strangers_meet_requests', key: 'id' },
            onDelete: 'CASCADE',
        },
        hostUserId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'host_user_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        reason: {
            type: DataTypes.STRING(255),
            allowNull: false,
        },
        reasonText: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'reason_text',
        },
        status: {
            type: DataTypes.STRING(50),
            allowNull: false,
            defaultValue: HostCancellationStatus.PENDING_ADMIN_REVIEW,
        },
        refundPolicyPercentage: {
            type: DataTypes.DECIMAL(5, 2),
            allowNull: true,
            field: 'refund_policy_percentage',
            get() {
                const val = this.getDataValue('refundPolicyPercentage');
                return val === null || val === undefined ? null : parseFloat(val.toString());
            },
        },
        refundMethod: {
            type: DataTypes.STRING(30),
            allowNull: true,
            field: 'refund_method',
        },
        totalCollectedAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.0,
            field: 'total_collected_amount',
            get() {
                const val = this.getDataValue('totalCollectedAmount');
                return val === null || val === undefined ? 0.0 : parseFloat(val.toString());
            },
        },
        totalRefundAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            field: 'total_refund_amount',
            get() {
                const val = this.getDataValue('totalRefundAmount');
                return val === null || val === undefined ? null : parseFloat(val.toString());
            },
        },
        totalMembersCount: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
            field: 'total_members_count',
        },
        adminReviewedBy: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'admin_reviewed_by',
            references: { model: 'users', key: 'id' },
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
        hostDepositAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.0,
            field: 'host_deposit_amount',
            get() {
                const val = this.getDataValue('hostDepositAmount');
                return val === null || val === undefined ? 0.0 : parseFloat(val.toString());
            },
        },
        hostRefundType: {
            type: DataTypes.STRING(30),
            allowNull: true,
            field: 'host_refund_type',
        },
        hostRefundPercentage: {
            type: DataTypes.DECIMAL(5, 2),
            allowNull: true,
            field: 'host_refund_percentage',
            get() {
                const val = this.getDataValue('hostRefundPercentage');
                return val === null || val === undefined ? null : parseFloat(val.toString());
            },
        },
        hostRefundAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.0,
            field: 'host_refund_amount',
            get() {
                const val = this.getDataValue('hostRefundAmount');
                return val === null || val === undefined ? 0.0 : parseFloat(val.toString());
            },
        },
        hostRefundDestination: {
            type: DataTypes.STRING(30),
            allowNull: true,
            field: 'host_refund_destination',
        },
        hostRefundStatus: {
            type: DataTypes.STRING(50),
            allowNull: true,
            defaultValue: 'NONE',
            field: 'host_refund_status',
        },
        hostPayoutDetails: {
            type: DataTypes.JSONB,
            allowNull: true,
            field: 'host_payout_details',
        },
        hostSettlementTransactionId: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'host_settlement_transaction_id',
        },
        hostSettledAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'host_settled_at',
        },
        hostSettledBy: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'host_settled_by',
        },
        hostSettlementNotes: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'host_settlement_notes',
        },
    },
    {
        sequelize,
        modelName: 'StrangersMeetHostCancellationRequest',
        tableName: 'strangers_meet_host_cancellation_requests',
        timestamps: true,
        indexes: [
            {
                name: 'idx_sm_host_cancel_meet_id',
                fields: ['meet_id'],
            },
            {
                name: 'idx_sm_host_cancel_host_user_id',
                fields: ['host_user_id'],
            },
            {
                name: 'idx_sm_host_cancel_status',
                fields: ['status'],
            },
        ],
    }
);

export default StrangersMeetHostCancellationRequest;
