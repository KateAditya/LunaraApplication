import { Router } from 'express';
import { body, param, query } from 'express-validator';
import { validate } from '../middleware/validate';
import { authenticate, optionalAuth } from '../middleware/auth';
import ctrl from '../controllers/mobileBookingController';

const router = Router();

// ─── Venue-scoped helpers ────────────────────────────────────────────────────

/**
 * GET /api/mobile/bookings/venues/:venueId/packages
 * Returns Silver / Gold / Platinum table packages for a venue.
 * Auto-seeds defaults if none exist.
 */
router.get(
    '/venues/:venueId/packages',
    [param('venueId').isUUID().withMessage('venueId must be a UUID'), validate],
    ctrl.getTablePackages
);

/**
 * GET /api/mobile/bookings/venues/:venueId/timeslots?date=YYYY-MM-DD
 * Returns available time slots for a venue on a given date.
 */
router.get(
    '/venues/:venueId/timeslots',
    [
        param('venueId').isUUID().withMessage('venueId must be a UUID'),
        query('date').optional().isISO8601().withMessage('date must be YYYY-MM-DD'),
        validate,
    ],
    ctrl.getTimeSlots
);

// ─── Booking CRUD ────────────────────────────────────────────────────────────

/**
 * POST /api/mobile/bookings
 * Creates a booking (status=pending). User then chooses Pay Now or Split Bill.
 */
router.post(
    '/',
    [
        authenticate,
        body('userId').notEmpty().withMessage('userId is required'),
        body('venueId').notEmpty().withMessage('venueId is required'),
        body('bookingDate').isISO8601().withMessage('bookingDate must be YYYY-MM-DD'),
        body('startTime').notEmpty().withMessage('startTime is required (e.g. "22:00")'),
        body('tablePackage')
            .optional({ nullable: true, checkFalsy: true })
            .isString()
            .withMessage('tablePackage is invalid'),
        body('goingMode')
            .optional({ nullable: true, checkFalsy: true })
            .isString()
            .withMessage('goingMode must be string'),
        body('numberOfGuests').optional({ nullable: true, checkFalsy: true }).isNumeric(),
        body('partySubject').optional({ nullable: true, checkFalsy: true }).isString(),
        body('partyRequirement').optional({ nullable: true, checkFalsy: true }).isString(),
        body('partyDescription').optional({ nullable: true, checkFalsy: true }).isString(),
        body('mobileNumber').optional({ nullable: true, checkFalsy: true }).isString(),
        body('optionalMobileNumber').optional({ nullable: true, checkFalsy: true }).isString(),
        body('isUpcomingNight').optional({ nullable: true }).isBoolean(),
        validate,
    ],
    ctrl.createBooking
);

/**
 * POST /api/mobile/bookings/party-event
 * Creates a Party Event booking
 */
router.post(
    '/party-event',
    [
        authenticate,
        body('userId').notEmpty().withMessage('userId is required'),
        body('partyEventId').notEmpty().withMessage('partyEventId is required'),
        body('quantity').isInt({ min: 1 }).withMessage('quantity must be at least 1'),
        validate,
    ],
    ctrl.createPartyBooking
);

/**
 * GET /api/mobile/bookings
 * List all bookings for a user. Query: ?userId=<uuid>
 */
router.get('/', optionalAuth, ctrl.listMyBookings);

// ─── Payment actions ──────────────────────────────────────────────────────────
// NOTE: All specific /:id/sub-routes MUST be declared before GET /:id
// to prevent Express matching /:id first and treating the sub-path as the id.

/**
 * POST /api/mobile/bookings/:id/pay-now
 * Simulate full payment → booking confirmed → ticket generated.
 */
router.post(
    '/:id/pay-now',
    [authenticate, param('id').notEmpty().withMessage('id is required'), validate],
    ctrl.payNow
);

/**
 * POST /api/mobile/bookings/:id/initiate-large-party-payment
 * Create Razorpay Order for Large Party Booking.
 */
router.post(
    '/:id/initiate-large-party-payment',
    [authenticate, param('id').notEmpty().withMessage('id is required'), validate],
    ctrl.initiateLargePartyPayment
);

/**
 * POST /api/mobile/bookings/:id/verify-large-party-payment
 * Verify signature of Razorpay Payment for Large Party Booking.
 */
router.post(
    '/:id/verify-large-party-payment',
    [
        authenticate,
        param('id').notEmpty().withMessage('id is required'),
        body('razorpay_order_id').notEmpty().withMessage('razorpay_order_id is required'),
        body('razorpay_payment_id').notEmpty().withMessage('razorpay_payment_id is required'),
        body('razorpay_signature').notEmpty().withMessage('razorpay_signature is required'),
        validate,
    ],
    ctrl.verifyLargePartyPayment
);

/**
 * POST /api/mobile/bookings/:id/split-bill
 * Set up split payment with named members.
 */
router.post(
    '/:id/split-bill',
    [
        authenticate,
        param('id').notEmpty().withMessage('id is required'),
        body('members').isArray({ min: 1 }).withMessage('members must be a non-empty array'),
        body('members.*.name').notEmpty().withMessage('Each member must have a name'),
        body('members.*.shareAmount').isNumeric().withMessage('Each member must have a shareAmount'),
        validate,
    ],
    ctrl.setupSplitBill
);

/**
 * POST /api/mobile/bookings/:id/split-bill/pay
 * Simulate one member's payment.
 */
router.post(
    '/:id/split-bill/pay',
    [
        authenticate,
        param('id').notEmpty().withMessage('id is required'),
        body('memberId').isUUID().withMessage('memberId must be a UUID'),
        validate,
    ],
    ctrl.payMySplit
);

/**
 * POST /api/mobile/bookings/:id/secure-reservation
 * Lock in the reservation → ticket generated.
 */
router.post(
    '/:id/secure-reservation',
    [authenticate, param('id').notEmpty().withMessage('id is required'), validate],
    ctrl.secureReservation
);

// ─── Ticket actions ───────────────────────────────────────────────────────────

/**
 * GET /api/mobile/bookings/:id/ticket
 * Returns digital ticket data (ticketCode for QR, venue, date, status).
 */
router.get(
    '/:id/ticket',
    [authenticate, param('id').notEmpty().withMessage('id is required'), validate],
    ctrl.getTicket
);

/**
 * POST /api/mobile/bookings/:id/add-to-wallet
 * Marks booking as added to Apple Wallet → status = completed.
 */
router.post(
    '/:id/add-to-wallet',
    [authenticate, param('id').notEmpty().withMessage('id is required'), validate],
    ctrl.addToWallet
);

// ─── Generic booking detail — MUST be last among GET /:id routes ─────────────

/**
 * GET /api/mobile/bookings/:id
 * Full booking detail including group/split members.
 */
router.get('/:id', [authenticate, param('id').notEmpty().withMessage('id is required'), validate], ctrl.getBookingDetail);

export default router;
