import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum StrangersMeetCancellationStatus {
    PENDING = 'pending',
    APPROVED = 'approved',
    REJECTED = 'rejected',
    CANCELLED = 'cancelled',
}

export interface StrangersMeetCancellationRequestAttributes {
    id: string;
    meetId: string;
    joinerId: string;
    userId: string;
    hostUserId: string;
    status: StrangersMeetCancellationStatus;
    reason: string;
    otherReasonText?: string | null;
    paidAmount: number;
    refundAmount?: number | null;
    walletTransactionId?: string | null;
    rejectReason?: string | null;
    respondedAt?: Date | null;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface StrangersMeetCancellationRequestCreationAttributes
    extends Optional<
        StrangersMeetCancellationRequestAttributes,
        | 'id'
        | 'status'
        | 'otherReasonText'
        | 'refundAmount'
        | 'walletTransactionId'
        | 'rejectReason'
        | 'respondedAt'
        | 'createdAt'
        | 'updatedAt'
    > { }

export class StrangersMeetCancellationRequest
    extends Model<StrangersMeetCancellationRequestAttributes, StrangersMeetCancellationRequestCreationAttributes>
    implements StrangersMeetCancellationRequestAttributes {
    public id!: string;
    public meetId!: string;
    public joinerId!: string;
    public userId!: string;
    public hostUserId!: string;
    public status!: StrangersMeetCancellationStatus;
    public reason!: string;
    public otherReasonText?: string | null;
    public paidAmount!: number;
    public refundAmount?: number | null;
    public walletTransactionId?: string | null;
    public rejectReason?: string | null;
    public respondedAt?: Date | null;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

StrangersMeetCancellationRequest.init(
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
        hostUserId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'host_user_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        status: {
            type: DataTypes.STRING(30),
            allowNull: false,
            defaultValue: StrangersMeetCancellationStatus.PENDING,
        },
        reason: {
            type: DataTypes.STRING(255),
            allowNull: false,
        },
        otherReasonText: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'other_reason_text',
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
        refundAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: true,
            field: 'refund_amount',
            get() {
                const val = this.getDataValue('refundAmount');
                return val === null || val === undefined ? null : parseFloat(val.toString());
            },
        },
        walletTransactionId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'wallet_transaction_id',
        },
        rejectReason: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'reject_reason',
        },
        respondedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'responded_at',
        },
    },
    {
        sequelize,
        modelName: 'StrangersMeetCancellationRequest',
        tableName: 'strangers_meet_cancellation_requests',
        timestamps: true,
        indexes: [
            {
                name: 'idx_sm_cancel_meet_id',
                fields: ['meet_id'],
            },
            {
                name: 'idx_sm_cancel_joiner_id',
                fields: ['joiner_id'],
            },
            {
                name: 'idx_sm_cancel_user_id',
                fields: ['user_id'],
            },
            {
                name: 'idx_sm_cancel_host_user_id',
                fields: ['host_user_id'],
            },
            {
                name: 'idx_sm_cancel_status',
                fields: ['status'],
            },
        ],
    }
);

export default StrangersMeetCancellationRequest;
