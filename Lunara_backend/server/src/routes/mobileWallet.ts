import { Router } from 'express';
import { query } from 'express-validator';
import { validate } from '../middleware/validate';
import * as ctrl from '../controllers/walletController';

const router = Router();

/**
 * GET /api/mobile/wallet
 * Returns incomplete events and transaction histories.
 */
router.get(
    '/',
    [
        query('userId').notEmpty().withMessage('userId is required'),
        validate,
    ],
    ctrl.getWalletData
);

export default router;
