import { Router } from 'express';
import { body, param } from 'express-validator';
import { validate } from '../middleware/validate';
import { authenticate, optionalAuth } from '../middleware/auth';
import {
    createPartyPlan,
    verifyHostPayment,
    getAllPartyPlans,
    getPlansByUser,
    getPartyPlanById,
    updatePartyPlanStatus,
    deletePartyPlan,
    createPartyPlanRequest,
    getPartyPlanRequests,
    acceptPartyPlanRequest,
    verifyJoinerPayment,
    cancelPartyPlan,
    repostPartyPlan,
    getJoinerRequests,
    initiateHostPayment,
    initiateJoinerPayment,
    confirmSelfPaidJoin,
    acceptPartyPlanInvite,
    getPartyPlanTicket,
    confirmArrival,
    submitPartyReview,
    rejectPartyPlanRequest,
    cancelPartyPlanRequest,
    withdrawPartyPlanRequest,
    revokePartyPlanAcceptance,
    getPlanSummary,
} from '../controllers/partyPlanController';

const router = Router();

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans
// Create a new party plan (called when user taps "POST PARTY PLAN")
// ─────────────────────────────────────────────────────────────────────────────
/**
 * Body (JSON):
 *   userId        string   required  — UUID of the user posting the plan
 *   venueId       string   required  — UUID of the selected venue
 *   message       string   required  — Party message / description (1–500 chars)
 *   planDateTime  string   required  — ISO 8601 datetime e.g. "2025-06-01T22:00:00.000Z"
 *   visibility    string   optional  — "public" or "private" (default: "public")
 *   selectedUsers string[] optional  — Array of user UUIDs if visibility is "private"
 *
 * Response 201:
 *   { success, message, data: { id, status, message, planDateTime, createdAt, user, venue } }
 */
router.post(
    '/',
    [
        authenticate,
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('venueId').notEmpty().isUUID().withMessage('venueId must be a valid UUID'),
        body('message')
            .notEmpty().withMessage('message is required')
            .isLength({ min: 1, max: 500 }).withMessage('message must be between 1 and 500 characters'),
        body('planDateTime')
            .notEmpty().withMessage('planDateTime is required')
            .isISO8601().withMessage('planDateTime must be a valid ISO 8601 date (e.g. "2025-06-01T22:00:00.000Z")'),
        body('visibility')
            .optional()
            .isIn(['public', 'private']).withMessage('visibility must be public or private'),
        body('selectedUsers')
            .optional()
            .isArray().withMessage('selectedUsers must be an array of user UUIDs'),
        validate,
    ],
    createPartyPlan
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/host-pay
// Verify host payment for party plan deposit
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/host-pay',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').optional({ checkFalsy: true }).isUUID().withMessage('userId must be a valid UUID'),
        body('razorpay_order_id').notEmpty().withMessage('razorpay_order_id is required'),
        body('razorpay_payment_id').notEmpty().withMessage('razorpay_payment_id is required'),
        // Razorpay's Flutter SDK can hand back a null signature for some payment
        // methods; the controller already treats an empty signature as a valid
        // mock-payment signal, so the validator must not reject it upstream.
        body('razorpay_signature').optional({ checkFalsy: true }).isString().withMessage('razorpay_signature must be a string'),
        validate,
    ],
    verifyHostPayment
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans
// Get all posted party plans (with user + venue details)
// ─────────────────────────────────────────────────────────────────────────────
/**
 * Query params:
 *   status      — active | inactive | cancelled  (default: active)
 *   venueId     — filter by venue UUID (optional)
 *   requesterId — user UUID to fetch private plans shared with them (optional)
 *   page        — page number (default: 1)
 *   limit       — results per page, max 100 (default: 20)
 *
 * Response 200:
 *   { success, total, page, limit, pages, data: [...plans] }
 */
router.get('/', optionalAuth, getAllPartyPlans);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/user/:userId
// Get all plans posted by a specific user
// ─────────────────────────────────────────────────────────────────────────────
/**
 * Params:
 *   userId — UUID of the user
 * Query params:
 *   status  — filter by status (optional)
 *
 * Response 200:
 *   { success, userId, total, data: [...plans] }
 */
router.get(
    '/user/:userId',
    [optionalAuth, param('userId').isUUID().withMessage('userId must be a valid UUID'), validate],
    getPlansByUser
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/:id
// Get a single party plan by ID
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/:id',
    [optionalAuth, param('id').isUUID().withMessage('id must be a valid UUID'), validate],
    getPartyPlanById
);

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/mobile/party-plans/:id/status
// Update plan status (e.g. cancel a plan)
// ─────────────────────────────────────────────────────────────────────────────
/**
 * Body (JSON):
 *   userId  string  required — must be the plan creator's userId
 *   status  string  required — active | inactive | cancelled
 */
router.patch(
    '/:id/status',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('status').isIn(['active', 'inactive', 'cancelled']).withMessage('status must be active, inactive, or cancelled'),
        validate,
    ],
    updatePartyPlanStatus
);

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/mobile/party-plans/:id
// Delete a party plan (only the creator can delete)
// ─────────────────────────────────────────────────────────────────────────────
/**
 * Body (JSON):
 *   userId  string  required — must match the plan creator's userId
 */
router.delete(
    '/:id',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    deletePartyPlan
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/cancel
// Cancel a party plan
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/cancel',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    cancelPartyPlan
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/repost
// Repost a party plan with a new date/time (by host)
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/repost',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('newDateTime').notEmpty().withMessage('newDateTime is required').isISO8601().withMessage('newDateTime must be a valid ISO 8601 date string'),
        body('reason').optional().isString().isLength({ max: 500 }),
        validate,
    ],
    repostPartyPlan
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/requests
// Request to join a party plan
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/requests',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    createPartyPlanRequest
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/:id/requests
// Host view requests for their plan
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/:id/requests',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        validate,
    ],
    getPartyPlanRequests
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/accept
// Accept request
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/requests/:reqId/accept',
    [
        authenticate,
        param('reqId').isUUID().withMessage('reqId must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    acceptPartyPlanRequest
);

// Requester cancellation is valid only before acceptance.
router.post(
    '/requests/:reqId/cancel',
    [
        authenticate,
        param('reqId').isUUID().withMessage('reqId must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('reason').optional().isString().isLength({ max: 500 }),
        validate,
    ],
    cancelPartyPlanRequest
);

// These are distinct pre-payment actions. They never cancel a confirmed plan.
router.post(
    '/requests/:reqId/withdraw',
    [
        authenticate,
        param('reqId').isUUID().withMessage('reqId must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('reason').optional().isString().isLength({ max: 500 }),
        validate,
    ],
    withdrawPartyPlanRequest
);
router.post(
    '/requests/:reqId/revoke',
    [
        authenticate,
        param('reqId').isUUID().withMessage('reqId must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('reason').optional().isString().isLength({ max: 500 }),
        validate,
    ],
    revokePartyPlanAcceptance
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/accept-invite
// Accept an invite from the host
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/requests/:reqId/accept-invite',
    [
        authenticate,
        param('reqId').isUUID().withMessage('reqId must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    acceptPartyPlanInvite
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/confirm-self-paid
// Confirm self-paid request/invite
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/requests/:reqId/confirm-self-paid',
    [
        authenticate,
        param('reqId').isUUID().withMessage('reqId must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    confirmSelfPaidJoin
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/requests/user/:userId
// Joiner view of their own requests
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/requests/user/:userId',
    [
        authenticate,
        param('userId').isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    getJoinerRequests
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/joiner-pay
// Verify joiner payment
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/requests/:reqId/joiner-pay',
    [
        authenticate,
        param('reqId').isUUID().withMessage('reqId must be a valid UUID'),
        body('userId').optional({ checkFalsy: true }).isUUID().withMessage('userId must be a valid UUID'),
        body('razorpay_order_id').notEmpty().withMessage('razorpay_order_id is required'),
        body('razorpay_payment_id').notEmpty().withMessage('razorpay_payment_id is required'),
        // Same rationale as host-pay above — an empty signature is a valid
        // mock-payment signal to the controller and must not 400 here.
        body('razorpay_signature').optional({ checkFalsy: true }).isString().withMessage('razorpay_signature must be a string'),
        validate,
    ],
    verifyJoinerPayment
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/reject
// Reject request
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/requests/:reqId/reject',
    [
        authenticate,
        param('reqId').isUUID().withMessage('reqId must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    rejectPartyPlanRequest
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/initiate-host-payment
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/initiate-host-payment',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').optional({ checkFalsy: true }).isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    initiateHostPayment
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/initiate-joiner-payment
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/requests/:reqId/initiate-joiner-payment',
    [
        authenticate,
        param('reqId').isUUID().withMessage('reqId must be a valid UUID'),
        body('userId').optional({ checkFalsy: true }).isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    initiateJoinerPayment
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/requests/:reqId/ticket
// Fetch a full ticket payload (plan + host photo + joiner photo + ticketCode)
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/requests/:reqId/ticket',
    [
        authenticate,
        param('reqId').isUUID().withMessage('reqId must be a valid UUID'),
        validate,
    ],
    getPartyPlanTicket
);

// Safety Check Endpoints
import { respondToSafetyCheck, getPendingSafetyCheck } from '../controllers/mobileSafetyCheckController';

router.post('/safety-checks/respond', authenticate, respondToSafetyCheck);
router.get('/safety-checks/pending', authenticate, getPendingSafetyCheck);

// Phase 2 & 3 Routes
router.post('/:id/confirm-arrival', authenticate, confirmArrival);
router.post('/:planId/arrival-confirm', authenticate, confirmArrival);
router.get('/:planId/summary', authenticate, getPlanSummary);
router.post('/:id/review', authenticate, submitPartyReview);

export default router;
