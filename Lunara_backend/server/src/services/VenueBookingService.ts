import Booking, { BookingStatus, PaymentStatus, GoingMode, AdminApprovalStatus } from '../models/Booking';
import Venue from '../models/Venue';
import BookingTablePackage, { TablePackageName } from '../models/BookingTablePackage';
import { PlanEligibilityService } from './PlanEligibilityService';
import { validateVenueTimingAndHolidays, normalizeStartTime } from '../utils/venueValidator';
import { checkExistingBookingForDate } from '../utils/bookingLimitValidator';
import { generateTicketForBookingHelper } from './ticketService';
import { NotificationService } from './NotificationService';
import { logger } from '../config/logger';
import Razorpay from 'razorpay';
import crypto from 'crypto';

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
        const isStandardOrGroup = packageName === 'Standard Booking' || packageName === 'Group Party Booking' || packageName === 'Confirmation Charges' || !packageName || packageName === 'none';

        if (isStandardOrGroup) {
            const rawCharge = Number(venue.tableBookingCharges);
            const basePrice = (!isNaN(rawCharge) && rawCharge >= 0) ? rawCharge : 0;
            const subtotal = basePrice * numberOfGuests;
            const discountPercent = Number(venue.discountPercentage || 0);
            const discountAmount = (subtotal * discountPercent) / 100;
            totalAmount = Math.max(0, subtotal - discountAmount);
        } else if (packageName && packageName !== 'none') {
            pkg = await BookingTablePackage.findOne({ where: { venueId, name: packageName, isActive: true } });
            if (!pkg) {
                await BookingTablePackage.bulkCreate(DEFAULT_PACKAGES.map(p => ({ ...p, venueId })));
                pkg = await BookingTablePackage.findOne({ where: { venueId, name: packageName, isActive: true } });
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
            partyRequirement, partyDescription, mobileNumber, optionalMobileNumber, isUpcomingNight
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

        if (isLargeParty) {
            const bookingConflictMsg = await checkExistingBookingForDate(userId, bookingDate);
            if (bookingConflictMsg) {
                throw new Error('You already have an active plan or booking scheduled on this day.');
            }
        }

        const pricing = await this.calculateAuthoritativePrice(venueId, packageName, numberOfGuests);

        const initialApprovalStatus: AdminApprovalStatus | undefined = isLargeParty
            ? AdminApprovalStatus.PENDING
            : undefined;

        const normalizedStart = normalizeStartTime(startTime);
        const bookingStartDateTime = new Date(`${bookingDate}T${normalizedStart}:00`);
        if (isNaN(bookingStartDateTime.getTime())) {
            throw new Error('Invalid bookingDate or startTime format');
        }

        const planType = isUpcomingNight ? 'upcoming_night' : (isLargeParty ? 'large_group_party' : 'venue_booking');

        let razorpayOrder: any = null;
        // Solo mode or small party (<= 20) with price > 0 generates Razorpay order immediately
        if ((goingMode === GoingMode.SOLO || !isLargeParty) && pricing.totalAmount > 0) {
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
                    bookingDate: new Date(bookingDate),
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
                    status: razorpayOrder ? BookingStatus.PENDING : (isLargeParty && numberOfGuests > 20 ? BookingStatus.PENDING : BookingStatus.CONFIRMED),
                    paymentStatus: razorpayOrder ? PaymentStatus.PENDING : PaymentStatus.PAID,
                    razorpayOrderId: razorpayOrder ? razorpayOrder.id : undefined
                }, { transaction });
            }
        );

        try {
            if (booking.status === BookingStatus.CONFIRMED) {
                await generateTicketForBookingHelper(booking.id);
                await NotificationService.dispatch({
                    recipientUserId: userId,
                    eventType: 'booking_confirmed',
                    category: 'bookings',
                    entityType: 'Booking',
                    entityId: booking.id,
                    title: '🎉 Booking Confirmed!',
                    body: `Your booking at ${venue.name} for ${bookingDate} at ${startTime} has been confirmed. View your digital ticket now!`,
                    priority: 'HIGH',
                    idempotencyKey: `booking_created_${booking.id}`,
                    actionType: 'view_ticket',
                    deepLink: `/ticket/${booking.id}`,
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
            } else if (razorpayOrder) {
                await NotificationService.dispatch({
                    recipientUserId: userId,
                    eventType: 'booking_pending_payment',
                    category: 'bookings',
                    entityType: 'Booking',
                    entityId: booking.id,
                    title: '🎟 Booking Reserved',
                    body: `Your booking at ${venue.name} for ${bookingDate} is reserved. Complete payment to secure your ticket!`,
                    priority: 'HIGH',
                    idempotencyKey: `booking_pending_${booking.id}`,
                    actionType: 'pay_now',
                    deepLink: `/checkout/${booking.id}`,
                });
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

        await booking.update({
            paymentStatus: PaymentStatus.PAID,
            status: BookingStatus.CONFIRMED
        });

        try {
            await generateTicketForBookingHelper(booking.id);
            const venue = await Venue.findByPk(booking.venueId, { attributes: ['name', 'ownerId'] });
            const venueName = venue ? venue.name : 'venue';

            await NotificationService.dispatch({
                recipientUserId: booking.userId,
                eventType: 'booking_confirmed',
                category: 'bookings',
                entityType: 'Booking',
                entityId: booking.id,
                title: '🎉 Booking Confirmed!',
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
        } catch (tErr) {
            logger.error(`[VenueBookingService] Ticket generation/notification error for Booking ${booking.id}:`, tErr);
        }

        return booking;
    }
}
