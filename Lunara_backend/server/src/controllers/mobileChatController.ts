import { Request, Response } from 'express';
import { Op } from 'sequelize';
import Conversation, { ConversationStatus } from '../models/Conversation';
import Message, { MessageType, MessageStatus, InvitationStatus } from '../models/Message';
import SocialConnection, { ConnectionStatus } from '../models/SocialConnection';
import User from '../models/User';
import UserPhoto from '../models/UserPhoto';
import { logger } from '../config/logger';
import { sendPushNotification } from '../services/fcmService';

// ─── Static Icebreakers ───────────────────────────────────────────────────────
const ICEBREAKERS = [
    { id: 1, emoji: '🔥', text: 'Obsidian or Elara tonight?'              },
    { id: 2, emoji: '🎧', text: 'Favorite DJ in the city?'                 },
    { id: 3, emoji: '🍸', text: 'What is your go-to signature cocktail?'   },
    { id: 4, emoji: '✨', text: 'Best rooftop view you have seen?'          },
    { id: 5, emoji: '🎵', text: 'Melodic House or Hard Techno?'             },
    { id: 6, emoji: '🌙', text: 'Night in or night out this weekend?'       },
    { id: 7, emoji: '🎤', text: 'Last concert you went to?'                 },
    { id: 8, emoji: '🥂', text: 'Champagne or craft cocktails?'             },
    { id: 9, emoji: '🕺', text: 'Dance floor or VIP lounge?'                },
    { id: 10,emoji: '💬', text: 'Tell me something interesting about yourself' },
];

// ─── Helper: enrich user for chat list ───────────────────────────────────────
function formatUserBrief(user: any) {
    if (!user) return null;

    // Resolve profile image: prefer User.profileImageUrl, fall back to primary UserPhoto
    const primaryPhoto = Array.isArray(user.photos) && user.photos.length > 0
        ? user.photos[0]
        : null;
    const profilePhotoUrl = user.profileImageUrl
        ?? (primaryPhoto ? primaryPhoto.getUrl() : null);

    return {
        id:             user.id,
        name:           `${user.firstName ?? ''} ${user.lastName ?? ''}`.trim(),
        firstName:      user.firstName,
        profilePhotoUrl,
        isOnline:       user.isOnline ?? false,
        lastActiveAt:   user.lastActiveAt ?? null,
    };
}

// ─── Ensure conversation deletion columns helper ────────────────────────────
let columnsEnsured = false;
async function ensureConversationColumns() {
    if (columnsEnsured) return;
    try {
        const sequelize = (await import('../config/database')).default;
        await sequelize.query(`
            ALTER TABLE conversations ADD COLUMN IF NOT EXISTS cleared_at_one TIMESTAMP WITH TIME ZONE;
            ALTER TABLE conversations ADD COLUMN IF NOT EXISTS cleared_at_two TIMESTAMP WITH TIME ZONE;
            ALTER TABLE conversations ADD COLUMN IF NOT EXISTS deleted_by_one BOOLEAN DEFAULT FALSE;
            ALTER TABLE conversations ADD COLUMN IF NOT EXISTS deleted_by_two BOOLEAN DEFAULT FALSE;
            ALTER TABLE messages ADD COLUMN IF NOT EXISTS deleted_for_users JSONB DEFAULT '[]'::jsonb;
        `);
        columnsEnsured = true;
    } catch (err) {
        logger.warn('ensureConversationColumns error:', err);
    }
}

// ─── GET /conversations — Chat list ──────────────────────────────────────────
export const getConversations = async (req: Request, res: Response) => {
    try {
        await ensureConversationColumns();
        const userId = (req.query.userId || req.body.userId) as string;
        if (!userId) return res.status(400).json({ success: false, message: 'userId is required' });

        const conversations = await Conversation.findAll({
            where: {
                [Op.or]: [{ participantOne: userId }, { participantTwo: userId }],
                status: { [Op.ne]: ConversationStatus.BLOCKED },
            },
            include: [
                {
                    model: User, as: 'userOne',
                    attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                    include: [{
                        model: UserPhoto,
                        as: 'photos',
                        where: { isPrimary: true },
                        attributes: ['id', 'filePath', 'userId'],
                        required: false,
                    }],
                },
                {
                    model: User, as: 'userTwo',
                    attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                    include: [{
                        model: UserPhoto,
                        as: 'photos',
                        where: { isPrimary: true },
                        attributes: ['id', 'filePath', 'userId'],
                        required: false,
                    }],
                },
            ],
            order: [['lastMessageAt', 'DESC NULLS LAST'], ['createdAt', 'DESC']],
        });

        // Deduplicate conversations by otherUser ID (keep the one with latest lastMessageAt)
        const mapByOtherUser = new Map<string, any>();
        const aggregatedUnreadMap = new Map<string, number>();

        for (const conv of conversations) {
            const otherUserId = conv.getOtherParticipant(userId);
            if (!otherUserId) continue;

            // Filter out conversations that the user explicitly deleted unless there's a newer message
            const uId = userId.toLowerCase();
            const isP1 = (conv.participantOne || '').toLowerCase() === uId;
            const isP2 = (conv.participantTwo || '').toLowerCase() === uId;

            if (isP1 && conv.deletedByOne) {
                const clearedTime = conv.clearedAtOne ? new Date(conv.clearedAtOne).getTime() : 0;
                const lastMsgTime = conv.lastMessageAt ? new Date(conv.lastMessageAt).getTime() : 0;
                if (!conv.lastMessageAt || lastMsgTime <= clearedTime) {
                    continue; // Skip deleted conversation
                }
            } else if (isP2 && conv.deletedByTwo) {
                const clearedTime = conv.clearedAtTwo ? new Date(conv.clearedAtTwo).getTime() : 0;
                const lastMsgTime = conv.lastMessageAt ? new Date(conv.lastMessageAt).getTime() : 0;
                if (!conv.lastMessageAt || lastMsgTime <= clearedTime) {
                    continue; // Skip deleted conversation
                }
            }

            const key = otherUserId.toLowerCase();
            const unread = conv.getUnreadFor ? conv.getUnreadFor(userId) : (isP1 ? (conv.unreadOne || 0) : (conv.unreadTwo || 0));
            aggregatedUnreadMap.set(key, (aggregatedUnreadMap.get(key) || 0) + Number(unread || 0));

            const existing = mapByOtherUser.get(key);
            if (!existing) {
                mapByOtherUser.set(key, conv);
            } else {
                const existingTime = existing.lastMessageAt ? new Date(existing.lastMessageAt).getTime() : (existing.createdAt ? new Date(existing.createdAt).getTime() : 0);
                const newTime = conv.lastMessageAt ? new Date(conv.lastMessageAt).getTime() : (conv.createdAt ? new Date(conv.createdAt).getTime() : 0);
                if (newTime > existingTime) {
                    mapByOtherUser.set(key, conv);
                }
            }
        }

        const list = [];
        for (const conv of mapByOtherUser.values()) {
            const otherUserId = conv.getOtherParticipant(userId);
            const otherUser = (otherUserId && conv.participantOne && otherUserId.toLowerCase() === conv.participantOne.toLowerCase())
                ? (conv as any).userOne
                : (conv as any).userTwo;

            const uId = userId.toLowerCase();
            const isP1 = (conv.participantOne || '').toLowerCase() === uId;
            const clearedTime = isP1
                ? (conv.clearedAtOne ? new Date(conv.clearedAtOne).getTime() : 0)
                : (conv.clearedAtTwo ? new Date(conv.clearedAtTwo).getTime() : 0);
            const lastMsgTime = conv.lastMessageAt ? new Date(conv.lastMessageAt).getTime() : 0;
            const isClearedForUser = clearedTime > 0 && lastMsgTime <= clearedTime;

            const key = otherUserId.toLowerCase();
            const totalUnreadForUser = isClearedForUser ? 0 : (aggregatedUnreadMap.get(key) ?? (conv.getUnreadFor ? conv.getUnreadFor(userId) : 0));

            const rawPreview = conv.lastMessagePreview?.toString().trim();
            const preview = isClearedForUser ? 'Tap to chat' : ((rawPreview && rawPreview.length > 0) ? rawPreview : 'Tap to chat');
            const lastMsgAt = isClearedForUser ? null : conv.lastMessageAt;

            list.push({
                conversationId:      conv.id,
                id:                  conv.id,
                otherUser:           formatUserBrief(otherUser),
                lastMessagePreview:  preview,
                lastMessageAt:       lastMsgAt,
                unreadCount:         totalUnreadForUser,
                status:              conv.status,
                contextType:         conv.contextType,
                contextId:           conv.contextId,
            });
        }

        return res.json({ success: true, count: list.length, data: list });
    } catch (err: any) {
        logger.error('getConversations:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── POST /conversations — Create or get existing conversation ────────────────
export const getOrCreateConversation = async (req: Request, res: Response) => {
    try {
        const { userId, otherUserId, contextType, contextId } = req.body;

        if (!userId || !otherUserId) {
            return res.status(400).json({ success: false, message: 'userId and otherUserId are required' });
        }
        if (userId.toLowerCase() === otherUserId.toLowerCase()) {
            return res.status(400).json({ success: false, message: 'Cannot create conversation with yourself' });
        }

        // ── Security Guard: Enforce that Party Plan chat requires BOTH payments ─────
        if (contextType === 'party_plan' && contextId) {
            try {
                const PartyPlan = (await import('../models/PartyPlan')).default;
                const PartyPlanRequest = (await import('../models/PartyPlanRequest')).default;
                const plan = await PartyPlan.findByPk(contextId, {
                    include: [{ model: PartyPlanRequest, as: 'requests' }]
                });
                if (plan) {
                    const p = plan as any;
                    const isHost = plan.userId === userId || plan.userId === otherUserId;
                    const matchedReq = p.requests?.find((r: any) => 
                        (r.requesterId === userId || r.requesterId === otherUserId) &&
                        (r.status === 'accepted' || r.status === 'payment_pending' || r.status === 'confirmed' || r.status === 'paid')
                    );
                    if (!isHost || !matchedReq) {
                        return res.status(403).json({
                            success: false,
                            message: 'You are not a matched participant in this Party Plan.'
                        });
                    }
                    if (plan.status === 'cancelled' || plan.lifecycleStatus === 'cancelled') {
                        return res.status(403).json({
                            success: false,
                            message: 'This Party Plan has been cancelled.'
                        });
                    }
                    const hostPaid = plan.hostPaymentStatus === 'paid';
                    const joinerPaid = matchedReq?.joinerPaymentStatus === 'paid' || plan.paymentType === 'self_pay';
                    const isChatUnlocked = Boolean(p.chatEnabled) || p.lifecycleStatus === 'chat_enabled' || p.lifecycleStatus === 'match_confirmed' || (hostPaid && joinerPaid);

                    if (!isChatUnlocked) {
                        return res.status(403).json({
                            success: false,
                            message: 'Chat is locked until both host and partner complete their safety deposit payments.'
                        });
                    }
                }
            } catch (checkErr: any) {
                logger.warn('Error checking party_plan chat unlock status:', checkErr.message);
            }
        }

        // ── Security Guard: Enforce that Stranger Meet chat requires paid status ─────
        if ((contextType === 'stranger_meet' || contextType === 'strangers_meet') && contextId) {
            try {
                const StrangersMeetRequest = (await import('../models/StrangersMeetRequest')).default;
                const StrangersMeetJoiner = (await import('../models/StrangersMeetJoiner')).default;
                const meet = await StrangersMeetRequest.findByPk(contextId);
                if (meet) {
                    const isHost = meet.userId === userId || meet.userId === otherUserId;
                    const participantId = meet.userId === userId ? otherUserId : userId;
                    const joiner = await StrangersMeetJoiner.findOne({
                        where: {
                            strangersMeetRequestId: contextId,
                            userId: participantId,
                        }
                    });
                    if (!isHost || !joiner) {
                        return res.status(403).json({
                            success: false,
                            message: 'You are not a confirmed participant in this Stranger Meet.'
                        });
                    }
                    const isJoinerPaid = joiner.status === 'paid' || joiner.paymentStatus === 'paid' || Number(meet.chargesPerHead || 0) === 0;
                    if (!isJoinerPaid) {
                        return res.status(403).json({
                            success: false,
                            message: 'Chat is locked until the participant entry fee is paid.'
                        });
                    }
                }
            } catch (smCheckErr: any) {
                logger.warn('Error checking stranger_meet chat unlock status:', smCheckErr.message);
            }
        }

        // Search for any existing conversation between these 2 users in EITHER direction
        const existing = await Conversation.findAll({
            where: {
                [Op.or]: [
                    { participantOne: userId, participantTwo: otherUserId },
                    { participantOne: otherUserId, participantTwo: userId },
                ],
                status: { [Op.ne]: ConversationStatus.BLOCKED },
            },
            order: [['lastMessageAt', 'DESC NULLS LAST'], ['createdAt', 'DESC']],
        });

        let conversation: Conversation;
        let created = false;

        if (existing.length > 0) {
            conversation = existing[0];
        } else {
            const [p1, p2] = [userId, otherUserId].sort();
            conversation = await Conversation.create({
                participantOne: p1,
                participantTwo: p2,
                contextType,
                contextId,
            });
            created = true;
        }

        const otherUser = await User.findByPk(otherUserId, {
            attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
            include: [{
                model: UserPhoto,
                as: 'photos',
                where: { isPrimary: true },
                attributes: ['id', 'filePath', 'userId'],
                required: false,
            }],
        });

        return res.status(created ? 201 : 200).json({
            success: true,
            message: created ? 'Conversation created' : 'Conversation retrieved',
            data: {
                conversationId: conversation.id,
                id:             conversation.id,
                otherUser:      formatUserBrief(otherUser),
                unreadCount:    conversation.getUnreadFor(userId),
                status:         conversation.status,
                isNew:          created,
            },
        });
    } catch (err: any) {
        logger.error('getOrCreateConversation:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── GET /conversations/:id/messages — Fetch messages ────────────────────────
export const getMessages = async (req: Request, res: Response) => {
    try {
        const { id }   = req.params;
        const userId   = req.query.userId as string;
        const before   = req.query.before as string | undefined;  // cursor pagination
        const limit    = Math.min(parseInt(req.query.limit as string) || 30, 100);

        if (!userId) return res.status(400).json({ success: false, message: 'userId is required' });

        // Verify user is participant
        const conv = await Conversation.findByPk(id);
        if (!conv) return res.status(404).json({ success: false, message: 'Conversation not found' });
        const uId = userId.toLowerCase();
        const p1 = (conv.participantOne || '').toLowerCase();
        const p2 = (conv.participantTwo || '').toLowerCase();
        if (p1 !== uId && p2 !== uId) {
            return res.status(403).json({ success: false, message: 'Access denied' });
        }

        // Find all conversation IDs between these two participants to include legacy duplicate conversations
        const allConvs = await Conversation.findAll({
            where: {
                [Op.or]: [
                    { participantOne: conv.participantOne, participantTwo: conv.participantTwo },
                    { participantOne: conv.participantTwo, participantTwo: conv.participantOne },
                ],
            },
            attributes: ['id'],
        });
        const convIds = allConvs.map(c => c.id);

        const timeConditions: any[] = [];
        const isP1 = p1 === uId;
        const clearedAt = isP1 ? conv.clearedAtOne : conv.clearedAtTwo;
        if (clearedAt) {
            timeConditions.push({ [Op.gt]: new Date(clearedAt) });
        }
        if (before) {
            timeConditions.push({ [Op.lt]: new Date(before) });
        }

        const where: any = {
            conversationId: { [Op.in]: convIds },
            deletedAt: null as any,
        };
        if (timeConditions.length === 1) {
            where.createdAt = timeConditions[0];
        } else if (timeConditions.length > 1) {
            where.createdAt = { [Op.and]: timeConditions };
        }

        const messages = await Message.findAll({
            where,
            include: [{
                model: User, as: 'sender',
                attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                include: [{
                    model: UserPhoto,
                    as: 'photos',
                    where: { isPrimary: true },
                    attributes: ['id', 'filePath', 'userId'],
                    required: false,
                }],
            }],
            order: [['createdAt', 'DESC']],
            limit,
        });

        // Filter out messages deleted specifically for this user ("Delete for me")
        const visibleMessages = messages.filter(m => {
            const dfu = (m as any).deletedForUsers;
            if (!dfu) return true;
            if (Array.isArray(dfu)) {
                return !dfu.map((x: any) => String(x).toLowerCase()).includes(uId);
            }
            if (typeof dfu === 'string') {
                try {
                    const parsed = JSON.parse(dfu);
                    return Array.isArray(parsed) ? !parsed.map((x: any) => String(x).toLowerCase()).includes(uId) : true;
                } catch (_) { return true; }
            }
            return true;
        });

        // Mark unread messages as read across all related conversations
        const unreadIds = visibleMessages
            .filter(m => m.senderId !== userId && m.status !== MessageStatus.READ)
            .map(m => m.id);

        if (unreadIds.length > 0) {
            await Message.update(
                { status: MessageStatus.READ, readAt: new Date() },
                { where: { id: { [Op.in]: unreadIds } } }
            );
            
            for (const c of allConvs) {
                const resetField = (c.participantOne && userId && c.participantOne.toLowerCase() === userId.toLowerCase()) ? { unreadOne: 0 } : { unreadTwo: 0 };
                await (c as any).update(resetField);
            }
            
            // Emit read receipt to the sender
            try {
                const { io } = require('../server');
                const otherUserId = conv.getOtherParticipant(userId);
                io.to(`user_${otherUserId}`).emit('messages_read', { conversationId: id, readAt: new Date() });

                // Emit chat_badge_updated to current user so their badge clears immediately
                const myConvs = await Conversation.findAll({
                    where: {
                        [Op.or]: [
                            { participantOne: userId },
                            { participantTwo: userId }
                        ],
                        status: { [Op.ne]: ConversationStatus.BLOCKED }
                    },
                    attributes: ['id', 'participantOne', 'participantTwo', 'unreadOne', 'unreadTwo', 'deletedByOne', 'deletedByTwo']
                });
                let myRemainingChatCount = 0;
                for (const c of myConvs) {
                    const isP1 = (c.participantOne || '').toLowerCase() === userId.toLowerCase();
                    const isP2 = (c.participantTwo || '').toLowerCase() === userId.toLowerCase();
                    if (isP1 && c.deletedByOne) continue;
                    if (isP2 && c.deletedByTwo) continue;
                    myRemainingChatCount += Number(c.getUnreadFor ? c.getUnreadFor(userId) : (isP1 ? (c.unreadOne || 0) : (c.unreadTwo || 0)));
                }
                io.to(`user_${userId}`).emit('chat_badge_updated', {
                    conversationId: id,
                    chatCount: myRemainingChatCount,
                    unreadCount: 0
                });
            } catch (err) {
                logger.error('Failed to emit messages_read socket event:', err);
            }
        }

        // Return in chronological order (oldest first for chat display)
        const ordered = [...visibleMessages].reverse();

        return res.json({
            success: true,
            count:   ordered.length,
            hasMore: messages.length === limit,
            data:    ordered.map(m => formatMessage(m)),
        });
    } catch (err: any) {
        logger.error('getMessages:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── POST /conversations/:id/messages — Send message ─────────────────────────
export const sendMessage = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const {
            senderId,
            clientMessageId,
            type = MessageType.TEXT,
            content,
            mediaUrl,
            mediaMimeType,
            duration,
            fileSize,
            waveformData,
            replyToMessageId,
            invitationRef,
            invitationRefType,
            invitationTime,
        } = req.body;

        if (!senderId) return res.status(400).json({ success: false, message: 'senderId is required' });

        // ── Idempotency check: return existing message if clientMessageId already processed
        if (clientMessageId) {
            try {
                const existing = await Message.findOne({
                    where: { conversationId: id, clientMessageId },
                    include: [{
                        model: User, as: 'sender',
                        attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                        include: [{
                            model: UserPhoto, as: 'photos',
                            where: { isPrimary: true },
                            attributes: ['id', 'filePath', 'userId'],
                            required: false,
                        }],
                    }],
                });
                if (existing) {
                    return res.status(200).json({
                        success: true,
                        message: 'Message already sent (idempotent)',
                        data: formatMessage(existing),
                    });
                }
            } catch (findErr: any) {
                logger.warn('[SendMessage] client_message_id query fallback:', findErr.message);
                await Message.sync().catch(() => {});
            }
        }

        const conv = await Conversation.findByPk(id);
        if (!conv) return res.status(404).json({ success: false, message: 'Conversation not found' });
        const sId = senderId.toLowerCase();
        const p1 = (conv.participantOne || '').toLowerCase();
        const p2 = (conv.participantTwo || '').toLowerCase();
        if (p1 !== sId && p2 !== sId) {
            return res.status(403).json({ success: false, message: 'You are not part of this conversation' });
        }
        if (conv.status === ConversationStatus.BLOCKED) {
            return res.status(403).json({ success: false, message: 'This conversation is blocked' });
        }

        // Check if chat subscription is active
        const { getChatSessionStatus } = require('./chatSubscriptionController');
        const sessionStatus = await getChatSessionStatus(id, senderId);
        if (!sessionStatus.canChat) {
            return res.status(403).json({ success: false, message: 'Chat session has expired or is locked' });
        }

        // Validate content based on type
        if ([MessageType.TEXT, MessageType.ICEBREAKER].includes(type) && !content) {
            return res.status(400).json({ success: false, message: 'content is required for text/icebreaker messages' });
        }
        if ([MessageType.IMAGE, MessageType.STICKER, MessageType.VOICE].includes(type) && !mediaUrl) {
            return res.status(400).json({ success: false, message: 'mediaUrl is required for image/sticker/voice messages' });
        }
        if (type === MessageType.INVITATION && (!invitationRef || !invitationTime)) {
            return res.status(400).json({ success: false, message: 'invitationRef and invitationTime are required for invitation messages' });
        }

        const recipientId = conv.getOtherParticipant(senderId);

        // Check if sender has blocked recipient
        const isSenderBlockingRecipient = await SocialConnection.findOne({
            where: {
                requesterId: senderId,
                receiverId: recipientId,
                status: ConnectionStatus.BLOCKED,
            },
        });
        if (isSenderBlockingRecipient) {
            return res.status(403).json({
                success: false,
                message: 'You have blocked this user. Unblock them to send messages.',
            });
        }

        // Check if recipient has blocked sender (silent drop / message isolation for recipient)
        const isRecipientBlockingSender = await SocialConnection.findOne({
            where: {
                requesterId: recipientId,
                receiverId: senderId,
                status: ConnectionStatus.BLOCKED,
            },
        });

        let isRecipientOnline = false;
        if (!isRecipientBlockingSender) {
            try {
                const { io } = require('../server');
                const recipientRoom = io.sockets.adapter.rooms.get(`user_${recipientId}`);
                isRecipientOnline = !!(recipientRoom && recipientRoom.size > 0);
            } catch (err) {}
        }

        const msgPayload = {
            conversationId: id,
            senderId,
            clientMessageId,
            type,
            content,
            mediaUrl,
            mediaMimeType,
            duration: duration ? parseInt(duration) : undefined,
            fileSize: fileSize ? parseInt(fileSize) : undefined,
            waveformData: waveformData ? String(waveformData) : undefined,
            replyToMessageId,
            invitationRef,
            invitationRefType,
            invitationTime,
            invitationStatus: type === MessageType.INVITATION ? InvitationStatus.PENDING : undefined,
            status: isRecipientOnline ? MessageStatus.DELIVERED : MessageStatus.SENT,
            deletedForUsers: isRecipientBlockingSender ? [recipientId] : [],
        };

        let message: Message;
        try {
            message = await Message.create(msgPayload);
        } catch (createErr: any) {
            logger.warn('[SendMessage] Message.create failed, triggering table auto-sync fallback:', createErr.message);
            await Message.sync().catch(() => {});
            message = await Message.create(msgPayload);
        }

        // Build preview text
        const preview = message.getPreview();

        // Increment unread for the OTHER participant safely (only if recipient has not blocked sender)
        const isOne = (conv.participantOne && senderId && conv.participantOne.toLowerCase() === senderId.toLowerCase());
        const currentUnreadOne = Number(conv.unreadOne || 0);
        const currentUnreadTwo = Number(conv.unreadTwo || 0);
        const unreadUpdate = isRecipientBlockingSender
            ? {}
            : (isOne ? { unreadTwo: currentUnreadTwo + 1 } : { unreadOne: currentUnreadOne + 1 });

        await (conv as any).update({
            lastMessageId:      message.id,
            lastMessageAt:      message.createdAt,
            lastMessagePreview: preview,
            deletedByOne:       false,
            deletedByTwo:       false,
            ...unreadUpdate,
        });

        const formattedMsg = formatMessage(message as any);

        // Emit new_message and notifications to recipient ONLY if recipient hasn't blocked sender
        if (!isRecipientBlockingSender) {
            // Calculate recipient unread chat count quickly
            let recipientChatCount = 0;
            try {
                const recipientConvs = await Conversation.findAll({
                    where: {
                        [Op.or]: [
                            { participantOne: recipientId },
                            { participantTwo: recipientId }
                        ],
                        status: { [Op.ne]: ConversationStatus.BLOCKED }
                    },
                    attributes: ['id', 'participantOne', 'participantTwo', 'unreadOne', 'unreadTwo', 'deletedByOne', 'deletedByTwo']
                });
                for (const c of recipientConvs) {
                    const isP1 = (c.participantOne || '').toLowerCase() === recipientId.toLowerCase();
                    const isP2 = (c.participantTwo || '').toLowerCase() === recipientId.toLowerCase();
                    if (isP1 && (c as any).deletedByOne) continue;
                    if (isP2 && (c as any).deletedByTwo) continue;
                    recipientChatCount += Number(c.getUnreadFor ? c.getUnreadFor(recipientId) : (isP1 ? ((c as any).unreadOne || 0) : ((c as any).unreadTwo || 0)));
                }
            } catch (_) {}

            try {
                const { io } = require('../server');
                io.to(`user_${recipientId}`).emit('new_message', formattedMsg);
                io.to(`user_${recipientId}`).emit('chat_badge_updated', {
                    conversationId: id,
                    chatCount: recipientChatCount,
                    unreadCount: conv.getUnreadFor ? conv.getUnreadFor(recipientId) : (isOne ? currentUnreadTwo + 1 : currentUnreadOne + 1)
                });
            } catch (err) {
                logger.error('Failed to emit new_message socket event to recipient:', err);
            }

            // ── Push notification (for offline recipients) ───────────────────────
            if (!isRecipientOnline) {
                try {
                    const recipient = await User.findByPk(recipientId, { attributes: ['id', 'firstName', 'lastName', 'fcmToken'] });
                    const senderUser = await User.findByPk(senderId, { attributes: ['id', 'firstName', 'lastName'] });
                    const fcmToken = (recipient as any)?.fcmToken;
                    if (fcmToken) {
                        const senderName = senderUser
                            ? `${senderUser.firstName} ${senderUser.lastName}`.trim()
                            : 'Someone';
                        const notifBody = type === MessageType.IMAGE
                            ? '📷 Sent you a photo'
                            : type === MessageType.STICKER
                            ? '🎨 Sent you a sticker'
                            : type === MessageType.VOICE
                            ? '🎙️ Sent you a voice message'
                            : type === MessageType.INVITATION
                            ? '🗓️ Sent you an invitation'
                            : (content ?? 'New message');

                        await sendPushNotification(fcmToken, {
                            title: senderName,
                            body: notifBody,
                            data: {
                                type: 'new_message',
                                conversationId: id,
                                senderId,
                            },
                        });
                    }
                } catch (err: any) {
                    logger.warn('Failed to send chat push notification:', err.message);
                }
            }
        }

        // Always emit to sender room
        try {
            const { io } = require('../server');
            io.to(`user_${senderId}`).emit('new_message', formattedMsg);
            if (isRecipientOnline && !isRecipientBlockingSender) {
                io.to(`user_${senderId}`).emit('messages_delivered', { conversationId: id });
            }
        } catch (err) {
            logger.error('Failed to emit new_message socket event to sender:', err);
        }

        return res.status(201).json({
            success: true,
            message: 'Message sent',
            data:    formatMessage(message),
        });
    } catch (err: any) {
        logger.error('sendMessage:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── PATCH /conversations/:id/messages/:msgId/invitation — Accept/Decline ────
export const respondToInvitation = async (req: Request, res: Response) => {
    try {
        const { id, msgId } = req.params;
        const { userId, action } = req.body; // action: 'accept' | 'decline'

        if (!['accept', 'decline'].includes(action)) {
            return res.status(400).json({ success: false, message: "action must be 'accept' or 'decline'" });
        }

        const message = await Message.findOne({
            where: { id: msgId, conversationId: id, type: MessageType.INVITATION },
        });
        if (!message) return res.status(404).json({ success: false, message: 'Invitation message not found' });
        if (message.senderId === userId) {
            return res.status(400).json({ success: false, message: 'You cannot respond to your own invitation' });
        }
        if (message.invitationStatus !== InvitationStatus.PENDING) {
            return res.status(400).json({ success: false, message: `Invitation already ${message.invitationStatus}` });
        }

        // Check if chat subscription is active
        const { getChatSessionStatus } = require('./chatSubscriptionController');
        const sessionStatus = await getChatSessionStatus(id, userId);
        if (!sessionStatus.canChat) {
            return res.status(403).json({ success: false, message: 'Chat session has expired or is locked' });
        }

        const newStatus = action === 'accept' ? InvitationStatus.ACCEPTED : InvitationStatus.DECLINED;
        await (message as any).update({ invitationStatus: newStatus });

        // Auto-send a status message in the conversation
        const statusText = action === 'accept'
            ? '✅ Invitation accepted!'
            : '❌ Invitation declined.';

        await Message.create({
            conversationId: id,
            senderId:       userId,
            type:           MessageType.TEXT,
            content:        statusText,
            status:         MessageStatus.SENT,
        });

        return res.json({
            success: true,
            message: `Invitation ${newStatus}`,
            data: { messageId: msgId, invitationStatus: newStatus },
        });
    } catch (err: any) {
        logger.error('respondToInvitation:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── GET /icebreakers — List icebreaker prompts ───────────────────────────────
export const getIcebreakers = async (_req: Request, res: Response) => {
    try {
        return res.json({ success: true, count: ICEBREAKERS.length, data: ICEBREAKERS });
    } catch (err: any) {
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── PATCH /conversations/:id/read — Mark all as read ────────────────────────
export const markConversationRead = async (req: Request, res: Response) => {
    try {
        const { id }   = req.params;
        const { userId } = req.body;
        if (!userId) return res.status(400).json({ success: false, message: 'userId is required' });

        const conv = await Conversation.findByPk(id);
        if (!conv) return res.status(404).json({ success: false, message: 'Conversation not found' });

        await Message.update(
            { status: MessageStatus.READ, readAt: new Date() },
            { where: { conversationId: id, senderId: { [Op.ne]: userId }, status: { [Op.ne]: MessageStatus.READ } } }
        );

        const resetField = (conv.participantOne && userId && conv.participantOne.toLowerCase() === userId.toLowerCase()) ? { unreadOne: 0 } : { unreadTwo: 0 };
        await (conv as any).update(resetField);

        try {
            const { io } = require('../server');
            const otherUserId = conv.getOtherParticipant(userId);
            io.to(`user_${otherUserId}`).emit('messages_read', { conversationId: id, readAt: new Date() });

            // Emit chat_badge_updated to current user so their badge and row clear immediately
            const myConvs = await Conversation.findAll({
                where: {
                    [Op.or]: [
                        { participantOne: userId },
                        { participantTwo: userId }
                    ],
                    status: { [Op.ne]: ConversationStatus.BLOCKED }
                },
                attributes: ['id', 'participantOne', 'participantTwo', 'unreadOne', 'unreadTwo', 'deletedByOne', 'deletedByTwo']
            });
            let myRemainingChatCount = 0;
            for (const c of myConvs) {
                const isP1 = (c.participantOne || '').toLowerCase() === userId.toLowerCase();
                const isP2 = (c.participantTwo || '').toLowerCase() === userId.toLowerCase();
                if (isP1 && (c as any).deletedByOne) continue;
                if (isP2 && (c as any).deletedByTwo) continue;
                myRemainingChatCount += Number(c.getUnreadFor ? c.getUnreadFor(userId) : (isP1 ? ((c as any).unreadOne || 0) : ((c as any).unreadTwo || 0)));
            }
            io.to(`user_${userId}`).emit('chat_badge_updated', {
                conversationId: id,
                chatCount: myRemainingChatCount,
                unreadCount: 0
            });
        } catch (err) {
            logger.error('Failed to emit messages_read / chat_badge_updated socket event:', err);
        }

        return res.json({ success: true, message: 'Conversation marked as read' });
    } catch (err: any) {
        logger.error('markConversationRead:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── DELETE /conversations/:id/messages/:msgId — Soft-delete message ─────────
export const deleteMessage = async (req: Request, res: Response) => {
    try {
        await ensureConversationColumns();
        const { id, msgId } = req.params;
        const { userId, deleteForEveryone = true } = req.body;
        if (!userId) return res.status(400).json({ success: false, message: 'userId is required' });

        const message = await Message.findOne({ where: { id: msgId, conversationId: id } });
        if (!message) return res.status(404).json({ success: false, message: 'Message not found' });

        const conv = await Conversation.findByPk(id);
        if (!conv) return res.status(404).json({ success: false, message: 'Conversation not found' });

        const uId = userId.toLowerCase();
        const p1 = (conv.participantOne || '').toLowerCase();
        const p2 = (conv.participantTwo || '').toLowerCase();
        if (p1 !== uId && p2 !== uId) {
            return res.status(403).json({ success: false, message: 'Access denied' });
        }

        const isSender = message.senderId.toLowerCase() === uId;
        const otherUserId = conv.getOtherParticipant(userId);

        // Find ALL conversation rows between these two participants
        const allConvs = await Conversation.findAll({
            where: {
                [Op.or]: [
                    { participantOne: conv.participantOne, participantTwo: conv.participantTwo },
                    { participantOne: conv.participantTwo, participantTwo: conv.participantOne },
                ],
            },
        });
        const allConvIds = allConvs.map(c => c.id);

        if (deleteForEveryone === true) {
            // Delete for everyone — only the sender is authorized (WhatsApp behavior)
            if (!isSender) {
                return res.status(403).json({
                    success: false,
                    message: 'You can only delete your own messages for everyone',
                });
            }

            await (message as any).update({ deletedAt: new Date(), content: null, mediaUrl: null });

            // Find the new latest non-deleted message across the conversations
            const remainingMessages = await Message.findAll({
                where: {
                    conversationId: { [Op.in]: allConvIds },
                    deletedAt: null as any,
                },
                order: [['createdAt', 'DESC']],
                limit: 10,
            });

            const latestMsg = remainingMessages.length > 0 ? remainingMessages[0] : null;
            const newPreview = latestMsg ? latestMsg.getPreview() : '';
            const newLastMsgAt = latestMsg ? latestMsg.createdAt : null;
            const newLastMsgId = latestMsg ? latestMsg.id : null;

            for (const c of allConvs) {
                await (c as any).update({
                    lastMessageId: newLastMsgId,
                    lastMessagePreview: newPreview,
                    lastMessageAt: newLastMsgAt,
                });
            }

            // Real-time socket broadcast to both participants
            try {
                const { io } = require('../server');
                const deletePayload = {
                    conversationId: id,
                    messageId: msgId,
                    deleteForEveryone: true,
                    lastMessagePreview: newPreview,
                    lastMessageAt: newLastMsgAt,
                    hasRemainingMessages: !!latestMsg,
                };
                io.to(`user_${userId}`).emit('message_deleted', deletePayload);
                if (otherUserId) {
                    io.to(`user_${otherUserId}`).emit('message_deleted', deletePayload);
                }
            } catch (err) {
                logger.error('Failed to emit message_deleted socket event:', err);
            }

            return res.json({
                success: true,
                message: 'Message deleted for everyone successfully',
                data: {
                    messageId: msgId,
                    conversationId: id,
                    deleteForEveryone: true,
                    lastMessagePreview: newPreview,
                    lastMessageAt: newLastMsgAt,
                },
            });
        } else {
            // Delete for me — hide message only for the requesting user
            let deletedForUsers: string[] = [];
            const rawDfu = (message as any).deletedForUsers;
            if (Array.isArray(rawDfu)) {
                deletedForUsers = [...rawDfu];
            } else if (typeof rawDfu === 'string') {
                try { deletedForUsers = JSON.parse(rawDfu); } catch (_) {}
            }
            if (!deletedForUsers.map(x => String(x).toLowerCase()).includes(uId)) {
                deletedForUsers.push(userId);
                await (message as any).update({ deletedForUsers });
            }

            // Find the new latest remaining message for THIS user (excluding messages in deletedForUsers)
            const remainingMessages = await Message.findAll({
                where: {
                    conversationId: { [Op.in]: allConvIds },
                    deletedAt: null as any,
                },
                order: [['createdAt', 'DESC']],
                limit: 50,
            });

            const userRemainingMessages = remainingMessages.filter(m => {
                const dfu = (m as any).deletedForUsers;
                if (!dfu) return true;
                if (Array.isArray(dfu)) {
                    return !dfu.map((x: any) => String(x).toLowerCase()).includes(uId);
                }
                if (typeof dfu === 'string') {
                    try {
                        const parsed = JSON.parse(dfu);
                        return Array.isArray(parsed) ? !parsed.map((x: any) => String(x).toLowerCase()).includes(uId) : true;
                    } catch (_) { return true; }
                }
                return true;
            });

            const latestUserMsg = userRemainingMessages.length > 0 ? userRemainingMessages[0] : null;
            const newPreview = latestUserMsg ? latestUserMsg.getPreview() : '';
            const newLastMsgAt = latestUserMsg ? latestUserMsg.createdAt : null;

            // NOTE: "Delete for me" only hides the message for the requesting user.
            // The conversation's shared lastMessageId/lastMessagePreview/lastMessageAt
            // columns represent the true last message for BOTH participants and must
            // NOT be overwritten here — otherwise the other participant's chat list
            // preview gets corrupted with a message they never deleted. getConversations
            // computes each user's effective preview dynamically instead.

            // Real-time socket broadcast ONLY to requesting user
            try {
                const { io } = require('../server');
                const deletePayload = {
                    conversationId: id,
                    messageId: msgId,
                    deleteForEveryone: false,
                    targetUserId: userId,
                    lastMessagePreview: newPreview,
                    lastMessageAt: newLastMsgAt,
                    hasRemainingMessages: !!latestUserMsg,
                };
                io.to(`user_${userId}`).emit('message_deleted', deletePayload);
            } catch (err) {
                logger.error('Failed to emit message_deleted socket event:', err);
            }

            return res.json({
                success: true,
                message: 'Message deleted for you successfully',
                data: {
                    messageId: msgId,
                    conversationId: id,
                    deleteForEveryone: false,
                    lastMessagePreview: newPreview,
                    lastMessageAt: newLastMsgAt,
                },
            });
        }
    } catch (err: any) {
        logger.error('deleteMessage:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── POST /conversations/:id/messages/batch-delete — Batch delete messages ───
export const batchDeleteMessages = async (req: Request, res: Response) => {
    try {
        await ensureConversationColumns();
        const { id } = req.params;
        const { userId, messageIds, deleteForEveryone = false } = req.body;

        if (!userId) return res.status(400).json({ success: false, message: 'userId is required' });
        if (!Array.isArray(messageIds) || messageIds.length === 0) {
            return res.status(400).json({ success: false, message: 'messageIds array is required and must not be empty' });
        }

        const conv = await Conversation.findByPk(id);
        if (!conv) return res.status(404).json({ success: false, message: 'Conversation not found' });

        const uId = userId.toLowerCase();
        const p1 = (conv.participantOne || '').toLowerCase();
        const p2 = (conv.participantTwo || '').toLowerCase();
        if (p1 !== uId && p2 !== uId) {
            return res.status(403).json({ success: false, message: 'Access denied' });
        }

        const otherUserId = conv.getOtherParticipant(userId);

        // Find all conversation rows between these two participants
        const allConvs = await Conversation.findAll({
            where: {
                [Op.or]: [
                    { participantOne: conv.participantOne, participantTwo: conv.participantTwo },
                    { participantOne: conv.participantTwo, participantTwo: conv.participantOne },
                ],
            },
        });
        const allConvIds = allConvs.map(c => c.id);

        const targetMessages = await Message.findAll({
            where: {
                id: { [Op.in]: messageIds },
                conversationId: { [Op.in]: allConvIds },
            },
        });

        if (targetMessages.length === 0) {
            return res.status(404).json({ success: false, message: 'No matching messages found' });
        }

        if (deleteForEveryone === true) {
            // Delete for everyone — verify all selected messages were sent by the requesting user
            const unauthorized = targetMessages.some(m => m.senderId.toLowerCase() !== uId);
            if (unauthorized) {
                return res.status(403).json({
                    success: false,
                    message: 'You can only delete your own messages for everyone',
                });
            }

            const validIds = targetMessages.map(m => m.id);
            await (Message as any).update(
                { deletedAt: new Date(), content: null, mediaUrl: null },
                { where: { id: { [Op.in]: validIds } } }
            );

            // Recalculate latest message across conversations
            const remainingMessages = await Message.findAll({
                where: {
                    conversationId: { [Op.in]: allConvIds },
                    deletedAt: null as any,
                },
                order: [['createdAt', 'DESC']],
                limit: 10,
            });

            const latestMsg = remainingMessages.length > 0 ? remainingMessages[0] : null;
            const newPreview = latestMsg ? latestMsg.getPreview() : '';
            const newLastMsgAt = latestMsg ? latestMsg.createdAt : null;
            const newLastMsgId = latestMsg ? latestMsg.id : null;

            for (const c of allConvs) {
                await (c as any).update({
                    lastMessageId: newLastMsgId,
                    lastMessagePreview: newPreview,
                    lastMessageAt: newLastMsgAt,
                });
            }

            // Real-time socket broadcast to both participants
            try {
                const { io } = require('../server');
                const deletePayload = {
                    conversationId: id,
                    messageIds: validIds,
                    deleteForEveryone: true,
                    lastMessagePreview: newPreview,
                    lastMessageAt: newLastMsgAt,
                    hasRemainingMessages: !!latestMsg,
                };
                io.to(`user_${userId}`).emit('messages_batch_deleted', deletePayload);
                if (otherUserId) {
                    io.to(`user_${otherUserId}`).emit('messages_batch_deleted', deletePayload);
                }
            } catch (err) {
                logger.error('Failed to emit messages_batch_deleted socket event:', err);
            }

            return res.json({
                success: true,
                message: `${validIds.length} messages deleted for everyone successfully`,
                data: {
                    messageIds: validIds,
                    conversationId: id,
                    deleteForEveryone: true,
                    lastMessagePreview: newPreview,
                    lastMessageAt: newLastMsgAt,
                },
            });
        } else {
            // Delete for me — hide messages only for the requesting user
            const validIds: string[] = [];
            for (const m of targetMessages) {
                let deletedForUsers: string[] = [];
                const rawDfu = (m as any).deletedForUsers;
                if (Array.isArray(rawDfu)) {
                    deletedForUsers = [...rawDfu];
                } else if (typeof rawDfu === 'string') {
                    try { deletedForUsers = JSON.parse(rawDfu); } catch (_) {}
                }
                if (!deletedForUsers.map(x => String(x).toLowerCase()).includes(uId)) {
                    deletedForUsers.push(userId);
                    await (m as any).update({ deletedForUsers });
                }
                validIds.push(m.id);
            }

            // Real-time socket broadcast ONLY to requesting user
            try {
                const { io } = require('../server');
                const deletePayload = {
                    conversationId: id,
                    messageIds: validIds,
                    deleteForEveryone: false,
                    targetUserId: userId,
                };
                io.to(`user_${userId}`).emit('messages_batch_deleted', deletePayload);
            } catch (err) {
                logger.error('Failed to emit messages_batch_deleted socket event:', err);
            }

            return res.json({
                success: true,
                message: `${validIds.length} messages deleted for you successfully`,
                data: {
                    messageIds: validIds,
                    conversationId: id,
                    deleteForEveryone: false,
                },
            });
        }
    } catch (err: any) {
        logger.error('batchDeleteMessages error:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── DELETE /conversations/:id/messages — Clear all messages in conversation ──
export const clearChat = async (req: Request, res: Response) => {
    try {
        await ensureConversationColumns();
        const { id } = req.params;
        const { userId, clearForEveryone } = req.body;
        if (!userId) return res.status(400).json({ success: false, message: 'userId is required' });

        let conv = await Conversation.findByPk(id);
        if (!conv) {
            // Check if id is otherUserId
            conv = await Conversation.findOne({
                where: {
                    [Op.or]: [
                        { participantOne: userId, participantTwo: id },
                        { participantOne: id, participantTwo: userId },
                    ],
                },
            });
        }
        if (!conv) return res.status(404).json({ success: false, message: 'Conversation not found' });

        const uId = userId.toLowerCase();
        const p1 = (conv.participantOne || '').toLowerCase();
        const p2 = (conv.participantTwo || '').toLowerCase();
        if (p1 !== uId && p2 !== uId) {
            return res.status(403).json({ success: false, message: 'Access denied' });
        }

        const otherUserId = conv.getOtherParticipant(userId);

        // Find ALL conversation IDs between these two participants
        const allConvs = await Conversation.findAll({
            where: {
                [Op.or]: [
                    { participantOne: conv.participantOne, participantTwo: conv.participantTwo },
                    { participantOne: conv.participantTwo, participantTwo: conv.participantOne },
                ],
            },
        });
        const allConvIds = allConvs.map(c => c.id);

        const now = new Date();
        for (const c of allConvs) {
            const isP1 = (c.participantOne || '').toLowerCase() === uId;
            if (clearForEveryone === true) {
                await (c as any).update({
                    clearedAtOne: now,
                    clearedAtTwo: now,
                    lastMessagePreview: '',
                    unreadOne: 0,
                    unreadTwo: 0,
                });
            } else if (isP1) {
                await (c as any).update({
                    clearedAtOne: now,
                    unreadOne: 0,
                });
            } else {
                await (c as any).update({
                    clearedAtTwo: now,
                    unreadTwo: 0,
                });
            }
        }

        if (clearForEveryone === true) {
            await Message.update(
                { deletedAt: now, content: null as any, mediaUrl: null as any },
                { where: { conversationId: { [Op.in]: allConvIds } } }
            );
        }

        try {
            const { io } = require('../server');
            for (const convId of allConvIds) {
                io.to(`user_${userId}`).emit('chat_cleared', { conversationId: convId, otherUserId });
                if (clearForEveryone) {
                    io.to(`user_${otherUserId}`).emit('chat_cleared', { conversationId: convId, otherUserId: userId });
                }
            }

            const myConvs = await Conversation.findAll({
                where: {
                    [Op.or]: [
                        { participantOne: userId },
                        { participantTwo: userId }
                    ],
                    status: { [Op.ne]: ConversationStatus.BLOCKED }
                },
                attributes: ['id', 'participantOne', 'participantTwo', 'unreadOne', 'unreadTwo', 'deletedByOne', 'deletedByTwo', 'clearedAtOne', 'clearedAtTwo', 'lastMessageAt']
            });
            let myRemainingChatCount = 0;
            for (const c of myConvs) {
                const isP1 = (c.participantOne || '').toLowerCase() === userId.toLowerCase();
                const isP2 = (c.participantTwo || '').toLowerCase() === userId.toLowerCase();
                if (isP1 && (c as any).deletedByOne) continue;
                if (isP2 && (c as any).deletedByTwo) continue;
                const cTime = isP1
                    ? ((c as any).clearedAtOne ? new Date((c as any).clearedAtOne).getTime() : 0)
                    : ((c as any).clearedAtTwo ? new Date((c as any).clearedAtTwo).getTime() : 0);
                const lmTime = c.lastMessageAt ? new Date(c.lastMessageAt).getTime() : 0;
                if (cTime > 0 && lmTime <= cTime) continue;
                myRemainingChatCount += Number(c.getUnreadFor ? c.getUnreadFor(userId) : (isP1 ? ((c as any).unreadOne || 0) : ((c as any).unreadTwo || 0)));
            }
            for (const convId of allConvIds) {
                io.to(`user_${userId}`).emit('chat_badge_updated', {
                    conversationId: convId,
                    chatCount: myRemainingChatCount,
                    unreadCount: 0
                });
            }
        } catch (err) {
            logger.error('Failed to emit chat_cleared / chat_badge_updated socket event:', err);
        }

        return res.json({ success: true, message: 'Chat cleared successfully' });
    } catch (err: any) {
        logger.error('clearChat:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── DELETE /conversations/:id — Delete entire conversation / user from chat ───
export const deleteConversation = async (req: Request, res: Response) => {
    try {
        await ensureConversationColumns();
        const { id } = req.params;
        const { userId, deleteForEveryone } = req.body;
        if (!userId) return res.status(400).json({ success: false, message: 'userId is required' });

        let conv = await Conversation.findByPk(id);
        if (!conv) {
            // Check if id is otherUserId
            conv = await Conversation.findOne({
                where: {
                    [Op.or]: [
                        { participantOne: userId, participantTwo: id },
                        { participantOne: id, participantTwo: userId },
                    ],
                },
            });
        }
        if (!conv) return res.status(404).json({ success: false, message: 'Conversation not found' });

        const uId = userId.toLowerCase();
        const p1 = (conv.participantOne || '').toLowerCase();
        const p2 = (conv.participantTwo || '').toLowerCase();
        if (p1 !== uId && p2 !== uId) {
            return res.status(403).json({ success: false, message: 'Access denied' });
        }

        const otherUserId = conv.getOtherParticipant(userId);

        // Find ALL conversation rows between these two participants
        const allConvs = await Conversation.findAll({
            where: {
                [Op.or]: [
                    { participantOne: conv.participantOne, participantTwo: conv.participantTwo },
                    { participantOne: conv.participantTwo, participantTwo: conv.participantOne },
                ],
            },
        });
        const allConvIds = allConvs.map(c => c.id);

        const now = new Date();
        for (const c of allConvs) {
            const isP1 = (c.participantOne || '').toLowerCase() === uId;
            if (deleteForEveryone === true) {
                await (c as any).update({
                    deletedByOne: true,
                    deletedByTwo: true,
                    clearedAtOne: now,
                    clearedAtTwo: now,
                    unreadOne: 0,
                    unreadTwo: 0,
                    lastMessagePreview: '',
                });
            } else if (isP1) {
                await (c as any).update({
                    deletedByOne: true,
                    clearedAtOne: now,
                    unreadOne: 0,
                });
            } else {
                await (c as any).update({
                    deletedByTwo: true,
                    clearedAtTwo: now,
                    unreadTwo: 0,
                });
            }
        }

        if (deleteForEveryone === true) {
            await Message.update(
                { deletedAt: now, content: null as any, mediaUrl: null as any },
                { where: { conversationId: { [Op.in]: allConvIds } } }
            );
        }

        try {
            const { io } = require('../server');
            for (const convId of allConvIds) {
                io.to(`user_${userId}`).emit('conversation_deleted', { conversationId: convId, otherUserId });
                io.to(`user_${userId}`).emit('chat_cleared', { conversationId: convId, otherUserId });
                if (deleteForEveryone) {
                    io.to(`user_${otherUserId}`).emit('conversation_deleted', { conversationId: convId, otherUserId: userId });
                    io.to(`user_${otherUserId}`).emit('chat_cleared', { conversationId: convId, otherUserId: userId });
                }
            }
        } catch (err) {
            logger.error('Failed to emit conversation_deleted socket event:', err);
        }

        return res.json({ success: true, message: 'Conversation deleted successfully' });
    } catch (err: any) {
        logger.error('deleteConversation:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── GET /conversations/:id/search — Search messages in conversation ─────────
export const searchMessages = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const userId = req.query.userId as string;
        const query = (req.query.query as string || '').trim();

        if (!userId) return res.status(400).json({ success: false, message: 'userId is required' });
        if (!query) return res.json({ success: true, count: 0, data: [] });

        const conv = await Conversation.findByPk(id);
        if (!conv) return res.status(404).json({ success: false, message: 'Conversation not found' });

        const messages = await Message.findAll({
            where: {
                conversationId: id,
                deletedAt: null as any,
                [Op.or]: [
                    { content: { [Op.iLike]: `%${query}%` } },
                    { type: { [Op.iLike]: `%${query}%` } },
                    { invitationTime: { [Op.iLike]: `%${query}%` } },
                ],
            },
            include: [{
                model: User, as: 'sender',
                attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                include: [{
                    model: UserPhoto, as: 'photos',
                    where: { isPrimary: true },
                    attributes: ['id', 'filePath', 'userId'],
                    required: false,
                }],
            }],
            order: [['createdAt', 'DESC']],
            limit: 50,
        });

        return res.json({
            success: true,
            count: messages.length,
            data: messages.map(m => formatMessage(m)),
        });
    } catch (err: any) {
        logger.error('searchMessages:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── Helper: format a message for the response ────────────────────────────────
function formatMessage(m: Message) {
    return {
        id:               m.id,
        conversationId:   m.conversationId,
        senderId:         m.senderId,
        clientMessageId:  m.clientMessageId ?? null,
        sender:           (m as any).sender ? formatUserBrief((m as any).sender) : undefined,
        type:             m.type,
        content:          m.deletedAt ? '[Message deleted]' : (m.content ?? null),
        mediaUrl:         m.deletedAt ? null : (m.mediaUrl ?? null),
        mediaMimeType:    m.mediaMimeType ?? null,
        duration:         m.duration ?? null,
        fileSize:         m.fileSize ?? null,
        waveformData:     m.waveformData ?? null,
        replyToMessageId: m.replyToMessageId ?? null,
        // Invitation fields
        invitationRef:    m.invitationRef ?? null,
        invitationRefType:m.invitationRefType ?? null,
        invitationTime:   m.invitationTime ?? null,
        invitationStatus: m.invitationStatus ?? null,
        // Status
        status:           m.status,
        readAt:           m.readAt ?? null,
        isDeleted:        !!m.deletedAt,
        createdAt:        m.createdAt,
    };
}

export default {
    getConversations,
    getOrCreateConversation,
    getMessages,
    sendMessage,
    respondToInvitation,
    getIcebreakers,
    markConversationRead,
    deleteMessage,
    batchDeleteMessages,
    clearChat,
    deleteConversation,
    searchMessages,
};
