import { body } from 'express-validator';
import { validate } from './validate';

export const updateProfileValidation = [
    // Basic Info
    body('firstName').optional().trim().isLength({ min: 1, max: 100 }).withMessage('First name must be between 1 and 100 characters'),
    body('lastName').optional().trim().isLength({ min: 1, max: 100 }).withMessage('Last name must be between 1 and 100 characters'),
    body('phone').optional().trim().customSanitizer(val => {
        if (!val) return val;
        const cleaned = val.replace(/^\+91\s*/, '').replace(/[\s\-()]/g, '');
        return cleaned;
    }),
    body('dateOfBirth').optional({ nullable: true, checkFalsy: true }).custom((value) => {
        if (!value) return true;
        const d = new Date(value);
        if (isNaN(d.getTime())) {
            throw new Error('Date of birth must be a valid date');
        }
        if (d >= new Date()) {
            throw new Error('Date of birth cannot be in the future');
        }
        return true;
    }),
    body('gender').optional().trim().isString(),
    body('city').optional().trim().isString(),

    // Bio & Intent
    body('bio').optional().trim().isLength({ max: 500 }).withMessage('Bio must be at most 500 characters'),
    body('lookingFor').optional().isArray().withMessage('lookingFor must be an array'),
    body('interests').optional().isArray().withMessage('interests must be an array'),

    // Music & Habits
    body('musicPreference').optional().isArray().withMessage('musicPreference must be an array'),
    body('smokingPreference').optional().trim().isString(),
    body('drinkPreference').optional().isArray().withMessage('drinkPreference must be an array'),

    // Professional Background
    body('occupation').optional().trim().isString(),
    body('education').optional().trim().isString(),

    // Matching Preferences
    body('preferredGenders').optional().isArray().withMessage('preferredGenders must be an array'),
    body('minAgePreference').optional({ nullable: true, checkFalsy: true }).toInt().isInt({ min: 18 }).withMessage('Minimum age preference must be at least 18'),
    body('maxAgePreference').optional({ nullable: true, checkFalsy: true }).toInt().isInt({ max: 100 }).withMessage('Maximum age preference must be at most 100'),
    body('minBudget').optional({ nullable: true, checkFalsy: true }).toInt().isInt({ min: 0 }).withMessage('Minimum budget must be a positive number'),
    body('maxBudget').optional({ nullable: true, checkFalsy: true }).toInt().isInt({ min: 0 }).withMessage('Maximum budget must be a positive number'),
    body('budgetRange').optional().trim().isString(),

    // Privacy Settings
    body('invisibleMode').optional().isBoolean(),
    body('matchDistanceKm').optional({ nullable: true, checkFalsy: true }).toInt().isInt({ min: 1, max: 100 }),
    body('bookingAlertsEnabled').optional().isBoolean(),

    validate
];

export const changePasswordValidation = [
    body('currentPassword').notEmpty().withMessage('Current password is required'),
    body('newPassword')
        .notEmpty().withMessage('New password is required')
        .isLength({ min: 3 }).withMessage('Password must contain minimum 3 characters')
        .custom((value, { req }) => {
            if (value === req.body.currentPassword) {
                throw new Error('New password cannot be the same as current password');
            }
            if (req.body.confirmPassword && value !== req.body.confirmPassword) {
                throw new Error('Passwords do not match');
            }
            return true;
        }),
    body('confirmPassword').notEmpty().withMessage('Confirm password is required'),
    validate
];
