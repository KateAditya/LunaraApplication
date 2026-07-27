import { Request, Response } from 'express';
import { Op, fn, col } from 'sequelize';
import { Payment, User } from '../models';
import { logger } from '../config/logger';

export const getPaymentSummary = async (req: Request, res: Response) => {
    try {
        const { startDate, endDate } = req.query;
        
        let whereClause: any = {};
        if (startDate && endDate) {
            whereClause.createdAt = {
                [Op.between]: [new Date(startDate as string), new Date(endDate as string)],
            };
        }

        // 1. Total successful revenue
        const revenueResult = await Payment.sum('amount', {
            where: {
                ...whereClause,
                status: 'successful'
            }
        });
        const totalRevenue = revenueResult || 0;

        // 2. Transaction counts
        const allPayments = await Payment.findAll({
            where: whereClause,
            attributes: ['status', [fn('count', col('id')), 'count']],
            group: ['status']
        });
        
        let successfulCount = 0;
        let failedCount = 0;
        let pendingCount = 0;
        
        allPayments.forEach((p: any) => {
            const countStr = p.getDataValue('count');
            const countNum = parseInt(typeof countStr === 'string' ? countStr : countStr.toString(), 10);
            
            if (p.status === 'successful') successfulCount += countNum;
            else if (p.status === 'failed') failedCount += countNum;
            else pendingCount += countNum; // initiated, processing, refunded
        });
        
        const totalTransactions = successfulCount + failedCount + pendingCount;
        const averageTransactionValue = successfulCount > 0 ? totalRevenue / successfulCount : 0;

        // 3. Payment methods distribution
        const paymentMethodsResult = await Payment.findAll({
            where: {
                ...whereClause,
                status: 'successful'
            },
            attributes: ['paymentMethod', [fn('count', col('id')), 'count']],
            group: ['paymentMethod']
        });

        // 4. Revenue broken down by day
        // Using DATE_TRUNC for Postgres
        const revenueOverTimeRaw = await Payment.findAll({
            where: {
                ...whereClause,
                status: 'successful'
            },
            attributes: [
                [fn('DATE_TRUNC', 'day', col('createdAt')), 'date'],
                [fn('SUM', col('amount')), 'revenue']
            ],
            group: [fn('DATE_TRUNC', 'day', col('createdAt'))],
            order: [[fn('DATE_TRUNC', 'day', col('createdAt')), 'ASC']],
            raw: true
        });

        res.status(200).json({
            success: true,
            data: {
                totalRevenue,
                totalTransactions,
                successfulCount,
                failedCount,
                pendingCount,
                averageTransactionValue,
                paymentMethods: paymentMethodsResult,
                revenueOverTime: revenueOverTimeRaw
            }
        });
    } catch (error: any) {
        logger.error('Error fetching payment summary:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch payment summary',
            error: error.message
        });
    }
};

export const getPayments = async (req: Request, res: Response) => {
    try {
        const page = parseInt(req.query.page as string) || 1;
        const limit = parseInt(req.query.limit as string) || 10;
        const status = req.query.status as string;
        const search = req.query.search as string;
        const startDate = req.query.startDate as string;
        const endDate = req.query.endDate as string;
        const offset = (page - 1) * limit;

        let whereClause: any = {};
        
        if (status && status !== 'all') {
            whereClause.status = status;
        }

        if (startDate && endDate) {
            whereClause.createdAt = {
                [Op.between]: [new Date(startDate), new Date(endDate)],
            };
        }

        let userWhereClause: any = {};
        if (search) {
            userWhereClause = {
                [Op.or]: [
                    { firstName: { [Op.iLike]: `%${search}%` } },
                    { lastName: { [Op.iLike]: `%${search}%` } },
                    { email: { [Op.iLike]: `%${search}%` } }
                ]
            };
        }

        const { rows, count } = await Payment.findAndCountAll({
            where: whereClause,
            include: [
                {
                    model: User,
                    as: 'payer',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'profileImageUrl'],
                    where: Object.keys(userWhereClause).length > 0 ? userWhereClause : undefined,
                    required: Object.keys(userWhereClause).length > 0
                }
            ],
            order: [['createdAt', 'DESC']],
            limit,
            offset
        });

        res.status(200).json({
            success: true,
            data: rows,
            pagination: {
                total: count,
                page,
                limit,
                totalPages: Math.ceil(count / limit)
            }
        });
    } catch (error: any) {
        logger.error('Error fetching payments:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch payments',
            error: error.message
        });
    }
};
