import { Router } from 'express';
import { body, param } from 'express-validator';
import { validate } from '../middleware/validate';
import { authenticate } from '../middleware/auth';
import {
    createRequest,
    getUserRequests,
    getUserJoinedMeets,
    getUserStrangersMeetsByUserId,
    getRequestById,
    confirmPayment,
    initiatePayment,
    getFeedRequests,
    initiateJoinPayment,
    confirmJoinPayment,
    completeMeet,
    sendJoinRequest,
    handleJoinRequest,
    submitSettlementRequest,
    updateChargesPerHead,
    getMeetFinancials,
    getStrangersMeetTicket,
    startMeetup,
    extendMeetup,
    confirmEndedMeetup,
    postNotStarted,
    requestJoinerCancellation,
    respondJoinerCancellation,
    getJoinerCancellationStatus,
    requestHostCancellation,
} from '../controllers/strangersMeetController';

const router = Router();

router.get('/requests/:id/ticket', authenticate, getStrangersMeetTicket);
router.get('/:id/financials', getMeetFinancials);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet
// User submits a new Strangers Meet request
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/',
    [
        authenticate,
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
        // v2: optional structured bank/UPI payment details
        body('bankName').optional().isString().isLength({ max: 100 }),
        body('accountNumber').optional().isString().isLength({ max: 50 }),
        body('accountHolderName').optional().isString().isLength({ max: 100 }),
        body('ifscCode').optional().isString().isLength({ max: 20 }),
        body('upiId').optional().isString().isLength({ max: 100 }),
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
    [authenticate, param('userId').isUUID().withMessage('userId must be a valid UUID'), validate],
    getUserRequests
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/strangers-meet/user/:userId
// Get active/approved strangers meet requests for a specific user's public profile
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/user/:userId',
    [param('userId').isUUID().withMessage('userId must be a valid UUID'), validate],
    getUserStrangersMeetsByUserId
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/strangers-meet/my-joined/:userId
// Get all requests user has joined
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/my-joined/:userId',
    [authenticate, param('userId').isUUID().withMessage('userId must be a valid UUID'), validate],
    getUserJoinedMeets
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
// GET /api/mobile/strangers-meet/:id/financials
// Get financial breakdown (platform fee, host profit, settlement amount)
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/:id/financials',
    [param('id').isUUID().withMessage('id must be a valid UUID'), validate],
    getMeetFinancials
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
        authenticate,
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
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('razorpay_order_id').notEmpty().withMessage('razorpay_order_id is required'),
        body('razorpay_payment_id').notEmpty().withMessage('razorpay_payment_id is required'),
        body('razorpay_signature').notEmpty().withMessage('razorpay_signature is required'),
        validate,
    ],
    confirmPayment
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/join/initiate-payment
// Initiate payment order to join a Strangers Meet
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/join/initiate-payment',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    initiateJoinPayment
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/join/confirm
// Confirm payment and join the Strangers Meet
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/join/confirm',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    confirmJoinPayment
);

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/mobile/strangers-meet/:id/complete
// Host marks the strangers meet as successfully completed
// ─────────────────────────────────────────────────────────────────────────────
router.patch(
    '/:id/complete',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    completeMeet
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/join-request
// Participant submits a request to join a Stranger Meet
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/join-request',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    sendJoinRequest
);

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/mobile/strangers-meet/:id/join-request/:joinerId
// Host accepts/rejects a participant's request to join
// ─────────────────────────────────────────────────────────────────────────────
router.patch(
    '/:id/join-request/:joinerId',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        param('joinerId').isUUID().withMessage('joinerId must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('action').notEmpty().isIn(['accept', 'reject']).withMessage('action must be accept or reject'),
        validate,
    ],
    handleJoinRequest
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/settlement-request
// Host submits bank/UPI details to request meetup earnings settlement
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/settlement-request',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('bankDetails').notEmpty().withMessage('bankDetails is required'),
        validate,
    ],
    submitSettlementRequest
);

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/mobile/strangers-meet/:id/charges
// Host sets/updates chargesPerHead
// ─────────────────────────────────────────────────────────────────────────────
router.patch(
    '/:id/charges',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('chargesPerHead').notEmpty().isFloat({ min: 0 }).withMessage('chargesPerHead is required and must be >= 0'),
        validate,
    ],
    updateChargesPerHead
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/start
// Host confirms meetup started + selects duration
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/start',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('durationHours').optional().isFloat({ min: 0.25, max: 24 }).withMessage('durationHours must be between 0.25 and 24'),
        body('customEndDateTime').optional().isISO8601().withMessage('customEndDateTime must be valid ISO8601 date'),
        validate,
    ],
    startMeetup
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/extend
// Host extends meetup duration
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/extend',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('additionalHours').optional().isFloat({ min: 0.25, max: 12 }).withMessage('additionalHours must be between 0.25 and 12'),
        body('customEndDateTime').optional().isISO8601().withMessage('customEndDateTime must be valid ISO8601 date'),
        validate,
    ],
    extendMeetup
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/confirm-ended
// Host confirms meetup ended
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/confirm-ended',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    confirmEndedMeetup
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/strangers-meet/:id/not-started
// Host marks meetup as not started
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/not-started',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('reason').optional().isString(),
        validate,
    ],
    postNotStarted
);

// ─────────────────────────────────────────────────────────────────────────────
// Cancellation & Refund Flow (Joined Member Cancels)
// ─────────────────────────────────────────────────────────────────────────────

// POST /api/mobile/strangers-meet/:id/joiner-cancel-request
// Member submits cancellation request to host
router.post(
    '/:id/joiner-cancel-request',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('reason').notEmpty().withMessage('Cancellation reason is required'),
        body('otherReasonText').optional().isString(),
        validate,
    ],
    requestJoinerCancellation
);

// PATCH /api/mobile/strangers-meet/:id/joiner-cancel-request/:cancellationId
// Host approves or rejects member's cancellation request
router.patch(
    '/:id/joiner-cancel-request/:cancellationId',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        param('cancellationId').isUUID().withMessage('cancellationId must be a valid UUID'),
        body('action').notEmpty().isIn(['accept', 'reject']).withMessage('action must be accept or reject'),
        body('rejectReason').optional().isString(),
        validate,
    ],
    respondJoinerCancellation
);

// GET /api/mobile/strangers-meet/:id/cancellation-status
// Get cancellation request status for caller
router.get(
    '/:id/cancellation-status',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        validate,
    ],
    getJoinerCancellationStatus
);

// POST /api/mobile/strangers-meet/:id/host-cancel-request
// Host submits cancellation request for Admin review
router.post(
    '/:id/host-cancel-request',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('reason').notEmpty().withMessage('Cancellation reason is required'),
        body('reasonText').optional().isString(),
        validate,
    ],
    requestHostCancellation
);

export default router;
