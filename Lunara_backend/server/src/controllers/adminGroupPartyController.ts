import { Request, Response } from 'express';
import GroupParty from '../models/GroupParty';
import Venue from '../models/Venue';
import User from '../models/User';
import { logger } from '../config/logger';

export const getAdminGroupParties = async (req: Request, res: Response): Promise<void> => {
    try {
        const { venueId, status, paymentStatus, page = '1', limit = '20' } = req.query;

        const where: any = {};
        if (venueId) where.venueId = venueId;
        if (status) where.status = status;
        if (paymentStatus) where.paymentStatus = paymentStatus;

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
