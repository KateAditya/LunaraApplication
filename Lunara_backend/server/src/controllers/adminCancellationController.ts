import { Request, Response } from 'express';
import { Op } from 'sequelize';
import GroupParty from '../models/GroupParty';
import Booking from '../models/Booking';
import User from '../models/User';
import Venue from '../models/Venue';
import { logger } from '../config/logger';
import { NotificationService } from '../services/NotificationService';
import { RealtimeEventBroker } from '../services/RealtimeEventBroker';
import { GroupPartyService } from '../services/GroupPartyService';
import { VenueBookingService } from '../services/VenueBookingService';

export class AdminCancellationController {
    /**
     * GET /api/admin/bookings/group-party-cancellations
     * List cancelled group parties and with-friends bookings (especially > ₹1,500)
     */
    public static async getGroupPartyCancellations(req: Request, res: Response): Promise<Response> {
        try {
            const { status, search, page = '1', limit = '20' } = req.query;
            const pageNum = Math.max(1, parseInt(page as string) || 1);
            const limitNum = Math.min(100, Math.max(1, parseInt(limit as string) || 20));
            const offset = (pageNum - 1) * limitNum;

            // GroupParty search condition
            const gpWhere: any = {
                status: 'cancelled',
            };

            if (status === 'pending' || status === 'pending_payout') {
                gpWhere[Op.or] = [
                    { refundStatus: 'PENDING_PAYOUT' },
                    { paymentStatus: 'refund_processing' },
                ];
            } else if (status === 'completed' || status === 'paid') {
                gpWhere[Op.or] = [
                    { refundStatus: 'COMPLETED' },
                    { paymentStatus: 'refunded' },
                ];
            }

            // Booking search condition (with friends or small group)
            const bkWhere: any = {
                status: 'cancelled',
                [Op.or]: [
                    { goingMode: 'with_friends' },
                    { goingMode: 'party_request' },
                    { numberOfGuests: { [Op.between]: [2, 20] } },
                ],
            };

            if (status === 'pending' || status === 'pending_payout') {
                bkWhere[Op.and] = [
                    {
                        [Op.or]: [
                            { refundStatus: 'PENDING_PAYOUT' },
                            { paymentStatus: 'refund_processing' },
                        ],
                    },
                ];
            } else if (status === 'completed' || status === 'paid') {
                bkWhere[Op.and] = [
                    {
                        [Op.or]: [
                            { refundStatus: 'COMPLETED' },
                            { paymentStatus: 'refunded' },
                        ],
                    },
                ];
            }

            const [groupParties, bookings] = await Promise.all([
                GroupParty.findAll({
                    where: gpWhere,
                    include: [
                        {
                            model: User,
                            as: 'creator',
                            attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                        },
                        {
                            model: Venue,
                            as: 'venue',
                            attributes: ['id', 'name', 'city', 'addressLine1'],
                        },
                    ],
                    order: [['cancelledAt', 'DESC'], ['createdAt', 'DESC']],
                }),
                Booking.findAll({
                    where: bkWhere,
                    include: [
                        {
                            model: User,
                            as: 'customer',
                            attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                        },
                        {
                            model: Venue,
                            as: 'venue',
                            attributes: ['id', 'name', 'city', 'addressLine1'],
                        },
                    ],
                    order: [['cancelledAt', 'DESC'], ['createdAt', 'DESC']],
                }),
            ]);

            // Normalize results
            const normalizedGP = groupParties.map((gp: any) => {
                const refundAmt = Number(gp.refundAmount || 0);
                const isOver1500 = refundAmt > 1500 || gp.refundMethod === 'BANK_UPI';
                return {
                    id: gp.id,
                    bookingType: 'group_party',
                    bookingId: gp.id,
                    partyDate: gp.partyDate,
                    startTime: gp.startTime,
                    numberOfGuests: gp.numberOfFriends || 1,
                    totalAmount: Number(gp.totalAmount || 0),
                    refundAmount: refundAmt,
                    isOver1500,
                    refundStatus: gp.refundStatus || (gp.paymentStatus === 'refunded' ? 'COMPLETED' : 'PENDING_PAYOUT'),
                    paymentStatus: gp.paymentStatus,
                    refundMethod: gp.refundMethod || (isOver1500 ? 'BANK_UPI' : 'WALLET'),
                    payoutType: gp.payoutType || 'UPI_ID',
                    upiId: gp.upiId || null,
                    upiNumber: gp.upiNumber || null,
                    bankAccountNumber: gp.bankAccountNumber || null,
                    bankIfsc: gp.bankIfsc || null,
                    bankHolderName: gp.bankHolderName || null,
                    cancellationReason: gp.cancellationReason || null,
                    paymentReference: gp.refundTransactionReference || null,
                    adminNotes: gp.adminNotes || null,
                    cancelledAt: gp.cancelledAt || gp.updatedAt,
                    paidAt: gp.refundPaidAt || null,
                    user: gp.creator || null,
                    venue: gp.venue || null,
                };
            });

            const normalizedBK = bookings.map((bk: any) => {
                const refundAmt = Number(bk.refundAmount || 0);
                const isOver1500 = refundAmt > 1500 || bk.refundMethod === 'BANK_UPI';
                return {
                    id: bk.id,
                    bookingType: 'booking',
                    bookingId: bk.id,
                    partyDate: bk.bookingDate,
                    startTime: bk.startTime,
                    numberOfGuests: bk.numberOfGuests || 1,
                    totalAmount: Number(bk.totalAmount || 0),
                    refundAmount: refundAmt,
                    isOver1500,
                    refundStatus: bk.refundStatus || (bk.paymentStatus === 'refunded' ? 'COMPLETED' : 'PENDING_PAYOUT'),
                    paymentStatus: bk.paymentStatus,
                    refundMethod: bk.refundMethod || (isOver1500 ? 'BANK_UPI' : 'WALLET'),
                    payoutType: bk.payoutType || 'UPI_ID',
                    upiId: bk.upiId || null,
                    upiNumber: bk.upiNumber || null,
                    bankAccountNumber: bk.bankAccountNumber || null,
                    bankIfsc: bk.bankIfsc || null,
                    bankHolderName: bk.bankHolderName || null,
                    cancellationReason: bk.cancellationReason || null,
                    paymentReference: bk.refundTransactionReference || null,
                    adminNotes: bk.adminNotes || null,
                    cancelledAt: bk.cancelledAt || bk.updatedAt,
                    paidAt: bk.refundPaidAt || null,
                    user: bk.customer || null,
                    venue: bk.venue || null,
                };
            });

            // Combine and prioritize > 1500 / PENDING_PAYOUT
            let combined = [...normalizedGP, ...normalizedBK];

            // Filter for search string
            if (search && typeof search === 'string' && search.trim().length > 0) {
                const q = search.trim().toLowerCase();
                combined = combined.filter((item) => {
                    const u = item.user;
                    const v = item.venue;
                    const userName = `${u?.firstName || ''} ${u?.lastName || ''}`.toLowerCase();
                    const userPhone = (u?.phone || '').toLowerCase();
                    const userEmail = (u?.email || '').toLowerCase();
                    const venueName = (v?.name || '').toLowerCase();
                    const upi = (item.upiId || '').toLowerCase();
                    return userName.includes(q) || userPhone.includes(q) || userEmail.includes(q) || venueName.includes(q) || upi.includes(q);
                });
            }

            // Calculate KPIs
            const totalPending = combined.filter((c) => c.refundStatus === 'PENDING_PAYOUT' || c.paymentStatus === 'refund_processing').length;
            const totalCompleted = combined.filter((c) => c.refundStatus === 'COMPLETED' || c.paymentStatus === 'refunded').length;
            const totalRefundAmount = combined.reduce((acc, c) => acc + (c.refundAmount || 0), 0);
            const totalRequests = combined.length;

            // Sort by cancelledAt DESC
            combined.sort((a, b) => new Date(b.cancelledAt || 0).getTime() - new Date(a.cancelledAt || 0).getTime());

            // Paginate
            const paginated = combined.slice(offset, offset + limitNum);

            return res.json({
                success: true,
                data: paginated,
                pagination: {
                    page: pageNum,
                    limit: limitNum,
                    total: totalRequests,
                    totalPages: Math.ceil(totalRequests / limitNum),
                },
                kpis: {
                    totalRequests,
                    totalPending,
                    totalCompleted,
                    totalRefundAmount,
                },
            });
        } catch (err: any) {
            logger.error('[AdminCancellationController] getGroupPartyCancellations error:', err);
            return res.status(500).json({ success: false, message: err.message || 'Failed to fetch cancellations' });
        }
    }

    /**
     * GET /api/admin/bookings/group-party-cancellations/:id
     * Get detail of single cancelled group party
     */
    public static async getGroupPartyCancellationDetail(req: Request, res: Response): Promise<Response> {
        try {
            const { id } = req.params;

            // Try finding in GroupParty
            let party = await GroupParty.findByPk(id, {
                include: [
                    {
                        model: User,
                        as: 'creator',
                        attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                    },
                    {
                        model: Venue,
                        as: 'venue',
                        attributes: ['id', 'name', 'city', 'addressLine1'],
                    },
                ],
            });

            if (party) {
                const gpAny = party as any;
                const refundAmt = Number(gpAny.refundAmount || 0);
                return res.json({
                    success: true,
                    data: {
                        id: gpAny.id,
                        bookingType: 'group_party',
                        bookingId: gpAny.id,
                        partyDate: gpAny.partyDate,
                        startTime: gpAny.startTime,
                        numberOfGuests: gpAny.numberOfFriends || 1,
                        totalAmount: Number(gpAny.totalAmount || 0),
                        refundAmount: refundAmt,
                        refundStatus: gpAny.refundStatus || (gpAny.paymentStatus === 'refunded' ? 'COMPLETED' : 'PENDING_PAYOUT'),
                        paymentStatus: gpAny.paymentStatus,
                        refundMethod: gpAny.refundMethod || (refundAmt > 1500 ? 'BANK_UPI' : 'WALLET'),
                        payoutType: gpAny.payoutType || 'UPI_ID',
                        upiId: gpAny.upiId || null,
                        upiNumber: gpAny.upiNumber || null,
                        bankAccountNumber: gpAny.bankAccountNumber || null,
                        bankIfsc: gpAny.bankIfsc || null,
                        bankHolderName: gpAny.bankHolderName || null,
                        cancellationReason: gpAny.cancellationReason || null,
                        paymentReference: gpAny.refundTransactionReference || null,
                        adminNotes: gpAny.adminNotes || null,
                        cancelledAt: gpAny.cancelledAt || gpAny.updatedAt,
                        paidAt: gpAny.refundPaidAt || null,
                        user: gpAny.creator || null,
                        venue: gpAny.venue || null,
                    },
                });
            }

            // Try finding in Booking
            const booking = await Booking.findByPk(id, {
                include: [
                    {
                        model: User,
                        as: 'customer',
                        attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                    },
                    {
                        model: Venue,
                        as: 'venue',
                        attributes: ['id', 'name', 'city', 'addressLine1'],
                    },
                ],
            });

            if (!booking) {
                return res.status(404).json({ success: false, message: 'Cancellation record not found' });
            }

            const bkAny = booking as any;
            const refundAmt = Number(bkAny.refundAmount || 0);
            return res.json({
                success: true,
                data: {
                    id: bkAny.id,
                    bookingType: 'booking',
                    bookingId: bkAny.id,
                    partyDate: bkAny.bookingDate,
                    startTime: bkAny.startTime,
                    numberOfGuests: bkAny.numberOfGuests || 1,
                    totalAmount: Number(bkAny.totalAmount || 0),
                    refundAmount: refundAmt,
                    refundStatus: bkAny.refundStatus || (bkAny.paymentStatus === 'refunded' ? 'COMPLETED' : 'PENDING_PAYOUT'),
                    paymentStatus: bkAny.paymentStatus,
                    refundMethod: bkAny.refundMethod || (refundAmt > 1500 ? 'BANK_UPI' : 'WALLET'),
                    payoutType: bkAny.payoutType || 'UPI_ID',
                    upiId: bkAny.upiId || null,
                    upiNumber: bkAny.upiNumber || null,
                    bankAccountNumber: bkAny.bankAccountNumber || null,
                    bankIfsc: bkAny.bankIfsc || null,
                    bankHolderName: bkAny.bankHolderName || null,
                    cancellationReason: bkAny.cancellationReason || null,
                    paymentReference: bkAny.refundTransactionReference || null,
                    adminNotes: bkAny.adminNotes || null,
                    cancelledAt: bkAny.cancelledAt || bkAny.updatedAt,
                    paidAt: bkAny.refundPaidAt || null,
                    user: bkAny.customer || null,
                    venue: bkAny.venue || null,
                },
            });
        } catch (err: any) {
            logger.error('[AdminCancellationController] getGroupPartyCancellationDetail error:', err);
            return res.status(500).json({ success: false, message: err.message || 'Failed to fetch cancellation detail' });
        }
    }

    /**
     * POST /api/admin/bookings/group-party-cancellations/:id/mark-paid
     * Admin marks payout as paid with transaction reference (UTR)
     */
    public static async markGroupPartyRefundPaid(req: Request, res: Response): Promise<Response> {
        try {
            const { id } = req.params;
            const { paymentReference, notes } = req.body;

            if (!paymentReference || typeof paymentReference !== 'string' || paymentReference.trim().length === 0) {
                return res.status(400).json({ success: false, message: 'Payment reference / UTR transaction ID is required' });
            }

            const cleanRef = paymentReference.trim();
            const now = new Date();

            let targetUserId: string | null = null;
            let targetVenueName = 'Venue';
            let refundAmt = 0;
            let isGroupParty = true;

            // Look in GroupParty
            const party = await GroupParty.findByPk(id, {
                include: [{ model: Venue, as: 'venue' }],
            });

            if (party) {
                targetUserId = party.userId;
                targetVenueName = (party as any).venue?.name || 'Venue';
                refundAmt = Number((party as any).refundAmount || 0);

                await party.update({
                    paymentStatus: 'refunded' as any,
                    refundStatus: 'COMPLETED',
                    refundTransactionReference: cleanRef,
                    refundPaidAt: now,
                    adminNotes: notes?.trim() ? `${(party as any).adminNotes ? (party as any).adminNotes + ' | ' : ''}${notes.trim()}` : (party as any).adminNotes,
                } as any);
            } else {
                // Look in Booking
                const booking = await Booking.findByPk(id, {
                    include: [{ model: Venue, as: 'venue' }],
                });

                if (!booking) {
                    return res.status(404).json({ success: false, message: 'Cancellation record not found' });
                }

                isGroupParty = false;
                targetUserId = booking.userId;
                targetVenueName = (booking as any).venue?.name || 'Venue';
                refundAmt = Number((booking as any).refundAmount || 0);

                await booking.update({
                    paymentStatus: 'refunded' as any,
                    refundStatus: 'COMPLETED',
                    refundTransactionReference: cleanRef,
                    refundPaidAt: now,
                    adminNotes: notes?.trim() ? `${(booking as any).adminNotes ? (booking as any).adminNotes + ' | ' : ''}${notes.trim()}` : (booking as any).adminNotes,
                } as any);
            }

            // Dispatch user notification
            if (targetUserId) {
                const notifTitle = isGroupParty ? '🎉 Group Party Refund Transferred!' : '🎉 Booking Refund Transferred!';
                const notifBody = `Your refund of ₹${refundAmt.toLocaleString('en-IN')} for ${targetVenueName} has been transferred to your payout account.\nPayment Reference (UTR): ${cleanRef}.\nThe amount should reflect in your account within 2-4 hours.`;

                await NotificationService.dispatch({
                    recipientUserId: targetUserId,
                    eventType: 'refund_completed',
                    category: 'bookings',
                    entityType: isGroupParty ? 'GroupParty' : 'Booking',
                    entityId: id,
                    title: notifTitle,
                    body: notifBody,
                    priority: 'HIGH',
                    idempotencyKey: `refund_paid_${id}_${now.getTime()}`,
                    actionType: 'view_details',
                    deepLink: isGroupParty ? '/group-parties' : '/bookings',
                    metadata: {
                        bookingId: id,
                        refundAmount: refundAmt,
                        paymentReference: cleanRef,
                        status: 'COMPLETED',
                    },
                }).catch((e: any) => logger.warn('[AdminCancellationController] Notification dispatch failed:', e));

                // Emit realtime events to user
                RealtimeEventBroker.emitToUser(targetUserId, isGroupParty ? 'group_party_updated' : 'booking_updated', isGroupParty ? 'group_party' : 'payment', id, {
                    id,
                    status: 'cancelled',
                    paymentStatus: 'refunded',
                    refundStatus: 'COMPLETED',
                    refundAmount: refundAmt,
                    paymentReference: cleanRef,
                });

                // Socket emits
                try {
                    const { io } = require('../server');
                    if (io) {
                        io.to(`user_${targetUserId}`).emit('notification_created', {
                            id: `refund_paid_${id}`,
                            title: notifTitle,
                            body: notifBody,
                            createdAt: now.toISOString(),
                            read: false,
                            data: {
                                type: 'refund_completed',
                                bookingId: id,
                                paymentReference: cleanRef,
                                refundAmount: refundAmt,
                            },
                        });

                        io.to(`user_${targetUserId}`).emit(isGroupParty ? 'group_party_status_update' : 'venue_booking_status_update', {
                            bookingId: id,
                            status: 'cancelled',
                            cancellationStatus: 'COMPLETED',
                            refundAmount: refundAmt,
                            paymentReference: cleanRef,
                        });

                        // Broadcast to live feed room
                        io.to('live_feed').emit('live_feed_update', {
                            type: 'group_party_activity',
                            bookingId: id,
                            venueName: targetVenueName,
                            status: 'refund_completed',
                            timestamp: now.toISOString(),
                        });
                    }
                } catch (socketErr) {
                    logger.warn('[AdminCancellationController] Socket emit error:', socketErr);
                }

                // Enrich live feed card
                try {
                    if (isGroupParty) {
                        const enriched = await GroupPartyService.enrichGroupPartyNotificationCard(id, targetUserId);
                        if (enriched) {
                            RealtimeEventBroker.emitToUser(targetUserId, 'notification_updated', 'notification', id, enriched);
                        }
                    } else {
                        const enriched = await VenueBookingService.enrichVenueBookingNotificationCard(id, targetUserId);
                        if (enriched) {
                            RealtimeEventBroker.emitToUser(targetUserId, 'notification_updated', 'notification', id, enriched);
                        }
                    }
                } catch (_) {}
            }

            return res.json({
                success: true,
                message: 'Refund marked as paid successfully. User has been notified.',
                data: {
                    id,
                    refundStatus: 'COMPLETED',
                    paymentStatus: 'refunded',
                    paymentReference: cleanRef,
                    paidAt: now,
                },
            });
        } catch (err: any) {
            logger.error('[AdminCancellationController] markGroupPartyRefundPaid error:', err);
            return res.status(500).json({ success: false, message: err.message || 'Failed to mark refund as paid' });
        }
    }
}

export default AdminCancellationController;
