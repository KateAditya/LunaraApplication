import { Request, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { Op } from 'sequelize';
import Razorpay from 'razorpay';
import Ad from '../models/Ad';
import Booking, { BookingStatus, PaymentStatus, BookingPaymentMode } from '../models/Booking';
import Venue from '../models/Venue';
import VenueImage from '../models/VenueImage';
import User from '../models/User';
import { logger } from '../config/logger';
import { EventSeatService } from '../services/EventSeatService';
import { generateTicketForBookingHelper } from '../services/ticketService';
import { NotificationService } from '../services/NotificationService';

const razorpay = new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
    key_secret: process.env.RAZORPAY_KEY_SECRET || 'secret123',
});

const MENU_IMAGE_TYPES = ['menu', 'food_menu', 'drinks_menu', 'beverage_menu', 'bar_menu', 'wine_menu'];

function getVenueCoverImageUrl(venue: Venue | null): string | null {
    if (!venue) return null;
    const vAny = venue as any;
    const rawDirect = vAny.coverImageUrl || vAny.profilePhotoUrl || vAny.bannerImageUrl;
    if (rawDirect) {
        return rawDirect.startsWith('http') ? rawDirect : `/${rawDirect.replace(/^\/+/, '')}`;
    }
    const images = vAny.images as Array<{ filePath?: string; url?: string; imageType?: string; type?: string; isPrimary?: boolean }> | undefined;
    if (Array.isArray(images) && images.length > 0) {
        const primaryNonMenu = images.find(img => img.isPrimary && !MENU_IMAGE_TYPES.includes((img.imageType || img.type || '').toLowerCase()));
        if (primaryNonMenu) {
            const p = primaryNonMenu.filePath || primaryNonMenu.url;
            if (p) return p.startsWith('http') ? p : `/${p.replace(/^\/+/, '')}`;
        }
        const anyNonMenu = images.find(img => !MENU_IMAGE_TYPES.includes((img.imageType || img.type || '').toLowerCase()));
        if (anyNonMenu) {
            const p = anyNonMenu.filePath || anyNonMenu.url;
            if (p) return p.startsWith('http') ? p : `/${p.replace(/^\/+/, '')}`;
        }
        const first = images[0];
        const p = first?.filePath || first?.url;
        if (p) return p.startsWith('http') ? p : `/${p.replace(/^\/+/, '')}`;
    }
    return null;
}

function buildEventTicket(booking: Booking, venue: Venue | null, ticketCode: string, user?: User | null, ad?: Ad | null) {
    const rawUser = user || (booking as any).user;
    const userObj = rawUser ? {
        id: rawUser.id,
        fullName: `${rawUser.firstName || ''} ${rawUser.lastName || ''}`.trim() || 'Guest',
        firstName: rawUser.firstName,
        lastName: rawUser.lastName,
        email: rawUser.email,
        phone: rawUser.phone,
        mobileNumber: rawUser.phone,
        profilePhotoUrl: rawUser.profileImageUrl || null,
        profileImageUrl: rawUser.profileImageUrl || null,
    } : null;

    const bAny = booking as any;
    const partyEvent = ad || bAny.partyEvent;
    const bannerImageUrl = partyEvent?.imagePath
        ? (partyEvent.imagePath.startsWith('http') ? partyEvent.imagePath : `/${partyEvent.imagePath.replace(/^\/+/, '')}`)
        : null;
    const eventTitle = partyEvent?.title || booking.partySubject || 'Upcoming Night Event';
    const venueCoverUrl = getVenueCoverImageUrl(venue);

    return {
        bookingId: booking.id,
        bookingNumber: booking.bookingNumber,
        ticketCode,
        ticketUrl: (booking as any).ticketUrl || null,
        venue: venue
            ? {
                id: (venue as any).id,
                name: (venue as any).name,
                addressLine1: (venue as any).addressLine1,
                area: (venue as any).area,
                city: (venue as any).city,
                address: `${(venue as any).area || (venue as any).addressLine1 || ''}, ${(venue as any).city || ''}`.trim(),
                images: (venue as any).images ?? [],
                profilePhotoUrl: venueCoverUrl,
                coverImageUrl: venueCoverUrl,
                latitude: (venue as any).latitude ?? null,
                longitude: (venue as any).longitude ?? null,
            }
            : null,
        bookingDate: booking.bookingDate,
        startTime: booking.startTime,
        tablePackage: booking.tablePackage,
        numberOfGuests: booking.numberOfGuests,
        totalAmount: Number(booking.totalAmount || 0),
        status: booking.status,
        paymentStatus: booking.paymentStatus,
        paymentMode: booking.paymentMode,
        addedToWallet: booking.addedToWallet ?? false,
        user: userObj,
        host: userObj,
        isUpcomingNight: true,
        isEventBooking: true,
        bannerImageUrl,
        eventPoster: bannerImageUrl,
        imageUrl: bannerImageUrl || venueCoverUrl,
        eventTitle,
        partySubject: eventTitle || booking.partySubject,
        partyEvent: partyEvent ? {
            id: partyEvent.id,
            title: partyEvent.title,
            imagePath: bannerImageUrl,
            bannerImageUrl,
            aboutEvent: partyEvent.aboutEvent,
            eventDate: partyEvent.eventDate,
            entryPrice: partyEvent.entryPrice,
        } : null,
    };
}

/**
 * POST /api/mobile/bookings/party-event
 * Creates a Party Event booking order (Free or Paid).
 * Allows purchasing multiple tickets (quantity >= 1) and multiple batches of tickets.
 */
export const createPartyBooking = async (req: Request, res: Response): Promise<void> => {
    try {
        const { partyEventId, quantity, eventDate, time } = req.body;
        const userId = (req as any).user?.id || req.body?.userId;

        if (!userId) {
            res.status(401).json({ success: false, message: 'Authentication required' });
            return;
        }

        const ad = await Ad.findByPk(partyEventId);
        if (!ad || ad.type !== 'Party' || !ad.isActive) {
            res.status(404).json({ success: false, message: 'Active Party Event not found' });
            return;
        }

        const qty = Number(quantity);
        if (!Number.isFinite(qty) || qty < 1) {
            res.status(400).json({ success: false, message: 'Invalid ticket quantity.' });
            return;
        }

        // Clean up any stale unpaid pending attempts for this user and event so a fresh order proceeds cleanly
        await Booking.update(
            { status: BookingStatus.CANCELLED },
            {
                where: {
                    userId,
                    partyEventId: ad.id,
                    status: BookingStatus.PENDING,
                    paymentStatus: { [Op.ne]: PaymentStatus.PAID },
                },
            }
        );

        // Check seat availability under advisory check
        const advisoryRemaining = await EventSeatService.remaining(ad.id);
        if (advisoryRemaining !== null && advisoryRemaining < qty) {
            res.status(400).json({
                success: false,
                code: 'SEATS_UNAVAILABLE',
                message: advisoryRemaining <= 0
                    ? 'This event is sold out.'
                    : `Only ${advisoryRemaining} seat${advisoryRemaining === 1 ? '' : 's'} remaining.`,
                remainingSeats: advisoryRemaining,
            });
            return;
        }

        // Resolve eventDate string properly (YYYY-MM-DD)
        let eventDateStr = '';
        const rawDate = eventDate || req.body?.bookingDate || req.body?.date || ad.eventDate;
        
        if (rawDate) {
            if (rawDate instanceof Date) {
                const yyyy = rawDate.getFullYear();
                const mm = String(rawDate.getMonth() + 1).padStart(2, '0');
                const dd = String(rawDate.getDate()).padStart(2, '0');
                eventDateStr = `${yyyy}-${mm}-${dd}`;
            } else if (typeof rawDate === 'string') {
                const str = rawDate.trim();
                const match = str.match(/^(\d{4}-\d{2}-\d{2})/);
                if (match) {
                    eventDateStr = match[1];
                } else {
                    const parsed = new Date(str);
                    if (!isNaN(parsed.getTime())) {
                        const yyyy = parsed.getFullYear();
                        const mm = String(parsed.getMonth() + 1).padStart(2, '0');
                        const dd = String(parsed.getDate()).padStart(2, '0');
                        eventDateStr = `${yyyy}-${mm}-${dd}`;
                    }
                }
            }
        }

        if (!eventDateStr) {
            const fallbackDate = ad.toDate || ad.fromDate;
            if (fallbackDate instanceof Date) {
                const yyyy = fallbackDate.getFullYear();
                const mm = String(fallbackDate.getMonth() + 1).padStart(2, '0');
                const dd = String(fallbackDate.getDate()).padStart(2, '0');
                eventDateStr = `${yyyy}-${mm}-${dd}`;
            } else if (fallbackDate) {
                eventDateStr = String(fallbackDate).split('T')[0];
            } else {
                eventDateStr = new Date().toISOString().split('T')[0];
            }
        }

        const rawTime = time || req.body?.startTime || (ad as any).time || (ad as any).startTime || '20:00';
        const eventTimeStr = String(rawTime).trim() || '20:00';

        const amount = (ad.entryPrice || 0) * qty;
        const bookingNumber = `BKG-${Math.random().toString(36).substr(2, 6).toUpperCase()}`;

        let booking = await Booking.create({
            bookingNumber,
            userId,
            venueId: ad.venueId || '',
            bookingDate: eventDateStr as any,
            startTime: eventTimeStr,
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

        const venueDetails = ad.venueId
            ? await Venue.findByPk(ad.venueId, {
                attributes: ['id', 'name', 'addressLine1', 'area', 'city', 'latitude', 'longitude'],
                include: [
                    {
                        model: VenueImage,
                        as: 'images',
                        attributes: ['id', 'filePath', 'imageType', 'isPrimary', 'displayOrder'],
                        required: false,
                    },
                ],
            })
            : null;

        if (amount === 0) {
            // Free event flow — take seat under atomic row lock
            try {
                await EventSeatService.reserve(ad.id, qty);
            } catch (seatErr: any) {
                await booking.destroy();
                res.status(409).json({
                    success: false,
                    code: seatErr?.code === 'EVENT_SOLD_OUT' ? 'EVENT_SOLD_OUT' : 'SEAT_RESERVATION_FAILED',
                    message: seatErr?.code === 'EVENT_SOLD_OUT'
                        ? 'This event just sold out.'
                        : 'Could not reserve a seat for this event.',
                    remainingSeats: seatErr?.remainingSeats ?? 0,
                });
                return;
            }

            const ticketCode = uuidv4();
            booking.ticketCode = ticketCode;
            await booking.save();

            setImmediate(async () => {
                try {
                    await generateTicketForBookingHelper(booking.id);
                    const guestCount = booking.numberOfGuests || 1;
                    const ticketWord = guestCount === 1 ? 'pass' : 'passes';
                    const titleLabel = ad.title || 'Party Event';
                    const vName = venueDetails?.name || 'the venue';
                    await NotificationService.dispatch({
                        recipientUserId: booking.userId,
                        eventType: 'booking_confirmed',
                        category: 'bookings',
                        entityType: 'Booking',
                        entityId: booking.id,
                        title: `🎉 Free Event Pass Confirmed: ${titleLabel}!`,
                        body: `Your free entry ${ticketWord} (${guestCount}) for ${titleLabel} at ${vName} is confirmed! Digital pass ready in Ticket Pocket.`,
                        priority: 'HIGH',
                        idempotencyKey: `booking_free_${booking.id}`,
                        actionType: 'view_ticket',
                        deepLink: `/ticket/${booking.id}`,
                        metadata: {
                            bookingId: booking.id,
                            partyEventId: ad.id,
                            eventTitle: ad.title,
                            venueName: vName,
                            numberOfGuests: guestCount,
                            isFree: true,
                        },
                    });
                } catch (ticketErr) {
                    logger.error(`Background ticket processing failed for free booking ${booking.id}:`, ticketErr);
                }
            });

            res.status(201).json({
                success: true,
                data: booking,
                ticket: buildEventTicket(booking, venueDetails, ticketCode, null, ad),
                message: 'Free registration successful',
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
        logger.error('createPartyBooking error in mobilePartyEventBookingController:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to create party booking' });
    }
};

export default {
    createPartyBooking,
};
