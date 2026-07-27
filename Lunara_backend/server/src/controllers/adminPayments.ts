import { Request, Response } from 'express';
import { Op } from 'sequelize';
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

        // 1. Fetch all matching payments
        const allPayments = await Payment.findAll({
            where: whereClause,
            order: [['createdAt', 'ASC']],
            raw: true
        });

        let totalRevenue = 0;
        let successfulCount = 0;
        let failedCount = 0;
        let pendingCount = 0;
        const paymentMethodsMap: { [key: string]: number } = {};
        const revenueOverTimeMap: { [dateStr: string]: number } = {};

        allPayments.forEach((p: any) => {
            const amount = parseFloat(p.amount) || 0;
            const status = (p.status || '').toLowerCase();
            const method = p.paymentMethod || p.payment_method || 'razorpay';

            if (status === 'successful') {
                successfulCount++;
                totalRevenue += amount;

                paymentMethodsMap[method] = (paymentMethodsMap[method] || 0) + 1;

                const createdAt = p.createdAt || p.created_at;
                if (createdAt) {
                    const d = new Date(createdAt);
                    const dateStr = d.toISOString().split('T')[0]; // YYYY-MM-DD
                    revenueOverTimeMap[dateStr] = (revenueOverTimeMap[dateStr] || 0) + amount;
                }
            } else if (status === 'failed') {
                failedCount++;
            } else {
                pendingCount++;
            }
        });

        const totalTransactions = allPayments.length;
        const averageTransactionValue = successfulCount > 0 ? totalRevenue / successfulCount : 0;

        const paymentMethods = Object.keys(paymentMethodsMap).map(method => ({
            paymentMethod: method,
            count: paymentMethodsMap[method]
        }));

        const revenueOverTime = Object.keys(revenueOverTimeMap).sort().map(date => ({
            date,
            revenue: revenueOverTimeMap[date]
        }));

        res.status(200).json({
            success: true,
            data: {
                totalRevenue,
                totalTransactions,
                successfulCount,
                failedCount,
                pendingCount,
                averageTransactionValue,
                paymentMethods,
                revenueOverTime
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
