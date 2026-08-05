import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface AreaAttributes {
    id: string;
    name: string;
    city: string | null;
    isActive: boolean;
    displayOrder: number;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface AreaCreationAttributes
    extends Optional<AreaAttributes, 'id' | 'city' | 'isActive' | 'displayOrder' | 'createdAt' | 'updatedAt'> {}

class Area
    extends Model<AreaAttributes, AreaCreationAttributes>
    implements AreaAttributes {
    public id!: string;
    public name!: string;
    public city!: string | null;
    public isActive!: boolean;
    public displayOrder!: number;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

Area.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        name: {
            type: DataTypes.STRING(100),
            allowNull: false,
            unique: true,
            validate: {
                notEmpty: { msg: 'Area name is required' },
                len: { args: [2, 100], msg: 'Area name must be between 2 and 100 characters' },
            },
        },
        city: {
            type: DataTypes.STRING(100),
            allowNull: true,
            defaultValue: 'Pune',
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
        tableName: 'areas',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['name'], unique: true },
            { fields: ['is_active'] },
            { fields: ['display_order'] },
        ],
    }
);

export default Area;
