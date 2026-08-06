import express from 'express';
import { authenticate, authorize } from '../middleware/auth';
import { UserRole } from '../models/User';
import * as adminWalletCtrl from '../controllers/adminWalletController';

const router = express.Router();

// Protect all admin wallet routes
router.use(authenticate, authorize(UserRole.ADMIN));

// Wallet Config Management
router.get('/config', adminWalletCtrl.getWalletConfig);
router.put('/config', adminWalletCtrl.updateWalletConfig);

// User Wallet Control
router.post('/users/:userId/freeze', adminWalletCtrl.freezeUserWallet);
router.post('/users/:userId/unfreeze', adminWalletCtrl.unfreezeUserWallet);
router.post('/users/:userId/manual-credit', adminWalletCtrl.adminManualCredit);
router.post('/users/:userId/manual-debit', adminWalletCtrl.adminManualDebit);

// Transaction Ledger
router.get('/transactions', adminWalletCtrl.getWalletLedger);

// Promotional Campaigns
router.get('/campaigns', adminWalletCtrl.listPromotionalCampaigns);
router.post('/campaigns', adminWalletCtrl.createPromotionalCampaign);

// Cashback Rules
router.get('/cashback-rules', adminWalletCtrl.listCashbackRules);
router.post('/cashback-rules', adminWalletCtrl.createCashbackRule);

export default router;
