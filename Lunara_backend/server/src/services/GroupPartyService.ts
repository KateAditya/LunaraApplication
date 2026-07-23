import { Transaction, Op } from 'sequelize';
import GroupParty, { GroupPartyStatus, GroupPartyPaymentStatus } from '../models/GroupParty';
import Booking, { BookingStatus, PaymentStatus, GoingMode, AdminApprovalStatus, BookingPaymentMode } from '../models/Booking';
import Venue from '../models/Venue';
import User from '../models/User';
import { PlanEligibilityService } from './PlanEligibilityService';
import { validateVenueTimingAndHolidays } from '../utils/venueValidator';
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
        const timingValidation = validateVenueTimingAndHolidays(venue, partyDate);
        if (!timingValidation.isValid) {
            throw new Error(timingValidation.reason || 'Venue is closed on selected date or timing');
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
                razorpayOrder = await razorpay.orders.create({
                    amount: Math.round(pricing.totalAmount * 100),
                    currency: 'INR',
                    receipt: `gp_${Date.now()}`
                });
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
                        startTime: startTime || '08:00 PM',
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
        razorpay_signature: string
    ): Promise<GroupParty> {
        const groupParty = await GroupParty.findOne({ where: { paymentId: razorpay_order_id } });
        if (!groupParty) {
            throw new Error('Group party booking not found');
        }

        // Idempotency check: if already confirmed/paid, return directly
        if (groupParty.paymentStatus === GroupPartyPaymentStatus.PAID && groupParty.status === GroupPartyStatus.CONFIRMED) {
            logger.info(`[GroupPartyService] GroupParty ${groupParty.id} already paid. Returning idempotent response.`);
            return groupParty;
        }

        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(`${razorpay_order_id}|${razorpay_payment_id}`);
        const generatedSignature = hmac.digest('hex');

        if (generatedSignature !== razorpay_signature) {
            await groupParty.update({ paymentStatus: GroupPartyPaymentStatus.FAILED });
            throw new Error('Invalid payment signature');
        }

        await groupParty.update({
            paymentStatus: GroupPartyPaymentStatus.PAID,
            status: GroupPartyStatus.CONFIRMED
        });

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
     * Helper to dispatch Socket & Push Notifications idempotently
     */
    private static async emitNotifications(
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

            if (host && host.fcmToken) {
                const { sendPushNotification } = require('./fcmService');
                await sendPushNotification(host.fcmToken, { title, body, data: { type, entityId } });
            }

            const { io } = require('../server');
            if (io) {
                io.to(`user_${userId}`).emit('group_party_status_update', { partyId: entityId, eventType });
            }
        } catch (err) {
            logger.warn(`[GroupPartyService] Notification emit warning: ${err}`);
        }
    }
}
