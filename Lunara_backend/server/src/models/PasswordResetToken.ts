import { Model, DataTypes, Optional, Op } from 'sequelize';
import sequelize from '../config/database';
import crypto from 'crypto';

// PasswordResetToken attributes
export interface PasswordResetTokenAttributes {
    id: string;
    userId: string;
    token: string;
    expiresAt: Date;
    usedAt?: Date;
    createdAt?: Date;
}

export interface PasswordResetTokenCreationAttributes
    extends Optional<PasswordResetTokenAttributes, 'id' | 'usedAt' | 'createdAt'> { }

class PasswordResetToken
    extends Model<PasswordResetTokenAttributes, PasswordResetTokenCreationAttributes>
    implements PasswordResetTokenAttributes {
    public id!: string;
    public userId!: string;
    public token!: string;
    public expiresAt!: Date;
    public usedAt?: Date;
    public readonly createdAt!: Date;

    // Instance methods
    public isExpired(): boolean {
        return new Date() > this.expiresAt;
    }

    public isUsed(): boolean {
        return this.usedAt !== null && this.usedAt !== undefined;
    }

    public isValid(): boolean {
        return !this.isExpired() && !this.isUsed();
    }

    // Static methods
    public static async generateToken(userId: string): Promise<PasswordResetToken> {
        // Generate secure random token
        const rawToken = crypto.randomBytes(32).toString('hex');

        // Hash token before storing
        const hashedToken = crypto.createHash('sha256').update(rawToken).digest('hex');

        // Token expires in 15 minutes
        const expiresAt = new Date();
        expiresAt.setMinutes(expiresAt.getMinutes() + parseInt(process.env.RESET_TOKEN_EXPIRY_MINUTES || '15'));

        // Invalidate any existing unused tokens for this user
        await PasswordResetToken.destroy({
            where: { userId, usedAt: { [Op.is]: null as any } },
        });

        const resetToken = await PasswordResetToken.create({
            userId,
            token: hashedToken,
            expiresAt,
        });

        // Return raw token for email (only time it's available unhashed)
        (resetToken as any).rawToken = rawToken;
        return resetToken;
    }

    public static async verifyToken(rawToken: string): Promise<PasswordResetToken | null> {
        const hashedToken = crypto.createHash('sha256').update(rawToken).digest('hex');

        const token = await PasswordResetToken.findOne({
            where: { token: hashedToken },
        });

        if (!token || !token.isValid()) {
            return null;
        }

        return token;
    }

    public async markAsUsed(): Promise<void> {
        this.usedAt = new Date();
        await this.save();
    }
}

PasswordResetToken.init(
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
        token: {
            type: DataTypes.STRING(255),
            allowNull: false,
            unique: true,
        },
        expiresAt: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'expires_at',
        },
        usedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'used_at',
        },
    },
    {
        sequelize,
        tableName: 'password_reset_tokens',
        underscored: true,
        timestamps: true,
        updatedAt: false,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['token'], unique: true },
            { fields: ['expires_at'] },
        ],
    }
);

export default PasswordResetToken;
