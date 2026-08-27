import { Router } from 'express';
import { body, param, query } from 'express-validator';
import { validate } from '../middleware/validate';
import {
    getAllRequests,
    approveRequest,
    rejectRequest,
    paySettlement,
    approveSettlementPayout,
    adminConfirmEnded,
    adminMarkSettled,
    getNeedsHostContact,
    resolveEscalation,
    getSettlementSummary,
} from '../controllers/strangersMeetController';

const router = Router();

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/strangers-meet
// Admin — list all requests
// Query: ?status=pending|approved|in_progress|completed|needs_contact|payouts|all  ?page=1  ?limit=20
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/',
    [
        query('status').optional().isString().withMessage('Invalid status'),
        query('page').optional().isInt({ min: 1 }).withMessage('page must be a positive integer'),
        query('limit').optional().isInt({ min: 1, max: 100 }).withMessage('limit must be between 1 and 100'),
        validate,
    ],
    getAllRequests
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/strangers-meet/needs-contact
// Admin — list requests requiring host contact (24h timeout escalation)
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/needs-contact',
    [
        query('page').optional().isInt({ min: 1 }).withMessage('page must be a positive integer'),
        query('limit').optional().isInt({ min: 1, max: 100 }).withMessage('limit must be between 1 and 100'),
        validate,
    ],
    getNeedsHostContact
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/strangers-meet/:id/settlement-summary
// Admin — get automated settlement calculation breakdown
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/:id/settlement-summary',
    [
        param('id').isUUID().withMessage('id must be a valid UUID'),
        validate,
    ],
    getSettlementSummary
);

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/admin/strangers-meet/:id/approve
// Admin approves a request and sets the payment amount
// Body: { paymentAmount: number, adminNotes?: string }
// ─────────────────────────────────────────────────────────────────────────────
router.patch(
    '/:id/approve',
    [
        param('id').notEmpty().withMessage('id is required'),
        validate,
    ],
    approveRequest
);
router.post(
    '/:id/approve',
    [
        param('id').notEmpty().withMessage('id is required'),
        validate,
    ],
    approveRequest
);
router.put(
    '/:id/approve',
    [
        param('id').notEmpty().withMessage('id is required'),
        validate,
    ],
    approveRequest
);

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/admin/strangers-meet/:id/reject
// Admin rejects a request
// Body: { adminNotes?: string }
// ─────────────────────────────────────────────────────────────────────────────
router.patch(
    '/:id/reject',
    [
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('adminNotes').optional().isString(),
        validate,
    ],
    rejectRequest
);

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/admin/strangers-meet/:id/confirm-ended
// Admin confirms meetup ended (starts 24h settlement window)
// ─────────────────────────────────────────────────────────────────────────────
router.patch(
    '/:id/confirm-ended',
    [
        param('id').isUUID().withMessage('id must be a valid UUID'),
        validate,
    ],
    adminConfirmEnded
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/admin/strangers-meet/:id/mark-settled
// Admin confirms payout and marks amount as settled
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/mark-settled',
    [
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('paymentReference').notEmpty().withMessage('paymentReference is required'),
        body('settlementMethod').optional().isString(),
        body('amount').optional().isFloat({ min: 0 }),
        validate,
    ],
    adminMarkSettled
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/admin/strangers-meet/:id/resolve-escalation
// Admin resolves 24-hour escalation case
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/resolve-escalation',
    [
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('resolution').notEmpty().withMessage('resolution is required'),
        body('resolutionNotes').optional().isString(),
        validate,
    ],
    resolveEscalation
);

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/admin/strangers-meet/:id/approve-settlement
// Admin approves payout request (notifies user amount credited in 24 hours)
// ─────────────────────────────────────────────────────────────────────────────
router.patch(
    '/:id/approve-settlement',
    [
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('settlementAmount').optional().isFloat({ gt: 0 }).withMessage('settlementAmount must be greater than 0'),
        validate,
    ],
    approveSettlementPayout
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/admin/strangers-meet/:id/pay-settlement
// Admin records settlement payout details
// ─────────────────────────────────────────────────────────────────────────────
router.post(
    '/:id/pay-settlement',
    [
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('transactionId').notEmpty().withMessage('transactionId is required'),
        body('amount').notEmpty().isFloat({ gt: 0 }).withMessage('amount must be greater than 0'),
        body('paymentDate').optional().isISO8601().withMessage('Invalid payment date'),
        body('paymentMethod').optional().isString(),
        validate,
    ],
    paySettlement
);

export default router;
