import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';
import path from 'path';
import fs from 'fs';

// Image type enum
export enum VenueImageType {
    COVER = 'cover',
    INTERIOR = 'interior',
    EXTERIOR = 'exterior',
    MENU = 'menu',
    FOOD_MENU = 'food_menu',
    BAR_MENU = 'bar_menu',
    BEVERAGE_MENU = 'beverage_menu',
    PARTY_PACKAGES = 'party_packages',
    EVENT = 'event',
    VIDEO = 'video',
}

// VenueImage attributes
export interface VenueImageAttributes {
    id: string;
    venueId: string;
    filePath: string;
    fileSize: number;
    mimeType: string;
    imageType: VenueImageType;
    caption?: string;
    isPrimary: boolean;
    displayOrder: number;
    uploadedBy: string;
    uploadedAt: Date;
    createdAt?: Date;
}

export interface VenueImageCreationAttributes
    extends Optional<
        VenueImageAttributes,
        'id' | 'caption' | 'isPrimary' | 'displayOrder' | 'uploadedAt' | 'createdAt'
    > { }

class VenueImage
    extends Model<VenueImageAttributes, VenueImageCreationAttributes>
    implements VenueImageAttributes {
    public id!: string;
    public venueId!: string;
    public filePath!: string;
    public fileSize!: number;
    public mimeType!: string;
    public imageType!: VenueImageType;
    public caption?: string;
    public isPrimary!: boolean;
    public displayOrder!: number;
    public uploadedBy!: string;
    public uploadedAt!: Date;
    public readonly createdAt!: Date;

    // Instance methods
    public getFullPath(): string {
        return path.join(process.cwd(), this.filePath);
    }

    public getUrl(): string {
        // Forward slashes for URLs, keep the directory structure intact
        const normalizedPath = this.filePath.replace(/\\/g, '/');
        return `/${normalizedPath}`;
    }

    public async deleteFile(): Promise<void> {
        const fullPath = this.getFullPath();
        if (fs.existsSync(fullPath)) {
            fs.unlinkSync(fullPath);
        }
    }

    // Static methods
    public static async setAsPrimary(imageId: string, venueId: string): Promise<void> {
        await VenueImage.update({ isPrimary: false }, { where: { venueId } });
        await VenueImage.update({ isPrimary: true }, { where: { id: imageId, venueId } });
    }

    public static async getImagesByType(
        venueId: string,
        imageType: VenueImageType
    ): Promise<VenueImage[]> {
        return VenueImage.findAll({
            where: { venueId, imageType },
            order: [['displayOrder', 'ASC'], ['uploadedAt', 'DESC']],
        });
    }
}

VenueImage.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        venueId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'venue_id',
            references: {
                model: 'venues',
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
        },
        mimeType: {
            type: DataTypes.STRING(50),
            allowNull: false,
            field: 'mime_type',
        },
        imageType: {
            type: DataTypes.ENUM(...Object.values(VenueImageType)),
            allowNull: false,
            field: 'image_type',
        },
        caption: {
            type: DataTypes.STRING(255),
            allowNull: true,
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
        uploadedBy: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'uploaded_by',
            references: {
                model: 'users',
                key: 'id',
            },
        },
        uploadedAt: {
            type: DataTypes.DATE,
            defaultValue: DataTypes.NOW,
            field: 'uploaded_at',
        },
    },
    {
        sequelize,
        tableName: 'venue_images',
        underscored: true,
        timestamps: true,
        updatedAt: false,
        indexes: [
            { fields: ['venue_id'] },
            { fields: ['image_type'] },
            { fields: ['venue_id', 'is_primary'] },
        ],
    }
);

VenueImage.beforeDestroy(async (image) => {
    await image.deleteFile();
});

export default VenueImage;
