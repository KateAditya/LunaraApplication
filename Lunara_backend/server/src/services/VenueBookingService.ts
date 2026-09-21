import { Op } from 'sequelize';
import Booking, { BookingStatus, PaymentStatus, GoingMode, AdminApprovalStatus } from '../models/Booking';
import Venue from '../models/Venue';
import BookingTablePackage, { TablePackageName } from '../models/BookingTablePackage';
import { PlanEligibilityService } from './PlanEligibilityService';
import { validateVenueTimingAndHolidays, normalizeStartTime } from '../utils/venueValidator';
import { TimeLockError } from '../utils/bookingLimitValidator';
import { EventTimeLockService, parseBookingDateTime } from './EventTimeLockService';
import { generateTicketForBookingHelper } from './ticketService';
import { NotificationService } from './NotificationService';
import { logger } from '../config/logger';
import Razorpay from 'razorpay';
import crypto from 'crypto';
import { parseEventDateTimeToUTC, formatTime12Hour, formatDateFull } from '../utils/dateTimeUtils';
import { BookingPolicyService } from './BookingPolicyService';
import { BookingPolicyType } from '../models/BookingPolicyConfig';

const razorpay = new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
    key_secret: process.env.RAZORPAY_KEY_SECRET || 'secret123',
});

const DEFAULT_PACKAGES = [
    { name: TablePackageName.SILVER, label: 'Silver', description: 'Up to 5 People • 1 Bottle', price: 500, maxGuests: 5, bottlesIncluded: 1 },
    { name: TablePackageName.GOLD, label: 'Gold', description: 'Up to 8 People • 2 Bottles', price: 900, maxGuests: 8, bottlesIncluded: 2 },
    { name: TablePackageName.PLATINUM, label: 'Platinum', description: 'VIP Table • Unlimited Mixers', price: 1500, maxGuests: 20, bottlesIncluded: 0 },
];

export interface CreateBookingPayload {
    userId: string;
    venueId: string;
    bookingDate: string;
    startTime: string;
    tablePackage: string;
    numberOfGuests: number;
    specialRequests?: string;
    goingMode?: string; // 'solo' | 'party_request'
    partySubject?: string;
    partyRequirement?: string;
    partyDescription?: string;
    mobileNumber?: string;
    optionalMobileNumber?: string;
    isUpcomingNight?: boolean;
    paymentMode?: string;
}

export class VenueBookingService {

    /**
     * Authoritatively calculates pricing snapshot on backend
     */
    public static async calculateAuthoritativePrice(
        venueId: string,
        packageName: string,
        numberOfGuests: number
    ): Promise<{ totalAmount: number; commissionAmount: number; pkg?: BookingTablePackage }> {
        const venue = await Venue.findByPk(venueId);
        if (!venue) throw new Error('Venue not found');

        let totalAmount = 0;
        let pkg: BookingTablePackage | null = null;

        const validEnumPackages = [
            TablePackageName.SILVER.toLowerCase(),
            TablePackageName.GOLD.toLowerCase(),
            TablePackageName.PLATINUM.toLowerCase(),
        ];
        const cleanPkgName = (packageName || '').toLowerCase().trim();
        const isPackageEnum = validEnumPackages.includes(cleanPkgName);

        if (!isPackageEnum) {
            const rawCharge = Number(venue.tableBookingCharges);
            const basePrice = (!isNaN(rawCharge) && rawCharge >= 0) ? rawCharge : 0;
            const subtotal = basePrice * numberOfGuests;
            const discountPercent = Number(venue.discountPercentage || 0);
            const discountAmount = (subtotal * discountPercent) / 100;
            totalAmount = Math.max(0, subtotal - discountAmount);
        } else {
            pkg = await BookingTablePackage.findOne({ where: { venueId, name: cleanPkgName as TablePackageName, isActive: true } });
            if (!pkg) {
                await BookingTablePackage.bulkCreate(DEFAULT_PACKAGES.map(p => ({ ...p, venueId })));
                pkg = await BookingTablePackage.findOne({ where: { venueId, name: cleanPkgName as TablePackageName, isActive: true } });
            }
            if (pkg) {
                totalAmount = Number(pkg.price);
            } else {
                const rawCharge = Number(venue.tableBookingCharges);
                const basePrice = (!isNaN(rawCharge) && rawCharge >= 0) ? rawCharge : 0;
                totalAmount = basePrice * numberOfGuests;
            }
        }

        const commissionAmount = Math.round(totalAmount * 0.1 * 100) / 100;
        return { totalAmount, commissionAmount, pkg: pkg || undefined };
    }

    /**
     * Creation entrypoint for Solo & Friends Venue Bookings
     */
    public static async createVenueBooking(payload: CreateBookingPayload): Promise<{
        booking: Booking;
        razorpayOrder?: any;
    }> {
        const {
            userId, venueId, bookingDate, startTime, tablePackage: packageName,
            numberOfGuests, specialRequests, goingMode = 'solo', partySubject,
            partyRequirement, partyDescription, mobileNumber, optionalMobileNumber, isUpcomingNight,
            paymentMode
        } = payload;

        if (![GoingMode.SOLO, GoingMode.PARTY_REQUEST].includes(goingMode as GoingMode)) {
            throw new Error('Unsupported goingMode. Only "solo" or "party_request" are supported.');
        }

        const venue = await Venue.findByPk(venueId);
        if (!venue) throw new Error('Venue not found');

        if (venue.capacity && venue.capacity > 0 && numberOfGuests > venue.capacity) {
            throw new Error(`Maximum capacity for this venue is ${venue.capacity} guests.`);
        }

        const timingValidation = validateVenueTimingAndHolidays(venue, bookingDate, startTime);
        if (!timingValidation.isValid) {
            throw new Error(timingValidation.reason || 'Venue is closed on selected date.');
        }

        const isLargeParty = goingMode === GoingMode.PARTY_REQUEST && numberOfGuests > 20;

        // ── Universal 4-Hour Time-Lock Validation ─────────────────────────────
        // Direct upcoming night / party event ticket purchases do not enforce a 4-hour time lock
        if (!isUpcomingNight) {
            const bookingDateTime = parseBookingDateTime(bookingDate, startTime);
            const timeLockCheck = await EventTimeLockService.validateFourHourGap(
                userId,
                bookingDateTime,
                isLargeParty ? 'large_party' : 'solo_booking'
            );
            if (!timeLockCheck.allowed) {
                throw new TimeLockError(timeLockCheck);
            }
        }

        const cleanBookingDate = typeof bookingDate === 'string' && bookingDate.includes('T')
            ? bookingDate.split('T')[0]
            : String(bookingDate).substring(0, 10);

        // Clear the user's own abandoned/unpaid solo or small-party booking
        // attempts for this exact date before proceeding. A PENDING Booking
        // row (with a Razorpay order) is created below BEFORE payment
        // completes — same pattern as GroupParty — so a dismissed payment
        // sheet or a failed charge would otherwise leave a stale row (and
        // its PlanTimeLock) that blocks every subsequent retry for the rest
        // of the cooldown window. Deliberately excludes large-party rows,
        // whose PENDING status means "awaiting admin approval," a genuine
        // wait state that must not be auto-cancelled.
        if (!isLargeParty) {
            const staleSameDayBookings = await Booking.findAll({
                where: {
                    userId,
                    venueId,
                    bookingDate: cleanBookingDate,
                    status: BookingStatus.PENDING,
                    paymentStatus: { [Op.ne]: PaymentStatus.PAID },
                    isLargePartyRequest: false,
                },
            });
            for (const stale of staleSameDayBookings) {
                await stale.update({ status: BookingStatus.CANCELLED });
                await PlanEligibilityService.releaseLock(stale.id);
            }
        }

        const pricing = await this.calculateAuthoritativePrice(venueId, packageName, numberOfGuests);

        const initialApprovalStatus: AdminApprovalStatus | undefined = isLargeParty
            ? AdminApprovalStatus.PENDING
            : undefined;

        const normalizedStart = normalizeStartTime(startTime);
        const bookingStartDateTime = parseEventDateTimeToUTC(cleanBookingDate, normalizedStart);
        if (isNaN(bookingStartDateTime.getTime())) {
            throw new Error('Invalid bookingDate or startTime format');
        }

        const planType = isUpcomingNight ? 'upcoming_night' : (isLargeParty ? 'large_group_party' : 'venue_booking');

        // Authoritative Booking Lead Time Validation for Solo Bookings
        // Only paid solo bookings enforce pre-booking lead time cutoff; complimentary (free) walk-in reservations allow immediate entry as long as the slot time is not in the past
        if (goingMode === GoingMode.SOLO) {
            if (pricing.totalAmount > 0) {
                const leadTimeValidation = await BookingPolicyService.validateBookingTime(
                    BookingPolicyType.SOLO_BOOKING,
                    bookingStartDateTime
                );
                if (!leadTimeValidation.allowed) {
                    throw new Error(leadTimeValidation.reason || 'Booking lead time window has closed.');
                }
            } else {
                // Complimentary booking: ensure slot is not in the past (allow ongoing slot up to 30 mins)
                if (bookingStartDateTime.getTime() < Date.now() - 30 * 60 * 1000) {
                    throw new Error('Selected booking slot has already passed.');
                }
            }
        }

        const isWalletPayment = (paymentMode || '').toLowerCase() === 'wallet';
        let razorpayOrder: any = null;
        // Solo mode or small party (<= 20) with price > 0 generates Razorpay order immediately (skipped for wallet)
        if ((goingMode === GoingMode.SOLO || !isLargeParty) && pricing.totalAmount > 0 && !isWalletPayment) {
            try {
                razorpayOrder = await razorpay.orders.create({
                    amount: Math.round(pricing.totalAmount * 100),
                    currency: 'INR',
                    receipt: `bk_${Date.now()}`
                });
            } catch (rzpErr: any) {
                logger.warn(`[VenueBookingService] Razorpay order creation failed, fallback to mock order ID: ${rzpErr.message}`);
                razorpayOrder = {
                    id: `order_${Date.now()}_${Math.floor(1000 + Math.random() * 9000)}`,
                    amount: Math.round(pricing.totalAmount * 100),
                    currency: 'INR',
                    receipt: `bk_${Date.now()}`
                };
            }
        }

        const booking = await PlanEligibilityService.runAtomicCheckAndCreate(
            userId,
            planType,
            bookingStartDateTime,
            async (transaction) => {
                return await Booking.create({
                    userId,
                    venueId,
                    bookingDate: cleanBookingDate as any,
                    startTime: normalizedStart,
                    numberOfGuests: numberOfGuests || (pricing.pkg ? pricing.pkg.maxGuests : 1),
                    totalAmount: pricing.totalAmount,
                    depositAmount: 0,
                    commissionAmount: pricing.commissionAmount,
                    goingMode: goingMode as GoingMode,
                    tablePackage: packageName,
                    specialRequests,
                    isLargePartyRequest: isLargeParty,
                    isUpcomingNight: !!isUpcomingNight,
                    adminApprovalStatus: initialApprovalStatus,
                    partySubject: isLargeParty ? (partySubject || undefined) : undefined,
                    partyRequirement: isLargeParty ? (partyRequirement || undefined) : undefined,
                    partyDescription: isLargeParty ? (partyDescription || undefined) : undefined,
                    mobileNumber: isLargeParty ? (mobileNumber?.trim() || undefined) : undefined,
                    optionalMobileNumber: isLargeParty ? (optionalMobileNumber?.trim() || undefined) : undefined,
                    status: (isLargeParty || razorpayOrder || isWalletPayment || pricing.totalAmount > 0) ? BookingStatus.PENDING : BookingStatus.CONFIRMED,
                    paymentStatus: (isLargeParty || razorpayOrder || isWalletPayment || pricing.totalAmount > 0) ? PaymentStatus.PENDING : PaymentStatus.PAID,
                    razorpayOrderId: razorpayOrder ? razorpayOrder.id : undefined
                }, { transaction });
            }
        );

        try {
            if (booking.status === BookingStatus.CONFIRMED) {
                await generateTicketForBookingHelper(booking.id);
                await booking.reload();

                const guestCount = booking.numberOfGuests || 1;
                const isSolo = goingMode === GoingMode.SOLO || guestCount === 1;
                const isLarge = guestCount > 20 || booking.isLargePartyRequest;
                const notifTitle = isLarge
                    ? '🎉 Large Party Confirmed!'
                    : (isSolo ? '🎉 Solo Booking Confirmed!' : '🎉 Group Party Confirmed!');

                await NotificationService.dispatch({
                    recipientUserId: userId,
                    eventType: 'booking_confirmed',
                    category: 'bookings',
                    entityType: 'Booking',
                    entityId: booking.id,
                    title: notifTitle,
                    body: `Your booking at ${venue.name} for ${formatDateFull(bookingStartDateTime)} at ${formatTime12Hour(bookingStartDateTime)} has been confirmed. View your digital ticket now!`,
                    priority: 'HIGH',
                    idempotencyKey: `booking_created_${booking.id}`,
                    actionType: 'view_ticket',
                    deepLink: `/ticket/${booking.id}`,
                    metadata: {
                        bookingId: booking.id,
                        venueId: venue.id,
                        venueName: venue.name,
                        ticketCode: booking.ticketCode,
                        ticketUrl: (booking as any).ticketUrl,
                        isSolo,
                        isLargeParty: isLarge,
                        guestCount,
                    },
                });

                // Notify Venue Owner
                if (venue.ownerId) {
                    await NotificationService.dispatch({
                        recipientUserId: venue.ownerId,
                        eventType: 'venue_booking_received',
                        category: 'bookings',
                        entityType: 'Booking',
                        entityId: booking.id,
                        title: '🎟 New Booking Received!',
                        body: `A new booking of ${numberOfGuests} guests at ${venue.name} for ${bookingDate} has been confirmed.`,
                        priority: 'HIGH',
                        idempotencyKey: `venue_owner_booking_${booking.id}`,
                    }).catch(() => {});
                }

                // Real-time notification & live feed broadcast for confirmed booking
                try {
                    const enrichedCard = await VenueBookingService.enrichVenueBookingNotificationCard(booking.id, booking.userId);
                    const { io } = require('../server');
                    if (io && enrichedCard) {
                        io.to(`user_${booking.userId}`).emit('notification_updated', enrichedCard);
                        io.to(`user_${booking.userId}`).emit('venue_booking_status_update', { bookingId: booking.id, status: 'confirmed' });
                        io.to('live_feed').emit('live_feed_update', {
                            type: 'venue_booking_activity',
                            bookingId: booking.id,
                            venueName: venue.name,
                            status: 'confirmed',
                            timestamp: new Date().toISOString()
                        });
                    }
                } catch (broadcastErr: any) {
                    logger.warn('Failed to broadcast realtime live feed update for free booking: ' + broadcastErr.message);
                }
            }

            if (isLargeParty || isUpcomingNight) {
                const { io } = require('../server');
                if (io) {
                    io.to('admin_notifications').emit('admin_notification_created', {
                        title: isLargeParty ? 'New Large Party Request' : 'New Upcoming Night Request',
                        body: `A new request for ${numberOfGuests} guests at ${venue.name} requires admin attention.`,
                        type: 'booking_request',
                        entityId: booking.id
                    });
                }
            }
        } catch (adminErr: any) {
            logger.warn('Failed to emit notification for booking: ' + adminErr.message);
        }

        return { booking, razorpayOrder };
    }

    /**
     * Idempotent Payment Verification for Venue Bookings
     */
    public static async verifyBookingPayment(
        razorpay_order_id: string,
        razorpay_payment_id: string,
        razorpay_signature: string
    ): Promise<Booking> {
        const booking = await Booking.findOne({ where: { razorpayOrderId: razorpay_order_id } });
        if (!booking) throw new Error('Booking record not found for the given order');

        if (booking.paymentStatus === PaymentStatus.PAID && booking.status === BookingStatus.CONFIRMED) {
            logger.info(`[VenueBookingService] Booking ${booking.id} already verified & confirmed. Returning idempotent response.`);
            return booking;
        }

        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(`${razorpay_order_id}|${razorpay_payment_id}`);
        const generatedSignature = hmac.digest('hex');

        if (generatedSignature !== razorpay_signature) {
            await booking.update({ paymentStatus: PaymentStatus.PENDING });
            throw new Error('Invalid payment signature');
        }

        // Re-validate booking eligibility using central server time before final confirmation
        if (booking.goingMode === GoingMode.SOLO) {
            const eventDateTime = parseBookingDateTime(booking.bookingDate as any, booking.startTime);
            const leadTimeValidation = await BookingPolicyService.validateBookingTime(
                BookingPolicyType.SOLO_BOOKING,
                eventDateTime
            );
            if (!leadTimeValidation.allowed) {
                await booking.update({ status: BookingStatus.CANCELLED, paymentStatus: PaymentStatus.PENDING });
                await PlanEligibilityService.releaseLock(booking.id);
                throw new Error(leadTimeValidation.reason || 'Booking window has closed for this event time.');
            }
        }

        await booking.update({
            paymentStatus: PaymentStatus.PAID,
            status: BookingStatus.CONFIRMED
        });

        try {
            await generateTicketForBookingHelper(booking.id);
            const venue = await Venue.findByPk(booking.venueId, { attributes: ['name', 'ownerId'] });
            const venueName = venue ? venue.name : 'venue';

            const guestCount = booking.numberOfGuests || 1;
            const isSolo = booking.goingMode === GoingMode.SOLO || guestCount === 1;
            const isLarge = guestCount > 20 || booking.isLargePartyRequest;
            const notifTitle = isLarge
                ? '🎉 Large Party Confirmed!'
                : (isSolo ? '🎉 Solo Booking Confirmed!' : '🎉 Group Party Confirmed!');

            await NotificationService.dispatch({
                recipientUserId: booking.userId,
                eventType: 'booking_confirmed',
                category: 'bookings',
                entityType: 'Booking',
                entityId: booking.id,
                title: notifTitle,
                body: `Your payment for ${venueName} is confirmed! Your ticket is ready in your Wallet.`,
                priority: 'HIGH',
                idempotencyKey: `booking_verified_${booking.id}`,
                actionType: 'view_ticket',
                deepLink: `/ticket/${booking.id}`,
            });

            if (venue && venue.ownerId) {
                await NotificationService.dispatch({
                    recipientUserId: venue.ownerId,
                    eventType: 'venue_booking_received',
                    category: 'bookings',
                    entityType: 'Booking',
                    entityId: booking.id,
                    title: '🎟 New Booking Received!',
                    body: `A new booking at ${venueName} has been confirmed.`,
                    priority: 'HIGH',
                    idempotencyKey: `venue_owner_verified_${booking.id}`,
                }).catch(() => {});
            }

            const enrichedCard = await VenueBookingService.enrichVenueBookingNotificationCard(booking.id, booking.userId);
            const { io } = require('../server');
            if (io && enrichedCard) {
                io.to(`user_${booking.userId}`).emit('notification_updated', enrichedCard);
                io.to(`user_${booking.userId}`).emit('venue_booking_status_update', { bookingId: booking.id, status: 'confirmed' });
                io.to('live_feed').emit('live_feed_update', { type: 'venue_booking_activity', bookingId: booking.id, venueName, status: 'confirmed', timestamp: new Date().toISOString() });
            }

            try {
                const AuditLog = (await import('../models/AuditLog')).default;
                await AuditLog.logAction({
                    userId: booking.userId,
                    action: 'VENUE_BOOKING_CONFIRMED',
                    bookingId: booking.id,
                    metadata: { totalAmount: booking.totalAmount, venueName }
                }).catch(() => {});
            } catch (aErr) {}
        } catch (tErr) {
            logger.error(`[VenueBookingService] Ticket generation/notification error for Booking ${booking.id}:`, tErr);
        }

        return booking;
    }

    /**
     * Consolidates all Venue Booking notifications into ONE single card per booking.
     * Card ID: venue_booking_timeline_${bookingId}
     */
    public static async enrichVenueBookingNotificationCard(
        bookingId: string,
        _recipientUserId: string,
        preloadedBooking?: any
    ): Promise<any | null> {
        try {
            const bookingRecord = preloadedBooking || await Booking.findByPk(bookingId, {
                include: [{ model: Venue, as: 'venue', attributes: ['name', 'addressLine1', 'city'] }]
            });

            if (!bookingRecord || bookingRecord.isLargePartyRequest || bookingRecord.isGroupBooking) {
                return null;
            }

            const venueName = (bookingRecord as any)?.venue?.name || 'Venue';
            const guestCount = bookingRecord.numberOfGuests;
            const bookingDate = bookingRecord.bookingDate;

            const isCreated = true;
            const isRequested = true;
            const isConfirmed = bookingRecord.status === BookingStatus.CONFIRMED || bookingRecord.paymentStatus === PaymentStatus.PAID;
            const isPaid = bookingRecord.paymentStatus === PaymentStatus.PAID;
            const isActive = isConfirmed && bookingRecord.status !== BookingStatus.CANCELLED;
            const isCompleted = bookingRecord.status === BookingStatus.COMPLETED;
            const isCancelled = bookingRecord.status === BookingStatus.CANCELLED;
            const isRefunded = bookingRecord.paymentStatus === PaymentStatus.REFUNDED;

            const reminder2h = bookingRecord.reminder2hSent || false;
            const reminder1h = bookingRecord.reminder1hSent || false;
            const reminder30m = bookingRecord.reminder30mSent || false;

            const timelineSteps = [
                { id: 'created', label: 'Booking Created', completed: isCreated },
                { id: 'requested', label: 'Booking Requested', completed: isRequested },
                { id: 'confirmed', label: 'Booking Confirmed', completed: isConfirmed || isCompleted },
                { id: 'payment_completed', label: 'Payment Completed', completed: isPaid || isCompleted },
                { id: 'active', label: 'Booking Active', completed: isActive || isCompleted },
                { id: 'reminder_2h', label: '2 Hour Reminder', completed: reminder2h || isCompleted },
                { id: 'reminder_1h', label: '1 Hour Reminder', completed: reminder1h || isCompleted },
                { id: 'reminder_30m', label: '30 Minute Reminder', completed: reminder30m || isCompleted },
                { id: 'completed', label: 'Booking Completed', completed: isCompleted }
            ];

            const completedCount = timelineSteps.filter(s => s.completed).length;
            const progressPercentage = Math.round((completedCount / timelineSteps.length) * 100);

            const isPlan = bookingRecord.goingMode === GoingMode.PLAN;
            const isSolo = !isPlan && (bookingRecord.goingMode === GoingMode.SOLO || guestCount === 1);
            const isLarge = !isPlan && (guestCount > 20 || bookingRecord.isLargePartyRequest);

            const refundAmt = Number(bookingRecord.refundAmount || 0);
            const totalAmt = Number(bookingRecord.totalAmount || bookingRecord.depositAmount || 0);
            const refundPct = (totalAmt > 0 && refundAmt > 0)
                ? Math.round((refundAmt / totalAmt) * 100)
                : ((bookingRecord as any).refundPercentage || 100);

            let title = isPlan
                ? `Party Plan at ${venueName} 🎟`
                : (isLarge
                    ? `Large Party at ${venueName} 🎉`
                    : (isSolo ? `Solo Booking at ${venueName} 🎟` : `Group Party at ${venueName} 🎉`));
            let body = `Your reservation for ${guestCount} guests at ${venueName} is being processed.`;
            let statusText = 'Booking Requested';

            if (isCompleted) {
                title = isPlan
                    ? `Party Plan Completed ✨`
                    : (isLarge
                        ? `Large Party Completed ✨`
                        : (isSolo ? `Solo Booking Completed ✨` : `Group Party Completed ✨`));
                body = `Hope you enjoyed your experience at ${venueName}!`;
                statusText = 'Completed';
            } else if (isConfirmed && !isCancelled) {
                title = isPlan
                    ? `Party Plan Confirmed! 🎉`
                    : (isLarge
                        ? `Large Party Confirmed! 🎉`
                        : (isSolo ? `Solo Booking Confirmed! 🎉` : `Group Party Confirmed! 🎉`));
                body = `Your reservation for ${guestCount} guests at ${venueName} is fully confirmed. Your ticket is ready!`;
                statusText = 'Confirmed';
            } else if (isCancelled) {
                title = isPlan
                    ? `Party Plan Cancelled ❌`
                    : (isLarge
                        ? `Large Party Cancelled ❌`
                        : (isSolo ? `Solo Booking Cancelled ❌` : `Group Party Cancelled ❌`));
                body = (isRefunded || refundAmt > 0)
                    ? `Your booking for ${venueName} was cancelled. ${refundPct}% (₹${refundAmt.toFixed(0)}) refunded to your Lunara Wallet.`
                    : `Your booking for ${venueName} was cancelled.`;
                statusText = 'Cancelled';
            }

            const actionButtons = [];
            if (!isPaid && !isCancelled) {
                actionButtons.push({ id: 'pay_now', label: 'Pay Now', primary: true, action: 'PAY_NOW' });
            }
            if (isConfirmed && !isCancelled) {
                actionButtons.push({ id: 'view_ticket', label: 'View Ticket', primary: true, action: 'VIEW_TICKET' });

                // Check cancellation cutoff authoritatively
                const eventDateTime = parseBookingDateTime(bookingRecord.bookingDate as any, bookingRecord.startTime);
                const cutoffValidation = await BookingPolicyService.validateCancellationTime(
                    BookingPolicyType.SOLO_BOOKING,
                    eventDateTime
                );
                if (cutoffValidation.canCancel) {
                    actionButtons.push({ id: 'cancel_booking', label: 'Cancel Booking', primary: false, action: 'CANCEL_BOOKING' });
                }
            }
            if (isCancelled && (isRefunded || refundAmt > 0)) {
                actionButtons.push({ id: 'view_wallet', label: 'View Wallet', primary: true, action: 'VIEW_WALLET' });
            }
            actionButtons.push({ id: 'view_details', label: 'View Details', primary: false, action: 'VIEW_DETAILS' });

            const updatedIso = bookingRecord.updatedAt ? bookingRecord.updatedAt.toISOString() : new Date().toISOString();

            const rawTotal = Number(bookingRecord.totalAmount || bookingRecord.depositAmount || 0);

            return {
                id: `venue_booking_timeline_${bookingId}`,
                title,
                body,
                createdAt: updatedIso,
                updatedAt: updatedIso,
                lastActivityAt: updatedIso,
                requiresAction: Boolean(!isConfirmed && !isCancelled && bookingRecord.paymentStatus !== 'paid'),
                read: false,
                isRead: false,
                category: 'bookings',
                status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isConfirmed ? 'confirmed' : 'pending')),
                paymentStatus: bookingRecord.paymentStatus || (isConfirmed ? 'paid' : 'pending'),
                totalAmount: rawTotal,
                refundAmount: refundAmt,
                refundPercentage: refundPct,
                refundStatus: bookingRecord.refundStatus,
                refundMethod: bookingRecord.refundMethod,
                ticketCode: bookingRecord.ticketCode || undefined,
                ticketUrl: (bookingRecord as any).ticketUrl || undefined,
                data: {
                    type: 'venue_booking_timeline',
                    bookingId,
                    venueName,
                    guestCount,
                    bookingDate,
                    statusText,
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isConfirmed ? 'confirmed' : 'pending')),
                    paymentStatus: bookingRecord.paymentStatus || (isConfirmed ? 'paid' : 'pending'),
                    totalAmount: rawTotal,
                    amount: rawTotal,
                    refundAmount: refundAmt,
                    refundPercentage: refundPct,
                    refundStatus: bookingRecord.refundStatus,
                    refundMethod: bookingRecord.refundMethod,
                    ticketCode: bookingRecord.ticketCode || undefined,
                    ticketUrl: (bookingRecord as any).ticketUrl || undefined,
                    venue: (bookingRecord as any).venue ? {
                        id: (bookingRecord as any).venue.id || bookingRecord.venueId,
                        name: (bookingRecord as any).venue.name || venueName,
                        address: (bookingRecord as any).venue.addressLine1,
                        city: (bookingRecord as any).venue.city,
                    } : undefined,
                    timelineProgress: progressPercentage,
                    currentStatusStep: isCompleted ? 9 : (isActive ? 5 : (isConfirmed ? 3 : 2)),
                    timelineSteps,
                    actionButtons
                }
            };
        } catch (err) {
            logger.error(`[VenueBookingService] enrichVenueBookingNotificationCard error for booking ${bookingId}:`, err);
            return null;
        }
    }

    /**
     * Cancel an uncompleted/pending booking payment attempt and release any time locks immediately.
     */
    public static async cancelPendingBooking(bookingId: string, userId: string): Promise<boolean> {
        try {
            const booking = await Booking.findOne({
                where: {
                    id: bookingId,
                    userId,
                    status: BookingStatus.PENDING,
                },
            });
            if (booking) {
                await booking.update({ status: BookingStatus.CANCELLED });
                await PlanEligibilityService.releaseLock(booking.id);
                logger.info(`[VenueBookingService] Cancelled pending Booking ${bookingId} and released lock for user ${userId}`);
                return true;
            }
            return false;
        } catch (err) {
            logger.error(`[VenueBookingService] Error cancelling pending Booking ${bookingId}:`, err);
            return false;
        }
    }
}

