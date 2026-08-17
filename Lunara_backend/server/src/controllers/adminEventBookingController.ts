import { Request, Response } from 'express';
import { Op } from 'sequelize';
import Booking, { BookingStatus, PaymentStatus } from '../models/Booking';
import Ad from '../models/Ad';
import User from '../models/User';
import Ticket from '../models/Ticket';

/**
 * Fetch all Party Events for the dropdown
 */
export const getPartyEvents = async (_req: Request, res: Response) => {
    try {
        const events = await Ad.findAll({
            where: { type: 'Party' },
            order: [['eventDate', 'DESC'], ['createdAt', 'DESC']],
            attributes: ['id', 'title', 'eventDate', 'entryPrice', 'seatLimit', 'isUnlimited', 'city', 'area', 'venueId'],
        });
        res.json({ success: true, events });
    } catch (error) {
        console.error('Error fetching party events:', error);
        res.status(500).json({ success: false, message: 'Internal server error' });
    }
};

/**
 * Fetch summary statistics for a specific Party Event
 */
export const getEventSummary = async (req: Request, res: Response): Promise<void> => {
    try {
        const { eventId } = req.params;

        const event = await Ad.findOne({ where: { id: eventId, type: 'Party' } });
        if (!event) {
            res.status(404).json({ success: false, message: 'Party event not found' });
            return;
        }

        const validBookings = await Booking.findAll({
            where: {
                partyEventId: eventId,
                status: {
                    [Op.notIn]: [BookingStatus.CANCELLED, BookingStatus.NO_SHOW]
                }
            }
        });

        let totalBookings = validBookings.length;
        let confirmedBookings = 0;
        let paidBookings = 0;
        let freeBookings = 0;
        let totalEntries = 0;
        let totalRevenue = 0;

        for (const b of validBookings) {
            if (b.status === BookingStatus.CONFIRMED) {
                confirmedBookings++;
                totalEntries += b.numberOfGuests;

                if (b.paymentStatus === PaymentStatus.PAID) {
                    if (b.totalAmount > 0) {
                        paidBookings++;
                        totalRevenue += Number(b.totalAmount);
                    } else {
                        freeBookings++;
                    }
                } else if (b.totalAmount == 0) {
                    // Free registration logic for older logic if paymentStatus isn't explicitly PAID
                    freeBookings++;
                }
            }
        }

        let filledSeats = totalEntries;
        let remainingSeats = event.isUnlimited ? 'Unlimited' : Math.max(0, (event.seatLimit || 0) - filledSeats);

        res.json({
            success: true,
            summary: {
                totalBookings,
                confirmedBookings,
                paidBookings,
                freeBookings,
                totalEntries,
                filledSeats,
                remainingSeats,
                totalRevenue,
                seatLimit: event.isUnlimited ? 'No Limit' : event.seatLimit,
            }
        });
    } catch (error) {
        console.error('Error fetching event summary:', error);
        res.status(500).json({ success: false, message: 'Internal server error' });
    }
};

/**
 * Fetch paginated bookings for a specific Party Event with search and filters
 */
export const getEventBookings = async (req: Request, res: Response): Promise<void> => {
    try {
        const { eventId } = req.params;
        const page = parseInt(req.query.page as string) || 1;
        const limit = parseInt(req.query.limit as string) || 20;
        const offset = (page - 1) * limit;

        const search = (req.query.search as string) || '';
        const bookingStatus = req.query.bookingStatus as string;
        const paymentStatus = req.query.paymentStatus as string;
        const fromDate = req.query.fromDate as string;
        const toDate = req.query.toDate as string;

        // Base where clause for Booking
        let whereClause: any = {
            partyEventId: eventId
        };

        if (bookingStatus) whereClause.status = bookingStatus;
        if (paymentStatus) {
            if (paymentStatus === 'free') {
                whereClause.totalAmount = 0;
            } else {
                whereClause.paymentStatus = paymentStatus;
            }
        }
        
        if (fromDate || toDate) {
            whereClause.bookingDate = {};
            if (fromDate) whereClause.bookingDate[Op.gte] = new Date(fromDate);
            if (toDate) whereClause.bookingDate[Op.lte] = new Date(toDate);
        }

        // Search in user or booking number
        let userWhereClause: any = {};
        if (search) {
            const searchLower = `%${search.toLowerCase()}%`;
            whereClause[Op.or] = [
                { bookingNumber: { [Op.iLike]: searchLower } }
            ];
            
            userWhereClause = {
                [Op.or]: [
                    { firstName: { [Op.iLike]: searchLower } },
                    { lastName: { [Op.iLike]: searchLower } },
                    { email: { [Op.iLike]: searchLower } },
                    { mobile: { [Op.iLike]: searchLower } }
                ]
            };
        }

        let includeConfig: any[] = [
            {
                model: User,
                as: 'user',
                attributes: ['id', 'firstName', 'lastName', 'email', 'mobile', 'profileImageUrl'],
                where: search ? userWhereClause : undefined,
                required: !!search && Object.keys(userWhereClause).length > 0
            }
        ];
        
        if (search) {
            delete whereClause[Op.or]; // Remove previous OR
            includeConfig[0].where = undefined;
            includeConfig[0].required = false;

            whereClause[Op.or] = [
                { bookingNumber: { [Op.iLike]: `%${search}%` } },
                { '$user.first_name$': { [Op.iLike]: `%${search}%` } },
                { '$user.last_name$': { [Op.iLike]: `%${search}%` } },
                { '$user.email$': { [Op.iLike]: `%${search}%` } },
                { '$user.mobile$': { [Op.iLike]: `%${search}%` } }
            ];
        }

        const { count, rows } = await Booking.findAndCountAll({
            where: whereClause,
            include: includeConfig,
            order: [['createdAt', 'DESC']],
            limit,
            offset,
            distinct: true
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
    } catch (error) {
        console.error('Error fetching event bookings:', error);
        res.status(500).json({ success: false, message: 'Internal server error' });
    }
};
