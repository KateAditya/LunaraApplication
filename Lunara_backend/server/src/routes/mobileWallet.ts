import { Router } from 'express';
import { query } from 'express-validator';
import { validate } from '../middleware/validate';
import * as ctrl from '../controllers/walletController';

const router = Router();

/**
 * GET /api/mobile/wallet
 * Returns Smart Credit Wallet dashboard payload & recent transactions.
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
 * POST /api/mobile/wallet/recharge-order
 * Creates Razorpay Order for wallet recharge.
 */
router.post('/recharge-order', ctrl.createRechargeOrder);

/**
 * POST /api/mobile/wallet/verify-recharge
 * Verifies Razorpay signature & credits wallet.
 */
router.post('/verify-recharge', ctrl.verifyRechargePayment);

/**
 * POST /api/mobile/wallet/recharge
 */
router.post('/recharge', ctrl.rechargeWallet);

/**
 * POST /api/mobile/wallet/pay-vip
 */
router.post('/pay-vip', ctrl.payVipWithWallet);

/**
 * POST /api/mobile/wallet/pay-super-likes
 */
router.post('/pay-super-likes', ctrl.paySuperLikesWithWallet);

/**
 * POST /api/mobile/wallet/pay-boost
 */
router.post('/pay-boost', ctrl.payBoostWithWallet);

/**
 * POST /api/mobile/wallet/pay-with-wallet
 * Legacy Guard: Blocks booking/deposit payments via wallet.
 */
router.post('/pay-with-wallet', ctrl.payWithWallet);

/**
 * GET /api/mobile/wallet/transactions
 */
router.get('/transactions', ctrl.getWalletTransactions);

export default router;
