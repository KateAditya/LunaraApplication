import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

// UserProfile attributes
export interface UserProfileAttributes {
    id: string;
    userId: string;
    displayName?: string;
    bio?: string;
    gender?: string;
    city?: string;
    occupation?: string;
    company?: string;
    education?: string;
    relationshipStatus?: string;
    lookingFor?: string[];
    nightlifePreference?: string[];
    interests?: string[];
    instagramHandle?: string;
    spotifyProfile?: string;
    
    // Daily limits tracking
    dailyMatchRequestsCount?: number;
    dailyLikesCount?: number;
    dailyPostsCount?: number;
    lastActivityDate?: Date;

    createdAt?: Date;
    updatedAt?: Date;
}

export interface UserProfileCreationAttributes
    extends Optional<
        UserProfileAttributes,
        | 'id'
        | 'displayName'
        | 'bio'
        | 'gender'
        | 'city'
        | 'occupation'
        | 'company'
        | 'education'
        | 'relationshipStatus'
        | 'lookingFor'
        | 'nightlifePreference'
        | 'interests'
        | 'instagramHandle'
        | 'spotifyProfile'
        | 'dailyMatchRequestsCount'
        | 'dailyLikesCount'
        | 'dailyPostsCount'
        | 'lastActivityDate'
        | 'createdAt'
        | 'updatedAt'
    > { }

class UserProfile
    extends Model<UserProfileAttributes, UserProfileCreationAttributes>
    implements UserProfileAttributes {
    public id!: string;
    public userId!: string;
    public displayName?: string;
    public bio?: string;
    public gender?: string;
    public city?: string;
    public occupation?: string;
    public company?: string;
    public education?: string;
    public relationshipStatus?: string;
    public lookingFor?: string[];
    public nightlifePreference?: string[];
    public interests?: string[];
    public instagramHandle?: string;
    public spotifyProfile?: string;

    public dailyMatchRequestsCount?: number;
    public dailyLikesCount?: number;
    public dailyPostsCount?: number;
    public lastActivityDate?: Date;

    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    // Instance methods
    public isProfileComplete(): boolean {
        return !!(
            this.displayName &&
            this.bio &&
            this.city &&
            this.lookingFor &&
            this.lookingFor.length > 0
        );
    }

    public getCompletionPercentage(): number {
        const fields = [
            this.displayName,
            this.bio,
            this.gender,
            this.city,
            this.occupation,
            this.company,
            this.education,
            this.relationshipStatus,
            this.lookingFor && this.lookingFor.length > 0,
            this.nightlifePreference && this.nightlifePreference.length > 0,
            this.interests && this.interests.length > 0,
            this.instagramHandle,
            this.spotifyProfile,
        ];

        const filledFields = fields.filter(Boolean).length;
        return Math.round((filledFields / fields.length) * 100);
    }
}

UserProfile.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        userId: {
            type: DataTypes.UUID,
            allowNull: false,
            unique: true,
            field: 'user_id',
            references: {
                model: 'users',
                key: 'id',
            },
            onDelete: 'CASCADE',
        },
        displayName: {
            type: DataTypes.STRING(100),
            allowNull: true,
            field: 'display_name',
            validate: {
                len: [2, 100],
            },
        },
        bio: {
            type: DataTypes.TEXT,
            allowNull: true,
            validate: {
                len: [0, 500],
            },
        },
        gender: {
            type: DataTypes.STRING(20),
            allowNull: true,
        },
        city: {
            type: DataTypes.STRING(100),
            allowNull: true,
        },
        occupation: {
            type: DataTypes.STRING(100),
            allowNull: true,
        },
        company: {
            type: DataTypes.STRING(100),
            allowNull: true,
        },
        education: {
            type: DataTypes.STRING(200),
            allowNull: true,
        },
        relationshipStatus: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'relationship_status',
        },
        lookingFor: {
            type: DataTypes.ARRAY(DataTypes.STRING),
            allowNull: true,
            defaultValue: [],
            field: 'looking_for',
        },
        nightlifePreference: {
            type: DataTypes.ARRAY(DataTypes.STRING),
            allowNull: true,
            defaultValue: [],
            field: 'nightlife_preference',
        },
        interests: {
            type: DataTypes.ARRAY(DataTypes.STRING),
            allowNull: true,
            defaultValue: [],
            field: 'interests',
        },
        instagramHandle: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'instagram_handle',
            validate: {
                is: /^[a-zA-Z0-9._]{0,30}$/,
            },
        },
        spotifyProfile: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'spotify_profile',
        },
        dailyMatchRequestsCount: {
            type: DataTypes.INTEGER,
            allowNull: true,
            defaultValue: 0,
        },
        dailyLikesCount: {
            type: DataTypes.INTEGER,
            allowNull: true,
            defaultValue: 0,
        },
        dailyPostsCount: {
            type: DataTypes.INTEGER,
            allowNull: true,
            defaultValue: 0,
        },
        lastActivityDate: {
            type: DataTypes.DATE,
            allowNull: true,
        },
    },
    {
        sequelize,
        tableName: 'user_profiles',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['user_id'], unique: true },
            { fields: ['city'] },
        ],
    }
);

export default UserProfile;
