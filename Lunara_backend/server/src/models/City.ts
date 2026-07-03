import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

export interface CityAttributes {
    id: string;
    name: string;
    state: string | null;
    isActive: boolean;
    displayOrder: number;
    createdAt?: Date;
    updatedAt?: Date;
}

export interface CityCreationAttributes
    extends Optional<CityAttributes, 'id' | 'state' | 'isActive' | 'displayOrder' | 'createdAt' | 'updatedAt'> {}

class City
    extends Model<CityAttributes, CityCreationAttributes>
    implements CityAttributes {
    public id!: string;
    public name!: string;
    public state!: string | null;
    public isActive!: boolean;
    public displayOrder!: number;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

City.init(
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
                notEmpty: { msg: 'City name is required' },
                len: { args: [2, 100], msg: 'City name must be between 2 and 100 characters' },
            },
        },
        state: {
            type: DataTypes.STRING(100),
            allowNull: true,
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
        tableName: 'cities',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['name'], unique: true },
            { fields: ['is_active'] },
            { fields: ['display_order'] },
        ],
    }
);

export default City;
