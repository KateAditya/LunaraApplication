import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import * as ctrl from '../controllers/mobileSubscriptionController';

const router = Router();

// All routes require mobile user auth
router.use(authenticate);

// ── Plan Listing ───────────────────────────────────────────────────────────────
router.get('/packages', ctrl.getAvailablePackages);

// ── Current Subscription ───────────────────────────────────────────────────────
router.get('/current', ctrl.getCurrentSubscription);

// ── Purchase Flow ──────────────────────────────────────────────────────────────
router.post('/purchase', ctrl.purchaseSubscription);
router.post('/renew', ctrl.renewSubscription);
router.post('/cancel', ctrl.cancelSubscription);

// ── Boost Purchase ─────────────────────────────────────────────────────────────
router.post('/purchase-boost', ctrl.purchaseBoost);

// ── History & Invoices ─────────────────────────────────────────────────────────
router.get('/history', ctrl.getSubscriptionHistory);

// ── Feature Access Check ───────────────────────────────────────────────────────
router.get('/check/:featureKey', ctrl.checkFeatureAccess);

export default router;
