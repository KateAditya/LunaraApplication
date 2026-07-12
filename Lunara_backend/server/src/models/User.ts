import { Model, DataTypes, Optional } from 'sequelize';
import sequelize from '../config/database';
import bcrypt from 'bcryptjs';

// User role enum
export enum UserRole {
    CUSTOMER = 'customer',
    VENUE_OWNER = 'venue_owner',
    ADMIN = 'admin',
}

// User attributes interface
export interface UserAttributes {
    id: string;
    email: string;
    phone: string;
    passwordHash: string;
    firstName: string;
    lastName: string;
    dateOfBirth: Date;
    role: UserRole;
    isVerified: boolean;
    isActive: boolean;
    mfaEnabled: boolean;
    mfaSecret?: string | null;
    profileImageUrl?: string;
    createdAt?: Date;
    updatedAt?: Date;
    lastLoginAt?: Date;
    isOnline: boolean;
    lastActiveAt?: Date;
    noShowCount: number;
    fcmToken?: string | null;
    clearedNotificationsAt?: Date | null;
    blockCount: number;
    isAutoblocked: boolean;
    autoblockedReason?: string | null;
}

// Creation attributes (optional fields)
export interface UserCreationAttributes
    extends Optional<UserAttributes, 'id' | 'isVerified' | 'isActive' | 'isOnline' | 'mfaEnabled' | 'mfaSecret' | 'profileImageUrl' | 'createdAt' | 'updatedAt' | 'lastLoginAt' | 'lastActiveAt' | 'noShowCount' | 'fcmToken' | 'clearedNotificationsAt' | 'blockCount' | 'isAutoblocked' | 'autoblockedReason'> { }

// User model class
class User extends Model<UserAttributes, UserCreationAttributes> implements UserAttributes {
    public id!: string;
    public email!: string;
    public phone!: string;
    public passwordHash!: string;
    public firstName!: string;
    public lastName!: string;
    public dateOfBirth!: Date;
    public role!: UserRole;
    public isVerified!: boolean;
    public isActive!: boolean;
    public mfaEnabled!: boolean;
    public mfaSecret?: string | null;
    public profileImageUrl?: string;
    public readonly createdAt!: Date;
    public readonly updatedAt!: Date;
    public lastLoginAt?: Date;
    public isOnline!: boolean;
    public lastActiveAt?: Date;
    public noShowCount!: number;
    public fcmToken?: string | null;
    public clearedNotificationsAt?: Date | null;
    public blockCount!: number;
    public isAutoblocked!: boolean;
    public autoblockedReason?: string | null;

    // Instance methods
    public async comparePassword(password: string): Promise<boolean> {
        return bcrypt.compare(password, this.passwordHash);
    }

    public getFullName(): string {
        return `${this.firstName} ${this.lastName}`;
    }

    public getAge(): number {
        const today = new Date();
        const birthDate = new Date(this.dateOfBirth);
        let age = today.getFullYear() - birthDate.getFullYear();
        const monthDiff = today.getMonth() - birthDate.getMonth();

        if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
            age--;
        }

        return age;
    }

    public isAdult(): boolean {
        return this.getAge() >= parseInt(process.env.MINIMUM_AGE || '18');
    }

    // Convert to safe JSON (exclude password)
    public toJSON(): Partial<UserAttributes> {
        const values = { ...this.get() };
        delete (values as any).passwordHash;
        return values;
    }
}

// Initialize model
User.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        email: {
            type: DataTypes.STRING(255),
            allowNull: false,
            unique: true,
            validate: {
                isEmail: {
                    msg: 'Must be a valid email address',
                },
            },
        },
        phone: {
            type: DataTypes.STRING(20),
            allowNull: false,
            unique: true,
            validate: {
                is: {
                    args: /^[6-9]\d{9}$/,
                    msg: 'Must be a valid Indian phone number',
                },
            },
        },
        passwordHash: {
            type: DataTypes.STRING(255),
            allowNull: false,
            field: 'password_hash',
        },
        firstName: {
            type: DataTypes.STRING(100),
            allowNull: false,
            field: 'first_name',
            validate: {
                len: {
                    args: [2, 100],
                    msg: 'First name must be between 2 and 100 characters',
                },
            },
        },
        lastName: {
            type: DataTypes.STRING(100),
            allowNull: false,
            field: 'last_name',
            validate: {
                len: {
                    args: [1, 100],
                    msg: 'Last name must be between 1 and 100 characters',
                },
            },
        },
        dateOfBirth: {
            type: DataTypes.DATEONLY,
            allowNull: false,
            field: 'date_of_birth',
            validate: {
                isDate: true,
                isBefore: new Date().toISOString().split('T')[0],
            },
        },
        role: {
            type: DataTypes.ENUM(...Object.values(UserRole)),
            allowNull: false,
            defaultValue: UserRole.CUSTOMER,
        },
        isVerified: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_verified',
        },
        isActive: {
            type: DataTypes.BOOLEAN,
            defaultValue: true,
            field: 'is_active',
        },
        mfaEnabled: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'mfa_enabled',
        },
        mfaSecret: {
            type: DataTypes.STRING(255),
            allowNull: true,
            field: 'mfa_secret',
        },
        profileImageUrl: {
            type: DataTypes.STRING(500),
            allowNull: true,
            field: 'profile_image_url',
        },
        lastLoginAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'last_login_at',
        },
        isOnline: {
            type: DataTypes.BOOLEAN,
            defaultValue: false,
            field: 'is_online',
        },
        lastActiveAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'last_active_at',
        },
        noShowCount: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            field: 'no_show_count',
        },
        fcmToken: {
            type: DataTypes.STRING(500),
            allowNull: true,
            field: 'fcm_token',
        },
        clearedNotificationsAt: {
            type: DataTypes.DATE,
            allowNull: true,
            defaultValue: null,
            field: 'cleared_notifications_at',
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
    },
    {
        sequelize,
        tableName: 'users',
        underscored: true,
        timestamps: true,
        indexes: [
            { fields: ['email'] },
            { fields: ['phone'] },
            { fields: ['role'] },
        ],
    }
);

// Hooks
User.beforeCreate(async (user) => {
    if (user.passwordHash && !user.passwordHash.startsWith('$2')) {
        // Only hash if it's not already hashed
        user.passwordHash = await bcrypt.hash(user.passwordHash, 10);
    }
});

User.beforeUpdate(async (user) => {
    if (user.changed('passwordHash') && !user.passwordHash.startsWith('$2')) {
        user.passwordHash = await bcrypt.hash(user.passwordHash, 10);
    }
});

export default User;
