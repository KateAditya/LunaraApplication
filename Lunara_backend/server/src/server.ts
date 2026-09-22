import express, { Application } from 'express';
import dotenv from 'dotenv';
import cluster from 'cluster';
import { fork } from 'child_process';
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
import fs from 'fs';
import { logger } from './config/logger';
import { connectDatabase } from './config/database';
import { redisService } from './config/redis';
import { attachRedisAdapter } from './config/socketAdapter';
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
        origin: true,
        credentials: true,
    },
    transports: ['websocket', 'polling'],
});

/// Resolves once the cross-process socket adapter has been attached (or has been
/// determined to be unavailable). Both entry points — the HTTP server below and
/// `cronWorker.ts` — await this before accepting traffic or running jobs, so no
/// emit is issued while the adapter is still connecting.
export const socketAdapterReady: Promise<boolean> = attachRedisAdapter(io);

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
        skip: (req) => req.path === '/health' || req.path.startsWith('/socket.io') || req.baseUrl?.startsWith('/socket.io'),
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

    // Ensure Azure Blob Storage CORS rules allow web browser access
    if (process.env.AZURE_STORAGE_CONNECTION_STRING) {
        try {
            const { BlobServiceClient } = require('@azure/storage-blob');
            const blobServiceClient = BlobServiceClient.fromConnectionString(process.env.AZURE_STORAGE_CONNECTION_STRING);
            blobServiceClient.setProperties({
                cors: [
                    {
                        allowedOrigins: '*',
                        allowedMethods: 'GET,HEAD,OPTIONS,PUT,POST,DELETE,PATCH',
                        allowedHeaders: '*',
                        exposedHeaders: '*',
                        maxAgeInSeconds: 86400,
                    },
                ],
            }).then(() => {
                logger.info('Azure Blob Storage CORS rules ensured.');
            }).catch((err: any) => {
                logger.warn('Azure Blob Storage CORS check warning:', err?.message || err);
            });
        } catch (err: any) {
            logger.warn('Azure Blob Storage init warning:', err?.message || err);
        }
    }
    
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

// Background auto-approval & expiration check for cancellation requests, every 15 minutes.
//
// This used to start at module scope, which was fine while a single process did
// everything. `cronWorker.ts` imports this module to reach `io`, so at module
// scope the timer would now run in BOTH the web process and the cron worker and
// double-execute the check. It is started explicitly by whichever process owns
// the scheduled work instead — see `startBackgroundJobs()`.
let isCancellationAutoCheckRunning = false;
let cancellationAutoCheckTimer: NodeJS.Timeout | null = null;

export const startCancellationAutoCheck = (): void => {
    if (process.env.NODE_ENV === 'test' || cancellationAutoCheckTimer) return;
    cancellationAutoCheckTimer = setInterval(async () => {
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
};

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
            const now = new Date();
            await User.update({ isOnline: true, lastActiveAt: now }, { where: { id: userId } });

            // Targeted emission: notify admin room and user's own socket
            io.to('admin').emit('user_status_changed', { userId, isOnline: true, lastActiveAt: now });
            socket.emit('user_status_changed', { userId, isOnline: true, lastActiveAt: now });

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
                    if (otherUser) {
                        // Targeted emission to conversation partner only
                        io.to(`user_${otherUser}`).emit('user_status_changed', { userId, isOnline: true, lastActiveAt: now });
                        io.to(`user_${otherUser}`).emit('messages_delivered', { conversationId: conv.id });
                    }
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
                
                // Targeted emission to admin and active conversation partners only
                io.to('admin').emit('user_status_changed', { userId, isOnline: false, lastActiveAt: now });

                const convs = await Conversation.findAll({
                    where: {
                        [Op.or]: [{ participantOne: userId }, { participantTwo: userId }]
                    },
                    attributes: ['participantOne', 'participantTwo']
                });
                for (const conv of convs) {
                    const otherUser = (conv.participantOne && conv.participantOne.toLowerCase() === userId.toLowerCase()) ? conv.participantTwo : conv.participantOne;
                    if (otherUser) {
                        io.to(`user_${otherUser}`).emit('user_status_changed', { userId, isOnline: false, lastActiveAt: now });
                    }
                }
            } catch (err) {
                logger.error('Failed to update offline status:', err);
            }
        }
    });
});

const PORT = process.env.PORT || 5000;
const HOST = process.env.HOST || 'localhost';

// Serve the Admin Panel (React frontend)
const possibleAdminPaths = [
    path.join(__dirname, '../../admin-panel/dist'),
    path.join(process.cwd(), 'admin-dist'),
    path.join(__dirname, '../admin-dist'),
    path.join(process.cwd(), 'dist/admin-dist'),
];

let resolvedAdminPath: string | null = null;
for (const p of possibleAdminPaths) {
    if (fs.existsSync(path.join(p, 'index.html'))) {
        resolvedAdminPath = p;
        break;
    }
}

if (resolvedAdminPath) {
    app.use(express.static(resolvedAdminPath));
}

// Catch-all route to serve the React index.html for any non-API routes (React Router support)
app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api') || req.path.startsWith('/uploads') || req.path.startsWith('/health')) {
        return next();
    }
    if (resolvedAdminPath && fs.existsSync(path.join(resolvedAdminPath, 'index.html'))) {
        return res.sendFile(path.join(resolvedAdminPath, 'index.html'));
    }
    res.status(200).send(`
        <!DOCTYPE html>
        <html>
        <head><title>Lunara Platform</title><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="background:#0b0d14;color:#f3f4f6;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;">
            <div style="text-align:center;padding:2rem;background:#151824;border-radius:12px;border:1px solid #282f44;max-width:480px;">
                <h2 style="color:#a855f7;margin-top:0;">✨ Lunara Backend & Admin API</h2>
                <p style="color:#9ca3af;">Production API server is active and healthy.</p>
                <div style="margin-top:1.5rem;">
                    <a href="/api" style="color:#38bdf8;text-decoration:none;margin:0 10px;">API Status</a>
                    <a href="/health" style="color:#38bdf8;text-decoration:none;margin:0 10px;">Health Check</a>
                </div>
            </div>
        </body>
        </html>
    `);
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
/**
 * Starts every scheduled job. Called only by the process that owns background
 * work — `cronWorker.ts` — never by the HTTP process.
 */
export const startBackgroundJobs = (): void => {
    startPartyPlanCron();
    startNotificationJobCron();
    startExpiringPlanAlertCron();
    startSubscriptionCron();
    startBoostCron();
    startStrangersMeetCron();
    ExpiredTicketCleanupWorker.startWorker();
    startCancellationAutoCheck();
    logger.info(`[CronWorker] Background jobs started in dedicated process ${process.pid}.`);
};

/**
 * Forks the cron worker, unless this deployment is configured not to run jobs.
 *
 * `RUN_CRON=false` keeps the meaning it always had — "this deployment does not
 * run scheduled work" — only the implementation changed from inline to forked.
 * The `NODE_APP_INSTANCE` guard is preserved so a PM2 cluster still starts jobs
 * on instance 0 alone.
 */
let cronWorkerRestarts = 0;
const forkCronWorker = (): void => {
    const isFirstPm2Instance = !process.env.NODE_APP_INSTANCE || process.env.NODE_APP_INSTANCE === '0';
    const shouldRunCron = process.env.RUN_CRON !== 'false';

    if (!shouldRunCron || !isFirstPm2Instance) {
        logger.info(
            `[CronWorker] Not started (pid ${process.pid}, RUN_CRON=${process.env.RUN_CRON}, NODE_APP_INSTANCE=${process.env.NODE_APP_INSTANCE ?? 'unset'}).`
        );
        return;
    }

    const isTs = __filename.endsWith('.ts') || !fs.existsSync(path.join(__dirname, 'cronWorker.js'));
    const workerFileName = isTs ? 'cronWorker.ts' : 'cronWorker.js';
    const workerPath = path.join(__dirname, workerFileName);
    const execArgv = isTs
        ? ['-r', 'ts-node/register/transpile-only', ...process.execArgv.filter(a => a !== '-r' && !a.includes('ts-node'))]
        : process.execArgv;
    const child = fork(workerPath, [], {
        env: { ...process.env, TS_NODE_TRANSPILE_ONLY: 'true' },
        execArgv,
    });
    logger.info(`[CronWorker] Forked background job process ${child.pid}.`);

    child.on('exit', (code, signal) => {
        // Losing the worker silently would stop every reminder, payment timeout
        // and expiry in the product, so it is always brought back — but with a
        // widening delay so a crash loop cannot saturate the container.
        cronWorkerRestarts++;
        const delayMs = Math.min(30000, 1000 * Math.pow(2, Math.min(cronWorkerRestarts, 5)));
        logger.error(
            `[CronWorker] Process ${child.pid} exited (code=${code}, signal=${signal}). Restarting in ${delayMs}ms (restart #${cronWorkerRestarts}).`
        );
        setTimeout(forkCronWorker, delayMs);
    });
};

const startServer = async () => {
    try {
        await connectDatabase();

        // Attach the cross-process socket adapter before accepting traffic, so
        // no client can connect during the window where an emit would not fan
        // out. A failure here is logged, never fatal — the API still serves.
        await socketAdapterReady;

        httpServer.listen(PORT, () => {
            logger.info(`Worker ${process.pid} running server on http://${HOST}:${PORT}`);
            logger.info(`Environment: ${process.env.NODE_ENV}`);
            logger.info(`Cache Engine: ${redisService.isReady() ? 'Azure Managed Redis' : 'In-Memory High-Speed Cache'}`);
        });

        // Background jobs are NOT started here any more.
        //
        // They used to run inline in this process. node-cron then began logging
        // "missed execution ... Possible blocking IO or high CPU" because the
        // scheduled work and the HTTP handlers shared one event loop. A stalled
        // event loop also stops Node accepting sockets, the kernel accept queue
        // overflows, SYNs are dropped, and the client sits through TCP
        // retransmission backoff — measured as 13-21s hangs on requests that the
        // server itself answers in under 100ms, including `/health`, which does
        // no I/O at all.
        //
        // The jobs now run in a forked child with its own event loop, so they
        // cannot delay a request no matter how long they take.
        forkCronWorker();
    } catch (error) {
        logger.error('Failed to start server:', error);
        process.exit(1);
    }
};

if (require.main === module && process.env.NODE_ENV !== 'test') {
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
