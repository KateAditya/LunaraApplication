import { Request, Response } from 'express';
import { Op } from 'sequelize';
import { v4 as uuidv4 } from 'uuid';
import Booking, { BookingStatus, PaymentStatus, BookingPaymentMode } from '../models/Booking';
import User from '../models/User';
import GroupParty, { GroupPartyStatus, GroupPartyPaymentStatus } from '../models/GroupParty';
import PartyPlan from '../models/PartyPlan';
import PartyPlanRequest from '../models/PartyPlanRequest';
import StrangersMeetRequest from '../models/StrangersMeetRequest';
import StrangersMeetJoiner from '../models/StrangersMeetJoiner';
import BookingTablePackage, { TablePackageName } from '../models/BookingTablePackage';
import BookingMember, { MemberPaymentStatus } from '../models/BookingMember';
import GroupBooking from '../models/GroupBooking';
import Payment, { PaymentMethod, PaymentStatus as TxnStatus } from '../models/Payment';
import Venue from '../models/Venue';
import VenueImage from '../models/VenueImage';
import Ad from '../models/Ad';
import { logger } from '../config/logger';
import Razorpay from 'razorpay';
import crypto from 'crypto';
import { generateTicketForBookingHelper, generateTicketForGroupPartyHelper } from '../services/ticketService';
import { VenueBookingService } from '../services/VenueBookingService';
import { NotificationService } from '../services/NotificationService';

const razorpay = new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
    key_secret: process.env.RAZORPAY_KEY_SECRET || 'secret123',
});

// ─── Default packages seeded per venue on first request ──────────────────────
const DEFAULT_PACKAGES = [
    { name: TablePackageName.SILVER, label: 'Silver', description: 'Up to 5 People • 1 Bottle', price: 500, maxGuests: 5, bottlesIncluded: 1 },
    { name: TablePackageName.GOLD, label: 'Gold', description: 'Up to 8 People • 2 Bottles', price: 900, maxGuests: 8, bottlesIncluded: 2 },
    { name: TablePackageName.PLATINUM, label: 'Platinum', description: 'VIP Table • Unlimited Mixers', price: 1500, maxGuests: 20, bottlesIncluded: 0 },
];

// ─── Helper: build ticket response ───────────────────────────────────────────
function buildTicket(booking: Booking, venue: Venue | null, ticketCode: string) {
    return {
        bookingId: booking.id,
        bookingNumber: booking.bookingNumber,
        ticketCode,
        ticketUrl: (booking as any).ticketUrl || null,
        venue: venue
            ? { id: (venue as any).id, name: (venue as any).name, address: (venue as any).address }
            : null,
        bookingDate: booking.bookingDate,
        startTime: booking.startTime,
        tablePackage: booking.tablePackage,
        numberOfGuests: booking.numberOfGuests,
        status: booking.status,
        paymentStatus: booking.paymentStatus,
        paymentMode: booking.paymentMode,
        addedToWallet: booking.addedToWallet ?? false,
    };
}

// ─── GET /venues/:venueId/packages ───────────────────────────────────────────
export const getTablePackages = async (req: Request, res: Response) => {
    try {
        const { venueId } = req.params;
        const venue = await Venue.findByPk(venueId);
        if (!venue) return res.status(404).json({ success: false, message: 'Venue not found' });

        let pkgs = await BookingTablePackage.findAll({
            where: { venueId, isActive: true },
            order: [['price', 'ASC']],
        });

        // Auto-seed default packages for this venue if none exist
        if (pkgs.length === 0) {
            pkgs = await BookingTablePackage.bulkCreate(
                DEFAULT_PACKAGES.map(p => ({ ...p, venueId }))
            );
        }

        return res.json({ success: true, data: pkgs });
    } catch (err: any) {
        logger.error('getTablePackages:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── GET /venues/:venueId/timeslots?date=YYYY-MM-DD ──────────────────────────
export const getTimeSlots = async (req: Request, res: Response) => {
    try {
        const { venueId } = req.params;
        const { date } = req.query;

        const venue = await Venue.findByPk(venueId);
        if (!venue) return res.status(404).json({ success: false, message: 'Venue not found' });

        // Dummy slots — replace with DB-driven availability in production
        const slots = [
            { time: '20:00', label: '8:00 PM', available: true },
            { time: '21:00', label: '9:00 PM', available: true },
            { time: '22:00', label: '10:00 PM', available: true },
            { time: '22:30', label: '10:30 PM', available: true },
            { time: '23:00', label: '11:00 PM', available: false }, // simulated full
            { time: '23:30', label: '11:30 PM', available: true },
        ];

        return res.json({ success: true, data: { venueId, date: date || new Date().toISOString().split('T')[0], slots } });
    } catch (err: any) {
        logger.error('getTimeSlots:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── POST / — Create Booking ─────────────────────────────────────────────────
export const createBooking = async (req: Request, res: Response): Promise<void> => {
    try {
        const {
            venueId,
            bookingDate,
            startTime,
            tablePackage: packageName,
            numberOfGuests,
            specialRequests,
            goingMode = 'solo',
            partySubject,
            partyRequirement,
            partyDescription,
            mobileNumber,
            optionalMobileNumber,
            isUpcomingNight,
        } = req.body;
        const userId = req.user!.id;

        if (!venueId || !bookingDate || !startTime || !packageName) {
            res.status(400).json({
                success: false,
                message: 'Required: venueId, bookingDate, startTime, tablePackage',
            });
            return;
        }

        const { booking, razorpayOrder } = await VenueBookingService.createVenueBooking({
            userId,
            venueId,
            bookingDate,
            startTime,
            tablePackage: packageName,
            numberOfGuests: Number(numberOfGuests),
            specialRequests,
            goingMode,
            partySubject,
            partyRequirement,
            partyDescription,
            mobileNumber,
            optionalMobileNumber,
            isUpcomingNight
        });

        const venueDetails = await Venue.findByPk(venueId, { attributes: ['id', 'name', 'addressLine1', 'area', 'city'] });

        res.status(201).json({
            success: true,
            data: booking,
            razorpayOrderId: razorpayOrder ? razorpayOrder.id : '',
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
            amount: razorpayOrder ? razorpayOrder.amount : 0,
            currency: razorpayOrder ? razorpayOrder.currency : 'INR',
            ticket: buildTicket(booking, venueDetails, booking.ticketCode || '')
        });
    } catch (err: any) {
        logger.error('createBooking error:', err);
        if (err.code && err.code.startsWith('PLAN_')) {
            res.status(409).json({
                success: false,
                code: err.code,
                message: err.message,
                lock: err.details
            });
            return;
        }
        res.status(400).json({ success: false, message: err.message || 'Failed to create booking' });
    }
};

// ─── POST /party-event — Create Party Event Booking ──────────────────────────
export const createPartyBooking = async (req: Request, res: Response): Promise<void> => {
    try {
        const { partyEventId, quantity } = req.body;
        const userId = req.user!.id;

        const ad = await Ad.findByPk(partyEventId);
        if (!ad || ad.type !== 'Party' || !ad.isActive) {
            res.status(404).json({ success: false, message: 'Active Party Event not found' });
            return;
        }

        // Check seat limit
        const qty = Number(quantity);
        if (!ad.isUnlimited) {
            const seatsRemaining = (ad.seatLimit || 0) - (ad.filledSeats || 0);
            if (seatsRemaining < qty) {
                res.status(400).json({ success: false, message: 'Not enough seats available.' });
                return;
            }
        }

        const amount = (ad.entryPrice || 0) * qty;

        const bookingNumber = `BKG-${Math.random().toString(36).substr(2, 6).toUpperCase()}`;

        let booking = await Booking.create({
            bookingNumber,
            userId,
            venueId: ad.venueId || '',
            bookingDate: ad.eventDate || new Date(),
            startTime: '20:00', // Default start time
            numberOfGuests: qty,
            totalAmount: amount,
            depositAmount: 0,
            commissionAmount: 0,
            status: amount === 0 ? BookingStatus.CONFIRMED : BookingStatus.PENDING,
            paymentStatus: amount === 0 ? PaymentStatus.PAID : PaymentStatus.PENDING,
            paymentMode: BookingPaymentMode.PAY_NOW,
            isGroupBooking: qty > 1,
            isUpcomingNight: true,
            partyEventId: ad.id,
        });

        const venueDetails = await Venue.findByPk(ad.venueId, { attributes: ['id', 'name', 'addressLine1', 'area', 'city'] });

        if (amount === 0) {
            // Free event flow
            const ticketCode = uuidv4();
            booking.ticketCode = ticketCode;
            await booking.save();
            
            // Increment seats
            ad.filledSeats = (ad.filledSeats || 0) + qty;
            await ad.save();

            setImmediate(async () => {
                try {
                    await generateTicketForBookingHelper(booking.id);
                    await NotificationService.dispatch({
                        recipientUserId: booking.userId,
                        eventType: 'booking_confirmed',
                        category: 'bookings',
                        entityType: 'Booking',
                        entityId: booking.id,
                        title: '🎉 Free Booking Confirmed!',
                        body: `Your booking for ${ad.title || 'Party Event'} is confirmed!`,
                        priority: 'HIGH',
                        idempotencyKey: `booking_free_${booking.id}`,
                        actionType: 'view_ticket',
                        deepLink: `/ticket/${booking.id}`,
                    });
                } catch (ticketErr) {
                    logger.error(`Background ticket processing failed for free booking ${booking.id}:`, ticketErr);
                }
            });

            res.status(201).json({
                success: true,
                data: booking,
                ticket: buildTicket(booking, venueDetails as any, ticketCode),
                message: 'Free registration successful'
            });
            return;
        }

        // Paid flow - Generate Razorpay Order
        let razorpayOrder = null;
        if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_SECRET) {
            razorpayOrder = await razorpay.orders.create({
                amount: Math.round(amount * 100), // in paise
                currency: 'INR',
                receipt: booking.id,
            });
            booking.razorpayOrderId = razorpayOrder.id;
            await booking.save();
        } else {
            razorpayOrder = { id: 'dummy_order_' + booking.id, amount: amount * 100, currency: 'INR' };
        }

        res.status(201).json({
            success: true,
            data: booking,
            razorpayOrderId: razorpayOrder.id,
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
            amount: razorpayOrder.amount,
            currency: razorpayOrder.currency,
        });

    } catch (err: any) {
        logger.error('createPartyBooking error:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to create party booking' });
    }
};

// ─── POST /:id/pay-now ────────────────────────────────────────────────────────
export const payNow = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const { paymentMethod, transactionId, razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;
        const userId = req.user!.id;

        const booking = await Booking.findByPk(id);
        if (!booking) return res.status(404).json({ success: false, message: 'Booking not found' });
        if (booking.userId !== userId) {
            return res.status(403).json({ success: false, message: 'You can only pay for your own booking' });
        }

        if (booking.status === BookingStatus.CONFIRMED && booking.paymentStatus === PaymentStatus.PAID) {
            const venue = await Venue.findByPk(booking.venueId, { attributes: ['id', 'name', 'addressLine1', 'area', 'city'] });
            return res.json({
                success: true,
                message: 'Booking is already confirmed',
                data: buildTicket(booking, venue as any, booking.ticketCode || uuidv4()),
            });
        }

        const isWallet = paymentMethod === 'WALLET' || razorpay_payment_id?.startsWith('wallet_');
        const finalMethod = isWallet ? PaymentMethod.WALLET : PaymentMethod.CARD;
        const finalGateway = isWallet ? 'WALLET' : (razorpay_payment_id ? 'RAZORPAY' : 'DUMMY_PAY_NOW');

        // Record Payment transaction
        await Payment.create({
            bookingId: id,
            userId: userId || booking.userId,
            amount: booking.totalAmount,
            paymentMethod: finalMethod,
            paymentGateway: finalGateway,
            status: TxnStatus.SUCCESSFUL,
            gatewayResponse: { 
                mode: isWallet ? 'wallet' : 'gateway',
                transactionId: transactionId || razorpay_payment_id,
                razorpayOrderId: razorpay_order_id || booking.razorpayOrderId,
                razorpaySignature: razorpay_signature || null,
                paidAt: new Date().toISOString()
            },
        } as any);

        const ticketCode = booking.ticketCode || uuidv4();
        await (booking as any).update({
            paymentStatus: PaymentStatus.PAID,
            paymentMode: BookingPaymentMode.PAY_NOW,
            status: BookingStatus.CONFIRMED,
            ticketCode,
        });

        if (booking.partyEventId) {
            try {
                const ad = await Ad.findByPk(booking.partyEventId);
                if (ad) {
                    ad.filledSeats = (ad.filledSeats || 0) + (booking.numberOfGuests || 1);
                    await ad.save();
                }
            } catch (err) {
                logger.error(`Failed to update filledSeats for ad ${booking.partyEventId}:`, err);
            }
        }

        // Generate digital ticket in background & dispatch notification
        setImmediate(async () => {
            try {
                await generateTicketForBookingHelper(booking.id);
                const venueInfo = await Venue.findByPk(booking.venueId, { attributes: ['name'] });
                const vName = venueInfo?.name || 'Venue';
                await NotificationService.dispatch({
                    recipientUserId: booking.userId,
                    eventType: 'booking_confirmed',
                    category: 'bookings',
                    entityType: 'Booking',
                    entityId: booking.id,
                    title: '🎉 Booking Confirmed!',
                    body: `Your booking payment for ${vName} is successful! Your ticket is now available in your Ticket Wallet.`,
                    priority: 'HIGH',
                    idempotencyKey: `booking_paynow_${booking.id}`,
                    actionType: 'view_ticket',
                    deepLink: `/ticket/${booking.id}`,
                });
            } catch (ticketErr) {
                logger.error(`Background ticket/notification processing failed for booking ${booking.id}:`, ticketErr);
            }
        });

        const venue = await Venue.findByPk(booking.venueId, { attributes: ['id', 'name', 'addressLine1', 'area', 'city'] });
        return res.json({
            success: true,
            message: 'Payment successful. Your booking is confirmed!',
            data: buildTicket(booking, venue as any, ticketCode),
        });
    } catch (err: any) {
        logger.error('payNow:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── POST /:id/split-bill ─────────────────────────────────────────────────────
export const setupSplitBill = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const { members } = req.body;
        const userId = req.user!.id;
        // members: [{ name: string, userId?: string, shareAmount: number }]

        if (!Array.isArray(members) || members.length < 1) {
            return res.status(400).json({ success: false, message: 'Provide at least 1 member' });
        }

        const booking = await Booking.findByPk(id);
        if (!booking) return res.status(404).json({ success: false, message: 'Booking not found' });
        if (booking.userId !== userId) {
            return res.status(403).json({ success: false, message: 'You can only set up split billing on your own booking' });
        }
        if (booking.status === BookingStatus.CONFIRMED) {
            return res.status(400).json({ success: false, message: 'Booking already confirmed' });
        }

        const groupBooking = await GroupBooking.create({
            bookingId: id,
            organizerId: userId,
            totalMembers: members.length,
            confirmedMembers: 0,
            paidMembers: 0,
            splitPaymentEnabled: true,
        });

        const memberRecords = await Promise.all(
            members.map((m: { name: string; userId?: string; shareAmount: number }, idx: number) =>
                BookingMember.create({
                    groupBookingId: groupBooking.id,
                    userId: m.userId || undefined,
                    displayName: m.name,
                    shareAmount: m.shareAmount,
                    paymentStatus: MemberPaymentStatus.PENDING,
                    isOrganizer: idx === 0,
                })
            )
        );

        await (booking as any).update({
            paymentMode: BookingPaymentMode.SPLIT_BILL,
            isGroupBooking: true,
        });

        return res.json({
            success: true,
            message: 'Split bill set up. Members can now pay their share.',
            data: {
                groupBookingId: groupBooking.id,
                invitationCode: groupBooking.invitationCode,
                bookingId: id,
                totalAmount: Number(booking.totalAmount),
                totalCollected: 0,
                totalMembers: members.length,
                paidMembers: 0,
                members: memberRecords.map(m => ({
                    id: m.id,
                    displayName: m.displayName,
                    shareAmount: Number(m.shareAmount),
                    paymentStatus: m.paymentStatus,
                    isOrganizer: m.isOrganizer,
                })),
            },
        });
    } catch (err: any) {
        logger.error('setupSplitBill:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── POST /:id/split-bill/pay ─────────────────────────────────────────────────
export const payMySplit = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const { memberId } = req.body;
        const userId = req.user!.id;

        if (!memberId) return res.status(400).json({ success: false, message: 'memberId is required' });

        const booking = await Booking.findByPk(id);
        if (!booking) return res.status(404).json({ success: false, message: 'Booking not found' });

        const member = await BookingMember.findByPk(memberId);
        if (!member) return res.status(404).json({ success: false, message: 'Member not found' });
        if (member.paymentStatus === MemberPaymentStatus.PAID) {
            return res.status(400).json({ success: false, message: 'This member has already paid' });
        }

        // Simulate split payment
        const ts = Date.now().toString(36).toUpperCase();
        const rnd = Math.random().toString(36).substring(2, 6).toUpperCase();
        const transactionId = `SPLIT${ts}${rnd}`;

        await Payment.create({
            bookingId: id,
            userId: userId || booking.userId,
            amount: member.shareAmount,
            paymentMethod: PaymentMethod.CARD,
            paymentGateway: 'DUMMY_SPLIT',
            status: TxnStatus.SUCCESSFUL,
            gatewayResponse: { mode: 'test', memberId, simulatedAt: new Date().toISOString() },
        } as any);

        await (member as any).update({
            paymentStatus: MemberPaymentStatus.PAID,
            paidAt: new Date(),
            transactionId,
        });

        // Update group booking paid count
        const groupBooking = await GroupBooking.findByPk(member.groupBookingId);
        if (groupBooking) {
            const newPaidCount = groupBooking.paidMembers + 1;
            await groupBooking.update({ paidMembers: newPaidCount });
            if (newPaidCount >= groupBooking.totalMembers) {
                await (booking as any).update({ paymentStatus: PaymentStatus.PAID });
            }
        }

        // Build updated split summary
        const allMembers = await BookingMember.findAll({ where: { groupBookingId: member.groupBookingId } });
        const totalCollected = allMembers
            .filter(m => m.paymentStatus === MemberPaymentStatus.PAID || m.id === member.id)
            .reduce((sum, m) => sum + Number(m.shareAmount), 0);

        return res.json({
            success: true,
            message: 'Payment successful!',
            data: {
                memberId: member.id,
                displayName: member.displayName,
                shareAmount: Number(member.shareAmount),
                paymentStatus: MemberPaymentStatus.PAID,
                transactionId,
                totalCollected,
                totalAmount: Number(booking.totalAmount),
                paidMembers: groupBooking ? groupBooking.paidMembers + 1 : 1,
                totalMembers: groupBooking ? groupBooking.totalMembers : 1,
                members: allMembers.map(m => ({
                    id: m.id,
                    displayName: m.displayName,
                    shareAmount: Number(m.shareAmount),
                    paymentStatus: m.id === member.id ? MemberPaymentStatus.PAID : m.paymentStatus,
                    isOrganizer: m.isOrganizer,
                })),
            },
        });
    } catch (err: any) {
        logger.error('payMySplit:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── POST /:id/secure-reservation ────────────────────────────────────────────
export const secureReservation = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;

        const booking = await Booking.findByPk(id);
        if (!booking) return res.status(404).json({ success: false, message: 'Booking not found' });
        if (booking.userId !== req.user!.id) {
            return res.status(403).json({ success: false, message: 'You can only secure your own booking' });
        }

        const ticketCode = (booking as any).ticketCode || uuidv4();
        await (booking as any).update({
            status: BookingStatus.CONFIRMED,
            ticketCode,
        });

        // Generate digital ticket in background
        setImmediate(async () => {
            try {
                await generateTicketForBookingHelper(booking.id);
            } catch (ticketErr) {
                logger.error(`Background ticket generation failed for booking ${booking.id}:`, ticketErr);
            }
        });

        const venue = await Venue.findByPk(booking.venueId, { attributes: ['id', 'name', 'addressLine1', 'area', 'city'] });
        return res.json({
            success: true,
            message: 'Reservation secured! Your digital ticket is ready.',
            data: buildTicket(booking, venue as any, ticketCode),
        });
    } catch (err: any) {
        logger.error('secureReservation:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── GET /:id/ticket ──────────────────────────────────────────────────────────
export const getTicket = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;

        const booking = await Booking.findByPk(id, {
            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }],
        });
        if (!booking) return res.status(404).json({ success: false, message: 'Booking not found' });
        if (booking.userId !== req.user!.id) {
            return res.status(403).json({ success: false, message: 'You can only view your own ticket' });
        }

        const ticketCode = (booking as any).ticketCode;
        if (!ticketCode) {
            return res.status(400).json({ success: false, message: 'Ticket not yet generated. Complete payment first.' });
        }

        return res.json({
            success: true,
            data: buildTicket(booking, (booking as any).venue, ticketCode),
        });
    } catch (err: any) {
        logger.error('getTicket:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── POST /:id/add-to-wallet ──────────────────────────────────────────────────
export const addToWallet = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;

        const booking = await Booking.findByPk(id);
        if (!booking) return res.status(404).json({ success: false, message: 'Booking not found' });
        if (booking.userId !== req.user!.id) {
            return res.status(403).json({ success: false, message: 'You can only add your own booking to wallet' });
        }

        await (booking as any).update({
            addedToWallet: true,
            status: BookingStatus.COMPLETED,
        });

        return res.json({
            success: true,
            message: 'Booking added to wallet. Your experience begins!',
            data: {
                bookingId: id,
                bookingNumber: booking.bookingNumber,
                addedToWallet: true,
                status: BookingStatus.COMPLETED,
            },
        });
    } catch (err: any) {
        logger.error('addToWallet:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── GET / — List user's bookings ─────────────────────────────────────────────
export const listMyBookings = async (req: Request, res: Response) => {
    try {
        const userId = req.user?.id || (req.query.userId as string);
        if (!userId) {
            return res.status(400).json({ success: false, message: 'User ID is required' });
        }

        const venueInclude = {
            model: Venue,
            as: 'venue',
            attributes: ['id', 'name', 'addressLine1', 'area', 'city'],
            include: [
                {
                    model: VenueImage,
                    as: 'images',
                    attributes: ['id', 'filePath', 'imageType', 'isPrimary'],
                    required: false,
                }
            ],
            required: false,
        };

        const [
            bookings,
            hostPlans,
            joinerRequests,
            groupParties,
            smHostRequests,
            smJoinerRequests
        ] = await Promise.all([
            Booking.findAll({
                where: { userId },
                include: [venueInclude],
                order: [['bookingDate', 'DESC'], ['startTime', 'DESC']],
            }).catch(err => {
                logger.error('listMyBookings Booking query error:', err);
                return [];
            }),
            PartyPlan.findAll({
                where: { userId },
                include: [venueInclude],
                order: [['planDateTime', 'DESC']],
            }).catch(err => {
                logger.error('listMyBookings PartyPlan host query error:', err);
                return [];
            }),
            PartyPlanRequest.findAll({
                where: {
                    requesterId: userId,
                    status: { [Op.ne]: 'payment_failed' },
                },
                include: [{ model: PartyPlan, as: 'plan', include: [venueInclude] }],
                order: [['createdAt', 'DESC']],
            }).catch(err => {
                logger.error('listMyBookings PartyPlanRequest joiner query error:', err);
                return [];
            }),
            GroupParty.findAll({
                where: { userId },
                include: [venueInclude],
                order: [['partyDate', 'DESC'], ['startTime', 'DESC']],
            }).catch(err => {
                logger.error('listMyBookings GroupParty query error:', err);
                return [];
            }),
            StrangersMeetRequest.findAll({
                where: {
                    userId,
                    status: { [Op.ne]: 'rejected' },
                },
                include: [venueInclude],
                order: [['createdAt', 'DESC']],
            }).catch(err => {
                logger.error('listMyBookings StrangersMeetRequest query error:', err);
                return [];
            }),
            StrangersMeetJoiner.findAll({
                where: {
                    userId,
                    status: { [Op.ne]: 'rejected' },
                },
                include: [{ model: StrangersMeetRequest, as: 'strangersMeetRequest', include: [venueInclude] }],
                order: [['createdAt', 'DESC']],
            }).catch(err => {
                logger.error('listMyBookings StrangersMeetJoiner query error:', err);
                return [];
            }),
        ]);

        const synthesized: any[] = [];

        for (const plan of hostPlans) {
            const venue = (plan as any).venue;
            const planDateTime = new Date(plan.planDateTime);
            const bookedDate = plan.createdAt ? new Date(plan.createdAt).toISOString() : planDateTime.toISOString();
            synthesized.push({
                id: `party_plan_host_${plan.id}`,
                bookingId: plan.id,
                bookingType: 'party_plan',
                status: plan.status === 'cancelled' ? 'cancelled' : 'confirmed',
                createdAt: bookedDate,
                bookedAt: bookedDate,
                bookingDate: planDateTime.toISOString(),
                startTime: planDateTime.toTimeString().substring(0, 5),
                totalAmount: Number(plan.depositAmount),
                tablePackage: 'PARTY PLAN (HOST)',
                numberOfGuests: 2,
                venue,
                isPartyPlan: true,
            });
        }

        for (const request of joinerRequests) {
            const plan = (request as any).plan;
            if (!plan) continue;
            const venue = (plan as any).venue;
            const planDateTime = new Date(plan.planDateTime);
            const bookedDate = request.createdAt ? new Date(request.createdAt).toISOString() : (plan.createdAt ? new Date(plan.createdAt).toISOString() : planDateTime.toISOString());
            synthesized.push({
                id: `party_plan_joiner_${request.id}`,
                bookingId: plan.id,
                bookingType: 'party_plan',
                status: request.status === 'cancelled' || request.status === 'rejected' ? 'cancelled' : 'confirmed',
                createdAt: bookedDate,
                bookedAt: bookedDate,
                bookingDate: planDateTime.toISOString(),
                startTime: planDateTime.toTimeString().substring(0, 5),
                totalAmount: Number(plan.depositAmount ?? 99),
                tablePackage: 'PARTY PLAN (JOINER)',
                numberOfGuests: 2,
                venue,
                isPartyPlan: true,
            });
        }

        for (const gp of groupParties) {
            const venue = (gp as any).venue;
            const partyDate = new Date(gp.partyDate);
            const bookedDate = gp.createdAt ? new Date(gp.createdAt).toISOString() : partyDate.toISOString();
            synthesized.push({
                id: `group_party_${gp.id}`,
                bookingId: gp.id,
                bookingType: 'group_party',
                status: gp.status === 'cancelled' ? 'cancelled' : 'confirmed',
                createdAt: bookedDate,
                bookedAt: bookedDate,
                bookingDate: partyDate.toISOString(),
                startTime: gp.startTime || '20:00',
                totalAmount: Number(gp.totalAmount || 0),
                tablePackage: 'GROUP PARTY',
                numberOfGuests: gp.numberOfFriends || 1,
                venue,
                isGroupParty: true,
                ticketCode: gp.ticketCode,
                ticketUrl: gp.ticketUrl,
            });
        }

        for (const sm of smHostRequests) {
            const venue = (sm as any).venue;
            const eventDt = sm.eventDateTime ? new Date(sm.eventDateTime) : new Date((sm as any).createdAt || Date.now());
            const bookedDate = (sm as any).createdAt ? new Date((sm as any).createdAt).toISOString() : eventDt.toISOString();
            synthesized.push({
                id: `strangers_meet_host_${sm.id}`,
                bookingId: sm.id,
                bookingType: 'strangers_meet',
                type: 'strangers_meet',
                isStrangersMeet: true,
                status: sm.status === 'cancelled' ? 'cancelled' : 'confirmed',
                createdAt: bookedDate,
                bookedAt: bookedDate,
                bookingDate: eventDt.toISOString(),
                eventDateTime: eventDt.toISOString(),
                startTime: eventDt.toTimeString().substring(0, 5),
                totalAmount: Number(sm.paymentAmount || 0),
                tablePackage: 'STRANGERS MEET (HOST)',
                numberOfGuests: sm.numberOfPersons || 2,
                venue,
                ticketCode: sm.ticketId,
                ticketUrl: sm.ticketUrl,
                rawRequest: sm.toJSON(),
            });
        }

        for (const joiner of smJoinerRequests) {
            const sm = (joiner as any).strangersMeetRequest;
            if (!sm) continue;
            const venue = sm.venue;
            const eventDt = sm.eventDateTime ? new Date(sm.eventDateTime) : new Date(sm.createdAt || Date.now());
            const bookedDate = (joiner as any).createdAt ? new Date((joiner as any).createdAt).toISOString() : (sm.createdAt ? new Date(sm.createdAt).toISOString() : eventDt.toISOString());
            synthesized.push({
                id: `strangers_meet_joiner_${joiner.id}`,
                bookingId: sm.id,
                bookingType: 'strangers_meet',
                type: 'strangers_meet',
                isStrangersMeet: true,
                status: (joiner.status as string) === 'cancelled' || (joiner.status as string) === 'rejected' ? 'cancelled' : 'confirmed',
                createdAt: bookedDate,
                bookedAt: bookedDate,
                bookingDate: eventDt.toISOString(),
                eventDateTime: eventDt.toISOString(),
                startTime: eventDt.toTimeString().substring(0, 5),
                totalAmount: Number(joiner.paymentAmount || sm.chargesPerHead || 0),
                tablePackage: 'STRANGERS MEET (JOINER)',
                numberOfGuests: 1,
                venue,
                ticketCode: sm.ticketId,
                ticketUrl: sm.ticketUrl,
                rawRequest: sm.toJSON(),
            });
        }

        const normalizedBookings = bookings.map(b => {
            const json: any = b.toJSON();
            json.bookedAt = json.createdAt ? new Date(json.createdAt).toISOString() : json.bookingDate;
            return json;
        });

        const seenKeys = new Set<string>();
        const combined: any[] = [];

        for (const item of [...normalizedBookings, ...synthesized]) {
            const key = `${item.bookingType || 'normal'}_${item.bookingId || item.id}`;
            if (!seenKeys.has(key)) {
                seenKeys.add(key);
                combined.push(item);
            }
        }

        combined.sort((a, b) => {
            const timeB = new Date(b.bookedAt || b.createdAt || b.bookingDate).getTime();
            const timeA = new Date(a.bookedAt || a.createdAt || a.bookingDate).getTime();
            return timeB - timeA;
        });

        return res.json({ success: true, data: combined });
    } catch (err: any) {
        logger.error('listMyBookings:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── GET /:id — Booking detail ────────────────────────────────────────────────
export const getBookingDetail = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;

        const booking = await Booking.findByPk(id, {
            include: [
                { model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] },
                {
                    model: GroupBooking,
                    as: 'groupBooking',
                    include: [{ model: BookingMember, as: 'members' }],
                },
            ],
        });
        if (!booking) return res.status(404).json({ success: false, message: 'Booking not found' });
        if (booking.userId !== req.user!.id) {
            return res.status(403).json({ success: false, message: 'You can only view your own booking' });
        }

        return res.json({ success: true, data: booking });
    } catch (err: any) {
        logger.error('getBookingDetail:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── POST /:id/initiate-large-party-payment ─────────────────────────────────
export const initiateLargePartyPayment = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        let booking = await Booking.findByPk(id);
        if (!booking) {
            const groupParty = await GroupParty.findByPk(id);
            if (!groupParty) {
                return res.status(404).json({ success: false, message: 'Booking or Group Party not found' });
            }
            if (groupParty.userId !== req.user!.id) {
                return res.status(403).json({ success: false, message: 'You can only pay for your own group party' });
            }
            const pStatus = (groupParty.status || '').toLowerCase();
            const pPayStatus = (groupParty.paymentStatus || '').toLowerCase();
            if (pStatus === 'cancelled' || pPayStatus === 'paid') {
                return res.status(400).json({ success: false, message: 'Group party is already confirmed/cancelled' });
            }
            const amount = Number(groupParty.totalAmount);
            if (isNaN(amount) || amount <= 0) {
                return res.status(400).json({ success: false, message: 'Invalid total amount set for group party' });
            }
            const options = {
                amount: Math.round(amount * 100),
                currency: 'INR',
                receipt: `gp_${groupParty.id.replace(/-/g, '').slice(0, 30)}`,
            };
            let order: any = { id: `order_mock_${Date.now()}`, amount: options.amount, currency: options.currency };
            if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id') {
                try {
                    order = await razorpay.orders.create(options);
                } catch (err: any) {
                    logger.warn('Razorpay create order failed for group party, using mock order. Error: ' + err.message);
                }
            }
            await groupParty.update({ paymentId: order.id });
            return res.json({
                success: true,
                razorpayOrderId: order.id,
                amount: order.amount,
                currency: order.currency,
                razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
            });
        }
        
        if (booking.userId !== req.user!.id) {
            return res.status(403).json({ success: false, message: 'You can only pay for your own booking' });
        }

        const goingMode = (booking.goingMode || '').toLowerCase();
        const isLargeParty = booking.isLargePartyRequest || goingMode === 'party_request' || goingMode === 'group_party' || (booking.numberOfGuests || 0) > 20;

        if (!isLargeParty) {
            return res.status(400).json({ success: false, message: 'Not a group or large party request booking' });
        }

        const adminStatus = (booking.adminApprovalStatus || '').toLowerCase();
        const bookingStatus = (booking.status || '').toLowerCase();

        const isApproved = adminStatus === 'approved' ||
            adminStatus === 'approved_awaiting_payment' ||
            adminStatus === 'awaiting_payment' ||
            adminStatus === 'payment_sent' ||
            bookingStatus === 'approved' ||
            bookingStatus === 'confirmed' ||
            bookingStatus === 'payment_sent' ||
            bookingStatus === 'pending';

        if (!isApproved) {
            return res.status(400).json({ success: false, message: 'Booking is not approved by admin or payment already completed' });
        }

        const amount = Number(booking.adminPaymentAmount || booking.totalAmount);
        if (isNaN(amount) || amount <= 0) {
            return res.status(400).json({ success: false, message: 'Invalid total amount set for booking' });
        }

        const options = {
            amount: Math.round(amount * 100), // in paise
            currency: 'INR',
            receipt: `blp_${booking.id.replace(/-/g, '').slice(0, 30)}`,
        };

        let order: any = { id: `order_mock_${Date.now()}`, amount: options.amount, currency: options.currency };
        if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id') {
            try {
                order = await razorpay.orders.create(options);
            } catch (err: any) {
                logger.warn('Razorpay create order failed, using mock order. Error: ' + err.message);
            }
        }

        await (booking as any).update({
            razorpayOrderId: order.id,
        });

        return res.json({
            success: true,
            razorpayOrderId: order.id,
            amount: order.amount,
            currency: order.currency,
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
        });
    } catch (err: any) {
        logger.error('initiateLargePartyPayment:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── POST /:id/verify-large-party-payment ───────────────────────────────────
export const verifyLargePartyPayment = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        // Wallet payments never create a real Razorpay order on the record, so the
        // Flutter wallet callback sends a synthetic order id (e.g. 'order_mock_wallet').
        // Skip the order-id equality check for these, same as Party Plan / Strangers Meet.
        const isMockOrWalletOrder = !razorpay_order_id ||
            razorpay_order_id.startsWith('order_mock_') ||
            razorpay_order_id.startsWith('wallet_');

        let booking = await Booking.findByPk(id);
        if (!booking) {
            const groupParty = await GroupParty.findByPk(id);
            if (!groupParty) {
                return res.status(404).json({ success: false, message: 'Booking/GroupParty not found' });
            }
            if (groupParty.userId !== req.user!.id) {
                return res.status(403).json({ success: false, message: 'You can only verify payment for your own group party' });
            }
            if (!isMockOrWalletOrder && groupParty.paymentId !== razorpay_order_id) {
                return res.status(400).json({ success: false, message: 'Invalid order ID' });
            }

            const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
            hmac.update(razorpay_order_id + '|' + razorpay_payment_id);
            const generatedSignature = hmac.digest('hex');

            if (generatedSignature === razorpay_signature || razorpay_signature === 'mock_signature') {
                await groupParty.update({
                    paymentStatus: GroupPartyPaymentStatus.PAID,
                    status: GroupPartyStatus.CONFIRMED
                });

                // Generate digital ticket in background
                setImmediate(async () => {
                    try {
                        await generateTicketForGroupPartyHelper(groupParty.id);
                    } catch (ticketErr) {
                        logger.error(`Background ticket generation failed for GroupParty ${groupParty.id}:`, ticketErr);
                    }
                });

                const venue = await Venue.findByPk(groupParty.venueId, { attributes: ['id', 'name', 'addressLine1', 'area', 'city'] });

                try {
                    const venueName = venue?.name || 'Venue';
                    // Reuse the same DB-record + push + notification_updated/live_feed_update
                    // pattern used by the free/instant-confirm path, instead of the ad-hoc
                    // FCM-only notification this branch previously sent.
                    const { GroupPartyService } = await import('../services/GroupPartyService');
                    await GroupPartyService.emitNotifications(groupParty.userId, venueName, 'small_paid', groupParty.id, groupParty.numberOfFriends);

                    const { io } = require('../server');
                    if (io) {
                        io.to(`user_${groupParty.userId}`).emit('group_party_payment_success', { partyId: groupParty.id });
                        io.to(`user_${groupParty.userId}`).emit('large_party_payment_success', { bookingId: groupParty.id });
                    }
                } catch (pushErr) {
                    logger.warn('Failed to send push/socket for group party verification: ' + pushErr);
                }

                return res.json({
                    success: true,
                    message: 'Payment verified successfully and booking is confirmed!',
                    data: {
                        bookingId: groupParty.id,
                        bookingNumber: groupParty.paymentId || `GP-${groupParty.id}`,
                        venueName: venue?.name,
                        address: venue?.addressLine1,
                        area: venue?.area,
                        city: venue?.city,
                        bookingDate: groupParty.partyDate,
                        startTime: '08:00 PM',
                        numberOfGuests: groupParty.numberOfFriends,
                        totalAmount: groupParty.totalAmount,
                        ticketCode: groupParty.paymentId || `TKT-${groupParty.id}`,
                        status: 'confirmed',
                        paymentStatus: 'paid',
                        goingMode: 'party_request'
                    }
                });
            } else {
                return res.status(400).json({ success: false, message: 'Invalid payment signature' });
            }
        }

        if (booking.userId !== req.user!.id) {
            return res.status(403).json({ success: false, message: 'You can only verify payment for your own booking' });
        }

        if (!isMockOrWalletOrder && booking.razorpayOrderId !== razorpay_order_id) {
            return res.status(400).json({ success: false, message: 'Invalid order ID' });
        }

        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(razorpay_order_id + '|' + razorpay_payment_id);
        const generatedSignature = hmac.digest('hex');

        if (generatedSignature === razorpay_signature || razorpay_signature === 'mock_signature') {
            const ticketCode = uuidv4();
            await (booking as any).update({
                paymentStatus: PaymentStatus.PAID,
                paymentMode: BookingPaymentMode.PAY_NOW,
                status: BookingStatus.CONFIRMED,
                adminApprovalStatus: 'payment_done',
                ticketCode,
            });

            // Generate digital ticket in background
            setImmediate(async () => {
                try {
                    await generateTicketForBookingHelper(booking.id);
                } catch (ticketErr) {
                    logger.error(`Background ticket generation failed for booking ${booking.id}:`, ticketErr);
                }
            });

            // Create Payment record
            await Payment.create({
                transactionId: razorpay_payment_id,
                bookingId: id,
                userId: booking.userId,
                amount: booking.totalAmount,
                currency: 'INR',
                paymentMethod: PaymentMethod.RAZORPAY,
                paymentGateway: 'razorpay',
                status: TxnStatus.SUCCESSFUL,
                refundAmount: 0,
            } as any);

            const venue = await Venue.findByPk(booking.venueId, { attributes: ['id', 'name', 'addressLine1', 'area', 'city'] });

            try {
                const venueName = venue?.name || 'Venue';
                const notifTitle = 'Party Confirmed! 🎉';
                const notifBody = `Your payment for the party at ${venueName} is verified. Booking confirmed!`;
                const notifType = 'large_party_payment_success';

                // Create DB Notification Record — same pattern as admin approval,
                // required for the Notification Center / Live Feed to show anything.
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
                        metadata: { bookingId: booking.id, venueName },
                    });
                } catch (dbErr) {
                    logger.warn('Failed to save DB notification for large party payment success: ' + dbErr);
                }

                const host = await User.findByPk(booking.userId, { attributes: ['id', 'fcmToken'] });
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
                if (io) {
                    io.to(`user_${booking.userId}`).emit('large_party_payment_success', { bookingId: booking.id });

                    try {
                        const { GroupPartyService } = await import('../services/GroupPartyService');
                        const enrichedCard = await GroupPartyService.enrichLargePartyNotificationCard(booking.id, booking.userId);
                        io.to(`user_${booking.userId}`).emit('notification_updated', enrichedCard);
                        io.to('live_feed').emit('live_feed_update', { type: 'large_party_activity', bookingId: booking.id, venueName, status: 'payment_done', timestamp: new Date().toISOString() });
                    } catch (cardErr) {}
                }
            } catch (socketErr) {
                logger.warn('Socket/Push emission failed for large_party_payment_success:', socketErr);
            }

            return res.json({
                success: true,
                message: 'Payment verified successfully and booking is confirmed!',
                data: buildTicket(booking, venue as any, ticketCode),
            });
        } else {
            return res.status(400).json({ success: false, message: 'Invalid payment signature' });
        }
    } catch (err: any) {
        logger.error('verifyLargePartyPayment:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

export default {
    getTablePackages,
    getTimeSlots,
    createBooking,
    createPartyBooking,
    payNow,
    setupSplitBill,
    payMySplit,
    secureReservation,
    getTicket,
    addToWallet,
    listMyBookings,
    getBookingDetail,
    initiateLargePartyPayment,
    verifyLargePartyPayment,
};
