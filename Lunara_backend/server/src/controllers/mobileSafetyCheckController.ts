import { Request, Response } from 'express';
import PartySafetyCheck, { SafetyStatus } from '../models/PartySafetyCheck';
import User from '../models/User';
import { logger } from '../config/logger';

/**
 * POST /api/mobile/safety-checks/respond
 * User submits their safety check status (SAFE, EXTENDED, NEED_HELP)
 */
export const respondToSafetyCheck = async (req: Request, res: Response): Promise<Response> => {
    try {
        const checkId = req.params.checkId || req.body.checkId;
        const { safetyStatus, notes, locationLat, locationLng, reasons, opinion } = req.body;
        const userId = req.user!.id;

        if (!checkId || !safetyStatus) {
            return res.status(400).json({ success: false, message: 'checkId and safetyStatus are required' });
        }

        const combinedNotes = notes || (Array.isArray(reasons) ? reasons.join(', ') : reasons) || opinion || '';

        const safetyCheck = await PartySafetyCheck.findByPk(checkId);
        if (!safetyCheck) {
            return res.status(404).json({ success: false, message: 'Safety check record not found' });
        }
        if (safetyCheck.userId !== userId) {
            return res.status(403).json({ success: false, message: 'You can only respond to your own safety check' });
        }

        const isEmergency = safetyStatus === SafetyStatus.NEED_HELP || safetyStatus === 'NEED_HELP' || safetyStatus === 'UNSAFE';

        await safetyCheck.update({
            safetyStatus: isEmergency ? SafetyStatus.NEED_HELP : (safetyStatus === 'EXTENDED' ? SafetyStatus.EXTENDED : SafetyStatus.SAFE),
            notes: combinedNotes || undefined,
            locationLat: locationLat ? Number(locationLat) : undefined,
            locationLng: locationLng ? Number(locationLng) : undefined,
            alertTriggered: isEmergency,
            respondedAt: new Date(),
        });

        // Mark associated notification as read
        try {
            const Notification = (await import('../models/Notification')).default;
            await Notification.update(
                { isRead: true },
                {
                    where: {
                        recipientUserId: userId,
                        entityId: checkId,
                    }
                }
            );
        } catch (notifErr: any) {
            logger.warn('Failed to update notification status on safety check response:', notifErr.message);
        }

        // Also save to user-to-user SafetyCheck table if partner exists
        if (safetyCheck.partnerUserId) {
            try {
                const SafetyCheck = (await import('../models')).SafetyCheck;
                if (SafetyCheck) {
                    await SafetyCheck.create({
                        userId,
                        partnerId: safetyCheck.partnerUserId,
                        feltSafe: !isEmergency,
                        prebuiltAnswers: Array.isArray(reasons) ? reasons.join(', ') : (reasons || ''),
                        opinion: combinedNotes,
                        status: isEmergency ? 'pending' : 'resolved',
                    });
                }
            } catch (scErr: any) {
                logger.warn('Failed to mirror to SafetyCheck table:', scErr.message);
            }
        }

        // If Emergency / NEED_HELP, broadcast high-priority admin alert via Socket.IO
        if (isEmergency) {
            try {
                const { io } = require('../server');
                const user = await User.findByPk(userId, { attributes: ['id', 'firstName', 'lastName', 'phone'] });
                io.to('admin').emit('admin_safety_alert', {
                    alertId: safetyCheck.id,
                    type: 'EMERGENCY_HELP_REQUEST',
                    user: {
                        id: user?.id,
                        name: user ? `${user.firstName} ${user.lastName}` : 'User',
                        phone: user?.phone,
                    },
                    venueName: safetyCheck.venueName,
                    notes: combinedNotes || 'User pressed Emergency / Need Help button',
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

import { Op } from 'sequelize';

/**
 * Last time the 12-hour auto-resolve sweep ran for a given user.
 *
 * The sweep is housekeeping, not part of this endpoint's answer: the pending
 * query below already excludes anything older than 12 hours, so the response is
 * identical whether or not the sweep has run yet. It used to run inline on every
 * call — and the live feed polls this endpoint on every refresh — so each poll
 * paid for a scan plus, whenever it found anything, two bulk writes. One of those
 * writes is to the notifications table, whose model hooks drop that user's cached
 * notification payload: a read endpoint was repeatedly invalidating the most
 * expensive cache in the app and forcing it to rebuild from scratch.
 */
const lastSafetySweepAt = new Map<string, number>();
const SAFETY_SWEEP_INTERVAL_MS = 5 * 60 * 1000;

async function autoResolveExpiredSafetyChecks(userId: string, now: Date, twelveHoursAgo: Date): Promise<void> {
    try {
        const expiredChecks = await PartySafetyCheck.findAll({
            where: {
                userId,
                safetyStatus: SafetyStatus.NO_RESPONSE,
                [Op.or]: [
                    { partyDate: { [Op.lte]: twelveHoursAgo } },
                    { createdAt: { [Op.lte]: twelveHoursAgo } },
                ]
            },
            attributes: ['id'],
        });

        if (expiredChecks.length > 0) {
            const expiredIds = expiredChecks.map(c => c.id);
            await PartySafetyCheck.update(
                {
                    safetyStatus: SafetyStatus.SAFE,
                    notes: 'Auto-resolved safe after 12 hours',
                    respondedAt: now,
                },
                {
                    where: { id: { [Op.in]: expiredIds } }
                }
            );

            // Mark associated notifications as read
            try {
                const Notification = (await import('../models/Notification')).default;
                await Notification.update(
                    { isRead: true },
                    {
                        where: {
                            recipientUserId: userId,
                            entityId: { [Op.in]: expiredIds },
                        }
                    }
                );
            } catch (_) {}
        }
    } catch (autoErr: any) {
        logger.warn('[getPendingSafetyCheck] Failed to auto-resolve 12h checks:', autoErr.message);
    }
}

/**
 * GET /api/mobile/safety-checks/pending
 * Get pending/unanswered safety check for current user
 */
export const getPendingSafetyCheck = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.user!.id;
        const now = new Date();
        const twelveHoursAgo = new Date(now.getTime() - 12 * 60 * 60 * 1000);

        // Auto-resolve checks older than 12 hours, off the response path and at
        // most once every few minutes per user. A 12-hour rule does not need to
        // be enforced on every poll.
        const lastSweep = lastSafetySweepAt.get(userId) ?? 0;
        if (now.getTime() - lastSweep >= SAFETY_SWEEP_INTERVAL_MS) {
            lastSafetySweepAt.set(userId, now.getTime());
            setImmediate(() => {
                autoResolveExpiredSafetyChecks(userId, now, twelveHoursAgo).catch(() => {});
            });
        }

        const pendingCheck = await PartySafetyCheck.findOne({
            where: {
                userId,
                safetyStatus: SafetyStatus.NO_RESPONSE,
                partyDate: { [Op.gt]: twelveHoursAgo },
                createdAt: { [Op.gt]: twelveHoursAgo },
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
                attributes: ['id', 'firstName', 'lastName', 'phone', 'profileImageUrl'],
            });
            if (partner) {
                partnerInfo = {
                    id: partner.id,
                    name: `${partner.firstName} ${partner.lastName}`.trim(),
                    phone: partner.phone,
                    avatarUrl: partner.profileImageUrl || null,
                };
            }
        }

        // Calculate dynamic actual elapsed hours from party start
        const partyStart = pendingCheck.partyDate ? new Date(pendingCheck.partyDate) : (pendingCheck.createdAt ? new Date(pendingCheck.createdAt) : now);
        const diffMs = Math.max(0, now.getTime() - partyStart.getTime());
        const elapsedHours = Math.max(1, Math.round(diffMs / (1000 * 60 * 60)));
        const hoursText = `${elapsedHours} hour${elapsedHours === 1 ? '' : 's'} ago`;

        return res.status(200).json({
            success: true,
            data: {
                ...pendingCheck.toJSON(),
                partner: partnerInfo,
                elapsedHours,
                hoursText,
                dynamicMessage: `Your party at ${pendingCheck.venueName} started ${hoursText}. Please confirm you are safe & sound.`,
            }
        });
    } catch (err: any) {
        logger.error('getPendingSafetyCheck error:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};
