import { Router } from 'express';
import { getDeltaSync } from '../controllers/mobileSyncController';
import { authenticate } from '../middleware/auth';

const router = Router();

// GET /api/mobile/sync/delta?since=ISO_DATE
router.get('/delta', authenticate, getDeltaSync);

export default router;
