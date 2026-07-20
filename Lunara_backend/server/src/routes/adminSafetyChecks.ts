import { Router } from 'express';
import { param, body } from 'express-validator';
import { validate } from '../middleware/validate';
import { SafetyCheck, User } from '../models';

const router = Router();

// GET /api/admin/safety-checks
router.get('/', async (_req, res) => {
    try {
        const safetyChecks = await SafetyCheck.findAll({
            include: [
                {
                    model: User,
                    as: 'user',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'profileImageUrl']
                },
                {
                    model: User,
                    as: 'partner',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'profileImageUrl']
                }
            ],
            order: [['createdAt', 'DESC']]
        });
        
        const formattedSafetyChecks = safetyChecks.map(sc => {
            const json = sc.toJSON() as any;
            return {
                ...json,
                prebuiltAnswers: json.prebuiltAnswers 
                    ? json.prebuiltAnswers.split(',').map((s: string) => s.trim()).filter(Boolean)
                    : []
            };
        });
        
        return res.json({ success: true, data: formattedSafetyChecks });
    } catch (error: any) {
        console.error('Error fetching safety checks for admin:', error);
        return res.status(500).json({ success: false, message: 'Failed to fetch safety checks.' });
    }
});

// POST /api/admin/safety-checks/:id/feedback
router.post(
    '/:id/feedback',
    [
        param('id').isUUID().withMessage('id must be a UUID'),
        body('adminFeedback').notEmpty().withMessage('adminFeedback is required'),
        validate
    ],
    async (req: any, res: any) => {
        try {
            const { id } = req.params;
            const { adminFeedback } = req.body;
            
            const safetyCheck = await SafetyCheck.findByPk(id);
            if (!safetyCheck) {
                return res.status(404).json({ success: false, message: 'Safety check not found.' });
            }
            
            safetyCheck.adminFeedback = adminFeedback;
            safetyCheck.status = 'resolved';
            await safetyCheck.save();

            // Send push notification and emit socket event to user
            try {
                const host = await User.findByPk(safetyCheck.userId, { attributes: ['id', 'fcmToken'] });
                const partner = await User.findByPk(safetyCheck.partnerId, { attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] });
                const partnerName = partner ? `${partner.firstName} ${partner.lastName}` : 'your partner';

                if (host && host.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(host.fcmToken, {
                        title: 'Safety Check Feedback',
                        body: `Regarding your safety check with ${partnerName}: ${adminFeedback}`,
                        data: {
                            type: 'safety_check_feedback',
                            safetyCheckId: safetyCheck.id,
                        }
                    });
                }

                const { io } = require('../server');
                io.to(`user_${safetyCheck.userId}`).emit('notification_created', {
                    id: `safety_feedback_${safetyCheck.id}`,
                    title: 'Safety Check Feedback',
                    body: `Regarding your safety check with ${partnerName}: ${adminFeedback}`,
                    createdAt: new Date().toISOString(),
                    read: false,
                    sender: partner ? {
                        id: safetyCheck.partnerId,
                        firstName: partner.firstName,
                        lastName: partner.lastName,
                        profileImageUrl: partner.profileImageUrl,
                    } : null,
                    data: {
                        type: 'safety_check_feedback',
                        safetyCheckId: safetyCheck.id,
                    }
                });
            } catch (pushErr) {
                console.error('Failed to send push/socket for safety check feedback:', pushErr);
            }
            
            const json = safetyCheck.toJSON() as any;
            const formatted = {
                ...json,
                prebuiltAnswers: json.prebuiltAnswers 
                    ? json.prebuiltAnswers.split(',').map((s: string) => s.trim()).filter(Boolean)
                    : []
            };
            
            return res.json({ success: true, data: formatted });
        } catch (error: any) {
            console.error('Error submitting safety check feedback:', error);
            return res.status(500).json({ success: false, message: 'Failed to submit feedback.' });
        }
    }
);

export default router;
