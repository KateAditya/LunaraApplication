import { Request, Response } from 'express';
import { Conversation, Message, User } from '../models';
import ChatSubscription, { ChatSubscriptionStatus, ChatSubscriptionType } from '../models/ChatSubscription';
import { logger } from '../config/logger';

// ── Admin-configurable settings (defaults, overridable via DB/env) ─────────────
const DEFAULT_FREE_DAYS     = parseInt(process.env.CHAT_FREE_DAYS      || '7');
const DEFAULT_EXTENSION_DAYS  = parseInt(process.env.CHAT_EXTENSION_DAYS  || '7');
const DEFAULT_EXTENSION_PRICE = parseFloat(process.env.CHAT_EXTENSION_PRICE || '100');

// In-memory settings store (in production, persist these in DB/Redis)
let chatSettings = {
    freeDays:       DEFAULT_FREE_DAYS,
    extensionDays:  DEFAULT_EXTENSION_DAYS,
    extensionPrice: DEFAULT_EXTENSION_PRICE,
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/settings/chat
// ─────────────────────────────────────────────────────────────────────────────
export const getAdminChatSettings = async (_req: Request, res: Response): Promise<Response> => {
    return res.json({ success: true, data: chatSettings });
};

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/admin/settings/chat
// ─────────────────────────────────────────────────────────────────────────────
export const updateAdminChatSettings = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { freeDays, extensionDays, extensionPrice } = req.body;
        if (freeDays      !== undefined) chatSettings.freeDays       = Number(freeDays);
        if (extensionDays  !== undefined) chatSettings.extensionDays   = Number(extensionDays);
        if (extensionPrice !== undefined) chatSettings.extensionPrice  = Number(extensionPrice);
        return res.json({ success: true, data: chatSettings });
    } catch (err) {
        logger.error('updateAdminChatSettings error', err);
        return res.status(500).json({ success: false, message: 'Failed to update settings' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// Helper: get current settings
// ─────────────────────────────────────────────────────────────────────────────
export const getChatSettings = () => chatSettings;

// ─────────────────────────────────────────────────────────────────────────────
// Helper: get or compute session status for a conversation
// Returns { canChat, expiresAt, daysLeft, isFree, subscriptionId }
// ─────────────────────────────────────────────────────────────────────────────
export async function getChatSessionStatus(_conversationId: string, _userId: string) {
    // Legacy subscription gating has been deprecated. All matched chat sessions are free.
    const infiniteExpiry = new Date();
    infiniteExpiry.setFullYear(infiniteExpiry.getFullYear() + 10); // 10 years in the future
    return {
        canChat: true,
        expiresAt: infiniteExpiry,
        daysLeft: 3650,
        isFree: true,
        subscriptionId: 'free_unlimited'
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/chat/init-free   (called when a match is created)
// Body: { conversationId, userId }
// ─────────────────────────────────────────────────────────────────────────────
export const initFreeChat = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { conversationId, userId } = req.body;
        if (!conversationId || !userId) {
            return res.status(400).json({ success: false, message: 'conversationId and userId are required' });
        }

        // Check if free subscription already exists for this conversation
        const existing = await ChatSubscription.findOne({
            where: { conversationId, subscriptionType: ChatSubscriptionType.FREE },
        });

        if (existing) {
            return res.json({ success: true, data: existing });
        }

        const freeDays = chatSettings.freeDays;
        const validUntil = new Date();
        validUntil.setDate(validUntil.getDate() + freeDays);

        const sub = await ChatSubscription.create({
            conversationId,
            paidById: userId,
            amount: 0,
            daysGranted: freeDays,
            validUntil,
            status: ChatSubscriptionStatus.ACTIVE,
            subscriptionType: ChatSubscriptionType.FREE,
        });

        return res.json({ success: true, data: sub });
    } catch (err) {
        logger.error('initFreeChat error', err);
        return res.status(500).json({ success: false, message: 'Failed to init free chat' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/chat/session-status/:conversationId
// ─────────────────────────────────────────────────────────────────────────────
export const getSessionStatus = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { conversationId } = req.params;
        const userId = (req.user as any)?.id || req.query.userId as string;
        if (!conversationId) {
            return res.status(400).json({ success: false, message: 'conversationId is required' });
        }

        const conv = await Conversation.findByPk(conversationId);
        if (!conv) {
            return res.status(404).json({ success: false, message: 'Conversation not found' });
        }
        if (userId && conv.participantOne !== userId && conv.participantTwo !== userId) {
            return res.status(403).json({ success: false, message: 'Access denied' });
        }

        const status = await getChatSessionStatus(conversationId, userId);
        return res.json({
            success: true,
            data: {
                ...status,
                settings: chatSettings,
            },
        });
    } catch (err) {
        logger.error('getSessionStatus error', err);
        return res.status(500).json({ success: false, message: 'Failed to get session status' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/chat/extend
// Body: { conversationId, userId, paymentId } (paymentId from Razorpay)
// ─────────────────────────────────────────────────────────────────────────────
export const extendChat = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { conversationId, userId, paymentId: _paymentId } = req.body;
        if (!conversationId || !userId) {
            return res.status(400).json({ success: false, message: 'conversationId and userId are required' });
        }

        const { extensionDays, extensionPrice } = chatSettings;

        // Find the latest valid sub to extend from, or use now as base
        const latestSub = await ChatSubscription.findOne({
            where: { conversationId, status: ChatSubscriptionStatus.ACTIVE },
            order: [['valid_until', 'DESC']],
        });

        const baseDate = latestSub && latestSub.validUntil > new Date()
            ? latestSub.validUntil
            : new Date();

        const validUntil = new Date(baseDate);
        validUntil.setDate(validUntil.getDate() + extensionDays);

        const sub = await ChatSubscription.create({
            conversationId,
            paidById: userId,
            amount: extensionPrice,
            daysGranted: extensionDays,
            validUntil,
            status: ChatSubscriptionStatus.ACTIVE,
            subscriptionType: ChatSubscriptionType.PAID,
        });

        // Send a system message in the conversation indicating extension
        const conv = await Conversation.findByPk(conversationId);
        if (conv) {
            await Message.create({
                conversationId,
                senderId: userId,
                type: 'system',
                content: `💬 Chat extended for ${extensionDays} more days.`,
            } as any);
        }

        return res.json({ success: true, data: sub });
    } catch (err) {
        logger.error('extendChat error', err);
        return res.status(500).json({ success: false, message: 'Failed to extend chat' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/chat/request-extension
// Body: { conversationId, requesterId, targetUserId }
// Sends a special message requesting the other user to pay
// ─────────────────────────────────────────────────────────────────────────────
export const requestExtension = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { conversationId, requesterId, targetUserId } = req.body;
        if (!conversationId || !requesterId || !targetUserId) {
            return res.status(400).json({ success: false, message: 'conversationId, requesterId, and targetUserId are required' });
        }

        // Get requester name
        const requester = await User.findByPk(requesterId, { attributes: ['firstName', 'lastName'] });
        const requesterName = requester ? `${requester.firstName} ${requester.lastName}`.trim() : 'Your match';

        const { extensionDays, extensionPrice } = chatSettings;

        // Send a special pay_request message type
        const msg = await Message.create({
            conversationId,
            senderId: requesterId,
            type: 'pay_request',
            content: JSON.stringify({
                requesterId,
                targetUserId,
                extensionDays,
                extensionPrice,
                requesterName,
                message: `${requesterName} is asking you to pay ₹${extensionPrice} to extend chat for ${extensionDays} more days.`,
            }),
        } as any);

        return res.json({ success: true, data: msg });
    } catch (err) {
        logger.error('requestExtension error', err);
        return res.status(500).json({ success: false, message: 'Failed to send extension request' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/chat/accept-extension-request
// Body: { conversationId, userId, paymentId }
// Called after target user accepts the pay request and pays
// ─────────────────────────────────────────────────────────────────────────────
export const acceptExtensionRequest = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { conversationId, userId, paymentId: _paymentId2, requestedById } = req.body;
        if (!conversationId || !userId) {
            return res.status(400).json({ success: false, message: 'conversationId and userId are required' });
        }

        const { extensionDays, extensionPrice } = chatSettings;

        const latestSub = await ChatSubscription.findOne({
            where: { conversationId, status: ChatSubscriptionStatus.ACTIVE },
            order: [['valid_until', 'DESC']],
        });

        const baseDate = latestSub && latestSub.validUntil > new Date()
            ? latestSub.validUntil
            : new Date();

        const validUntil = new Date(baseDate);
        validUntil.setDate(validUntil.getDate() + extensionDays);

        const sub = await ChatSubscription.create({
            conversationId,
            paidById: userId,
            amount: extensionPrice,
            daysGranted: extensionDays,
            validUntil,
            status: ChatSubscriptionStatus.ACTIVE,
            subscriptionType: ChatSubscriptionType.PAY_REQ,
            requestedById: requestedById || undefined,
        });

        // Confirm message
        await Message.create({
            conversationId,
            senderId: userId,
            type: 'system',
            content: `✅ Payment accepted! Chat extended for ${extensionDays} more days.`,
        } as any);

        return res.json({ success: true, data: sub });
    } catch (err) {
        logger.error('acceptExtensionRequest error', err);
        return res.status(500).json({ success: false, message: 'Failed to process extension payment' });
    }
};
