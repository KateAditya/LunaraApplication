import express, { Application } from 'express';
import dotenv from 'dotenv';
import cluster from 'cluster';
import { cpus } from 'os';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import morgan from 'morgan';
import cookieParser from 'cookie-parser';
import { createServer } from 'http';
import { Server as SocketIOServer } from 'socket.io';
import rateLimit from 'express-rate-limit';
import path from 'path';
import { logger } from './config/logger';
import { connectDatabase } from './config/database';
import { errorHandler } from './middleware/errorHandler';
import User from './models/User';
import Message, { MessageStatus } from './models/Message';
import Conversation from './models/Conversation';
import SocialConnection, { ConnectionStatus } from './models/SocialConnection';
import { Op } from 'sequelize';

// Load environment variables
dotenv.config();

const app: Application = express();

// Trust Azure / NGINX reverse proxy — MUST be set before any rate limiter
// Setting to 1 means trust the first proxy hop only.
app.set('trust proxy', 1);

const httpServer = createServer(app);
const io = new SocketIOServer(httpServer, {
    cors: {
        origin: process.env.SOCKET_IO_CORS_ORIGIN?.split(',') || ['http://localhost:3000'],
        credentials: true,
    },
});

// 1. CORS — MUST be first before any other middleware or helmet
app.use(cors({
    origin: true,
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'Accept', 'X-Requested-With', 'x-user-id', 'sentry-trace', 'baggage'],
    exposedHeaders: ['Content-Range', 'X-Content-Range'],
    maxAge: 86400, // 24-hour preflight cache in browsers
}));
app.options('*', cors({ origin: true, credentials: true, maxAge: 86400 }));

// 2. Security headers (Helmet)
app.use(helmet({
    crossOriginResourcePolicy: { policy: "cross-origin" },
    contentSecurityPolicy: {
        directives: {
            ...helmet.contentSecurityPolicy.getDefaultDirectives(),
            "img-src": ["'self'", "data:", "blob:", "https:", "*.blob.core.windows.net", "placehold.co", "*.placehold.co", "images.unsplash.com"],
            "media-src": ["'self'", "data:", "blob:", "https:"],
            "connect-src": ["'self'", "*.azurewebsites.net", "*.windows.net", "ws:", "wss:"],
        },
    },
}));

// Explicit Permissions-Policy to silence the 'unload' violation from Chrome extensions
app.use((_req, res, next) => {
    res.setHeader('Permissions-Policy', 'unload=()');
    next();
});

app.use(compression({ threshold: 256, level: 6 })); // High-speed gzip compression

// Performance: Cache headers for read-heavy public endpoints (stale-while-revalidate)
// Strictly non-cached for user-specific, payment, or transactional data
app.use((req, res, next) => {
    if (req.method === 'GET') {
        const p = req.path;
        if (
            p.startsWith('/api/venues') ||
            p.startsWith('/api/ads/active') ||
            p.startsWith('/api/mobile/cities') ||
            p.startsWith('/api/support/') ||
            p.startsWith('/api/packages') ||
            p.startsWith('/api/mobile/subscription-packages')
        ) {
            res.setHeader('Cache-Control', 'public, max-age=15, stale-while-revalidate=60');
        } else if (
            p.includes('/party-plans') ||
            p.includes('/wallet') ||
            p.includes('/bookings') ||
            p.includes('/payments') ||
            p.includes('/user/')
        ) {
            res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
            res.setHeader('Pragma', 'no-cache');
        }
    }
    next();
});

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(cookieParser());
app.use(morgan('combined', { stream: { write: (message) => logger.info(message.trim()) } }));

// Diagnostic timing middleware for performance auditing (Phase 1 diagnostic monitoring)
app.use((req, res, next) => {
    const startHr = process.hrtime();
    const method = req.method;
    const url = req.originalUrl || req.url;

    res.on('finish', () => {
        const [seconds, nanoseconds] = process.hrtime(startHr);
        const durationMs = (seconds * 1000 + nanoseconds / 1e6).toFixed(2);
        const numMs = parseFloat(durationMs);

        if (numMs > 500) {
            logger.warn(`[SLOW ROUTE AUDIT] ${method} ${url} took ${durationMs}ms with status ${res.statusCode}`);
        }
    });
    next();
});
// Rate limiting — apply globally. The keyGenerator strips any port from IP:PORT
// strings produced by Azure's load balancer to avoid ERR_ERL_INVALID_IP_ADDRESS.
const safeIpKeyGenerator = (req: any): string => {
    const raw = req.ip || req.socket?.remoteAddress || 'unknown';
    // Azure LB may pass '1.2.3.4:56789' — strip the port
    return raw.includes(':') && !raw.startsWith('::') ? raw.split(':')[0] : raw;
};

if (process.env.NODE_ENV !== 'development') {
    const limiter = rateLimit({
        windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000'),
        max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '10000'),
        message: { success: false, message: 'Too many requests from this IP, please try again later.' },
        keyGenerator: safeIpKeyGenerator,
        skip: (req) => req.path === '/health',
    });
    app.use('/api/', limiter);
}

app.get('/health', (_req, res) => {
    res.status(200).json({
        status: 'OK',
        timestamp: new Date().toISOString(),
    });
});

// Serve static files from uploads directory (or redirect to Azure Blob Storage)
let accountName = process.env.AZURE_STORAGE_ACCOUNT_NAME;
if (!accountName && process.env.AZURE_STORAGE_CONNECTION_STRING) {
    const match = process.env.AZURE_STORAGE_CONNECTION_STRING.match(/AccountName=([^;]+)/);
    if (match) {
        accountName = match[1];
    }
}

if (accountName) {
    const containerName = process.env.AZURE_STORAGE_CONTAINER_NAME || 'uploads';
    const blobBaseUrl = `https://${accountName}.blob.core.windows.net/${containerName}`;
    
    app.use('/uploads', (req, res) => {
        // req.path starts with a slash, e.g., /venues/123/img.jpg
        res.redirect(301, `${blobBaseUrl}${req.path}`);
    });
} else {
    app.use('/uploads', express.static(path.join(process.cwd(), 'uploads')));
    
    // Fallback for missing images in /uploads to prevent 404 errors in the mobile app during dev
    app.use('/uploads', (_req, res) => {
        res.redirect('https://placehold.co/600x400/2a1b38/e0a0ff.png?text=Image+Not+Found');
    });
}

// API Routes
import authRoutes from './routes/auth';
import venueRoutes from './routes/venues';
import userRoutes from './routes/users';
import dashboardRoutes from './routes/dashboard';
import adsRoutes from './routes/ads';
import mobileAuthRoutes from './routes/mobileAuth';
import mobileUserRoutes from './routes/mobileUser';
import mobileBookingRoutes from './routes/mobileBooking';
import mobilePlanRoutes from './routes/mobilePlan';
import mobileChatRoutes from './routes/mobileChat';
import supportLegalRoutes from './routes/supportLegal';
import mobileSupportLegalRoutes from './routes/mobileSupportLegal';
import mobilePartyPlanRoutes from './routes/mobilePartyPlan';
import mobileGroupPartyRoutes from './routes/mobileGroupParty';
import mobileNightPartnerRoutes from './routes/mobileNightPartner';
import adminGroupPartyRoutes from './routes/adminGroupParty';
import profileRoutes from './routes/profile';
import mobileStrangersMeetRoutes from './routes/mobileStrangersMeet';
import adminStrangersMeetRoutes from './routes/adminStrangersMeet';
import mobileCityRoutes from './routes/mobileCity';
import areaRoutes from './routes/areaRoutes';
import adminBookingsRoutes from './routes/adminBookings';
import adminSubscriptionRoutes from './routes/adminSubscription';
import mobileSubscriptionRoutes from './routes/mobileSubscription';
import mobileWalletRoutes from './routes/mobileWallet';
import mobileTicketRoutes from './routes/mobileTicket';
import adminPaymentsRoutes from './routes/adminPayments';
import adminNotificationRoutes from './routes/adminNotificationRoutes';
import adminEventBookingRoutes from './routes/adminEventBooking';
import { ExpiredTicketCleanupWorker } from './services/ExpiredTicketCleanupWorker';
import { startPartyPlanCron, startNotificationJobCron, startExpiringPlanAlertCron } from './cron/partyPlanCron';
import { startSubscriptionCron } from './cron/subscriptionCron';
import { startBoostCron } from './cron/boostCron';
import { startStrangersMeetCron } from './cron/strangersMeetCron';
import { getAdminChatSettings, updateAdminChatSettings } from './controllers/chatSubscriptionController';
import { getAdminTimeLockSettings, updateAdminTimeLockSettings } from './controllers/mobilePlanController';
import { getAdminBookingPolicySettings, updateAdminBookingPolicySettings } from './controllers/adminBookingController';
import dbRestoreRoutes from './routes/dbRestore';
import adminSafetyChecksRoutes from './routes/adminSafetyChecks';

app.get('/api', (_req, res) => {
    res.json({
        message: 'Lunara Backend API',
        version: '1.0.0',
        status: 'Running',
        endpoints: {
            auth: '/api/auth',
            mobileAuth: '/api/mobile/auth',
            mobileBookings: '/api/mobile/bookings',
            mobilePlans: '/api/mobile/plans',
            mobileChat: '/api/mobile/chat',
            mobileGroupParty: '/api/mobile/group-parties',
            health: '/health',
            dashboard: '/api/dashboard',
        },
    });
});

// Mount routes
app.use('/api/auth', authRoutes);
app.use('/api/venues', venueRoutes);
app.use('/api/users', userRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/ads', adsRoutes);
app.use('/api/mobile/auth', mobileAuthRoutes);       // Mobile App — auth
app.use('/api/mobile/user', mobileUserRoutes);       // Mobile App — user profile
app.use('/api/mobile/bookings', mobileBookingRoutes); // Mobile App — bookings
app.use('/api/mobile/plans', mobilePlanRoutes);       // Mobile App — post a plan
app.use('/api/mobile/chat', mobileChatRoutes);        // Mobile App — chat
app.use('/api/support', supportLegalRoutes);              // Support & Legal (Admin)
app.use('/api/mobile/support', mobileSupportLegalRoutes);  // Support & Legal (Mobile App)
app.use('/api/mobile/party-plans', mobilePartyPlanRoutes); // Party Plans (Mobile App)
app.use('/api/mobile/group-parties', mobileGroupPartyRoutes); // Group Parties (Mobile App)
app.use('/api/mobile/nights', mobileNightPartnerRoutes); // Upcoming Nights Partner Discovery & Matching (Mobile App)
app.use('/api/admin/group-parties', adminGroupPartyRoutes); // Group Parties (Admin)
app.use('/api/profile', profileRoutes);                    // Edit Profile & Password APIs
app.use('/api/mobile/strangers-meet', mobileStrangersMeetRoutes); // Strangers Meet (Mobile)
app.use('/api/admin/strangers-meet', adminStrangersMeetRoutes);
app.use('/api/admin/bookings', adminBookingsRoutes);   // Strangers Meet (Admin)
app.use('/api/admin/event-bookings', adminEventBookingRoutes); // Event Bookings (Admin)
app.use('/admin/event-bookings', adminEventBookingRoutes);     // Event Bookings Alias
app.use('/api/mobile/cities', mobileCityRoutes);                   // Cities (Mobile App)
app.use('/api/areas', areaRoutes);                                 // Areas API (Admin & App)
app.use('/api/admin/subscriptions', adminSubscriptionRoutes); // Subscriptions (Admin)
app.use('/api/admin/safety-checks', adminSafetyChecksRoutes); // Safety Checks (Admin)
import mobilePaymentRoutes from './routes/mobilePayment';
app.use('/api/mobile/payments', mobilePaymentRoutes);         // Central Payments & Webhooks (Mobile)
app.use('/api/mobile/subscriptions', mobileSubscriptionRoutes); // Subscriptions (Mobile)
app.use('/api/mobile/wallet', mobileWalletRoutes);             // Wallet (Mobile)
app.use('/api/mobile/tickets', mobileTicketRoutes);           // Digital Tickets (Mobile)
import mobileSyncRoutes from './routes/mobileSyncRoutes';
app.use('/api/mobile/sync', mobileSyncRoutes);                 // Delta Synchronization (Mobile)
import adminWalletRoutes from './routes/adminWalletRoutes';
app.use('/api/admin/wallet', adminWalletRoutes);                  // Smart Credit Wallet (Admin)
app.use('/api/admin/payments', adminPaymentsRoutes);          // Payments (Admin)
app.use('/api/admin/notifications', adminNotificationRoutes);   // Admin Notifications (Admin)

import adminMonitoringRoutes from './routes/adminMonitoringRoutes';
import { idempotencyGuard } from './middleware/idempotencyMiddleware';
import { adminLogin } from './controllers/authController';

// Admin Login Route Aliases
app.post('/api/auth/admin-login', adminLogin);
app.post('/api/admin/login', adminLogin);
app.post('/api/admin-login', adminLogin);
app.post('/admin-login', adminLogin);
app.post('/admin/login', adminLogin);

app.use(idempotencyGuard);
app.use('/api/admin/monitoring', adminMonitoringRoutes);
app.use('/api/admin/reports', adminMonitoringRoutes);

import { getReliabilitySummary, getReliabilityLeaderboard } from './controllers/reliabilityController';
import { getRewardBalance, claimDailyReward, redeemRewardPoints } from './controllers/rewardPointsController';

app.get('/api/mobile/user/reliability-summary', getReliabilitySummary);
app.get('/api/mobile/rewards/balance', getRewardBalance);
app.post('/api/mobile/rewards/claim-daily', claimDailyReward);
app.post('/api/mobile/rewards/redeem', redeemRewardPoints);
app.get('/api/admin/reliability/leaderboard', getReliabilityLeaderboard);

import {
    getAdminCancellationRequests,
    checkExpiredOrAutoApprovedRequests,
    getAdminCancelledPlans,
    getAdminCancellationAnalytics,
    getAdminCancellationDetail,
    adminMarkForInvestigation,
    adminRestoreBooking,
    exportCancellations,
} from './controllers/cancellationController';

// Admin — basic cancellation requests (legacy)
app.get('/api/admin/cancellation-requests', getAdminCancellationRequests);

// Admin — Party Plan Cancellation Management Module
app.get('/api/admin/party-plans/cancellations/analytics', getAdminCancellationAnalytics);
app.get('/api/admin/party-plans/cancellations/export', exportCancellations);
app.get('/api/admin/party-plans/cancellations', getAdminCancelledPlans);
app.get('/api/admin/party-plans/cancellations/:id', getAdminCancellationDetail);
app.post('/api/admin/party-plans/cancellations/:id/investigate', adminMarkForInvestigation);
app.post('/api/admin/party-plans/cancellations/:id/restore', adminRestoreBooking);

// Run background auto-approval & expiration check for cancellation requests every 15 minutes
let isCancellationAutoCheckRunning = false;
if (process.env.NODE_ENV !== 'test') {
    setInterval(async () => {
        if (isCancellationAutoCheckRunning) {
            logger.warn('[Cron] Cancellation auto-check is already running. Skipping overlapping execution.');
            return;
        }
        isCancellationAutoCheckRunning = true;
        try {
            await checkExpiredOrAutoApprovedRequests();
        } catch (err) {
            logger.error('Cancellation auto-check error:', err);
        } finally {
            isCancellationAutoCheckRunning = false;
        }
    }, 15 * 60 * 1000);
}

// Admin — chat subscription settings
app.get('/api/admin/settings/chat', getAdminChatSettings);
app.put('/api/admin/settings/chat', updateAdminChatSettings);

// Admin — plan time lock settings
app.get('/api/admin/settings/time-lock', getAdminTimeLockSettings);
app.put('/api/admin/settings/time-lock', updateAdminTimeLockSettings);

// Admin — universal booking & cancellation policy settings (Solo Booking & Small Group Party <=20)
app.get('/api/admin/settings/booking-policy', getAdminBookingPolicySettings);
app.put('/api/admin/settings/booking-policy', updateAdminBookingPolicySettings);

// TEMP: DB restore endpoint — REMOVE AFTER USE
app.use('/api/db-restore', dbRestoreRoutes);

// TODO: Import and use other route modules
// app.use('/api/bookings', bookingRoutes);
// app.use('/api/payments', paymentRoutes);

// Socket.IO connection handling
io.on('connection', (socket) => {
    logger.info(`Client connected: ${socket.id}`);

    socket.on('join_admin_room', () => {
        socket.join('admin');
        socket.join('admin_notifications');
        logger.info(`Socket ${socket.id} joined admin and admin_notifications room`);
    });

    socket.on('join_user_room', async (userId: string) => {
        socket.join(`user_${userId}`);
        socket.join('live_feed');
        (socket as any).userId = userId;
        logger.info(`Socket ${socket.id} joined user room user_${userId} and live_feed`);

        try {
            await User.update({ isOnline: true, lastActiveAt: new Date() }, { where: { id: userId } });
            io.emit('user_status_changed', { userId, isOnline: true, lastActiveAt: new Date() });

            const convs = await Conversation.findAll({
                where: {
                    [Op.or]: [{ participantOne: userId }, { participantTwo: userId }]
                }
            });
            const convIds = convs.map(c => c.id);
            if (convIds.length > 0) {
                await Message.update(
                    { status: MessageStatus.DELIVERED },
                    {
                        where: {
                            conversationId: { [Op.in]: convIds },
                            senderId: { [Op.ne]: userId },
                            status: MessageStatus.SENT
                        }
                    }
                );
                for (const conv of convs) {
                    const otherUser = (conv.participantOne && userId && conv.participantOne.toLowerCase() === userId.toLowerCase()) ? conv.participantTwo : conv.participantOne;
                    io.to(`user_${otherUser}`).emit('messages_delivered', { conversationId: conv.id });
                }
            }
        } catch (err) {
            logger.error('Failed to update online status or delivery:', err);
        }
    });

    socket.on('join_city_room', (city: string) => {
        if (city && typeof city === 'string') {
            const cleanCity = city.trim().toLowerCase().replace(/\s+/g, '_');
            socket.join(`city_${cleanCity}`);
            logger.info(`Socket ${socket.id} joined city room: city_${cleanCity}`);
        }
    });

    socket.on('leave_city_room', (city: string) => {
        if (city && typeof city === 'string') {
            const cleanCity = city.trim().toLowerCase().replace(/\s+/g, '_');
            socket.leave(`city_${cleanCity}`);
            logger.info(`Socket ${socket.id} left city room: city_${cleanCity}`);
        }
    });

    socket.on('typing_started', async (data: { conversationId: string; recipientId: string; senderId?: string }) => {
        if (data?.recipientId) {
            const senderId = data.senderId || (socket as any).userId;
            if (senderId) {
                try {
                    const isBlocked = await SocialConnection.findOne({
                        where: {
                            requesterId: data.recipientId,
                            receiverId: senderId,
                            status: ConnectionStatus.BLOCKED,
                        },
                    });
                    if (isBlocked) return;
                } catch (_) {}
            }
            io.to(`user_${data.recipientId}`).emit('typing_started', {
                conversationId: data.conversationId,
                senderId,
            });
        }
    });

    socket.on('typing_stopped', async (data: { conversationId: string; recipientId: string; senderId?: string }) => {
        if (data?.recipientId) {
            const senderId = data.senderId || (socket as any).userId;
            if (senderId) {
                try {
                    const isBlocked = await SocialConnection.findOne({
                        where: {
                            requesterId: data.recipientId,
                            receiverId: senderId,
                            status: ConnectionStatus.BLOCKED,
                        },
                    });
                    if (isBlocked) return;
                } catch (_) {}
            }
            io.to(`user_${data.recipientId}`).emit('typing_stopped', {
                conversationId: data.conversationId,
                senderId,
            });
        }
    });

    socket.on('disconnect', async () => {
        logger.info(`Client disconnected: ${socket.id}`);
        const userId = (socket as any).userId;
        if (userId) {
            try {
                const now = new Date();
                await User.update({ isOnline: false, lastActiveAt: now }, { where: { id: userId } });
                io.emit('user_status_changed', { userId, isOnline: false, lastActiveAt: now });
            } catch (err) {
                logger.error('Failed to update offline status:', err);
            }
        }
    });
});

const PORT = process.env.PORT || 5000;
const HOST = process.env.HOST || 'localhost';

// Serve the Admin Panel (React frontend)
const adminPanelPath = path.join(__dirname, '../../admin-panel/dist');
app.use(express.static(adminPanelPath));

// Catch-all route to serve the React index.html for any non-API routes (React Router support)
app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api') || req.path.startsWith('/uploads')) {
        return next();
    }
    res.sendFile(path.join(adminPanelPath, 'index.html'));
});

// 404 handler
app.use((req, res) => {
    logger.warn(`404 Not Found: ${req.method} ${req.originalUrl}`);
    res.status(404).json({
        success: false,
        message: 'Route not found',
    });
});

// Error handling middleware (must be last)
app.use(errorHandler);

// Sync database and start server after database connection
// Sync database and start server after database connection
const startServer = async () => {
    try {
        await connectDatabase();

        httpServer.listen(PORT, () => {
            logger.info(`Worker ${process.pid} running server on http://${HOST}:${PORT}`);
            logger.info(`Environment: ${process.env.NODE_ENV}`);
        });

        // Start Background Cron Jobs
        // Only run on the master process (if native cluster is disabled) AND only on instance 0 (if PM2 cluster)
        const isMasterProcess = cluster.isPrimary || (cluster as any).isMaster;
        const isFirstPm2Instance = !process.env.NODE_APP_INSTANCE || process.env.NODE_APP_INSTANCE === '0';
        const shouldRunCron = process.env.RUN_CRON !== 'false';
        if (isMasterProcess && isFirstPm2Instance && shouldRunCron) {
            startPartyPlanCron();
            startNotificationJobCron();
            startExpiringPlanAlertCron();
            startSubscriptionCron();
            startBoostCron();
            startStrangersMeetCron();
            ExpiredTicketCleanupWorker.startWorker();
            logger.info('Background Cron Jobs & ExpiredTicketCleanupWorker started on process/instance.');
        } else {
            logger.info(`Background Cron Jobs bypassed on worker/instance (Process ID: ${process.pid}, RUN_CRON=${process.env.RUN_CRON}).`);
        }
    } catch (error) {
        logger.error('Failed to start server:', error);
        process.exit(1);
    }
};

if (process.env.NODE_ENV !== 'test') {
    const enableCluster = process.env.ENABLE_CLUSTER === 'true' && (cluster.isPrimary || (cluster as any).isMaster);
    
    if (enableCluster) {
        const numCPUs = cpus().length;
        logger.info(`Primary process ${process.pid} is running. Forking ${numCPUs} CPU cores for load balancing...`);
        
        for (let i = 0; i < numCPUs; i++) {
            cluster.fork();
        }
        
        cluster.on('exit', (worker) => {
            logger.warn(`Worker ${worker.process.pid} died. Forking a new worker...`);
            cluster.fork();
        });
        
        // Connect to database and start cron on primary process
        const isFirstPm2Instance = !process.env.NODE_APP_INSTANCE || process.env.NODE_APP_INSTANCE === '0';
        const shouldRunCron = process.env.RUN_CRON !== 'false';
        if (isFirstPm2Instance && shouldRunCron) {
            connectDatabase().then(() => {
                startPartyPlanCron();
                startNotificationJobCron();
                startExpiringPlanAlertCron();
                startSubscriptionCron();
                startBoostCron();
                startStrangersMeetCron();
                ExpiredTicketCleanupWorker.startWorker();
                logger.info('Primary process database connected & initiated background Cron Jobs.');
            }).catch((err) => {
                logger.error('Primary process failed to connect to database for Cron Jobs:', err);
            });
        }
    } else {
        startServer();
    }
}

// Graceful shutdown
process.on('SIGTERM', () => {
    logger.info('SIGTERM signal received: closing HTTP server');
    httpServer.close(() => {
        logger.info('HTTP server closed');
        process.exit(0);
    });
});

export { io };
export default app;
