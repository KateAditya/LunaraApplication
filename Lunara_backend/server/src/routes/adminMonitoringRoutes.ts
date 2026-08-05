import { Router } from 'express';
import {
    getAdminMonitoringDashboard,
    getBookingMonitoringTimeline,
    getWalletMonitoring,
    getNotificationMonitoring,
    getReadOnlyChatMonitoring,
    getSystemHealth,
} from '../controllers/adminMonitoringController';
import {
    getAnalyticsOverview,
    exportReport,
} from '../controllers/analyticsController';

const router = Router();

// Monitoring Endpoints
router.get('/dashboard', getAdminMonitoringDashboard);
router.get('/bookings/:id/timeline', getBookingMonitoringTimeline);
router.get('/wallets', getWalletMonitoring);
router.get('/notifications', getNotificationMonitoring);
router.get('/chats', getReadOnlyChatMonitoring);

// Health Endpoint
router.get('/health', getSystemHealth);

// Analytics & Reports
router.get('/analytics/overview', getAnalyticsOverview);
router.get('/reports/export', exportReport);

export default router;
