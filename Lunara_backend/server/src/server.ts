import express, { Application } from 'express';
import dotenv from 'dotenv';
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
import { Op } from 'sequelize';
import { startPartyPlanCron } from './cron/partyPlanCron';

// Load environment variables
dotenv.config();

const app: Application = express();

// Trust reverse proxy (e.g., NGINX) to ensure rate limiter uses real client IPs
app.set('trust proxy', 1);

const httpServer = createServer(app);
const io = new SocketIOServer(httpServer, {
    cors: {
        origin: process.env.SOCKET_IO_CORS_ORIGIN?.split(',') || ['http://localhost:3000'],
        credentials: true,
    },
});

// Middleware
app.use(helmet({
    crossOriginResourcePolicy: { policy: "cross-origin" },
    contentSecurityPolicy: {
        directives: {
            ...helmet.contentSecurityPolicy.getDefaultDirectives(),
            "img-src": ["'self'", "data:", "blob:", "*.blob.core.windows.net", "placehold.co", "*.placehold.co", "images.unsplash.com"],
            "connect-src": ["'self'", "*.azurewebsites.net", "*.windows.net"],
        },
    },
})); // Security headers

// Explicit Permissions-Policy to silence the 'unload' violation from Chrome extensions
app.use((_req, res, next) => {
    res.setHeader('Permissions-Policy', 'unload=()');
    next();
});

app.use(cors({
    origin: true,
    credentials: true,
}));
app.use(compression()); // Compress responses
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(cookieParser());
app.use(morgan('combined', { stream: { write: (message) => logger.info(message.trim()) } }));
app.set('trust proxy', 1);
// Rate limiting (only in production/staging)
if (process.env.NODE_ENV !== 'development') {
    const limiter = rateLimit({
        windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000'),
        max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '10000'),
        message: { success: false, message: 'Too many requests from this IP, please try again later.' },
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
if (process.env.AZURE_STORAGE_ACCOUNT_NAME) {
    const accountName = process.env.AZURE_STORAGE_ACCOUNT_NAME;
    const containerName = process.env.AZURE_STORAGE_CONTAINER_NAME || 'lunara-uploads';
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
import adminGroupPartyRoutes from './routes/adminGroupParty';
import profileRoutes from './routes/profile';
import mobileStrangersMeetRoutes from './routes/mobileStrangersMeet';
import adminStrangersMeetRoutes from './routes/adminStrangersMeet';
import mobileCityRoutes from './routes/mobileCity';
import adminBookingsRoutes from './routes/adminBookings';
import adminSubscriptionRoutes from './routes/adminSubscription';
import mobileSubscriptionRoutes from './routes/mobileSubscription';
import { getAdminChatSettings, updateAdminChatSettings } from './controllers/chatSubscriptionController';

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
app.use('/api/admin/group-parties', adminGroupPartyRoutes); // Group Parties (Admin)
app.use('/api/profile', profileRoutes);                    // Edit Profile & Password APIs
app.use('/api/mobile/strangers-meet', mobileStrangersMeetRoutes); // Strangers Meet (Mobile)
app.use('/api/admin/strangers-meet', adminStrangersMeetRoutes);
app.use('/api/admin/bookings', adminBookingsRoutes);   // Strangers Meet (Admin)
app.use('/api/mobile/cities', mobileCityRoutes);                   // Cities (Mobile App)
app.use('/api/admin/subscriptions', adminSubscriptionRoutes); // Subscriptions (Admin)
app.use('/api/mobile/subscriptions', mobileSubscriptionRoutes); // Subscriptions (Mobile)

// Admin — chat subscription settings
app.get('/api/admin/settings/chat', getAdminChatSettings);
app.put('/api/admin/settings/chat', updateAdminChatSettings);

// TODO: Import and use other route modules
// app.use('/api/bookings', bookingRoutes);
// app.use('/api/payments', paymentRoutes);

// Socket.IO connection handling
io.on('connection', (socket) => {
    logger.info(`Client connected: ${socket.id}`);

    socket.on('join_user_room', async (userId: string) => {
        socket.join(`user_${userId}`);
        (socket as any).userId = userId;
        logger.info(`Socket ${socket.id} joined user room user_${userId}`);

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
                    const otherUser = conv.participantOne === userId ? conv.participantTwo : conv.participantOne;
                    io.to(`user_${otherUser}`).emit('messages_delivered', { conversationId: conv.id });
                }
            }
        } catch (err) {
            logger.error('Failed to update online status or delivery:', err);
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

    // TODO: Add socket event handlers for real-time features
    // - venue availability updates
    // - booking confirmations
    // - admin notifications
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
const startServer = async () => {
    try {
        await connectDatabase();
        httpServer.listen(PORT, () => {
            logger.info(`Server running on http://${HOST}:${PORT}`);
            logger.info(`Environment: ${process.env.NODE_ENV}`);
        });

        // Start Background Cron Jobs
        startPartyPlanCron();
    } catch (error) {
        logger.error('Failed to start server:', error);
        process.exit(1);
    }
};

if (process.env.NODE_ENV !== 'test') {
    startServer();
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
