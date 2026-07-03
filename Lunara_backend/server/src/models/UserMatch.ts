import { Model, DataTypes, Optional, Op } from 'sequelize';
import sequelize from '../config/database';

// Match status enum
export enum MatchStatus {
    PENDING = 'pending',
    CONNECTED = 'connected',
    DECLINED = 'declined',
    EXPIRED = 'expired',
}

// UserMatch attributes
export interface UserMatchAttributes {
    id: string;
    user1Id: string;
    user2Id: string;
    compatibilityScore: number;
    commonInterests?: any;
    matchReason?: string;
    status: MatchStatus;
    venueId?: string;
    eventDate?: Date;
    expiresAt: Date;
    createdAt?: Date;
}

export interface UserMatchCreationAttributes
    extends Optional<
        UserMatchAttributes,
        'id' | 'commonInterests' | 'matchReason' | 'status' | 'venueId' | 'eventDate' | 'createdAt'
    > { }

class UserMatch extends Model<UserMatchAttributes, UserMatchCreationAttributes> implements UserMatchAttributes {
    public id!: string;
    public user1Id!: string;
    public user2Id!: string;
    public compatibilityScore!: number;
    public commonInterests?: any;
    public matchReason?: string;
    public status!: MatchStatus;
    public venueId?: string;
    public eventDate?: Date;
    public expiresAt!: Date;
    public readonly createdAt!: Date;

    // Instance methods
    public isExpired(): boolean {
        return new Date() > this.expiresAt && this.status === MatchStatus.PENDING;
    }

    public isActive(): boolean {
        return this.status === MatchStatus.CONNECTED;
    }

    public async accept(): Promise<void> {
        this.status = MatchStatus.CONNECTED;
        await this.save();
    }

    public async decline(): Promise<void> {
        this.status = MatchStatus.DECLINED;
        await this.save();
    }

    // Static method to find mutual matches
    public static async findMutualMatches(user1Id: string, user2Id: string): Promise<UserMatch | null> {
        return UserMatch.findOne({
            where: {
                status: MatchStatus.CONNECTED,
                [Op.or]: [
                    { user1Id, user2Id },
                    { user1Id: user2Id, user2Id: user1Id },
                ],
            },
        });
    }
}

UserMatch.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        user1Id: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'user1_id',
            references: {
                model: 'users',
                key: 'id',
            },
        },
        user2Id: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'user2_id',
            references: {
                model: 'users',
                key: 'id',
            },
        },
        compatibilityScore: {
            type: DataTypes.DECIMAL(5, 2),
            allowNull: false,
            field: 'compatibility_score',
            validate: {
                min: 0,
                max: 100,
            },
        },
        commonInterests: {
            type: DataTypes.JSONB,
            allowNull: true,
            field: 'common_interests',
        },
        matchReason: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'match_reason',
        },
        status: {
            type: DataTypes.ENUM(...Object.values(MatchStatus)),
            defaultValue: MatchStatus.PENDING,
        },
        venueId: {
            type: DataTypes.UUID,
            allowNull: true,
            field: 'venue_id',
            references: {
                model: 'venues',
                key: 'id',
            },
        },
        eventDate: {
            type: DataTypes.DATEONLY,
            allowNull: true,
            field: 'event_date',
        },
        expiresAt: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'expires_at',
        },
    },
    {
        sequelize,
        tableName: 'user_matches',
        underscored: true,
        timestamps: true,
        updatedAt: false,
        indexes: [
            { fields: ['user1_id'] },
            { fields: ['user2_id'] },
            { fields: ['status'] },
            { fields: ['expires_at'] },
            { fields: ['compatibility_score'] },
        ],
    }
);

// Hook to automatically expire old matches
UserMatch.beforeCreate((match) => {
    if (!match.expiresAt) {
        const expiryDays = parseInt(process.env.MATCH_EXPIRY_DAYS || '7');
        const expiresAt = new Date();
        expiresAt.setDate(expiresAt.getDate() + expiryDays);
        match.expiresAt = expiresAt;
    }
});

export default UserMatch;
