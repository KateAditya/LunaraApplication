import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export enum LegalDocumentType {
    TERMS_OF_SERVICE = 'terms_of_service',
    PRIVACY_POLICY = 'privacy_policy',
    REFUND_POLICY = 'refund_policy',
    OTHER = 'other',
}

export interface LegalDocumentAttributes {
    id: string;
    title: string;
    type: LegalDocumentType;
    content: string;
    version: string;
    isActive: boolean;
    effectiveDate: Date;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface LegalDocumentCreationAttributes
    extends Optional<LegalDocumentAttributes, 'id' | 'isActive' | 'createdAt' | 'updatedAt'> {}

class LegalDocument
    extends Model<LegalDocumentAttributes, LegalDocumentCreationAttributes>
    implements LegalDocumentAttributes {
    public id!: string;
    public title!: string;
    public type!: LegalDocumentType;
    public content!: string;
    public version!: string;
    public isActive!: boolean;
    public effectiveDate!: Date;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

LegalDocument.init(
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
        type: {
            type: DataTypes.STRING(50),
            allowNull: false,
            validate: {
                isIn: {
                    args: [Object.values(LegalDocumentType)],
                    msg: `Type must be one of: ${Object.values(LegalDocumentType).join(', ')}`,
                },
            },
        },
        content: {
            type: DataTypes.TEXT,
            allowNull: false,
            validate: {
                notEmpty: { msg: 'Content is required' },
            },
        },
        version: {
            type: DataTypes.STRING(20),
            allowNull: false,
            validate: {
                notEmpty: { msg: 'Version is required' },
            },
        },
        isActive: {
            type: DataTypes.BOOLEAN,
            defaultValue: true,
            field: 'is_active',
        },
        effectiveDate: {
            type: DataTypes.DATEONLY,
            allowNull: false,
            field: 'effective_date',
            validate: {
                isDate: { msg: 'Must be a valid date', args: true },
            },
        },
    },
    {
        sequelize,
        tableName: 'legal_documents',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['type'] },
            { fields: ['is_active'] },
            { fields: ['effective_date'] },
        ],
    }
);

export default LegalDocument;
