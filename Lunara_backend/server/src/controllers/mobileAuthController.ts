import { Request, Response } from 'express';
import { Op } from 'sequelize';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { User, UserProfile, UserPreference, EmailVerification, OTPVerification } from '../models';
import { OTPPurpose } from '../models/OTPVerification';
import { UserRole } from '../models/User';
import { generateTokenPair } from '../utils/jwt';
import { sendVerificationEmail } from '../services/emailService';
import { azureFaceService } from '../services/azureFaceService';
import { logger } from '../config/logger';
import { SMSService } from '../services/smsService';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/** Strict email format check */
function isValidEmail(email: string): boolean {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
}

/** Indian mobile number: starts with 6-9, exactly 10 digits */
function isValidPhone(phone: string): boolean {
    return SMSService.isValidIndianMobile(phone);
}

function passwordStrengthError(password: string): string | null {
    if (password.length < 3)
        return 'Password must be at least 3 characters long';
    return null;
}

/** Calculate age from DOB string */
function calcAge(dob: string): number {
    const birth = new Date(dob);
    const today = new Date();
    let age = today.getFullYear() - birth.getFullYear();
    const m = today.getMonth() - birth.getMonth();
    if (m < 0 || (m === 0 && today.getDate() < birth.getDate())) age--;
    return age;
}

// ─────────────────────────────────────────────────────────────────────────────
// Request body type (documentation only — TypeScript won't enforce at runtime)
// ─────────────────────────────────────────────────────────────────────────────
interface MobileRegisterBody {
    firstName: string;
    lastName: string;
    email: string;
    phone: string;
    password: string;
    dateOfBirth: string;   // ISO format: YYYY-MM-DD
    gender?: string;
    city?: string;
    biometricEnabled?: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/auth/send-otp
// PUBLIC — Send dummy OTP
// ─────────────────────────────────────────────────────────────────────────────
export const mobileSendOTP = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { phone } = req.body;

        if (!phone?.trim()) {
            return res.status(400).json({ success: false, message: 'Phone number is required' });
        }

        const cleanPhone = SMSService.normalizePhone(phone);
        if (!SMSService.isValidIndianMobile(cleanPhone)) {
            return res.status(400).json({ success: false, message: 'Please enter a valid 10-digit Indian mobile number (e.g. 9876543210)' });
        }

        // Check if user already exists
        const existing = await User.findOne({ where: { phone: cleanPhone } });
        if (existing) {
            return res.status(409).json({ success: false, code: 'DUPLICATE_USER', message: 'An account with this phone number already exists' });
        }

        // Generate OTP
        const { code } = await OTPVerification.generateOTP(cleanPhone, OTPPurpose.REGISTRATION);

        // Send real SMS via True Bulk SMS API
        const smsResult = await SMSService.sendOTP(cleanPhone, code);

        logger.info(`[MobileSendOTP] Generated OTP for ${cleanPhone}: ${code}. SMS Status: ${smsResult.message}`);

        return res.status(200).json({
            success: true,
            message: `OTP sent successfully to +91 ${cleanPhone}`,
            smsSent: smsResult.success
        });
    } catch (error: any) {
        logger.error('[MobileSendOTP] Error:', error);
        return res.status(500).json({ success: false, message: 'Failed to send OTP' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/auth/check-email
// PUBLIC — Check if email is taken
// ─────────────────────────────────────────────────────────────────────────────
export const mobileCheckEmail = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { email } = req.body;
        if (!email) {
            return res.status(400).json({ success: false, message: 'Email is required' });
        }

        const existing = await User.findOne({ where: { email: email.trim().toLowerCase() } });
        if (existing) {
            return res.status(200).json({ success: true, isTaken: true, message: 'Email is already taken' });
        }

        return res.status(200).json({ success: true, isTaken: false, message: 'Email is available' });
    } catch (error: any) {
        logger.error('[MobileCheckEmail] Error:', error);
        return res.status(500).json({ success: false, message: 'Failed to check email' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/auth/verify-otp
// PUBLIC — Verify OTP
// ─────────────────────────────────────────────────────────────────────────────
export const mobileVerifyOTP = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { phone, otp, purpose } = req.body;

        if (!phone || !otp) {
            return res.status(400).json({ success: false, message: 'Phone and OTP are required' });
        }

        const cleanPhone = SMSService.normalizePhone(phone);
        if (!SMSService.isValidIndianMobile(cleanPhone)) {
            return res.status(400).json({ success: false, message: 'Invalid 10-digit Indian phone number' });
        }

        const cleanOtp = String(otp).trim();

        // Determine target purpose or default to REGISTRATION with PASSWORD_RESET fallback
        let targetPurpose = OTPPurpose.REGISTRATION;
        if (purpose && Object.values(OTPPurpose).includes(purpose as OTPPurpose)) {
            targetPurpose = purpose as OTPPurpose;
        }

        let result = await OTPVerification.verifyOTP(cleanPhone, cleanOtp, targetPurpose);

        // Fallback check for PASSWORD_RESET if purpose wasn't explicitly passed and REGISTRATION failed
        if (!result.success && !purpose) {
            const resetResult = await OTPVerification.verifyOTP(cleanPhone, cleanOtp, OTPPurpose.PASSWORD_RESET);
            if (resetResult.success) {
                result = resetResult;
            }
        }

        if (!result.success) {
            return res.status(400).json({ success: false, message: result.message });
        }

        return res.status(200).json({ success: true, message: 'OTP verified successfully' });
    } catch (error: any) {
        logger.error('[MobileVerifyOTP] Error:', error);
        return res.status(500).json({ success: false, message: 'Failed to verify OTP' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/auth/register
// PUBLIC — no authentication required
// ─────────────────────────────────────────────────────────────────────────────
export const mobileRegister = async (req: Request, res: Response): Promise<Response> => {
    try {
        const {
            firstName,
            lastName,
            email,
            phone,
            password,
            dateOfBirth,
            gender,
            city,
        } = req.body as MobileRegisterBody;

        // ── 1. Required field presence check ──────────────────────────────────
        const missing: string[] = [];
        if (!firstName?.trim()) missing.push('firstName');
        if (!lastName?.trim()) missing.push('lastName');
        if (!email?.trim()) missing.push('email');
        if (!phone?.trim()) missing.push('phone');
        if (!password) missing.push('password');
        if (!dateOfBirth?.trim()) missing.push('dateOfBirth');

        if (missing.length > 0) {
            return res.status(400).json({
                success: false,
                code: 'MISSING_FIELDS',
                message: 'Required fields are missing',
                fields: missing,
            });
        }

        const cleanPhone = SMSService.normalizePhone(phone);

        // ── 1.5. OTP Verification Check ───────────────────────────────────────
        const otpRecord = await OTPVerification.findOne({
            where: { phone: cleanPhone, purpose: OTPPurpose.REGISTRATION },
            order: [['createdAt', 'DESC']]
        });

        if (!otpRecord || !otpRecord.isVerified()) {
            return res.status(400).json({
                success: false,
                code: 'OTP_NOT_VERIFIED',
                message: 'Phone number is not verified. Please verify OTP first.'
            });
        }

        // ── 2. Format validations ─────────────────────────────────────────────
        if (!isValidEmail(email)) {
            return res.status(400).json({
                success: false,
                code: 'INVALID_EMAIL',
                message: 'Please provide a valid email address',
            });
        }

        if (!isValidPhone(cleanPhone)) {
            return res.status(400).json({
                success: false,
                code: 'INVALID_PHONE',
                message: 'Please provide a valid 10-digit Indian mobile number (starting with 6–9)',
            });
        }

        const pwdError = passwordStrengthError(password);
        if (pwdError) {
            return res.status(400).json({
                success: false,
                code: 'WEAK_PASSWORD',
                message: pwdError,
            });
        }

        // ── 3. Age verification ───────────────────────────────────────────────
        const age = calcAge(dateOfBirth);
        const minAge = parseInt(process.env.MINIMUM_AGE || '18', 10);

        if (isNaN(age) || age < 0) {
            return res.status(400).json({
                success: false,
                code: 'INVALID_DOB',
                message: 'Please provide a valid date of birth (YYYY-MM-DD)',
            });
        }

        if (age < minAge) {
            return res.status(400).json({
                success: false,
                code: 'UNDERAGE',
                message: `You must be at least ${minAge} years old to register`,
            });
        }

        // ── 4. Duplicate check (email OR phone) ───────────────────────────────
        const existing = await User.findOne({
            where: {
                [Op.or]: [
                    { email: email.trim().toLowerCase() },
                    { phone: cleanPhone },
                ],
            },
        });

        if (existing) {
            const conflict =
                existing.email === email.trim().toLowerCase() ? 'email' : 'phone';
            return res.status(409).json({
                success: false,
                code: 'DUPLICATE_USER',
                message: conflict === 'email'
                    ? 'An account with this email already exists'
                    : 'An account with this phone number already exists',
                field: conflict,
            });
        }

        // ── 5. Hash password ──────────────────────────────────────────────────
        //  The User model's beforeCreate hook also hashes, but we hash here
        //  explicitly so the model receives an already-hashed value, which the
        //  hook skips (it checks for the $2 bcrypt prefix).
        const SALT_ROUNDS = parseInt(process.env.BCRYPT_ROUNDS || '12', 10);
        const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

        // ── 6. Create user ────────────────────────────────────────────────────
        const user = await User.create({
            firstName: firstName.trim(),
            lastName: lastName.trim(),
            email: email.trim().toLowerCase(),
            phone: cleanPhone,
            passwordHash,                      // pre-hashed, hook will skip re-hash
            dateOfBirth: new Date(dateOfBirth),
            role: UserRole.CUSTOMER,
            isActive: true,
            isVerified: false,
            mfaEnabled: false,
        });

        // ── 7. Create supporting records (non-fatal if any fail) ──────────────
        await Promise.allSettled([
            UserProfile.create({
                userId: user.id,
                displayName: `${firstName.trim()} ${lastName.trim()}`,
                gender: gender?.trim(),
                city: city?.trim(),
            }),
            UserPreference.create({ userId: user.id }),
            // Delete OTP record after successful registration
            otpRecord.destroy(),
        ]);

        // ── 8. Send verification email (non-fatal) ────────────────────────────
        try {
            const verification = await EmailVerification.generateToken(user.id);
            const rawToken = (verification as any).rawToken;
            await sendVerificationEmail(user.email, rawToken, user.firstName);
            logger.info(`[MobileRegister] Verification email sent to ${user.email}`);
        } catch (emailErr: any) {
            logger.warn(`[MobileRegister] Email send skipped: ${emailErr.message}`);
        }

        // ── 9. Issue JWT token pair ───────────────────────────────────────────
        const tokens = generateTokenPair({
            userId: user.id,
            email: user.email,
            role: user.role,
        });

        logger.info(`[MobileRegister] New mobile user registered: ${user.email} | ID: ${user.id}`);

        // ── 10. Success response ──────────────────────────────────────────────
        return res.status(201).json({
            success: true,
            message: 'Registration successful. Please verify your email to unlock all features.',
            data: {
                user: user.toJSON(),     // passwordHash excluded by toJSON()
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                expiresIn: process.env.JWT_EXPIRES_IN || '7d',
            },
        });

    } catch (error: any) {
        logger.error('[MobileRegister] Error:', error);

        // Handle Sequelize unique-constraint violation (safety net)
        if (error.name === 'SequelizeUniqueConstraintError') {
            const field = error.errors?.[0]?.path || 'field';
            return res.status(409).json({
                success: false,
                code: 'DUPLICATE_USER',
                message: `An account with this ${field} already exists`,
                field,
            });
        }

        // Handle Sequelize validation errors
        if (error.name === 'SequelizeValidationError') {
            return res.status(400).json({
                success: false,
                code: 'VALIDATION_ERROR',
                message: error.errors?.[0]?.message || 'Validation failed',
            });
        }

        return res.status(500).json({
            success: false,
            code: 'SERVER_ERROR',
            message: 'Registration failed due to a server error. Please try again.',
        });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/auth/forgot-password
// ─────────────────────────────────────────────────────────────────────────────
export const mobileForgotPassword = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { phone } = req.body;

        if (!phone) {
            return res.status(400).json({ success: false, message: 'Phone number is required' });
        }

        const cleanPhone = SMSService.normalizePhone(phone);
        if (!SMSService.isValidIndianMobile(cleanPhone)) {
            return res.status(400).json({ success: false, message: 'Please enter a valid 10-digit Indian mobile number' });
        }

        // Check if user exists
        const user = await User.findOne({ where: { phone: cleanPhone } });
        if (!user) {
            return res.status(404).json({ success: false, message: 'No account found with this phone number' });
        }

        // Generate OTP
        const { code } = await OTPVerification.generateOTP(cleanPhone, OTPPurpose.PASSWORD_RESET);

        // Send real SMS via True Bulk SMS API
        const smsResult = await SMSService.sendOTP(cleanPhone, code);

        logger.info(`[MobileForgotPassword] Generated reset OTP for ${cleanPhone}: ${code}. SMS Status: ${smsResult.message}`);

        return res.status(200).json({
            success: true,
            message: `Password reset OTP sent successfully to +91 ${cleanPhone}`,
            smsSent: smsResult.success
        });
    } catch (error: any) {
        logger.error('[MobileForgotPassword] Error:', error);
        return res.status(500).json({ success: false, message: 'Failed to process forgot password request' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/auth/reset-password
// ─────────────────────────────────────────────────────────────────────────────
export const mobileResetPassword = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { phone, otp, newPassword } = req.body;

        if (!phone || !otp || !newPassword) {
            return res.status(400).json({ success: false, message: 'Phone, OTP, and new password are required' });
        }

        const cleanPhone = SMSService.normalizePhone(phone);
        const cleanOtp = String(otp).trim();

        if (newPassword.length < 3) {
            return res.status(400).json({ success: false, message: 'Password must be at least 3 characters long' });
        }

        // Find user
        const user = await User.findOne({ where: { phone: cleanPhone } });
        if (!user) {
            return res.status(404).json({ success: false, message: 'No account found with this phone number' });
        }

        // Find OTP record
        const hashedCode = crypto.createHash('sha256').update(cleanOtp).digest('hex');
        const otpRecord = await OTPVerification.findOne({
            where: { phone: cleanPhone, purpose: OTPPurpose.PASSWORD_RESET },
            order: [['createdAt', 'DESC']],
        });

        if (!otpRecord) {
            return res.status(400).json({ success: false, message: 'OTP record not found. Please request a new code.' });
        }

        if (otpRecord.isExpired()) {
            return res.status(400).json({ success: false, message: 'OTP has expired. Please request a new one.' });
        }

        // Check if code matches OR if it was verified recently (within last 15 minutes) during this reset flow
        const matchesCode = otpRecord.otpCode === hashedCode;
        const recentlyVerified = otpRecord.verifiedAt && (Date.now() - new Date(otpRecord.verifiedAt).getTime() < 15 * 60 * 1000);

        if (!matchesCode && !recentlyVerified) {
            return res.status(400).json({ success: false, code: 'INVALID_OTP', message: 'Invalid OTP code.' });
        }

        // Hash new password
        const salt = await bcrypt.genSalt(10);
        const passwordHash = await bcrypt.hash(newPassword, salt);

        // Update user
        user.passwordHash = passwordHash;
        await user.save();

        // Mark OTP as verified with current timestamp
        otpRecord.verifiedAt = new Date();
        await otpRecord.save();

        logger.info(`[MobileResetPassword] Password reset successful for user: ${user.email} / ${user.phone}`);

        return res.status(200).json({
            success: true,
            message: 'Password has been reset successfully',
        });
    } catch (error: any) {
        logger.error('[MobileResetPassword] Error:', error);
        return res.status(500).json({ success: false, message: 'Failed to reset password' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/auth/logout
// ─────────────────────────────────────────────────────────────────────────────
export const mobileLogout = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.body.userId || req.user?.id;

        if (!userId) {
            return res.status(400).json({ success: false, message: 'User ID is required' });
        }

        const user = await User.findByPk(userId);
        if (user) {
            const now = new Date();
            await user.update({ isOnline: false, lastActiveAt: now });

            try {
                const { io } = require('../server');
                io.emit('user_status_changed', { userId: user.id, isOnline: false, lastActiveAt: now });
            } catch (err) {
                logger.warn('[MobileLogout] Could not emit socket event', err);
            }
        }

        logger.info(`[MobileLogout] User logged out: ${userId}`);

        return res.status(200).json({
            success: true,
            message: 'Logged out successfully',
        });
    } catch (error: any) {
        logger.error('[MobileLogout] Error:', error);
        return res.status(500).json({ success: false, message: 'Failed to logout' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/auth/verify-face
// One-time face verification via Azure AI Face Service
// ─────────────────────────────────────────────────────────────────────────────
export const mobileVerifyFace = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { selfie, profilePhoto } = req.body;

        if (!selfie || !profilePhoto) {
            return res.status(400).json({
                success: false,
                code: 'MISSING_IMAGES',
                message: 'Both selfie and profilePhoto are required for face verification',
            });
        }

        logger.info('[MobileVerifyFace] Initiating Azure AI face verification...');
        const result = await azureFaceService.performOneTimeVerification(selfie, profilePhoto);

        if (!result.success || !result.verified) {
            return res.status(400).json({
                success: false,
                verified: false,
                confidence: result.confidence,
                message: result.message,
                details: result.details,
            });
        }

        return res.status(200).json({
            success: true,
            verified: true,
            confidence: result.confidence,
            message: result.message,
            details: result.details,
        });
    } catch (error: any) {
        logger.error('[MobileVerifyFace] Error during face verification:', error);
        return res.status(500).json({
            success: false,
            message: error.message || 'Face verification service error',
        });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/auth/detect-face
// Single image human face detection
// ─────────────────────────────────────────────────────────────────────────────
export const mobileDetectFace = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { image } = req.body;

        if (!image) {
            return res.status(400).json({
                success: false,
                hasFace: false,
                message: 'No image provided for face detection',
            });
        }

        logger.info('[MobileDetectFace] Detecting human face in photo...');
        const imageBuf = azureFaceService.parseImageBuffer(image);
        const result = await azureFaceService.detectFace(imageBuf);

        if (!result.hasFace) {
            return res.status(400).json({
                success: false,
                hasFace: false,
                faceCount: result.faceCount,
                message: result.message || 'No human face detected in photo. Please upload a clear photo of yourself.',
            });
        }

        return res.status(200).json({
            success: true,
            hasFace: true,
            faceCount: result.faceCount,
            message: result.message || 'Human face detected successfully',
        });
    } catch (error: any) {
        logger.error('[MobileDetectFace] Error:', error);
        return res.status(500).json({
            success: false,
            hasFace: false,
            message: error.message || 'Face detection service error',
        });
    }
};

/**
 * POST /api/mobile/auth/facebook-login
 * PUBLIC — Authenticate or Register User using Facebook Auth Credentials
 */
export const mobileFacebookLogin = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { facebookId, email, firstName, lastName, avatarUrl } = req.body;

        if (!facebookId) {
            return res.status(400).json({ success: false, message: 'facebookId is required for Facebook authentication' });
        }

        const cleanEmail = email ? email.toLowerCase().trim() : undefined;
        let user: any = null;

        // 1. Try finding user by facebookId
        user = await User.findOne({ where: { facebookId } });

        // 2. If not found by facebookId, try finding by email
        if (!user && cleanEmail) {
            user = await User.findOne({ where: { email: cleanEmail } });
            if (user) {
                // Link facebookId to existing account
                await user.update({ facebookId });
            }
        }

        // 3. If user exists, log in
        if (user) {
            if (user.isDeleted || !user.isActive) {
                return res.status(403).json({ success: false, message: 'Your account has been deactivated or suspended.' });
            }

            await user.update({ lastLoginAt: new Date(), isOnline: true });
            const tokens = generateTokenPair({ userId: user.id, email: user.email, role: user.role });

            return res.status(200).json({
                success: true,
                message: 'Facebook login successful',
                token: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                user: {
                    id: user.id,
                    email: user.email,
                    firstName: user.firstName,
                    lastName: user.lastName,
                    phone: user.phone,
                    role: user.role,
                    profileImageUrl: user.profileImageUrl || avatarUrl || null,
                },
            });
        }

        // 4. If user does NOT exist, create new user account
        const dummyPassword = await bcrypt.hash(`fb_${facebookId}_${Date.now()}`, 10);
        const fName = firstName || 'Facebook';
        const lName = lastName || 'User';
        const userEmail = cleanEmail || `fb_${facebookId}@lunara.app`;
        const dummyPhone = `91${Math.floor(1000000000 + Math.random() * 9000000000)}`;

        user = await User.create({
            email: userEmail,
            phone: dummyPhone,
            passwordHash: dummyPassword,
            firstName: fName,
            lastName: lName,
            dateOfBirth: new Date('2000-01-01'),
            role: UserRole.CUSTOMER,
            isVerified: true,
            isActive: true,
            facebookId,
            profileImageUrl: avatarUrl || null,
        });

        await UserProfile.create({
            userId: user.id,
            bio: 'Hey there! I am on Lunara.',
            gender: 'other',
            city: 'Mumbai',
        });

        const tokens = generateTokenPair({ userId: user.id, email: user.email, role: user.role });

        logger.info(`[MobileFacebookLogin] Created new account for Facebook user ${user.id} (${user.email})`);

        return res.status(201).json({
            success: true,
            message: 'Facebook registration successful',
            token: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            user: {
                id: user.id,
                email: user.email,
                firstName: user.firstName,
                lastName: user.lastName,
                phone: user.phone,
                role: user.role,
                profileImageUrl: avatarUrl || null,
            },
        });
    } catch (error: any) {
        logger.error('[MobileFacebookLogin] Error:', error);
        return res.status(500).json({ success: false, message: error.message || 'Facebook authentication failed' });
    }
};

export default { mobileSendOTP, mobileVerifyOTP, mobileRegister, mobileForgotPassword, mobileResetPassword, mobileLogout, mobileCheckEmail, mobileVerifyFace, mobileDetectFace, mobileFacebookLogin };

