import { Router } from 'express';
import { body, param } from 'express-validator';
import { validate } from '../middleware/validate';
import { uploadTempPhotos } from '../middleware/upload';
import mobileUserController from '../controllers/mobileUserController';
import { User, UserMatch, Payment, PartyPlanRequest, PlanJoinRequest, Conversation, Message, Plan, PartyPlan, Venue } from '../models';
import { Op } from 'sequelize';
import { optionalAuth } from '../middleware/auth';

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
 */
router.post('/photos', uploadTempPhotos.array('photos', 6), mobileUserController.uploadPhotos);



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
router.get('/customers', optionalAuth, mobileUserController.getAllCustomers);

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
 * GET /api/mobile/user/blocks/details
 */
router.get('/blocks/details', optionalAuth, mobileUserController.getBlockedUsersDetails);

const readNotificationIds = new Set<string>();
const readRequestIds = new Set<string>();

async function getUserNotifications(uId: string): Promise<any[]> {
    const user = await User.findByPk(uId, { attributes: ['clearedNotificationsAt'] });
    const clearedAt = user?.clearedNotificationsAt ? new Date(user.clearedNotificationsAt).getTime() : 0;

    // 1. Fetch Likes & Super Likes
    const matches = await UserMatch.findAll({
        where: { user2Id: uId },
        include: [
            {
                model: User,
                as: 'user1',
                attributes: ['id', 'firstName', 'lastName', 'profileImageUrl']
            }
        ],
        order: [['createdAt', 'DESC']],
        limit: 20
    });

    // 2. Fetch Payments
    const payments = await Payment.findAll({
        where: { userId: uId },
        order: [['createdAt', 'DESC']],
        limit: 20
    });

    // 3. Fetch PartyPlanRequests
    const partyRequests = await PartyPlanRequest.findAll({
        where: { requesterId: uId },
        include: [
            {
                model: PartyPlan,
                as: 'plan',
                include: [
                    {
                        model: Venue,
                        as: 'venue',
                        attributes: ['name']
                    }
                ]
            }
        ],
        order: [['createdAt', 'DESC']],
        limit: 20
    });

    // 4. Fetch PlanJoinRequests
    const planJoinRequests = await PlanJoinRequest.findAll({
        where: { requesterId: uId },
        include: [
            {
                model: Plan,
                as: 'plan',
                include: [
                    {
                        model: Venue,
                        as: 'venue',
                        attributes: ['name']
                    }
                ]
            }
        ],
        order: [['createdAt', 'DESC']],
        limit: 20
    });

    // Compile notifications list
    const notifications: any[] = [];

    // Add Likes/Super Likes
    for (const match of matches) {
        const sender = (match as any).user1;
        if (!sender) continue;
        const senderName = `${sender.firstName} ${sender.lastName}`;
        const isSuper = match.matchReason === 'superlike';
        const title = isSuper ? 'Super Like' : 'Like';
        const body = isSuper 
            ? `${senderName} super liked your profile 🌟`
            : `${senderName} liked your profile ❤️`;
        
        const notificationId = `match_${match.id}`;
        const isRead = match.status === 'connected' || match.status === 'declined' || readNotificationIds.has(notificationId);

        notifications.push({
            id: notificationId,
            title,
            body,
            createdAt: match.createdAt ? match.createdAt.toISOString() : new Date().toISOString(),
            read: isRead,
        });
    }

    // Add Payments
    for (const p of payments) {
        const notificationId = `payment_${p.id}`;
        const isSuccess = p.status === 'successful';
        notifications.push({
            id: notificationId,
            title: isSuccess ? 'Payment Successful' : 'Payment Update',
            body: `Payment of ₹${p.amount} ${isSuccess ? 'confirmed' : p.status}.`,
            createdAt: p.createdAt ? p.createdAt.toISOString() : new Date().toISOString(),
            read: readNotificationIds.has(notificationId),
        });
    }

    // Add PartyPlanRequests
    for (const pr of partyRequests) {
        const plan = (pr as any).plan;
        const venueName = plan?.venue?.name || 'Club';
        let body = '';
        let title = 'Plan Request Update';
        const notificationId = `ppr_${pr.id}`;
        let isRead = false;

        if (pr.status === 'accepted') {
            title = 'Plan Request Accepted';
            body = `Your request to join Party Plan at ${venueName} was accepted. Pay to confirm.`;
        } else if (pr.status === 'payment_pending') {
            title = 'Plan Request Accepted';
            body = `Your request to join Party Plan at ${venueName} was accepted. Pay to confirm.`;
        } else if (pr.status === 'rejected') {
            body = `Your request to join Party Plan at ${venueName} was declined.`;
            isRead = true;
        } else {
            continue;
        }

        notifications.push({
            id: notificationId,
            title,
            body,
            createdAt: pr.updatedAt ? pr.updatedAt.toISOString() : (pr.createdAt ? pr.createdAt.toISOString() : new Date().toISOString()),
            read: isRead || readNotificationIds.has(notificationId),
        });
    }

    // Add PlanJoinRequests
    for (const pjr of planJoinRequests) {
        const plan = (pjr as any).plan;
        const venueName = plan?.venue?.name || 'Club';
        let body = '';
        let title = 'Plan Request Update';
        const notificationId = `pjr_${pjr.id}`;
        let isRead = false;

        if (pjr.status === 'accepted') {
            title = 'Plan Request Accepted';
            body = `Your request to join Stranger Meet at ${venueName} was accepted.`;
        } else if (pjr.status === 'rejected') {
            body = `Your request to join Stranger Meet at ${venueName} was declined.`;
            isRead = true;
        } else {
            continue;
        }

        notifications.push({
            id: notificationId,
            title,
            body,
            createdAt: pjr.updatedAt ? pjr.updatedAt.toISOString() : (pjr.createdAt ? pjr.createdAt.toISOString() : new Date().toISOString()),
            read: isRead || readNotificationIds.has(notificationId),
        });
    }

    // Simulated profile visits using other real users
    const otherUsers = await User.findAll({
        where: {
            id: { [Op.ne]: uId },
            role: 'customer'
        },
        limit: 3
    });

    otherUsers.forEach((user, index) => {
        const name = `${user.firstName} ${user.lastName}`;
        const timeDiff = (index + 1) * 2 * 3600000;
        const notificationId = `visit_${user.id}_${index}`;
        notifications.push({
            id: notificationId,
            title: 'Profile Visit',
            body: `${name} viewed your profile`,
            createdAt: new Date(Date.now() - timeDiff).toISOString(),
            read: readNotificationIds.has(notificationId),
        });
    });

    notifications.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
    return notifications.filter(n => new Date(n.createdAt).getTime() > clearedAt);
}

/**
 * GET /api/mobile/user/notifications
 * Returns a list of notifications for the user
 */
router.get('/notifications', async (req, res) => {
    try {
        const { userId } = req.query;
        if (!userId) return res.status(400).json({ success: false, message: 'userId required' });

        const uId = userId as string;
        const notifications = await getUserNotifications(uId);

        return res.json({ success: true, data: notifications });
    } catch (error: any) {
        console.error('Error fetching notifications:', error);
        return res.status(500).json({ success: false, message: 'Failed to fetch notifications' });
    }
});

/**
 * PATCH /api/mobile/user/notifications/:id/read
 */
router.patch('/notifications/:id/read', async (req, res) => {
    const { id } = req.params;
    readNotificationIds.add(id);
    return res.json({ success: true, message: 'Notification marked as read' });
});

/**
 * POST /api/mobile/user/notifications/clear-all
 */
router.post('/notifications/clear-all', async (req, res) => {
    try {
        const { userId } = req.body;
        if (!userId) return res.status(400).json({ success: false, message: 'userId required' });

        const user = await User.findByPk(userId);
        if (!user) return res.status(404).json({ success: false, message: 'User not found' });

        user.clearedNotificationsAt = new Date();
        await user.save();

        return res.json({ success: true, message: 'All notifications cleared successfully' });
    } catch (error: any) {
        console.error('Error clearing notifications:', error);
        return res.status(500).json({ success: false, message: 'Failed to clear notifications' });
    }
});

/**
 * PATCH /api/mobile/user/requests/:id/read
 */
router.patch('/requests/:id/read', async (req, res) => {
    const { id } = req.params;
    readRequestIds.add(id);
    return res.json({ success: true, message: 'Request marked as read' });
});

/**
 * GET /api/mobile/user/badge-counts
 */
router.get('/badge-counts', async (req, res) => {
    try {
        const { userId } = req.query;
        if (!userId) return res.status(400).json({ success: false, message: 'userId required' });

        const uId = userId as string;

        // 1. General notifications count
        const notifications = await getUserNotifications(uId);
        const unreadNotificationsCount = notifications.filter(n => n.read !== true).length;

        // 2. Incoming Stranger Meet requests
        const myTablePlans = await Plan.findAll({ where: { userId: uId }, attributes: ['id'] });
        const myTablePlanIds = myTablePlans.map(p => p.id);
        const unreadIncomingTableRequestsCount = myTablePlanIds.length > 0
            ? (await PlanJoinRequest.findAll({ where: { planId: { [Op.in]: myTablePlanIds }, status: 'pending' } }))
                .filter(r => !readRequestIds.has(r.id)).length
            : 0;

        // 3. Incoming Party Plan requests
        const myPartyPlans = await PartyPlan.findAll({ where: { userId: uId }, attributes: ['id'] });
        const myPartyPlanIds = myPartyPlans.map(p => p.id);
        const unreadIncomingPartyRequestsCount = myPartyPlanIds.length > 0
            ? (await PartyPlanRequest.findAll({ where: { planId: { [Op.in]: myPartyPlanIds }, status: 'pending' } }))
                .filter(r => !readRequestIds.has(r.id)).length
            : 0;

        // 4. Outgoing accepted requests (waiting for user payment)
        const unreadPartyRequestsCount = await PartyPlanRequest.count({
            where: {
                requesterId: uId,
                status: { [Op.in]: ['accepted', 'payment_pending'] },
                joinerPaymentStatus: 'unpaid'
            }
        });

        const unreadPlanRequestsCount = await PlanJoinRequest.count({
            where: {
                requesterId: uId,
                status: 'accepted',
                paymentStatus: 'pending'
            }
        });

        const liveFeedCount = unreadNotificationsCount + 
                              unreadIncomingTableRequestsCount + 
                              unreadIncomingPartyRequestsCount + 
                              unreadPartyRequestsCount + 
                              unreadPlanRequestsCount;

        const userConversations = await Conversation.findAll({
            where: {
                [Op.or]: [
                    { participantOne: uId },
                    { participantTwo: uId }
                ]
            }
        });

        const conversationIds = userConversations.map(c => c.id);

        let chatCount = 0;
        if (conversationIds.length > 0) {
            chatCount = await Message.count({
                where: {
                    conversationId: { [Op.in]: conversationIds },
                    senderId: { [Op.ne]: uId },
                    status: { [Op.ne]: 'read' }
                }
            });
        }

        return res.json({
            success: true,
            data: {
                liveFeedCount,
                chatCount,
                totalCount: liveFeedCount + chatCount
            }
        });
    } catch (error: any) {
        console.error('Error fetching badge counts:', error);
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
