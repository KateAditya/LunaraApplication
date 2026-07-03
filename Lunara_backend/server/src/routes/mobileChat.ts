import { Router } from 'express';
import { body, param } from 'express-validator';
import { validate } from '../middleware/validate';
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
router.get('/conversations', ctrl.getConversations);

/**
 * POST /api/mobile/chat/conversations
 * Create or retrieve an existing 1-to-1 conversation.
 * Body: { userId, otherUserId, contextType?, contextId? }
 */
router.post(
    '/conversations',
    [
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
    [param('id').isUUID(), validate],
    ctrl.getMessages
);

/**
 * POST /api/mobile/chat/conversations/:id/messages
 * Send a message. Supports: text | image | sticker | invitation | icebreaker
 *
 * For text/icebreaker:  { senderId, type, content }
 * For image/sticker:    { senderId, type, mediaUrl, mediaMimeType? }
 * For invitation:       { senderId, type: 'invitation', invitationRef, invitationRefType, invitationTime }
 */
router.post(
    '/conversations/:id/messages',
    [
        param('id').isUUID(),
        body('senderId').notEmpty().withMessage('senderId is required'),
        body('type')
            .optional()
            .isIn(['text', 'image', 'sticker', 'invitation', 'icebreaker'])
            .withMessage('type must be text, image, sticker, invitation, or icebreaker'),
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
        param('id').isUUID(),
        param('msgId').isUUID(),
        body('userId').notEmpty().withMessage('userId is required'),
        validate,
    ],
    ctrl.deleteMessage
);

/**
 * PATCH /api/mobile/chat/conversations/:id/read
 * Mark all unread messages in a conversation as read.
 * Body: { userId }
 */
router.patch(
    '/conversations/:id/read',
    [param('id').isUUID(), body('userId').notEmpty(), validate],
    ctrl.markConversationRead
);

export default router;
