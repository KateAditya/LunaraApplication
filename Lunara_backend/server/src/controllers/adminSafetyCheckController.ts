import { Request, Response } from 'express';
import PartySafetyCheck, { SafetyStatus } from '../models/PartySafetyCheck';
import User from '../models/User';
import { logger } from '../config/logger';

/**
 * GET /api/admin/safety-checks
 * Party Plan-wise Safety Checks view showing Host & Partner user-centric details
 */
export const getAdminPartyPlanSafetyChecks = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { status, planType, page = 1, limit = 20 } = req.query;

        const whereClause: any = {};
        if (status && status !== 'all') {
            whereClause.safetyStatus = status;
        }
        if (planType) {
            whereClause.planType = planType;
        }

        const checks = await PartySafetyCheck.findAll({
            where: whereClause,
            order: [
                ['alertTriggered', 'DESC'],
                ['created_at', 'DESC']
            ],
            limit: Number(limit),
            offset: (Number(page) - 1) * Number(limit),
        });

        // Enrich with user-centric Host & Partner details
        const enrichedChecks = await Promise.all(checks.map(async (check) => {
            const user: any = await User.findByPk(check.userId, {
                attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
            });

            let partner: any = null;
            if (check.partnerUserId) {
                partner = await User.findByPk(check.partnerUserId, {
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                });
            }

            return {
                id: check.id,
                planId: check.planId,
                planType: check.planType,
                venueName: check.venueName,
                partyDate: check.partyDate,
                partyTime: check.partyTime,
                safetyStatus: check.safetyStatus,
                notes: check.notes,
                locationLat: check.locationLat,
                locationLng: check.locationLng,
                alertTriggered: check.alertTriggered,
                notificationSentAt: check.notificationSentAt,
                respondedAt: check.respondedAt,
                user: user ? {
                    id: user.id,
                    name: `${user.firstName} ${user.lastName}`.trim(),
                    email: user.email,
                    phone: user.phone,
                    avatarUrl: user.profileImageUrl || null,
                } : null,
                partner: partner ? {
                    id: partner.id,
                    name: `${partner.firstName} ${partner.lastName}`.trim(),
                    email: partner.email,
                    phone: partner.phone,
                    avatarUrl: partner.profileImageUrl || null,
                } : null,
            };
        }));

        // Summary Statistics
        const total = await PartySafetyCheck.count();
        const safeCount = await PartySafetyCheck.count({ where: { safetyStatus: SafetyStatus.SAFE } });
        const extendedCount = await PartySafetyCheck.count({ where: { safetyStatus: SafetyStatus.EXTENDED } });
        const needHelpCount = await PartySafetyCheck.count({ where: { safetyStatus: SafetyStatus.NEED_HELP } });
        const noResponseCount = await PartySafetyCheck.count({ where: { safetyStatus: SafetyStatus.NO_RESPONSE } });

        return res.status(200).json({
            success: true,
            summary: {
                total,
                safeCount,
                extendedCount,
                needHelpCount,
                noResponseCount,
            },
            data: enrichedChecks,
        });
    } catch (err: any) {
        logger.error('getAdminPartyPlanSafetyChecks error:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

/**
 * POST /api/admin/safety-checks/:id/resolve
 * Resolve an Emergency / Need Help safety check alert
 */
export const resolveAdminSafetyAlert = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { id } = req.params;
        const { adminNotes } = req.body;

        const check = await PartySafetyCheck.findByPk(id);
        if (!check) {
            return res.status(404).json({ success: false, message: 'Safety check record not found' });
        }

        await check.update({
            alertTriggered: false,
            notes: adminNotes ? `${check.notes || ''} [Admin Resolved: ${adminNotes}]` : check.notes,
        });

        return res.status(200).json({
            success: true,
            message: 'Safety alert marked as resolved',
            data: check,
        });
    } catch (err: any) {
        logger.error('resolveAdminSafetyAlert error:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};
