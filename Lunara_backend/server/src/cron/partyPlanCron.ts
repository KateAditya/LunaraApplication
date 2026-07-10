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
                    await plan.update({ status: PartyPlanStatus.ACTIVE, isLive: true });
                    logger.info(`Plan ${plan.id} is live again because host failed to pay deposit within 30m.`);
                    await relistPartyPlanInSocket(plan.id);
                } else if (hostPaid && !joinerPaid) {
                    // Joiner did not pay within their 30 min window (starts after host paid):
                    await request.update({ status: PartyPlanRequestStatus.PAYMENT_FAILED });
                    // Host remains paid, and plan goes back live publicly!
                    await plan.update({ status: PartyPlanStatus.ACTIVE, isLive: true });
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
            io.emit('party_plan_created', responseData);
        }
    } catch (socketErr) {
        logger.warn('Socket emission failed for relistPartyPlanInSocket:', socketErr);
    }
}
