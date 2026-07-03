import { Router } from 'express';
import { body } from 'express-validator';
import { validate } from '../middleware/validate';
import { calculatePricing, createGroupParty, verifyPayment } from '../controllers/mobileGroupPartyController';

const router = Router();

router.post(
    '/calculate-pricing',
    [
        body('venueId').notEmpty().isUUID().withMessage('venueId must be a valid UUID'),
        body('numberOfFriends').isInt({ min: 1, max: 20 }).withMessage('numberOfFriends must be between 1 and 20'),
        validate,
    ],
    calculatePricing
);

router.post(
    '/',
    [
        body('userId').notEmpty().isUUID().withMessage('userId must be a valid UUID'),
        body('venueId').notEmpty().isUUID().withMessage('venueId must be a valid UUID'),
        body('numberOfFriends').isInt({ min: 1, max: 20 }).withMessage('numberOfFriends must be between 1 and 20'),
        body('partyDate').isISO8601().withMessage('partyDate must be a valid date'),
        validate,
    ],
    createGroupParty
);

router.post(
    '/verify',
    [
        body('razorpay_order_id').notEmpty().withMessage('razorpay_order_id is required'),
        body('razorpay_payment_id').notEmpty().withMessage('razorpay_payment_id is required'),
        body('razorpay_signature').notEmpty().withMessage('razorpay_signature is required'),
        validate,
    ],
    verifyPayment
);

export default router;
