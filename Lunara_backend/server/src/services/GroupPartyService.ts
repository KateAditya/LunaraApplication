import { Transaction, Op } from 'sequelize';
import GroupParty, { GroupPartyStatus, GroupPartyPaymentStatus } from '../models/GroupParty';
import Booking, { BookingStatus, PaymentStatus, GoingMode, AdminApprovalStatus, BookingPaymentMode } from '../models/Booking';
import Venue from '../models/Venue';
import User from '../models/User';
import { PlanEligibilityService } from './PlanEligibilityService';
import { validateVenueTimingAndHolidays, normalizeStartTime } from '../utils/venueValidator';
import { checkExistingBookingForDate } from '../utils/bookingLimitValidator';
import { generateTicketForGroupPartyHelper } from './ticketService';
import { logger } from '../config/logger';
import Razorpay from 'razorpay';
import crypto from 'crypto';

const razorpay = new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
    key_secret: process.env.RAZORPAY_KEY_SECRET || 'secret123',
});

export enum PartyType {
    SMALL = 'SMALL_GROUP_PARTY',
    LARGE = 'LARGE_GROUP_PARTY'
}

export interface PricingCalculationResult {
    numberOfFriends: number;
    tableBookingCharge: number;
    discountPercentage: number;
    discountAmount: number;
    totalAmount: number;
    chargePerPerson: number;
}

export interface CreateGroupPartyPayload {
    userId: string;
    venueId: string;
    numberOfFriends: number;
    partyDate: string; // ISO or YYYY-MM-DD
    mobileNumber: string;
    optionalMobileNumber?: string;
    foodPreference?: string;
    drinkPreference?: string;
    // Large Party specific fields
    partySubject?: string;
    partyRequirement?: string;
    partyDescription?: string;
    startTime?: string;
}

export class GroupPartyService {
    // Configurable thresholds
    public static readonly DEFAULT_SMALL_PARTY_MAX = 20;

    /**
     * Determines backend party type authoritatively based on guest count and venue capacity.
     */
    public static resolvePartyType(guestCount: number, venueCapacity: number): PartyType {
        if (guestCount > venueCapacity) {
            throw new Error(`Guest count (${guestCount}) exceeds maximum venue capacity (${venueCapacity})`);
        }
        return guestCount <= this.DEFAULT_SMALL_PARTY_MAX ? PartyType.SMALL : PartyType.LARGE;
    }

    /**
     * Calculates authoritative price on backend using venue configuration snapshots.
     */
    public static async calculateAuthoritativePricing(venueId: string, numberOfFriends: number): Promise<PricingCalculationResult> {
        const venue = await Venue.findByPk(venueId);
        if (!venue) {
            throw new Error('Venue not found');
        }

        const chargePerPerson = venue.groupPartyChargePerPerson || venue.tableBookingCharges || 0;
        const discountPercentage = venue.groupPartyDiscountPercentage || venue.discountPercentage || 0;

        const tableBookingCharge = chargePerPerson * numberOfFriends;
        const discountAmount = (tableBookingCharge * discountPercentage) / 100;
        const totalAmount = Math.max(0, tableBookingCharge - discountAmount);

        return {
            numberOfFriends,
            chargePerPerson,
            tableBookingCharge,
            discountPercentage,
            discountAmount,
            totalAmount
        };
    }

    /**
     * Unified Creation Entrypoint for Group Parties
     */
    public static async createParty(payload: CreateGroupPartyPayload): Promise<{
        partyType: PartyType;
        record: GroupParty | Booking;
        razorpayOrderId?: string;
        razorpayKeyId?: string;
        amount?: number;
        currency?: string;
    }> {
        const { userId, venueId, numberOfFriends, partyDate, mobileNumber, optionalMobileNumber, foodPreference, drinkPreference, partySubject, partyRequirement, partyDescription, startTime } = payload;

        if (!mobileNumber || !mobileNumber.trim()) {
            throw new Error('Mobile number is required');
        }

        const venue = await Venue.findByPk(venueId);
        if (!venue) {
            throw new Error('Venue not found');
        }

        // Validate venue operating timing and holidays
        const timingValidation = validateVenueTimingAndHolidays(venue, partyDate, startTime);
        if (!timingValidation.isValid) {
            throw new Error(timingValidation.reason || 'Venue is closed on selected date or timing');
        }

        // Clear out the user's own abandoned/unpaid attempt(s) for this exact
        // date before checking conflict or creating lock.
        const staleSameDayParties = await GroupParty.findAll({
            where: {
                userId,
                partyDate: new Date(partyDate),
                status: GroupPartyStatus.PENDING,
                paymentStatus: { [Op.ne]: GroupPartyPaymentStatus.PAID },
            },
        });
        for (const stale of staleSameDayParties) {
            await stale.update({ status: GroupPartyStatus.CANCELLED, paymentStatus: GroupPartyPaymentStatus.FAILED });
            await PlanEligibilityService.releaseLock(stale.id);
        }

        // Check user booking conflict for date
        const bookingConflictMsg = await checkExistingBookingForDate(userId, partyDate);
        if (bookingConflictMsg) {
            throw new Error('You already have an active plan or booking scheduled on this day.');
        }

        const partyType = this.resolvePartyType(numberOfFriends, venue.capacity || 500);

        if (partyType === PartyType.SMALL) {
            // SMALL PARTY FLOW
            const pricing = await this.calculateAuthoritativePricing(venueId, numberOfFriends);
            
            let razorpayOrder: any = null;
            if (pricing.totalAmount > 0) {
                try {
                    razorpayOrder = await razorpay.orders.create({
                        amount: Math.round(pricing.totalAmount * 100),
                        currency: 'INR',
                        receipt: `gp_${Date.now()}`
                    });
                } catch (rzpErr) {
                    logger.warn('Failed to create real Razorpay order for GP, falling back to mock order: ' + rzpErr);
                    razorpayOrder = {
                        id: `order_mock_${Date.now()}`,
                        amount: Math.round(pricing.totalAmount * 100),
                        currency: 'INR'
                    };
                }
            }

            const groupParty = await PlanEligibilityService.runAtomicCheckAndCreate(
                userId,
                'group_party',
                new Date(partyDate),
                async (transaction: Transaction) => {
                    return await GroupParty.create({
                        userId,
                        venueId,
                        numberOfFriends,
                        tableBookingCharge: pricing.tableBookingCharge,
                        discountAmount: pricing.discountAmount,
                        totalAmount: pricing.totalAmount,
                        partyDate: new Date(partyDate),
                        startTime: startTime ? normalizeStartTime(startTime) : undefined,
                        mobileNumber: mobileNumber.trim(),
                        optionalMobileNumber: optionalMobileNumber?.trim(),
                        foodPreference: foodPreference?.trim(),
                        drinkPreference: drinkPreference?.trim(),
                        status: pricing.totalAmount > 0 ? GroupPartyStatus.PENDING : GroupPartyStatus.CONFIRMED,
                        paymentStatus: pricing.totalAmount > 0 ? GroupPartyPaymentStatus.PENDING : GroupPartyPaymentStatus.PAID,
                        paymentId: razorpayOrder ? razorpayOrder.id : `free_${Date.now()}`
                    }, { transaction });
                }
            );

            // Handle Free Party Instant Confirmation
            if (pricing.totalAmount <= 0) {
                try {
                    await generateTicketForGroupPartyHelper(groupParty.id);
                } catch (ticketErr) {
                    logger.error(`[GroupPartyService] Free ticket gen error for GP ${groupParty.id}:`, ticketErr);
                }
                this.emitNotifications(userId, venue.name, 'free_confirmed', groupParty.id, numberOfFriends);
            }

            return {
                partyType: PartyType.SMALL,
                record: groupParty,
                razorpayOrderId: razorpayOrder ? razorpayOrder.id : '',
                razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
                amount: razorpayOrder ? razorpayOrder.amount : 0,
                currency: razorpayOrder ? razorpayOrder.currency : 'INR'
            };

        } else {
            // LARGE PARTY FLOW (> 20 Guests)
            if (!partySubject?.trim() || !partyRequirement?.trim()) {
                throw new Error('Party Subject and Requirements are mandatory for large group requests.');
            }

            const bookingNumber = `LGP-${Date.now().toString(36).toUpperCase()}-${Math.floor(1000 + Math.random() * 9000)}`;

            const booking = await PlanEligibilityService.runAtomicCheckAndCreate(
                userId,
                'large_group_party',
                new Date(partyDate),
                async (transaction: Transaction) => {
                    return await Booking.create({
                        bookingNumber,
                        userId,
                        venueId,
                        bookingDate: new Date(partyDate),
                        startTime: normalizeStartTime(startTime),
                        tablePackage: 'large_party_request',
                        goingMode: GoingMode.PARTY_REQUEST,
                        isLargePartyRequest: true,
                        adminApprovalStatus: AdminApprovalStatus.PENDING,
                        numberOfGuests: numberOfFriends,
                        partySubject: partySubject.trim(),
                        partyRequirement: partyRequirement.trim(),
                        partyDescription: partyDescription?.trim(),
                        mobileNumber: mobileNumber.trim(),
                        optionalMobileNumber: optionalMobileNumber?.trim(),
                        status: BookingStatus.PENDING,
                        paymentStatus: PaymentStatus.PENDING,
                        paymentMode: BookingPaymentMode.PAY_NOW,
                        totalAmount: 0,
                        depositAmount: 0,
                        commissionAmount: 0,
                    }, { transaction });
                }
            );

            this.emitNotifications(userId, venue.name, 'large_submitted', booking.id, numberOfFriends);

            return {
                partyType: PartyType.LARGE,
                record: booking
            };
        }
    }

    /**
     * Idempotent Payment Verification for Small Group Parties
     */
    public static async verifySmallPartyPayment(
        razorpay_order_id: string,
        razorpay_payment_id: string,
        razorpay_signature: string,
        callerUserId: string
    ): Promise<GroupParty> {
        const groupParty = await GroupParty.findOne({ where: { paymentId: razorpay_order_id } });
        if (!groupParty) {
            throw new Error('Group party booking not found');
        }
        if (groupParty.userId !== callerUserId) {
            const err: any = new Error('You can only verify payment for your own group party');
            err.statusCode = 403;
            throw err;
        }

        // Idempotency check: if already confirmed/paid, return directly
        if (groupParty.paymentStatus === GroupPartyPaymentStatus.PAID && groupParty.status === GroupPartyStatus.CONFIRMED) {
            logger.info(`[GroupPartyService] GroupParty ${groupParty.id} already paid. Returning idempotent response.`);
            return groupParty;
        }

        const isWalletOrMock = razorpay_payment_id?.startsWith('wallet_') ||
            razorpay_order_id?.startsWith('order_mock_') ||
            razorpay_signature === 'mock_signature';

        if (!isWalletOrMock) {
            const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
            hmac.update(`${razorpay_order_id}|${razorpay_payment_id}`);
            const generatedSignature = hmac.digest('hex');

            if (generatedSignature !== razorpay_signature) {
                await groupParty.update({ paymentStatus: GroupPartyPaymentStatus.FAILED });
                throw new Error('Invalid payment signature');
            }
        }

        await groupParty.update({
            paymentStatus: GroupPartyPaymentStatus.PAID,
            status: GroupPartyStatus.CONFIRMED,
            paymentId: razorpay_payment_id || razorpay_order_id,
        });

        try {
            const AuditLog = (await import('../models/AuditLog')).default;
            await AuditLog.logAction({
                userId: groupParty.userId,
                action: 'GROUP_PARTY_PAYMENT_VERIFIED',
                metadata: { razorpay_payment_id, razorpay_order_id, totalAmount: groupParty.totalAmount, partyId: groupParty.id }
            }).catch(() => {});
        } catch (aErr) {}

        try {
            await generateTicketForGroupPartyHelper(groupParty.id);
        } catch (tErr) {
            logger.error(`[GroupPartyService] Ticket generation error for GP ${groupParty.id}:`, tErr);
        }

        const venue = await Venue.findByPk(groupParty.venueId);
        this.emitNotifications(groupParty.userId, venue?.name || 'Venue', 'small_paid', groupParty.id, groupParty.numberOfFriends);

        return groupParty;
    }

    /**
     * Cancel an uncompleted/pending group party payment attempt and release any time locks immediately.
     */
    public static async cancelPendingParty(partyId: string, userId: string): Promise<boolean> {
        try {
            const groupParty = await GroupParty.findOne({
                where: {
                    id: partyId,
                    userId,
                    status: GroupPartyStatus.PENDING,
                    paymentStatus: { [Op.ne]: GroupPartyPaymentStatus.PAID },
                }
            });

            if (!groupParty) {
                return false;
            }

            await groupParty.update({
                status: GroupPartyStatus.CANCELLED,
                paymentStatus: GroupPartyPaymentStatus.FAILED
            });

            await PlanEligibilityService.releaseLock(partyId);
            logger.info(`[GroupPartyService] Cancelled pending GroupParty ${partyId} and released lock for user ${userId}`);
            return true;
        } catch (err: any) {
            logger.error(`[GroupPartyService] Error cancelling pending GroupParty ${partyId}:`, err);
            return false;
        }
    }

    /**
     * Background Job: Sweeps abandoned PENDING orders > 10 minutes old and expires them to release locks.
     */
    public static async expireAbandonedPendingOrders(): Promise<number> {
        const TEN_MINUTES_AGO = new Date(Date.now() - 10 * 60 * 1000);

        // 1. Expire Small Group Parties
        const expiredGroupParties = await GroupParty.findAll({
            where: {
                status: GroupPartyStatus.PENDING,
                paymentStatus: GroupPartyPaymentStatus.PENDING,
                createdAt: { [Op.lt]: TEN_MINUTES_AGO }
            }
        });

        let count = 0;
        for (const party of expiredGroupParties) {
            await party.update({
                status: GroupPartyStatus.CANCELLED,
                paymentStatus: GroupPartyPaymentStatus.FAILED
            });
            logger.info(`[GroupPartyService] Expired abandoned Small GroupParty ${party.id}`);
            count++;
        }

        return count;
    }

    /**
     * Helper to dispatch Socket & Push Notifications idempotently and persist DB records.
     */
    public static async emitNotifications(
        userId: string,
        venueName: string,
        eventType: 'free_confirmed' | 'small_paid' | 'large_submitted',
        entityId: string,
        guestCount: number
    ): Promise<void> {
        try {
            const host = await User.findByPk(userId, { attributes: ['id', 'fcmToken'] });
            let title = '';
            let body = '';
            let type = '';

            if (eventType === 'free_confirmed') {
                title = 'Group Party Booked! 🎉';
                body = `Your group party of ${guestCount} friends at ${venueName} is confirmed!`;
                type = 'group_party_confirmed';
            } else if (eventType === 'small_paid') {
                title = 'Group Party Booked! 🎉';
                body = `Your payment is verified. Group party at ${venueName} is confirmed!`;
                type = 'group_party_confirmed';
            } else if (eventType === 'large_submitted') {
                title = 'Party Request Submitted ⏳';
                body = `Your party request of ${guestCount} guests at ${venueName} is submitted for admin approval.`;
                type = 'large_party_request_submitted';
            }

            // 1. Create DB Notification Record for Host
            try {
                const Notification = (await import('../models/Notification')).default;
                
                await Notification.create({
                    recipientUserId: userId,
                    eventType: type,
                    category: 'bookings' as any,
                    entityType: eventType === 'large_submitted' ? 'booking' : 'group_party',
                    entityId,
                    title,
                    body,
                    priority: 'HIGH' as any,
                    isRead: false,
                    metadata: {
                        venueName,
                        guestCount,
                        eventType,
                        liveCountdownTarget: Date.now() + 24 * 60 * 60 * 1000
                    }
                });
            } catch (dbErr) {
                logger.warn(`[GroupPartyService] Failed to save DB Notification for host: ${dbErr}`);
            }

            // 2. Send FCM Push to Host
            if (host && host.fcmToken) {
                try {
                    const { sendPushNotification } = require('./fcmService');
                    await sendPushNotification(host.fcmToken, { title, body, data: { type, entityId } });
                } catch (pushErr) {
                    logger.warn(`[GroupPartyService] Push send warning: ${pushErr}`);
                }
            }

            // 3. For Large Group Party (> 20 guests): Notify Admins & Venue Owner
            if (eventType === 'large_submitted') {
                try {
                    const Notification = (await import('../models/Notification')).default;

                    const admins = await User.findAll({ where: { role: 'admin' }, attributes: ['id', 'fcmToken'] });
                    const adminTitle = 'New Large Party Request 🚨';
                    const adminBody = `New large party request of ${guestCount} guests at ${venueName} submitted for approval.`;

                    for (const admin of admins) {
                        await Notification.create({
                            recipientUserId: admin.id,
                            eventType: 'large_party_request_submitted',
                            category: 'bookings' as any,
                            entityType: 'booking',
                            entityId,
                            title: adminTitle,
                            body: adminBody,
                            priority: 'HIGH' as any,
                            isRead: false,
                            metadata: { venueName, guestCount, entityId }
                        }).catch(() => {});

                        if (admin.fcmToken) {
                            const { sendPushNotification } = require('./fcmService');
                            sendPushNotification(admin.fcmToken, {
                                title: adminTitle,
                                body: adminBody,
                                data: { type: 'large_party_request_submitted', entityId }
                            }).catch(() => {});
                        }
                    }

                    const { io } = require('../server');
                    if (io) {
                        io.to('admin_notifications').emit('admin_notification_created', {
                            title: adminTitle,
                            body: adminBody,
                            entityId,
                            guestCount,
                            venueName,
                            type: 'party_request',
                            createdAt: new Date().toISOString()
                        });
                    }
                } catch (adminNotifErr) {
                    logger.warn(`[GroupPartyService] Admin notification emit warning: ${adminNotifErr}`);
                }
            } else if (eventType === 'small_paid' || eventType === 'free_confirmed') {
                try {
                    const { io } = require('../server');
                    if (io) {
                        io.to('admin_notifications').emit('admin_notification_created', {
                            title: 'Group Party Booked 🎉',
                            body: `Confirmed group party of ${guestCount} friends at ${venueName}. Payment confirmed.`,
                            entityId,
                            guestCount,
                            venueName,
                            type: 'group_party',
                            createdAt: new Date().toISOString()
                        });
                    }
                } catch (adminNotifErr) {
                    logger.warn(`[GroupPartyService] Admin notification emit warning: ${adminNotifErr}`);
                }
            }

            // 4. Send Live Socket Event to Host & Live Feed
            const { io } = require('../server');
            if (io) {
                io.to(`user_${userId}`).emit('group_party_status_update', { partyId: entityId, eventType });
                io.to(`user_${userId}`).emit('notification_updated', {
                    id: `group_party_timeline_${entityId}`,
                    partyId: entityId,
                    eventType
                });
                io.to('live_feed').emit('live_feed_update', {
                    type: 'group_party_activity',
                    partyId: entityId,
                    venueName,
                    guestCount,
                    eventType,
                    timestamp: new Date().toISOString()
                });
            }
        } catch (err) {
            logger.warn(`[GroupPartyService] Notification emit warning: ${err}`);
        }
    }

    /**
     * Consolidates all Group Party notifications into ONE single card per party.
     * Card ID: group_party_timeline_${partyId}
     */
    public static async enrichGroupPartyNotificationCard(partyId: string, _recipientUserId: string, preloadedGp?: any): Promise<any | null> {
        try {
            // Use pre-loaded record if provided to avoid N+1 DB hit
            let gp = preloadedGp ?? await GroupParty.findByPk(partyId, {
                include: [{ model: Venue, as: 'venue', attributes: ['name', 'addressLine1', 'city'] }]
            });

            let isLargeBooking = false;
            let bookingRecord: any = null;

            if (!gp) {
                const Booking = (await import('../models/Booking')).default;
                bookingRecord = await Booking.findByPk(partyId, {
                    include: [{ model: Venue, as: 'venue', attributes: ['name', 'addressLine1', 'city'] }]
                });
                if (!bookingRecord || !bookingRecord.isLargePartyRequest) {
                    return null;
                }
                isLargeBooking = true;
            }

            const venueName = isLargeBooking ? (bookingRecord.venue?.name || 'Venue') : ((gp as any)?.venue?.name || 'Venue');
            const partyDate = isLargeBooking ? bookingRecord.bookingDate : gp?.partyDate;
            const guestCount = isLargeBooking ? bookingRecord.numberOfGuests : gp?.numberOfFriends;
            const isConfirmed = isLargeBooking 
                ? (bookingRecord.status === 'confirmed' || bookingRecord.adminApprovalStatus === 'payment_done')
                // Free parties: status=CONFIRMED even if paymentStatus=pending; paid parties: need PAID too
                : (gp?.status === GroupPartyStatus.CONFIRMED && (gp?.paymentStatus === GroupPartyPaymentStatus.PAID || Number(gp?.totalAmount ?? 0) <= 0));
            const isPending = isLargeBooking 
                ? (bookingRecord.adminApprovalStatus === 'pending')
                : (gp?.status === GroupPartyStatus.PENDING);
            const isApproved = isLargeBooking 
                ? (bookingRecord.adminApprovalStatus === 'approved')
                : (gp?.status === GroupPartyStatus.APPROVED);
            const isRejected = isLargeBooking 
                ? (bookingRecord.adminApprovalStatus === 'rejected')
                : (gp?.status === GroupPartyStatus.REJECTED);
            const isCancelled = isLargeBooking 
                ? (bookingRecord.status === 'cancelled')
                : (gp?.status === GroupPartyStatus.CANCELLED);
            const isCompleted = isLargeBooking
                ? (bookingRecord.status === 'completed')
                : (gp as any)?.status === 'completed';
            const isExpired = isLargeBooking
                ? (bookingRecord.adminApprovalStatus === 'expired')
                : (gp?.status === GroupPartyStatus.EXPIRED);
            const expiresAt = isLargeBooking ? bookingRecord.expiresAt : gp?.expiresAt;

            const reminder2h = isLargeBooking ? false : (gp?.reminder2hSent || false);
            const reminder1h = isLargeBooking ? false : (gp?.reminder1hSent || false);
            const reminder30m = isLargeBooking ? false : (gp?.reminder30mSent || false);

            const timelineSteps = [
                { id: 'created', label: 'Group Party Created', completed: true },
                { id: 'joined', label: 'Joined', completed: true },
                { id: 'request_pending', label: 'Request Pending', completed: isPending || isApproved || isConfirmed || isCompleted },
                { id: 'approved', label: 'Approved', completed: isApproved || isConfirmed || isCompleted },
                { id: 'payment_confirmed', label: 'Payment Confirmed', completed: isConfirmed || isCompleted },
                { id: 'chat_enabled', label: 'Chat Enabled', completed: isConfirmed || isCompleted },
                { id: 'reminder_2h', label: '2 Hour Reminder', completed: reminder2h || isCompleted },
                { id: 'reminder_1h', label: '1 Hour Reminder', completed: reminder1h || isCompleted },
                { id: 'reminder_30m', label: '30 Minute Reminder', completed: reminder30m || isCompleted },
                { id: 'completed', label: 'Group Party Completed', completed: isCompleted }
            ];

            const completedCount = timelineSteps.filter(s => s.completed).length;
            const progressPercentage = Math.round((completedCount / timelineSteps.length) * 100);

            let title = `Group Party at ${venueName} 🎉`;
            let body = `Group party of ${guestCount} friends at ${venueName}.`;
            let statusText = 'Group Party Initiated';

            if (isConfirmed) {
                title = `Group Party Confirmed! 🎉`;
                body = `Your group party of ${guestCount} friends at ${venueName} is fully confirmed. Get ready!`;
                statusText = 'Confirmed';
            } else if (isApproved) {
                title = `Group Party Approved! 💳`;
                body = `Your request for ${guestCount} guests at ${venueName} is approved. Complete payment now.`;
                statusText = 'Approved - Pending Payment';
            } else if (isPending) {
                title = `Group Party Request Pending ⏳`;
                body = `Your party request at ${venueName} is pending admin/venue verification.`;
                statusText = 'Pending Approval';
            } else if (isRejected) {
                title = `Group Party Rejected ❌`;
                body = `Your party request at ${venueName} could not be approved.`;
                statusText = 'Rejected';
            } else if (isCancelled) {
                title = `Group Party Cancelled ❌`;
                body = `Your group party at ${venueName} was cancelled.`;
                statusText = 'Cancelled';
            } else if (isCompleted) {
                title = `Group Party Completed ✨`;
                body = `Hope you had an amazing night at ${venueName}!`;
                statusText = 'Completed';
            } else if (isExpired) {
                title = `Group Party Expired ⌛`;
                body = `Your party request at ${venueName} expired because payment wasn't completed before the event started.`;
                statusText = 'Expired';
            }

            const actionButtons = [];
            if (!isExpired && (isApproved || (isPending && gp?.paymentStatus === GroupPartyPaymentStatus.PENDING))) {
                actionButtons.push({ id: 'pay_now', label: 'Pay Now', primary: true, action: 'PAY_NOW' });
            }
            if (isConfirmed) {
                actionButtons.push({ id: 'open_chat', label: 'Open Chat', primary: true, action: 'OPEN_CHAT' });
                actionButtons.push({ id: 'view_ticket', label: 'View Ticket', primary: false, action: 'VIEW_TICKET' });
            }
            actionButtons.push({ id: 'view_details', label: 'View Details', primary: false, action: 'VIEW_DETAILS' });

            const updatedIso = isLargeBooking 
                ? (bookingRecord.updatedAt ? bookingRecord.updatedAt.toISOString() : new Date().toISOString())
                : (gp?.updatedAt ? gp.updatedAt.toISOString() : new Date().toISOString());

            return {
                id: `group_party_timeline_${partyId}`,
                title,
                body,
                createdAt: updatedIso,
                updatedAt: updatedIso,
                read: false,
                isRead: false,
                category: 'bookings',
                // Top-level status fields so Flutter can resolve status without parsing data
                status: isExpired ? 'expired' : (isConfirmed ? 'confirmed' : (isCompleted ? 'completed' : (isApproved ? 'approved' : (isCancelled ? 'cancelled' : 'pending')))),
                paymentStatus: isLargeBooking
                    ? (bookingRecord?.paymentStatus || 'pending')
                    : (gp?.paymentStatus || 'pending'),
                totalAmount: isLargeBooking ? 0 : Number(gp?.totalAmount || 0),
                isSmallGroupParty: !isLargeBooking,
                isExpired,
                expiresAt,
                data: {
                    type: 'group_party_timeline',
                    partyId,
                    venueName,
                    guestCount,
                    partyDate,
                    statusText,
                    status: isExpired ? 'expired' : (isConfirmed ? 'confirmed' : (isCompleted ? 'completed' : (isApproved ? 'approved' : (isCancelled ? 'cancelled' : 'pending')))),
                    paymentStatus: isLargeBooking
                        ? (bookingRecord?.paymentStatus || 'pending')
                        : (gp?.paymentStatus || 'pending'),
                    totalAmount: isLargeBooking ? 0 : Number(gp?.totalAmount || 0),
                    isSmallGroupParty: !isLargeBooking,
                    isExpired,
                    expiresAt,
                    timelineProgress: progressPercentage,
                    currentStatusStep: isCompleted ? 10 : (isConfirmed ? 6 : (isApproved ? 4 : 2)),
                    timelineSteps,
                    actionButtons
                }
            };
        } catch (err) {
            logger.error(`[GroupPartyService] enrichGroupPartyNotificationCard error for party ${partyId}:`, err);
            return null;
        }
    }

    /**
     * Consolidates all Large Party notifications into ONE single card per party request.
     * Card ID: large_party_timeline_${bookingId}
     */
    public static async enrichLargePartyNotificationCard(bookingId: string, _recipientUserId: string): Promise<any | null> {
        try {
            const Booking = (await import('../models/Booking')).default;
            const Venue = (await import('../models/Venue')).default;
            const bookingRecord = await Booking.findByPk(bookingId, {
                include: [{ model: Venue, as: 'venue', attributes: ['name', 'addressLine1', 'city'] }]
            });

            if (!bookingRecord || !bookingRecord.isLargePartyRequest) {
                return null;
            }

            const venueName = (bookingRecord as any)?.venue?.name || 'Venue';
            const guestCount = bookingRecord.numberOfGuests;
            const partyDate = bookingRecord.bookingDate;

            const isPublished = true;
            const isRequestSent = true;
            const isApproved = bookingRecord.adminApprovalStatus === 'approved' ||
                bookingRecord.adminApprovalStatus === 'payment_sent' ||
                bookingRecord.adminApprovalStatus === 'payment_done';
            const isPaymentPending = bookingRecord.adminApprovalStatus === 'payment_sent' && bookingRecord.paymentStatus !== 'paid';
            const isPaymentConfirmed = bookingRecord.adminApprovalStatus === 'payment_done' ||
                bookingRecord.status === 'confirmed' ||
                bookingRecord.paymentStatus === 'paid';
            const isChatEnabled = isPaymentConfirmed;
            const isCompleted = bookingRecord.status === 'completed';
            const isExpired = bookingRecord.adminApprovalStatus === 'expired';
            const isRejected = (bookingRecord.adminApprovalStatus === 'rejected' || bookingRecord.status === 'cancelled') && !isExpired;

            const reminder2h = bookingRecord.reminder2hSent || false;
            const reminder1h = bookingRecord.reminder1hSent || false;
            const reminder30m = bookingRecord.reminder30mSent || false;

            const timelineSteps = [
                { id: 'published', label: 'Party Published', completed: isPublished },
                { id: 'request_sent', label: 'Request Sent', completed: isRequestSent },
                { id: 'approved', label: 'Approved', completed: isApproved || isPaymentConfirmed || isCompleted },
                { id: 'payment_pending', label: 'Payment Pending', completed: isPaymentPending || isPaymentConfirmed || isCompleted },
                { id: 'payment_confirmed', label: 'Payment Confirmed', completed: isPaymentConfirmed || isCompleted },
                { id: 'chat_enabled', label: 'Chat Enabled', completed: isChatEnabled || isCompleted },
                { id: 'reminder_2h', label: '2 Hour Reminder', completed: reminder2h || isCompleted },
                { id: 'reminder_1h', label: '1 Hour Reminder', completed: reminder1h || isCompleted },
                { id: 'reminder_30m', label: '30 Minute Reminder', completed: reminder30m || isCompleted },
                { id: 'completed', label: 'Event Completed', completed: isCompleted }
            ];

            const completedCount = timelineSteps.filter(s => s.completed).length;
            const progressPercentage = Math.round((completedCount / timelineSteps.length) * 100);

            let title = `Large Party Request at ${venueName} 🚨`;
            let body = `Your request for ${guestCount} guests at ${venueName} has been submitted for admin approval.`;
            let statusText = 'Request Submitted';

            if (isCompleted) {
                title = `Large Party Completed ✨`;
                body = `Hope you had an amazing night at ${venueName}!`;
                statusText = 'Completed';
            } else if (isPaymentConfirmed) {
                title = `Large Party Confirmed! 🎉`;
                body = `Your party of ${guestCount} guests at ${venueName} is fully confirmed. Enjoy your night!`;
                statusText = 'Confirmed';
            } else if (isPaymentPending) {
                title = `Large Party Payment Link Received 💳`;
                body = `Admin sent a payment link of ₹${bookingRecord.adminPaymentAmount || bookingRecord.totalAmount} for your party at ${venueName}. Complete payment now.`;
                statusText = 'Payment Link Received';
            } else if (isApproved) {
                title = `Large Party Request Approved! 🎉`;
                body = `Admin approved your request for ${guestCount} guests at ${venueName}. Payment link arriving shortly.`;
                statusText = 'Approved - Awaiting Payment Link';
            } else if (isRejected) {
                title = `Large Party Request Rejected ❌`;
                body = `Your request for ${guestCount} guests at ${venueName} could not be approved.`;
                statusText = 'Rejected';
            } else if (isExpired) {
                title = `Large Party Request Expired ⌛`;
                body = `Your request for ${guestCount} guests at ${venueName} expired because payment wasn't completed before the event started.`;
                statusText = 'Expired';
            }

            const actionButtons = [];
            if (isPaymentPending && !isExpired) {
                actionButtons.push({ id: 'pay_now', label: 'Pay Now', primary: true, action: 'PAY_NOW', paymentAmount: bookingRecord.adminPaymentAmount });
            }
            if (isPaymentConfirmed) {
                actionButtons.push({ id: 'open_chat', label: 'Open Chat', primary: true, action: 'OPEN_CHAT' });
                actionButtons.push({ id: 'view_ticket', label: 'View Ticket', primary: false, action: 'VIEW_TICKET' });
            }
            actionButtons.push({ id: 'view_details', label: 'View Details', primary: false, action: 'VIEW_DETAILS' });

            const updatedIso = bookingRecord.updatedAt ? bookingRecord.updatedAt.toISOString() : new Date().toISOString();

            return {
                id: `large_party_timeline_${bookingId}`,
                title,
                body,
                createdAt: updatedIso,
                updatedAt: updatedIso,
                read: false,
                isRead: false,
                category: 'bookings',
                status: isExpired ? 'expired' : (isPaymentConfirmed ? 'confirmed' : (isCompleted ? 'completed' : (isApproved ? 'approved' : (isRejected ? 'cancelled' : 'pending')))),
                paymentStatus: bookingRecord.paymentStatus || 'pending',
                isExpired,
                expiresAt: bookingRecord.expiresAt,
                data: {
                    type: 'large_party_timeline',
                    bookingId,
                    venueName,
                    guestCount,
                    partyDate,
                    statusText,
                    isExpired,
                    expiresAt: bookingRecord.expiresAt,
                    timelineProgress: progressPercentage,
                    currentStatusStep: isCompleted ? 10 : (isPaymentConfirmed ? 6 : (isPaymentPending ? 4 : (isApproved ? 3 : 2))),
                    timelineSteps,
                    actionButtons,
                    adminPaymentAmount: bookingRecord.adminPaymentAmount,
                    adminPaymentLink: bookingRecord.adminPaymentLink
                }
            };
        } catch (err) {
            logger.error(`[GroupPartyService] enrichLargePartyNotificationCard error for booking ${bookingId}:`, err);
            return null;
        }
    }
}
