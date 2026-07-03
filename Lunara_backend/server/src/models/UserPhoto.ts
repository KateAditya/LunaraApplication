import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';
import path from 'path';
import fs from 'fs';

// UserPhoto attributes
export interface UserPhotoAttributes {
    id: string;
    userId: string;
    filePath: string;
    fileSize: number;
    mimeType: string;
    isPrimary: boolean;
    displayOrder: number;
    uploadedAt: Date;
    createdAt?: Date;
}

export interface UserPhotoCreationAttributes
    extends Optional<UserPhotoAttributes, 'id' | 'isPrimary' | 'displayOrder' | 'uploadedAt' | 'createdAt'> { }

class UserPhoto extends Model<UserPhotoAttributes, UserPhotoCreationAttributes> implements UserPhotoAttributes {
    public id!: string;
    public userId!: string;
    public filePath!: string;
    public fileSize!: number;
    public mimeType!: string;
    public isPrimary!: boolean;
    public displayOrder!: number;
    public uploadedAt!: Date;
    public readonly createdAt!: Date;

    // Instance methods
    public getFullPath(): string {
        return path.join(process.cwd(), this.filePath);
    }

    public getUrl(): string {
        // Return URL for serving the image
        return '/' + this.filePath.replace(/\\/g, '/');
    }

    public async deleteFile(): Promise<void> {
        const fullPath = this.getFullPath();
        if (fs.existsSync(fullPath)) {
            fs.unlinkSync(fullPath);
        }
    }

    // Static methods
    public static async setAsPrimary(photoId: string, userId: string): Promise<void> {
        // Remove primary flag from all user photos
        await UserPhoto.update(
            { isPrimary: false },
            { where: { userId } }
        );

        // Set this photo as primary
        await UserPhoto.update(
            { isPrimary: true },
            { where: { id: photoId, userId } }
        );
    }

    public static async getPhotosForUser(userId: string): Promise<UserPhoto[]> {
        return UserPhoto.findAll({
            where: { userId },
            order: [
                ['isPrimary', 'DESC'],
                ['displayOrder', 'ASC'],
                ['uploadedAt', 'DESC'],
            ],
        });
    }

    public static async getPrimaryPhoto(userId: string): Promise<UserPhoto | null> {
        return UserPhoto.findOne({
            where: { userId, isPrimary: true },
        });
    }
}

UserPhoto.init(
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
        filePath: {
            type: DataTypes.STRING(500),
            allowNull: false,
            field: 'file_path',
        },
        fileSize: {
            type: DataTypes.INTEGER,
            allowNull: false,
            field: 'file_size',
            validate: {
                min: 0,
            },
        },
        mimeType: {
            type: DataTypes.STRING(50),
            allowNull: false,
            field: 'mime_type',
        },
        isPrimary: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_primary',
        },
        displayOrder: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'display_order',
        },
        uploadedAt: {
            type: DataTypes.DATE,
            defaultValue: DataTypes.NOW,
            field: 'uploaded_at',
        },
    },
    {
        sequelize,
        tableName: 'user_photos',
        underscored: true,
        timestamps: true,
        updatedAt: false,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['user_id', 'is_primary'] },
        ],
    }
);

// Hooks
UserPhoto.beforeDestroy(async (photo) => {
    // Delete physical file when record is deleted
    await photo.deleteFile();
});

export default UserPhoto;
