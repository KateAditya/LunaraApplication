import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum PartyPlanRequestStatus {
    PENDING = 'pending',
    WAITING = 'waiting',          // Put on hold while another user is accepted
    PAYMENT_PENDING = 'payment_pending',
    ACCEPTED = 'accepted',
    REJECTED = 'rejected',
    CANCELLED = 'cancelled',
    PAYMENT_FAILED = 'payment_failed',
}

export enum PartyPlanRequestType {
    PUBLIC_REQUEST = 'public_request',
    PRIVATE_INVITE = 'private_invite',
}

export enum PartyPlanJoinerPaymentStatus {
    UNPAID = 'unpaid',
    PAID = 'paid',
    REFUNDED = 'refunded',
}

export interface PartyPlanRequestAttributes {
    id: string;
    planId: string;
    requesterId: string;
    requestType?: PartyPlanRequestType | string;
    status: PartyPlanRequestStatus;
    joinerPaymentStatus: PartyPlanJoinerPaymentStatus;
    joinerRazorpayOrderId?: string;
    joinerRazorpayPaymentId?: string;
    paymentTimeoutAt?: Date | null;
    /**
     * Request cancellation is intentionally represented separately from the
     * plan lifecycle.  `status = cancelled` remains backwards compatible;
     * these fields explain whether the requester withdrew or the host revoked.
     */
    cancelledAt?: Date | null;
    cancelledBy?: string | null;
    cancellationReason?: string | null;
    previousStatus?: string | null;
    latLangCheckIn: boolean;
    guestArrivalConfirmed?: boolean;
    guestArrivalTime?: Date | null;
    guestFirstCheckStatus?: string | null;
    guestFirstCheckRespondedAt?: Date | null;
    guestFinalCheckStatus?: string | null;
    guestFinalCheckRespondedAt?: Date | null;
    partnerReachStatus?: string;
    partnerReachConfirmedAt?: Date | null;
    partnerReachConfirmationSource?: string | null;
    partnerReachNotificationId?: string | null;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface PartyPlanRequestCreationAttributes
    extends Optional<
        PartyPlanRequestAttributes,
        'id' | 'requestType' | 'status' | 'joinerPaymentStatus' | 'latLangCheckIn' | 'createdAt' | 'updatedAt' | 'guestArrivalConfirmed' | 'guestArrivalTime' | 'cancelledAt' | 'cancelledBy' | 'cancellationReason' | 'previousStatus' | 'guestFirstCheckStatus' | 'guestFirstCheckRespondedAt' | 'guestFinalCheckStatus' | 'guestFinalCheckRespondedAt' | 'partnerReachStatus' | 'partnerReachConfirmedAt' | 'partnerReachConfirmationSource' | 'partnerReachNotificationId'
    > {}

class PartyPlanRequest
    extends Model<PartyPlanRequestAttributes, PartyPlanRequestCreationAttributes>
    implements PartyPlanRequestAttributes {
    public id!: string;
    public planId!: string;
    public requesterId!: string;
    public requestType!: PartyPlanRequestType | string;
    public status!: PartyPlanRequestStatus;
    public joinerPaymentStatus!: PartyPlanJoinerPaymentStatus;
    public joinerRazorpayOrderId?: string;
    public joinerRazorpayPaymentId?: string;
    public paymentTimeoutAt?: Date | null;
    public cancelledAt?: Date | null;
    public cancelledBy?: string | null;
    public cancellationReason?: string | null;
    public previousStatus?: string | null;
    public latLangCheckIn!: boolean;
    public guestArrivalConfirmed!: boolean;
    public guestArrivalTime?: Date | null;
    public guestFirstCheckStatus?: string | null;
    public guestFirstCheckRespondedAt?: Date | null;
    public guestFinalCheckStatus?: string | null;
    public guestFinalCheckRespondedAt?: Date | null;
    public partnerReachStatus?: string;
    public partnerReachConfirmedAt?: Date | null;
    public partnerReachConfirmationSource?: string | null;
    public partnerReachNotificationId?: string | null;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

PartyPlanRequest.init(
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
        requesterId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'requester_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        requestType: {
            type: DataTypes.STRING(50),
            allowNull: false,
            defaultValue: PartyPlanRequestType.PUBLIC_REQUEST,
            field: 'request_type',
        },
        status: {
            type: DataTypes.ENUM(...Object.values(PartyPlanRequestStatus)),
            allowNull: false,
            defaultValue: PartyPlanRequestStatus.PENDING,
        },
        joinerPaymentStatus: {
            type: DataTypes.ENUM(...Object.values(PartyPlanJoinerPaymentStatus)),
            allowNull: false,
            defaultValue: PartyPlanJoinerPaymentStatus.UNPAID,
            field: 'joiner_payment_status',
        },
        joinerRazorpayOrderId: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'joiner_razorpay_order_id',
        },
        joinerRazorpayPaymentId: {
            type: DataTypes.STRING,
            allowNull: true,
            field: 'joiner_razorpay_payment_id',
        },
        paymentTimeoutAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'payment_timeout_at',
        },
        cancelledAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'cancelled_at',
        },
        cancelledBy: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'cancelled_by',
        },
        cancellationReason: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'cancellation_reason',
        },
        previousStatus: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'previous_status',
        },
        latLangCheckIn: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'lat_lang_check_in',
        },
        guestArrivalConfirmed: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'guest_arrival_confirmed',
        },
        guestArrivalTime: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'guest_arrival_time',
        },
        guestFirstCheckStatus: {
            type: DataTypes.STRING(30),
            defaultValue: 'pending',
            field: 'guest_first_check_status',
        },
        guestFirstCheckRespondedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'guest_first_check_responded_at',
        },
        guestFinalCheckStatus: {
            type: DataTypes.STRING(30),
            defaultValue: 'pending',
            field: 'guest_final_check_status',
        },
        guestFinalCheckRespondedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'guest_final_check_responded_at',
        },
        partnerReachStatus: {
            type: DataTypes.STRING(30),
            defaultValue: 'PENDING',
            field: 'partner_reach_status',
        },
        partnerReachConfirmedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'partner_reach_confirmed_at',
        },
        partnerReachConfirmationSource: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'partner_reach_confirmation_source',
        },
        partnerReachNotificationId: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'partner_reach_notification_id',
        },
    },
    {
        sequelize,
        tableName: 'party_plan_requests',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['plan_id'] },
            { fields: ['requester_id'] },
            { fields: ['status'] },
            { fields: ['plan_id', 'status'] },
            { fields: ['requester_id', 'status'] },
            { fields: ['plan_id', 'requester_id'] },
            { fields: ['request_type'] },
            { fields: ['plan_id', 'request_type'] },
            { fields: ['requester_id', 'request_type'] },
            { fields: ['created_at'] },
        ],
    }
);

export default PartyPlanRequest;
