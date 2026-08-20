import { Request, Response } from 'express';
import GroupParty from '../models/GroupParty';
import Venue from '../models/Venue';
import User from '../models/User';
import { logger } from '../config/logger';
import { Op } from 'sequelize';

export const getAdminGroupParties = async (req: Request, res: Response): Promise<void> => {
    try {
        const { venueId, paymentStatus, page = '1', limit = '20' } = req.query;

        const where: any = {
            numberOfFriends: { [Op.lte]: 20 }
        };
        if (venueId) where.venueId = venueId;
        // A small (<=20) GroupParty has no admin-approval step at all — the
        // 'pending' status literally just means "payment not completed yet,"
        // which is either still in progress or abandoned. There is nothing
        // for an admin to approve/reject here (unlike the >20 Large Party
        // flow, which uses a completely separate Booking/adminApprovalStatus
        // model). Requesting status=pending previously returned every raw
        // pending row, including abandoned checkouts, with Approve/Reject
        // actions that don't apply to them — so pending/unpaid rows are
        // never surfaced to admins regardless of the requested filter.
        where.status = { [Op.in]: ['confirmed', 'completed'] };
        where.paymentStatus = 'paid';
        if (paymentStatus && paymentStatus !== 'pending') where.paymentStatus = paymentStatus;

        const pageNum = Math.max(1, parseInt(page as string));
        const limitNum = Math.min(100, Math.max(1, parseInt(limit as string)));
        const offset = (pageNum - 1) * limitNum;

        const { count, rows } = await GroupParty.findAndCountAll({
            where,
            include: [
                {
                    model: User,
                    as: 'creator',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone'],
                },
                {
                    model: Venue,
                    as: 'venue',
                    attributes: ['id', 'name', 'city'],
                },
            ],
            order: [['createdAt', 'DESC']],
            limit: limitNum,
            offset,
        });

        res.json({
            success: true,
            total: count,
            page: pageNum,
            limit: limitNum,
            pages: Math.ceil(count / limitNum),
            data: rows,
        });
    } catch (err: any) {
        logger.error('getAdminGroupParties error:', err);
        res.status(500).json({ success: false, error: err.message });
    }
};
