import { Request, Response } from 'express';
import Booking, { AdminApprovalStatus } from '../models/Booking';
import User from '../models/User';
import Venue from '../models/Venue';
import GroupParty, { GroupPartyStatus, GroupPartyPaymentStatus } from '../models/GroupParty';
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
            // Fallback to GroupParty
            const groupParty = await GroupParty.findByPk(id);
            if (!groupParty) {
                return res.status(404).json({ success: false, message: 'Booking or Group Party not found' });
            }

            if (status === 'approved') {
                if (totalAmount === undefined || isNaN(Number(totalAmount))) {
                    return res.status(400).json({ success: false, message: 'Valid totalAmount is required when approving' });
                }
                await groupParty.update({
                    status: GroupPartyStatus.APPROVED,
                    totalAmount: Number(totalAmount)
                });
            } else if (status === 'rejected') {
                await groupParty.update({
                    status: GroupPartyStatus.REJECTED
                });
            }

            try {
                const host = await User.findByPk(groupParty.userId, { attributes: ['id', 'fcmToken'] });
                const venue = await Venue.findByPk(groupParty.venueId, { attributes: ['id', 'name'] });
                const venueName = venue?.name || 'Venue';
                if (host && host.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(host.fcmToken, {
                        title: status === 'approved' ? 'Group Party Approved! 🎉' : 'Group Party Rejected ❌',
                        body: status === 'approved'
                            ? `Your group party request at ${venueName} has been approved! Complete payment to confirm.`
                            : `Your group party request at ${venueName} was rejected by the admin.`,
                        data: {
                            type: status === 'approved' ? 'group_party_approved' : 'group_party_rejected',
                            partyId: groupParty.id,
                        }
                    });
                }
                const { io } = require('../server');
                io.to(`user_${groupParty.userId}`).emit('large_party_status_update', {
                    bookingId: groupParty.id,
                    status: groupParty.status
                });
            } catch (pushErr) {
                logger.warn('Failed to send push/socket for group party admin approval: ' + pushErr);
            }

            return res.json({ success: true, message: `Group Party request ${status} successfully`, data: groupParty });
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

        try {
            const host = await User.findByPk(booking.userId, { attributes: ['id', 'fcmToken'] });
            const venue = await Venue.findByPk(booking.venueId, { attributes: ['id', 'name'] });
            const venueName = venue?.name || 'Venue';
            if (host && host.fcmToken) {
                const { sendPushNotification } = require('../services/fcmService');
                await sendPushNotification(host.fcmToken, {
                    title: status === 'approved' ? 'Large Party Approved! 🎉' : 'Large Party Rejected ❌',
                    body: status === 'approved'
                        ? `Your large party request at ${venueName} has been approved! Complete payment to confirm.`
                        : `Your large party request at ${venueName} was rejected by the admin.`,
                    data: {
                        type: status === 'approved' ? 'large_party_approved' : 'large_party_rejected',
                        bookingId: booking.id,
                    }
                });
            }
            const { io } = require('../server');
            io.to(`user_${booking.userId}`).emit('large_party_status_update', {
                bookingId: booking.id,
                status: booking.adminApprovalStatus
            });
        } catch (pushErr) {
            logger.warn('Failed to send push/socket for admin approval: ' + pushErr);
        }

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

        try {
            const host = await User.findByPk(booking.userId, { attributes: ['id', 'fcmToken'] });
            const venue = await Venue.findByPk(booking.venueId, { attributes: ['id', 'name'] });
            const venueName = venue?.name || 'Venue';
            if (host && host.fcmToken) {
                const { sendPushNotification } = require('../services/fcmService');
                await sendPushNotification(host.fcmToken, {
                    title: 'Payment Link Received 💳',
                    body: `Admin sent a payment link of ₹${paymentAmount} for your party at ${venueName}. Click to pay!`,
                    data: {
                        type: 'large_party_payment_link',
                        bookingId: booking.id,
                    }
                });
            }
            const { io } = require('../server');
            io.to(`user_${booking.userId}`).emit('large_party_status_update', {
                bookingId: booking.id,
                status: booking.adminApprovalStatus
            });
        } catch (pushErr) {
            logger.warn('Failed to send push/socket for sendPaymentLink: ' + pushErr);
        }

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
            const groupParty = await GroupParty.findByPk(id);
            if (!groupParty) {
                return res.status(404).json({ success: false, message: 'Booking/Group Party not found' });
            }

            await groupParty.update({
                status: GroupPartyStatus.CONFIRMED,
                paymentStatus: GroupPartyPaymentStatus.PAID
            });

            try {
                const host = await User.findByPk(groupParty.userId, { attributes: ['id', 'fcmToken'] });
                const venue = await Venue.findByPk(groupParty.venueId, { attributes: ['id', 'name'] });
                const venueName = venue?.name || 'Venue';
                if (host && host.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(host.fcmToken, {
                        title: 'Group Party Confirmed! 🎉',
                        body: `Your payment of ₹${groupParty.totalAmount} for your party at ${venueName} is verified. Booking confirmed!`,
                        data: {
                            type: 'group_party_confirmed',
                            partyId: groupParty.id,
                        }
                    });
                }
                const { io } = require('../server');
                io.to(`user_${groupParty.userId}`).emit('group_party_payment_success', { partyId: groupParty.id });
                io.to(`user_${groupParty.userId}`).emit('large_party_payment_success', { bookingId: groupParty.id });
            } catch (pushErr) {
                logger.warn('Failed to send push/socket for markPaymentDone: ' + pushErr);
            }

            return res.json({ success: true, message: 'Group Party payment marked as done', data: groupParty });
        }

        await (booking as any).update({
            adminApprovalStatus: AdminApprovalStatus.PAYMENT_DONE,
        });

        try {
            const host = await User.findByPk(booking.userId, { attributes: ['id', 'fcmToken'] });
            const venue = await Venue.findByPk(booking.venueId, { attributes: ['id', 'name'] });
            const venueName = venue?.name || 'Venue';
            if (host && host.fcmToken) {
                const { sendPushNotification } = require('../services/fcmService');
                await sendPushNotification(host.fcmToken, {
                    title: 'Party Confirmed! 🎉',
                    body: `Your payment of ₹${booking.totalAmount} for your party at ${venueName} is verified. Booking confirmed!`,
                    data: {
                        type: 'large_party_confirmed',
                        bookingId: booking.id,
                    }
                });
            }
            const { io } = require('../server');
            io.to(`user_${booking.userId}`).emit('large_party_payment_success', { bookingId: booking.id });
        } catch (pushErr) {
            logger.warn('Failed to send push/socket for markPaymentDone: ' + pushErr);
        }

        return res.json({ success: true, message: 'Payment marked as done', data: booking });
    } catch (err: any) {
        logger.error('markPaymentDone:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

