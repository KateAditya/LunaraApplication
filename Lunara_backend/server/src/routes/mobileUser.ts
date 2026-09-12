import { Router } from 'express';
import { body, param } from 'express-validator';
import { validate } from '../middleware/validate';
import { uploadTempPhotos } from '../middleware/upload';
import mobileUserController from '../controllers/mobileUserController';
import { User, UserMatch, Payment, PartyPlanRequest, PlanJoinRequest, Conversation, Plan, PartyPlan, Venue, StrangersMeetRequest, StrangersMeetJoiner, SafetyCheck, Booking, GroupParty } from '../models';
import Notification from '../models/Notification';
import { Op } from 'sequelize';
import { authenticate, optionalAuth } from '../middleware/auth';
import { NotificationActionController } from '../controllers/NotificationActionController';
import * as reliabilityCtrl from '../controllers/reliabilityController';
import { batchEnrichPartyPlanNotificationCards } from '../controllers/partyPlanController';
import { setPrimaryPhoto, deletePhoto } from '../controllers/profileController';
import { createHash } from 'crypto';
import apiCache from '../utils/apiCache';

const router = Router();

// ── Validation Middlewares ───────────────────────────────────────────────────

const profileSetupValidation = [
    // Step 2
    body('bio').optional().trim().isLength({ max: 500 }).withMessage('Bio must be at most 500 characters'),
    body('lookingFor').optional().isArray().withMessage('lookingFor must be an array'),
    body('interests').optional().isArray().withMessage('interests must be an array'),
    body('nightlifePreference').optional().isArray().withMessage('nightlifePreference must be an array'),
    // Step 3
    body('musicPreference').optional().isArray().withMessage('musicPreference must be an array'),
    body('smokingPreference').optional().trim().isString(),
    body('drinkPreference').optional().isArray().withMessage('drinkPreference must be an array'),
    body('occupation').optional().trim().isString(),
    body('education').optional().trim().isString(),
    body('city').optional().trim().isString(),
    body('budgetRange').optional().trim().isString(),
    body('minBudget').optional({ nullable: true, checkFalsy: true }).toInt().isInt({ min: 0 }),
    body('maxBudget').optional({ nullable: true, checkFalsy: true }).toInt().isInt({ min: 0 }),
    // Step 4
    body('preferredGenders').optional().isArray().withMessage('preferredGenders must be an array'),
    body('minAgePreference').optional({ nullable: true, checkFalsy: true }).toInt().isInt({ min: 18 }).withMessage('minAgePreference must be at least 18'),
    body('maxAgePreference').optional({ nullable: true, checkFalsy: true }).toInt().isInt({ max: 100 }),
    body('showMeInMatching').optional().isBoolean(),
    body('matchDistanceKm').optional({ nullable: true, checkFalsy: true }).toInt().isInt({ min: 1 }),
    body('bookingAlertsEnabled').optional().isBoolean(),
    validate,
];

// ── Routes ────────────────────────────────────────────────────────────────────

/**
 * Photo management routes
 */
router.post('/photos', authenticate, uploadTempPhotos.array('photos', 6), mobileUserController.uploadPhotos);
router.put('/photos/:id/primary', authenticate, setPrimaryPhoto);
router.delete('/photos/:id', authenticate, deletePhoto);

/**
 * PUT /api/mobile/user/profile-setup
 * 
 * Public/Testing — userId must be provided in body.
 * Save JSON data for the onboarding steps 2, 3, and 4.
 */
router.put('/profile-setup', authenticate, profileSetupValidation, mobileUserController.completeProfileSetup);

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
router.get('/:id/status', [authenticate, param('id').isUUID(), validate], mobileUserController.getUserStatus);

/**
 * POST /api/mobile/user/fcm-token
 *
 * Registers (or updates) the FCM device token for push notifications.
 * Body: { userId: string, token: string, platform: 'android' | 'ios' }
 */
router.post(
    '/fcm-token',
    [
        authenticate,
        body('userId').notEmpty().withMessage('userId is required'),
        body('token').notEmpty().withMessage('token is required'),
        validate,
    ],
    mobileUserController.registerFcmToken
);

router.post(
    '/unregister-fcm-token',
    authenticate,
    mobileUserController.unregisterFcmToken
);

/**
 * POST /api/mobile/user/block
 */
router.post('/block', [
    authenticate,
    body('userId').optional().isUUID(),
    body('targetUserId').notEmpty().isUUID(),
    validate
], mobileUserController.blockUser);

/**
 * POST /api/mobile/user/unblock
 */
router.post('/unblock', [
    authenticate,
    body('userId').optional().isUUID(),
    body('targetUserId').notEmpty().isUUID(),
    validate
], mobileUserController.unblockUser);

/**
 * POST /api/mobile/user/report
 */
router.post('/report', [
    authenticate,
    body('userId').optional().isUUID(),
    body('targetUserId').notEmpty().isUUID(),
    body('reason').optional().isString(),
    validate
], mobileUserController.reportUser);

/**
 * GET /api/mobile/user/blocks
 */
router.get('/blocks', authenticate, mobileUserController.getBlockedUsers);

/**
 * GET /api/mobile/user/blocks/details
 */
router.get('/blocks/details', optionalAuth, mobileUserController.getBlockedUsersDetails);

// Per-user read notification tracking (keyed by userId to prevent cross-user leakage)
//
// These are a best-effort supplement, not a source of truth. Read state is
// durably held in three other places: the client sends its own
// readNotificationIds with each request, Notification.isRead is persisted, and
// User.clearedNotificationsAt bounds the whole feed. This map is also discarded
// on every process restart, so the app already tolerates losing it entirely.
//
// Left unbounded it grows for the life of the process, which shows up as
// lengthening GC pauses and eventually an out-of-memory restart. Bounding it
// is strictly safer than that: an evicted entry falls back to the three sources
// above, exactly as it would after a restart.
const MAX_TRACKED_USERS = 2000;
const MAX_IDS_PER_USER = 300;

const userReadNotificationIds = new Map<string, Set<string>>();
const userReadRequestIds = new Map<string, Set<string>>();

/**
 * Fetches this user's set, refreshing its recency. When the map is over
 * capacity the least-recently-used user is dropped. Map preserves insertion
 * order, so re-inserting on access gives LRU semantics for free.
 */
function getTrackedSet(map: Map<string, Set<string>>, userId: string): Set<string> {
    let ids = map.get(userId);
    if (ids === undefined) {
        ids = new Set<string>();
    } else {
        map.delete(userId);
    }
    map.set(userId, ids);

    while (map.size > MAX_TRACKED_USERS) {
        const oldest = map.keys().next();
        if (oldest.done) break;
        map.delete(oldest.value);
    }
    return ids;
}

/** Records an id, discarding this user's oldest once past the per-user cap. */
function addTrackedId(ids: Set<string>, id: string): void {
    if (ids.has(id)) return;
    ids.add(id);
    while (ids.size > MAX_IDS_PER_USER) {
        const oldest = ids.values().next();
        if (oldest.done) break;
        ids.delete(oldest.value);
    }
}

/** Marks one notification read for this user. */
function markNotificationRead(userId: string, id: string): void {
    addTrackedId(getTrackedSet(userReadNotificationIds, userId), id);
}

/** Marks one request read for this user. */
function markRequestRead(userId: string, id: string): void {
    addTrackedId(getTrackedSet(userReadRequestIds, userId), id);
}

function getReadNotificationIds(userId: string): Set<string> {
    return getTrackedSet(userReadNotificationIds, userId);
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
    const nightPartnerIds = new Set<string>();

    // 0. Fetch stored DB Notification records
    try {
        const { SubscriptionService } = require('../services/subscriptionService');
        const canSeeWhoLiked = await SubscriptionService.hasAccess(uId, 'who_liked_me');

        const storedNotifs = await Notification.findAll({
            where: { recipientUserId: uId },
            order: [['createdAt', 'DESC']],
            limit: 100
        });

        for (const sn of storedNotifs) {
            const notificationId = sn.id;
            const snCreatedTime = sn.createdAt ? new Date(sn.createdAt).getTime() : 0;
            const isCleared = clearedAt > 0 && snCreatedTime <= clearedAt;
            const isRead = sn.isRead || isCleared || activeReadNotificationIds.has(notificationId);
            let metadata = sn.metadata || {};
            
            // Extract partyPlanId if present
            const pId = metadata.planId || metadata.partyPlanId || (sn.entityType === 'party_plan' ? sn.entityId : null);
            if (pId) {
                partyPlanIds.add(pId);
            }

            // Extract nightPartnerId if present
            const npId = metadata.nightId || metadata.matchId || metadata.requestId || (sn.entityType === 'night_partner' ? sn.entityId : null);
            if (npId) {
                nightPartnerIds.add(npId);
            }

            const isSuper = sn.category === 'super_like' || sn.eventType === 'super_like' || metadata?.action === 'superlike';
            const isNormalLike = (sn.category === 'likes' || sn.eventType === 'like' || metadata?.action === 'like') && !isSuper;
            let title = sn.title;
            let body = sn.body;
            let deepLink = sn.deepLink;
            let actionType = sn.actionType;

            if (isNormalLike && !canSeeWhoLiked) {
                title = '❤️ Someone liked your profile';
                body = 'Someone liked your profile! Upgrade to VIP to see who!';
                deepLink = '/vip-membership';
                actionType = 'open_vip_upgrade';
                metadata = {
                    ...metadata,
                    isMasked: true,
                    action: 'like',
                };
            }

            notifications.push({
                id: notificationId,
                title,
                body,
                category: sn.category || 'system',
                type: sn.eventType || 'system_notice',
                eventType: sn.eventType || 'system_notice',
                createdAt: sn.createdAt ? sn.createdAt.toISOString() : new Date().toISOString(),
                read: isRead,
                isRead: isRead,
                data: metadata,
                metadata: metadata,
                actor: metadata?.actor || null,
                sender: metadata?.actor || null,
                imageUrl: sn.imageUrl || metadata?.actor?.profilePhotoUrl || null,
                deepLink,
                actionType,
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
                    { '$requests.requester_id$': uId }
                ]
            },
            include: [{
                model: PartyPlanRequest,
                as: 'requests',
                required: false,
                attributes: ['id', 'planId', 'requesterId', 'status']
            }],
            attributes: ['id'],
            subQuery: false,
            limit: 20
        });
        for (const plan of recentPlans) {
            partyPlanIds.add(plan.id);
        }
    } catch (planErr) {
        console.error('Error fetching recent plans for notifications:', planErr);
    }

    // Build/Enrich Unified Party Plan Timeline Cards in ONE single batch query
    let timelineCards: any[] = [];
    if (partyPlanIds.size > 0) {
        try {
            const enrichedCards = await batchEnrichPartyPlanNotificationCards(Array.from(partyPlanIds), uId);
            const planCardResults = enrichedCards.map((card: any) => {
                if (!card || card.currentStatus === 'Waiting other user') return null;
                const planId = card.planId || card.id;
                // Find all DB notifications associated with this plan
                const planNotifs = notifications.filter(n => {
                    const metadata = n.data || {};
                    const pId = metadata.planId || metadata.partyPlanId || (n.entityType === 'party_plan' ? n.entityId : null);
                    return pId === planId;
                });

                const hasUnread = planNotifs.length > 0 ? planNotifs.some(n => !n.read) : false;
                let maxTime = new Date(card.lastActivityAt || card.lastUpdated || Date.now()).getTime();
                for (const pn of planNotifs) {
                    const pt = new Date(pn.createdAt).getTime();
                    if (pt > maxTime) maxTime = pt;
                }
                const lastActivityAt = new Date(maxTime).toISOString();
                const isCleared = clearedAt > 0 && maxTime <= clearedAt;
                const isCardRead = (isCleared && !card.requiresAction) || (!hasUnread && !card.requiresAction) || activeReadNotificationIds.has(`party_plan_timeline_${planId}`);

                return {
                    id: `party_plan_timeline_${planId}`,
                    title: card.planTitle,
                    body: card.currentStatus,
                    category: 'events',
                    type: 'party_plan_timeline',
                    createdAt: lastActivityAt,
                    lastActivityAt,
                    requiresAction: card.requiresAction,
                    read: isCardRead,
                    isRead: isCardRead,
                    imageUrl: card.partyImage || card.hostProfilePhotoUrl || card.guestProfilePhotoUrl,
                    host: card.host,
                    creator: card.creator,
                    user: card.user,
                    actor: card.host || card.creator || card.user,
                    sender: card.host || card.creator || card.user,
                    hostProfilePhotoUrl: card.hostProfilePhotoUrl,
                    guestProfilePhotoUrl: card.guestProfilePhotoUrl,
                    data: card,
                    plan: card,
                    deepLink: `/party-plans/${planId}`,
                };
            });
            timelineCards.push(...planCardResults.filter(Boolean));
        } catch (enrichErr) {
            console.error('Error batch enriching party plans:', enrichErr);
        }
    }

    // Filter out raw party plan and upcoming night notifications (they are now unified in timelineCards & nightCardsResult)
    const otherNotifs = notifications.filter(n => {
        const metadata = n.data || {};
        const pId = metadata.planId || metadata.partyPlanId || (n.entityType === 'party_plan' ? n.entityId : null);
        const isUnifiedPartyPlan = !!pId && timelineCards.some(tc => tc.id === `party_plan_timeline_${pId}`);
        const isNightPartnerRaw = n.entityType === 'night_partner' ||
            n.entityType === 'NightPartnerRequest' ||
            n.entityType === 'NightPartnerMatch' ||
            n.type === 'PARTNER_REQUEST_RECEIVED' ||
            n.eventType === 'PARTNER_REQUEST_RECEIVED' ||
            n.eventType === 'UPCOMING_NIGHT_TIMELINE' ||
            (n.category === 'requests' && (n.title || '').toLowerCase().includes('invite for party event'));
        return !isUnifiedPartyPlan && !isNightPartnerRaw;
    });

    // Merge other notifications and unified timeline cards
    notifications.length = 0;
    notifications.push(...otherNotifs, ...timelineCards);

    // Parallel Sub-Loaders for Maximum Speed (Runs concurrently via Promise.all)
    const [
        matchCardsResult,
        paymentCardsResult,
        smCardsResult,
        safetyCardsResult,
        bookingCardsResult,
        gpCardsResult,
        nightCardsResult
    ] = await Promise.all([
        // 1. Fetch Likes & Super Likes
        (async () => {
            try {
                const { SubscriptionService } = await import('../services/subscriptionService');
                const [matches, canSeeWhoLiked] = await Promise.all([
                    UserMatch.findAll({
                        where: { user2Id: uId },
                        include: [{ model: User, as: 'user1', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] }],
                        order: [['createdAt', 'DESC']],
                        limit: 20
                    }),
                    SubscriptionService.hasAccess(uId, 'who_liked_me')
                ]);

                const superlikeSenderIds = matches
                    .filter((m: any) => (m.matchReason === 'superlike' || m.isSuperLike) && m.user1?.id)
                    .map((m: any) => m.user1.id);

                const plansBySender = new Map<string, any[]>();
                if (superlikeSenderIds.length > 0) {
                    try {
                        const superlikePlans = await PartyPlan.findAll({
                            where: {
                                userId: { [Op.in]: superlikeSenderIds },
                                status: 'active',
                                isLive: true,
                                planDateTime: { [Op.gte]: new Date() },
                                visibility: 'public',
                            },
                            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }],
                            order: [['planDateTime', 'ASC']],
                            limit: 30,
                        });
                        for (const p of superlikePlans) {
                            const list = plansBySender.get((p as any).userId) || [];
                            if (list.length < 3) {
                                list.push({
                                    id: p.id,
                                    title: `Let's party at ${(p as any).venue?.name || 'Venue'}! 🚀`,
                                    venueName: (p as any).venue?.name || 'Venue',
                                    planDateTime: (p as any).planDateTime,
                                    status: (p as any).status,
                                    isLive: (p as any).isLive,
                                });
                                plansBySender.set((p as any).userId, list);
                            }
                        }
                    } catch (pErr) {
                        console.error('Error batch-fetching superlike sender plans:', pErr);
                    }
                }

                return matches.map((match) => {
                    const m = match as any;
                    const firstUser = m.user1;
                    const notificationId = `match_${match.id}`;

                    const mCreatedTime = match.createdAt ? new Date(match.createdAt).getTime() : 0;
                    const isCleared = clearedAt > 0 && mCreatedTime <= clearedAt;
                    const isRead = isCleared || activeReadNotificationIds.has(notificationId);
                    const isSuper = m.matchReason === 'superlike' || m.isSuperLike;
                    const senderName = `${firstUser?.firstName || 'Someone'} ${firstUser?.lastName || ''}`.trim();
                    const postedPlans = firstUser?.id ? (plansBySender.get(firstUser.id) || []) : [];

                    if (isSuper) {
                        return {
                            id: notificationId,
                            title: '⭐ Super Like!',
                            body: `${senderName} sent you a Super Like! 💜`,
                            category: 'super_like',
                            type: 'super_like',
                            actionType: 'view_profile',
                            deepLink: firstUser ? `/profile/${firstUser.id}` : undefined,
                            createdAt: match.createdAt ? match.createdAt.toISOString() : new Date().toISOString(),
                            read: isRead,
                            isRead: isRead,
                            sender: firstUser ? {
                                id: firstUser.id,
                                firstName: firstUser.firstName,
                                lastName: firstUser.lastName,
                                profileImageUrl: firstUser.profileImageUrl,
                            } : null,
                            data: {
                                matchId: match.id,
                                senderId: firstUser?.id,
                                senderName,
                                senderImage: firstUser?.profileImageUrl || '',
                                postedPlans,
                                action: 'superlike',
                            }
                        };
                    }

                    // Normal Like: receiver-driven entitlement
                    if (canSeeWhoLiked) {
                        return {
                            id: notificationId,
                            title: `💖 ${senderName} liked your profile!`,
                            body: `${senderName} liked your profile ❤️`,
                            category: 'likes',
                            type: 'like',
                            actionType: 'view_profile',
                            deepLink: firstUser ? `/profile/${firstUser.id}` : undefined,
                            createdAt: match.createdAt ? match.createdAt.toISOString() : new Date().toISOString(),
                            read: isRead,
                            isRead: isRead,
                            sender: firstUser ? {
                                id: firstUser.id,
                                firstName: firstUser.firstName,
                                lastName: firstUser.lastName,
                                profileImageUrl: firstUser.profileImageUrl,
                            } : null,
                            data: {
                                matchId: match.id,
                                senderId: firstUser?.id,
                                senderName,
                                senderImage: firstUser?.profileImageUrl || '',
                                postedPlans,
                                action: 'like',
                            }
                        };
                    } else {
                        return {
                            id: notificationId,
                            title: '❤️ Someone liked your profile',
                            body: 'Someone liked your profile! Upgrade to VIP to see who!',
                            category: 'likes',
                            type: 'like',
                            actionType: 'open_vip_upgrade',
                            deepLink: '/vip-membership',
                            createdAt: match.createdAt ? match.createdAt.toISOString() : new Date().toISOString(),
                            read: isRead,
                            isRead: isRead,
                            sender: {
                                id: 'masked',
                                firstName: 'Someone',
                                lastName: '',
                                profileImageUrl: 'https://placehold.co/400x400/2a1b38/e0a0ff.png?text=Upgrade+to+See',
                            },
                            data: {
                                matchId: match.id,
                                isMasked: true,
                                action: 'like',
                            }
                        };
                    }
                });
            } catch (err) {
                console.error('Error fetching match notifications:', err);
                return [];
            }
        })(),

        // 2. Fetch Payments
        (async () => {
            try {
                const payments = await Payment.findAll({
                    where: { userId: uId },
                    order: [['createdAt', 'DESC']],
                    limit: 20
                });
                return payments.map(payment => {
                    const notificationId = `payment_${payment.id}`;
                    return {
                        id: notificationId,
                        title: '💳 Payment Transaction',
                        body: `Transaction of ₹${payment.amount} was ${payment.status}.`,
                        category: 'payments',
                        type: 'payment_update',
                        createdAt: payment.createdAt ? payment.createdAt.toISOString() : new Date().toISOString(),
                        read: activeReadNotificationIds.has(notificationId),
                        isRead: activeReadNotificationIds.has(notificationId),
                        data: { paymentId: payment.id }
                    };
                });
            } catch (err) {
                console.error('Error fetching payment notifications:', err);
                return [];
            }
        })(),

        // 3. Fetch Stranger Meet Cards
        (async () => {
            try {
                const { StrangersMeetService } = await import('../services/StrangersMeetService');
                const [hostMeets, joinedRecords] = await Promise.all([
                    StrangersMeetRequest.findAll({
                        where: { userId: uId },
                        attributes: ['id']
                    }),
                    StrangersMeetJoiner.findAll({
                        where: { userId: uId },
                        attributes: ['strangersMeetRequestId']
                    })
                ]);

                const meetIds = Array.from(new Set([
                    ...hostMeets.map(m => m.id),
                    ...joinedRecords.map(j => j.strangersMeetRequestId)
                ]));

                const smCards = await Promise.all(
                    meetIds.map(async (mId) => {
                        try {
                            const card = await StrangersMeetService.enrichStrangersMeetNotificationCard(mId, uId);
                            if (card) {
                                const notificationId = card.id;
                                const lastActivityAt = card.lastActivityAt || card.updatedAt || new Date().toISOString();
                                const cardTime = new Date(lastActivityAt).getTime();
                                const isCleared = clearedAt > 0 && cardTime <= clearedAt;
                                const isRead = (isCleared && !card.requiresAction) || activeReadNotificationIds.has(notificationId);
                                return {
                                    id: notificationId,
                                    title: card.title,
                                    body: `${card.currentStatusText} — ${card.venueName} (${card.venueArea})`,
                                    createdAt: lastActivityAt,
                                    lastActivityAt,
                                    requiresAction: card.requiresAction,
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
                                };
                            }
                        } catch (err) {
                            console.error(`Error enriching strangers meet ${mId}:`, err);
                        }
                        return null;
                    })
                );
                return smCards.filter(Boolean);
            } catch (err) {
                console.error('Error fetching strangers meet notifications:', err);
                return [];
            }
        })(),

        // 4. Fetch Safety Check Feedbacks
        (async () => {
            try {
                const safetyFeedbacks = await SafetyCheck.findAll({
                    where: { userId: uId, adminFeedback: { [Op.ne]: null as any } },
                    include: [{ model: User, as: 'partner', attributes: ['firstName', 'lastName', 'profileImageUrl'] }],
                    order: [['updatedAt', 'DESC']],
                    limit: 10
                });
                return safetyFeedbacks.map(sf => {
                    const partner = (sf as any).partner;
                    const partnerName = partner ? `${partner.firstName} ${partner.lastName}` : 'your partner';
                    const notificationId = `safety_feedback_${sf.id}`;
                    return {
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
                    };
                });
            } catch (err) {
                console.error('Error fetching safety check feedbacks:', err);
                return [];
            }
        })(),

        // 5. Fetch Booking records
        (async () => {
            try {
                const bookings = await Booking.findAll({
                    where: {
                        userId: uId,
                        goingMode: { [Op.in]: ['solo', 'party_request'] },
                    },
                    include: [{ model: Venue, as: 'venue', attributes: ['name', 'addressLine1', 'city'] }],
                    order: [['createdAt', 'DESC']],
                    limit: 30
                });
                const bookingCards = await Promise.all(
                    bookings.map(async (booking) => {
                        try {
                            if (booking.goingMode === 'party_request' || booking.isLargePartyRequest) {
                                const { GroupPartyService } = await import('../services/GroupPartyService');
                                const enrichedCard = await GroupPartyService.enrichLargePartyNotificationCard(booking.id, uId);
                                if (enrichedCard) {
                                    const lastActivityAt = enrichedCard.lastActivityAt || enrichedCard.updatedAt || enrichedCard.createdAt || new Date().toISOString();
                                    const cardTime = new Date(lastActivityAt).getTime();
                                    const isCleared = clearedAt > 0 && cardTime <= clearedAt;
                                    const isRead = (isCleared && !enrichedCard.requiresAction) || activeReadNotificationIds.has(enrichedCard.id);
                                    enrichedCard.createdAt = lastActivityAt;
                                    enrichedCard.lastActivityAt = lastActivityAt;
                                    enrichedCard.read = isRead;
                                    enrichedCard.isRead = isRead;
                                    return enrichedCard;
                                }
                            } else {
                                const { VenueBookingService } = await import('../services/VenueBookingService');
                                const enrichedCard = await VenueBookingService.enrichVenueBookingNotificationCard(booking.id, uId, booking);
                                if (enrichedCard) {
                                    const lastActivityAt = enrichedCard.lastActivityAt || enrichedCard.updatedAt || enrichedCard.createdAt || new Date().toISOString();
                                    const cardTime = new Date(lastActivityAt).getTime();
                                    const isCleared = clearedAt > 0 && cardTime <= clearedAt;
                                    const isRead = (isCleared && !enrichedCard.requiresAction) || activeReadNotificationIds.has(enrichedCard.id);
                                    enrichedCard.createdAt = lastActivityAt;
                                    enrichedCard.lastActivityAt = lastActivityAt;
                                    enrichedCard.read = isRead;
                                    enrichedCard.isRead = isRead;
                                    return enrichedCard;
                                }
                            }
                        } catch (err) {
                            console.error(`Error enriching booking ${booking.id}:`, err);
                        }
                        return null;
                    })
                );
                return bookingCards.filter(Boolean);
            } catch (err) {
                console.error('Error fetching booking notifications:', err);
                return [];
            }
        })(),

        // 6. Fetch GroupParty records
        (async () => {
            try {
                const { GroupPartyService } = await import('../services/GroupPartyService');
                const Venue = (await import('../models/Venue')).default;
                const groupParties = await GroupParty.findAll({
                    where: {
                        userId: uId,
                        status: { [Op.ne]: 'cancelled' }
                    },
                    include: [{ model: Venue, as: 'venue', attributes: ['name', 'addressLine1', 'city'] }],
                    order: [['createdAt', 'DESC']],
                    limit: 20
                });
                const gpCards = await Promise.all(
                    groupParties.map(async (gp) => {
                        try {
                            const enrichedCard = await GroupPartyService.enrichGroupPartyNotificationCard(gp.id, uId, gp);
                            if (enrichedCard) {
                                const lastActivityAt = enrichedCard.lastActivityAt || enrichedCard.updatedAt || enrichedCard.createdAt || new Date().toISOString();
                                const cardTime = new Date(lastActivityAt).getTime();
                                const isCleared = clearedAt > 0 && cardTime <= clearedAt;
                                const isRead = (isCleared && !enrichedCard.requiresAction) || activeReadNotificationIds.has(enrichedCard.id);
                                enrichedCard.createdAt = lastActivityAt;
                                enrichedCard.lastActivityAt = lastActivityAt;
                                enrichedCard.read = isRead;
                                enrichedCard.isRead = isRead;
                                return enrichedCard;
                            }
                        } catch (err) {
                            console.error(`Error enriching group party ${gp.id}:`, err);
                        }
                        return null;
                    })
                );
                return gpCards.filter(Boolean);
            } catch (err) {
                console.error('Error fetching group party notifications:', err);
                return [];
            }
        })(),

        // 7. Fetch Upcoming Night records (Unified Timeline Card per Night)
        (async () => {
            try {
                const { NightPartnerService } = await import('../services/NightPartnerService');
                const NightPartnerRequest = (await import('../models/NightPartnerRequest')).default;
                const NightPartnerMatch = (await import('../models/NightPartnerMatch')).default;

                const [hostRequests, partnerRequests, hostMatches, partnerMatches] = await Promise.all([
                    NightPartnerRequest.findAll({
                        where: {
                            hostId: uId,
                            status: { [Op.in]: ['PENDING', 'ACCEPTED'] },
                            [Op.or]: [
                                { expiresAt: null as any },
                                { expiresAt: { [Op.gt]: new Date() } }
                            ]
                        },
                        attributes: ['id', 'venueId', 'eventDate', 'status', 'createdAt', 'updatedAt'],
                        order: [['updatedAt', 'DESC']]
                    }),
                    NightPartnerRequest.findAll({
                        where: {
                            partnerId: uId,
                            status: { [Op.in]: ['PENDING', 'ACCEPTED'] },
                            [Op.or]: [
                                { expiresAt: null as any },
                                { expiresAt: { [Op.gt]: new Date() } }
                            ]
                        },
                        attributes: ['id', 'venueId', 'eventDate', 'status', 'createdAt', 'updatedAt'],
                        order: [['updatedAt', 'DESC']]
                    }),
                    NightPartnerMatch.findAll({
                        where: { hostId: uId, status: { [Op.notIn]: ['CANCELLED'] } },
                        attributes: ['id', 'venueId', 'eventDate', 'status', 'createdAt', 'updatedAt'],
                        order: [['updatedAt', 'DESC']]
                    }),
                    NightPartnerMatch.findAll({
                        where: { partnerId: uId, status: { [Op.notIn]: ['CANCELLED'] } },
                        attributes: ['id', 'venueId', 'eventDate', 'status', 'createdAt', 'updatedAt'],
                        order: [['updatedAt', 'DESC']]
                    })
                ]);

                const eventMap = new Map<string, string>();
                for (const m of [...hostMatches, ...partnerMatches]) {
                    const dateStr = m.eventDate ? new Date(m.eventDate).toISOString().split('T')[0] : '';
                    const key = `${m.venueId}_${dateStr}`;
                    if (!eventMap.has(key)) {
                        eventMap.set(key, m.id);
                    }
                }
                for (const pr of partnerRequests) {
                    const dateStr = pr.eventDate ? new Date(pr.eventDate).toISOString().split('T')[0] : '';
                    const key = `${pr.venueId}_${dateStr}`;
                    if (!eventMap.has(key)) {
                        eventMap.set(key, pr.id);
                    }
                }
                for (const hr of hostRequests) {
                    const dateStr = hr.eventDate ? new Date(hr.eventDate).toISOString().split('T')[0] : '';
                    const key = `${hr.venueId}_${dateStr}`;
                    if (!eventMap.has(key)) {
                        eventMap.set(key, hr.id);
                    }
                }

                const nightIds = Array.from(eventMap.values());
                const nightCards = await Promise.all(
                    nightIds.map(async (nId) => {
                        try {
                            const enrichedCard = await NightPartnerService.enrichUpcomingNightNotificationCard(nId, uId);
                            if (enrichedCard) {
                                const lastActivityAt = enrichedCard.lastActivityAt || enrichedCard.updatedAt || enrichedCard.createdAt || new Date().toISOString();
                                const cardTime = new Date(lastActivityAt).getTime();
                                const isCleared = clearedAt > 0 && cardTime <= clearedAt;
                                const isRead = isCleared || activeReadNotificationIds.has(enrichedCard.id);
                                enrichedCard.createdAt = lastActivityAt;
                                enrichedCard.lastActivityAt = lastActivityAt;
                                enrichedCard.read = isRead;
                                enrichedCard.isRead = isRead;
                                return enrichedCard;
                            }
                        } catch (err) {
                            console.error(`Error enriching night card ${nId}:`, err);
                        }
                        return null;
                    })
                );
                return nightCards.filter(Boolean);
            } catch (err) {
                console.error('Error fetching upcoming night notifications:', err);
                return [];
            }
        })()
    ]);

    notifications.push(
        ...matchCardsResult,
        ...paymentCardsResult,
        ...smCardsResult,
        ...safetyCardsResult,
        ...bookingCardsResult,
        ...gpCardsResult,
        ...nightCardsResult
    );

    // Sort by actionable priority first, then by lastActivityAt / createdAt descending
    notifications.sort((a, b) => {
        const aReq = a.requiresAction ? 1 : 0;
        const bReq = b.requiresAction ? 1 : 0;
        if (aReq !== bReq) return bReq - aReq;
        const aTime = new Date(a.lastActivityAt || a.createdAt || 0).getTime();
        const bTime = new Date(b.lastActivityAt || b.createdAt || 0).getTime();
        return bTime - aTime;
    });

    // universal deduplication fallback for non-timeline cards
    const entityKeys = new Map<string, any>();
    const deduplicatedNotifications: any[] = [];

    // Prioritize timeline cards first so they win during deduplication
    const sortedForDedup = [...notifications].sort((a, b) => {
        const aIsTimeline = a.type?.endsWith('_timeline') || a.id?.includes('_timeline_') ? 1 : 0;
        const bIsTimeline = b.type?.endsWith('_timeline') || b.id?.includes('_timeline_') ? 1 : 0;
        return bIsTimeline - aIsTimeline;
    });

    for (const n of sortedForDedup) {
        const data = n.data || {};
        const titleLower = (n.title || '').toLowerCase();
        const bodyLower = (n.body || '').toLowerCase();
        const typeLower = (n.type || n.eventType || '').toLowerCase();
        const isSm = typeLower.startsWith('strangers_meet') || typeLower.includes('stranger_meet') || typeLower.includes('stranger') || n.entityType === 'strangers_meet' || n.entityType === 'StrangerMeet' || n.entityType === 'strangers_meet_request' || titleLower.includes('stranger meet') || bodyLower.includes('stranger meet');

        const strangerMeetId = data.strangersMeetId?.toString() || data.meetId?.toString() || data.planId?.toString() || (data.planDetails ? data.planDetails.id?.toString() : null) || (data.strangersMeet ? data.strangersMeet.id?.toString() : null) ||
            (n.metadata ? (n.metadata.strangersMeetId?.toString() || n.metadata.meetId?.toString() || n.metadata.planId?.toString()) : null) ||
            (n.entityType === 'strangers_meet' || n.entityType === 'StrangerMeet' ? n.entityId?.toString() : null) ||
            (n.id?.startsWith('strangers_meet_') ? n.id.replace(/^strangers_meet_(?:timeline_)?([^_]+).*/, '$1') : null) ||
            (isSm ? (data.requestId?.toString() || n.entityId?.toString() || (n.metadata ? n.metadata.requestId?.toString() : null)) : null);

        const isLp = typeLower.startsWith('large_party') || typeLower.includes('large_party') || titleLower.includes('large party') || bodyLower.includes('large party');
        const isGp = typeLower.startsWith('group_party') || n.entityType === 'group_party' || n.entityType === 'GroupParty' || titleLower.includes('group party') || bodyLower.includes('group party') || isLp;

        const groupPartyId = data.partyId?.toString() || data.groupPartyId?.toString() ||
            (n.entityType === 'group_party' || n.entityType === 'GroupParty' ? n.entityId?.toString() : null) ||
            (n.id?.startsWith('group_party_') ? n.id.replace(/^group_party_(?:timeline_)?([^_]+).*/, '$1') : null) ||
            (n.id?.startsWith('large_party_') ? n.id.replace(/^large_party_(?:timeline_)?([^_]+).*/, '$1') : null) ||
            (isGp ? (data.bookingId?.toString() || n.entityId?.toString() || (n.metadata ? n.metadata.bookingId?.toString() : null)) : null);

        const bookingId = data.bookingId?.toString() ||
            (n.metadata ? n.metadata.bookingId?.toString() : null) ||
            (n.entityType === 'booking' || n.entityType === 'Booking' ? n.entityId?.toString() : null) ||
            (n.id?.startsWith('solo_booking_') ? n.id.replace(/^solo_booking_([^_]+).*/, '$1') : null) ||
            (n.id?.startsWith('large_party_') ? n.id.replace(/^large_party_(?:timeline_)?([^_]+).*/, '$1') : null);

        const partyPlanId = data.partyPlanId?.toString() || data.planId?.toString() ||
            (n.entityType === 'party_plan' || n.entityType === 'party_plan_request' || n.entityType === 'PartyPlan' || n.entityType === 'PartyPlanRequest' ? n.entityId?.toString() : null) ||
            (n.id?.startsWith('party_plan_') ? n.id.replace(/^party_plan_(?:timeline_)?([^_]+).*/, '$1') : null) ||
            (n.metadata ? (n.metadata.partyPlanId || n.metadata.planId) : null);

        const isUn = typeLower.startsWith('upcoming_night') || typeLower.includes('night_partner') || typeLower.includes('partner_request') || n.entityType === 'night_partner' || n.entityType === 'NightPartnerRequest' || n.entityType === 'NightPartnerMatch' || titleLower.includes('night partner') || titleLower.includes('upcoming night');

        const upcomingNightId = data.nightId?.toString() || data.matchId?.toString() || data.requestId?.toString() ||
            (n.entityType === 'night_partner' || n.entityType === 'NightPartnerRequest' || n.entityType === 'NightPartnerMatch' ? n.entityId?.toString() : null) ||
            (n.id?.startsWith('upcoming_night_') ? n.id.replace(/^upcoming_night_(?:timeline_)?([^_]+).*/, '$1') : null) ||
            (n.metadata ? (n.metadata.nightId || n.metadata.matchId || n.metadata.requestId) : null) ||
            (isUn ? n.entityId?.toString() : null);

        let key: string | null = null;
        if (strangerMeetId) key = `sm_${strangerMeetId}`;
        else if (groupPartyId) key = `gp_${groupPartyId}`;
        else if (partyPlanId) key = `pp_${partyPlanId}`;
        else if (bookingId) key = `bk_${bookingId}`;
        else if (upcomingNightId) key = `un_${upcomingNightId}`;

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
                if (n.type === 'upcoming_night_timeline') {
                    const stage = n.data?.stage || n.data?.status || '';
                    return stage === 'INVITE_SENT' || stage === 'PENDING' || stage === 'WAITING_FOR_PAYMENT' || stage === 'PAYMENT_PENDING' || n.data?.cancellationStatus === 'REQUESTED';
                }
                if (type.startsWith('group_party_initiated') || type.startsWith('large_party_payment_link') || type.startsWith('large_party_approved')) {
                    return true;
                }
                if (type.includes('join_request') || type.includes('awaiting_payment') || type.includes('PARTNER_REQUEST') || type.includes('PAYMENT_PENDING')) {
                    return true;
                }
                return false;
            }
            
            if (filter === 'completed') {
                if (n.type === 'party_plan_timeline') {
                    return ['Completed', 'Cancelled', 'Expired'].includes(statusText);
                }
                if (n.type === 'upcoming_night_timeline') {
                    const status = (n.data?.status || '').toUpperCase();
                    return ['COMPLETED', 'CANCELLED', 'EXPIRED', 'DECLINED'].includes(status);
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

    // Clear old cleared notifications, but ALWAYS preserve active action-required tasks (e.g. Pay Deposit)
    const activeNotifs = filtered.filter(n => {
        const primaryAction = (n.data?.primaryAction || n.primaryAction || '').toString().toLowerCase();
        const hostStatus = (n.data?.hostPaymentStatus || '').toString().toLowerCase();
        const isActionRequired = primaryAction.includes('pay') || primaryAction.includes('accept') ||
            (hostStatus && hostStatus !== 'paid' && hostStatus !== 'completed');
        if (isActionRequired) return true;
        return new Date(n.createdAt).getTime() > clearedAt;
    });

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
router.get('/notifications', authenticate, async (req, res) => {
    try {
        const { userId, readNotificationIds, filter, search } = req.query;
        const uId = req.user!.id;
        if (userId && userId !== uId) {
            return res.status(403).json({ success: false, message: 'You cannot access another user\'s notifications.' });
        }

        const filterStr = (filter as string) || 'all';
        const searchStr = (search as string) || '';

        // This response is expensive to build (many enriched sub-loaders) and is
        // re-requested on every live-feed refresh. Cache it per user, keyed by
        // every input that can change the output, so repeated identical reads
        // are served from memory. Writes to the notifications table invalidate
        // this via model hooks, and the read-state routes below invalidate it
        // explicitly, so a cached entry can never outlive a change.
        const readIdsFingerprint = createHash('sha1')
            .update(typeof readNotificationIds === 'string' ? readNotificationIds : '')
            .digest('hex')
            .slice(0, 16);
        const cacheKey = `notif:${uId}:${filterStr}:${searchStr}:${readIdsFingerprint}`;

        const cachedResponse = apiCache.get<{ success: boolean; data: any[] }>(cacheKey);
        if (cachedResponse) {
            return res.json(cachedResponse);
        }

        const clientReadNotificationIds = new Set<string>(
            typeof readNotificationIds === 'string'
                ? readNotificationIds.split(',').filter(Boolean)
                : []
        );
        let notifications: any[] = [];
        try {
            notifications = await getUserNotifications(
                uId,
                filterStr,
                searchStr,
                clientReadNotificationIds,
                getReadNotificationIds(uId)
            );
        } catch (genErr) {
            console.error('Error loading enriched notifications, falling back to basic notifications:', genErr);
            const NotificationModel = (await import('../models/Notification')).default;
            const dbNotifs = await NotificationModel.findAll({
                where: { recipientUserId: uId },
                order: [['createdAt', 'DESC']],
                limit: 30,
            }).catch(() => []);
            notifications = dbNotifs.map(n => ({
                id: n.id,
                title: n.title,
                body: n.body,
                createdAt: n.createdAt ? n.createdAt.toISOString() : new Date().toISOString(),
                read: n.isRead,
                type: n.eventType,
                data: n.metadata,
                section: getDateSection(n.createdAt ? n.createdAt.toISOString() : new Date().toISOString())
            }));
        }

        const payload = { success: true, data: notifications };
        // Short TTL: long enough to collapse the burst of refreshes a single
        // socket event causes, short enough that nothing feels stale.
        apiCache.set(cacheKey, payload, 15);
        return res.json(payload);
    } catch (error: any) {
        console.error('Error fetching notifications endpoint:', error);
        return res.status(200).json({ success: true, data: [] });
    }
});

/**
 * PATCH /api/mobile/user/notifications/:id/read
 */
router.patch('/notifications/:id/read', authenticate, async (req, res) => {
    const { id } = req.params;
    const suppliedUserId = (req.query.userId as string) || (req.body?.userId as string);
    const userId = req.user!.id;
    if (suppliedUserId && suppliedUserId !== userId) {
        return res.status(403).json({ success: false, message: 'You cannot modify another user\'s notifications.' });
    }
    markNotificationRead(userId, id);
    // The read set lives in memory, so no model hook fires for it.
    apiCache.invalidatePrefix(`notif:${userId}:`);
    apiCache.invalidatePrefix(`badge:${userId}:`);

    try {
        const uuidRegex = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
        
        if (uuidRegex.test(id)) {
            const notification = await Notification.findByPk(id);
            if (notification) {
                if (notification.recipientUserId !== userId) {
                    return res.status(403).json({ success: false, message: 'You cannot modify another user\'s notifications.' });
                }
                notification.isRead = true;
                notification.readAt = new Date();
                await notification.save();
            }
        } else {
            // Extract UUID pattern from composite string ID like 'upcoming_night_timeline_<uuid>' or 'sm_<uuid>'
            const match = id.match(/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/);
            if (match) {
                const extractedId = match[0];
                // First try finding by PK using extracted UUID
                const notifByPk = await Notification.findByPk(extractedId);
                if (notifByPk) {
                    if (notifByPk.recipientUserId !== userId) {
                        return res.status(403).json({ success: false, message: 'You cannot modify another user\'s notifications.' });
                    }
                    notifByPk.isRead = true;
                    notifByPk.readAt = new Date();
                    await notifByPk.save();
                } else if (userId) {
                    // Update by entityId & recipientUserId
                    await Notification.update(
                        { isRead: true, readAt: new Date() },
                        { where: { recipientUserId: userId, entityId: extractedId } }
                    );
                }
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
router.post('/notifications/clear-all', authenticate, NotificationActionController.clearAll);

/**
 * POST /api/mobile/user/notifications/:id/action
 */
router.post('/notifications/:id/action', authenticate, NotificationActionController.handleAction);

/**
 * POST /api/mobile/user/notifications/mark-all-read
 */
router.post('/notifications/mark-all-read', authenticate, NotificationActionController.markAllAsRead);

/**
 * GET /api/mobile/user/notifications/unread-count
 */
router.get('/notifications/unread-count', authenticate, NotificationActionController.getUnreadCount);

/**
 * PATCH /api/mobile/user/requests/:id/read
 */
router.patch('/requests/:id/read', authenticate, async (req, res) => {
    const { id } = req.params;
    const suppliedUserId = (req.query.userId as string) || (req.body?.userId as string);
    const userId = req.user!.id;
    if (suppliedUserId && suppliedUserId !== userId) {
        return res.status(403).json({ success: false, message: 'You cannot modify another user\'s request read state.' });
    }
    markRequestRead(userId, id);
    apiCache.invalidatePrefix(`notif:${userId}:`);
    apiCache.invalidatePrefix(`badge:${userId}:`);
    return res.json({ success: true, message: 'Request marked as read' });
});

/**
 * GET /api/mobile/user/badge-counts
 */
router.get('/badge-counts', authenticate, async (req, res) => {
    try {
        const { userId, readRequestIds: clientReadReqIds, readNotificationIds: clientReadNotifIds } = req.query;
        const uId = req.user!.id;
        if (userId && userId !== uId) {
            return res.status(403).json({ success: false, message: 'You cannot access another user\'s badge counts.' });
        }

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

        // Badge counts are polled every 30s by the dashboard and recomputed from
        // eight queries each time. Cache briefly, keyed by the same inputs the
        // response depends on. The TTL is well inside the existing 30s poll
        // interval, so this never makes a badge staler than it already was, and
        // the notification write hooks drop this key the moment anything changes.
        const badgeFingerprint = createHash('sha1')
            .update(`${typeof clientReadReqIds === 'string' ? clientReadReqIds : ''}|${typeof clientReadNotifIds === 'string' ? clientReadNotifIds : ''}`)
            .digest('hex')
            .slice(0, 16);
        const badgeCacheKey = `badge:${uId}:${badgeFingerprint}`;
        const cachedBadges = apiCache.get<any>(badgeCacheKey);
        if (cachedBadges) {
            return res.json(cachedBadges);
        }

        const isUUID = (str: string) => /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(str);
        const validReadRequestUUIDs = Array.from(activeReadRequestIds).filter(isUUID);

        const user = await User.findByPk(uId, { attributes: ['clearedNotificationsAt'] });
        const clearedAtTime = user?.clearedNotificationsAt ? new Date(user.clearedNotificationsAt).getTime() : 0;

        const partyReqWhere: any = {
            requesterId: uId,
            status: { [Op.in]: ['accepted', 'payment_pending'] },
            joinerPaymentStatus: 'unpaid',
        };
        if (validReadRequestUUIDs.length > 0) {
            partyReqWhere.id = { [Op.notIn]: validReadRequestUUIDs };
        }
        if (user?.clearedNotificationsAt) {
            partyReqWhere.createdAt = { [Op.gt]: user.clearedNotificationsAt };
        }

        const planReqWhere: any = {
            requesterId: uId,
            status: 'accepted',
            paymentStatus: 'pending',
        };
        if (validReadRequestUUIDs.length > 0) {
            planReqWhere.id = { [Op.notIn]: validReadRequestUUIDs };
        }
        if (user?.clearedNotificationsAt) {
            planReqWhere.createdAt = { [Op.gt]: user.clearedNotificationsAt };
        }

        const validReadNotifUUIDs = Array.from(activeReadNotificationIds).filter(isUUID);
        const notifWhere: any = {
            recipientUserId: uId,
            isRead: false,
        };
        if (validReadNotifUUIDs.length > 0) {
            notifWhere.id = { [Op.notIn]: validReadNotifUUIDs };
        }
        if (user?.clearedNotificationsAt) {
            notifWhere.createdAt = { [Op.gt]: user.clearedNotificationsAt };
        }

        // Execute all independent badge count queries concurrently in parallel
        const [
            unreadNotificationsCount,
            unreadPartyRequestsCount,
            unreadPlanRequestsCount,
            userConversations,
            incomingPartyReqs,
            incomingStrangerJoiners,
            incomingTableReqs,
        ] = await Promise.all([
            Notification.count({ where: notifWhere }),
            PartyPlanRequest.count({ where: partyReqWhere }),
            PlanJoinRequest.count({ where: planReqWhere }),
            Conversation.findAll({
                where: {
                    [Op.or]: [
                        { participantOne: uId },
                        { participantTwo: uId }
                    ],
                    status: { [Op.ne]: 'blocked' }
                },
                attributes: ['id', 'participantOne', 'participantTwo', 'unreadOne', 'unreadTwo', 'deletedByOne', 'deletedByTwo']
            }),
            PartyPlanRequest.findAll({
                where: { status: 'pending' },
                include: [{
                    model: PartyPlan,
                    as: 'plan',
                    where: { userId: uId },
                    attributes: ['id', 'selectedUsers']
                }],
                attributes: ['id', 'requesterId', 'createdAt']
            }).then(reqs => reqs.filter(r => {
                const planUsers = (r as any).plan?.selectedUsers;
                const isPrivateInvite = Array.isArray(planUsers) && planUsers.includes(r.requesterId);
                return !isPrivateInvite;
            })).catch(() => []),
            StrangersMeetJoiner.findAll({
                where: { status: 'pending' },
                include: [{
                    model: StrangersMeetRequest,
                    as: 'strangersMeetRequest',
                    where: { userId: uId },
                    attributes: ['id']
                }],
                attributes: ['id', 'createdAt']
            }).catch(() => []),
            PlanJoinRequest.findAll({
                where: { status: 'pending' },
                include: [{
                    model: Plan,
                    as: 'plan',
                    where: { userId: uId },
                    attributes: ['id']
                }],
                attributes: ['id', 'createdAt']
            }).catch(() => []),
        ]);

        let chatCount = 0;
        for (const conv of userConversations) {
            const isP1 = (conv.participantOne || '').toLowerCase() === uId.toLowerCase();
            const isP2 = (conv.participantTwo || '').toLowerCase() === uId.toLowerCase();
            if (isP1 && (conv as any).deletedByOne) continue;
            if (isP2 && (conv as any).deletedByTwo) continue;
            const unread = isP1 ? ((conv as any).unreadOne || 0) : ((conv as any).unreadTwo || 0);
            chatCount += Number(unread || 0);
        }

        const unreadIncomingTableRequestsCount = incomingTableReqs.filter(r => !activeReadRequestIds.has(r.id) && (!clearedAtTime || new Date((r as any).createdAt || 0).getTime() > clearedAtTime)).length;
        const unreadIncomingPartyRequestsCount = incomingPartyReqs.filter(r => !activeReadRequestIds.has(r.id) && (!clearedAtTime || new Date((r as any).createdAt || 0).getTime() > clearedAtTime)).length;
        const unreadIncomingStrangerRequestsCount = incomingStrangerJoiners.filter(r => !activeReadRequestIds.has(r.id) && (!clearedAtTime || new Date((r as any).createdAt || 0).getTime() > clearedAtTime)).length;

        const liveFeedCount = unreadNotificationsCount + 
                              unreadIncomingTableRequestsCount + 
                              unreadIncomingPartyRequestsCount + 
                              unreadIncomingStrangerRequestsCount +
                              unreadPartyRequestsCount + 
                              unreadPlanRequestsCount;

        const badgePayload = {
            success: true,
            data: {
                liveFeedCount,
                chatCount,
                totalCount: liveFeedCount + chatCount
            }
        };
        // 10s is a third of the dashboard's own 30s poll, so a badge can never
        // be staler than it already was; writes invalidate this key immediately.
        apiCache.set(badgeCacheKey, badgePayload, 10);
        return res.json(badgePayload);
    } catch (error: any) {
        console.error('Error fetching badge counts:', error);
        return res.status(500).json({ success: false, message: 'Failed to fetch badge counts' });
    }
});
router.post('/swipe', authenticate, mobileUserController.swipeUser);
router.post('/unlike', authenticate, mobileUserController.unlikeUser);

/**
 * GET /api/mobile/user/likes-matches
 * Fetch all likes/matches for a user
 */
router.get('/likes-matches', authenticate, mobileUserController.getMyLikesAndMatches);
router.get('/who-liked-summary', authenticate, mobileUserController.getWhoLikedSummary);
router.get('/who-liked-me', authenticate, mobileUserController.getPeopleWhoLikedMe);

/**
 * GET /api/mobile/user/swipe-status
 * Check if current user already liked/superliked a target today, and get plan limits.
 * Query: userId, targetUserId
 */
router.get('/swipe-status', authenticate, mobileUserController.getSwipeStatus);

/**
 * POST /api/mobile/user/backtrack
 * Backtrack the last swipe action on a target user, subject to subscription limit.
 */
router.post('/backtrack', authenticate, mobileUserController.backtrackSwipe);

// ── Chat Subscription Routes ──────────────────────────────────────────────────
import * as chatSubCtrl from '../controllers/chatSubscriptionController';

/** GET /api/mobile/chat/session-status/:conversationId */
router.get('/chat/session-status/:conversationId', authenticate, chatSubCtrl.getSessionStatus);

/** POST /api/mobile/chat/init-free */
router.post('/chat/init-free', authenticate, chatSubCtrl.initFreeChat);

/** POST /api/mobile/chat/extend */
router.post('/chat/extend', authenticate, chatSubCtrl.extendChat);

/** POST /api/mobile/chat/request-extension */
router.post('/chat/request-extension', authenticate, chatSubCtrl.requestExtension);

/** POST /api/mobile/chat/accept-extension-request */
router.post('/chat/accept-extension-request', authenticate, chatSubCtrl.acceptExtensionRequest);

/**
 * POST /api/mobile/user/safety-check
 * Submits safety check report
 */
router.post('/safety-check', authenticate, async (req, res) => {
    try {
        const { partnerId, feltSafe, prebuiltAnswers, opinion } = req.body;
        const userId = req.user!.id;
        if (!partnerId || feltSafe === undefined) {
            return res.status(400).json({ success: false, message: 'partnerId and feltSafe are required.' });
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

router.post('/safety-checks/respond', authenticate, (req, res) => {
    const { respondToSafetyCheck } = require('../controllers/mobileSafetyCheckController');
    return respondToSafetyCheck(req, res);
});
router.post('/safety-checks/:checkId/respond', authenticate, (req, res) => {
    const { respondToSafetyCheck } = require('../controllers/mobileSafetyCheckController');
    return respondToSafetyCheck(req, res);
});
router.get('/safety-checks/pending', authenticate, (req, res) => {
    const { getPendingSafetyCheck } = require('../controllers/mobileSafetyCheckController');
    return getPendingSafetyCheck(req, res);
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
        authenticate,
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
router.get('/profile-summary', authenticate, async (req, res) => {
    try {
        const userId = req.user!.id;

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

router.get('/reliability-summary', optionalAuth, reliabilityCtrl.getReliabilitySummary);
router.get('/reliability-history', authenticate, reliabilityCtrl.getReliabilityHistory);

export default router;
