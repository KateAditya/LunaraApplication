import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum JoinRequestStatus {
    PENDING   = 'pending',
    ACCEPTED  = 'accepted',
    REJECTED  = 'rejected',
    CANCELLED = 'cancelled',
}

export enum JoinPaymentStatus {
    PENDING = 'pending',
    PAID    = 'paid',
}

export interface PlanJoinRequestAttributes {
    id: string;
    planId: string;
    requesterId: string;
    status: JoinRequestStatus;
    paymentStatus: JoinPaymentStatus;
    shareAmount: number;
    transactionId?: string;
    paidAt?: Date;
    message?: string;          // Optional note from joiner
    createdAt?: Date;
    updatedAt?: Date;
}

export interface PlanJoinRequestCreationAttributes
    extends Optional<
        PlanJoinRequestAttributes,
        | 'id'
        | 'status'
        | 'paymentStatus'
        | 'transactionId'
        | 'paidAt'
        | 'message'
        | 'createdAt'
        | 'updatedAt'
    > {}

class PlanJoinRequest
    extends Model<PlanJoinRequestAttributes, PlanJoinRequestCreationAttributes>
    implements PlanJoinRequestAttributes {
    public id!: string;
    public planId!: string;
    public requesterId!: string;
    public status!: JoinRequestStatus;
    public paymentStatus!: JoinPaymentStatus;
    public shareAmount!: number;
    public transactionId?: string;
    public paidAt?: Date;
    public message?: string;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    public isPaid(): boolean {
        return this.paymentStatus === JoinPaymentStatus.PAID;
    }
}

PlanJoinRequest.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        planId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'plan_id',
            references: { model: 'plans', key: 'id' },
        },
        requesterId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'requester_id',
            references: { model: 'users', key: 'id' },
        },
        status: {
            type: DataTypes.ENUM(...Object.values(JoinRequestStatus)),
            defaultValue: JoinRequestStatus.PENDING,
        },
        paymentStatus: {
            type: DataTypes.ENUM(...Object.values(JoinPaymentStatus)),
            defaultValue: JoinPaymentStatus.PENDING,
            field: 'payment_status',
        },
        shareAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            field: 'share_amount',
        },
        transactionId: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'transaction_id',
        },
        paidAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'paid_at',
        },
        message: {
            type: DataTypes.TEXT,
            allowNull: true,
        },
    },
    {
        sequelize,
        tableName: 'plan_join_requests',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['plan_id'] },
            { fields: ['requester_id'] },
            { fields: ['status'] },
        ],
    }
);

export default PlanJoinRequest;
