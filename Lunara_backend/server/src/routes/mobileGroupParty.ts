import { Router } from 'express';
import { body } from 'express-validator';
import { validate } from '../middleware/validate';
import { calculatePricing, createGroupParty, verifyPayment, getMyGroupParties, getGroupPartyTicket } from '../controllers/mobileGroupPartyController';

const router = Router();

router.get('/', getMyGroupParties);
router.get('/:id/ticket', getGroupPartyTicket);

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
        // The service routes 1–20 people to GroupParty and larger groups to
        // the admin-approved large-party Booking workflow.
        body('numberOfFriends').isInt({ min: 1, max: 500 }).withMessage('numberOfFriends must be between 1 and 500'),
        body('partyDate').isISO8601().withMessage('partyDate must be a valid date'),
        body('startTime').optional({ nullable: true, checkFalsy: true }).isString().trim().isLength({ max: 20 }).withMessage('startTime is invalid'),
        body('mobileNumber').isString().trim().matches(/^\d{10}$/).withMessage('mobileNumber must be a valid 10-digit number'),
        body('optionalMobileNumber').optional({ nullable: true, checkFalsy: true }).isString().trim().matches(/^\d{10}$/).withMessage('optionalMobileNumber must be a valid 10-digit number'),
        body('foodPreference').optional({ nullable: true, checkFalsy: true }).isString().trim().isLength({ max: 100 }),
        body('drinkPreference').optional({ nullable: true, checkFalsy: true }).isString().trim().isLength({ max: 100 }),
        body('partySubject').optional({ nullable: true, checkFalsy: true }).isString().trim().isLength({ max: 200 }),
        body('partyRequirement').optional({ nullable: true, checkFalsy: true }).isString().trim().isLength({ max: 2000 }),
        body('partyDescription').optional({ nullable: true, checkFalsy: true }).isString().trim().isLength({ max: 5000 }),
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
