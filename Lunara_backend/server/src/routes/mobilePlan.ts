import { Router } from 'express';
import { body, param } from 'express-validator';
import { validate } from '../middleware/validate';
import { optionalAuth } from '../middleware/auth';
import ctrl from '../controllers/mobilePlanController';

const router = Router();

// ─── User's own plans ────────────────────────────────────────────────────────

router.get('/eligibility', ctrl.checkEligibility);

/**
 * GET /api/mobile/plans/my-plans?userId=<uuid>
 * Lists all plans the calling user has posted.
 */
router.get('/my-plans', ctrl.getMyPlans);

/**
 * GET /api/mobile/plans/my-joins?userId=<uuid>
 * Lists all plans the calling user has joined.
 */
router.get('/my-joins', ctrl.getMyJoins);

// ─── Live Feed ───────────────────────────────────────────────────────────────

/**
 * GET /api/mobile/plans/live-feed
 * Returns all active plans (optionally filtered by venueId, date).
 * Query: ?viewerId=<uuid>&venueId=<uuid>&date=YYYY-MM-DD
 */
router.get('/live-feed', optionalAuth, ctrl.getLiveFeed);

// ─── Post a Plan ─────────────────────────────────────────────────────────────

/**
 * POST /api/mobile/plans
 * Creates a new plan and posts it to the Live Feed.
 * Body: { userId, venueId, planDate, startTime, tablePackage, paymentOption?, description? }
 */
router.post(
    '/',
    [
        body('userId').notEmpty().withMessage('userId is required'),
        body('venueId').isUUID().withMessage('venueId must be a UUID'),
        body('planDate').isISO8601().withMessage('planDate must be YYYY-MM-DD'),
        body('startTime').notEmpty().withMessage('startTime is required (e.g. "22:00")'),
        body('tablePackage')
            .isIn(['silver', 'gold', 'platinum'])
            .withMessage('tablePackage must be silver, gold, or platinum'),
        body('paymentOption')
            .optional()
            .isIn(['full', 'split'])
            .withMessage('paymentOption must be "full" or "split"'),
        validate,
    ],
    ctrl.postPlan
);

// ─── Plan sub-routes — MUST all be before GET /:id ───────────────────────────

/**
 * POST /api/mobile/plans/:id/join
 * Send join request + simulate payment (dummy).
 * Body: { requesterId, message? }
 */
router.post(
    '/:id/join',
    [
        param('id').isUUID(),
        body('requesterId').notEmpty().withMessage('requesterId is required'),
        validate,
    ],
    ctrl.joinPlan
);

/**
 * GET /api/mobile/plans/:id/split-status
 * Returns current split payment status for the plan's payment screen.
 */
router.get('/:id/split-status', [param('id').isUUID(), validate], ctrl.getSplitStatus);

/**
 * POST /api/mobile/plans/:id/secure-reservation
 * Locks in the reservation → creates Booking + generates digital ticket.
 * Body: { userId }
 */
router.post(
    '/:id/secure-reservation',
    [param('id').isUUID(), body('userId').optional(), validate],
    ctrl.securePlanReservation
);

/**
 * GET /api/mobile/plans/:id/ticket
 * Returns the digital ticket for a secured plan.
 */
router.get('/:id/ticket', [param('id').isUUID(), validate], ctrl.getPlanTicket);

/**
 * POST /api/mobile/plans/:id/add-to-wallet
 * Marks plan booking as added to wallet → status = completed.
 */
router.post(
    '/:id/add-to-wallet',
    [param('id').isUUID(), validate],
    ctrl.addPlanToWallet
);

import {
    createCancellationRequest,
    getCancellationRequest,
    respondToCancellationRequest,
} from '../controllers/cancellationController';

/**
 * POST /api/mobile/plans/:id/cancellation-request
 * Initiates a mutual cancellation request for a confirmed Party Plan
 */
router.post(
    '/:id/cancellation-request',
    [param('id').isUUID(), validate],
    createCancellationRequest
);

/**
 * GET /api/mobile/plans/:id/cancellation-request
 * Returns cancellation request status for a Party Plan
 */
router.get(
    '/:id/cancellation-request',
    [param('id').isUUID(), validate],
    getCancellationRequest
);

/**
 * POST /api/mobile/plans/:id/cancellation-request/respond
 * Recipient approves or rejects a cancellation request
 */
router.post(
    '/:id/cancellation-request/respond',
    [param('id').isUUID(), validate],
    respondToCancellationRequest
);

// ─── Generic plan detail — MUST be last among GET /:id routes ────────────────

/**
 * GET /api/mobile/plans/:id
 * Full plan details — opens "See Details" profile card.
 * Query: ?viewerId=<uuid>  (for match score)
 */
router.get('/:id', [param('id').isUUID(), validate], ctrl.getPlanDetail);

export default router;
