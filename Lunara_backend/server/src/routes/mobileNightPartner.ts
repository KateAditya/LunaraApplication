import { Router } from 'express';
import { body, param, query } from 'express-validator';
import { validate } from '../middleware/validate';
import ctrl from '../controllers/mobileNightPartnerController';

const router = Router();

/**
 * POST /api/mobile/nights/interested
 * Mark interest in an upcoming night event
 */
router.post(
    '/interested',
    [
        body('userId').notEmpty().withMessage('userId is required'),
        body('venueId').isUUID().withMessage('venueId must be a UUID'),
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
        body('userId').notEmpty().withMessage('userId is required'),
        body('venueId').isUUID().withMessage('venueId must be a UUID'),
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
        query('hostId').notEmpty().withMessage('hostId is required'),
        query('venueId').isUUID().withMessage('venueId must be a UUID'),
        query('eventDate').isISO8601().withMessage('eventDate must be YYYY-MM-DD'),
        validate,
    ],
    ctrl.getInterestedPartners
);

/**
 * GET /api/mobile/nights/partners/:userId/profile
 * Get safe partner profile preview for Host
 */
router.get(
    '/partners/:userId/profile',
    [param('userId').isUUID().withMessage('userId must be a UUID'), validate],
    ctrl.getPartnerProfilePreview
);

/**
 * POST /api/mobile/nights/requests
 * Host sends a partner request
 */
router.post(
    '/requests',
    [
        body('hostId').notEmpty().withMessage('hostId is required'),
        body('partnerId').isUUID().withMessage('partnerId must be a UUID'),
        body('venueId').isUUID().withMessage('venueId must be a UUID'),
        body('eventDate').isISO8601().withMessage('eventDate must be YYYY-MM-DD'),
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
        param('id').isUUID().withMessage('id must be a UUID'),
        body('hostId').notEmpty().withMessage('hostId is required'),
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
        param('id').isUUID().withMessage('id must be a UUID'),
        body('razorpay_order_id').notEmpty().withMessage('razorpay_order_id is required'),
        body('razorpay_payment_id').notEmpty().withMessage('razorpay_payment_id is required'),
        body('razorpay_signature').notEmpty().withMessage('razorpay_signature is required'),
        validate,
    ],
    ctrl.verifyMatchPayment
);

export default router;
