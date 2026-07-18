import { Router } from 'express';
import { param, body } from 'express-validator';
import { validate } from '../middleware/validate';
import * as ctrl from '../controllers/adminBookingController';
import { authenticate, authorize } from '../middleware/auth';
import { UserRole } from '../models/User';

const router = Router();

// Apply auth middleware to all admin bookings routes
router.use(authenticate);
router.use(authorize(UserRole.ADMIN, UserRole.VENUE_OWNER));

// GET /api/admin/bookings
router.get('/', ctrl.getBookings);

// GET /api/admin/bookings/stats
router.get('/stats', ctrl.getBookingStats);

// GET /api/admin/bookings/large-party-requests
router.get('/large-party-requests', ctrl.getLargePartyRequests);

// POST /api/admin/bookings/:id/approve-party-request
router.post(
    '/:id/approve-party-request',
    [
        param('id').isUUID().withMessage('id must be a UUID'),
        body('status').isIn(['approved', 'rejected']).withMessage('status must be approved or rejected'),
        validate,
    ],
    ctrl.approveLargePartyRequest
);

// POST /api/admin/bookings/:id/send-payment-link
router.post(
    '/:id/send-payment-link',
    [
        param('id').isUUID().withMessage('id must be a UUID'),
        body('paymentLink').notEmpty().withMessage('paymentLink is required'),
        body('paymentAmount').isFloat({ gt: 0 }).withMessage('paymentAmount must be > 0'),
        validate,
    ],
    ctrl.sendPaymentLink
);

// POST /api/admin/bookings/:id/mark-payment-done
router.post(
    '/:id/mark-payment-done',
    [param('id').isUUID().withMessage('id must be a UUID'), validate],
    ctrl.markPaymentDone
);

export default router;
