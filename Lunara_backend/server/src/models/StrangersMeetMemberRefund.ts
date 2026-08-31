import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum MemberRefundStatus {
    PENDING = 'PENDING',
    REFUND_PAID = 'REFUND_PAID',
    FAILED = 'FAILED',
}

export interface StrangersMeetMemberRefundAttributes {
    id: string;
    hostCancellationRequestId: string;
    meetId: string;
    joinerId: string;
    userId: string;
    paidAmount: number;
    refundPercentage: number;
    refundAmount: number;
    refundMethod: string;
    status: MemberRefundStatus;
    walletTransactionId?: string | null;
    payoutDetails?: any | null;
    paymentReference?: string | null;
    paidByAdminId?: string | null;
    paidAt?: Date | null;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface StrangersMeetMemberRefundCreationAttributes
    extends Optional<
        StrangersMeetMemberRefundAttributes,
        | 'id'
        | 'status'
        | 'walletTransactionId'
        | 'payoutDetails'
        | 'paymentReference'
        | 'paidByAdminId'
        | 'paidAt'
        | 'createdAt'
        | 'updatedAt'
    > { }

export class StrangersMeetMemberRefund
    extends Model<StrangersMeetMemberRefundAttributes, StrangersMeetMemberRefundCreationAttributes>
    implements StrangersMeetMemberRefundAttributes {
    public id!: string;
    public hostCancellationRequestId!: string;
    public meetId!: string;
    public joinerId!: string;
    public userId!: string;
    public paidAmount!: number;
    public refundPercentage!: number;
    public refundAmount!: number;
    public refundMethod!: string;
    public status!: MemberRefundStatus;
    public walletTransactionId?: string | null;
    public payoutDetails?: any | null;
    public paymentReference?: string | null;
    public paidByAdminId?: string | null;
    public paidAt?: Date | null;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

StrangersMeetMemberRefund.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        hostCancellationRequestId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'host_cancellation_request_id',
            references: { model: 'strangers_meet_host_cancellation_requests', key: 'id' },
            onDelete: 'CASCADE',
        },
        meetId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'meet_id',
            references: { model: 'strangers_meet_requests', key: 'id' },
            onDelete: 'CASCADE',
        },
        joinerId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'joiner_id',
            references: { model: 'strangers_meet_joiners', key: 'id' },
            onDelete: 'CASCADE',
        },
        userId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'user_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        paidAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.0,
            field: 'paid_amount',
            get() {
                const val = this.getDataValue('paidAmount');
                return val === null || val === undefined ? 0.0 : parseFloat(val.toString());
            },
        },
        refundPercentage: {
            type: DataTypes.DECIMAL(5, 2),
            allowNull: false,
            defaultValue: 100.0,
            field: 'refund_percentage',
            get() {
                const val = this.getDataValue('refundPercentage');
                return val === null || val === undefined ? 100.0 : parseFloat(val.toString());
            },
        },
        refundAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.0,
            field: 'refund_amount',
            get() {
                const val = this.getDataValue('refundAmount');
                return val === null || val === undefined ? 0.0 : parseFloat(val.toString());
            },
        },
        refundMethod: {
            type: DataTypes.STRING(30),
            allowNull: false,
            defaultValue: 'WALLET',
            field: 'refund_method',
        },
        status: {
            type: DataTypes.STRING(30),
            allowNull: false,
            defaultValue: MemberRefundStatus.PENDING,
        },
        walletTransactionId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'wallet_transaction_id',
        },
        payoutDetails: {
            type: DataTypes.JSONB,
            allowNull: true,
            field: 'payout_details',
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
            references: { model: 'users', key: 'id' },
        },
        paidAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'paid_at',
        },
    },
    {
        sequelize,
        modelName: 'StrangersMeetMemberRefund',
        tableName: 'strangers_meet_member_refunds',
        timestamps: true,
        indexes: [
            {
                name: 'idx_sm_mem_refund_host_cancel_id',
                fields: ['host_cancellation_request_id'],
            },
            {
                name: 'idx_sm_mem_refund_meet_id',
                fields: ['meet_id'],
            },
            {
                name: 'idx_sm_mem_refund_joiner_id',
                fields: ['joiner_id'],
            },
            {
                name: 'idx_sm_mem_refund_user_id',
                fields: ['user_id'],
            },
            {
                name: 'idx_sm_mem_refund_status',
                fields: ['status'],
            },
        ],
    }
);

export default StrangersMeetMemberRefund;
