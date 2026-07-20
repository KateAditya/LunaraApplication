import { Router } from 'express';
import { authenticate, authorize } from '../middleware/auth';
import { UserRole } from '../models/User';
import * as ctrl from '../controllers/adminSubscriptionController';

const router = Router();

// Apply admin auth middleware to all routes
router.use(authenticate);
router.use(authorize(UserRole.ADMIN));

// ── Analytics ──────────────────────────────────────────────────────────────────
router.get('/analytics/overview', ctrl.getAnalyticsOverview);

// ── Feature Catalog ────────────────────────────────────────────────────────────
router.get('/features', ctrl.getAllFeatures);
router.post('/features', ctrl.createFeature);
router.put('/features/:id', ctrl.updateFeature);
router.delete('/features/:id', ctrl.deleteFeature);

// ── Transactions ───────────────────────────────────────────────────────────────
router.get('/transactions', ctrl.getAllTransactions);

// ── Subscribed Users ───────────────────────────────────────────────────────────
router.get('/users', ctrl.getSubscribedUsers);

// ── User Subscription Management (Admin Actions) ──────────────────────────────
router.patch('/users/:userId/force-expire', ctrl.forceExpireUserSubscription);
router.patch('/users/:userId/extend', ctrl.extendUserSubscription);
router.post('/users/:userId/grant', ctrl.grantUserSubscription);        // Grant free VIP
router.patch('/users/:userId/credits', ctrl.adjustUserCredits);         // Adjust superlikes/boosts
router.delete('/users/:userId/usage', ctrl.resetUserUsage);             // Reset daily usage counters
router.get('/users/:userId/status', ctrl.getUserFeatureStatus);         // Live feature snapshot

// ── Tier-level Bulk Feature Configuration ─────────────────────────────────────
router.put('/tiers/:tier/features', ctrl.bulkConfigureTierFeatures);    // Bulk-config all pkgs of a tier

// ── Seed Defaults (one-time setup) ────────────────────────────────────────────
router.post('/seed', ctrl.seedDefaultPackages);

// ── Plans CRUD ─────────────────────────────────────────────────────────────────
router.get('/', ctrl.getAllPackages);
router.post('/', ctrl.createPackage);
router.put('/:id', ctrl.updatePackage);
router.delete('/:id', ctrl.deletePackage);

// ── Plan Actions ───────────────────────────────────────────────────────────────
router.post('/:id/duplicate', ctrl.duplicatePackage);
router.patch('/:id/archive', ctrl.archivePackage);
router.patch('/:id/toggle-status', ctrl.togglePackageStatus);

// ── Plan Features (feature matrix per package) ────────────────────────────────
router.get('/:id/features', ctrl.getPlanFeatures);
router.put('/:id/features', ctrl.updatePlanFeatures);

export default router;
