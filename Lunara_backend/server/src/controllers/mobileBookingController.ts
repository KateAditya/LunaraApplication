import { Request, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import Booking, { BookingStatus, PaymentStatus, GoingMode, BookingPaymentMode } from '../models/Booking';
import BookingTablePackage, { TablePackageName } from '../models/BookingTablePackage';
import BookingMember, { MemberPaymentStatus } from '../models/BookingMember';
import GroupBooking from '../models/GroupBooking';
import Payment, { PaymentMethod, PaymentStatus as TxnStatus } from '../models/Payment';
import Venue from '../models/Venue';
import { logger } from '../config/logger';

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
export const createBooking = async (req: Request, res: Response) => {
    try {
        const {
            userId,
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
        } = req.body;

        if (!userId || !venueId || !bookingDate || !startTime || !packageName) {
            return res.status(400).json({
                success: false,
                message: 'Required: userId, venueId, bookingDate, startTime, tablePackage',
            });
        }

        // Validate goingMode
        if (![GoingMode.SOLO, GoingMode.PARTY_REQUEST].includes(goingMode as GoingMode)) {
            return res.status(400).json({ success: false, message: 'Only "solo" or "party_request" goingMode is supported in this version' });
        }

        // Fetch package price (auto-seed if needed)
        let pkg = null;
        let isStandardOrGroup = packageName === 'Standard Booking' || packageName === 'Group Party Booking';

        const venue = await Venue.findByPk(venueId);
        if (!venue) return res.status(404).json({ success: false, message: 'Venue not found' });

        // Enforce boundary constraint
        if (numberOfGuests > venue.capacity) {
            return res.status(400).json({ success: false, message: `Maximum capacity for this venue is ${venue.capacity} guests.` });
        }

        if (packageName && packageName !== 'none' && !isStandardOrGroup) {
            pkg = await BookingTablePackage.findOne({ where: { venueId, name: packageName, isActive: true } });
            if (!pkg) {
                // Try seeding
                await BookingTablePackage.bulkCreate(DEFAULT_PACKAGES.map(p => ({ ...p, venueId })));
                pkg = await BookingTablePackage.findOne({ where: { venueId, name: packageName, isActive: true } });
            }
            if (!pkg) return res.status(400).json({ success: false, message: `Package "${packageName}" not found` });
        }

        let totalAmount = 0;
        let commissionAmount = 0;

        if (isStandardOrGroup) {
            const basePrice = Number(venue.tableBookingCharges || 0);
            const subtotal = basePrice * numberOfGuests;
            const discountPercent = Number(venue.discountPercentage || 0);
            const discountAmount = (subtotal * discountPercent) / 100;
            totalAmount = subtotal - discountAmount;
            commissionAmount = Math.round(totalAmount * 0.1 * 100) / 100;
        } else if ((goingMode === GoingMode.SOLO || packageName !== 'none') && pkg) {
            totalAmount = Number(pkg.price);
            commissionAmount = Math.round(totalAmount * 0.1 * 100) / 100;
        }

        const isLargeParty = goingMode === GoingMode.PARTY_REQUEST;

        const booking = await Booking.create({
            userId,
            venueId,
            bookingDate: new Date(bookingDate),
            startTime,
            numberOfGuests: numberOfGuests || (pkg ? pkg.maxGuests : 1),
            totalAmount,
            depositAmount: 0,
            commissionAmount,
            goingMode: goingMode,
            tablePackage: packageName,
            specialRequests,
            isLargePartyRequest: isLargeParty,
            adminApprovalStatus: isLargeParty ? 'pending' : null,
            partySubject: isLargeParty ? partySubject : null,
            partyRequirement: isLargeParty ? partyRequirement : null,
            partyDescription: isLargeParty ? partyDescription : null,
        } as any);

        // Fetch venue details for the response
        const venueDetails = await Venue.findByPk(venueId, { attributes: ['id', 'name', 'addressLine1', 'area', 'city'] });

        return res.status(201).json({
            success: true,
            message: 'Booking created. Choose your payment method to confirm.',
            data: {
                bookingId: booking.id,
                bookingNumber: booking.bookingNumber,
                venue: venueDetails,
                bookingDate,
                startTime,
                tablePackage: packageName,
                tableLabel: pkg?.label,
                tableDescription: pkg?.description,
                maxGuests: pkg?.maxGuests,
                numberOfGuests: booking.numberOfGuests,
                totalAmount,
                status: booking.status,
                paymentStatus: booking.paymentStatus,
                goingMode: booking.goingMode,
            },
        });
    } catch (err: any) {
        logger.error('createBooking:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

// ─── POST /:id/pay-now ────────────────────────────────────────────────────────
export const payNow = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const { userId } = req.body;

        const booking = await Booking.findByPk(id);
        if (!booking) return res.status(404).json({ success: false, message: 'Booking not found' });
        if (booking.status === BookingStatus.CONFIRMED) {
            return res.status(400).json({ success: false, message: 'Booking already confirmed' });
        }

        // Simulate successful payment
        await Payment.create({
            bookingId: id,
            userId: userId || booking.userId,
            amount: booking.totalAmount,
            paymentMethod: PaymentMethod.CARD,
            paymentGateway: 'DUMMY_PAY_NOW',
            status: TxnStatus.SUCCESSFUL,
            gatewayResponse: { mode: 'test', simulatedAt: new Date().toISOString() },
        } as any);

        const ticketCode = uuidv4();
        await (booking as any).update({
            paymentStatus: PaymentStatus.PAID,
            paymentMode: BookingPaymentMode.PAY_NOW,
            status: BookingStatus.CONFIRMED,
            ticketCode,
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
        const { userId, members } = req.body;
        // members: [{ name: string, userId?: string, shareAmount: number }]

        if (!Array.isArray(members) || members.length < 1) {
            return res.status(400).json({ success: false, message: 'Provide at least 1 member' });
        }

        const booking = await Booking.findByPk(id);
        if (!booking) return res.status(404).json({ success: false, message: 'Booking not found' });
        if (booking.status === BookingStatus.CONFIRMED) {
            return res.status(400).json({ success: false, message: 'Booking already confirmed' });
        }

        const groupBooking = await GroupBooking.create({
            bookingId: id,
            organizerId: userId || booking.userId,
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
        const { memberId, userId } = req.body;

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

        const ticketCode = (booking as any).ticketCode || uuidv4();
        await (booking as any).update({
            status: BookingStatus.CONFIRMED,
            ticketCode,
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
        const userId = (req.query.userId || req.body.userId) as string;
        if (!userId) return res.status(400).json({ success: false, message: 'userId is required' });

        const bookings = await Booking.findAll({
            where: { userId },
            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
            order: [['createdAt', 'DESC']],
        });

        return res.json({ success: true, data: bookings });
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

        return res.json({ success: true, data: booking });
    } catch (err: any) {
        logger.error('getBookingDetail:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
};

export default {
    getTablePackages,
    getTimeSlots,
    createBooking,
    payNow,
    setupSplitBill,
    payMySplit,
    secureReservation,
    getTicket,
    addToWallet,
    listMyBookings,
    getBookingDetail,
};
