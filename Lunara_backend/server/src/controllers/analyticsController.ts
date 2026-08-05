import { Request, Response } from 'express';
import PartyPlan from '../models/PartyPlan';
import User from '../models/User';
import WalletTransaction from '../models/WalletTransaction';
import PartyReview from '../models/PartyReview';
import { logger } from '../config/logger';

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/analytics/overview
// Returns business metrics: completion rate, revenue breakdown, refund rates, top hosts/venues
// ─────────────────────────────────────────────────────────────────────────────
export const getAnalyticsOverview = async (_req: Request, res: Response): Promise<void> => {
    try {
        const totalPlans = await PartyPlan.count();
        const completedPlans = await PartyPlan.count({ where: { status: 'inactive' } });
        const activePlans = await PartyPlan.count({ where: { status: 'active' } });
        const completionRate = totalPlans > 0 ? ((completedPlans / totalPlans) * 100).toFixed(1) : '0.0';

        // Wallet transactions metrics
        const totalRecharges = await WalletTransaction.sum('amount', { where: { transactionType: 'recharge' } }) || 0;
        const totalRefunds = await WalletTransaction.sum('amount', { where: { transactionType: 'refund' } }) || 0;
        const totalVipPurchases = await WalletTransaction.sum('amount', { where: { transactionType: 'vip_purchase' } }) || 0;
        const totalDeposits = await WalletTransaction.sum('amount', { where: { transactionType: 'commitment_deposit' } }) || 0;

        // Ratings & Reviews
        const totalReviews = await PartyReview.count();
        const avgRatingResult = await PartyReview.aggregate('rating', 'AVG') as number | null;
        const avgRating = avgRatingResult ? parseFloat(avgRatingResult.toString()).toFixed(2) : '5.00';

        res.json({
            success: true,
            data: {
                performance: {
                    totalPlans,
                    activePlans,
                    completedPlans,
                    completionRate: `${completionRate}%`,
                    avgRating,
                    totalReviews,
                },
                financials: {
                    totalRecharges: Number(totalRecharges),
                    totalRefunds: Number(totalRefunds),
                    totalVipPurchases: Number(totalVipPurchases),
                    totalDeposits: Number(totalDeposits),
                    netRevenue: Number(totalVipPurchases) + (Number(totalDeposits) - Number(totalRefunds)),
                },
            }
        });
    } catch (err: any) {
        logger.error('getAnalyticsOverview error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch analytics overview', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/admin/reports/export
// Generates downloadable CSV / JSON reports for bookings, wallet, users, refunds
// ─────────────────────────────────────────────────────────────────────────────
export const exportReport = async (req: Request, res: Response): Promise<void> => {
    try {
        const type = (req.query.type || 'bookings') as string;
        const format = (req.query.format || 'json') as string;

        let reportData: any[] = [];
        let filename = `lunara_${type}_report_${Date.now()}`;

        if (type === 'wallet') {
            filename = `lunara_wallet_ledger_${Date.now()}`;
            reportData = await WalletTransaction.findAll({ order: [['createdAt', 'DESC']], limit: 500 });
        } else if (type === 'users') {
            filename = `lunara_users_report_${Date.now()}`;
            reportData = await User.findAll({ attributes: ['id', 'firstName', 'lastName', 'email', 'reliabilityScore', 'noShowCount', 'isAutoblocked'], limit: 500 });
        } else if (type === 'reviews') {
            filename = `lunara_reviews_report_${Date.now()}`;
            reportData = await PartyReview.findAll({ order: [['createdAt', 'DESC']], limit: 500 });
        } else {
            // Default: Bookings
            filename = `lunara_party_plans_report_${Date.now()}`;
            reportData = await PartyPlan.findAll({ order: [['createdAt', 'DESC']], limit: 500 });
        }

        if (format === 'csv') {
            res.setHeader('Content-Type', 'text/csv');
            res.setHeader('Content-Disposition', `attachment; filename="${filename}.csv"`);
            
            if (reportData.length === 0) {
                res.send('No data available');
                return;
            }

            const headers = Object.keys(reportData[0].dataValues || reportData[0]);
            let csv = headers.join(',') + '\n';

            for (const row of reportData) {
                const values = headers.map(h => {
                    const val = (row.dataValues ? row.dataValues[h] : row[h]);
                    return `"${String(val !== undefined && val !== null ? val : '').replace(/"/g, '""')}"`;
                });
                csv += values.join(',') + '\n';
            }

            res.send(csv);
            return;
        }

        // Default JSON output
        res.json({
            success: true,
            reportType: type,
            count: reportData.length,
            data: reportData,
        });
    } catch (err: any) {
        logger.error('exportReport error:', err);
        res.status(500).json({ success: false, message: 'Failed to generate report', error: err.message });
    }
};
