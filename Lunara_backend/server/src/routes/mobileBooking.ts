import { Router } from 'express';
import { body, param, query } from 'express-validator';
import { validate } from '../middleware/validate';
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
        body('userId').notEmpty().withMessage('userId is required'),
        body('venueId').isUUID().withMessage('venueId must be a UUID'),
        body('bookingDate').isISO8601().withMessage('bookingDate must be YYYY-MM-DD'),
        body('startTime').notEmpty().withMessage('startTime is required (e.g. "22:00")'),
        body('tablePackage')
            .optional()
            .isIn(['silver', 'gold', 'platinum', 'Confirmation Charges', 'none'])
            .withMessage('tablePackage is invalid'),
        body('goingMode')
            .optional()
            .isIn(['solo', 'party_request'])
            .withMessage('goingMode must be solo or party_request'),
        body('numberOfGuests').optional().isNumeric(),
        body('partySubject').optional().isString(),
        body('partyRequirement').optional().isString(),
        body('partyDescription').optional().isString(),
        validate,
    ],
    ctrl.createBooking
);

/**
 * GET /api/mobile/bookings
 * List all bookings for a user. Query: ?userId=<uuid>
 */
router.get('/', ctrl.listMyBookings);

// ─── Payment actions ──────────────────────────────────────────────────────────
// NOTE: All specific /:id/sub-routes MUST be declared before GET /:id
// to prevent Express matching /:id first and treating the sub-path as the id.

/**
 * POST /api/mobile/bookings/:id/pay-now
 * Simulate full payment → booking confirmed → ticket generated.
 */
router.post(
    '/:id/pay-now',
    [param('id').isUUID(), validate],
    ctrl.payNow
);

/**
 * POST /api/mobile/bookings/:id/initiate-large-party-payment
 * Create Razorpay Order for Large Party Booking.
 */
router.post(
    '/:id/initiate-large-party-payment',
    [param('id').isUUID(), validate],
    ctrl.initiateLargePartyPayment
);

/**
 * POST /api/mobile/bookings/:id/verify-large-party-payment
 * Verify signature of Razorpay Payment for Large Party Booking.
 */
router.post(
    '/:id/verify-large-party-payment',
    [
        param('id').isUUID(),
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
        param('id').isUUID(),
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
        param('id').isUUID(),
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
    [param('id').isUUID(), validate],
    ctrl.secureReservation
);

// ─── Ticket actions ───────────────────────────────────────────────────────────

/**
 * GET /api/mobile/bookings/:id/ticket
 * Returns digital ticket data (ticketCode for QR, venue, date, status).
 */
router.get(
    '/:id/ticket',
    [param('id').isUUID(), validate],
    ctrl.getTicket
);

/**
 * POST /api/mobile/bookings/:id/add-to-wallet
 * Marks booking as added to Apple Wallet → status = completed.
 */
router.post(
    '/:id/add-to-wallet',
    [param('id').isUUID(), validate],
    ctrl.addToWallet
);

// ─── Generic booking detail — MUST be last among GET /:id routes ─────────────

/**
 * GET /api/mobile/bookings/:id
 * Full booking detail including group/split members.
 */
router.get('/:id', [param('id').isUUID(), validate], ctrl.getBookingDetail);

export default router;
