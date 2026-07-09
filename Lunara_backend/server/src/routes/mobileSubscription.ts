import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import * as mobileSubscriptionController from '../controllers/mobileSubscriptionController';

const router = Router();

router.use(authenticate);

router.get('/packages', mobileSubscriptionController.getAvailablePackages);
router.get('/current', mobileSubscriptionController.getCurrentSubscription);
router.post('/purchase', mobileSubscriptionController.purchaseSubscription);
router.post('/purchase-boost', mobileSubscriptionController.purchaseBoost);

export default router;
