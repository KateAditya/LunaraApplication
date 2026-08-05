import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface PartyReviewAttributes {
    id: string;
    planId: string;
    bookingId?: string | null;
    reviewerId: string;
    revieweeId: string;
    rating: number; // 1 to 5
    comment?: string | null;
    isReported: boolean;
    reportReason?: string | null;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface PartyReviewCreationAttributes
    extends Optional<PartyReviewAttributes, 'id' | 'isReported' | 'createdAt' | 'updatedAt'> {}

class PartyReview
    extends Model<PartyReviewAttributes, PartyReviewCreationAttributes>
    implements PartyReviewAttributes {
    public id!: string;
    public planId!: string;
    public bookingId?: string | null;
    public reviewerId!: string;
    public revieweeId!: string;
    public rating!: number;
    public comment?: string | null;
    public isReported!: boolean;
    public reportReason?: string | null;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

PartyReview.init(
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
        },
        reviewerId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'reviewer_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        revieweeId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'reviewee_id',
            references: { model: 'users', key: 'id' },
            onDelete: 'CASCADE',
        },
        rating: {
            type: DataTypes.INTEGER,
            allowNull: false,
            validate: { min: 1, max: 5 },
        },
        comment: {
            type: DataTypes.TEXT,
            allowNull: true,
        },
        isReported: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_reported',
        },
        reportReason: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'report_reason',
        },
    },
    {
        sequelize,
        tableName: 'party_reviews',
        timestamps: true,
        indexes: [
            { fields: ['plan_id', 'reviewerId'], unique: true },
            { fields: ['reviewer_id'] },
            { fields: ['reviewee_id'] },
        ],
    }
);

export default PartyReview;
