import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum StrangersMeetJoinerPaymentStatus {
    PENDING = 'pending',
    PAID = 'paid',
}

export enum StrangersMeetJoinerStatus {
    PENDING = 'pending',
    ACCEPTED = 'accepted',
    REJECTED = 'rejected',
    PAID = 'paid',
}

export interface StrangersMeetJoinerAttributes {
    id: string;
    strangersMeetRequestId: string;
    userId: string;
    status?: StrangersMeetJoinerStatus;
    paymentStatus: StrangersMeetJoinerPaymentStatus;
    paymentAmount: number;
    razorpayOrderId?: string;
    razorpayPaymentId?: string;
    razorpaySignature?: string;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface StrangersMeetJoinerCreationAttributes
    extends Optional<
        StrangersMeetJoinerAttributes,
        | 'id'
        | 'status'
        | 'paymentStatus'
        | 'paymentAmount'
        | 'createdAt'
        | 'updatedAt'
    > { }

class StrangersMeetJoiner
    extends Model<StrangersMeetJoinerAttributes, StrangersMeetJoinerCreationAttributes>
    implements StrangersMeetJoinerAttributes {
    public id!: string;
    public strangersMeetRequestId!: string;
    public userId!: string;
    public status!: StrangersMeetJoinerStatus;
    public paymentStatus!: StrangersMeetJoinerPaymentStatus;
    public paymentAmount!: number;
    public razorpayOrderId?: string;
    public razorpayPaymentId?: string;
    public razorpaySignature?: string;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

StrangersMeetJoiner.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        strangersMeetRequestId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'strangers_meet_request_id',
            references: { model: 'strangers_meet_requests', key: 'id' },
            onDelete: 'CASCADE',
        },
        userId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'user_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        status: {
            type: DataTypes.ENUM(...Object.values(StrangersMeetJoinerStatus)),
            allowNull: false,
            defaultValue: StrangersMeetJoinerStatus.PENDING,
        },
        paymentStatus: {
            type: DataTypes.ENUM(...Object.values(StrangersMeetJoinerPaymentStatus)),
            allowNull: false,
            defaultValue: StrangersMeetJoinerPaymentStatus.PENDING,
            field: 'payment_status',
        },
        paymentAmount: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.0,
            field: 'payment_amount',
        },
        razorpayOrderId: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'razorpay_order_id',
        },
        razorpayPaymentId: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'razorpay_payment_id',
        },
        razorpaySignature: {
            type: DataTypes.STRING(200),
            allowNull: true,
            field: 'razorpay_signature',
        },
    },
    {
        sequelize,
        tableName: 'strangers_meet_joiners',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['strangers_meet_request_id'] },
            { fields: ['user_id'] },
            { fields: ['payment_status'] },
        ],
    }
);

export default StrangersMeetJoiner;
