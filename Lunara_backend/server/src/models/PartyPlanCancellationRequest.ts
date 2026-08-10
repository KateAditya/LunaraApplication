import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum CancellationRequestStatus {
    PENDING = 'pending',
    APPROVED = 'approved',
    REJECTED = 'rejected',
    EXPIRED = 'expired',
    AUTO_APPROVED = 'auto_approved',
}

export enum CancellationReason {
    MY_PLANS_CHANGED = 'my_plans_changed',
    NOT_AVAILABLE = 'not_available',
    NOT_INTERESTED = 'not_interested',
    FOUND_ANOTHER_PLAN = 'found_another_plan',
    VENUE_CHANGED = 'venue_changed',
    PERSONAL_REASONS = 'personal_reasons',
    OTHER = 'other',
}

export interface PartyPlanCancellationRequestAttributes {
    id: string;
    planId: string;
    bookingId?: string | null;
    requestedById: string;
    recipientUserId: string;
    status: CancellationRequestStatus;
    reason: CancellationReason;
    otherReasonText?: string | null;
    requestedAt: Date;
    expiresAt: Date;
    respondedAt?: Date | null;
    respondedById?: string | null;
    autoApprovalEligible: boolean;
    hostDepositAmount: number;
    joinerDepositAmount: number;
    hostWalletTransactionId?: string | null;
    joinerWalletTransactionId?: string | null;
    reliabilityImpact: number;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface PartyPlanCancellationRequestCreationAttributes
    extends Optional<
        PartyPlanCancellationRequestAttributes,
        | 'id'
        | 'bookingId'
        | 'status'
        | 'otherReasonText'
        | 'respondedAt'
        | 'respondedById'
        | 'autoApprovalEligible'
        | 'hostDepositAmount'
        | 'joinerDepositAmount'
        | 'hostWalletTransactionId'
        | 'joinerWalletTransactionId'
        | 'reliabilityImpact'
        | 'createdAt'
        | 'updatedAt'
    > {}

class PartyPlanCancellationRequest
    extends Model<PartyPlanCancellationRequestAttributes, PartyPlanCancellationRequestCreationAttributes>
    implements PartyPlanCancellationRequestAttributes {
    public id!: string;
    public planId!: string;
    public bookingId?: string | null;
    public requestedById!: string;
    public recipientUserId!: string;
    public status!: CancellationRequestStatus;
    public reason!: CancellationReason;
    public otherReasonText?: string | null;
    public requestedAt!: Date;
    public expiresAt!: Date;
    public respondedAt?: Date | null;
    public respondedById?: string | null;
    public autoApprovalEligible!: boolean;
    public hostDepositAmount!: number;
    public joinerDepositAmount!: number;
    public hostWalletTransactionId?: string | null;
    public joinerWalletTransactionId?: string | null;
    public reliabilityImpact!: number;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

PartyPlanCancellationRequest.init(
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
            references: { model: 'party_plans', key: 'id' },
            onDelete: 'CASCADE',
        },
        bookingId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'booking_id',
            references: { model: 'bookings', key: 'id' },
            onDelete: 'SET NULL',
        },
        requestedById: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'requested_by_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        recipientUserId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'recipient_user_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        status: {
            type: DataTypes.ENUM(...Object.values(CancellationRequestStatus)),
            allowNull: false,
            defaultValue: CancellationRequestStatus.PENDING,
        },
        reason: {
            type: DataTypes.ENUM(...Object.values(CancellationReason)),
            allowNull: false,
            defaultValue: CancellationReason.MY_PLANS_CHANGED,
        },
        otherReasonText: {
            type: DataTypes.STRING(150),
            allowNull: true,
            field: 'other_reason_text',
        },
        requestedAt: {
            type: DataTypes.DATE,
            allowNull: false,
            defaultValue: DataTypes.NOW,
            field: 'requested_at',
        },
        expiresAt: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'expires_at',
        },
        respondedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'responded_at',
        },
        respondedById: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'responded_by_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'SET NULL',
        },
        autoApprovalEligible: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'auto_approval_eligible',
        },
        hostDepositAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 99.00,  // Commitment deposit is always ₹99
            field: 'host_deposit_amount',
        },
        joinerDepositAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 99.00,  // Commitment deposit is always ₹99
            field: 'joiner_deposit_amount',
        },
        hostWalletTransactionId: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'host_wallet_transaction_id',
        },
        joinerWalletTransactionId: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'joiner_wallet_transaction_id',
        },
        reliabilityImpact: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: -5,
            field: 'reliability_impact',
        },
    },
    {
        sequelize,
        tableName: 'party_plan_cancellation_requests',
        timestamps: true,
        underscored: true,
    }
);

export default PartyPlanCancellationRequest;
