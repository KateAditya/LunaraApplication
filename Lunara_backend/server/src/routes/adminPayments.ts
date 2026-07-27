import express from 'express';
import { getPaymentSummary, getPayments } from '../controllers/adminPayments';
import { authenticate, authorize } from '../middleware/auth';
import { UserRole } from '../models/User';

const router = express.Router();

// Apply auth middleware to all routes in this router
router.use(authenticate, authorize(UserRole.ADMIN));

router.get('/summary', getPaymentSummary);
router.get('/', getPayments);

export default router;
