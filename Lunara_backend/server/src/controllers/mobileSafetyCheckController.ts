import { Request, Response } from 'express';
import PartySafetyCheck, { SafetyStatus } from '../models/PartySafetyCheck';
import User from '../models/User';
import UserProfile from '../models/UserProfile';
import UserPhoto from '../models/UserPhoto';
import { logger } from '../config/logger';

/**
 * POST /api/mobile/safety-checks/respond
 * User submits their safety check status (SAFE, EXTENDED, NEED_HELP)
 */
export const respondToSafetyCheck = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { checkId, userId, safetyStatus, notes, locationLat, locationLng } = req.body;

        if (!checkId || !safetyStatus) {
            return res.status(400).json({ success: false, message: 'checkId and safetyStatus are required' });
        }

        const safetyCheck = await PartySafetyCheck.findByPk(checkId);
        if (!safetyCheck) {
            return res.status(404).json({ success: false, message: 'Safety check record not found' });
        }

        const isEmergency = safetyStatus === SafetyStatus.NEED_HELP;

        await safetyCheck.update({
            safetyStatus: safetyStatus as SafetyStatus,
            notes: notes || undefined,
            locationLat: locationLat ? Number(locationLat) : undefined,
            locationLng: locationLng ? Number(locationLng) : undefined,
            alertTriggered: isEmergency,
            respondedAt: new Date(),
        });

        // If Emergency / NEED_HELP, broadcast high-priority admin alert via Socket.IO
        if (isEmergency) {
            try {
                const { io } = require('../server');
                const user = await User.findByPk(userId || safetyCheck.userId, { attributes: ['id', 'firstName', 'lastName', 'phone'] });
                io.to('admin').emit('admin_safety_alert', {
                    alertId: safetyCheck.id,
                    type: 'EMERGENCY_HELP_REQUEST',
                    user: {
                        id: user?.id,
                        name: user ? `${user.firstName} ${user.lastName}` : 'User',
                        phone: user?.phone,
                    },
                    venueName: safetyCheck.venueName,
                    notes: notes || 'User pressed Emergency / Need Help button',
                    locationLat: locationLat || null,
                    locationLng: locationLng || null,
                    timestamp: new Date().toISOString(),
                });
            } catch (socketErr: any) {
                logger.warn('Failed to emit admin_safety_alert:', socketErr.message);
            }
        }

        return res.status(200).json({
            success: true,
            message: isEmergency ? 'Emergency alert sent to admin! Stay safe.' : 'Safety status updated successfully.',
            data: safetyCheck,
        });
    } catch (err: any) {
        logger.error('respondToSafetyCheck error:', err);
        return res.status(500).json({ success: false, message: err.message || 'Failed to submit safety check' });
    }
};

/**
 * GET /api/mobile/safety-checks/pending
 * Get pending/unanswered safety check for current user
 */
export const getPendingSafetyCheck = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = (req.query.userId || req.body.userId) as string;
        if (!userId) {
            return res.status(400).json({ success: false, message: 'userId is required' });
        }

        const pendingCheck = await PartySafetyCheck.findOne({
            where: {
                userId,
                safetyStatus: SafetyStatus.NO_RESPONSE,
            },
            order: [['created_at', 'DESC']],
        });

        if (!pendingCheck) {
            return res.status(200).json({ success: true, data: null });
        }

        // Fetch user and partner details for context
        let partnerInfo = null;
        if (pendingCheck.partnerUserId) {
            const partner: any = await User.findByPk(pendingCheck.partnerUserId, {
                attributes: ['id', 'firstName', 'lastName', 'phone'],
                include: [
                    { model: UserProfile, as: 'profile', attributes: ['avatarUrl'] },
                    { model: UserPhoto, as: 'photos', attributes: ['photoUrl'] }
                ]
            });
            if (partner) {
                partnerInfo = {
                    id: partner.id,
                    name: `${partner.firstName} ${partner.lastName}`.trim(),
                    phone: partner.phone,
                    avatarUrl: partner.profile?.avatarUrl || partner.photos?.[0]?.photoUrl || null,
                };
            }
        }

        return res.status(200).json({
            success: true,
            data: {
                ...pendingCheck.toJSON(),
                partner: partnerInfo,
            }
        });
    } catch (err: any) {
        logger.error('getPendingSafetyCheck error:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};
