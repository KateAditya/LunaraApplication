// Trigger azure deployment 2
import { Router } from 'express';
import { body, param } from 'express-validator';
import { validate } from '../middleware/validate';
import { uploadTempPhotos } from '../middleware/upload';
import mobileUserController from '../controllers/mobileUserController';
import { User, UserMatch, Payment, PartyPlanRequest, PlanJoinRequest, Conversation, Message, Plan, PartyPlan, Venue, StrangersMeetRequest, StrangersMeetJoiner, SafetyCheck, Booking, GroupParty } from '../models';
import Notification from '../models/Notification';
import { Op } from 'sequelize';
import { optionalAuth } from '../middleware/auth';
import { NotificationActionController } from '../controllers/NotificationActionController';
import { enrichPartyPlanNotificationCard } from '../controllers/partyPlanController';

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
router.get('/userprofile', optionalAuth, mobileUserController.getMyProfile);

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

router.post(
    '/unregister-fcm-token',
    mobileUserController.unregisterFcmToken
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

// Per-user read notification tracking (keyed by userId to prevent cross-user leakage)
const userReadNotificationIds = new Map<string, Set<string>>();
const userReadRequestIds = new Map<string, Set<string>>();

function getReadNotificationIds(userId: string): Set<string> {
    if (!userReadNotificationIds.has(userId)) {
        userReadNotificationIds.set(userId, new Set<string>());
    }
    return userReadNotificationIds.get(userId)!;
}

function getReadRequestIds(userId: string): Set<string> {
    if (!userReadRequestIds.has(userId)) {
        userReadRequestIds.set(userId, new Set<string>());
    }
    return userReadRequestIds.get(userId)!;
}


function getDateSection(createdAtStr: string): 'Today' | 'Yesterday' | 'This Week' | 'Earlier' {
    const date = new Date(createdAtStr);
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);
    const startOfWeek = new Date(today);
    startOfWeek.setDate(startOfWeek.getDate() - today.getDay());
    const dateTime = date.getTime();
    if (dateTime >= today.getTime()) return 'Today';
    if (dateTime >= yesterday.getTime()) return 'Yesterday';
    if (dateTime >= startOfWeek.getTime()) return 'This Week';
    return 'Earlier';
}

async function getUserNotifications(
    uId: string,
    filter: string = 'all',
    search: string = '',
    clientReadNotificationIds?: Set<string>,
    serverReadNotificationIds?: Set<string>
): Promise<any[]> {
    const user = await User.findByPk(uId, { attributes: ['clearedNotificationsAt'] });
    const clearedAt = user?.clearedNotificationsAt ? new Date(user.clearedNotificationsAt).getTime() : 0;
    const perUserServerIds = serverReadNotificationIds || getReadNotificationIds(uId);
    const activeReadNotificationIds = new Set<string>([
        ...(clientReadNotificationIds || []),
        ...perUserServerIds,
    ]);

    const notifications: any[] = [];
    const partyPlanIds = new Set<string>();

    // 0. Fetch stored DB Notification records
    try {
        const storedNotifs = await Notification.findAll({
            where: { recipientUserId: uId },
            order: [['createdAt', 'DESC']],
            limit: 100
        });

        for (const sn of storedNotifs) {
            const notificationId = sn.id;
            const isRead = sn.isRead || activeReadNotificationIds.has(notificationId);
            const metadata = sn.metadata || {};
            
            // Extract partyPlanId if present
            const pId = metadata.planId || metadata.partyPlanId || (sn.entityType === 'party_plan' ? sn.entityId : null);
            if (pId) {
                partyPlanIds.add(pId);
            }

            notifications.push({
                id: notificationId,
                title: sn.title,
                body: sn.body,
                category: sn.category || 'system',
                type: sn.eventType || 'system_notice',
                createdAt: sn.createdAt ? sn.createdAt.toISOString() : new Date().toISOString(),
                read: isRead,
                isRead: isRead,
                data: metadata,
                deepLink: sn.deepLink,
                actionType: sn.actionType,
                entityType: sn.entityType,
                entityId: sn.entityId,
            });
        }
    } catch (snErr) {
        console.error('Error fetching stored Notification records:', snErr);
    }

    // Fetch active/recent PartyPlans for the user to make sure they have a card
    try {
        const recentPlans = await PartyPlan.findAll({
            where: {
                [Op.or]: [
                    { userId: uId },
                    { '$requests.requesterId$': uId }
                ]
            },
            include: [{
                model: PartyPlanRequest,
                as: 'requests',
                required: false
            }],
            limit: 20
        });
        for (const plan of recentPlans) {
            partyPlanIds.add(plan.id);
        }
    } catch (planErr) {
        console.error('Error fetching recent plans for notifications:', planErr);
    }

    // Build/Enrich Unified Party Plan Timeline Cards
    const timelineCards: any[] = [];
    for (const planId of partyPlanIds) {
        const card = await enrichPartyPlanNotificationCard(planId, uId);
        if (card && card.currentStatus !== 'Waiting other user') {
            // Find all DB notifications associated with this plan
            const planNotifs = notifications.filter(n => {
                const metadata = n.data || {};
                const pId = metadata.planId || metadata.partyPlanId || (n.entityType === 'party_plan' ? n.entityId : null);
                return pId === planId;
            });

            // Timeline card is unread if ANY database notification for this plan is unread
            const hasUnread = planNotifs.length > 0 ? planNotifs.some(n => !n.read) : false;
            
            // The timestamp is the max of the plan's update time and latest notification's time
            let maxTime = new Date(card.lastUpdated).getTime();
            for (const pn of planNotifs) {
                const pt = new Date(pn.createdAt).getTime();
                if (pt > maxTime) maxTime = pt;
            }

            timelineCards.push({
                id: `party_plan_timeline_${planId}`,
                title: card.planTitle,
                body: card.currentStatus,
                category: 'events',
                type: 'party_plan_timeline',
                createdAt: new Date(maxTime).toISOString(),
                read: !hasUnread,
                isRead: !hasUnread,
                data: card,
                deepLink: `/party-plans/${planId}`,
            });
        }
    }

    // Filter out raw party plan notifications (they are now unified in timelineCards)
    const otherNotifs = notifications.filter(n => {
        const metadata = n.data || {};
        const pId = metadata.planId || metadata.partyPlanId || (n.entityType === 'party_plan' ? n.entityId : null);
        return !pId;
    });

    // Merge other notifications and unified timeline cards
    notifications.length = 0;
    notifications.push(...otherNotifs, ...timelineCards);

    // 1. Fetch Likes & Super Likes (in-memory fallback)
    try {
        const matches = await UserMatch.findAll({
            where: { user2Id: uId },
            include: [{ model: User, as: 'user1', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] }],
            order: [['createdAt', 'DESC']],
            limit: 20
        });
        for (const match of matches) {
            const m = match as any;
            const firstUser = m.user1;
            const notificationId = `match_${match.id}`;
            notifications.push({
                id: notificationId,
                title: m.isSuperLike ? '⭐ Super Liked!' : '💖 New Connection!',
                body: `${firstUser?.firstName || 'Someone'} ${m.isSuperLike ? 'super liked' : 'liked'} your profile.`,
                category: 'likes',
                type: m.isSuperLike ? 'super_like' : 'like',
                createdAt: match.createdAt ? match.createdAt.toISOString() : new Date().toISOString(),
                read: activeReadNotificationIds.has(notificationId),
                isRead: activeReadNotificationIds.has(notificationId),
                sender: firstUser ? {
                    id: firstUser.id,
                    firstName: firstUser.firstName,
                    lastName: firstUser.lastName,
                    profileImageUrl: firstUser.profileImageUrl,
                } : null,
                data: { matchId: match.id }
            });
        }
    } catch (matchErr) {
        console.error('Error fetching match notifications:', matchErr);
    }

    // 2. Fetch Payments (in-memory fallback)
    try {
        const payments = await Payment.findAll({
            where: { userId: uId },
            order: [['createdAt', 'DESC']],
            limit: 20
        });
        for (const payment of payments) {
            const notificationId = `payment_${payment.id}`;
            notifications.push({
                id: notificationId,
                title: '💳 Payment Transaction',
                body: `Transaction of ₹${payment.amount} was ${payment.status}.`,
                category: 'payments',
                type: 'payment_update',
                createdAt: payment.createdAt ? payment.createdAt.toISOString() : new Date().toISOString(),
                read: activeReadNotificationIds.has(notificationId),
                isRead: activeReadNotificationIds.has(notificationId),
                data: { paymentId: payment.id }
            });
        }
    } catch (payErr) {
        console.error('Error fetching payment notifications:', payErr);
    }

    // 3. Fetch Stranger Meet Cards (Unified Timeline Card Engine)
    try {
        const { StrangersMeetService } = await import('../services/StrangersMeetService');

        const hostMeets = await StrangersMeetRequest.findAll({
            where: { userId: uId },
            attributes: ['id']
        });

        const joinedRecords = await StrangersMeetJoiner.findAll({
            where: { userId: uId },
            attributes: ['strangersMeetRequestId']
        });

        const meetIds = Array.from(new Set([
            ...hostMeets.map(m => m.id),
            ...joinedRecords.map(j => j.strangersMeetRequestId)
        ]));

        for (const mId of meetIds) {
            const card = await StrangersMeetService.enrichStrangersMeetNotificationCard(mId, uId);
            if (card) {
                const notificationId = card.id;
                const isRead = activeReadNotificationIds.has(notificationId);
                notifications.push({
                    id: notificationId,
                    title: card.title,
                    body: `${card.currentStatusText} — ${card.venueName} (${card.venueArea})`,
                    createdAt: card.updatedAt,
                    read: isRead,
                    isRead: isRead,
                    category: 'bookings',
                    sender: card.host,
                    eventDetails: {
                        subject: card.title,
                        tagline: card.tagline,
                        venue: card.venueName,
                        eventDate: card.eventDate,
                        slotsFilled: card.slotsFilled,
                        totalSlots: card.totalSlots
                    },
                    data: {
                        type: 'strangers_meet_timeline',
                        strangersMeetId: card.meetId,
                        cardPayload: card
                    }
                });
            }
        }
    } catch (smErr) {
        console.error('Error fetching strangers meet notifications:', smErr);
    }

    // 4. Fetch Safety Check feedbacks
    try {
        const safetyFeedbacks = await SafetyCheck.findAll({
            where: { userId: uId, adminFeedback: { [Op.ne]: null as any } },
            include: [{ model: User, as: 'partner', attributes: ['firstName', 'lastName', 'profileImageUrl'] }],
            order: [['updatedAt', 'DESC']],
            limit: 10
        });
        for (const sf of safetyFeedbacks) {
            const partner = (sf as any).partner;
            const partnerName = partner ? `${partner.firstName} ${partner.lastName}` : 'your partner';
            const notificationId = `safety_feedback_${sf.id}`;
            notifications.push({
                id: notificationId,
                title: 'Safety Check Feedback',
                body: `Regarding your safety check with ${partnerName}: ${sf.adminFeedback}`,
                createdAt: sf.updatedAt ? sf.updatedAt.toISOString() : new Date().toISOString(),
                read: activeReadNotificationIds.has(notificationId),
                isRead: activeReadNotificationIds.has(notificationId),
                sender: partner ? {
                    id: sf.partnerId,
                    firstName: partner.firstName,
                    lastName: partner.lastName,
                    profileImageUrl: partner.profileImageUrl,
                } : null,
                data: { type: 'safety_check_feedback', safetyCheckId: sf.id }
            });
        }
    } catch (err) {
        console.error('Error fetching safety check feedbacks:', err);
    }

    // 5. Fetch Booking records (goingMode = party_request or solo)
    try {
        const bookings = await Booking.findAll({
            where: { userId: uId },
            include: [{ model: Venue, as: 'venue', attributes: ['name'] }],
            order: [['createdAt', 'DESC']],
            limit: 30
        });
        for (const booking of bookings) {
            if (booking.goingMode === 'party_request' || booking.isLargePartyRequest) {
                const { GroupPartyService } = await import('../services/GroupPartyService');
                const enrichedCard = await GroupPartyService.enrichLargePartyNotificationCard(booking.id, uId);
                if (enrichedCard) {
                    enrichedCard.read = activeReadNotificationIds.has(enrichedCard.id);
                    enrichedCard.isRead = activeReadNotificationIds.has(enrichedCard.id);
                    notifications.push(enrichedCard);
                }
            } else {
                const { VenueBookingService } = await import('../services/VenueBookingService');
                const enrichedCard = await VenueBookingService.enrichVenueBookingNotificationCard(booking.id, uId);
                if (enrichedCard) {
                    enrichedCard.read = activeReadNotificationIds.has(enrichedCard.id);
                    enrichedCard.isRead = activeReadNotificationIds.has(enrichedCard.id);
                    notifications.push(enrichedCard);
                }
            }
        }
    } catch (bookingErr) {
        console.error('Error fetching booking notifications:', bookingErr);
    }

    // 6. Fetch GroupParty records (Unified Timeline Card per Party)
    try {
        const { GroupPartyService } = await import('../services/GroupPartyService');
        const groupParties = await GroupParty.findAll({
            where: { userId: uId },
            order: [['createdAt', 'DESC']],
            limit: 20
        });
        for (const gp of groupParties) {
            const enrichedCard = await GroupPartyService.enrichGroupPartyNotificationCard(gp.id, uId);
            if (enrichedCard) {
                enrichedCard.read = activeReadNotificationIds.has(enrichedCard.id);
                enrichedCard.isRead = activeReadNotificationIds.has(enrichedCard.id);
                notifications.push(enrichedCard);
            }
        }
    } catch (gpErr) {
        console.error('Error fetching group party notifications:', gpErr);
    }

    // 7. Fetch Upcoming Night records (Unified Timeline Card per Night)
    try {
        const { NightPartnerService } = await import('../services/NightPartnerService');
        const NightPartnerRequest = (await import('../models/NightPartnerRequest')).default;
        const NightPartnerMatch = (await import('../models/NightPartnerMatch')).default;

        const hostRequests = await NightPartnerRequest.findAll({
            where: { hostId: uId },
            attributes: ['id']
        });
        const partnerRequests = await NightPartnerRequest.findAll({
            where: { partnerId: uId },
            attributes: ['id']
        });
        const hostMatches = await NightPartnerMatch.findAll({
            where: { hostId: uId },
            attributes: ['id']
        });
        const partnerMatches = await NightPartnerMatch.findAll({
            where: { partnerId: uId },
            attributes: ['id']
        });

        const nightIds = Array.from(new Set([
            ...hostRequests.map(r => r.id),
            ...partnerRequests.map(r => r.id),
            ...hostMatches.map(m => m.id),
            ...partnerMatches.map(m => m.id)
        ]));

        for (const nId of nightIds) {
            const enrichedCard = await NightPartnerService.enrichUpcomingNightNotificationCard(nId, uId);
            if (enrichedCard) {
                enrichedCard.read = activeReadNotificationIds.has(enrichedCard.id);
                enrichedCard.isRead = activeReadNotificationIds.has(enrichedCard.id);
                notifications.push(enrichedCard);
            }
        }
    } catch (unErr) {
        console.error('Error fetching upcoming night notifications:', unErr);
    }

    // Sort by createdAt descending
    notifications.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

    // universal deduplication fallback for non-timeline cards
    const entityKeys = new Map<string, any>();
    const deduplicatedNotifications: any[] = [];

    for (const n of notifications) {
        const data = n.data || {};
        const groupPartyId = data.partyId?.toString() || data.groupPartyId?.toString() ||
            (n.id?.startsWith('group_party_') ? n.id.replace(/^group_party_([^_]+).*/, '$1') : null);
        const bookingId = data.bookingId?.toString() ||
            (n.id?.startsWith('solo_booking_') ? n.id.replace(/^solo_booking_([^_]+).*/, '$1') : null) ||
            (n.id?.startsWith('large_party_') ? n.id.replace(/^large_party_([^_]+).*/, '$1') : null);

        let key: string | null = null;
        if (groupPartyId) key = `gp_${groupPartyId}`;
        else if (bookingId) key = `bk_${bookingId}`;
        else if (data.type?.startsWith('strangers_meet') && data.requestId) key = `sm_${data.requestId}`;

        if (key) {
            if (!entityKeys.has(key)) {
                entityKeys.set(key, n);
                deduplicatedNotifications.push(n);
            }
        } else {
            deduplicatedNotifications.push(n);
        }
    }

    // Apply category filtering
    let filtered = deduplicatedNotifications;
    if (filter && filter !== 'all') {
        filtered = filtered.filter(n => {
            const type = n.type || '';
            const statusText = n.data?.currentStatus || '';
            
            if (filter === 'action_required') {
                if (n.type === 'party_plan_timeline') {
                    const action = n.data?.primaryAction;
                    return action && ['Pay Now', 'Accept', 'Confirm Arrival'].includes(action);
                }
                if (type.startsWith('group_party_initiated') || type.startsWith('large_party_payment_link') || type.startsWith('large_party_approved')) {
                    return true;
                }
                if (type.includes('join_request') || type.includes('awaiting_payment')) {
                    return true;
                }
                return false;
            }
            
            if (filter === 'completed') {
                if (n.type === 'party_plan_timeline') {
                    return ['Completed', 'Cancelled', 'Expired'].includes(statusText);
                }
                if (type.includes('completed') || type.includes('cancelled') || type.includes('rejected')) {
                    return true;
                }
                return false;
            }
            
            if (filter === 'updates') {
                const isCompleted = n.type === 'party_plan_timeline' 
                    ? ['Completed', 'Cancelled', 'Expired'].includes(statusText)
                    : (type.includes('completed') || type.includes('cancelled') || type.includes('rejected'));
                
                const isActionReq = n.type === 'party_plan_timeline'
                    ? (n.data?.primaryAction && ['Pay Now', 'Accept', 'Confirm Arrival'].includes(n.data.primaryAction))
                    : (type.startsWith('group_party_initiated') || type.startsWith('large_party_payment_link') || type.startsWith('large_party_approved') || type.includes('join_request') || type.includes('awaiting_payment'));
                
                return !isCompleted && !isActionReq;
            }
            
            return true;
        });
    }

    // Apply search query
    if (search) {
        const query = search.toLowerCase();
        filtered = filtered.filter(n => {
            if (n.title?.toLowerCase().includes(query)) return true;
            if (n.body?.toLowerCase().includes(query)) return true;

            if (n.type === 'party_plan_timeline' && n.data) {
                const d = n.data;
                if (d.planTitle?.toLowerCase().includes(query)) return true;
                if (d.hostName?.toLowerCase().includes(query)) return true;
                if (d.guestName?.toLowerCase().includes(query)) return true;
                if (d.venueArea?.toLowerCase().includes(query)) return true;
                if (d.currentStatus?.toLowerCase().includes(query)) return true;
                if (d.date?.toLowerCase().includes(query)) return true;
            }
            return false;
        });
    }

    // Clear old cleared notifications
    const activeNotifs = filtered.filter(n => new Date(n.createdAt).getTime() > clearedAt);

    // Map each notification to include its date grouping section
    return activeNotifs.map(n => ({
        ...n,
        section: getDateSection(n.createdAt)
    }));
}

/**
 * GET /api/mobile/user/notifications
 * Returns a list of notifications for the user
 */
router.get('/notifications', async (req, res) => {
    try {
        const { userId, readNotificationIds, filter, search } = req.query;
        if (!userId) return res.status(400).json({ success: false, message: 'userId required' });

        const uId = userId as string;
        const filterStr = (filter as string) || 'all';
        const searchStr = (search as string) || '';

        const clientReadNotificationIds = new Set<string>(
            typeof readNotificationIds === 'string'
                ? readNotificationIds.split(',').filter(Boolean)
                : []
        );
        // Pass server-side per-user read IDs so they are merged correctly
        const notifications = await getUserNotifications(
            uId,
            filterStr,
            searchStr,
            clientReadNotificationIds,
            getReadNotificationIds(uId)
        );

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
    const userId = (req.query.userId as string) || (req.body?.userId as string);
    
    if (userId) {
        getReadNotificationIds(userId).add(id);
    }

    try {
        if (id.startsWith('party_plan_timeline_')) {
            const planId = id.replace('party_plan_timeline_', '');
            await Notification.update(
                { isRead: true, readAt: new Date() },
                { where: { recipientUserId: userId, entityType: 'party_plan', entityId: planId } }
            );
        } else {
            const notification = await Notification.findByPk(id);
            if (notification) {
                notification.isRead = true;
                notification.readAt = new Date();
                await notification.save();
            }
        }
    } catch (dbErr: any) {
        console.error('Error persisting notification read status in DB:', dbErr.message);
    }

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
 * POST /api/mobile/user/notifications/:id/action
 */
router.post('/notifications/:id/action', NotificationActionController.handleAction);

/**
 * POST /api/mobile/user/notifications/mark-all-read
 */
router.post('/notifications/mark-all-read', NotificationActionController.markAllAsRead);

/**
 * GET /api/mobile/user/notifications/unread-count
 */
router.get('/notifications/unread-count', NotificationActionController.getUnreadCount);

/**
 * PATCH /api/mobile/user/requests/:id/read
 */
router.patch('/requests/:id/read', async (req, res) => {
    const { id } = req.params;
    const userId = (req.query.userId as string) || (req.body?.userId as string);
    if (userId) {
        getReadRequestIds(userId).add(id);
    }
    return res.json({ success: true, message: 'Request marked as read' });
});

/**
 * GET /api/mobile/user/badge-counts
 */
router.get('/badge-counts', async (req, res) => {
    try {
        const { userId, readRequestIds: clientReadReqIds, readNotificationIds: clientReadNotifIds } = req.query;
        if (!userId) return res.status(400).json({ success: false, message: 'userId required' });

        const uId = userId as string;

        const activeReadRequestIds = new Set<string>(
            typeof clientReadReqIds === 'string'
                ? clientReadReqIds.split(',').filter(Boolean)
                : []
        );
        const clientParsedNotifIds = new Set<string>(
            typeof clientReadNotifIds === 'string'
                ? clientReadNotifIds.split(',').filter(Boolean)
                : []
        );
        // Merge client and server-side per-user read IDs
        const activeReadNotificationIds = new Set<string>([
            ...clientParsedNotifIds,
            ...getReadNotificationIds(uId),
        ]);

        // 1. General notifications count
        const notifications = await getUserNotifications(uId, 'all', '', activeReadNotificationIds, getReadNotificationIds(uId));
        const unreadNotificationsCount = notifications.filter(n => n.read !== true).length;

        // 2. Incoming Stranger Meet requests
        const myTablePlans = await Plan.findAll({ where: { userId: uId }, attributes: ['id'] });
        const myTablePlanIds = myTablePlans.map(p => p.id);
        const unreadIncomingTableRequestsCount = myTablePlanIds.length > 0
            ? (await PlanJoinRequest.findAll({ where: { planId: { [Op.in]: myTablePlanIds }, status: 'pending' } }))
                .filter(r => !activeReadRequestIds.has(r.id)).length
            : 0;

        // 3. Incoming Party Plan requests
        const myPartyPlans = await PartyPlan.findAll({ where: { userId: uId }, attributes: ['id'] });
        const myPartyPlanIds = myPartyPlans.map(p => p.id);
        const unreadIncomingPartyRequestsCount = myPartyPlanIds.length > 0
            ? (await PartyPlanRequest.findAll({ where: { planId: { [Op.in]: myPartyPlanIds }, status: 'pending' } }))
                .filter(r => !activeReadRequestIds.has(r.id)).length
            : 0;

        const isUUID = (str: string) => /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(str);
        const validReadRequestUUIDs = Array.from(activeReadRequestIds).filter(isUUID);

        // 4. Outgoing accepted requests (waiting for user payment)
        const partyReqWhere: any = {
            requesterId: uId,
            status: { [Op.in]: ['accepted', 'payment_pending'] },
            joinerPaymentStatus: 'unpaid',
        };
        if (validReadRequestUUIDs.length > 0) {
            partyReqWhere.id = { [Op.notIn]: validReadRequestUUIDs };
        }
        const unreadPartyRequestsCount = await PartyPlanRequest.count({ where: partyReqWhere });

        const planReqWhere: any = {
            requesterId: uId,
            status: 'accepted',
            paymentStatus: 'pending',
        };
        if (validReadRequestUUIDs.length > 0) {
            planReqWhere.id = { [Op.notIn]: validReadRequestUUIDs };
        }
        const unreadPlanRequestsCount = await PlanJoinRequest.count({ where: planReqWhere });

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

/**
 * GET /api/mobile/user/swipe-status
 * Check if current user already liked/superliked a target today, and get plan limits.
 * Query: userId, targetUserId
 */
router.get('/swipe-status', mobileUserController.getSwipeStatus);

/**
 * POST /api/mobile/user/backtrack
 * Backtrack the last swipe action on a target user, subject to subscription limit.
 */
router.post('/backtrack', mobileUserController.backtrackSwipe);

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

/**
 * POST /api/mobile/user/safety-check
 * Submits safety check report
 */
router.post('/safety-check', async (req, res) => {
    try {
        const { userId, partnerId, feltSafe, prebuiltAnswers, opinion } = req.body;
        if (!userId || !partnerId || feltSafe === undefined) {
            return res.status(400).json({ success: false, message: 'userId, partnerId, and feltSafe are required.' });
        }
        
        const safetyCheck = await SafetyCheck.create({
            userId,
            partnerId,
            feltSafe,
            prebuiltAnswers: Array.isArray(prebuiltAnswers) ? prebuiltAnswers.join(',') : prebuiltAnswers,
            opinion,
            status: 'pending'
        });
        
        return res.status(201).json({ success: true, data: safetyCheck });
    } catch (error: any) {
        console.error('Error submitting safety check:', error);
        return res.status(500).json({ success: false, message: 'Failed to submit safety check.' });
    }
});

/**
 * POST /api/mobile/user/delete-account
 *
 * Permanently deletes the user's account (soft-delete):
 *   - Requires `userId` and `password` in body for security re-authentication
 *   - Optionally accepts `reason` (string) explaining why they're leaving
 *   - Archives a full snapshot into deleted_accounts table
 *   - Sets isDeleted=true, isActive=false on the user record
 *
 * Body: { userId: string, password: string, reason?: string }
 *
 * Responses:
 *   200  { success, code: 'ACCOUNT_DELETED', message }
 *   400  { success, code: 'PASSWORD_REQUIRED', message }
 *   401  { success, code: 'INVALID_PASSWORD', message }
 *   404  { success, message: 'User not found' }
 *   409  { success, code: 'ALREADY_DELETED', message }
 *   500  { success, code: 'SERVER_ERROR', message }
 */
router.post(
    '/delete-account',
    [
        body('userId').optional().isUUID().withMessage('userId must be a valid UUID'),
        body('password').optional().isString(),
        body('reason').optional().isString().isLength({ max: 500 }),
        validate,
    ],
    mobileUserController.deleteAccount
);

/**
 * GET /api/mobile/user/profile-summary
 * Returns comprehensive profile statistics, reliability level, streaks, and platform metrics
 */
router.get('/profile-summary', async (req, res) => {
    try {
        const userId = (req.query.userId as string) || (req.user as any)?.id;
        if (!userId) {
            return res.status(400).json({ success: false, message: 'userId required' });
        }

        const user = await User.findByPk(userId);
        if (!user) {
            return res.status(404).json({ success: false, message: 'User not found' });
        }

        const score = Number(user.reliabilityScore !== undefined ? user.reliabilityScore : 70);
        
        let level = 'Good ✅';
        if (score >= 95) level = 'Elite 💎';
        else if (score >= 90) level = 'Excellent 🌟';
        else if (score >= 80) level = 'Trusted 🛡️';
        else if (score >= 70) level = 'Good ✅';
        else if (score >= 60) level = 'Average 📊';
        else if (score >= 40) level = 'Low ⚠️';
        else level = 'Restricted ⛔';

        const plansCreated = await PartyPlan.count({ where: { userId } });
        const plansJoined = await PartyPlanRequest.count({
            where: { requesterId: userId, status: 'accepted' }
        });

        const plansCompleted = await PartyPlan.count({
            where: {
                [Op.or]: [{ userId }, { '$requests.requester_id$': userId }],
                status: 'inactive'
            },
            include: [{ model: PartyPlanRequest, as: 'requests', required: false }]
        });

        const noShowCount = user.noShowCount || 0;
        const cancelledPlans = await PartyPlan.count({ where: { userId, status: 'cancelled' } });
        
        const requestsAccepted = await PartyPlanRequest.count({
            where: { '$plan.user_id$': userId, status: 'accepted' },
            include: [{ model: PartyPlan, as: 'plan', required: true }]
        });

        const requestsRejected = await PartyPlanRequest.count({
            where: { '$plan.user_id$': userId, status: 'rejected' },
            include: [{ model: PartyPlan, as: 'plan', required: true }]
        });

        const superLikesReceived = await UserMatch.count({
            where: { user2Id: userId, isSuperLike: true } as any
        });

        const totalTotalPlans = plansCreated + plansJoined;
        const completionRate = totalTotalPlans > 0 ? Math.round((plansCompleted / totalTotalPlans) * 100) : 100;
        const arrivalSuccessPercent = (totalTotalPlans - noShowCount) > 0 ? Math.min(100, Math.round(((totalTotalPlans - noShowCount) / totalTotalPlans) * 100)) : 100;

        return res.json({
            success: true,
            data: {
                userId: user.id,
                reliabilityScore: score,
                reliabilityLevel: level,
                overallRank: score >= 90 ? 'Top 5%' : score >= 80 ? 'Top 15%' : 'Top 30%',
                plansCreated,
                plansJoined,
                plansCompleted,
                completionRate: `${completionRate}%`,
                arrivalSuccessPercent: `${arrivalSuccessPercent}%`,
                noShowCount,
                cancelledPlans,
                requestsAccepted,
                requestsRejected,
                superLikesReceived,
                currentStreak: user.loginStreakDays || 1,
                bestStreak: Math.max(user.loginStreakDays || 1, 5),
                memberSince: user.createdAt ? user.createdAt.toISOString() : new Date().toISOString()
            }
        });
    } catch (err: any) {
        console.error('Error fetching profile summary:', err);
        return res.status(500).json({ success: false, message: 'Failed to fetch profile summary' });
    }
});

export default router;
