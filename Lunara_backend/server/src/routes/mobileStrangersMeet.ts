import { Router } from 'express';
import { body, param } from 'express-validator';
import { validate } from '../middleware/validate';
import {
    createRequest,
    getUserRequests,
    getRequestById,
    confirmPayment,
    initiatePayment,
    getFeedRequests,
} from '../controllers/strangersMeetController';

const router = Router();

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet
// User submits a new Strangers Meet request
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/',
    [
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('venueId').notEmpty().isUUID().withMessage('venueId must be a valid UUID'),
        body('subject').notEmpty().isLength({ min: 1, max: 200 }).withMessage('subject is required (max 200 chars)'),
        body('tagline').notEmpty().withMessage('tagline is required'),
        body('eventDateTime').notEmpty().isISO8601().withMessage('eventDateTime must be a valid ISO 8601 date'),
        body('numberOfPersons')
            .notEmpty().withMessage('numberOfPersons is required')
            .isInt({ min: 21, max: 50 }).withMessage('numberOfPersons must be between 21 and 50'),
        body('mobileNumber').notEmpty().isString().withMessage('mobileNumber is required'),
        body('alternateMobileNumber').optional().isString(),
        validate,
    ],
    createRequest
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/strangers-meet/my-requests/:userId
// Get all requests submitted by a specific user
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/my-requests/:userId',
    [param('userId').isUUID().withMessage('userId must be a valid UUID'), validate],
    getUserRequests
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/strangers-meet/feed
// Get all approved and paid strangers meet requests for public feed
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/feed',
    getFeedRequests
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/strangers-meet/:id
// Get a single request by ID
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/:id',
    [param('id').isUUID().withMessage('id must be a valid UUID'), validate],
    getRequestById
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/initiate-payment
// User initiates payment order for an approved request
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/initiate-payment',
    [
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    initiatePayment
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/pay
// User confirms payment for an approved request
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/pay',
    [
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('razorpay_order_id').notEmpty().withMessage('razorpay_order_id is required'),
        body('razorpay_payment_id').notEmpty().withMessage('razorpay_payment_id is required'),
        body('razorpay_signature').notEmpty().withMessage('razorpay_signature is required'),
        validate,
    ],
    confirmPayment
);

export default router;
