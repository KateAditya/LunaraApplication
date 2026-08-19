import { Router } from 'express';
import { body, param } from 'express-validator';
import { validate } from '../middleware/validate';
import { authenticate } from '../middleware/auth';
import ctrl from '../controllers/mobileChatController';

const router = Router();

// ─── Icebreakers (no auth needed for list) ───────────────────────────────────

/**
 * GET /api/mobile/chat/icebreakers
 * Returns the static list of icebreaker prompts shown in the bottom sheet.
 */
router.get('/icebreakers', ctrl.getIcebreakers);

// ─── Conversation list ────────────────────────────────────────────────────────

/**
 * GET /api/mobile/chat/conversations?userId=<uuid>
 * Returns all conversations for the user (chat list screen).
 * Sorted by lastMessageAt DESC.
 */
router.get('/conversations', authenticate, ctrl.getConversations);

/**
 * POST /api/mobile/chat/conversations
 * Create or retrieve an existing 1-to-1 conversation.
 * Body: { userId, otherUserId, contextType?, contextId? }
 */
router.post(
    '/conversations',
    [
        authenticate,
        body('userId').notEmpty().withMessage('userId is required'),
        body('otherUserId').isUUID().withMessage('otherUserId must be a UUID'),
        validate,
    ],
    ctrl.getOrCreateConversation
);

// ─── Per-conversation actions ─────────────────────────────────────────────────
// NOTE: Specific sub-routes before generic /:id

/**
 * GET /api/mobile/chat/conversations/:id/messages?userId=<uuid>&limit=30&before=<ISO date>
 * Returns paginated messages in a conversation (newest first, reversed for display).
 * Automatically marks messages as READ for the requesting user.
 */
router.get(
    '/conversations/:id/messages',
    [authenticate, param('id').isUUID(), validate],
    ctrl.getMessages
);

/**
 * GET /api/mobile/chat/conversations/:id/search?userId=<uuid>&query=<search>
 * Search text/invitation messages in a conversation.
 */
router.get(
    '/conversations/:id/search',
    [authenticate, param('id').isUUID(), validate],
    ctrl.searchMessages
);

/**
 * POST /api/mobile/chat/conversations/:id/messages
 * Send a message. Supports: text | image | sticker | invitation | icebreaker | voice
 *
 * For text/icebreaker:  { senderId, type, content }
 * For image/sticker:    { senderId, type, mediaUrl, mediaMimeType? }
 * For voice:            { senderId, type: 'voice', mediaUrl, duration?, fileSize?, waveformData? }
 * For invitation:       { senderId, type: 'invitation', invitationRef, invitationRefType, invitationTime }
 */
router.post(
    '/conversations/:id/messages',
    [
        authenticate,
        param('id').isUUID(),
        body('senderId').notEmpty().withMessage('senderId is required'),
        body('type')
            .optional()
            .isIn(['text', 'image', 'sticker', 'invitation', 'icebreaker', 'voice'])
            .withMessage('type must be text, image, sticker, invitation, icebreaker, or voice'),
        validate,
    ],
    ctrl.sendMessage
);

/**
 * PATCH /api/mobile/chat/conversations/:id/messages/:msgId/invitation
 * Accept or decline an invitation message.
 * Body: { userId, action: 'accept' | 'decline' }
 */
router.patch(
    '/conversations/:id/messages/:msgId/invitation',
    [
        authenticate,
        param('id').isUUID(),
        param('msgId').isUUID(),
        body('userId').notEmpty().withMessage('userId is required'),
        body('action').isIn(['accept', 'decline']).withMessage("action must be 'accept' or 'decline'"),
        validate,
    ],
    ctrl.respondToInvitation
);

/**
 * DELETE /api/mobile/chat/conversations/:id/messages/:msgId
 * Soft-delete a message (only the sender can delete).
 * Body: { userId }
 */
router.delete(
    '/conversations/:id/messages/:msgId',
    [
        authenticate,
        param('id').isUUID(),
        param('msgId').isUUID(),
        body('userId').notEmpty().withMessage('userId is required'),
        validate,
    ],
    ctrl.deleteMessage
);

/**
 * DELETE /api/mobile/chat/conversations/:id/messages
 * Clear all messages in a conversation for the user.
 * Body: { userId, clearForEveryone?: boolean }
 */
router.delete(
    '/conversations/:id/messages',
    [
        authenticate,
        param('id').isUUID(),
        body('userId').notEmpty().withMessage('userId is required'),
        validate,
    ],
    ctrl.clearChat
);

/**
 * POST /api/mobile/chat/conversations/:id/clear
 * Clear all messages in a conversation for the user.
 * Body: { userId, clearForEveryone?: boolean }
 */
router.post(
    '/conversations/:id/clear',
    [
        authenticate,
        param('id').isUUID(),
        body('userId').notEmpty().withMessage('userId is required'),
        validate,
    ],
    ctrl.clearChat
);

/**
 * DELETE /api/mobile/chat/conversations/:id
 * Delete the entire conversation / user from chat list.
 * Body: { userId, deleteForEveryone?: boolean }
 */
router.delete(
    '/conversations/:id',
    [
        authenticate,
        param('id').isUUID(),
        body('userId').notEmpty().withMessage('userId is required'),
        validate,
    ],
    ctrl.deleteConversation
);

/**
 * PATCH /api/mobile/chat/conversations/:id/read
 * Mark all unread messages in a conversation as read.
 * Body: { userId }
 */
router.patch(
    '/conversations/:id/read',
    [authenticate, param('id').isUUID(), body('userId').notEmpty(), validate],
    ctrl.markConversationRead
);

export default router;
