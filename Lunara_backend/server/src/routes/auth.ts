import express from 'express';
import * as authController from '../controllers/authController';
import { authenticate } from '../middleware/auth';
import { body } from 'express-validator';
import { validate } from '../middleware/validate';

const router = express.Router();

// Validation middleware
const registerValidation = [
    body('email').isEmail().withMessage('Valid email is required'),
    body('phone').matches(/^[6-9]\d{9}$/).withMessage('Valid Indian phone number is required'),
    body('password').isLength({ min: 3 }).withMessage('Password must be at least 3 characters'),
    body('firstName').trim().isLength({ min: 2 }).withMessage('First name is required'),
    body('lastName').trim().isLength({ min: 1 }).withMessage('Last name is required'),
    body('dateOfBirth').isISO8601().toDate().withMessage('Valid date of birth is required'),
    validate,
];

const loginValidation = [
    body('email').isEmail().withMessage('Valid email is required'),
    body('password').notEmpty().withMessage('Password is required'),
    validate,
];

const emailValidation = [
    body('email').isEmail().withMessage('Valid email is required'),
    validate,
];

const verifyEmailValidation = [
    body('token').notEmpty().withMessage('Verification token is required'),
    validate,
];

const resetPasswordValidation = [
    body('token').notEmpty().withMessage('Reset token is required'),
    body('newPassword').isLength({ min: 3 }).withMessage('New password must be at least 3 characters'),
    validate,
];

const changePasswordValidation = [
    body('currentPassword').notEmpty().withMessage('Current password is required'),
    body('newPassword').isLength({ min: 3 }).withMessage('Password must contain minimum 3 characters'),
    validate,
];

const updateProfileValidation = [
    body('firstName').optional().trim().isLength({ min: 2 }).withMessage('First name must be at least 2 characters'),
    body('lastName').optional().trim().isLength({ min: 1 }).withMessage('Last name must be at least 1 character'),
    body('phone').optional().matches(/^[6-9]\d{9}$/).withMessage('Valid Indian phone number is required'),
    body('dateOfBirth').optional().isISO8601().toDate().withMessage('Valid date of birth is required'),
    body('displayName').optional().trim().isLength({ min: 2, max: 100 }),
    body('bio').optional().trim().isLength({ max: 500 }),
    body('instagramHandle').optional().matches(/^[a-zA-Z0-9._]{0,30}$/),
    body('lookingFor').optional().isArray(),
    validate,
];

const profileSetupValidation = [
    body('displayName').optional().trim().isLength({ min: 2, max: 100 }),
    body('bio').optional().trim().isLength({ max: 500 }),
    body('gender').optional().trim().isLength({ max: 20 }),
    body('city').optional().trim().isLength({ max: 100 }),
    body('occupation').optional().trim().isLength({ max: 100 }),
    body('education').optional().trim().isLength({ max: 200 }),
    body('smokingPreference').optional().trim().isLength({ max: 20 }),
    body('musicPreference').optional().isArray(),
    body('drinkPreference').optional().isArray(),
    body('preferredGenders').optional().isArray(),
    body('minAgePreference').optional().isInt({ min: 18 }),
    body('maxAgePreference').optional().isInt({ max: 100 }),
    body('budgetRange').optional().trim().isLength({ max: 20 }),
    body('showMeInMatching').optional().isBoolean(),
    validate,
];

// Routes

/**
 * @route   POST /api/auth/register
 * @desc    Register a new user
 * @access  Public
 */
router.post('/register', registerValidation, authController.register);

/**
 * @route   POST /api/auth/verify-email
 * @desc    Verify email with token
 * @access  Public
 */
router.post('/verify-email', verifyEmailValidation, authController.verifyEmail);

/**
 * @route   POST /api/auth/login
 * @desc    Login user
 * @access  Public
 */
router.post('/login', loginValidation, authController.login);

/**
 * @route   POST /api/auth/admin-login
 * @desc    Admin-only login (validates role, auto-seeds admin from env on first run)
 * @access  Public
 */
router.post('/admin-login', loginValidation, authController.adminLogin);

/**
 * @route   POST /api/auth/bootstrap-admin
 * @desc    One-shot: create/reset admin user from env vars. Protected by BOOTSTRAP_SECRET.
 * @access  Public (secret-protected)
 */
router.post('/bootstrap-admin', authController.bootstrapAdmin);

/**
 * @route   POST /api/auth/forgot-password
 * @desc    Send password reset email
 * @access  Public
 */
router.post('/forgot-password', emailValidation, authController.forgotPassword);

/**
 * @route   POST /api/auth/reset-password
 * @desc    Reset password with token
 * @access  Public
 */
router.post('/reset-password', resetPasswordValidation, authController.resetPassword);

/**
 * @route   POST /api/auth/change-password
 * @desc    Change password (authenticated)
 * @access  Private
 */
router.post('/change-password', authenticate, changePasswordValidation, authController.changePassword);

/**
 * @route   GET /api/auth/me
 * @desc    Get current user
 * @access  Private
 */
router.get('/me', authenticate, authController.getCurrentUser);

/**
 * @route   PUT /api/auth/me
 * @desc    Update current user profile
 * @access  Private
 */
router.put('/me', authenticate, updateProfileValidation, authController.updateProfile);

/**
 * @route   PUT /api/auth/profile-setup
 * @desc    Setup complete unified profile data (4-step dating onboarding)
 * @access  Private
 */
router.put('/profile-setup', authenticate, profileSetupValidation, authController.setupProfile);

/**
 * @route   POST /api/auth/resend-verification
 * @desc    Resend verification email
 * @access  Public
 */
router.post('/resend-verification', emailValidation, authController.resendVerification);

/**
 * @route   POST /api/auth/setup-2fa
 * @desc    Setup 2FA (Generate Secret and QR Code)
 * @access  Private
 */
router.post('/setup-2fa', authenticate, authController.setup2FA);

/**
 * @route   POST /api/auth/verify-2fa-setup
 * @desc    Verify and enable 2FA for the first time
 * @access  Private
 */
router.post('/verify-2fa-setup', authenticate, authController.verify2FASetup);

/**
 * @route   POST /api/auth/verify-2fa-login
 * @desc    Verify TOTP during login flow
 * @access  Public
 */
router.post('/verify-2fa-login', authController.verify2FALogin);

export default router;
