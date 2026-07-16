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
