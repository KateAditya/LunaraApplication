import { Model, DataTypes } from 'sequelize';
import sequelize from '../config/database';

export enum SubscriptionStatus {
    ACTIVE = 'ACTIVE',
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
    },
    {
        sequelize,
        modelName: 'UserSubscription',
        tableName: 'UserSubscriptions',
        timestamps: true,
    }
);

export default UserSubscription;
