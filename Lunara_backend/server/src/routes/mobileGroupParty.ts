import { Router } from 'express';
import { body } from 'express-validator';
import { validate } from '../middleware/validate';
import { authenticate } from '../middleware/auth';
import { calculatePricing, createGroupParty, verifyPayment, getMyGroupParties, getGroupPartyTicket, cancelPendingGroupParty } from '../controllers/mobileGroupPartyController';

const router = Router();

router.get('/', authenticate, getMyGroupParties);
router.get('/:id/ticket', authenticate, getGroupPartyTicket);
router.post('/cancel-pending', authenticate, cancelPendingGroupParty);
router.delete('/:id/cancel', authenticate, cancelPendingGroupParty);

router.post(
    '/calculate-pricing',
    [
        body('venueId').notEmpty().isUUID().withMessage('venueId must be a valid UUID'),
        // This route serves both small (<=20) and large (>20) group party
        // requests — GroupPartyService.resolvePartyType/calculateAuthoritativePricing
        // enforces the real per-venue capacity ceiling. A hardcoded max:20
        // here previously rejected every large-party request outright before
        // it ever reached that logic.
        body('numberOfFriends').isInt({ min: 1, max: 500 }).withMessage('numberOfFriends must be a positive number'),
        validate,
    ],
    calculatePricing
);

router.post(
    '/',
    [
        authenticate,
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('venueId').notEmpty().isUUID().withMessage('venueId must be a valid UUID'),
        // Same reasoning as calculate-pricing above — the true ceiling is the
        // venue's actual capacity, enforced in GroupPartyService.resolvePartyType.
        body('numberOfFriends').isInt({ min: 1, max: 500 }).withMessage('numberOfFriends must be a positive number'),
        body('partyDate').isISO8601().withMessage('partyDate must be a valid date'),
        body('mobileNumber').notEmpty().withMessage('mobileNumber is required'),
        validate,
    ],
    createGroupParty
);

router.post(
    '/verify',
    [
        authenticate,
        body('razorpay_order_id').notEmpty().withMessage('razorpay_order_id is required'),
        body('razorpay_payment_id').notEmpty().withMessage('razorpay_payment_id is required'),
        body('razorpay_signature').notEmpty().withMessage('razorpay_signature is required'),
        validate,
    ],
    verifyPayment
);

export default router;
