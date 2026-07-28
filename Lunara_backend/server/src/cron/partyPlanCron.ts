import cron from 'node-cron';
import { Op } from 'sequelize';
import PartyPlanRequest, { PartyPlanRequestStatus } from '../models/PartyPlanRequest';
import PartyPlan, { PartyPlanStatus } from '../models/PartyPlan';
import User from '../models/User';
import Venue from '../models/Venue';
import UserProfile from '../models/UserProfile';
import UserPhoto from '../models/UserPhoto';
import VenueImage from '../models/VenueImage';
import { logger } from '../config/logger';
import ChatSubscription, { ChatSubscriptionStatus } from '../models/ChatSubscription';
import Conversation from '../models/Conversation';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import SubscriptionPackage from '../models/SubscriptionPackage';
import PartySafetyCheck, { SafetyStatus } from '../models/PartySafetyCheck';

// Run every 5 minutes
export const startPartyPlanCron = () => {
    cron.schedule('*/5 * * * *', async () => {
        try {
            logger.info('Running Party Plan Cron Jobs...');
            
            const now = new Date();

            // 1. Check for expired payment timeouts
            // Requests that are PAYMENT_PENDING but the timeout has passed
            const expiredRequests = await PartyPlanRequest.findAll({
                where: {
                    status: PartyPlanRequestStatus.PAYMENT_PENDING,
                    paymentTimeoutAt: {
                        [Op.lt]: now
                    }
                },
                include: [{ model: PartyPlan, as: 'plan' }]
            });

            for (const request of expiredRequests) {
                const plan = (request as any).plan as PartyPlan;
                if (!plan) {
                    await request.update({ status: PartyPlanRequestStatus.PAYMENT_FAILED });
                    continue;
                }

                const hostPaid = plan.hostPaymentStatus === 'paid';
                const joinerPaid = request.joinerPaymentStatus === 'paid';

                if (!hostPaid) {
                    // Host did not pay within their 30 min acceptance window:
                    await request.update({ status: PartyPlanRequestStatus.PAYMENT_FAILED });
                    await plan.update({ status: PartyPlanStatus.ACTIVE, isLive: plan.visibility !== 'private' });
                    logger.info(`Plan ${plan.id} is live again because host failed to pay deposit within 30m.`);
                    await relistPartyPlanInSocket(plan.id);
                } else if (hostPaid && !joinerPaid) {
                    // Joiner did not pay within their 30 min window (starts after host paid):
                    await request.update({ status: PartyPlanRequestStatus.PAYMENT_FAILED });
                    // Host remains paid, and plan goes back live publicly if not private!
                    await plan.update({ status: PartyPlanStatus.ACTIVE, isLive: plan.visibility !== 'private' });
                    logger.info(`Plan ${plan.id} is live again because joiner (req ${request.id}) did not pay within 30m. Host is already paid.`);
                    await relistPartyPlanInSocket(plan.id);

                    // Send push notification to host
                    try {
                        const hostUser = await User.findByPk(plan.userId);
                        if (hostUser && hostUser.fcmToken) {
                            const { sendMulticastPushNotification } = require('../services/fcmService');
                            await sendMulticastPushNotification([hostUser.fcmToken], {
                                title: '⚡ Plan Live Again',
                                body: 'The joiner did not complete payment within 30 minutes. Your party plan is live again with no payment requirements!',
                                data: {
                                    type: 'party_plan_timeout_relist',
                                    partyPlanId: plan.id,
                                },
                            });
                        }
                    } catch (pushErr: any) {
                        logger.warn('Failed to send timeout relist push notification:', pushErr.message);
                    }
                } else {
                    // Fallback: both paid. Mark accepted and inactive.
                    await request.update({ 
                        status: PartyPlanRequestStatus.ACCEPTED,
                        joinerPaymentStatus: 'paid' as any
                    });
                    await plan.update({ 
                        hostPaymentStatus: 'paid' as any,
                        status: PartyPlanStatus.INACTIVE,
                        isLive: false
                    });
                    logger.info(`Match Success (cron fallback) for plan ${plan.id}.`);
                }
            }

            // 2. Process Completed Plans (3 hours after planDateTime)
            // Refund successful matches and penalize no-shows
            const threeHoursAgo = new Date(now.getTime() - 3 * 60 * 60 * 1000);
            
            const completedPlans = await PartyPlan.findAll({
                where: {
                    status: PartyPlanStatus.ACTIVE,
                    planDateTime: {
                        [Op.lt]: threeHoursAgo
                    }
                }
            });

            for (const plan of completedPlans) {
                // Find paid join requests
                const paidRequests = await PartyPlanRequest.findAll({
                    where: {
                        planId: plan.id,
                        joinerPaymentStatus: 'paid'
                    }
                });

                if (paidRequests.length > 0) {
                    // We only have 1 accepted joiner for 1-on-1 party plan
                    const joinerReq = paidRequests[0];
                    const hostCheckedIn = plan.hostLatLangCheckIn;
                    const joinerCheckedIn = joinerReq.latLangCheckIn;

                    if (hostCheckedIn && joinerCheckedIn) {
                        // MATCH SUCCESS -> Refund both
                        logger.info(`Match Success! Refunding deposit for plan ${plan.id}`);
                        
                        // In reality, call Razorpay refund API here. For now mock:
                        await plan.update({ hostPaymentStatus: 'refunded' as any });
                        await joinerReq.update({ joinerPaymentStatus: 'refunded' as any });
                    } else {
                        // NO SHOW LOGIC
                        if (!hostCheckedIn) {
                            logger.info(`Host NO SHOW for plan ${plan.id}`);
                            const hostUser = await User.findByPk(plan.userId);
                            if (hostUser) {
                                const newCount = (hostUser.noShowCount || 0) + 1;
                                await hostUser.update({ noShowCount: newCount });
                                if (newCount >= 2) {
                                    logger.warn(`Restricting User profile for Host ${hostUser.id} due to 2 No-Shows`);
                                    await hostUser.update({ isActive: false });
                                }
                            }
                        }

                        if (!joinerCheckedIn) {
                            logger.info(`Joiner NO SHOW for request ${joinerReq.id}`);
                            const joinerUser = await User.findByPk(joinerReq.requesterId);
                            if (joinerUser) {
                                const newCount = (joinerUser.noShowCount || 0) + 1;
                                await joinerUser.update({ noShowCount: newCount });
                                if (newCount >= 2) {
                                    logger.warn(`Restricting User profile for Joiner ${joinerUser.id} due to 2 No-Shows`);
                                    await joinerUser.update({ isActive: false });
                                }
                            }
                        }
                    }
                }

                // Mark plan as completed/inactive so we don't process it again
                await plan.update({ status: PartyPlanStatus.INACTIVE });
            }

            // 3. Check for recently expired chat subscriptions
            const expiredChats = await ChatSubscription.findAll({
                where: {
                    status: ChatSubscriptionStatus.ACTIVE,
                    validUntil: {
                        [Op.lt]: now
                    }
                }
            });

            for (const sub of expiredChats) {
                await sub.update({ status: ChatSubscriptionStatus.EXPIRED });
                
                // Get the conversation participants and send a push notification
                try {
                    const conv = await Conversation.findByPk(sub.conversationId);
                    if (conv) {
                        const host = await User.findByPk(conv.participantOne);
                        const joiner = await User.findByPk(conv.participantTwo);
                        const tokens = [host?.fcmToken, joiner?.fcmToken].filter(t => t && t.trim() !== '') as string[];
                        if (tokens.length > 0) {
                            const { sendMulticastPushNotification } = require('../services/fcmService');
                            await sendMulticastPushNotification(tokens, {
                                title: '💬 Chat Expired',
                                body: 'Your private chat session has expired. Extend it to keep chatting!',
                                data: {
                                    type: 'chat_expired',
                                    conversationId: sub.conversationId,
                                },
                            });
                        }
                    }
                } catch (pushErr: any) {
                    logger.warn('Failed to send chat expired push notification:', pushErr.message);
                }
            }

            // 4. Check for user subscription expiration and expiration warnings (24h alert)
            const activeSubscriptions = await UserSubscription.findAll({
                where: {
                    status: SubscriptionStatus.ACTIVE,
                },
                include: [{ model: SubscriptionPackage, as: 'package' }]
            });

            const in24Hours = new Date(now.getTime() + 24 * 60 * 60 * 1000);

            for (const sub of activeSubscriptions) {
                const endDate = new Date(sub.endDate);
                const pkg = (sub as any).package;
                const pkgName = pkg?.name || 'VIP Package';

                if (endDate <= now) {
                    // Plan Has Expired
                    await sub.update({ status: SubscriptionStatus.EXPIRED });
                    logger.info(`Subscription ${sub.id} for user ${sub.userId} marked as EXPIRED.`);

                    // Push Notification to user
                    try {
                        const user = await User.findByPk(sub.userId);
                        if (user && user.fcmToken) {
                            const { sendMulticastPushNotification } = require('../services/fcmService');
                            await sendMulticastPushNotification([user.fcmToken], {
                                title: '⚡ VIP Plan Expired',
                                body: `Your ${pkgName} subscription has expired. Upgrade your plan to continue enjoying exclusive features!`,
                                data: {
                                    type: 'subscription_expired',
                                    subscriptionId: sub.id,
                                },
                            });
                        }

                        // Socket notification
                        const { io } = require('../server');
                        io.to(`user_${sub.userId}`).emit('subscription_expired', {
                            subscriptionId: sub.id,
                            userId: sub.userId,
                            message: `Your ${pkgName} subscription has expired.`,
                        });
                    } catch (pushErr: any) {
                        logger.warn(`Failed to send subscription expiration push/socket for user ${sub.userId}:`, pushErr.message);
                    }
                } else if (endDate <= in24Hours) {
                    // Plan is expiring within 24 hours - send warning if not already sent
                    if (!sub.expirationAlertSent) {
                        try {
                            const user = await User.findByPk(sub.userId);
                            if (user && user.fcmToken) {
                                const { sendMulticastPushNotification } = require('../services/fcmService');
                                await sendMulticastPushNotification([user.fcmToken], {
                                    title: '⏳ VIP Plan Expiring Soon',
                                    body: `Your ${pkgName} subscription will expire in less than 24 hours! Renew now to retain your benefits.`,
                                    data: {
                                        type: 'subscription_expiring_soon',
                                        subscriptionId: sub.id,
                                    },
                                });
                            }

                            const { io } = require('../server');
                            io.to(`user_${sub.userId}`).emit('subscription_expiring_soon', {
                                subscriptionId: sub.id,
                                userId: sub.userId,
                                endDate: sub.endDate,
                                message: `Your ${pkgName} subscription will expire in less than 24 hours!`,
                            });

                            await sub.update({ expirationAlertSent: true });
                        } catch (warnErr: any) {
                            logger.warn(`Failed to send subscription 24h warning to user ${sub.userId}:`, warnErr.message);
                        }
                    }
                }
            }
            
        } catch (error) {
            logger.error('Error running party plan cron jobs:', error);
        }
    });
};

async function relistPartyPlanInSocket(planId: string) {
    try {
        const relistedPlan = await PartyPlan.findByPk(planId, {
            include: [
                {
                    model: User,
                    as: 'creator',
                    include: [
                        { model: UserProfile, as: 'profile', required: false },
                        { model: UserPhoto, as: 'photos', required: false },
                    ]
                },
                {
                    model: Venue,
                    as: 'venue',
                    include: [
                        {
                            model: VenueImage,
                            as: 'images',
                            where: { imageType: 'cover', isPrimary: true },
                            required: false
                        }
                    ]
                }
            ]
        });

        if (relistedPlan) {
            const creator = (relistedPlan as any).creator;
            let photoUrl = creator?.profileImageUrl ?? null;
            if (creator?.photos && creator.photos.length > 0) {
                const primary = creator.photos.find((p: any) => p.isPrimary) || creator.photos[0];
                if (primary && primary.filePath) {
                    photoUrl = '/' + primary.filePath.replace(/\\/g, '/');
                }
            }

            const venueObj = (relistedPlan as any).venue;

            const responseData = {
                id: relistedPlan.id,
                status: relistedPlan.status,
                paymentStatus: relistedPlan.paymentStatus,
                visibility: relistedPlan.visibility,
                selectedUsers: relistedPlan.selectedUsers,
                message: relistedPlan.message,
                planDateTime: relistedPlan.planDateTime,
                createdAt: relistedPlan.createdAt,
                hostPaymentStatus: relistedPlan.hostPaymentStatus,
                hostRazorpayOrderId: relistedPlan.hostRazorpayOrderId,
                isLive: relistedPlan.isLive,
                depositAmount: relistedPlan.depositAmount,
                expiresAt: relistedPlan.expiresAt,
                user: creator ? {
                    id: creator.id,
                    firstName: creator.firstName,
                    lastName: creator.lastName,
                    email: creator.email,
                    phone: creator.phone,
                    profilePhotoUrl: photoUrl,
                    bio: creator.profile?.bio ?? null,
                    occupation: creator.profile?.occupation ?? null,
                    gender: creator.profile?.gender ?? null,
                    city: creator.profile?.city ?? null,
                } : null,
                venue: venueObj ? {
                    id: venueObj.id,
                    name: venueObj.name,
                    addressLine1: venueObj.addressLine1,
                    area: venueObj.area,
                    city: venueObj.city,
                    category: venueObj.category,
                } : null,
            };

            const { io } = require('../server');
            if (relistedPlan.visibility === 'private') {
                io.to(`user_${relistedPlan.userId}`).emit('party_plan_created', responseData);
                if (Array.isArray(relistedPlan.selectedUsers)) {
                    for (const invitedUserId of relistedPlan.selectedUsers) {
                        io.to(`user_${invitedUserId}`).emit('party_plan_created', responseData);
                    }
                }
            } else {
                io.emit('party_plan_created', responseData);
            }
        }
    } catch (socketErr) {
        logger.warn('Socket emission failed for relistPartyPlanInSocket:', socketErr);
    }
}

import { NotificationService } from '../services/NotificationService';
import StrangersMeetRequest from '../models/StrangersMeetRequest';
import StrangersMeetJoiner from '../models/StrangersMeetJoiner';
import PlanTimeLock from '../models/PlanTimeLock';

export const startNotificationJobCron = () => {
    cron.schedule('* * * * *', async () => {
        try {
            const now = new Date();
            const NotificationJob = require('../models/NotificationJob').default;

            const pendingJobs = await NotificationJob.findAll({
                where: {
                    status: 'pending',
                    sendAt: { [Op.lte]: now }
                }
            });

            if (pendingJobs.length === 0) return;

            logger.info(`Processing ${pendingJobs.length} scheduled notification jobs...`);

            for (const job of pendingJobs) {
                try {
                    await NotificationService.dispatch({
                        recipientUserId: job.userId,
                        eventType: 'lock_expired',
                        category: 'alert',
                        entityType: 'NotificationJob',
                        entityId: job.id,
                        title: job.title,
                        body: job.body,
                        priority: 'HIGH',
                        idempotencyKey: `job_dispatch_${job.id}`,
                    });

                    await job.update({ status: 'sent' });
                } catch (jobErr: any) {
                    logger.error(`Error processing job ${job.id}:`, jobErr);
                    await job.update({ status: 'failed' });
                }
            }
        } catch (cronErr: any) {
            logger.error('Notification Job Cron error:', cronErr);
        }
    });
};

export const startExpiringPlanAlertCron = () => {
    // Run every 3 minutes
    cron.schedule('*/3 * * * *', async () => {
        try {
            const now = new Date();
            const in15Mins = new Date(now.getTime() + 15 * 60 * 1000);
            const in45Mins = new Date(now.getTime() + 45 * 60 * 1000);
            const in10Mins = new Date(now.getTime() + 10 * 60 * 1000);

            // 1. Party Plans starting in ~30 mins (between 15m and 45m from now)
            const startingPlans = await PartyPlan.findAll({
                where: {
                    status: PartyPlanStatus.ACTIVE,
                    planDateTime: {
                        [Op.gte]: in15Mins,
                        [Op.lte]: in45Mins,
                    }
                },
                include: [{ model: Venue, as: 'venue', attributes: ['name'] }]
            });

            for (const plan of startingPlans) {
                const venueName = (plan as any).venue?.name || 'Venue';
                // Notify Host
                await NotificationService.dispatch({
                    recipientUserId: plan.userId,
                    eventType: 'party_plan_starting_soon',
                    category: 'alert',
                    entityType: 'PartyPlan',
                    entityId: plan.id,
                    title: '⏰ Party Plan Starting Soon!',
                    body: `Your party plan at ${venueName} starts in ~30 minutes! Open your ticket to prepare for check-in.`,
                    priority: 'HIGH',
                    idempotencyKey: `alert_plan_start_${plan.id}_${plan.userId}`,
                    deepLink: `/party-plan-ticket/${plan.id}`,
                    actionType: 'view_ticket',
                });

                // Notify Accepted Joiners
                const requests = await PartyPlanRequest.findAll({
                    where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED }
                });
                for (const req of requests) {
                    await NotificationService.dispatch({
                        recipientUserId: req.requesterId,
                        eventType: 'party_plan_starting_soon',
                        category: 'alert',
                        entityType: 'PartyPlan',
                        entityId: plan.id,
                        title: '⏰ Party Plan Starting Soon!',
                        body: `Your party plan at ${venueName} starts in ~30 minutes! Show your ticket at the venue.`,
                        priority: 'HIGH',
                        idempotencyKey: `alert_plan_start_${plan.id}_${req.requesterId}`,
                        deepLink: `/party-plan-ticket/${plan.id}`,
                        actionType: 'view_ticket',
                    });
                }
            }

            // 2. Strangers Meet starting in ~30 mins (between 15m and 45m from now)
            const startingMeets = await StrangersMeetRequest.findAll({
                where: {
                    status: 'approved',
                    eventDateTime: {
                        [Op.gte]: in15Mins,
                        [Op.lte]: in45Mins,
                    }
                },
                include: [{ model: Venue, as: 'venue', attributes: ['name'] }]
            });

            for (const meet of startingMeets) {
                const venueName = (meet as any).venue?.name || 'Venue';
                // Notify Host
                await NotificationService.dispatch({
                    recipientUserId: meet.userId,
                    eventType: 'strangers_meet_starting_soon',
                    category: 'alert',
                    entityType: 'StrangersMeetRequest',
                    entityId: meet.id,
                    title: '⏰ Stranger Meet Starting Soon!',
                    body: `Your meet "${meet.subject}" at ${venueName} starts in ~30 minutes!`,
                    priority: 'HIGH',
                    idempotencyKey: `alert_meet_start_${meet.id}_${meet.userId}`,
                    deepLink: `/strangers-meet-ticket/${meet.id}`,
                    actionType: 'view_ticket',
                });

                // Notify Joiners
                const joiners = await StrangersMeetJoiner.findAll({
                    where: { strangersMeetRequestId: meet.id, paymentStatus: 'paid' }
                });
                for (const j of joiners) {
                    await NotificationService.dispatch({
                        recipientUserId: j.userId,
                        eventType: 'strangers_meet_starting_soon',
                        category: 'alert',
                        entityType: 'StrangersMeetRequest',
                        entityId: meet.id,
                        title: '⏰ Stranger Meet Starting Soon!',
                        body: `Your meet "${meet.subject}" at ${venueName} starts in ~30 minutes!`,
                        priority: 'HIGH',
                        idempotencyKey: `alert_meet_start_${meet.id}_${j.userId}`,
                        deepLink: `/strangers-meet-ticket/${meet.id}`,
                        actionType: 'view_ticket',
                    });
                }
            }

            // 3. Time Lock Cooldown Ending (within next 10 minutes)
            const expiringLocks = await PlanTimeLock.findAll({
                where: {
                    status: 'active',
                    lockEndAt: {
                        [Op.gte]: now,
                        [Op.lte]: in10Mins,
                    }
                }
            });

            for (const lock of expiringLocks) {
                await NotificationService.dispatch({
                    recipientUserId: lock.userId,
                    eventType: 'cooldown_expiring_soon',
                    category: 'alert',
                    entityType: 'PlanTimeLock',
                    entityId: lock.id,
                    title: '⚡ Cooldown Expiring Soon',
                    body: 'Your plan creation cooldown expires in a few minutes. Get ready to post your next party!',
                    priority: 'NORMAL',
                    idempotencyKey: `alert_cooldown_${lock.id}_${lock.userId}`,
                    actionType: 'open_plans',
                });
            }

            // 4. Payment Window Closing Soon (10 minutes remaining)
            const pendingRequests = await PartyPlanRequest.findAll({
                where: {
                    status: PartyPlanRequestStatus.PAYMENT_PENDING,
                    paymentTimeoutAt: {
                        [Op.gte]: now,
                        [Op.lte]: in10Mins,
                    }
                },
                include: [{ model: PartyPlan, as: 'plan', include: [{ model: Venue, as: 'venue', attributes: ['name'] }] }]
            });

            for (const req of pendingRequests) {
                const plan = (req as any).plan;
                const venueName = plan?.venue?.name || 'Venue';
                const recipientId = req.joinerPaymentStatus !== 'paid' ? req.requesterId : plan?.userId;
                if (recipientId) {
                    await NotificationService.dispatch({
                        recipientUserId: recipientId,
                        eventType: 'payment_window_expiring',
                        category: 'alert',
                        entityType: 'PartyPlanRequest',
                        entityId: req.id,
                        title: '💳 Payment Window Closing Soon',
                        body: `Only ~10 minutes left to complete payment for party plan at ${venueName}. Complete payment to lock your spot!`,
                        priority: 'HIGH',
                        idempotencyKey: `alert_pay_timeout_${req.id}_${recipientId}`,
                        actionType: 'pay_now',
                    });
                }
            }
            // 5. Trigger Post-Party Safety Checks (3 hours after party start time)
            await checkAndTriggerPartySafetyChecks();
        } catch (alertErr: any) {
            logger.error('Expiring Plan Alert Cron Error:', alertErr);
        }
    });
};

/**
 * Automates 3-Hour Post-Party Safety Checks for Party Plans & Stranger Meets
 */
export const checkAndTriggerPartySafetyChecks = async () => {
    try {
        const now = new Date();
        const threeHoursAgo = new Date(now.getTime() - 3 * 60 * 60 * 1000);

        // 1. Party Plans scheduled 3+ hours ago
        const partyPlans = await PartyPlan.findAll({
            where: {
                planDateTime: { [Op.lte]: threeHoursAgo },
            },
            include: [
                { model: Venue, as: 'venue', attributes: ['name'] },
                { model: User, as: 'creator', attributes: ['id', 'firstName', 'lastName', 'phone'] }
            ]
        });

        for (const plan of partyPlans) {
            const venueName = (plan as any).venue?.name || 'Venue';
            const hostId = plan.userId;

            // Find accepted joiner
            const acceptedReq = await PartyPlanRequest.findOne({
                where: { planId: plan.id, status: PartyPlanRequestStatus.ACCEPTED },
                include: [{ model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'phone'] }]
            });

            const joinerId = acceptedReq ? acceptedReq.requesterId : undefined;

            // Dispatch to Host
            await dispatchSafetyCheckIfPending({
                planId: plan.id,
                planType: 'party_plan',
                userId: hostId,
                partnerUserId: joinerId,
                venueName,
                partyDate: plan.planDateTime,
                partyTime: (plan as any).startTime || '10:00 PM',
            });

            // Dispatch to Joiner
            if (joinerId) {
                await dispatchSafetyCheckIfPending({
                    planId: plan.id,
                    planType: 'party_plan',
                    userId: joinerId,
                    partnerUserId: hostId,
                    venueName,
                    partyDate: plan.planDateTime,
                    partyTime: (plan as any).startTime || '10:00 PM',
                });
            }
        }

        // 2. Stranger Meets scheduled 3+ hours ago
        const strangerMeets = await StrangersMeetRequest.findAll({
            where: {
                eventDateTime: { [Op.lte]: threeHoursAgo },
            },
            include: [{ model: Venue, as: 'venue', attributes: ['name'] }]
        });

        for (const meet of strangerMeets) {
            const venueName = (meet as any).venue?.name || 'Venue';
            const hostId = meet.userId;

            const joiners = await StrangersMeetJoiner.findAll({
                where: { strangersMeetRequestId: meet.id, paymentStatus: 'paid' }
            });

            const joinerIds = joiners.map(j => j.userId);

            // Dispatch to Host
            await dispatchSafetyCheckIfPending({
                planId: meet.id,
                planType: 'stranger_meet',
                userId: hostId,
                partnerUserId: joinerIds[0],
                venueName,
                partyDate: meet.eventDateTime,
                partyTime: '10:00 PM',
            });

            // Dispatch to Joiners
            for (const jId of joinerIds) {
                await dispatchSafetyCheckIfPending({
                    planId: meet.id,
                    planType: 'stranger_meet',
                    userId: jId,
                    partnerUserId: hostId,
                    venueName,
                    partyDate: meet.eventDateTime,
                    partyTime: '10:00 PM',
                });
            }
        }
    } catch (err: any) {
        logger.error('checkAndTriggerPartySafetyChecks error:', err);
    }
};

async function dispatchSafetyCheckIfPending(data: {
    planId: string;
    planType: string;
    userId: string;
    partnerUserId?: string;
    venueName: string;
    partyDate: Date;
    partyTime?: string;
}) {
    const existing = await PartySafetyCheck.findOne({
        where: {
            planId: data.planId,
            userId: data.userId,
        }
    });

    if (existing) return; // Notification already created

    const safetyRecord = await PartySafetyCheck.create({
        planId: data.planId,
        planType: data.planType,
        userId: data.userId,
        partnerUserId: data.partnerUserId,
        venueName: data.venueName,
        partyDate: data.partyDate,
        partyTime: data.partyTime,
        safetyStatus: SafetyStatus.NO_RESPONSE,
        alertTriggered: false,
        notificationSentAt: new Date(),
    });

    await NotificationService.dispatch({
        recipientUserId: data.userId,
        eventType: 'party_safety_check',
        category: 'alert',
        entityType: 'PartySafetyCheck',
        entityId: safetyRecord.id,
        title: '🛡️ Safety Check: Has your party ended?',
        body: `Your party at ${data.venueName} started 3 hours ago. Please confirm you are safe & sound.`,
        priority: 'HIGH',
        idempotencyKey: `safety_check_${safetyRecord.id}_${data.userId}`,
        actionType: 'safety_check',
        deepLink: `/safety-check/${safetyRecord.id}`,
    });
}

