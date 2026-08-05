import express from 'express';
import { getAdminNotificationSummary, getAdminNotificationActivity } from '../controllers/adminNotificationController';

const router = express.Router();

// GET /api/admin/notifications/summary - Fetch pending notification counts
router.get('/summary', getAdminNotificationSummary);

// GET /api/admin/notifications/activity - Fetch recent activity feed
router.get('/activity', getAdminNotificationActivity);

export default router;
