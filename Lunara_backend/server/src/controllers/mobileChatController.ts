import { Request, Response } from 'express';
import { Op } from 'sequelize';
import Conversation, { ConversationStatus } from '../models/Conversation';
import Message, { MessageType, MessageStatus, InvitationStatus } from '../models/Message';
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

// ─── GET /conversations — Chat list ──────────────────────────────────────────
export const getConversations = async (req: Request, res: Response) => {
    try {
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
                        limit: 1,
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
                        limit: 1,
                    }],
                },
            ],
            order: [['lastMessageAt', 'DESC NULLS LAST']],
        });

        const list = conversations.map(conv => {
            const otherUserId = conv.getOtherParticipant(userId);
            const otherUser = otherUserId === conv.participantOne
                ? (conv as any).userOne
                : (conv as any).userTwo;

            return {
                conversationId:      conv.id,
                otherUser:           formatUserBrief(otherUser),
                lastMessagePreview:  conv.lastMessagePreview ?? '',
                lastMessageAt:       conv.lastMessageAt,
                unreadCount:         conv.getUnreadFor(userId),
                status:              conv.status,
                contextType:         conv.contextType,
                contextId:           conv.contextId,
            };
        });

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
        if (userId === otherUserId) {
            return res.status(400).json({ success: false, message: 'Cannot create conversation with yourself' });
        }

        // Normalize participant order (smaller UUID first) to enforce the unique constraint
        const [p1, p2] = [userId, otherUserId].sort();

        const [conversation, created] = await Conversation.findOrCreate({
            where: { participantOne: p1, participantTwo: p2 },
            defaults: {
                participantOne: p1,
                participantTwo: p2,
                contextType,
                contextId,
            },
        });

        const otherUser = await User.findByPk(otherUserId, {
            attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
            include: [{
                model: UserPhoto,
                as: 'photos',
                where: { isPrimary: true },
                attributes: ['id', 'filePath', 'userId'],
                required: false,
                limit: 1,
            }],
        });

        return res.status(created ? 201 : 200).json({
            success: true,
            message: created ? 'Conversation created' : 'Conversation retrieved',
            data: {
                conversationId: conversation.id,
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
        if (conv.participantOne !== userId && conv.participantTwo !== userId) {
            return res.status(403).json({ success: false, message: 'Access denied' });
        }

        const where: any = {
            conversationId: id,
            deletedAt: null,
        };
        if (before) where.createdAt = { [Op.lt]: new Date(before) };

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
                    limit: 1,
                }],
            }],
            order: [['createdAt', 'DESC']],
            limit,
        });

        // Mark unread messages as read
        const unreadIds = messages
            .filter(m => m.senderId !== userId && m.status !== MessageStatus.READ)
            .map(m => m.id);

        if (unreadIds.length > 0) {
            await Message.update(
                { status: MessageStatus.READ, readAt: new Date() },
                { where: { id: { [Op.in]: unreadIds } } }
            );
            // Reset caller's unread count
            const resetField = conv.participantOne === userId ? { unreadOne: 0 } : { unreadTwo: 0 };
            await (conv as any).update(resetField);
            
            // Emit read receipt to the sender
            try {
                const { io } = require('../server');
                const otherUserId = conv.getOtherParticipant(userId);
                io.to(`user_${otherUserId}`).emit('messages_read', { conversationId: id, readAt: new Date() });
            } catch (err) {
                logger.error('Failed to emit messages_read socket event:', err);
            }
        }

        // Return in chronological order (oldest first for chat display)
        const ordered = [...messages].reverse();

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
            type = MessageType.TEXT,
            content,
            mediaUrl,
            mediaMimeType,
            invitationRef,
            invitationRefType,
            invitationTime,
        } = req.body;

        if (!senderId) return res.status(400).json({ success: false, message: 'senderId is required' });

        const conv = await Conversation.findByPk(id);
        if (!conv) return res.status(404).json({ success: false, message: 'Conversation not found' });
        if (conv.participantOne !== senderId && conv.participantTwo !== senderId) {
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
        if ([MessageType.IMAGE, MessageType.STICKER].includes(type) && !mediaUrl) {
            return res.status(400).json({ success: false, message: 'mediaUrl is required for image/sticker messages' });
        }
        if (type === MessageType.INVITATION && (!invitationRef || !invitationTime)) {
            return res.status(400).json({ success: false, message: 'invitationRef and invitationTime are required for invitation messages' });
        }

        const recipientId = conv.getOtherParticipant(senderId);
        let isRecipientOnline = false;
        try {
            const { io } = require('../server');
            const recipientRoom = io.sockets.adapter.rooms.get(`user_${recipientId}`);
            isRecipientOnline = recipientRoom && recipientRoom.size > 0;
        } catch (err) {}

        const message = await Message.create({
            conversationId: id,
            senderId,
            type,
            content,
            mediaUrl,
            mediaMimeType,
            invitationRef,
            invitationRefType,
            invitationTime,
            invitationStatus: type === MessageType.INVITATION ? InvitationStatus.PENDING : undefined,
            status: isRecipientOnline ? MessageStatus.DELIVERED : MessageStatus.SENT,
        });

        // Build preview text
        const preview = message.getPreview();

        // Increment unread for the OTHER participant
        const isOne = conv.participantOne === senderId;
        const unreadUpdate = isOne
            ? { unreadTwo: conv.unreadTwo + 1 }
            : { unreadOne: conv.unreadOne + 1 };

        await (conv as any).update({
            lastMessageId:      message.id,
            lastMessageAt:      message.createdAt,
            lastMessagePreview: preview,
            ...unreadUpdate,
        });

        // Emit new_message to recipient
        try {
            const { io } = require('../server');
            if (isRecipientOnline) {
                io.to(`user_${recipientId}`).emit('new_message', formatMessage(message as any));
                io.to(`user_${senderId}`).emit('messages_delivered', { conversationId: id });
            }
        } catch (err) {
            logger.error('Failed to emit new_message socket event:', err);
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

        const resetField = conv.participantOne === userId ? { unreadOne: 0 } : { unreadTwo: 0 };
        await (conv as any).update(resetField);

        try {
            const { io } = require('../server');
            const otherUserId = conv.getOtherParticipant(userId);
            io.to(`user_${otherUserId}`).emit('messages_read', { conversationId: id, readAt: new Date() });
        } catch (err) {
            logger.error('Failed to emit messages_read socket event:', err);
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
        const { id, msgId } = req.params;
        const { userId }    = req.body;

        const message = await Message.findOne({ where: { id: msgId, conversationId: id } });
        if (!message) return res.status(404).json({ success: false, message: 'Message not found' });
        if (message.senderId !== userId) {
            return res.status(403).json({ success: false, message: 'You can only delete your own messages' });
        }

        await (message as any).update({ deletedAt: new Date(), content: null, mediaUrl: null });

        return res.json({ success: true, message: 'Message deleted' });
    } catch (err: any) {
        logger.error('deleteMessage:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── Helper: format a message for the response ────────────────────────────────
function formatMessage(m: Message) {
    return {
        id:               m.id,
        conversationId:   m.conversationId,
        senderId:         m.senderId,
        sender:           (m as any).sender ? formatUserBrief((m as any).sender) : undefined,
        type:             m.type,
        content:          m.deletedAt ? '[Message deleted]' : (m.content ?? null),
        mediaUrl:         m.deletedAt ? null : (m.mediaUrl ?? null),
        mediaMimeType:    m.mediaMimeType ?? null,
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
};
