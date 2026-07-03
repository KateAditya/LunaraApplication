import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

// UserInterest attributes
export interface UserInterestAttributes {
    id: string;
    userId: string;
    category: string;
    interest: string;
    proficiencyLevel?: string;
    createdAt?: Date;
}

export interface UserInterestCreationAttributes
    extends Optional<UserInterestAttributes, 'id' | 'proficiencyLevel' | 'createdAt'> { }

class UserInterest
    extends Model<UserInterestAttributes, UserInterestCreationAttributes>
    implements UserInterestAttributes {
    public id!: string;
    public userId!: string;
    public category!: string;
    public interest!: string;
    public proficiencyLevel?: string;
    public readonly createdAt!: Date;

    // Static methods for predefined categories
    public static InterestCategories = {
        MUSIC: 'music',
        SPORTS: 'sports',
        FOOD: 'food',
        TRAVEL: 'travel',
        LIFESTYLE: 'lifestyle',
        ENTERTAINMENT: 'entertainment',
        TECHNOLOGY: 'technology',
        ARTS: 'arts',
    };

    public static ProficiencyLevels = {
        BEGINNER: 'beginner',
        INTERMEDIATE: 'intermediate',
        EXPERT: 'expert',
    };

    public static async getInterestsByCategory(
        userId: string,
        category: string
    ): Promise<UserInterest[]> {
        return UserInterest.findAll({
            where: { userId, category },
            order: [['created_at', 'DESC']],
        });
    }

    public static async getAllInterestsForUser(userId: string): Promise<Map<string, UserInterest[]>> {
        const interests = await UserInterest.findAll({
            where: { userId },
            order: [['category', 'ASC'], ['created_at', 'DESC']],
        });

        const grouped = new Map<string, UserInterest[]>();
        interests.forEach((interest) => {
            const existing = grouped.get(interest.category) || [];
            existing.push(interest);
            grouped.set(interest.category, existing);
        });

        return grouped;
    }
}

UserInterest.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        userId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'user_id',
            references: {
                model: 'users',
                key: 'id',
            },
            onDelete: 'CASCADE',
        },
        category: {
            type: DataTypes.STRING(50),
            allowNull: false,
        },
        interest: {
            type: DataTypes.STRING(100),
            allowNull: false,
        },
        proficiencyLevel: {
            type: DataTypes.STRING(20),
            allowNull: true,
            field: 'proficiency_level',
        },
    },
    {
        sequelize,
        tableName: 'user_interests',
        underscored: true,
        timestamps: true,
        updatedAt: false,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['category'] },
            { fields: ['user_id', 'category'] },
        ],
    }
);

export default UserInterest;
