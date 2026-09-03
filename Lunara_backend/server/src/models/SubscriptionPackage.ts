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
            field: 'daily_match_requests',
        },
        dailyLikes: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 7, // Default for free
            field: 'daily_likes',
        },
        dailyPosts: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 5, // Arbitrary limit for free
            field: 'daily_posts',
        },
        superlikesPerCycle: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
            field: 'superlikes_per_cycle',
        },
        boostsPerCycle: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 0,
            field: 'boosts_per_cycle',
        },
        backtrackLimit: {
            type: DataTypes.INTEGER,
            allowNull: false,
            defaultValue: 3,
            field: 'backtrack_limit',
        },
        hasHideProfile: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'has_hide_profile',
        },
        hasPriorityVisibility: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'has_priority_visibility',
        },
        hasTrustBadge: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'has_trust_badge',
        },
        hasEliteBadge: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'has_elite_badge',
        },
        canSeeWhoLiked: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
            field: 'can_see_who_liked',
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
