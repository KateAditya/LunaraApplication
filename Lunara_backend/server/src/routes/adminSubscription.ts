import { Router } from 'express';
import { authenticate, authorize } from '../middleware/auth';
import { UserRole } from '../models/User';
import * as adminSubscriptionController from '../controllers/adminSubscriptionController';

const router = Router();

// Apply admin auth middleware
router.use(authenticate);
router.use(authorize(UserRole.ADMIN));

router.get('/', adminSubscriptionController.getAllPackages);
router.post('/', adminSubscriptionController.createPackage);
router.put('/:id', adminSubscriptionController.updatePackage);
router.delete('/:id', adminSubscriptionController.deletePackage);

// Special route to seed defaults
router.post('/seed', adminSubscriptionController.seedDefaultPackages);

export default router;
