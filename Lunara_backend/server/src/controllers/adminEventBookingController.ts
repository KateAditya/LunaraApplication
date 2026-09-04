import { Request, Response } from 'express';
import { Op } from 'sequelize';
import Booking, { BookingStatus, PaymentStatus } from '../models/Booking';
import Ad from '../models/Ad';
import User from '../models/User';
import Ticket from '../models/Ticket';
import Venue from '../models/Venue';

/**
 * Fetch all Party Events for the dropdown and selection
 */
export const getPartyEvents = async (_req: Request, res: Response): Promise<void> => {
    try {
        const events = await Ad.findAll({
            where: { type: 'Party' },
            order: [['eventDate', 'DESC'], ['createdAt', 'DESC']],
            attributes: ['id', 'title', 'eventDate', 'entryPrice', 'seatLimit', 'isUnlimited', 'city', 'area', 'venueId'],
            include: [
                {
                    model: Venue,
                    as: 'venue',
                    attributes: ['id', 'name', 'addressLine1', 'city'],
                    required: false,
                }
            ]
        });
        res.json({ success: true, events });
    } catch (error) {
        console.error('Error fetching party events:', error);
        res.status(500).json({ success: false, message: 'Internal server error' });
    }
};

/**
 * Fetch summary statistics for a specific Party Event OR overall aggregate across all events
 */
export const getEventSummary = async (req: Request, res: Response): Promise<void> => {
    try {
        const { eventId } = req.params;
        const isAll = !eventId || eventId === 'all';

        let event: any = null;
        let whereClause: any = {};

        if (!isAll) {
            event = await Ad.findOne({
                where: { id: eventId, type: 'Party' },
                include: [{ model: Venue, as: 'venue', attributes: ['name', 'city', 'addressLine1'] }]
            });
            if (!event) {
                res.status(404).json({ success: false, message: 'Party event not found' });
                return;
            }
            whereClause.partyEventId = eventId;
        } else {
            whereClause.partyEventId = { [Op.ne]: null };
        }

        // Fetch ALL bookings for this event (or all events) to compute full financial & cancellation breakdown
        const allBookings = await Booking.findAll({
            where: whereClause,
            order: [['createdAt', 'DESC']],
        });

        const totalEventsCount = isAll ? await Ad.count({ where: { type: 'Party' } }) : 1;

        let totalBookings = allBookings.length;
        let confirmedBookings = 0;
        let completedBookings = 0;
        let cancelledBookings = 0;
        let pendingBookings = 0;
        let paidBookings = 0;
        let freeBookings = 0;
        let refundedBookings = 0;

        let totalAttendees = 0;
        let grossRevenue = 0;
        let refundedAmount = 0;

        for (const b of allBookings) {
            const amt = Number(b.totalAmount || 0);
            const status = (b.status || '').toLowerCase();
            const payStatus = (b.paymentStatus || '').toLowerCase();

            if (status === BookingStatus.CANCELLED) {
                cancelledBookings++;
                if (payStatus === PaymentStatus.REFUNDED || payStatus === PaymentStatus.PAID) {
                    refundedBookings++;
                    refundedAmount += amt;
                }
            } else if (status === BookingStatus.CONFIRMED || status === BookingStatus.COMPLETED) {
                if (status === BookingStatus.CONFIRMED) confirmedBookings++;
                if (status === BookingStatus.COMPLETED) completedBookings++;

                totalAttendees += Number(b.numberOfGuests || 1);

                if (payStatus === PaymentStatus.PAID) {
                    if (amt > 0) {
                        paidBookings++;
                        grossRevenue += amt;
                    } else {
                        freeBookings++;
                    }
                } else if (amt === 0) {
                    freeBookings++;
                }
            } else if (status === BookingStatus.PENDING) {
                pendingBookings++;
            }
        }

        const netRevenue = Math.max(0, grossRevenue - refundedAmount);
        const cancellationRate = totalBookings > 0 ? Number(((cancelledBookings / totalBookings) * 100).toFixed(1)) : 0;
        const avgBookingValue = (confirmedBookings + completedBookings) > 0 
            ? Math.round(grossRevenue / (confirmedBookings + completedBookings)) 
            : 0;

        let filledSeats = totalAttendees;
        let seatLimitDisplay = 'Unlimited';
        let remainingSeats: any = 'Unlimited';
        let occupancyRate = 0;

        if (event) {
            if (event.isUnlimited) {
                seatLimitDisplay = 'No Limit';
                remainingSeats = 'Unlimited';
            } else {
                const limit = Number(event.seatLimit || 0);
                seatLimitDisplay = String(limit);
                remainingSeats = Math.max(0, limit - filledSeats);
                occupancyRate = limit > 0 ? Number(Math.min(100, (filledSeats / limit) * 100).toFixed(1)) : 0;
            }
        }

        res.json({
            success: true,
            summary: {
                totalEvents: totalEventsCount,
                totalBookings,
                confirmedBookings,
                completedBookings,
                cancelledBookings,
                pendingBookings,
                paidBookings,
                freeBookings,
                refundedBookings,
                totalAttendees,
                filledSeats,
                remainingSeats,
                seatLimit: seatLimitDisplay,
                occupancyRate,
                grossRevenue,
                refundedAmount,
                netRevenue,
                cancellationRate,
                avgBookingValue,
                isAllEvents: isAll,
            }
        });
    } catch (error) {
        console.error('Error fetching event summary:', error);
        res.status(500).json({ success: false, message: 'Internal server error' });
    }
};

/**
 * Fetch paginated bookings for a specific Party Event OR all party events
 */
export const getEventBookings = async (req: Request, res: Response): Promise<void> => {
    try {
        const { eventId } = req.params;
        const isAll = !eventId || eventId === 'all';

        const page = parseInt(req.query.page as string) || 1;
        const limit = parseInt(req.query.limit as string) || 20;
        const offset = (page - 1) * limit;

        const search = ((req.query.search as string) || '').trim();
        const bookingStatus = (req.query.bookingStatus as string) || '';
        const paymentStatus = (req.query.paymentStatus as string) || '';
        const fromDate = req.query.fromDate as string;
        const toDate = req.query.toDate as string;

        // Base where clause for Booking
        let whereClause: any = {};
        if (!isAll) {
            whereClause.partyEventId = eventId;
        } else {
            whereClause.partyEventId = { [Op.ne]: null };
        }

        if (bookingStatus && bookingStatus !== 'all') {
            whereClause.status = bookingStatus;
        }

        if (paymentStatus && paymentStatus !== 'all') {
            if (paymentStatus === 'free') {
                whereClause.totalAmount = 0;
            } else {
                whereClause.paymentStatus = paymentStatus;
            }
        }
        
        if (fromDate || toDate) {
            whereClause.createdAt = {};
            if (fromDate) whereClause.createdAt[Op.gte] = new Date(fromDate);
            if (toDate) whereClause.createdAt[Op.lte] = new Date(toDate);
        }

        // Handle search
        let userWhereClause: any = undefined;
        if (search) {
            const searchLower = `%${search.toLowerCase()}%`;
            userWhereClause = {
                [Op.or]: [
                    { firstName: { [Op.iLike]: searchLower } },
                    { lastName: { [Op.iLike]: searchLower } },
                    { email: { [Op.iLike]: searchLower } },
                    { phone: { [Op.iLike]: searchLower } },
                ]
            };
        }

        const includeConfig: any[] = [
            {
                model: User,
                as: 'user',
                attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                where: userWhereClause,
                required: !!userWhereClause,
            },
            {
                model: Ad,
                as: 'partyEvent',
                attributes: ['id', 'title', 'eventDate', 'entryPrice', 'city', 'area'],
                required: false,
            }
        ];

        const { count, rows } = await Booking.findAndCountAll({
            where: whereClause,
            include: includeConfig,
            order: [['createdAt', 'DESC']],
            limit,
            offset,
            distinct: true,
        });

        const bookingIds = rows.map(b => b.id);
        let tickets: any[] = [];
        if (bookingIds.length > 0) {
            tickets = await Ticket.findAll({
                where: { bookingId: { [Op.in]: bookingIds } }
            });
        }
        const ticketMap = tickets.reduce((acc, t) => {
            acc[t.bookingId] = t;
            return acc;
        }, {} as Record<string, any>);

        const formattedRows = rows.map(row => {
            const rowJson = row.toJSON() as any;
            rowJson.ticket = ticketMap[row.id] || null;
            return rowJson;
        });

        res.json({
            success: true,
            bookings: formattedRows,
            totalCount: count,
            totalPages: Math.ceil(count / limit),
            currentPage: page
        });
    } catch (error: any) {
        console.error('Error fetching event bookings:', error);
        res.status(500).json({ success: false, message: error?.message || 'Internal server error' });
    }
};

