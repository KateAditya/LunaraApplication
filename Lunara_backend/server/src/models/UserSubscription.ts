import { Model, DataTypes } from 'sequelize';
import sequelize from '../config/database';

export enum SubscriptionStatus {
    ACTIVE = 'ACTIVE',
    UPCOMING = 'UPCOMING',
    EXPIRED = 'EXPIRED',
    CANCELLED = 'CANCELLED'
}

class UserSubscription extends Model {
    public id!: string;
    public userId!: string;
    public packageId!: string;
    
    public status!: SubscriptionStatus;
    public startDate!: Date;
    public endDate!: Date;

    // Remaining features for the current cycle
    public superlikesRemaining!: number;
    public boostsRemaining!: number;
    public expirationAlertSent!: boolean;

    // Multi-stage notification tracking fields
    public reminder1DaySent!: boolean;
    public reminder8HourSent!: boolean;
    public reminder5HourSent!: boolean;
    public reminder2HourSent!: boolean;
    public reminder1HourSent!: boolean;
    public expiryNotified!: boolean;
    public lastNotifiedAt?: Date | null;

    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

UserSubscription.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        userId: {
            type: DataTypes.UUID,
            allowNull: false,
            references: {
                model: 'users',
                key: 'id',
            },
        },
        packageId: {
            type: DataTypes.UUID,
            allowNull: false,
            references: {
                model: 'SubscriptionPackages',
                key: 'id',
            },
        },
        status: {
            type: DataTypes.ENUM(...Object.values(SubscriptionStatus)),
            allowNull: false,
            defaultValue: SubscriptionStatus.ACTIVE,
        },
        startDate: {
            type: DataTypes.DATE,
            allowNull: false,
            defaultValue: DataTypes.NOW,
        },
        endDate: {
            type: DataTypes.DATE,
            allowNull: false,
        },
        superlikesRemaining: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
        },
        boostsRemaining: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
        },
        expirationAlertSent: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
        },
        reminder1DaySent: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
        },
        reminder8HourSent: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
        },
        reminder5HourSent: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
        },
        reminder2HourSent: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
        },
        reminder1HourSent: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
        },
        expiryNotified: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
        },
        lastNotifiedAt: {
            type: DataTypes.DATE,
            allowNull: true,
        },
    },
    {
        sequelize,
        modelName: 'UserSubscription',
        tableName: 'UserSubscriptions',
        timestamps: true,
        indexes: [
            {
                name: 'idx_user_subs_status_enddate',
                fields: ['status', 'endDate'],
            },
            {
                name: 'idx_user_subs_user_status',
                fields: ['userId', 'status'],
            },
        ],
    }
);

export default UserSubscription;
