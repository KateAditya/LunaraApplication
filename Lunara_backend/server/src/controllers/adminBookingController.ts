import { Request, Response } from 'express';
import Booking, { AdminApprovalStatus } from '../models/Booking';
import User from '../models/User';
import Venue from '../models/Venue';
import { logger } from '../config/logger';

export const getLargePartyRequests = async (_req: Request, res: Response) => {
    try {
        const requests = await Booking.findAll({
            where: { isLargePartyRequest: true },
            include: [
                { model: User, as: 'customer', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] },
                { model: Venue, as: 'venue', attributes: ['id', 'name', 'city'] }
            ],
            order: [['createdAt', 'DESC']]
        });
        
        return res.json({ success: true, data: requests });
    } catch (err: any) {
        logger.error('getLargePartyRequests:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

export const approveLargePartyRequest = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const { totalAmount, status } = req.body;

        if (!['approved', 'rejected'].includes(status)) {
            return res.status(400).json({ success: false, message: 'Status must be approved or rejected' });
        }

        const booking = await Booking.findByPk(id);
        if (!booking) {
            return res.status(404).json({ success: false, message: 'Booking not found' });
        }
        if (!booking.isLargePartyRequest) {
            return res.status(400).json({ success: false, message: 'Not a large party request' });
        }

        booking.adminApprovalStatus = status as AdminApprovalStatus;
        if (status === 'approved') {
            if (totalAmount === undefined || isNaN(Number(totalAmount))) {
                return res.status(400).json({ success: false, message: 'Valid totalAmount is required when approving' });
            }
            booking.totalAmount = Number(totalAmount);
            booking.commissionAmount = Math.round(booking.totalAmount * 0.1 * 100) / 100;
        }

        await booking.save();

        return res.json({ success: true, message: `Request ${status} successfully`, data: booking });
    } catch (err: any) {
        logger.error('approveLargePartyRequest:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// POST /api/admin/bookings/:id/send-payment-link
// Admin attaches a Razorpay/custom payment link so the user can pay from the Live Feed
export const sendPaymentLink = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const { paymentLink, paymentAmount } = req.body;

        if (!paymentLink || !paymentLink.startsWith('http')) {
            return res.status(400).json({ success: false, message: 'A valid payment link URL is required' });
        }
        if (!paymentAmount || isNaN(Number(paymentAmount)) || Number(paymentAmount) <= 0) {
            return res.status(400).json({ success: false, message: 'A valid paymentAmount > 0 is required' });
        }

        const booking = await Booking.findByPk(id);
        if (!booking) {
            return res.status(404).json({ success: false, message: 'Booking not found' });
        }
        if (!booking.isLargePartyRequest) {
            return res.status(400).json({ success: false, message: 'Not a large party request' });
        }

        await (booking as any).update({
            adminPaymentLink: paymentLink.trim(),
            adminPaymentAmount: Number(paymentAmount),
            adminApprovalStatus: AdminApprovalStatus.PAYMENT_SENT,
        });

        return res.json({
            success: true,
            message: 'Payment link sent to user. It will appear in their Live Feed.',
            data: {
                id: booking.id,
                adminPaymentLink: paymentLink.trim(),
                adminPaymentAmount: Number(paymentAmount),
                adminApprovalStatus: AdminApprovalStatus.PAYMENT_SENT,
            },
        });
    } catch (err: any) {
        logger.error('sendPaymentLink:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// POST /api/admin/bookings/:id/mark-payment-done
// Admin marks payment as completed manually
export const markPaymentDone = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;

        const booking = await Booking.findByPk(id);
        if (!booking) {
            return res.status(404).json({ success: false, message: 'Booking not found' });
        }

        await (booking as any).update({
            adminApprovalStatus: AdminApprovalStatus.PAYMENT_DONE,
        });

        return res.json({ success: true, message: 'Payment marked as done', data: booking });
    } catch (err: any) {
        logger.error('markPaymentDone:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

