import { Router } from 'express';
import { body, param } from 'express-validator';
import { validate } from '../middleware/validate';
import { uploadTempPhotos } from '../middleware/upload';
import mobileUserController from '../controllers/mobileUserController';

const router = Router();

// ── Validation Middlewares ───────────────────────────────────────────────────

const profileSetupValidation = [
    // Step 2
    body('bio').optional().trim().isLength({ max: 200 }).withMessage('Bio must be at most 200 characters'),
    body('lookingFor').optional().isArray().withMessage('lookingFor must be an array'),
    // Step 3
    body('musicPreference').optional().isArray().withMessage('musicPreference must be an array'),
    body('smokingPreference').optional().trim().isString(),
    body('drinkPreference').optional().isArray().withMessage('drinkPreference must be an array'),
    body('occupation').optional().trim().isString(),
    body('education').optional().trim().isString(),
    body('budgetRange').optional().trim().isString(),
    // Step 4
    body('preferredGenders').optional().isArray().withMessage('preferredGenders must be an array'),
    body('minAgePreference').optional().isInt({ min: 18 }).withMessage('minAgePreference must be at least 18'),
    body('maxAgePreference').optional().isInt({ max: 100 }),
    body('showMeInMatching').optional().isBoolean(),
    body('matchDistanceKm').optional().isInt({ min: 1 }),
    body('bookingAlertsEnabled').optional().isBoolean(),
    validate,
];

// ── Routes ────────────────────────────────────────────────────────────────────

/**
 * POST /api/mobile/user/photos
 * 
 * Public/Testing — userId must be provided in body.
 * Upload multiple photos (multipart/form-data) under the field "photos".
router.post('/photos', uploadTempPhotos.array('photos', 6), mobileUserController.uploadPhotos);

/**
 * POST /api/mobile/user/verify-face
 * 
 * Verifies a live selfie against a profile photo using face recognition.
 * Expects: profilePhoto (file), selfiePhoto (file), userId (string)
 */
router.post('/verify-face', uploadTempPhotos.fields([{ name: 'profilePhoto', maxCount: 1 }, { name: 'selfiePhoto', maxCount: 1 }]), mobileUserController.verifyFace);

/**
 * PUT /api/mobile/user/profile-setup
 * 
 * Public/Testing — userId must be provided in body.
 * Save JSON data for the onboarding steps 2, 3, and 4.
 */
router.put('/profile-setup', profileSetupValidation, mobileUserController.completeProfileSetup);

/**
 * GET /api/mobile/user/userprofile
 *
 * Public/Testing — userId can be passed in body for testing.
 * In production, attach the authenticate middleware and use req.user.id.
 * Returns the user's name and profile photo.
 */
router.get('/userprofile', mobileUserController.getMyProfile);

/**
 * GET /api/mobile/user/customers
 *
 * Returns all users with role = customer, including profile, preferences, and primary photo.
 *
 * Query params:
 *   page   - page number  (default: 1)
 *   limit  - per page     (default: 20, max: 100)
 *   search - search by name / email / phone
 *   city   - filter by profile city
 *
 * Example:
 *   GET /api/mobile/user/customers?page=1&limit=20
 *   GET /api/mobile/user/customers?search=vishal
 *   GET /api/mobile/user/customers?city=Pune
 */
router.get('/customers', mobileUserController.getAllCustomers);

/**
 * GET /api/mobile/user/:id/status
 * Returns the online status and last active timestamp for a specific user
 */
router.get('/:id/status', [param('id').isUUID(), validate], mobileUserController.getUserStatus);

/**
 * POST /api/mobile/user/fcm-token
 *
 * Registers (or updates) the FCM device token for push notifications.
 * Body: { userId: string, token: string, platform: 'android' | 'ios' }
 */
router.post(
    '/fcm-token',
    [
        body('userId').notEmpty().withMessage('userId is required'),
        body('token').notEmpty().withMessage('token is required'),
        validate,
    ],
    mobileUserController.registerFcmToken
);

/**
 * POST /api/mobile/user/block
 */
router.post('/block', [
    body('userId').optional().isUUID(),
    body('targetUserId').notEmpty().isUUID(),
    validate
], mobileUserController.blockUser);

/**
 * POST /api/mobile/user/unblock
 */
router.post('/unblock', [
    body('userId').optional().isUUID(),
    body('targetUserId').notEmpty().isUUID(),
    validate
], mobileUserController.unblockUser);

/**
 * POST /api/mobile/user/report
 */
router.post('/report', [
    body('userId').optional().isUUID(),
    body('targetUserId').notEmpty().isUUID(),
    body('reason').optional().isString(),
    validate
], mobileUserController.reportUser);

/**
 * GET /api/mobile/user/blocks
 */
router.get('/blocks', mobileUserController.getBlockedUsers);

/**
 * GET /api/mobile/user/notifications
 * Returns a list of notifications for the user
 */
router.get('/notifications', async (req, res) => {
    try {
        const { userId } = req.query;
        if (!userId) return res.status(400).json({ success: false, message: 'userId required' });
        
        // Mock notifications for demonstration
        const notifications = [
            {
                id: 'notif_1',
                title: 'Like',
                body: 'Elara Velvet liked your profile ❤️',
                createdAt: new Date(Date.now() - 3600000).toISOString(), // 1 hour ago
                read: false,
            },
            {
                id: 'notif_2',
                title: 'Payment Successful',
                body: 'Payment of ₹99 confirmed for joining Party Plan at Ultra Club',
                createdAt: new Date(Date.now() - 86400000).toISOString(), // 1 day ago
                read: true,
            },
            {
                id: 'notif_3',
                title: 'Profile Visit',
                body: 'Sarah J. viewed your profile',
                createdAt: new Date(Date.now() - 172800000).toISOString(), // 2 days ago
                read: true,
            },
            {
                id: 'notif_4',
                title: 'Plan Request Accepted',
                body: 'Your plan request was accepted by Alex. Pay to confirm.',
                createdAt: new Date(Date.now() - 3600000 * 5).toISOString(),
                read: false,
            }
        ];
        
        return res.json({ success: true, data: notifications });
    } catch (error) {
        return res.status(500).json({ success: false, message: 'Failed to fetch notifications' });
    }
});

/**
 * PATCH /api/mobile/user/notifications/:id/read
 */
router.patch('/notifications/:id/read', async (_req, res) => {
    return res.json({ success: true, message: 'Notification marked as read' });
});

/**
 * GET /api/mobile/user/badge-counts
 */
router.get('/badge-counts', async (req, res) => {
    try {
        const { userId } = req.query;
        if (!userId) return res.status(400).json({ success: false, message: 'userId required' });
        
        // Mock values: 2 unread notifications/live feed, 5 unread chats
        return res.json({ 
            success: true, 
            data: {
                liveFeedCount: 2,
                chatCount: 5,
                totalCount: 7
            }
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: 'Failed to fetch badge counts' });
    }
});

/**
 * POST /api/mobile/user/swipe
 * Processes a profile swipe (like, superlike, nope)
 */
router.post('/swipe', mobileUserController.swipeUser);

/**
 * GET /api/mobile/user/likes-matches
 * Fetch all likes/matches for a user
 */
router.get('/likes-matches', mobileUserController.getMyLikesAndMatches);

// ── Chat Subscription Routes ──────────────────────────────────────────────────
import * as chatSubCtrl from '../controllers/chatSubscriptionController';

/** GET /api/mobile/chat/session-status/:conversationId */
router.get('/chat/session-status/:conversationId', chatSubCtrl.getSessionStatus);

/** POST /api/mobile/chat/init-free */
router.post('/chat/init-free', chatSubCtrl.initFreeChat);

/** POST /api/mobile/chat/extend */
router.post('/chat/extend', chatSubCtrl.extendChat);

/** POST /api/mobile/chat/request-extension */
router.post('/chat/request-extension', chatSubCtrl.requestExtension);

/** POST /api/mobile/chat/accept-extension-request */
router.post('/chat/accept-extension-request', chatSubCtrl.acceptExtensionRequest);

export default router;
