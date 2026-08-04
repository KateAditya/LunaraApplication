import { Model, DataTypes, Optional, Op } from 'sequelize';
import sequelize from '../config/database';
import crypto from 'crypto';

// OTP purpose enum
export enum OTPPurpose {
    REGISTRATION = 'registration',
    LOGIN = 'login',
    VERIFICATION = 'verification',
    PASSWORD_RESET = 'password_reset',
}

// OTPVerification attributes
export interface OTPVerificationAttributes {
    id: string;
    phone: string;
    otpCode: string;
    purpose: OTPPurpose;
    verifiedAt?: Date;
    expiresAt: Date;
    attempts: number;
    createdAt?: Date;
}

export interface OTPVerificationCreationAttributes
    extends Optional<OTPVerificationAttributes, 'id' | 'verifiedAt' | 'attempts' | 'createdAt'> { }

class OTPVerification
    extends Model<OTPVerificationAttributes, OTPVerificationCreationAttributes>
    implements OTPVerificationAttributes {
    public id!: string;
    public phone!: string;
    public otpCode!: string;
    public purpose!: OTPPurpose;
    public verifiedAt?: Date;
    public expiresAt!: Date;
    public attempts!: number;
    public readonly createdAt!: Date;

    // Instance methods
    public isExpired(): boolean {
        return new Date() > this.expiresAt;
    }

    public isVerified(): boolean {
        return this.verifiedAt !== null && this.verifiedAt !== undefined;
    }

    public isLocked(): boolean {
        const maxAttempts = parseInt(process.env.OTP_MAX_ATTEMPTS || '3');
        return this.attempts >= maxAttempts;
    }

    public isValid(): boolean {
        return !this.isExpired() && !this.isVerified() && !this.isLocked();
    }

    public async incrementAttempts(): Promise<void> {
        this.attempts += 1;
        await this.save();
    }

    // Static methods
    public static async generateOTP(
        phone: string,
        purpose: OTPPurpose
    ): Promise<{ otp: OTPVerification; code: string }> {
        const cleanPhone = phone.replace(/\D/g, '').slice(-10);

        // Generate 4-digit OTP
        const rawCode = Math.floor(1000 + Math.random() * 9000).toString();

        // Hash OTP before storing
        const hashedCode = crypto.createHash('sha256').update(rawCode).digest('hex');

        // OTP expires in 5 minutes
        const expiresAt = new Date();
        const expiryMinutes = parseInt(process.env.OTP_EXPIRY_MINUTES || '5');
        expiresAt.setMinutes(expiresAt.getMinutes() + expiryMinutes);

        // Delete any existing unverified OTPs for this phone/purpose
        await OTPVerification.destroy({
            where: { phone: cleanPhone, purpose, verifiedAt: { [Op.is]: null } as any },
        });

        const otp = await OTPVerification.create({
            phone: cleanPhone,
            otpCode: hashedCode,
            purpose,
            expiresAt,
            attempts: 0,
        });

        return { otp, code: rawCode };
    }

    public static async verifyOTP(
        phone: string,
        rawCode: string,
        purpose?: OTPPurpose
    ): Promise<{ success: boolean; message: string; otp?: OTPVerification }> {
        const cleanPhone = phone.replace(/\D/g, '').slice(-10);
        const hashedCode = crypto.createHash('sha256').update(rawCode).digest('hex');

        let otp = purpose
            ? await OTPVerification.findOne({
                where: { phone: cleanPhone, purpose },
                order: [['createdAt', 'DESC']],
              })
            : null;

        if (!otp) {
            otp = await OTPVerification.findOne({
                where: { phone: cleanPhone },
                order: [['createdAt', 'DESC']],
            });
        }

        if (!otp) {
            return { success: false, message: 'OTP not found. Please request a new one.' };
        }

        if (otp.isVerified()) {
            return { success: false, message: 'OTP already used.' };
        }

        if (otp.isExpired()) {
            return { success: false, message: 'OTP expired. Please request a new one.' };
        }

        if (otp.isLocked()) {
            return { success: false, message: 'Too many attempts. Please request a new OTP.' };
        }

        // Check if OTP matches
        if (otp.otpCode !== hashedCode) {
            await otp.incrementAttempts();
            const remaining = parseInt(process.env.OTP_MAX_ATTEMPTS || '3') - otp.attempts;
            return {
                success: false,
                message: `Invalid OTP. ${remaining} attempt${remaining !== 1 ? 's' : ''} remaining.`,
            };
        }

        // Mark as verified
        otp.verifiedAt = new Date();
        await otp.save();

        return { success: true, message: 'OTP verified successfully.', otp };
    }
}

OTPVerification.init(
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true,
        },
        phone: {
            type: DataTypes.STRING(20),
            allowNull: false,
            validate: {
                is: /^[6-9]\d{9}$/,
            },
        },
        otpCode: {
            type: DataTypes.STRING(255),
            allowNull: false,
            field: 'otp_code',
        },
        purpose: {
            type: DataTypes.ENUM(...Object.values(OTPPurpose)),
            allowNull: false,
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
        attempts: {
            type: DataTypes.INTEGER,
            defaultValue: 0,
            validate: {
                min: 0,
            },
        },
    },
    {
        sequelize,
        tableName: 'otp_verifications',
        underscored: true,
        timestamps: true,
        updatedAt: false,
        indexes: [
            { fields: ['phone'] },
            { fields: ['phone', 'purpose'] },
            { fields: ['expires_at'] },
        ],
    }
);

export default OTPVerification;
