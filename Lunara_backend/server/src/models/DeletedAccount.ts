import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';

// ─────────────────────────────────────────────────────────────────────────────
// Deleted Account Archive Model
// Stores a SNAPSHOT of user data at the time of deletion so admins can always
// retrieve full details even after the user record has been soft-deleted.
// ─────────────────────────────────────────────────────────────────────────────

export interface DeletedAccountAttributes {
    id: string;

    // Original user ID — kept so admin can cross-reference with other tables
    originalUserId: string;

    // Core identity snapshot
    email: string;
    phone: string;
    firstName: string;
    lastName: string;
    dateOfBirth: Date;
    role: string;
    gender?: string | null;
    city?: string | null;
    bio?: string | null;
    profileImageUrl?: string | null;
    occupation?: string | null;
    education?: string | null;

    // Account stats at time of deletion
    isVerified: boolean;
    blockCount: number;
    isAutoblocked: boolean;
    autoblockedReason?: string | null;
    noShowCount: number;
    lastLoginAt?: Date | null;
    registeredAt?: Date | null;

    // Deletion metadata
    deletionReason?: string | null;   // User-provided reason
    deletedByUser: boolean;           // true = self-deleted, false = admin-deleted
    adminNotes?: string | null;       // Admin can add notes post-deletion
    ipAddress?: string | null;        // IP at time of deletion request

    // Counts snapshot
    bookingsCount: number;
    subscriptionsCount: number;
    photosCount: number;

    createdAt?: Date;
    updatedAt?: Date;
}

export interface DeletedAccountCreationAttributes
    extends Optional<
        DeletedAccountAttributes,
        | 'id'
        | 'gender'
        | 'city'
        | 'bio'
        | 'profileImageUrl'
        | 'occupation'
        | 'education'
        | 'autoblockedReason'
        | 'deletionReason'
        | 'adminNotes'
        | 'ipAddress'
        | 'lastLoginAt'
        | 'registeredAt'
        | 'createdAt'
        | 'updatedAt'
    > {}

class DeletedAccount extends Model<DeletedAccountAttributes, DeletedAccountCreationAttributes>
    implements DeletedAccountAttributes {
    public id!: string;
    public originalUserId!: string;
    public email!: string;
    public phone!: string;
    public firstName!: string;
    public lastName!: string;
    public dateOfBirth!: Date;
    public role!: string;
    public gender?: string | null;
    public city?: string | null;
    public bio?: string | null;
    public profileImageUrl?: string | null;
    public occupation?: string | null;
    public education?: string | null;
    public isVerified!: boolean;
    public blockCount!: number;
    public isAutoblocked!: boolean;
    public autoblockedReason?: string | null;
    public noShowCount!: number;
    public lastLoginAt?: Date | null;
    public registeredAt?: Date | null;
    public deletionReason?: string | null;
    public deletedByUser!: boolean;
    public adminNotes?: string | null;
    public ipAddress?: string | null;
    public bookingsCount!: number;
    public subscriptionsCount!: number;
    public photosCount!: number;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
}

DeletedAccount.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        originalUserId: {
            type: DataTypes.UUID,
            allowNull: false,
            field: 'original_user_id',
            comment: 'References users.id — kept for cross-table lookups',
        },
        email: {
            type: DataTypes.STRING(255),
            allowNull: false,
        },
        phone: {
            type: DataTypes.STRING(20),
            allowNull: false,
        },
        firstName: {
            type: DataTypes.STRING(100),
            allowNull: false,
            field: 'first_name',
        },
        lastName: {
            type: DataTypes.STRING(100),
            allowNull: false,
            field: 'last_name',
        },
        dateOfBirth: {
            type: DataTypes.DATEONLY,
            allowNull: false,
            field: 'date_of_birth',
        },
        role: {
            type: DataTypes.STRING(20),
            allowNull: false,
        },
        gender: {
            type: DataTypes.STRING(30),
            allowNull: true,
        },
        city: {
            type: DataTypes.STRING(100),
            allowNull: true,
        },
        bio: {
            type: DataTypes.TEXT,
            allowNull: true,
        },
        profileImageUrl: {
            type: DataTypes.STRING(500),
            allowNull: true,
            field: 'profile_image_url',
        },
        occupation: {
            type: DataTypes.STRING(100),
            allowNull: true,
        },
        education: {
            type: DataTypes.STRING(200),
            allowNull: true,
        },
        isVerified: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_verified',
        },
        blockCount: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'block_count',
        },
        isAutoblocked: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_autoblocked',
        },
        autoblockedReason: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'autoblocked_reason',
        },
        noShowCount: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'no_show_count',
        },
        lastLoginAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'last_login_at',
        },
        registeredAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'registered_at',
        },
        deletionReason: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'deletion_reason',
        },
        deletedByUser: {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: true,
            field: 'deleted_by_user',
        },
        adminNotes: {
            type: DataTypes.TEXT,
            allowNull: true,
            field: 'admin_notes',
        },
        ipAddress: {
            type: DataTypes.STRING(50),
            allowNull: true,
            field: 'ip_address',
        },
        bookingsCount: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'bookings_count',
        },
        subscriptionsCount: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'subscriptions_count',
        },
        photosCount: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'photos_count',
        },
    },
    {
        sequelize,
        tableName: 'deleted_accounts',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['original_user_id'] },
            { fields: ['email'] },
            { fields: ['phone'] },
            { fields: ['created_at'] },
        ],
    }
);

export default DeletedAccount;
