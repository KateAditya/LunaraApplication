import { Request, Response } from 'express';
import { Op } from 'sequelize';
import {
    Notification,
    PartyPlan,
    PartyPlanRequest,
    StrangersMeetRequest,
    StrangersMeetJoiner,
    Conversation,
    Message,
    SmartWallet,
    User,
    UserSubscription,
    SubscriptionPackage,
} from '../models';
import { MessageStatus } from '../models/Message';
import { logger } from '../config/logger';

/**
 * GET /api/mobile/sync/delta?since=ISO_DATE
 * Lightweight delta synchronization endpoint.
 * Returns only entities changed since the provided timestamp for the authenticated user.
 */
export const getDeltaSync = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = (req as any).user?.id || (req as any).userId;
        if (!userId) {
            return res.status(401).json({ success: false, message: 'Authentication required' });
        }

        const sinceQuery = req.query.since as string;
        let sinceDate = sinceQuery ? new Date(sinceQuery) : new Date(Date.now() - 24 * 60 * 60 * 1000);
        if (isNaN(sinceDate.getTime())) {
            sinceDate = new Date(Date.now() - 24 * 60 * 60 * 1000);
        }

        // Parallel lightweight queries with indexed updatedAt filters
        const [
            unreadNotifCount,
            recentNotifications,
            updatedHostPlans,
            updatedUserRequests,
            updatedHostMeets,
            updatedUserMeetParticipations,
            userRecord,
            wallet,
            activeSubscription,
            unreadChatCount,
            updatedConversations,
        ] = await Promise.all([
            // 1. Unread notification count
            Notification.count({
                where: { recipientUserId: userId, isRead: false },
            }),
            // 2. Notifications changed since
            Notification.findAll({
                where: {
                    recipientUserId: userId,
                    updatedAt: { [Op.gt]: sinceDate },
                },
                order: [['updatedAt', 'DESC']],
                limit: 30,
            }),
            // 3. Party Plans where user is host updated since
            PartyPlan.findAll({
                where: {
                    userId,
                    updatedAt: { [Op.gt]: sinceDate },
                },
                attributes: ['id', 'status', 'isLive', 'lifecycleStatus', 'paymentStatus', 'hostPaymentStatus', 'matchedRequestId', 'updatedAt'],
                limit: 30,
            }),
            // 4. Party Plan requests involving user updated since
            PartyPlanRequest.findAll({
                where: {
                    requesterId: userId,
                    updatedAt: { [Op.gt]: sinceDate },
                },
                attributes: ['id', 'planId', 'status', 'requesterId', 'joinerPaymentStatus', 'updatedAt'],
                limit: 30,
            }),
            // 5. Stranger Meets where user is host updated since
            StrangersMeetRequest.findAll({
                where: {
                    userId,
                    updatedAt: { [Op.gt]: sinceDate },
                },
                attributes: ['id', 'status', 'paymentStatus', 'updatedAt'],
                limit: 30,
            }),
            // 6. Stranger Meet participations updated since
            StrangersMeetJoiner.findAll({
                where: {
                    userId,
                    updatedAt: { [Op.gt]: sinceDate },
                },
                attributes: ['id', 'strangersMeetRequestId', 'status', 'paymentStatus', 'updatedAt'],
                limit: 30,
            }),
            // 7. User balance
            User.findByPk(userId, {
                attributes: ['walletBalance', 'isOnline'],
            }),
            // 8. SmartWallet
            SmartWallet.findOne({
                where: { userId },
                attributes: ['balance', 'lockedBalance', 'promotionalBalance', 'cashbackBalance', 'rewardBalance', 'updatedAt'],
            }),
            // 9. Active subscription
            UserSubscription.findOne({
                where: { userId, status: 'ACTIVE' },
                attributes: ['id', 'status', 'superlikesRemaining', 'boostsRemaining', 'endDate', 'updatedAt'],
                include: [{ model: SubscriptionPackage, as: 'package', attributes: ['tier'] }],
                order: [['updatedAt', 'DESC']],
            }),
            // 10. Unread Chat count
            Message.count({
                include: [{
                    model: Conversation,
                    as: 'conversation',
                    where: {
                        [Op.or]: [{ participantOne: userId }, { participantTwo: userId }],
                    },
                    attributes: [],
                }],
                where: {
                    senderId: { [Op.ne]: userId },
                    status: { [Op.in]: [MessageStatus.SENT, MessageStatus.DELIVERED] },
                },
            }),
            // 11. Conversations updated since
            Conversation.findAll({
                where: {
                    [Op.or]: [{ participantOne: userId }, { participantTwo: userId }],
                    updatedAt: { [Op.gt]: sinceDate },
                },
                attributes: ['id', 'lastMessage', 'lastMessageAt', 'updatedAt'],
                limit: 30,
            }),
        ]);

        const rawBalance = userRecord?.walletBalance ? Number(userRecord.walletBalance) : (wallet?.balance ? Number(wallet.balance) : 0);

        return res.status(200).json({
            success: true,
            serverTimestamp: new Date().toISOString(),
            data: {
                unreadNotificationCount: unreadNotifCount,
                notifications: recentNotifications,
                partyPlans: updatedHostPlans,
                partyPlanRequests: updatedUserRequests,
                strangerMeets: updatedHostMeets,
                strangerMeetParticipations: updatedUserMeetParticipations,
                wallet: {
                    balance: rawBalance,
                    bonusBalance: wallet ? Number(wallet.promotionalBalance || 0) + Number(wallet.cashbackBalance || 0) : 0,
                },
                subscription: activeSubscription,
                unreadChatCount,
                conversations: updatedConversations,
            },
        });
    } catch (err: any) {
        logger.error('[getDeltaSync] Error executing delta sync:', err);
        return res.status(500).json({ success: false, message: 'Failed to execute delta sync', error: err.message });
    }
};
