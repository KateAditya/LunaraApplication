import { Router } from 'express';
import { getAdminGroupParties } from '../controllers/adminGroupPartyController';
import { authenticate, authorize } from '../middleware/auth';
import { UserRole } from '../models/User';

const router = Router();

router.get('/', authenticate, authorize(UserRole.ADMIN, UserRole.VENUE_OWNER), getAdminGroupParties);

export default router;
