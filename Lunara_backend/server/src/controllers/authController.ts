import { Request, Response } from 'express';
import { Op } from 'sequelize';
import { User, EmailVerification, PasswordResetToken, UserProfile, UserPreference, UserRole } from '../models';
import { generateTokenPair } from '../utils/jwt';
import { sendVerificationEmail, sendPasswordResetEmail, sendWelcomeEmail } from '../services/emailService';
import { UserService } from '../services/userService';
import { logger } from '../config/logger';
import speakeasy from 'speakeasy';
import QRCode from 'qrcode';

/**
 * Register a new user
 * POST /api/auth/register
 */
export async function register(req: Request, res: Response) {
    try {
        const { email, phone, password, firstName, lastName, dateOfBirth } = req.body;

        // Validate required fields
        if (!email || !phone || !password || !firstName || !lastName || !dateOfBirth) {
            return res.status(400).json({
                success: false,
                message: 'All fields are required: email, phone, password, firstName, lastName, dateOfBirth',
            });
        }

        const normalizedEmail = email.trim().toLowerCase();
        const normalizedPhone = phone.trim();

        // Check if user already exists
        const existingUser = await User.findOne({
            where: {
                [Op.or]: [{ email: normalizedEmail }, { phone: normalizedPhone }],
            },
        });

        if (existingUser) {
            if (existingUser.email === normalizedEmail) {
                return res.status(409).json({
                    success: false,
                    message: 'Email already registered',
                });
            }
            return res.status(409).json({
                success: false,
                message: 'Phone number already registered',
            });
        }

        // Validate age (must be 18+)
        const birthDate = new Date(dateOfBirth);
        const age = new Date().getFullYear() - birthDate.getFullYear();
        const minAge = parseInt(process.env.MINIMUM_AGE || '18');

        if (age < minAge) {
            return res.status(400).json({
                success: false,
                message: `You must be at least ${minAge} years old to register`,
            });
        }

        // Create user
        const user = await User.create({
            email: normalizedEmail,
            phone: normalizedPhone,
            passwordHash: password, // Will be hashed by model hook
            firstName,
            lastName,
            dateOfBirth: birthDate,
            role: UserRole.CUSTOMER,
        });

        // Create user profile
        await UserProfile.create({
            userId: user.id,
            displayName: `${firstName} ${lastName}`,
        });

        // Create user preferences
        await UserPreference.create({
            userId: user.id,
        });

        // Generate email verification token & send (non-blocking in dev)
        try {
            const verification = await EmailVerification.generateToken(user.id);
            const rawToken = (verification as any).rawToken;
            await sendVerificationEmail(email, rawToken, firstName);
        } catch (emailError: any) {
            logger.warn(`Email verification skipped (SMTP not configured): ${emailError.message}`);
        }

        // Generate JWT tokens
        const tokens = generateTokenPair({
            userId: user.id,
            email: user.email,
            role: user.role,
        });

        logger.info(`New user registered: ${email}`);

        return res.status(201).json({
            success: true,
            message: 'Registration successful. Please check your email to verify your account.',
            data: {
                user: user.toJSON(),
                ...tokens,
            },
        });
    } catch (error: any) {
        logger.error('Registration error:', error);
        return res.status(500).json({
            success: false,
            message: 'Registration failed',
            error: error.message,
        });
    }
}

/**
 * Verify email
 * POST /api/auth/verify-email
 */
export async function verifyEmail(req: Request, res: Response) {
    try {
        const { token } = req.body;

        if (!token) {
            return res.status(400).json({
                success: false,
                message: 'Verification token is required',
            });
        }

        // Verify token
        const verification = await EmailVerification.verifyToken(token);
        if (!verification) {
            return res.status(400).json({
                success: false,
                message: 'Invalid or expired verification token',
            });
        }

        // Mark as verified
        await verification.markAsVerified();

        // Update user
        const user = await User.findByPk(verification.userId);
        if (user) {
            user.isVerified = true;
            await user.save();

            // Send welcome email
            await sendWelcomeEmail(user.email, user.firstName);
        }

        logger.info(`Email verified for user: ${verification.userId}`);

        return res.json({
            success: true,
            message: 'Email verified successfully',
        });
    } catch (error: any) {
        logger.error('Email verification error:', error);
        return res.status(500).json({
            success: false,
            message: 'Email verification failed',
            error: error.message,
        });
    }
}

/**
 * Login
 * POST /api/auth/login
 */
export async function login(req: Request, res: Response) {
    try {
        const { email, password } = req.body;

        if (!email || !password) {
            return res.status(400).json({
                success: false,
                message: 'Email and password are required',
            });
        }

        const normalizedEmail = email.trim().toLowerCase();

        // Find user
        const user = await User.findOne({ where: { email: normalizedEmail } });
        if (!user) {
            return res.status(401).json({
                success: false,
                message: 'Invalid email or password',
            });
        }

        // Check if account is permanently deleted
        if ((user as any).isDeleted) {
            return res.status(403).json({
                success: false,
                code: 'ACCOUNT_DELETED',
                message: 'This account has been permanently deleted. Please contact support if this was a mistake.',
            });
        }

        // Check if account is active or auto-blocked
        if (!user.isActive || user.isAutoblocked) {
            if (user.isAutoblocked) {
                return res.status(403).json({
                    success: false,
                    code: 'USER_AUTOBLOCKED',
                    message: `You are autoblocked due to: ${user.autoblockedReason || 'safety reports/guidelines violation'}.`,
                    autoblockedReason: user.autoblockedReason || 'safety reports/guidelines violation',
                });
            }
            return res.status(403).json({
                success: false,
                message: 'Account is deactivated. Please contact support.',
            });
        }

        // Verify password
        const isPasswordValid = await user.comparePassword(password);
        if (!isPasswordValid) {
            return res.status(401).json({
                success: false,
                message: 'Invalid email or password',
            });
        }

        // Update last login
        user.lastLoginAt = new Date();
        await user.save({ fields: ['lastLoginAt'] });

        // Check if 2FA is enabled
        if (user.mfaEnabled) {
            return res.json({
                success: true,
                message: '2FA required',
                data: {
                    requires2FA: true,
                    userId: user.id
                }
            });
        }

        // Generate tokens (if 2FA not enabled)
        const tokens = generateTokenPair({
            userId: user.id,
            email: user.email,
            role: user.role,
        });

        logger.info(`User logged in: ${email}`);

        return res.json({
            success: true,
            message: 'Login successful',
            data: {
                user: user.toJSON(),
                ...tokens,
            },
        });
    } catch (error: any) {
        logger.error('Login error:', error);
        return res.status(500).json({
            success: false,
            message: 'Login failed',
            error: error.message,
        });
    }
}

/**
 * Admin Login — only allows users with role=admin
 * POST /api/auth/admin-login
 * Auto-creates the admin account from env vars if it doesn't exist (production cold-start).
 */
export async function adminLogin(req: Request, res: Response) {
    try {
        const { email, password } = req.body;

        if (!email || !password) {
            return res.status(400).json({ success: false, message: 'Email and password are required' });
        }

        const normalizedEmail = email.trim().toLowerCase();

        // ── Auto-seed admin from environment if not yet in DB ──
        const adminEmail = (process.env.ADMIN_EMAIL || 'admin@lunara.com').trim().toLowerCase();
        const adminPassword = process.env.ADMIN_PASSWORD || 'JaiGanesh@2026';
        if (adminEmail && adminPassword && normalizedEmail === adminEmail) {
            let existingAdmin = await User.findOne({ where: { email: adminEmail } });
            if (!existingAdmin) {
                logger.info(`Admin account not found — auto-creating: ${adminEmail}`);
                existingAdmin = await User.create({
                    email: adminEmail,
                    phone: process.env.ADMIN_PHONE || '9999999999',
                    passwordHash: adminPassword,
                    firstName: 'Super',
                    lastName: 'Admin',
                    dateOfBirth: new Date('1990-01-01'),
                    role: UserRole.ADMIN,
                    isVerified: true,
                    isActive: true,
                });
                try { await UserProfile.create({ userId: existingAdmin.id, displayName: 'Super Admin' }); } catch (_) { }
                try { await UserPreference.create({ userId: existingAdmin.id }); } catch (_) { }
                logger.info(`Admin account created successfully: ${adminEmail}`);
            }
        }

        const user = await User.findOne({ where: { email: normalizedEmail } });
        if (!user) {
            return res.status(401).json({
                success: false,
                message: 'Invalid email or password',
                debug: {
                    errorLocation: 'user_not_found_in_db',
                    inputEmail: normalizedEmail,
                    configuredAdminEmail: adminEmail,
                    envAdminEmailSet: !!process.env.ADMIN_EMAIL,
                    envAdminPasswordSet: !!process.env.ADMIN_PASSWORD
                }
            });
        }

        if (user.role !== UserRole.ADMIN) {
            return res.status(403).json({
                success: false,
                message: 'Access denied. Admin privileges required.',
                debug: {
                    errorLocation: 'role_mismatch',
                    userRole: user.role
                }
            });
        }

        if (!user.isActive) {
            return res.status(403).json({
                success: false,
                message: 'Admin account is deactivated.',
                debug: {
                    errorLocation: 'inactive_user'
                }
            });
        }

        const isPasswordValid = await user.comparePassword(password);
        if (!isPasswordValid) {
            return res.status(401).json({
                success: false,
                message: 'Invalid email or password',
                debug: {
                    errorLocation: 'invalid_password',
                    passwordLength: password.length,
                    storedHashStarts: user.passwordHash ? user.passwordHash.substring(0, 10) : 'null'
                }
            });
        }

        user.lastLoginAt = new Date();
        await user.save({ fields: ['lastLoginAt'] });

        if (user.mfaEnabled) {
            return res.json({
                success: true,
                message: '2FA required',
                data: { requires2FA: true, userId: user.id }
            });
        }

        const tokens = generateTokenPair({ userId: user.id, email: user.email, role: user.role });

        logger.info(`Admin logged in: ${email}`);

        return res.json({
            success: true,
            message: 'Admin login successful',
            data: { user: user.toJSON(), ...tokens },
        });
    } catch (error: any) {
        logger.error('Admin login error:', error);
        return res.status(500).json({ success: false, message: 'Admin login failed', error: error.message });
    }
}

/**
 * Bootstrap Admin — creates or resets admin user in the DB.
 * POST /api/auth/bootstrap-admin
 * Body: { secret: string }
 * Protected by BOOTSTRAP_SECRET env var (default: 'lunara-bootstrap-2026')
 */
export async function bootstrapAdmin(req: Request, res: Response) {
    try {
        const { secret } = req.body;
        const bootstrapSecret = process.env.BOOTSTRAP_SECRET || 'lunara-bootstrap-2026';
        if (!secret || secret !== bootstrapSecret) {
            return res.status(403).json({ success: false, message: 'Invalid bootstrap secret' });
        }

        const adminEmail = (process.env.ADMIN_EMAIL || 'admin@lunara.com').trim().toLowerCase();
        const adminPassword = process.env.ADMIN_PASSWORD || 'JaiGanesh@2026';
        const adminPhone = process.env.ADMIN_PHONE || '9999999999';

        let adminUser = await User.findOne({ where: { email: adminEmail } });
        if (adminUser) {
            // Reset password and ensure admin role
            adminUser.passwordHash = adminPassword; // beforeUpdate hook will hash it
            adminUser.role = UserRole.ADMIN;
            adminUser.isActive = true;
            adminUser.isVerified = true;
            await adminUser.save();
            return res.json({ success: true, message: `Admin user reset: ${adminEmail}`, action: 'updated' });
        }

        // Create from scratch
        adminUser = await User.create({
            email: adminEmail,
            phone: adminPhone,
            passwordHash: adminPassword,  // beforeCreate hook hashes it
            firstName: 'Super',
            lastName: 'Admin',
            dateOfBirth: new Date('1990-01-01'),
            role: UserRole.ADMIN,
            isVerified: true,
            isActive: true,
        });
        try { await UserProfile.create({ userId: adminUser.id, displayName: 'Super Admin' }); } catch (_) {}
        try { await UserPreference.create({ userId: adminUser.id }); } catch (_) {}
        logger.info(`Bootstrap: Admin user created: ${adminEmail}`);
        return res.json({ success: true, message: `Admin user created: ${adminEmail}`, action: 'created' });
    } catch (error: any) {
        logger.error('Bootstrap admin error:', error);
        return res.status(500).json({ success: false, message: 'Bootstrap failed', error: error.message });
    }
}

/**
 * Forgot password - send reset email
 * POST /api/auth/forgot-password
 */
export async function forgotPassword(req: Request, res: Response) {
    try {
        const { email } = req.body;

        if (!email) {
            return res.status(400).json({
                success: false,
                message: 'Email is required',
            });
        }

        const normalizedEmail = email.trim().toLowerCase();

        // Find user
        const user = await User.findOne({ where: { email: normalizedEmail } });
        if (!user) {
            // Don't reveal if email exists
            return res.json({
                success: true,
                message: 'If that email is registered, a password reset link has been sent.',
            });
        }

        // Generate reset token
        const resetToken = await PasswordResetToken.generateToken(user.id);
        const rawToken = (resetToken as any).rawToken;

        // Send reset email
        await sendPasswordResetEmail(email, rawToken, user.firstName);

        logger.info(`Password reset requested for: ${email}`);

        return res.json({
            success: true,
            message: 'If that email is registered, a password reset link has been sent.',
        });
    } catch (error: any) {
        logger.error('Forgot password error:', error);
        return res.status(500).json({
            success: false,
            message: 'Failed to process password reset request',
            error: error.message,
        });
    }
}

/**
 * Reset password with token
 * POST /api/auth/reset-password
 */
export async function resetPassword(req: Request, res: Response) {
    try {
        const { token, newPassword } = req.body;

        if (!token || !newPassword) {
            return res.status(400).json({
                success: false,
                message: 'Token and new password are required',
            });
        }

        // Validate password strength
        if (newPassword.length < 3) {
            return res.status(400).json({
                success: false,
                message: 'Password must be at least 3 characters long',
            });
        }

        // Verify token
        const resetToken = await PasswordResetToken.verifyToken(token);
        if (!resetToken) {
            return res.status(400).json({
                success: false,
                message: 'Invalid or expired reset token',
            });
        }

        // Update password
        const user = await User.findByPk(resetToken.userId);
        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found',
            });
        }

        user.passwordHash = newPassword; // Will be hashed by model hook
        await user.save();

        // Mark token as used
        await resetToken.markAsUsed();

        logger.info(`Password reset for user: ${user.email}`);

        return res.json({
            success: true,
            message: 'Password reset successful. You can now login with your new password.',
        });
    } catch (error: any) {
        logger.error('Reset password error:', error);
        return res.status(500).json({
            success: false,
            message: 'Password reset failed',
            error: error.message,
        });
    }
}

/**
 * Change password (authenticated)
 * POST /api/auth/change-password
 */
export async function changePassword(req: Request, res: Response) {
    try {
        const { currentPassword, newPassword } = req.body;
        const userId = req.user?.id;

        if (!userId) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required',
            });
        }

        if (!currentPassword || !newPassword) {
            return res.status(400).json({
                success: false,
                message: 'Current password and new password are required',
            });
        }

        // Validate new password
        if (newPassword.length < 3) {
            return res.status(400).json({
                success: false,
                message: 'New password must be at least 3 characters long',
            });
        }

        if (currentPassword === newPassword) {
            return res.status(400).json({
                success: false,
                message: 'New password must be different from current password',
            });
        }

        // Get user
        const user = await User.findByPk(userId);
        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found',
            });
        }

        // Verify current password
        const isPasswordValid = await user.comparePassword(currentPassword);
        if (!isPasswordValid) {
            return res.status(401).json({
                success: false,
                message: 'Current password is incorrect',
            });
        }

        // Update password
        user.passwordHash = newPassword; // Will be hashed by model hook
        await user.save();

        logger.info(`Password changed for user: ${user.email}`);

        return res.json({
            success: true,
            message: 'Password changed successfully',
        });
    } catch (error: any) {
        logger.error('Change password error:', error);
        return res.status(500).json({
            success: false,
            message: 'Failed to change password',
            error: error.message,
        });
    }
}

/**
 * Get current user
 * GET /api/auth/me
 */
export async function getCurrentUser(req: Request, res: Response) {
    try {
        const userId = req.user?.id;

        if (!userId) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required',
            });
        }

        const user = await User.findByPk(userId, {
            include: [
                { model: UserProfile, as: 'profile' },
                { model: UserPreference, as: 'preferences' },
            ],
        });

        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found',
            });
        }

        return res.json({
            success: true,
            data: user.toJSON(),
        });
    } catch (error: any) {
        logger.error('Get current user error:', error);
        return res.status(500).json({
            success: false,
            message: 'Failed to get user data',
            error: error.message,
        });
    }
}

/**
 * Update current user profile
 * PUT /api/auth/me
 */
export async function updateProfile(req: Request, res: Response) {
    try {
        const userId = req.user?.id;

        if (!userId) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required',
            });
        }

        const {
            firstName,
            lastName,
            phone,
            dateOfBirth,
            displayName,
            bio,
            gender,
            city,
            occupation,
            company,
            education,
            relationshipStatus,
            lookingFor,
            instagramHandle,
            spotifyProfile
        } = req.body;

        const user = await User.findByPk(userId);
        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found',
            });
        }

        // Update User base fields if provided
        if (firstName) user.firstName = firstName;
        if (lastName) user.lastName = lastName;
        if (phone) user.phone = phone;
        if (dateOfBirth) user.dateOfBirth = new Date(dateOfBirth);

        await user.save();

        // Find or create profile
        let profile = await UserProfile.findOne({ where: { userId } });
        if (!profile) {
            profile = await UserProfile.create({ userId, displayName: displayName || `${user.firstName} ${user.lastName}` });
        }

        // Update Profile fields if provided
        if (displayName !== undefined) profile.displayName = displayName;
        if (bio !== undefined) profile.bio = bio;
        if (gender !== undefined) profile.gender = gender;
        if (city !== undefined) profile.city = city;
        if (occupation !== undefined) profile.occupation = occupation;
        if (company !== undefined) profile.company = company;
        if (education !== undefined) profile.education = education;
        if (relationshipStatus !== undefined) profile.relationshipStatus = relationshipStatus;
        if (lookingFor !== undefined) profile.lookingFor = lookingFor;
        if (instagramHandle !== undefined) profile.instagramHandle = instagramHandle;
        if (spotifyProfile !== undefined) profile.spotifyProfile = spotifyProfile;

        await profile.save();

        // Refresh user data to return
        const updatedUser = await User.findByPk(userId, {
            include: [
                { model: UserProfile, as: 'profile' },
                { model: UserPreference, as: 'preferences' },
            ],
        });

        logger.info(`User profile updated: ${user.email}`);

        return res.json({
            success: true,
            message: 'Profile updated successfully',
            data: updatedUser?.toJSON(),
        });
    } catch (error: any) {
        logger.error('Update profile error:', error);
        return res.status(500).json({
            success: false,
            message: 'Failed to update profile',
            error: error.message,
        });
    }
}

/**
 * Setup Profile (Unified endpoint)
 * PUT /api/auth/profile-setup
 */
export async function setupProfile(req: Request, res: Response) {
    try {
        const userId = req.user?.id;

        if (!userId) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required',
            });
        }

        const data = req.body; // Expects SetupProfileData

        // Call the transactional service
        const result = await UserService.setupProfile(userId, data);

        logger.info(`User profile setup completed: ${userId}`);

        return res.json({
            success: true,
            message: 'Profile setup completed successfully',
            data: result,
        });
    } catch (error: any) {
        logger.error('Setup profile error:', error);
        return res.status(500).json({
            success: false,
            message: 'Failed to complete profile setup',
            error: error.message,
        });
    }
}

/**
 * Resend verification email
 * POST /api/auth/resend-verification
 */
export async function resendVerification(req: Request, res: Response) {
    try {
        const { email } = req.body;

        if (!email) {
            return res.status(400).json({
                success: false,
                message: 'Email is required',
            });
        }

        const normalizedEmail = email.trim().toLowerCase();

        const user = await User.findOne({ where: { email: normalizedEmail } });
        if (!user) {
            return res.json({
                success: true,
                message: 'If that email is registered and unverified, a verification link has been sent.',
            });
        }

        if (user.isVerified) {
            return res.status(400).json({
                success: false,
                message: 'Email is already verified',
            });
        }

        // Generate new verification token
        const verification = await EmailVerification.generateToken(user.id);
        const rawToken = (verification as any).rawToken;

        // Send verification email
        await sendVerificationEmail(email, rawToken, user.firstName);

        logger.info(`Verification email resent to: ${email}`);

        return res.json({
            success: true,
            message: 'Verification email sent successfully',
        });
    } catch (error: any) {
        logger.error('Resend verification error:', error);
        return res.status(500).json({
            success: false,
            message: 'Failed to resend verification email',
            error: error.message,
        });
    }
}

/**
 * Ensure the following 2FA operations: Setup, Verify Setup, and Verify Login
 */

/**
 * Setup 2FA - Generate secret and QR code
 * POST /api/auth/setup-2fa
 */
export async function setup2FA(req: Request, res: Response) {
    try {
        const userId = req.user?.id;
        if (!userId) return res.status(401).json({ success: false, message: 'Authentication required' });

        const user = await User.findByPk(userId);
        if (!user) return res.status(404).json({ success: false, message: 'User not found' });

        const secret = speakeasy.generateSecret({
            name: `Lunara Admin (${user.email})`
        });

        const qrCodeUrl = await QRCode.toDataURL(secret.otpauth_url!);

        // Temporarily store the secret until verified
        user.mfaSecret = secret.base32;
        await user.save();

        return res.json({
            success: true,
            data: {
                secret: secret.base32,
                qrCodeUrl
            }
        });
    } catch (error: any) {
        logger.error('Setup 2FA error:', error);
        return res.status(500).json({ success: false, message: 'Failed to setup 2FA' });
    }
}

/**
 * Verify 2FA Setup - Validate the first TOTP code
 * POST /api/auth/verify-2fa-setup
 */
export async function verify2FASetup(req: Request, res: Response) {
    try {
        const userId = req.user?.id;
        const { token } = req.body;

        if (!userId) return res.status(401).json({ success: false, message: 'Authentication required' });
        if (!token) return res.status(400).json({ success: false, message: 'TOTP token is required' });

        const user = await User.findByPk(userId);
        if (!user || !user.mfaSecret) {
            return res.status(400).json({ success: false, message: '2FA setup not initiated' });
        }

        const verified = speakeasy.totp.verify({
            secret: user.mfaSecret,
            encoding: 'base32',
            token
        });

        if (verified) {
            user.mfaEnabled = true;
            await user.save();
            return res.json({ success: true, message: '2FA enabled successfully' });
        } else {
            return res.status(400).json({ success: false, message: 'Invalid token' });
        }
    } catch (error: any) {
        logger.error('Verify 2FA setup error:', error);
        return res.status(500).json({ success: false, message: 'Failed to verify 2FA' });
    }
}

/**
 * Verify 2FA Login - Finalize the login process
 * POST /api/auth/verify-2fa-login
 */
export async function verify2FALogin(req: Request, res: Response) {
    try {
        const { userId, token } = req.body;

        if (!userId || !token) {
            return res.status(400).json({ success: false, message: 'User ID and token are required' });
        }

        const user = await User.findByPk(userId);
        if (!user || (!user.mfaEnabled && !user.mfaSecret)) {
            return res.status(400).json({ success: false, message: '2FA not enabled for this user' });
        }

        const verified = speakeasy.totp.verify({
            secret: user.mfaSecret!,
            encoding: 'base32',
            token
        });

        if (verified) {
            const tokens = generateTokenPair({
                userId: user.id,
                email: user.email,
                role: user.role,
            });

            user.lastLoginAt = new Date();
            await user.save({ fields: ['lastLoginAt'] });

            return res.json({
                success: true,
                message: 'Login successful',
                data: {
                    user: user.toJSON(),
                    ...tokens,
                }
            });
        } else {
            return res.status(400).json({ success: false, message: 'Invalid 2FA token' });
        }
    } catch (error: any) {
        logger.error('Verify 2FA login error:', error);
        return res.status(500).json({ success: false, message: 'Failed to verify 2FA login' });
    }
}

export default {
    register,
    verifyEmail,
    login,
    forgotPassword,
    resetPassword,
    changePassword,
    getCurrentUser,
    resendVerification,
    setup2FA,
    verify2FASetup,
    verify2FALogin,
    updateProfile,
    setupProfile
};
