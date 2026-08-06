import { Request, Response } from 'express';
import Booking, { AdminApprovalStatus } from '../models/Booking';
import { PlanEligibilityService } from '../services/PlanEligibilityService';
import User from '../models/User';
import Venue from '../models/Venue';
import GroupParty, { GroupPartyStatus, GroupPartyPaymentStatus } from '../models/GroupParty';
import Payment from '../models/Payment';
import { logger } from '../config/logger';
import { Op } from 'sequelize';

export const getLargePartyRequests = async (_req: Request, res: Response) => {
    try {
        const requests = await Booking.findAll({
            where: {
                isLargePartyRequest: true,
                numberOfGuests: { [Op.gt]: 20 }
            },
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

            if (groupParty.status !== GroupPartyStatus.PENDING) {
                return res.status(400).json({ success: false, message: `Request is already in '${groupParty.status}' status and cannot be modified.` });
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

                // Emit notification_created
                io.to(`user_${groupParty.userId}`).emit('notification_created', {
                    id: `group_party_${groupParty.id}_${status}`,
                    title: status === 'approved' ? 'Group Party Approved! 🎉' : 'Group Party Rejected ❌',
                    body: status === 'approved'
                        ? `Your group party request at ${venueName} has been approved! Complete payment to confirm.`
                        : `Your group party request at ${venueName} was rejected by the admin.`,
                    createdAt: new Date().toISOString(),
                    read: false,
                    data: {
                        type: status === 'approved' ? 'group_party_approved' : 'group_party_rejected',
                        partyId: groupParty.id,
                    }
                });
            } catch (pushErr) {
                logger.warn('Failed to send push/socket for group party admin approval: ' + pushErr);
            }

            return res.json({ success: true, message: `Group Party request ${status} successfully`, data: groupParty });
        }

        if (!booking.isLargePartyRequest) {
            return res.status(400).json({ success: false, message: 'Not a large party request' });
        }

        if (booking.adminApprovalStatus !== 'pending') {
            return res.status(400).json({ success: false, message: `Large party request is already '${booking.adminApprovalStatus}' and cannot be processed again.` });
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
            const notifTitle = status === 'approved' ? 'Large Party Approved! 🎉' : 'Large Party Rejected ❌';
            const notifBody = status === 'approved'
                ? `Your large party request at ${venueName} has been approved! Complete payment to confirm.`
                : `Your large party request at ${venueName} was rejected by the admin.`;
            const notifType = status === 'approved' ? 'large_party_approved' : 'large_party_rejected';

            // Create DB Notification Record
            try {
                const NotificationModel = (await import('../models/Notification')).default;
                await NotificationModel.create({
                    recipientUserId: booking.userId,
                    eventType: notifType,
                    category: 'bookings' as any,
                    entityType: 'booking',
                    entityId: booking.id,
                    title: notifTitle,
                    body: notifBody,
                    priority: 'HIGH' as any,
                    isRead: false,
                    metadata: { bookingId: booking.id, status, venueName }
                });
            } catch (dbErr) {
                logger.warn('Failed to save DB notification for admin approval: ' + dbErr);
            }

            if (host && host.fcmToken) {
                const { sendPushNotification } = require('../services/fcmService');
                await sendPushNotification(host.fcmToken, {
                    title: notifTitle,
                    body: notifBody,
                    data: {
                        type: notifType,
                        bookingId: booking.id,
                    }
                });
            }
            const { io } = require('../server');
            io.to(`user_${booking.userId}`).emit('large_party_status_update', {
                bookingId: booking.id,
                status: booking.adminApprovalStatus
            });

            // Emit notification_created
            io.to(`user_${booking.userId}`).emit('notification_created', {
                id: `large_party_${booking.id}_${status}`,
                title: notifTitle,
                body: notifBody,
                createdAt: new Date().toISOString(),
                read: false,
                data: {
                    type: notifType,
                    bookingId: booking.id,
                }
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

            // Emit notification_created
            io.to(`user_${booking.userId}`).emit('notification_created', {
                id: `large_party_${booking.id}_payment_sent`,
                title: 'Large Party Payment Link Received 💳',
                body: `Admin sent a payment link of ₹${paymentAmount} for your party at ${venueName}. Complete payment.`,
                createdAt: new Date().toISOString(),
                read: false,
                data: {
                    type: 'large_party_payment_link',
                    bookingId: booking.id,
                }
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

                // Emit notification_created
                io.to(`user_${groupParty.userId}`).emit('notification_created', {
                    id: `group_party_${groupParty.id}_confirmed`,
                    title: 'Group Party Confirmed! 🎉',
                    body: `Your group party of ${groupParty.numberOfFriends} friends at ${venueName} is confirmed!`,
                    createdAt: new Date().toISOString(),
                    read: false,
                    data: {
                        type: 'group_party_confirmed',
                        partyId: groupParty.id,
                    }
                });
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

            // Emit notification_created
            io.to(`user_${booking.userId}`).emit('notification_created', {
                id: `large_party_${booking.id}_payment_done`,
                title: 'Large Party Confirmed! 🎉',
                body: `Your party of ${booking.numberOfGuests} guests at ${venueName} is fully confirmed. Enjoy your night!`,
                createdAt: new Date().toISOString(),
                read: false,
                data: {
                    type: 'large_party_confirmed',
                    bookingId: booking.id,
                }
            });
        } catch (pushErr) {
            logger.warn('Failed to send push/socket for markPaymentDone: ' + pushErr);
        }

        return res.json({ success: true, message: 'Payment marked as done', data: booking });
    } catch (err: any) {
        logger.error('markPaymentDone:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

import PartyPlan from '../models/PartyPlan';

function mapPartyPlanToBooking(p: any) {
    return {
        id: p.id,
        bookingNumber: `PLN-${(p.id || '').substring(0, 8).toUpperCase()}`,
        userId: p.userId,
        venueId: p.venueId,
        bookingDate: p.planDateTime ? new Date(p.planDateTime).toISOString().split('T')[0] : (p.createdAt ? new Date(p.createdAt).toISOString().split('T')[0] : ''),
        startTime: p.planDateTime ? new Date(p.planDateTime).toTimeString().substring(0, 5) : '20:00',
        numberOfGuests: p.maxParticipants || p.currentParticipants || 1,
        totalAmount: Number(p.totalAmount || p.budgetPerPerson || 0),
        depositAmount: 0,
        commissionAmount: 0,
        status: p.status === 'active' || p.status === 'approved' ? 'confirmed' : (p.status || 'pending'),
        paymentStatus: p.hostPaymentStatus === 'paid' ? 'paid' : 'pending',
        isGroupBooking: false,
        isLargePartyRequest: false,
        isUpcomingNight: false,
        goingMode: 'plan',
        tablePackage: p.tablePackage || p.title || 'Party Plan',
        customer: p.creator ? {
            id: p.creator.id,
            firstName: p.creator.firstName,
            lastName: p.creator.lastName,
            email: p.creator.email,
            phone: p.creator.phone,
            profileImageUrl: p.creator.profileImageUrl,
        } : undefined,
        venue: p.venue ? {
            id: p.venue.id,
            name: p.venue.name,
            city: p.venue.city,
            category: p.venue.category,
        } : undefined,
        createdAt: p.createdAt,
        updatedAt: p.updatedAt,
    };
}

function mapGroupPartyToBooking(g: any) {
    return {
        id: g.id,
        bookingNumber: `GRP-${(g.id || '').substring(0, 8).toUpperCase()}`,
        userId: g.userId,
        venueId: g.venueId,
        bookingDate: g.partyDateTime ? new Date(g.partyDateTime).toISOString().split('T')[0] : (g.createdAt ? new Date(g.createdAt).toISOString().split('T')[0] : ''),
        startTime: g.partyDateTime ? new Date(g.partyDateTime).toTimeString().substring(0, 5) : '20:00',
        numberOfGuests: g.numberOfFriends || g.groupSize || 1,
        totalAmount: Number(g.totalAmount || 0),
        depositAmount: 0,
        commissionAmount: 0,
        status: g.status === 'approved' || g.status === 'confirmed' ? 'confirmed' : (g.status || 'pending'),
        paymentStatus: g.paymentStatus === 'paid' ? 'paid' : 'pending',
        isGroupBooking: true,
        isLargePartyRequest: false,
        isUpcomingNight: false,
        goingMode: 'party_request',
        tablePackage: g.title || 'Group Booking',
        customer: g.user ? {
            id: g.user.id,
            firstName: g.user.firstName,
            lastName: g.user.lastName,
            email: g.user.email,
            phone: g.user.phone,
            profileImageUrl: g.user.profileImageUrl,
        } : undefined,
        venue: g.venue ? {
            id: g.venue.id,
            name: g.venue.name,
            city: g.venue.city,
            category: g.venue.category,
        } : undefined,
        createdAt: g.createdAt,
        updatedAt: g.updatedAt,
    };
}

/**
 * @desc    Get all bookings with filters, search, and pagination
 * @route   GET /api/admin/bookings
 * @access  Private/Admin or Venue Owner
 */
export const getBookings = async (req: Request, res: Response) => {
    try {
        const {
            venueId,
            status,
            goingMode,
            isGroupBooking,
            isLargePartyRequest,
            isUpcomingNight,
            date,
            search,
            page = '1',
            limit = '20',
            sortBy = 'createdAt',
            sortOrder = 'DESC'
        } = req.query;

        const where: any = {};

        // Venue owner role scoping: restrict results to their own venues
        if (req.user?.role === 'venue_owner') {
            const ownedVenues = await Venue.findAll({
                where: { ownerId: req.user.id },
                attributes: ['id']
            });
            const ownedVenueIds = ownedVenues.map(v => v.id);
            if (venueId) {
                if (ownedVenueIds.includes(venueId as string)) {
                    where.venueId = venueId;
                } else {
                    return res.status(403).json({ success: false, message: 'Access denied to this venue' });
                }
            } else {
                where.venueId = { [Op.in]: ownedVenueIds };
            }
        } else if (venueId) {
            where.venueId = venueId;
        }

        if (status) where.status = status;

        const isGroupRequested = String(isGroupBooking) === 'true';
        const isLargeRequested = String(isLargePartyRequest) === 'true';
        const isUpcomingRequested = String(isUpcomingNight) === 'true';

        if (goingMode === 'solo') {
            where.goingMode = { [Op.or]: ['solo', { [Op.is]: null }] };
            where.isGroupBooking = { [Op.or]: [false, { [Op.is]: null }] };
            where.isLargePartyRequest = { [Op.or]: [false, { [Op.is]: null }] };
        } else if (goingMode === 'plan') {
            where.goingMode = 'plan';
        } else if (goingMode === 'party_request') {
            where.goingMode = 'party_request';
        } else if (goingMode && ['solo', 'plan', 'party_request'].includes(String(goingMode))) {
            where.goingMode = goingMode;
        }

        if (isGroupRequested) where.isGroupBooking = true;
        if (isLargeRequested) {
            where.isLargePartyRequest = true;
            where.numberOfGuests = { [Op.gt]: 20 };
        }
        if (isUpcomingRequested) where.isUpcomingNight = true;

        if (date === 'today') {
            const todayStr = new Date().toISOString().split('T')[0];
            where.bookingDate = todayStr;
        } else if (date) {
            where.bookingDate = date;
        }

        if (search) {
            where[Op.or] = [
                { bookingNumber: { [Op.iLike]: `%${search}%` } },
                { ticketCode: { [Op.iLike]: `%${search}%` } },
                { '$customer.firstName$': { [Op.iLike]: `%${search}%` } },
                { '$customer.lastName$': { [Op.iLike]: `%${search}%` } },
                { '$customer.email$': { [Op.iLike]: `%${search}%` } },
                { '$customer.phone$': { [Op.iLike]: `%${search}%` } }
            ];
        }

        const pageNum = Math.max(1, parseInt(page as string));
        const limitNum = Math.min(100, Math.max(1, parseInt(limit as string)));
        const offset = (pageNum - 1) * limitNum;

        // 1. Fetch primary Booking records
        let mainBookings = await Booking.findAll({
            where,
            include: [
                {
                    model: User,
                    as: 'customer',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl']
                },
                {
                    model: Venue,
                    as: 'venue',
                    attributes: ['id', 'name', 'city', 'category']
                }
            ],
            order: [[sortBy as string, sortOrder as string]],
        });

        let mappedList: any[] = mainBookings.map(b => b.toJSON());

        // 2. Aggregate PartyPlan records if 'plan' tab or general view
        if (!goingMode || goingMode === 'plan') {
            try {
                const partyPlans = await PartyPlan.findAll({
                    include: [
                        { model: User, as: 'creator', attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'] },
                        { model: Venue, as: 'venue', attributes: ['id', 'name', 'city', 'category'] }
                    ],
                    order: [['createdAt', 'DESC']],
                });
                const mappedPlans = partyPlans.map(mapPartyPlanToBooking);
                const existingIds = new Set(mappedList.map(b => b.id));
                for (const p of mappedPlans) {
                    if (!existingIds.has(p.id)) {
                        mappedList.push(p);
                    }
                }
            } catch (pErr) {
                logger.warn('Failed to fetch PartyPlans in getBookings:', pErr);
            }
        }

        // 3. Aggregate GroupParty records if 'group' tab, 'party_request' tab, or general view
        if (!goingMode || isGroupRequested || goingMode === 'party_request') {
            try {
                const groupParties = await GroupParty.findAll({
                    include: [
                        { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'] },
                        { model: Venue, as: 'venue', attributes: ['id', 'name', 'city', 'category'] }
                    ],
                    order: [['createdAt', 'DESC']],
                });
                const mappedGroups = groupParties.map(mapGroupPartyToBooking);
                const existingIds = new Set(mappedList.map(b => b.id));
                for (const g of mappedGroups) {
                    if (!existingIds.has(g.id)) {
                        mappedList.push(g);
                    }
                }
            } catch (gErr) {
                logger.warn('Failed to fetch GroupParties in getBookings:', gErr);
            }
        }

        // Apply pagination in memory over aggregated data
        const total = mappedList.length;
        const pagedBookings = mappedList.slice(offset, offset + limitNum);

        return res.json({
            success: true,
            data: {
                bookings: pagedBookings,
                pagination: {
                    page: pageNum,
                    limit: limitNum,
                    total,
                    totalPages: Math.ceil(total / limitNum)
                }
            }
        });
    } catch (err: any) {
        logger.error('getBookings error:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

/**
 * @desc    Get bookings stats summary
 * @route   GET /api/admin/bookings/stats
 * @access  Private/Admin or Venue Owner
 */
export const getBookingStats = async (req: Request, res: Response) => {
    try {
        const where: any = {};
        
        // Scope to venue owner if applicable
        if (req.user?.role === 'venue_owner') {
            const ownedVenues = await Venue.findAll({
                where: { ownerId: req.user.id },
                attributes: ['id']
            });
            const ownedVenueIds = ownedVenues.map(v => v.id);
            where.venueId = { [Op.in]: ownedVenueIds };
        }

        const totalBookings = await Booking.count({ where });
        const pendingBookings = await Booking.count({
            where: { ...where, status: 'pending' }
        });
        const confirmedBookings = await Booking.count({
            where: { ...where, status: 'confirmed' }
        });

        // Calculate total revenue from totalAmount where status is confirmed/completed and paid
        const totalRevenueResult = await Booking.sum('totalAmount', {
            where: {
                ...where,
                status: { [Op.in]: ['confirmed', 'completed'] },
                paymentStatus: 'paid'
            }
        });

        return res.json({
            success: true,
            data: {
                totalBookings,
                pendingBookings,
                confirmedBookings,
                totalRevenue: totalRevenueResult || 0
            }
        });
    } catch (err: any) {
        logger.error('getBookingStats error:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

export const confirmBooking = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const booking = await Booking.findByPk(id);
        if (!booking) {
            // Fallback to GroupParty
            const groupParty = await GroupParty.findByPk(id);
            if (!groupParty) {
                return res.status(404).json({ success: false, message: 'Booking or Group Party not found' });
            }
            await groupParty.update({ status: GroupPartyStatus.CONFIRMED });
            
            try {
                const host = await User.findByPk(groupParty.userId, { attributes: ['id', 'fcmToken'] });
                const venue = await Venue.findByPk(groupParty.venueId, { attributes: ['id', 'name'] });
                const venueName = venue?.name || 'Venue';
                if (host && host.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(host.fcmToken, {
                        title: 'Group Party Confirmed! 🎉',
                        body: `Your group party of ${groupParty.numberOfFriends} friends at ${venueName} is confirmed!`,
                        data: {
                            type: 'group_party_confirmed',
                            partyId: groupParty.id,
                        }
                    });
                }
                const { io } = require('../server');
                io.to(`user_${groupParty.userId}`).emit('large_party_status_update', {
                    bookingId: groupParty.id,
                    status: groupParty.status
                });

                // Emit notification_created
                io.to(`user_${groupParty.userId}`).emit('notification_created', {
                    id: `group_party_${groupParty.id}_confirmed`,
                    title: 'Group Party Confirmed! 🎉',
                    body: `Your group party of ${groupParty.numberOfFriends} friends at ${venueName} is confirmed!`,
                    createdAt: new Date().toISOString(),
                    read: false,
                    data: {
                        type: 'group_party_confirmed',
                        partyId: groupParty.id,
                    }
                });
            } catch (pushErr) {
                logger.warn('Failed to send push/socket for group party confirmation: ' + pushErr);
            }

            return res.json({ success: true, message: 'Group Party confirmed successfully', data: groupParty });
        }

        // Standard booking
        await booking.update({ status: 'confirmed' as any });

        try {
            const customer = await User.findByPk(booking.userId, { attributes: ['id', 'fcmToken'] });
            const venue = await Venue.findByPk(booking.venueId, { attributes: ['id', 'name'] });
            const venueName = venue?.name || 'Venue';
            
            const isLargeParty = booking.goingMode === 'party_request';
            const title = isLargeParty ? 'Large Party Confirmed! 🎉' : 'Booking Confirmed! 🎉';
            const body = isLargeParty 
                ? `Your party of ${booking.numberOfGuests} guests at ${venueName} is fully confirmed. Enjoy your night!`
                : `Your booking at ${venueName} has been confirmed. Enjoy your night!`;
            const type = isLargeParty ? 'large_party_confirmed' : 'booking_confirmed';

            if (customer && customer.fcmToken) {
                const { sendPushNotification } = require('../services/fcmService');
                await sendPushNotification(customer.fcmToken, {
                    title,
                    body,
                    data: {
                        type,
                        bookingId: booking.id,
                    }
                });
            }

            const { io } = require('../server');
            io.to(`user_${booking.userId}`).emit('large_party_status_update', {
                bookingId: booking.id,
                status: booking.status
            });

            // Emit notification_created
            io.to(`user_${booking.userId}`).emit('notification_created', {
                id: `${isLargeParty ? 'large_party' : 'solo_booking'}_${booking.id}_confirmed`,
                title,
                body,
                createdAt: new Date().toISOString(),
                read: false,
                data: {
                    type,
                    bookingId: booking.id,
                }
            });
        } catch (pushErr) {
            logger.warn('Failed to send push/socket for booking confirmation: ' + pushErr);
        }

        return res.json({ success: true, message: 'Booking confirmed successfully', data: booking });
    } catch (err: any) {
        logger.error('confirmBooking error:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

export const cancelBooking = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const { reason } = req.body;
        const booking = await Booking.findByPk(id);
        if (!booking) {
            // Fallback to GroupParty
            const groupParty = await GroupParty.findByPk(id);
            if (!groupParty) {
                return res.status(404).json({ success: false, message: 'Booking or Group Party not found' });
            }
            await groupParty.update({ status: GroupPartyStatus.CANCELLED });
            await PlanEligibilityService.releaseLock(id);
            
            try {
                const host = await User.findByPk(groupParty.userId, { attributes: ['id', 'fcmToken'] });
                const venue = await Venue.findByPk(groupParty.venueId, { attributes: ['id', 'name'] });
                const venueName = venue?.name || 'Venue';
                if (host && host.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(host.fcmToken, {
                        title: 'Group Party Cancelled ❌',
                        body: `Your group party booking at ${venueName} was cancelled. Reason: ${reason || 'N/A'}`,
                        data: {
                            type: 'group_party_cancelled',
                            partyId: groupParty.id,
                        }
                    });
                }
                const { io } = require('../server');
                io.to(`user_${groupParty.userId}`).emit('large_party_status_update', {
                    bookingId: groupParty.id,
                    status: groupParty.status
                });

                // Emit notification_created
                io.to(`user_${groupParty.userId}`).emit('notification_created', {
                    id: `group_party_${groupParty.id}_cancelled`,
                    title: 'Group Party Cancelled ❌',
                    body: `Your group party booking at ${venueName} was cancelled.`,
                    createdAt: new Date().toISOString(),
                    read: false,
                    data: {
                        type: 'group_party_cancelled',
                        partyId: groupParty.id,
                    }
                });
            } catch (pushErr) {
                logger.warn('Failed to send push/socket for group party cancellation: ' + pushErr);
            }

            return res.json({ success: true, message: 'Group Party cancelled successfully', data: groupParty });
        }

        // Standard booking
        await booking.update({ status: 'cancelled' as any });
        await PlanEligibilityService.releaseLock(id);

        try {
            const customer = await User.findByPk(booking.userId, { attributes: ['id', 'fcmToken'] });
            const venue = await Venue.findByPk(booking.venueId, { attributes: ['id', 'name'] });
            const venueName = venue?.name || 'Venue';
            
            const isLargeParty = booking.goingMode === 'party_request';
            const title = isLargeParty ? 'Large Party Request Rejected ❌' : 'Booking Cancelled ❌';
            const body = isLargeParty 
                ? `Your party request at ${venueName} was rejected by admin. Reason: ${reason || 'N/A'}`
                : `Your booking at ${venueName} was cancelled. Reason: ${reason || 'N/A'}`;
            const type = isLargeParty ? 'large_party_rejected' : 'booking_cancelled';

            if (customer && customer.fcmToken) {
                const { sendPushNotification } = require('../services/fcmService');
                await sendPushNotification(customer.fcmToken, {
                    title,
                    body,
                    data: {
                        type,
                        bookingId: booking.id,
                    }
                });
            }

            const { io } = require('../server');
            io.to(`user_${booking.userId}`).emit('large_party_status_update', {
                bookingId: booking.id,
                status: booking.status
            });

            // Emit notification_created
            io.to(`user_${booking.userId}`).emit('notification_created', {
                id: `${isLargeParty ? 'large_party' : 'solo_booking'}_${booking.id}_cancelled`,
                title,
                body,
                createdAt: new Date().toISOString(),
                read: false,
                data: {
                    type,
                    bookingId: booking.id,
                }
            });
        } catch (pushErr) {
            logger.warn('Failed to send push/socket for booking cancellation: ' + pushErr);
        }

        return res.json({ success: true, message: 'Booking cancelled successfully', data: booking });
    } catch (err: any) {
        logger.error('cancelBooking error:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

export const markCompleted = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const booking = await Booking.findByPk(id);
        if (!booking) {
            return res.status(404).json({ success: false, message: 'Booking not found' });
        }
        await booking.update({ status: 'completed' as any });

        try {
            const customer = await User.findByPk(booking.userId, { attributes: ['id', 'fcmToken'] });
            const venue = await Venue.findByPk(booking.venueId, { attributes: ['id', 'name'] });
            const venueName = venue?.name || 'Venue';
            
            const title = 'Booking Completed ✨';
            const body = `We hope you had a great time at ${venueName}!`;
            const type = 'booking_completed';

            if (customer && customer.fcmToken) {
                const { sendPushNotification } = require('../services/fcmService');
                await sendPushNotification(customer.fcmToken, {
                    title,
                    body,
                    data: {
                        type,
                        bookingId: booking.id,
                    }
                });
            }

            const { io } = require('../server');
            io.to(`user_${booking.userId}`).emit('large_party_status_update', {
                bookingId: booking.id,
                status: booking.status
            });

            // Emit notification_created
            io.to(`user_${booking.userId}`).emit('notification_created', {
                id: `solo_booking_${booking.id}_completed`,
                title,
                body,
                createdAt: new Date().toISOString(),
                read: false,
                data: {
                    type,
                    bookingId: booking.id,
                }
            });
        } catch (pushErr) {
            logger.warn('Failed to send push/socket for booking completion: ' + pushErr);
        }

        return res.json({ success: true, message: 'Booking marked completed successfully', data: booking });
    } catch (err: any) {
        logger.error('markCompleted error:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

export const markNoShow = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const booking = await Booking.findByPk(id);
        if (!booking) {
            return res.status(404).json({ success: false, message: 'Booking not found' });
        }
        await booking.update({ status: 'no_show' as any });

        try {
            const customer = await User.findByPk(booking.userId, { attributes: ['id', 'fcmToken'] });
            const venue = await Venue.findByPk(booking.venueId, { attributes: ['id', 'name'] });
            const venueName = venue?.name || 'Venue';
            
            const title = 'Booking No-Show ⚠️';
            const body = `Your booking at ${venueName} was marked as no-show.`;
            const type = 'booking_no_show';

            if (customer && customer.fcmToken) {
                const { sendPushNotification } = require('../services/fcmService');
                await sendPushNotification(customer.fcmToken, {
                    title,
                    body,
                    data: {
                        type,
                        bookingId: booking.id,
                    }
                });
            }

            const { io } = require('../server');
            io.to(`user_${booking.userId}`).emit('large_party_status_update', {
                bookingId: booking.id,
                status: booking.status
            });

            // Emit notification_created
            io.to(`user_${booking.userId}`).emit('notification_created', {
                id: `solo_booking_${booking.id}_no_show`,
                title,
                body,
                createdAt: new Date().toISOString(),
                read: false,
                data: {
                    type,
                    bookingId: booking.id,
                }
            });
        } catch (pushErr) {
            logger.warn('Failed to send push/socket for booking no-show: ' + pushErr);
        }

        return res.json({ success: true, message: 'Booking marked no-show successfully', data: booking });
    } catch (err: any) {
        logger.error('markNoShow error:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

export const getVenueWiseBookingSummary = async (req: Request, res: Response) => {
    try {
        const page = parseInt(req.query.page as string) || 1;
        const limit = parseInt(req.query.limit as string) || 10;
        const offset = (page - 1) * limit;

        const { fromDate, toDate, venueId, bookingStatus, paymentStatus, search } = req.query;

        // Build Venue where clause for search
        let venueWhere: any = {};
        if (venueId && venueId !== 'all') {
            venueWhere.id = venueId;
        }
        if (search) {
            venueWhere.name = { [Op.iLike]: `%${search}%` };
        }

        // 1. Fetch paginated venues
        const { rows: venues, count: totalVenues } = await Venue.findAndCountAll({
            where: venueWhere,
            attributes: ['id', 'name', 'city'],
            order: [['name', 'ASC']],
            limit,
            offset
        });

        if (venues.length === 0) {
            return res.json({
                success: true,
                data: {
                    summary: { totalVenues: 0, totalBookings: 0, totalConfirmed: 0, totalCancelled: 0, totalAmount: 0, totalPaid: 0, totalPending: 0 },
                    venues: [],
                    pagination: { total: 0, page, limit, totalPages: 0 }
                }
            });
        }

        const venueIds = venues.map(v => v.id);

        // Build Booking where clause
        let bookingWhere: any = { venueId: { [Op.in]: venueIds } };
        
        if (fromDate && toDate) {
            const fDate = new Date(fromDate as string);
            const tDate = new Date(toDate as string);
            tDate.setHours(23, 59, 59, 999);
            const toDateStr = `${toDate} 23:59:59`;

            bookingWhere[Op.or] = [
                { bookingDate: { [Op.between]: [fromDate, toDateStr] } },
                { bookingDate: { [Op.between]: [fDate, tDate] } },
                { createdAt: { [Op.between]: [fDate, tDate] } }
            ];
        } else if (fromDate) {
            const fDate = new Date(fromDate as string);
            bookingWhere[Op.or] = [
                { bookingDate: { [Op.gte]: fromDate } },
                { createdAt: { [Op.gte]: fDate } }
            ];
        } else if (toDate) {
            const tDate = new Date(toDate as string);
            tDate.setHours(23, 59, 59, 999);
            const toDateStr = `${toDate} 23:59:59`;
            bookingWhere[Op.or] = [
                { bookingDate: { [Op.lte]: toDateStr } },
                { createdAt: { [Op.lte]: tDate } }
            ];
        }

        if (bookingStatus && bookingStatus !== 'all') {
            bookingWhere.status = bookingStatus;
        }
        if (paymentStatus && paymentStatus !== 'all') {
            bookingWhere.paymentStatus = paymentStatus;
        }

        // 2. Fetch all bookings for these venues
        const bookings = await Booking.findAll({
            where: bookingWhere,
            include: [
                {
                    model: Payment,
                    as: 'payments',
                    attributes: ['amount', 'refundAmount', 'status']
                }
            ]
        });

        // 3. Aggregate data per venue
        const venueMap = new Map();
        venues.forEach(v => {
            venueMap.set(v.id, {
                venueId: v.id,
                venueName: `${v.name} (${v.city})`,
                totalBookings: 0,
                confirmedBookings: 0,
                pendingBookings: 0,
                cancelledBookings: 0,
                completedBookings: 0,
                totalBookingAmount: 0,
                paidAmount: 0,
                pendingAmount: 0,
                refundAmount: 0,
            });
        });

        let grandTotals = {
            totalVenues: totalVenues,
            totalBookings: 0,
            totalConfirmed: 0,
            totalCancelled: 0,
            totalAmount: 0,
            totalPaid: 0,
            totalPending: 0,
            todaysBookingCount: 0,
            todaysBookingAmount: 0,
            soloBookingCount: 0,
            soloBookingAmount: 0,
            partyPlansCount: 0,
            partyPlansAmount: 0,
            partyRequestsCount: 0,
            partyRequestsAmount: 0,
            groupPartyBookingCount: 0,
            groupPartyBookingAmount: 0,
            largePartiesCount: 0,
            largePartiesAmount: 0,
            upcomingNightBookingCount: 0,
            upcomingNightBookingAmount: 0
        };

        const todayStart = new Date();
        todayStart.setHours(0, 0, 0, 0);
        const todayEnd = new Date();
        todayEnd.setHours(23, 59, 59, 999);


        bookings.forEach(b => {
            const vStat = venueMap.get(b.venueId);
            if (!vStat) return;

            vStat.totalBookings++;
            grandTotals.totalBookings++;

            const bAmount = Number(b.totalAmount) || 0;

            if (b.createdAt && b.createdAt >= todayStart && b.createdAt <= todayEnd) {
                grandTotals.todaysBookingCount++;
                grandTotals.todaysBookingAmount += bAmount;
            }

            if (b.goingMode === 'solo') {
                grandTotals.soloBookingCount++;
                grandTotals.soloBookingAmount += bAmount;
            } else if (b.goingMode === 'plan') {
                grandTotals.partyPlansCount++;
                grandTotals.partyPlansAmount += bAmount;
            } else if (b.goingMode === 'party_request') {
                grandTotals.partyRequestsCount++;
                grandTotals.partyRequestsAmount += bAmount;
            }

            if (b.isGroupBooking) {
                grandTotals.groupPartyBookingCount++;
                grandTotals.groupPartyBookingAmount += bAmount;
            }

            if (b.isLargePartyRequest) {
                grandTotals.largePartiesCount++;
                grandTotals.largePartiesAmount += bAmount;
            }

            if (b.isUpcomingNight) {
                grandTotals.upcomingNightBookingCount++;
                grandTotals.upcomingNightBookingAmount += bAmount;
            }

            if (b.status === 'confirmed') {
                vStat.confirmedBookings++;
                grandTotals.totalConfirmed++;
            } else if (b.status === 'pending') {
                vStat.pendingBookings++;
            } else if (b.status === 'cancelled') {
                vStat.cancelledBookings++;
                grandTotals.totalCancelled++;
            } else if (b.status === 'completed') {
                vStat.completedBookings++;
            }

            // Amounts
            vStat.totalBookingAmount += bAmount;
            grandTotals.totalAmount += bAmount;

            // Calculate paid & refund from payments
            let bPaid = 0;
            let bRefund = 0;

            const bookingData: any = b;

            if (bookingData.payments && bookingData.payments.length > 0) {
                bookingData.payments.forEach((p: any) => {
                    if (p.status === 'successful') {
                        bPaid += Number(p.amount) || 0;
                    }
                    bRefund += Number(p.refundAmount) || 0;
                });
            } else {
                // fallback if no payment record exists but booking says paid
                if (b.paymentStatus === 'paid') {
                    bPaid = bAmount;
                } else {
                    bPaid = Number(b.depositAmount) || 0;
                }
            }

            vStat.paidAmount += bPaid;
            grandTotals.totalPaid += bPaid;

            vStat.refundAmount += bRefund;
            
            // pending is whatever is not paid from total
            const bPending = Math.max(0, bAmount - bPaid);
            vStat.pendingAmount += bPending;
            grandTotals.totalPending += bPending;
        });

        const sortedVenues = Array.from(venueMap.values());

        return res.json({
            success: true,
            data: {
                summary: grandTotals,
                venues: sortedVenues,
                pagination: {
                    total: totalVenues,
                    page,
                    limit,
                    totalPages: Math.ceil(totalVenues / limit)
                }
            }
        });

    } catch (error: any) {
        logger.error('getVenueWiseBookingSummary error:', error);
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const getVenueRevenueDetails = async (req: Request, res: Response) => {
    try {
        const { venueId, period = 'monthly', fromDate, toDate, page = '1', limit = '15', search, status } = req.query;

        if (!venueId) {
            return res.status(400).json({ success: false, message: 'venueId is required' });
        }

        const venue = await Venue.findByPk(venueId as string);

        if (!venue) {
            return res.status(404).json({ success: false, message: 'Venue not found' });
        }

        // Determine date range filters
        let startDate: Date;
        let endDate: Date = new Date();
        endDate.setHours(23, 59, 59, 999);

        const periodStr = (period as string).toLowerCase();

        if (fromDate && toDate) {
            startDate = new Date(fromDate as string);
            startDate.setHours(0, 0, 0, 0);
            endDate = new Date(toDate as string);
            endDate.setHours(23, 59, 59, 999);
        } else if (fromDate) {
            startDate = new Date(fromDate as string);
            startDate.setHours(0, 0, 0, 0);
        } else if (toDate) {
            endDate = new Date(toDate as string);
            endDate.setHours(23, 59, 59, 999);
            startDate = new Date(endDate);
            startDate.setMonth(startDate.getMonth() - 1, 1);
            startDate.setHours(0, 0, 0, 0);
        } else if (periodStr === 'daily') {
            startDate = new Date();
            startDate.setDate(startDate.getDate() - 29);
            startDate.setHours(0, 0, 0, 0);
        } else if (periodStr === 'weekly') {
            startDate = new Date();
            startDate.setDate(startDate.getDate() - (12 * 7));
            startDate.setHours(0, 0, 0, 0);
        } else if (periodStr === 'yearly') {
            startDate = new Date();
            startDate.setFullYear(startDate.getFullYear() - 4, 0, 1);
            startDate.setHours(0, 0, 0, 0);
        } else {
            // Monthly - default last 12 months
            startDate = new Date();
            startDate.setMonth(startDate.getMonth() - 11, 1);
            startDate.setHours(0, 0, 0, 0);
        }

        if (isNaN(startDate.getTime())) {
            startDate = new Date();
            startDate.setMonth(startDate.getMonth() - 11, 1);
            startDate.setHours(0, 0, 0, 0);
        }
        if (isNaN(endDate.getTime())) {
            endDate = new Date();
            endDate.setHours(23, 59, 59, 999);
        }

        const startDateStr = startDate.toISOString().split('T')[0];
        const endDateStr = endDate.toISOString().split('T')[0];
        const endDateFullStr = `${endDateStr} 23:59:59`;

        // Build Booking query matching bookingDate as Date, string, and createdAt fallback
        let bookingWhere: any = {
            venueId: venue.id,
            [Op.or]: [
                { bookingDate: { [Op.between]: [startDate, endDate] } },
                { bookingDate: { [Op.between]: [startDateStr, endDateFullStr] } },
                { createdAt: { [Op.between]: [startDate, endDate] } }
            ]
        };

        if (status && status !== 'all') {
            bookingWhere.status = status;
        }

        // Fetch bookings with payments & user info
        const bookings = await Booking.findAll({
            where: bookingWhere,
            include: [
                {
                    model: Payment,
                    as: 'payments',
                    attributes: ['amount', 'refundAmount', 'status']
                },
                {
                    model: User,
                    as: 'user',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone']
                }
            ],
            order: [['bookingDate', 'DESC'], ['createdAt', 'DESC']]
        });

        // Initialize KPIs
        let summary = {
            totalBookings: 0,
            confirmedBookings: 0,
            pendingBookings: 0,
            cancelledBookings: 0,
            completedBookings: 0,
            totalBookingAmount: 0,
            paidAmount: 0,
            pendingAmount: 0,
            refundAmount: 0,
            avgBookingValue: 0
        };

        // Mode breakdown
        const modeBreakdown: Record<string, { count: number; totalAmount: number; paidAmount: number }> = {
            solo: { count: 0, totalAmount: 0, paidAmount: 0 },
            party_request: { count: 0, totalAmount: 0, paidAmount: 0 },
            group_party: { count: 0, totalAmount: 0, paidAmount: 0 },
            large_party: { count: 0, totalAmount: 0, paidAmount: 0 },
            upcoming_night: { count: 0, totalAmount: 0, paidAmount: 0 }
        };

        // Trend aggregation map
        const trendMap = new Map<string, { label: string; dateKey: string; totalAmount: number; paidAmount: number; pendingAmount: number; bookingCount: number }>();

        // Pre-fill trend keys for smooth charts
        if (periodStr === 'daily' || periodStr === 'custom') {
            const curr = new Date(startDate);
            while (curr <= endDate) {
                const dateKey = curr.toISOString().split('T')[0];
                const label = curr.toLocaleDateString('en-IN', { day: '2-digit', month: 'short' });
                trendMap.set(dateKey, { label, dateKey, totalAmount: 0, paidAmount: 0, pendingAmount: 0, bookingCount: 0 });
                curr.setDate(curr.getDate() + 1);
            }
        } else if (periodStr === 'weekly') {
            for (let i = 11; i >= 0; i--) {
                const d = new Date();
                d.setDate(d.getDate() - (i * 7));
                const wkNum = getWeekNumber(d);
                const dateKey = `W${wkNum}-${d.getFullYear()}`;
                const label = `W${wkNum} (${d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short' })})`;
                trendMap.set(dateKey, { label, dateKey, totalAmount: 0, paidAmount: 0, pendingAmount: 0, bookingCount: 0 });
            }
        } else if (periodStr === 'monthly') {
            for (let i = 11; i >= 0; i--) {
                const d = new Date();
                d.setMonth(d.getMonth() - i, 1);
                const dateKey = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
                const label = d.toLocaleDateString('en-IN', { month: 'short', year: 'numeric' });
                trendMap.set(dateKey, { label, dateKey, totalAmount: 0, paidAmount: 0, pendingAmount: 0, bookingCount: 0 });
            }
        } else if (periodStr === 'yearly') {
            const currentYr = new Date().getFullYear();
            for (let i = 4; i >= 0; i--) {
                const yr = (currentYr - i).toString();
                trendMap.set(yr, { label: yr, dateKey: yr, totalAmount: 0, paidAmount: 0, pendingAmount: 0, bookingCount: 0 });
            }
        }

        const formattedRecords: any[] = [];

        bookings.forEach(b => {
            const bAmount = Number(b.totalAmount) || 0;
            summary.totalBookings++;
            summary.totalBookingAmount += bAmount;

            let bPaid = 0;
            let bRefund = 0;

            const bData: any = b;
            if (bData.payments && bData.payments.length > 0) {
                bData.payments.forEach((p: any) => {
                    const statusLower = (p.status || '').toString().toLowerCase();
                    if (['successful', 'paid', 'success', 'completed'].includes(statusLower)) {
                        bPaid += Number(p.amount) || 0;
                    }
                    bRefund += Number(p.refundAmount) || 0;
                });
            } else {
                if (b.paymentStatus === 'paid') {
                    bPaid = bAmount;
                } else if (b.paymentStatus === 'partially_paid') {
                    bPaid = Number(b.depositAmount) || 0;
                } else if (b.depositAmount && Number(b.depositAmount) > 0) {
                    bPaid = Number(b.depositAmount);
                }
            }

            if (bPaid > bAmount && bAmount > 0) {
                bPaid = bAmount;
            }

            const bPending = Math.max(0, bAmount - bPaid);
            summary.paidAmount += bPaid;
            summary.pendingAmount += bPending;
            summary.refundAmount += bRefund;

            if (b.status === 'confirmed') summary.confirmedBookings++;
            else if (b.status === 'pending') summary.pendingBookings++;
            else if (b.status === 'cancelled') summary.cancelledBookings++;
            else if (b.status === 'completed') summary.completedBookings++;

            // Mode breakdown
            let modeKey = 'solo';
            if (b.isLargePartyRequest) modeKey = 'large_party';
            else if (b.isGroupBooking) modeKey = 'group_party';
            else if (b.goingMode === 'party_request' || b.goingMode === 'plan') modeKey = 'party_request';
            else if (b.isUpcomingNight) modeKey = 'upcoming_night';

            if (modeBreakdown[modeKey]) {
                modeBreakdown[modeKey].count++;
                modeBreakdown[modeKey].totalAmount += bAmount;
                modeBreakdown[modeKey].paidAmount += bPaid;
            }

            // Trend grouping key
            const rawDate = b.bookingDate || b.createdAt;
            const bDate = rawDate ? new Date(rawDate) : new Date();
            if (isNaN(bDate.getTime())) return;
            let trendKey = '';

            if (periodStr === 'daily' || periodStr === 'custom') {
                trendKey = bDate.toISOString().split('T')[0];
            } else if (periodStr === 'weekly') {
                trendKey = `W${getWeekNumber(bDate)}-${bDate.getFullYear()}`;
            } else if (periodStr === 'monthly') {
                trendKey = `${bDate.getFullYear()}-${String(bDate.getMonth() + 1).padStart(2, '0')}`;
            } else if (periodStr === 'yearly') {
                trendKey = bDate.getFullYear().toString();
            }

            if (trendKey) {
                if (!trendMap.has(trendKey)) {
                    let label = trendKey;
                    if (periodStr === 'daily' || periodStr === 'custom') {
                        label = bDate.toLocaleDateString('en-IN', { day: '2-digit', month: 'short' });
                    } else if (periodStr === 'weekly') {
                        label = `W${getWeekNumber(bDate)} (${bDate.toLocaleDateString('en-IN', { day: '2-digit', month: 'short' })})`;
                    } else if (periodStr === 'monthly') {
                        label = bDate.toLocaleDateString('en-IN', { month: 'short', year: 'numeric' });
                    }
                    trendMap.set(trendKey, { label, dateKey: trendKey, totalAmount: 0, paidAmount: 0, pendingAmount: 0, bookingCount: 0 });
                }
                const item = trendMap.get(trendKey)!;
                item.totalAmount += bAmount;
                item.paidAmount += bPaid;
                item.pendingAmount += bPending;
                item.bookingCount++;
            }

            // User info
            const u = bData.user || bData.customer;
            const userName = u ? `${u.firstName || ''} ${u.lastName || ''}`.trim() || u.email || 'Guest' : 'Guest';

            formattedRecords.push({
                id: b.id,
                bookingDate: b.bookingDate,
                createdAt: b.createdAt,
                userName,
                userMobile: u?.phone || (u as any)?.mobileNumber || b.mobileNumber || 'N/A',
                userEmail: u?.email || 'N/A',
                goingMode: b.goingMode,
                numberOfGuests: b.numberOfGuests || 1,
                totalAmount: bAmount,
                paidAmount: bPaid,
                pendingAmount: bPending,
                status: b.status,
                paymentStatus: b.paymentStatus,
                isGroupBooking: b.isGroupBooking,
                isLargePartyRequest: b.isLargePartyRequest
            });
        });

        if (summary.totalBookings > 0) {
            summary.avgBookingValue = Math.round(summary.totalBookingAmount / summary.totalBookings);
        }

        // Apply search query to records if provided
        let filteredRecords = formattedRecords;
        if (search) {
            const q = (search as string).toLowerCase();
            filteredRecords = formattedRecords.filter(r =>
                r.userName.toLowerCase().includes(q) ||
                r.userMobile.toLowerCase().includes(q) ||
                r.id.toLowerCase().includes(q)
            );
        }

        // Pagination for records
        const pNum = parseInt(page as string) || 1;
        const lNum = parseInt(limit as string) || 15;
        const offset = (pNum - 1) * lNum;
        const paginatedRecords = filteredRecords.slice(offset, offset + lNum);

        return res.json({
            success: true,
            data: {
                venue: {
                    id: venue.id,
                    name: venue.name,
                    city: venue.city,
                    addressLine1: venue.addressLine1,
                    category: venue.category,
                    imageUrl: (venue as any).imageUrl || (venue as any).coverImageUrl || null
                },
                period: periodStr,
                fromDate: startDate.toISOString().split('T')[0],
                toDate: endDate.toISOString().split('T')[0],
                summary,
                modeBreakdown,
                trend: Array.from(trendMap.values()),
                records: paginatedRecords,
                pagination: {
                    total: filteredRecords.length,
                    page: pNum,
                    limit: lNum,
                    totalPages: Math.ceil(filteredRecords.length / lNum)
                }
            }
        });

    } catch (error: any) {
        logger.error('getVenueRevenueDetails error:', error);
        return res.status(500).json({ success: false, message: error.message });
    }
};

function getWeekNumber(d: Date): number {
    const target = new Date(d.valueOf());
    const dayNr = (d.getDay() + 6) % 7;
    target.setDate(target.getDate() - dayNr + 3);
    const firstThursday = target.valueOf();
    target.setMonth(0, 1);
    if (target.getDay() !== 4) {
        target.setMonth(0, 1 + ((4 - target.getDay() + 7) % 7));
    }
    return 1 + Math.ceil((firstThursday - target.valueOf()) / 604800000);
}




