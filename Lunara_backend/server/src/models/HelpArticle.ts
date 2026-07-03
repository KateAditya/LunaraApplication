import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface HelpArticleAttributes {
    id: string;
    title: string;
    content: string;
    category: string;
    isPublished: boolean;
    displayOrder: number;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface HelpArticleCreationAttributes
    extends Optional<HelpArticleAttributes, 'id' | 'isPublished' | 'displayOrder' | 'createdAt' | 'updatedAt'> {}

class HelpArticle
    extends Model<HelpArticleAttributes, HelpArticleCreationAttributes>
    implements HelpArticleAttributes {
    public id!: string;
    public title!: string;
    public content!: string;
    public category!: string;
    public isPublished!: boolean;
    public displayOrder!: number;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

HelpArticle.init(
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
        isPublished: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_published',
        },
        displayOrder: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'display_order',
        },
    },
    {
        sequelize,
        tableName: 'help_articles',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['category'] },
            { fields: ['is_published'] },
            { fields: ['display_order'] },
        ],
    }
);

export default HelpArticle;
