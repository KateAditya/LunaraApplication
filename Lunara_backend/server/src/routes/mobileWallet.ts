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

/**
 * POST /api/mobile/wallet/pay-with-wallet
 */
router.post(
    '/pay-with-wallet',
    ctrl.payWithWallet
);

router.post(
    '/recharge',
    ctrl.rechargeWallet
);

router.post(
    '/pay-vip',
    ctrl.payVipWithWallet
);

router.get(
    '/transactions',
    ctrl.getWalletTransactions
);

export default router;
