import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

// UserPreference attributes
export interface UserPreferenceAttributes {
    id: string;
    userId: string;
    preferredVenues?: string[];
    preferredCrowdSize?: string;
    musicPreference?: string[];
    drinkPreference?: string[];
    smokingPreference?: string;
    preferredGenders?: string[];
    minAgePreference?: number;
    maxAgePreference?: number;
    minBudget?: number;
    maxBudget?: number;
    budgetRange?: string;
    partyTimePreference?: string;
    groupSizePreference?: string;
    matchDistanceKm: number;
    showMeInMatching: boolean;
    bookingAlertsEnabled: boolean;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface UserPreferenceCreationAttributes
    extends Optional<
        UserPreferenceAttributes,
        | 'id'
        | 'preferredVenues'
        | 'preferredCrowdSize'
        | 'musicPreference'
        | 'drinkPreference'
        | 'smokingPreference'
        | 'preferredGenders'
        | 'minAgePreference'
        | 'maxAgePreference'
        | 'minBudget'
        | 'maxBudget'
        | 'budgetRange'
        | 'partyTimePreference'
        | 'groupSizePreference'
        | 'matchDistanceKm'
        | 'showMeInMatching'
        | 'bookingAlertsEnabled'
        | 'createdAt'
        | 'updatedAt'
    > { }

class UserPreference
    extends Model<UserPreferenceAttributes, UserPreferenceCreationAttributes>
    implements UserPreferenceAttributes {
    public id!: string;
    public userId!: string;
    public preferredVenues?: string[];
    public preferredCrowdSize?: string;
    public musicPreference?: string[];
    public drinkPreference?: string[];
    public smokingPreference?: string;
    public preferredGenders?: string[];
    public minAgePreference?: number;
    public maxAgePreference?: number;
    public minBudget?: number;
    public maxBudget?: number;
    public budgetRange?: string;
    public partyTimePreference?: string;
    public groupSizePreference?: string;
    public matchDistanceKm!: number;
    public showMeInMatching!: boolean;
    public bookingAlertsEnabled!: boolean;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;

    // Predefined options
    public static VenueCategories = ['pub', 'club', 'hotel', 'lounge'];
    public static CrowdSizes = ['intimate', 'moderate', 'large'];
    public static BudgetRanges = ['budget', 'moderate', 'premium', 'luxury'];
    public static PartyTimes = ['early_evening', 'peak_hours', 'late_night'];
    public static GroupSizes = ['solo', 'couple', 'small_group', 'large_group'];

    public static MusicGenres = [
        'edm', 'techno', 'house', 'trance',
        'hip_hop', 'rap', 'r_and_b',
        'rock', 'indie', 'alternative',
        'pop', 'commercial',
        'bollywood', 'punjabi', 'desi',
        'latin', 'reggae', 'afrobeats',
        'jazz', 'blues', 'soul',
        'retro', 'classics', '80s_90s',
    ];

    public static DrinkTypes = [
        'cocktails', 'mocktails',
        'beer', 'craft_beer',
        'wine', 'champagne',
        'whiskey', 'vodka', 'rum', 'gin',
        'shots', 'shooters',
        'none', // non-drinkers
    ];

    // Instance methods
    public isConfigured(): boolean {
        return !!(
            this.musicPreference && this.musicPreference.length > 0 &&
            this.drinkPreference && this.drinkPreference.length > 0 &&
            this.budgetRange
        );
    }

    public getMatchingScore(otherPreference: UserPreference): number {
        let score = 0;
        let totalWeight = 0;

        // Music preference match (weight: 20)
        const weight1 = 20;
        if (this.musicPreference && otherPreference.musicPreference) {
            const commonMusic = this.musicPreference.filter((m) =>
                otherPreference.musicPreference!.includes(m)
            );
            score += (commonMusic.length / Math.max(this.musicPreference.length, 1)) * weight1;
        }
        totalWeight += weight1;

        // Venue preference match (weight: 25)
        const weight2 = 25;
        if (this.preferredVenues && otherPreference.preferredVenues) {
            const commonVenues = this.preferredVenues.filter((v) =>
                otherPreference.preferredVenues!.includes(v)
            );
            score += (commonVenues.length / Math.max(this.preferredVenues.length, 1)) * weight2;
        }
        totalWeight += weight2;

        // Budget match (weight: 15)
        const weight3 = 15;
        if (this.budgetRange === otherPreference.budgetRange) {
            score += weight3;
        }
        totalWeight += weight3;

        // Crowd size match (weight: 10)
        const weight4 = 10;
        if (this.preferredCrowdSize === otherPreference.preferredCrowdSize) {
            score += weight4;
        }
        totalWeight += weight4;

        // Party time match (weight: 10)
        const weight5 = 10;
        if (this.partyTimePreference === otherPreference.partyTimePreference) {
            score += weight5;
        }
        totalWeight += weight5;

        // Drink preference match (weight: 10)
        const weight6 = 10;
        if (this.drinkPreference && otherPreference.drinkPreference) {
            const commonDrinks = this.drinkPreference.filter((d) =>
                otherPreference.drinkPreference!.includes(d)
            );
            score += (commonDrinks.length / Math.max(this.drinkPreference.length, 1)) * weight6;
        }
        totalWeight += weight6;

        // Group size match (weight: 10)
        const weight7 = 10;
        if (this.groupSizePreference === otherPreference.groupSizePreference) {
            score += weight7;
        }
        totalWeight += weight7;

        return totalWeight > 0 ? Math.round((score / totalWeight) * 100) : 0;
    }
}

UserPreference.init(
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
        preferredVenues: {
            type: DataTypes.ARRAY(DataTypes.STRING),
            allowNull: true,
            defaultValue: [],
            field: 'preferred_venues',
        },
        preferredCrowdSize: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'preferred_crowd_size',
        },
        musicPreference: {
            type: DataTypes.ARRAY(DataTypes.STRING),
            allowNull: true,
            defaultValue: [],
            field: 'music_preference',
        },
        drinkPreference: {
            type: DataTypes.ARRAY(DataTypes.STRING),
            allowNull: true,
            defaultValue: [],
            field: 'drink_preference',
        },
        smokingPreference: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'smoking_preference',
        },
        preferredGenders: {
            type: DataTypes.ARRAY(DataTypes.STRING),
            allowNull: true,
            defaultValue: [],
            field: 'preferred_genders',
        },
        minAgePreference: {
            type: DataTypes.INTEGER,
            allowNull: true,
            defaultValue: 18,
            field: 'min_age_preference',
        },
        maxAgePreference: {
            type: DataTypes.INTEGER,
            allowNull: true,
            defaultValue: 60,
            field: 'max_age_preference',
        },
        minBudget: {
            type: DataTypes.INTEGER,
            allowNull: true,
            field: 'min_budget',
        },
        maxBudget: {
            type: DataTypes.INTEGER,
            allowNull: true,
            field: 'max_budget',
        },
        budgetRange: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'budget_range',
        },
        partyTimePreference: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'party_time_preference',
        },
        groupSizePreference: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'group_size_preference',
        },
        matchDistanceKm: {
            type: DataTypes.INTEGER,
            defaultValue: 10,
            field: 'match_distance_km',
            validate: {
                min: 1,
                max: 100,
            },
        },
        showMeInMatching: {
            type: DataTypes.BOOLEAN,
            defaultValue: true,
            field: 'show_me_in_matching',
        },
        bookingAlertsEnabled: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'booking_alerts_enabled',
        },
    },
    {
        sequelize,
        tableName: 'user_preferences',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['user_id'], unique: true },
            { fields: ['show_me_in_matching'] },
        ],
    }
);

export default UserPreference;
