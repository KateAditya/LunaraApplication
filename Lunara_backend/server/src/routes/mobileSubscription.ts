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

// ── Unified Status (tier + limits + usage + boosts + superlikes in one call) ──
router.get('/status', ctrl.getSubscriptionStatus);

// ── Purchase Flow ──────────────────────────────────────────────────────────────
router.post('/create-order', ctrl.createSubscriptionOrder);
router.post('/purchase', ctrl.purchaseSubscription);
router.post('/renew', ctrl.renewSubscription);
router.post('/cancel', ctrl.cancelSubscription);

// ── Boost Purchase ─────────────────────────────────────────────────────────────
router.post('/create-boost-order', ctrl.createBoostOrder);
router.post('/purchase-boost', ctrl.purchaseBoost);
router.post('/use-boost', ctrl.useBoost);

// ── History & Invoices ─────────────────────────────────────────────────────────
router.get('/history', ctrl.getSubscriptionHistory);

// ── Feature Access Check ───────────────────────────────────────────────────────
router.get('/check/:featureKey', ctrl.checkFeatureAccess);

export default router;
