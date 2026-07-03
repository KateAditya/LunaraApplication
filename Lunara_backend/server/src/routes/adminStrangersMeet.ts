import { Router } from 'express';
import { body, param, query } from 'express-validator';
import { validate } from '../middleware/validate';
import {
    getAllRequests,
    approveRequest,
    rejectRequest,
} from '../controllers/strangersMeetController';

const router = Router();

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/strangers-meet
// Admin — list all requests
// Query: ?status=pending|approved|rejected  ?page=1  ?limit=20
// ─────────────────────────────────────────────────────────────────────────────
router.get(
    '/',
    [
        query('status').optional().isIn(['pending', 'approved', 'rejected']).withMessage('Invalid status'),
        query('page').optional().isInt({ min: 1 }).withMessage('page must be a positive integer'),
        query('limit').optional().isInt({ min: 1, max: 100 }).withMessage('limit must be between 1 and 100'),
        validate,
    ],
    getAllRequests
);

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/admin/strangers-meet/:id/approve
// Admin approves a request and sets the payment amount
// Body: { paymentAmount: number, adminNotes?: string }
// ─────────────────────────────────────────────────────────────────────────────
router.patch(
    '/:id/approve',
    [
        param('id').isUUID().withMessage('id must be a valid UUID'),
        body('paymentAmount')
            .notEmpty().withMessage('paymentAmount is required')
            .isFloat({ gt: 0 }).withMessage('paymentAmount must be greater than 0'),
        body('adminNotes').optional().isString(),
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

export default router;
