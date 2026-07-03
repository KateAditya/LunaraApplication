import { Router } from 'express';
import { body, param } from 'express-validator';
import { validate } from '../middleware/validate';
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
    getJoinerRequests,
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
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('razorpay_order_id').notEmpty().withMessage('razorpay_order_id is required'),
        body('razorpay_payment_id').notEmpty().withMessage('razorpay_payment_id is required'),
        body('razorpay_signature').notEmpty().withMessage('razorpay_signature is required'),
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
router.get('/', getAllPartyPlans);

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
    [param('userId').isUUID().withMessage('userId must be a valid UUID'), validate],
    getPlansByUser
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/:id
// Get a single party plan by ID
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/:id',
    [param('id').isUUID().withMessage('id must be a valid UUID'), validate],
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
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    cancelPartyPlan
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/requests
// Request to join a party plan
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/requests',
    [
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
        param('reqId').isUUID().withMessage('reqId must be a valid UUID'),
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        validate,
    ],
    acceptPartyPlanRequest
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/requests/user/:userId
// Joiner view of their own requests
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/requests/user/:userId',
    [
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
        param('reqId').isUUID().withMessage('reqId must be a valid UUID'),
        body('razorpay_order_id').notEmpty().withMessage('razorpay_order_id is required'),
        body('razorpay_payment_id').notEmpty().withMessage('razorpay_payment_id is required'),
        body('razorpay_signature').notEmpty().withMessage('razorpay_signature is required'),
        validate,
    ],
    verifyJoinerPayment
);

export default router;
