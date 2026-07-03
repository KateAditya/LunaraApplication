import { Model, DataTypes, Optional, Op } from 'sequelize';
import sequelize from '../config/database';
import crypto from 'crypto';

// EmailVerification attributes
export interface EmailVerificationAttributes {
    id: string;
    userId: string;
    token: string;
    verifiedAt?: Date;
    expiresAt: Date;
    createdAt?: Date;
}

export interface EmailVerificationCreationAttributes
    extends Optional<EmailVerificationAttributes, 'id' | 'verifiedAt' | 'createdAt'> { }

class EmailVerification
    extends Model<EmailVerificationAttributes, EmailVerificationCreationAttributes>
    implements EmailVerificationAttributes {
    public id!: string;
    public userId!: string;
    public token!: string;
    public verifiedAt?: Date;
    public expiresAt!: Date;
    public readonly createdAt!: Date;

    // Instance methods
    public isExpired(): boolean {
        return new Date() > this.expiresAt;
    }

    public isVerified(): boolean {
        return this.verifiedAt !== null && this.verifiedAt !== undefined;
    }

    public isValid(): boolean {
        return !this.isExpired() && !this.isVerified();
    }

    // Static methods
    public static async generateToken(userId: string): Promise<EmailVerification> {
        // Generate secure random token
        const rawToken = crypto.randomBytes(32).toString('hex');

        // Hash token before storing
        const hashedToken = crypto.createHash('sha256').update(rawToken).digest('hex');

        // Token expires in 24 hours
        const expiresAt = new Date();
        const expiryHours = parseInt(process.env.EMAIL_VERIFICATION_EXPIRY_HOURS || '24');
        expiresAt.setHours(expiresAt.getHours() + expiryHours);

        // Delete any existing unverified tokens for this user
        await EmailVerification.destroy({
            where: { userId, verifiedAt: { [Op.is]: null as any } },
        });

        const verification = await EmailVerification.create({
            userId,
            token: hashedToken,
            expiresAt,
        });

        // Return raw token for email (only time it's available unhashed)
        (verification as any).rawToken = rawToken;
        return verification;
    }

    public static async verifyToken(rawToken: string): Promise<EmailVerification | null> {
        const hashedToken = crypto.createHash('sha256').update(rawToken).digest('hex');

        const verification = await EmailVerification.findOne({
            where: { token: hashedToken },
        });

        if (!verification || !verification.isValid()) {
            return null;
        }

        return verification;
    }

    public async markAsVerified(): Promise<void> {
        this.verifiedAt = new Date();
        await this.save();
    }
}

EmailVerification.init(
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
        verifiedAt: {
            type: DataTypes.DATE,
            allowNull: true,
            field: 'verified_at',
        },
        expiresAt: {
            type: DataTypes.DATE,
            allowNull: false,
            field: 'expires_at',
        },
    },
    {
        sequelize,
        tableName: 'email_verifications',
        underscored: true,
        timestamps: true,
        updatedAt: false,
        indexes: [
            { fields: ['user_id'] },
            { fields: ['token'], unique: true },
        ],
    }
);

export default EmailVerification;
