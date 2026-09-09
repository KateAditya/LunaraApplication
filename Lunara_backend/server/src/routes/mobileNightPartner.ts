import { Router } from 'express';
import { body, param, query } from 'express-validator';
import { validate } from '../middleware/validate';
import { authenticate } from '../middleware/auth';
import ctrl from '../controllers/mobileNightPartnerController';

const router = Router();

/**
 * GET /api/mobile/nights/check-interest?userId=<uuid>&venueId=<uuid>&eventDate=YYYY-MM-DD
 * Check if user is interested in an upcoming night
 */
router.get(
    '/check-interest',
    [
        authenticate,
        query('userId').notEmpty().withMessage('userId is required'),
        query('venueId').notEmpty().withMessage('venueId is required'),
        query('eventDate').isISO8601().withMessage('eventDate must be YYYY-MM-DD'),
        validate,
    ],
    ctrl.checkUserInterest
);

/**
 * POST /api/mobile/nights/interested
 * Mark interest in an upcoming night event
 */
router.post(
    '/interested',
    [
        authenticate,
        body('userId').notEmpty().withMessage('userId is required'),
        body('venueId').notEmpty().withMessage('venueId is required'),
        body('eventDate').isISO8601().withMessage('eventDate must be YYYY-MM-DD'),
        validate,
    ],
    ctrl.markInterested
);

/**
 * DELETE /api/mobile/nights/interested
 * Remove interest in an upcoming night event
 */
router.delete(
    '/interested',
    [
        authenticate,
        body('userId').notEmpty().withMessage('userId is required'),
        body('venueId').notEmpty().withMessage('venueId is required'),
        body('eventDate').isISO8601().withMessage('eventDate must be YYYY-MM-DD'),
        validate,
    ],
    ctrl.removeInterest
);

/**
 * GET /api/mobile/nights/interested-partners?hostId=<uuid>&venueId=<uuid>&eventDate=YYYY-MM-DD
 * Get list of interested partners for Host Dashboard
 */
router.get(
    '/interested-partners',
    [
        authenticate,
        query('hostId').optional(),
        query('venueId').notEmpty().withMessage('venueId is required'),
        query('eventDate').notEmpty().withMessage('eventDate is required'),
        validate,
    ],
    ctrl.getInterestedPartners
);

/**
 * GET /api/mobile/nights/available-invitees?hostId=<uuid>&venueId=<uuid>&eventDate=YYYY-MM-DD&search=
 * Get list of available users who have NO existing plan or booking for that date
 */
router.get(
    '/available-invitees',
    [
        authenticate,
        query('hostId').optional(),
        query('venueId').notEmpty().withMessage('venueId is required'),
        query('eventDate').notEmpty().withMessage('eventDate is required'),
        validate,
    ],
    ctrl.getAvailableInvitees
);

/**
 * GET /api/mobile/nights/partners/:userId/profile
 * Get safe partner profile preview for Host
 */
router.get(
    '/partners/:userId/profile',
    [authenticate, param('userId').notEmpty().withMessage('userId is required'), validate],
    ctrl.getPartnerProfilePreview
);

/**
 * POST /api/mobile/nights/invite-payment/initiate
 * Host initiates payment for sending an invitation (Self Pay vs Split)
 */
router.post(
    '/invite-payment/initiate',
    [
        authenticate,
        body('venueId').notEmpty().withMessage('venueId is required'),
        body('eventDate').notEmpty().withMessage('eventDate is required'),
        body('paymentMode').isIn(['SELF_PAY', 'SPLIT']).withMessage('paymentMode must be SELF_PAY or SPLIT'),
        validate,
    ],
    ctrl.initiateInviteOrder
);

/**
 * POST /api/mobile/nights/invite-payment/verify
 * Host verifies payment and sends the invitation
 */
router.post(
    '/invite-payment/verify',
    [
        authenticate,
        body('partnerId').notEmpty().withMessage('partnerId is required'),
        body('venueId').notEmpty().withMessage('venueId is required'),
        body('eventDate').notEmpty().withMessage('eventDate is required'),
        body('paymentMode').isIn(['SELF_PAY', 'SPLIT']).withMessage('paymentMode must be SELF_PAY or SPLIT'),
        validate,
    ],
    ctrl.verifyInvitePaymentAndSend
);

/**
 * POST /api/mobile/nights/requests
 * Host sends a partner request
 */
router.post(
    '/requests',
    [
        authenticate,
        body('hostId').optional(),
        body('partnerId').notEmpty().withMessage('partnerId is required'),
        body('venueId').notEmpty().withMessage('venueId is required'),
        body('eventDate').notEmpty().withMessage('eventDate is required'),
        validate,
    ],
    ctrl.sendPartnerRequest
);

/**
 * PATCH /api/mobile/nights/requests/:id
 * Partner accepts or declines a partner request
 */
router.patch(
    '/requests/:id',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a UUID'),
        body('partnerId').notEmpty().withMessage('partnerId is required'),
        body('action').isIn(['accept', 'decline']).withMessage('action must be accept or decline'),
        validate,
    ],
    ctrl.respondToRequest
);

/**
 * DELETE /api/mobile/nights/requests/:id
 * Host cancels a pending request
 */
router.delete(
    '/requests/:id',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a UUID'),
        body('hostId').notEmpty().withMessage('hostId is required'),
        validate,
    ],
    ctrl.cancelRequest
);

/**
 * POST /api/mobile/nights/matches/:id/pay
 * Initiate payment for host match
 */
router.post(
    '/matches/:id/pay',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a UUID'),
        validate,
    ],
    ctrl.initiateMatchPayment
);

/**
 * POST /api/mobile/nights/matches/:id/verify
 * Verify payment and confirm match + unlock chat
 */
router.post(
    '/matches/:id/verify',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a UUID'),
        validate,
    ],
    ctrl.verifyMatchPayment
);

/**
 * POST /api/mobile/nights/cancel/:id
 * Cancel an upcoming night match or request
 */
router.post(
    '/cancel/:id',
    [
        authenticate,
        param('id').isUUID().withMessage('id must be a UUID'),
        validate,
    ],
    ctrl.cancelUpcomingNight
);

/**
 * GET /api/mobile/nights/event-posts
 * Get list of all event posts with interested count & stats
 */
router.get(
    '/event-posts',
    [authenticate],
    ctrl.getEventPosts
);

export default router;
