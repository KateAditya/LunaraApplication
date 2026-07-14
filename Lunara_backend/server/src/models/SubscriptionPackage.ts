import { Model, DataTypes } from 'sequelize';
import sequelize from '../config/database';

export enum PackageTier {
    FREE = 'FREE',
    CORE = 'CORE',
    PLUS = 'PLUS',
    PRO = 'PRO',
    ELITE = 'ELITE'
}

class SubscriptionPackage extends Model {
    public id!: string;
    public name!: string;
    public tier!: PackageTier;
    public price!: number;
    public durationDays!: number;

    // Feature Limits (-1 for unlimited)
    public dailyMatchRequests!: number;
    public dailyLikes!: number;
    public dailyPosts!: number;
    public superlikesPerCycle!: number;
    public boostsPerCycle!: number;
    public backtrackLimit!: number;

    // Boolean features
    public hasHideProfile!: boolean;
    public hasPriorityVisibility!: boolean;
    public hasTrustBadge!: boolean;
    public hasEliteBadge!: boolean;
    public canSeeWhoLiked!: boolean;

    public isActive!: boolean;

    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

SubscriptionPackage.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        name: {
            type: DataTypes.STRING,
            allowNull: false,
        },
        tier: {
            type: DataTypes.ENUM(...Object.values(PackageTier)),
            allowNull: false,
            defaultValue: PackageTier.FREE,
        },
        price: {
            type: DataTypes.DECIMAL(10, 2),
            allowNull: false,
            defaultValue: 0.0,
        },
        durationDays: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
        },
        dailyMatchRequests: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 3, // Default for free
        },
        dailyLikes: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 7, // Default for free
        },
        dailyPosts: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 5, // Arbitrary limit for free
        },
        superlikesPerCycle: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
        },
        boostsPerCycle: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
        },
        backtrackLimit: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 3,
        },
        hasHideProfile: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
        },
        hasPriorityVisibility: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
        },
        hasTrustBadge: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
        },
        hasEliteBadge: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
        },
        canSeeWhoLiked: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
        },
        isActive: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: true,
        },
    },
    {
        sequelize,
        modelName: 'SubscriptionPackage',
        tableName: 'SubscriptionPackages',
        timestamps: true,
    }
);

export default SubscriptionPackage;
