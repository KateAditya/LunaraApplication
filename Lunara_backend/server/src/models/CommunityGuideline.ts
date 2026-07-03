import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface CommunityGuidelineAttributes {
    id: string;
    title: string;
    content: string;
    category: string;
    isActive: boolean;
    displayOrder: number;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface CommunityGuidelineCreationAttributes
    extends Optional<CommunityGuidelineAttributes, 'id' | 'isActive' | 'displayOrder' | 'createdAt' | 'updatedAt'> {}

class CommunityGuideline
    extends Model<CommunityGuidelineAttributes, CommunityGuidelineCreationAttributes>
    implements CommunityGuidelineAttributes {
    public id!: string;
    public title!: string;
    public content!: string;
    public category!: string;
    public isActive!: boolean;
    public displayOrder!: number;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

CommunityGuideline.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        title: {
            type: DataTypes.STRING(255),
            allowNull: false,
            validate: {
                notEmpty: { msg: 'Title is required' },
                len: { args: [2, 255], msg: 'Title must be between 2 and 255 characters' },
            },
        },
        content: {
            type: DataTypes.TEXT,
            allowNull: false,
            validate: {
                notEmpty: { msg: 'Content is required' },
            },
        },
        category: {
            type: DataTypes.STRING(100),
            allowNull: false,
            validate: {
                notEmpty: { msg: 'Category is required' },
            },
        },
        isActive: {
            type: DataTypes.BOOLEAN,
            defaultValue: true,
            field: 'is_active',
        },
        displayOrder: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'display_order',
        },
    },
    {
        sequelize,
        tableName: 'community_guidelines',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['category'] },
            { fields: ['is_active'] },
            { fields: ['display_order'] },
        ],
    }
);

export default CommunityGuideline;
