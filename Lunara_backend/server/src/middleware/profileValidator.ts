import { body } from 'express-validator';
import { validate } from './validate';

export const updateProfileValidation = [
    // Basic Info
    body('firstName').optional().trim().isLength({ min: 2, max: 100 }).withMessage('First name must be between 2 and 100 characters'),
    body('lastName').optional().trim().isLength({ min: 1, max: 100 }).withMessage('Last name must be between 1 and 100 characters'),
    body('phone').optional().trim().matches(/^[6-9]\d{9}$/).withMessage('Must be a valid Indian phone number'),
    body('dateOfBirth').optional().isISO8601().toDate().withMessage('Must be a valid date').custom((value) => {
        if (value >= new Date()) {
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
    body('minAgePreference').optional().isInt({ min: 18 }).withMessage('Minimum age preference must be at least 18'),
    body('maxAgePreference').optional().isInt({ max: 100 }).withMessage('Maximum age preference must be at most 100'),
    body('minBudget').optional().isInt({ min: 0 }).withMessage('Minimum budget must be a positive number'),
    body('maxBudget').optional().isInt({ min: 0 }).withMessage('Maximum budget must be a positive number'),

    // Privacy Settings
    body('invisibleMode').optional().isBoolean(),
    body('matchDistanceKm').optional().isInt({ min: 1, max: 100 }),
    body('bookingAlertsEnabled').optional().isBoolean(),

    validate
];

export const changePasswordValidation = [
    body('currentPassword').notEmpty().withMessage('Current password is required'),
    body('newPassword')
        .notEmpty().withMessage('New password is required')
        .isLength({ min: 8 }).withMessage('Password must be at least 8 characters long')
        .matches(/[A-Z]/).withMessage('Password must contain at least 1 uppercase letter')
        .matches(/[a-z]/).withMessage('Password must contain at least 1 lowercase letter')
        .matches(/[0-9]/).withMessage('Password must contain at least 1 number')
        .matches(/[^A-Za-z0-9]/).withMessage('Password must contain at least 1 special character')
        .custom((value, { req }) => {
            if (value === req.body.currentPassword) {
                throw new Error('New password cannot be the same as current password');
            }
            if (value !== req.body.confirmPassword) {
                throw new Error('New password and confirm password must match');
            }
            return true;
        }),
    body('confirmPassword').notEmpty().withMessage('Confirm password is required'),
    validate
];
