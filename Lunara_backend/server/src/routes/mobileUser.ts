// Trigger azure deployment 2
import { Router } from 'express';
import { body, param } from 'express-validator';
import { validate } from '../middleware/validate';
import { uploadTempPhotos } from '../middleware/upload';
import mobileUserController from '../controllers/mobileUserController';
import { User, UserMatch, Payment, PartyPlanRequest, PlanJoinRequest, Conversation, Message, Plan, PartyPlan, Venue, StrangersMeetRequest, StrangersMeetJoiner, SafetyCheck, Booking, GroupParty } from '../models';
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

async function getUserNotifications(uId: string, clientReadNotificationIds?: Set<string>, serverReadNotificationIds?: Set<string>): Promise<any[]> {
    const user = await User.findByPk(uId, { attributes: ['clearedNotificationsAt'] });
    const clearedAt = user?.clearedNotificationsAt ? new Date(user.clearedNotificationsAt).getTime() : 0;
    // Merge client-side read IDs with server-side per-user read IDs (never use the global set)
    const perUserServerIds = serverReadNotificationIds || getReadNotificationIds(uId);
    const activeReadNotificationIds = new Set<string>([
        ...(clientReadNotificationIds || []),
        ...perUserServerIds,
    ]);

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

    // Fetch PartyPlanRequests where current user is host
    const myHostedPlans = await PartyPlan.findAll({
        where: { userId: uId },
        attributes: ['id', 'venueId', 'visibility'],
        include: [{ model: Venue, as: 'venue', attributes: ['name'] }]
    });

    const hostPartyRequests = myHostedPlans.length > 0
        ? await PartyPlanRequest.findAll({
            where: {
                planId: { [Op.in]: myHostedPlans.map(p => p.id) },
                status: { [Op.in]: ['accepted', 'payment_pending'] }
            },
            include: [
                {
                    model: User,
                    as: 'requester',
                    attributes: ['id', 'firstName', 'lastName', 'profileImageUrl']
                }
            ],
            order: [['createdAt', 'DESC']],
            limit: 20
        })
        : [];

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

    // 5. Fetch StrangersMeetRequests created by uId (Host)
    const hostMeets = await StrangersMeetRequest.findAll({
        where: { userId: uId },
        include: [{ model: Venue, as: 'venue', attributes: ['name'] }],
        order: [['createdAt', 'DESC']],
        limit: 20
    });

    // 6. Fetch StrangersMeetJoiners where user is participant
    const myJoinRequests = await StrangersMeetJoiner.findAll({
        where: { userId: uId },
        include: [
            {
                model: StrangersMeetRequest,
                as: 'strangersMeetRequest',
                include: [{ model: Venue, as: 'venue', attributes: ['name'] }]
            }
        ],
        order: [['createdAt', 'DESC']],
        limit: 20
    });

    // 7. Fetch StrangersMeetJoiners for host's meets
    const hostMeetIds = hostMeets.map(m => m.id);
    const incomingJoinRequests = hostMeetIds.length > 0
        ? await StrangersMeetJoiner.findAll({
            where: {
                strangersMeetRequestId: { [Op.in]: hostMeetIds }
            },
            include: [
                {
                    model: User,
                    as: 'user',
                    attributes: ['id', 'firstName', 'lastName', 'profileImageUrl']
                },
                {
                    model: StrangersMeetRequest,
                    as: 'strangersMeetRequest'
                }
            ],
            order: [['createdAt', 'DESC']],
            limit: 20
        })
        : [];

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
        const isRead = match.status === 'connected' || match.status === 'declined' || activeReadNotificationIds.has(notificationId);

        notifications.push({
            id: notificationId,
            title,
            body,
            createdAt: match.createdAt ? match.createdAt.toISOString() : new Date().toISOString(),
            read: isRead,
            sender: {
                id: sender.id,
                firstName: sender.firstName,
                lastName: sender.lastName,
                profileImageUrl: sender.profileImageUrl,
            }
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
            read: activeReadNotificationIds.has(notificationId),
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
        let type = 'party_plan_request';

        if (pr.status === 'accepted' || pr.status === 'payment_pending') {
            const isInvite = plan && plan.selectedUsers && plan.selectedUsers.includes(uId);
            const isSelfPay = plan && plan.paymentType === 'self_pay';
            const hostPaid = plan && plan.hostPaymentStatus === 'paid';

            if (isInvite) {
                title = 'Private Party Plan Invite';
                if (isSelfPay) {
                    if (hostPaid) {
                        body = `Your private invite to Party Plan at ${venueName} is confirmed! (Paid by host) 🎉`;
                    } else {
                        body = `You have been privately invited to a Party Plan at ${venueName}. Accept to join.`;
                    }
                } else {
                    body = `You have been privately invited to a Party Plan at ${venueName}. Pay to confirm.`;
                }
            } else {
                title = 'Plan Request Accepted';
                if (isSelfPay) {
                    if (hostPaid) {
                        body = `Your request to join Party Plan at ${venueName} is confirmed! (Paid by host) 🎉`;
                    } else {
                        body = `Your request to join Party Plan at ${venueName} was accepted. Waiting for host payment to confirm. ⏳`;
                    }
                } else {
                    body = `Your request to join Party Plan at ${venueName} was accepted. Pay to confirm.`;
                }
            }
        } else if (pr.status === 'rejected') {
            const isInvite = plan && plan.selectedUsers && plan.selectedUsers.includes(uId);
            if (plan && plan.status === 'inactive') {
                title = 'Plan Unavailable';
                body = `The Party Plan at ${venueName} has been confirmed with another user. Feel free to find another plan!`;
                type = 'plan_unavailable';
            } else {
                if (isInvite) {
                    body = `The Party Plan at ${venueName} is no longer available.`;
                } else {
                    body = `Your request to join Party Plan at ${venueName} was declined.`;
                }
                type = 'party_plan_request';
            }
            isRead = true;
        } else if (pr.status === 'pending' && plan && (plan.visibility === 'private' || plan.visibility === 'both') && plan.selectedUsers?.includes(uId)) {
            title = 'Private Party Plan Invite';
            const isSelfPay = plan.paymentType === 'self_pay';
            if (isSelfPay) {
                body = `You have been privately invited to a Party Plan at ${venueName}. Accept to join.`;
            } else {
                body = `You have been privately invited to a Party Plan at ${venueName}. Accept and pay to join.`;
            }
            isRead = false;
        } else {
            continue;
        }

        notifications.push({
            id: notificationId,
            title,
            body,
            createdAt: pr.updatedAt ? pr.updatedAt.toISOString() : (pr.createdAt ? pr.createdAt.toISOString() : new Date().toISOString()),
            read: isRead || activeReadNotificationIds.has(notificationId),
            type,
        });
    }

    // Add Host PartyPlanRequests (Incoming accepted / paid)
    for (const pr of hostPartyRequests) {
        const plan = myHostedPlans.find(p => p.id === pr.planId);
        const venueName = (plan as any)?.venue?.name || 'Club';
        const joiner = (pr as any).requester;
        if (!joiner) continue;
        const joinerName = `${joiner.firstName} ${joiner.lastName}`;
        const notificationId = `ppr_host_${pr.id}`;
        
        let title = '';
        let body = '';
        const isInvite = plan && plan.selectedUsers && plan.selectedUsers.includes(joiner.id);

        if (isInvite) {
            title = 'Invite Accepted';
            if (pr.joinerPaymentStatus === 'paid') {
                body = `${joinerName} accepted and confirmed your private invite to the Party Plan at ${venueName}.`;
            } else {
                body = `${joinerName} accepted your private invite to the Party Plan at ${venueName}.`;
            }
        } else {
            title = 'Participant Joined';
            if (pr.joinerPaymentStatus === 'paid') {
                body = `${joinerName} completed their payment and joined your Party Plan at ${venueName}.`;
            } else if (pr.status === 'accepted') {
                body = `${joinerName} joined your Party Plan at ${venueName}.`;
            } else {
                continue;
            }
        }

        notifications.push({
            id: notificationId,
            title,
            body,
            createdAt: pr.updatedAt ? pr.updatedAt.toISOString() : (pr.createdAt ? pr.createdAt.toISOString() : new Date().toISOString()),
            read: activeReadNotificationIds.has(notificationId),
            sender: {
                id: joiner.id,
                firstName: joiner.firstName,
                lastName: joiner.lastName,
                profileImageUrl: joiner.profileImageUrl,
            }
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
            read: isRead || activeReadNotificationIds.has(notificationId),
        });
    }

    // Add Strangers Meet Host Requests Status Update Notifications
    for (const meet of hostMeets) {
        const m = meet as any;
        const venueName = m.venue?.name || 'Venue';
        if (m.status === 'approved') {
            const notificationId = `sm_host_approved_${m.id}`;
            const isPaid = m.paymentStatus === 'paid';
            notifications.push({
                id: notificationId,
                title: 'Stranger Meet Approved',
                body: `Your meet request "${m.subject}" at ${venueName} has been approved. ${isPaid ? 'Deposit paid.' : 'Please pay the deposit to make it live.'}`,
                createdAt: m.updatedAt ? m.updatedAt.toISOString() : (m.createdAt ? m.createdAt.toISOString() : new Date().toISOString()),
                read: activeReadNotificationIds.has(notificationId),
                data: {
                    type: 'strangers_meet_approved',
                    requestId: m.id,
                }
            });
        } else if (m.status === 'rejected') {
            const notificationId = `sm_host_rejected_${m.id}`;
            notifications.push({
                id: notificationId,
                title: 'Stranger Meet Rejected',
                body: `Your meet request "${m.subject}" at ${venueName} was rejected by admin. Reason: ${m.adminNotes || 'N/A'}`,
                createdAt: m.updatedAt ? m.updatedAt.toISOString() : (m.createdAt ? m.createdAt.toISOString() : new Date().toISOString()),
                read: activeReadNotificationIds.has(notificationId),
                data: {
                    type: 'strangers_meet_rejected',
                    requestId: m.id,
                }
            });
        } else if (m.status === 'pending') {
            const notificationId = `sm_host_pending_${m.id}`;
            notifications.push({
                id: notificationId,
                title: 'Request Submitted',
                body: `Your Stranger Meet request "${m.subject}" has been submitted for admin approval.`,
                createdAt: m.createdAt ? m.createdAt.toISOString() : new Date().toISOString(),
                read: activeReadNotificationIds.has(notificationId),
                data: {
                    type: 'strangers_meet_request_submitted',
                    requestId: m.id,
                }
            });
        }
    }

    // Add Strangers Meet Participant Join Request Notifications
    for (const jr of myJoinRequests) {
        const j = jr as any;
        const meet = j.strangersMeetRequest;
        if (!meet) continue;
        const venueName = meet.venue?.name || 'Venue';
        const eventDate = meet.eventDateTime ? new Date(meet.eventDateTime).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : null;
        const notificationId = `sm_join_${j.id}`;
        
        let title = '';
        let body = '';
        let showNotification = false;
        let type = '';

        if (j.status === 'accepted' && j.paymentStatus !== 'paid') {
            title = 'Request Accepted';
            body = `Your request to join "${meet.subject}" at ${venueName}${eventDate ? ' on ' + eventDate : ''} was accepted! Complete the payment to secure your spot.`;
            showNotification = true;
            type = 'strangers_meet_request_accepted';
        } else if (j.status === 'rejected') {
            title = 'Request Declined';
            body = `Your request to join "${meet.subject}" at ${venueName}${eventDate ? ' on ' + eventDate : ''} was declined by the host.`;
            showNotification = true;
            type = 'strangers_meet_request_rejected';
        } else if (j.status === 'paid' || j.paymentStatus === 'paid') {
            title = 'Booking Confirmed ✓';
            body = `Your payment for "${meet.subject}" at ${venueName}${eventDate ? ' on ' + eventDate : ''} was successful. Spot confirmed!`;
            showNotification = true;
            type = 'strangers_meet_payment_success';
        }

        if (showNotification) {
            notifications.push({
                id: notificationId,
                title,
                body,
                createdAt: j.updatedAt ? j.updatedAt.toISOString() : (j.createdAt ? j.createdAt.toISOString() : new Date().toISOString()),
                read: activeReadNotificationIds.has(notificationId),
                eventDetails: {
                    subject: meet.subject,
                    tagline: meet.tagline || null,
                    eventDate: eventDate,
                    venue: venueName,
                    chargesPerHead: meet.chargesPerHead,
                    totalSeats: meet.numberOfPersons,
                },
                data: {
                    type,
                    requestId: meet.id,
                }
            });
        }
    }

    // Add Strangers Meet Host Incoming Join Request Notifications
    // Group joiners by meet so multiple requests are merged Instagram-style
    const joinRequestsByMeet = new Map<string, any[]>();
    for (const ijr of incomingJoinRequests) {
        const ij = ijr as any;
        const meet = ij.strangersMeetRequest;
        if (!meet) continue;
        if (!joinRequestsByMeet.has(meet.id)) joinRequestsByMeet.set(meet.id, []);
        joinRequestsByMeet.get(meet.id)!.push(ij);
    }

    for (const [meetId, joiners] of joinRequestsByMeet) {
        const firstJoiner = joiners[0];
        const meet = firstJoiner.strangersMeetRequest;
        const venueName = meet?.venue?.name || 'Venue';
        const eventDate = meet?.eventDateTime ? new Date(meet.eventDateTime).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : null;

        // Pending joiners (need host action)
        const pendingJoiners = joiners.filter((ij: any) => ij.status === 'pending');
        if (pendingJoiners.length > 0) {
            const notificationId = `sm_incoming_grp_${meetId}`;
            const firstUser = pendingJoiners[0].user;
            const firstName = firstUser?.firstName || 'Someone';
            const othersCount = pendingJoiners.length - 1;
            const bodyText = othersCount > 0
                ? `${firstName} and ${othersCount} other${othersCount > 1 ? 's' : ''} want to join your "${meet.subject}" meet${eventDate ? ' on ' + eventDate : ''}.`
                : `${firstName} ${pendingJoiners[0].user?.lastName || ''} requested to join your "${meet.subject}" meet${eventDate ? ' on ' + eventDate : ''}.`;

            const isRead = pendingJoiners.every((ij: any) => activeReadNotificationIds.has(`sm_incoming_${ij.id}`));
            notifications.push({
                id: notificationId,
                title: `New Join Request${pendingJoiners.length > 1 ? 's' : ''}`,
                body: bodyText,
                createdAt: pendingJoiners[0].updatedAt?.toISOString() || pendingJoiners[0].createdAt?.toISOString() || new Date().toISOString(),
                read: isRead,
                grouped: true,
                groupCount: pendingJoiners.length,
                eventDetails: {
                    subject: meet.subject,
                    tagline: meet?.tagline || null,
                    eventDate: eventDate,
                    venue: venueName,
                    totalSeats: meet.numberOfPersons,
                    chargesPerHead: meet.chargesPerHead,
                },
                sender: firstUser ? {
                    id: firstUser.id,
                    firstName: firstUser.firstName,
                    lastName: firstUser.lastName,
                    profileImageUrl: firstUser.profileImageUrl,
                } : null,
                data: {
                    type: 'strangers_meet_join_request',
                    requestId: meetId,
                    joinerIds: pendingJoiners.map((ij: any) => ij.id),
                }
            });
        }

        // Accepted joiners who haven't paid yet (not vanishing after host accepts)
        const acceptedUnpaidJoiners = joiners.filter((ij: any) => ij.status === 'accepted' && ij.paymentStatus !== 'paid');
        if (acceptedUnpaidJoiners.length > 0) {
            const notificationId = `sm_incoming_accepted_${meetId}`;
            const firstUser = acceptedUnpaidJoiners[0].user;
            const othersCount = acceptedUnpaidJoiners.length - 1;
            const bodyText = othersCount > 0
                ? `${firstUser?.firstName || 'Someone'} and ${othersCount} other${othersCount > 1 ? 's' : ''} accepted, awaiting payment for "${meet.subject}"${eventDate ? ' on ' + eventDate : ''}.`
                : `${firstUser?.firstName || 'Someone'} ${firstUser?.lastName || ''} was accepted. Awaiting payment for "${meet.subject}"${eventDate ? ' on ' + eventDate : ''}.`;
            const isRead = acceptedUnpaidJoiners.every((ij: any) => activeReadNotificationIds.has(`sm_incoming_${ij.id}`));
            notifications.push({
                id: notificationId,
                title: 'Awaiting Payment',
                body: bodyText,
                createdAt: acceptedUnpaidJoiners[0].updatedAt?.toISOString() || new Date().toISOString(),
                read: isRead,
                grouped: true,
                groupCount: acceptedUnpaidJoiners.length,
                eventDetails: {
                    subject: meet.subject,
                    eventDate: eventDate,
                    venue: venueName,
                },
                sender: firstUser ? {
                    id: firstUser.id,
                    firstName: firstUser.firstName,
                    lastName: firstUser.lastName,
                    profileImageUrl: firstUser.profileImageUrl,
                } : null,
                data: {
                    type: 'strangers_meet_awaiting_payment',
                    requestId: meetId,
                }
            });
        }

        // Paid joiners (confirmation)
        const paidJoiners = joiners.filter((ij: any) => ij.status === 'paid' || ij.paymentStatus === 'paid');
        if (paidJoiners.length > 0) {
            const notificationId = `sm_incoming_paid_${meetId}`;
            const firstUser = paidJoiners[0].user;
            const othersCount = paidJoiners.length - 1;
            const bodyText = othersCount > 0
                ? `${firstUser?.firstName || 'Someone'} and ${othersCount} other${othersCount > 1 ? 's' : ''} paid and joined your "${meet.subject}" meet${eventDate ? ' on ' + eventDate : ''}.`
                : `${firstUser?.firstName || 'Someone'} ${firstUser?.lastName || ''} paid and joined your "${meet.subject}" meet${eventDate ? ' on ' + eventDate : ''}.`;
            const isRead = paidJoiners.every((ij: any) => activeReadNotificationIds.has(`sm_incoming_${ij.id}`));
            notifications.push({
                id: notificationId,
                title: 'Participant Joined',
                body: bodyText,
                createdAt: paidJoiners[0].updatedAt?.toISOString() || new Date().toISOString(),
                read: isRead,
                grouped: true,
                groupCount: paidJoiners.length,
                eventDetails: {
                    subject: meet.subject,
                    eventDate: eventDate,
                    venue: venueName,
                },
                sender: firstUser ? {
                    id: firstUser.id,
                    firstName: firstUser.firstName,
                    lastName: firstUser.lastName,
                    profileImageUrl: firstUser.profileImageUrl,
                } : null,
                data: {
                    type: 'strangers_meet_participant_joined',
                    requestId: meetId,
                }
            });
        }
    }

    // NOTE: Profile visit notifications are sent via real-time socket events (notification_created)
    // and stored per-user. Simulated visits have been removed to prevent cross-user notification leakage.
    // Fetch safety check feedbacks for the user
    try {
        const safetyFeedbacks = await SafetyCheck.findAll({
            where: {
                userId: uId,
                adminFeedback: { [Op.ne]: null as any }
            },
            include: [
                {
                    model: User,
                    as: 'partner',
                    attributes: ['firstName', 'lastName', 'profileImageUrl']
                }
            ],
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
                sender: partner ? {
                    id: sf.partnerId,
                    firstName: partner.firstName,
                    lastName: partner.lastName,
                    profileImageUrl: partner.profileImageUrl,
                } : null,
                data: {
                    type: 'safety_check_feedback',
                    safetyCheckId: sf.id,
                }
            });
        }
    } catch (err) {
        console.error('Error fetching safety check feedbacks for notifications:', err);
    }

    // Fetch Booking records (goingMode = party_request)
    try {
        const largePartyBookings = await Booking.findAll({
            where: { userId: uId, goingMode: 'party_request' },
            include: [{ model: Venue, as: 'venue', attributes: ['name'] }],
            order: [['createdAt', 'DESC']],
            limit: 20
        });

        for (const booking of largePartyBookings) {
            const venueName = (booking as any).venue?.name || 'Venue';
            const notificationId = `large_party_${booking.id}_${booking.adminApprovalStatus}`;
            
            let title = '';
            let body = '';
            let showNotification = false;
            let type = '';

            if (booking.adminApprovalStatus === 'pending') {
                title = 'Large Party Request Submitted ⏳';
                body = `Your party request of ${booking.numberOfGuests} guests at ${venueName} is pending admin approval.`;
                showNotification = true;
                type = 'large_party_pending';
            } else if (booking.adminApprovalStatus === 'approved') {
                title = 'Large Party Request Approved! 🎉';
                body = `Your party request at ${venueName} has been approved! Complete payment to confirm.`;
                showNotification = true;
                type = 'large_party_approved';
            } else if (booking.adminApprovalStatus === 'rejected') {
                title = 'Large Party Request Rejected ❌';
                body = `Your party request at ${venueName} was rejected by admin.`;
                showNotification = true;
                type = 'large_party_rejected';
            } else if (booking.adminApprovalStatus === 'payment_sent') {
                title = 'Large Party Payment Link Received 💳';
                body = `Admin sent a payment link of ₹${booking.adminPaymentAmount} for your party at ${venueName}. Complete payment.`;
                showNotification = true;
                type = 'large_party_payment_link';
            } else if (booking.adminApprovalStatus === 'payment_done') {
                title = 'Large Party Confirmed! 🎉';
                body = `Your party of ${booking.numberOfGuests} guests at ${venueName} is fully confirmed. Enjoy your night!`;
                showNotification = true;
                type = 'large_party_confirmed';
            }

            if (showNotification) {
                notifications.push({
                    id: notificationId,
                    title,
                    body,
                    createdAt: booking.updatedAt ? booking.updatedAt.toISOString() : (booking.createdAt ? booking.createdAt.toISOString() : new Date().toISOString()),
                    read: activeReadNotificationIds.has(notificationId),
                    data: {
                        type,
                        bookingId: booking.id,
                    }
                });
            }
        }
    } catch (bookingErr) {
        console.error('Error fetching large party booking notifications:', bookingErr);
    }

    // Fetch GroupParty records (<= 20 guests)
    try {
        const groupParties = await GroupParty.findAll({
            where: { userId: uId },
            include: [{ model: Venue, as: 'venue', attributes: ['name'] }],
            order: [['createdAt', 'DESC']],
            limit: 20
        });

        for (const gp of groupParties) {
            const venueName = (gp as any).venue?.name || 'Venue';
            const notificationId = `group_party_${gp.id}_${gp.status}`;

            let title = '';
            let body = '';
            let showNotification = false;
            let type = '';

            if (gp.status === 'pending') {
                title = 'Group Party Initiated 💳';
                body = `Please complete the payment for your group party at ${venueName} to confirm.`;
                showNotification = true;
                type = 'group_party_initiated';
            } else if (gp.status === 'approved') {
                title = 'Group Party Approved! 🎉';
                body = `Your group party request at ${venueName} has been approved! Complete payment to confirm.`;
                showNotification = true;
                type = 'group_party_approved';
            } else if (gp.status === 'rejected') {
                title = 'Group Party Rejected ❌';
                body = `Your group party request at ${venueName} was rejected by the admin.`;
                showNotification = true;
                type = 'group_party_rejected';
            } else if (gp.status === 'confirmed') {
                title = 'Group Party Confirmed! 🎉';
                body = `Your group party of ${gp.numberOfFriends} friends at ${venueName} is confirmed!`;
                showNotification = true;
                type = 'group_party_confirmed';
            } else if (gp.status === 'cancelled') {
                title = 'Group Party Cancelled ❌';
                body = `Your group party booking at ${venueName} was cancelled.`;
                showNotification = true;
                type = 'group_party_cancelled';
            }

            if (showNotification) {
                notifications.push({
                    id: notificationId,
                    title,
                    body,
                    createdAt: gp.updatedAt ? gp.updatedAt.toISOString() : (gp.createdAt ? gp.createdAt.toISOString() : new Date().toISOString()),
                    read: activeReadNotificationIds.has(notificationId),
                    data: {
                        type,
                        partyId: gp.id,
                    }
                });
            }
        }
    } catch (gpErr) {
        console.error('Error fetching group party notifications:', gpErr);
    }

    notifications.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
    return notifications.filter(n => new Date(n.createdAt).getTime() > clearedAt);
}

/**
 * GET /api/mobile/user/notifications
 * Returns a list of notifications for the user
 */
router.get('/notifications', async (req, res) => {
    try {
        const { userId, readNotificationIds } = req.query;
        if (!userId) return res.status(400).json({ success: false, message: 'userId required' });

        const uId = userId as string;
        const clientReadNotificationIds = new Set<string>(
            typeof readNotificationIds === 'string'
                ? readNotificationIds.split(',').filter(Boolean)
                : []
        );
        // Pass server-side per-user read IDs so they are merged correctly
        const notifications = await getUserNotifications(uId, clientReadNotificationIds, getReadNotificationIds(uId));

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
    // userId is required to scope the read state to the correct user
    const userId = (req.query.userId as string) || (req.body?.userId as string);
    if (userId) {
        getReadNotificationIds(userId).add(id);
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
        const notifications = await getUserNotifications(uId, activeReadNotificationIds, getReadNotificationIds(uId));
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

export default router;
