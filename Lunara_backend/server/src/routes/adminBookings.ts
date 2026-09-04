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

// GET /api/admin/bookings/venue-summary
router.get('/venue-summary', ctrl.getVenueWiseBookingSummary);

// GET /api/admin/bookings/venue-revenue-details
router.get('/venue-revenue-details', ctrl.getVenueRevenueDetails);

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

// POST /api/admin/bookings/:id/confirm
router.post(
    '/:id/confirm',
    [param('id').isUUID().withMessage('id must be a UUID'), validate],
    ctrl.confirmBooking
);

// POST /api/admin/bookings/:id/cancel
router.post(
    '/:id/cancel',
    [
        param('id').isUUID().withMessage('id must be a UUID'),
        body('reason').notEmpty().withMessage('reason is required'),
        validate
    ],
    ctrl.cancelBooking
);

// POST /api/admin/bookings/:id/complete
router.post(
    '/:id/complete',
    [param('id').isUUID().withMessage('id must be a UUID'), validate],
    ctrl.markCompleted
);

// POST /api/admin/bookings/:id/no-show
router.post(
    '/:id/no-show',
    [param('id').isUUID().withMessage('id must be a UUID'), validate],
    ctrl.markNoShow
);

// ─── Large Party Cancellation Management ────────────────────────────────────

// GET /api/admin/bookings/large-party-cancellations
router.get(
    '/large-party-cancellations',
    async (req: any, res: any) => {
        const { LargePartyCancellationController } = await import('../controllers/largePartyCancellationController');
        return LargePartyCancellationController.getAdminCancellations(req, res);
    }
);

// GET /api/admin/bookings/large-party-cancellations/:id
router.get(
    '/large-party-cancellations/:id',
    [param('id').isUUID().withMessage('id must be a UUID'), validate],
    async (req: any, res: any) => {
        const { LargePartyCancellationController } = await import('../controllers/largePartyCancellationController');
        return LargePartyCancellationController.getAdminCancellationDetail(req, res);
    }
);

// POST /api/admin/bookings/large-party-cancellations/:id/approve
router.post(
    '/large-party-cancellations/:id/approve',
    [
        param('id').isUUID().withMessage('id must be a UUID'),
        body('refundPercentage').isFloat({ min: 0, max: 100 }).withMessage('refundPercentage must be between 0 and 100'),
        validate,
    ],
    async (req: any, res: any) => {
        const { LargePartyCancellationController } = await import('../controllers/largePartyCancellationController');
        return LargePartyCancellationController.adminApproveCancellation(req, res);
    }
);

// POST /api/admin/bookings/large-party-cancellations/:id/reject
router.post(
    '/large-party-cancellations/:id/reject',
    [
        param('id').isUUID().withMessage('id must be a UUID'),
        body('rejectionReason').notEmpty().withMessage('rejectionReason is required'),
        validate,
    ],
    async (req: any, res: any) => {
        const { LargePartyCancellationController } = await import('../controllers/largePartyCancellationController');
        return LargePartyCancellationController.adminRejectCancellation(req, res);
    }
);

// POST /api/admin/bookings/large-party-cancellations/:id/mark-paid
router.post(
    '/large-party-cancellations/:id/mark-paid',
    [
        param('id').isUUID().withMessage('id must be a UUID'),
        body('paymentReference').notEmpty().withMessage('paymentReference is required'),
        validate,
    ],
    async (req: any, res: any) => {
        const { LargePartyCancellationController } = await import('../controllers/largePartyCancellationController');
        return LargePartyCancellationController.adminMarkRefundPaid(req, res);
    }
);

// ─── Group Party & With-Friends Cancellations (> ₹1,500) ────────────────────

// GET /api/admin/bookings/group-party-cancellations
router.get(
    '/group-party-cancellations',
    async (req: any, res: any) => {
        const { AdminCancellationController } = await import('../controllers/adminCancellationController');
        return AdminCancellationController.getGroupPartyCancellations(req, res);
    }
);

// GET /api/admin/bookings/group-party-cancellations/:id
router.get(
    '/group-party-cancellations/:id',
    [param('id').isUUID().withMessage('id must be a UUID'), validate],
    async (req: any, res: any) => {
        const { AdminCancellationController } = await import('../controllers/adminCancellationController');
        return AdminCancellationController.getGroupPartyCancellationDetail(req, res);
    }
);

// POST /api/admin/bookings/group-party-cancellations/:id/mark-paid
router.post(
    '/group-party-cancellations/:id/mark-paid',
    [
        param('id').isUUID().withMessage('id must be a UUID'),
        body('paymentReference').notEmpty().withMessage('paymentReference is required'),
        validate,
    ],
    async (req: any, res: any) => {
        const { AdminCancellationController } = await import('../controllers/adminCancellationController');
        return AdminCancellationController.markGroupPartyRefundPaid(req, res);
    }
);

export default router;

