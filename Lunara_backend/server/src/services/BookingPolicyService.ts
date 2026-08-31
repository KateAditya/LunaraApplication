import sequelize from '../config/database';
import BookingPolicyConfig, { BookingPolicyType } from '../models/BookingPolicyConfig';
import Booking, { BookingStatus, PaymentStatus, GoingMode } from '../models/Booking';
import GroupParty, { GroupPartyStatus, GroupPartyPaymentStatus } from '../models/GroupParty';
import Venue from '../models/Venue';
import Ticket, { TicketStatus } from '../models/Ticket';
import { WalletService } from './walletService';
import { PlanEligibilityService } from './PlanEligibilityService';
import { NotificationService } from './NotificationService';
import { RealtimeEventBroker } from './RealtimeEventBroker';
import { formatTime12Hour, formatDateFull } from '../utils/dateTimeUtils';
import { parseBookingDateTime } from './EventTimeLockService';

export interface BookingTimeValidationResult {
    allowed: boolean;
    minBookingLeadTimeHours: number;
    cutoffTime: Date;
    eventStartTime: Date;
    currentServerTime: Date;
    hoursRemaining: number;
    reason?: string;
}

export interface CancellationTimeValidationResult {
    canCancel: boolean;
    cancellationCutoffHours: number;
    cutoffTime: Date;
    eventStartTime: Date;
    currentServerTime: Date;
    reason?: string;
}

export interface RefundCalculationResult {
    refundEnabled: boolean;
    refundPercentage: number;
    paidAmount: number;
    refundAmount: number;
    nonRefundableAmount: number;
    isRefundable: boolean;
}

export interface CancellationPreviewResult {
    bookingId: string;
    bookingType: 'SOLO_BOOKING' | 'GROUP_PARTY';
    venueName: string;
    venueAddress?: string;
    eventDate: string;
    eventTime: string;
    canCancel: boolean;
    cancellationReason?: string;
    paidAmount: number;
    refundPolicy: {
        refundEnabled: boolean;
        refundPercentage: number;
        cancellationCutoffHours: number;
    };
    refundAmount: number;
    nonRefundableAmount: number;
    refundMethod: string;
}

export class BookingPolicyService {

    /**
     * Retrieves or auto-seeds default policy configuration for the specified booking type.
     */
    public static async getPolicy(bookingType: BookingPolicyType): Promise<BookingPolicyConfig> {
        let policy = await BookingPolicyConfig.findOne({ where: { bookingType } });
        if (!policy) {
            policy = await BookingPolicyConfig.create({
                bookingType,
                minBookingLeadTimeHours: 2.0,
                cancellationCutoffHours: 2.0,
                refundEnabled: true,
                refundPercentage: 80.0,
                isActive: true,
            });
        }
        return policy;
    }

    /**
     * Retrieves all active booking policies (Solo & Small Group Party).
     */
    public static async getAllPolicies(): Promise<Record<string, BookingPolicyConfig>> {
        const soloPolicy = await this.getPolicy(BookingPolicyType.SOLO_BOOKING);
        const groupPolicy = await this.getPolicy(BookingPolicyType.GROUP_PARTY);
        return {
            SOLO_BOOKING: soloPolicy,
            GROUP_PARTY: groupPolicy,
        };
    }

    /**
     * Updates policy settings for a specific booking type (Admin only).
     */
    public static async updatePolicy(
        bookingType: BookingPolicyType,
        updates: {
            minBookingLeadTimeHours?: number;
            cancellationCutoffHours?: number;
            refundEnabled?: boolean;
            refundPercentage?: number;
            isActive?: boolean;
        }
    ): Promise<BookingPolicyConfig> {
        const policy = await this.getPolicy(bookingType);
        if (updates.minBookingLeadTimeHours !== undefined) {
            policy.minBookingLeadTimeHours = Math.max(0, Number(updates.minBookingLeadTimeHours));
        }
        if (updates.cancellationCutoffHours !== undefined) {
            policy.cancellationCutoffHours = Math.max(0, Number(updates.cancellationCutoffHours));
        }
        if (updates.refundEnabled !== undefined) {
            policy.refundEnabled = Boolean(updates.refundEnabled);
        }
        if (updates.refundPercentage !== undefined) {
            policy.refundPercentage = Math.min(100, Math.max(0, Number(updates.refundPercentage)));
        }
        if (updates.isActive !== undefined) {
            policy.isActive = Boolean(updates.isActive);
        }
        await policy.save();
        return policy;
    }

    /**
     * Authoritatively validates booking lead time using backend server time.
     */
    public static async validateBookingTime(
        bookingType: BookingPolicyType,
        eventDateTime: Date
    ): Promise<BookingTimeValidationResult> {
        const policy = await this.getPolicy(bookingType);
        const currentServerTime = new Date();
        const nowMs = currentServerTime.getTime();
        const eventMs = eventDateTime.getTime();

        const leadTimeMs = policy.minBookingLeadTimeHours * 3600 * 1000;
        const cutoffTimestamp = eventMs - leadTimeMs;
        const cutoffTime = new Date(cutoffTimestamp);

        const diffMs = eventMs - nowMs;
        const diffHours = diffMs / (3600 * 1000);
        const hoursRemaining = Math.max(0, Math.round(diffHours * 10) / 10);

        if (nowMs > cutoffTimestamp) {
            const bookingTypeName = bookingType === BookingPolicyType.SOLO_BOOKING ? 'Solo Bookings' : 'Group Parties';
            return {
                allowed: false,
                minBookingLeadTimeHours: policy.minBookingLeadTimeHours,
                cutoffTime,
                eventStartTime: eventDateTime,
                currentServerTime,
                hoursRemaining,
                reason: `${bookingTypeName} must be booked at least ${policy.minBookingLeadTimeHours} hours before the scheduled start time. The booking window for this slot has closed.`,
            };
        }

        return {
            allowed: true,
            minBookingLeadTimeHours: policy.minBookingLeadTimeHours,
            cutoffTime,
            eventStartTime: eventDateTime,
            currentServerTime,
            hoursRemaining,
        };
    }

    /**
     * Authoritatively validates cancellation cutoff using backend server time.
     */
    public static async validateCancellationTime(
        bookingType: BookingPolicyType,
        eventDateTime: Date
    ): Promise<CancellationTimeValidationResult> {
        const policy = await this.getPolicy(bookingType);
        const currentServerTime = new Date();
        const nowMs = currentServerTime.getTime();
        const eventMs = eventDateTime.getTime();

        const cutoffMs = policy.cancellationCutoffHours * 3600 * 1000;
        const cutoffTimestamp = eventMs - cutoffMs;
        const cutoffTime = new Date(cutoffTimestamp);

        if (nowMs > cutoffTimestamp) {
            return {
                canCancel: false,
                cancellationCutoffHours: policy.cancellationCutoffHours,
                cutoffTime,
                eventStartTime: eventDateTime,
                currentServerTime,
                reason: `Cancellations are only allowed up to ${policy.cancellationCutoffHours} hours prior to the event. The cancellation window for this booking has closed.`,
            };
        }

        return {
            canCancel: true,
            cancellationCutoffHours: policy.cancellationCutoffHours,
            cutoffTime,
            eventStartTime: eventDateTime,
            currentServerTime,
        };
    }

    /**
     * Authoritatively calculates refund amount and percentage on backend.
     */
    public static async calculateRefund(
        bookingType: BookingPolicyType,
        paidAmount: number
    ): Promise<RefundCalculationResult> {
        const policy = await this.getPolicy(bookingType);
        const cleanPaid = Math.max(0, Number(paidAmount) || 0);

        if (!policy.refundEnabled || cleanPaid <= 0) {
            return {
                refundEnabled: policy.refundEnabled,
                refundPercentage: policy.refundPercentage,
                paidAmount: cleanPaid,
                refundAmount: 0,
                nonRefundableAmount: cleanPaid,
                isRefundable: false,
            };
        }

        const refundAmount = Math.round(cleanPaid * (policy.refundPercentage / 100) * 100) / 100;
        const nonRefundableAmount = Math.max(0, Math.round((cleanPaid - refundAmount) * 100) / 100);

        return {
            refundEnabled: true,
            refundPercentage: policy.refundPercentage,
            paidAmount: cleanPaid,
            refundAmount,
            nonRefundableAmount,
            isRefundable: refundAmount > 0,
        };
    }

    /**
     * Preview cancellation details for Solo Booking.
     */
    public static async getSoloBookingCancellationPreview(
        bookingId: string,
        userId: string
    ): Promise<CancellationPreviewResult> {
        const booking = await Booking.findOne({
            where: { id: bookingId, userId },
            include: [{ model: Venue, as: 'venue' }],
        });

        if (!booking) {
            throw new Error('Solo booking not found');
        }

        if (booking.isLargePartyRequest || booking.goingMode === GoingMode.PARTY_REQUEST && (booking.numberOfGuests || 1) > 20) {
            throw new Error('This policy applies exclusively to Solo Bookings and small group parties.');
        }

        if (booking.status === BookingStatus.CANCELLED) {
            throw new Error('Booking is already cancelled.');
        }

        const eventDateTime = parseBookingDateTime(booking.bookingDate as any, booking.startTime);
        const validation = await this.validateCancellationTime(BookingPolicyType.SOLO_BOOKING, eventDateTime);
        const paidAmount = booking.paymentStatus === PaymentStatus.PAID ? Number(booking.totalAmount || 0) : 0;
        const refundCalc = await this.calculateRefund(BookingPolicyType.SOLO_BOOKING, paidAmount);

        const venueName = (booking as any)?.venue?.name || 'Venue';
        const venueAddress = (booking as any)?.venue?.addressLine1 || (booking as any)?.venue?.city || '';

        return {
            bookingId: booking.id,
            bookingType: 'SOLO_BOOKING',
            venueName,
            venueAddress,
            eventDate: formatDateFull(eventDateTime),
            eventTime: formatTime12Hour(eventDateTime),
            canCancel: validation.canCancel,
            cancellationReason: validation.reason,
            paidAmount,
            refundPolicy: {
                refundEnabled: refundCalc.refundEnabled,
                refundPercentage: refundCalc.refundPercentage,
                cancellationCutoffHours: validation.cancellationCutoffHours,
            },
            refundAmount: validation.canCancel ? refundCalc.refundAmount : 0,
            nonRefundableAmount: validation.canCancel ? refundCalc.nonRefundableAmount : paidAmount,
            refundMethod: 'Lunara Wallet',
        };
    }

    /**
     * Atomically cancels Solo Booking, invalidates tickets, and issues wallet refund.
     */
    public static async cancelAndRefundSoloBooking(
        bookingId: string,
        userId: string,
        cancellationReason?: string
    ): Promise<{
        success: boolean;
        message: string;
        booking: Booking;
        refundAmount: number;
        walletTransactionId?: string;
    }> {
        const booking = await Booking.findOne({
            where: { id: bookingId, userId },
            include: [{ model: Venue, as: 'venue' }],
        });

        if (!booking) {
            throw new Error('Solo booking not found');
        }

        if (booking.isLargePartyRequest || (booking.goingMode === GoingMode.PARTY_REQUEST && (booking.numberOfGuests || 1) > 20)) {
            throw new Error('This cancellation policy does not apply to Large Parties (>20 guests).');
        }

        if (booking.status === BookingStatus.CANCELLED) {
            throw new Error('Booking has already been cancelled.');
        }

        const eventDateTime = parseBookingDateTime(booking.bookingDate as any, booking.startTime);
        const validation = await this.validateCancellationTime(BookingPolicyType.SOLO_BOOKING, eventDateTime);
        if (!validation.canCancel) {
            throw new Error(validation.reason || 'Cancellation cutoff window has passed.');
        }

        const wasPaid = booking.paymentStatus === PaymentStatus.PAID;
        const paidAmount = wasPaid ? Number(booking.totalAmount || 0) : 0;
        const refundCalc = await this.calculateRefund(BookingPolicyType.SOLO_BOOKING, paidAmount);
        const refundAmount = wasPaid ? refundCalc.refundAmount : 0;

        const t = await sequelize.transaction();
        let walletTxId: string | undefined;

        try {
            // Update booking status
            await booking.update({
                status: BookingStatus.CANCELLED,
                paymentStatus: refundAmount > 0 ? PaymentStatus.REFUNDED : booking.paymentStatus,
                cancellationReason: cancellationReason || 'Cancelled by user',
                cancelledAt: new Date(),
            }, { transaction: t });

            // Invalidate tickets
            await Ticket.update(
                { ticketStatus: TicketStatus.CANCELLED, cancelledAt: new Date() },
                { where: { bookingId: booking.id }, transaction: t }
            );

            // Release time locks
            await PlanEligibilityService.releaseLock(booking.id);

            // Process Wallet Refund if eligible
            if (wasPaid && refundAmount > 0) {
                const refundResult = await WalletService.refundToWallet({
                    userId,
                    amount: refundAmount,
                    bookingId: booking.id,
                    reference: `REFUND_SOLO_${booking.id.substring(0, 8).toUpperCase()}_${Date.now()}`,
                    reason: cancellationReason || `Cancellation refund for Solo Booking (${refundCalc.refundPercentage}%)`,
                    metadata: {
                        originalAmountPaid: paidAmount,
                        refundPercentage: refundCalc.refundPercentage,
                        nonRefundableAmount: refundCalc.nonRefundableAmount,
                        bookingId: booking.id,
                    },
                }, t);
                walletTxId = refundResult.transaction.id;
            }

            await t.commit();
        } catch (err) {
            await t.rollback();
            throw err;
        }

        const venueName = (booking as any)?.venue?.name || 'Venue';

        // Dispatch notifications
        await NotificationService.dispatch({
            recipientUserId: userId,
            eventType: 'booking_cancelled',
            category: 'bookings',
            entityType: 'Booking',
            entityId: booking.id,
            title: '❌ Booking Cancelled',
            body: refundAmount > 0
                ? `Your booking at ${venueName} has been cancelled. ₹${refundAmount} has been refunded to your Lunara Wallet.`
                : `Your booking at ${venueName} has been cancelled.`,
            priority: 'HIGH',
            idempotencyKey: `solo_cancel_${booking.id}`,
            actionType: 'view_details',
            deepLink: `/bookings`,
        }).catch(() => {});

        RealtimeEventBroker.emitToUser(userId, 'booking_updated', 'ticket', booking.id, {
            bookingId: booking.id,
            status: BookingStatus.CANCELLED,
            refundAmount,
        });

        return {
            success: true,
            message: refundAmount > 0
                ? `Booking cancelled successfully. ₹${refundAmount} refunded to your Lunara Wallet.`
                : 'Booking cancelled successfully.',
            booking,
            refundAmount,
            walletTransactionId: walletTxId,
        };
    }

    /**
     * Preview cancellation details for Small Group Party (<= 20).
     */
    public static async getSmallGroupPartyCancellationPreview(
        partyId: string,
        userId: string
    ): Promise<CancellationPreviewResult> {
        const party = await GroupParty.findOne({
            where: { id: partyId, userId },
            include: [{ model: Venue, as: 'venue' }],
        });

        if (!party) {
            throw new Error('Group party not found');
        }

        if (party.status === GroupPartyStatus.CANCELLED) {
            throw new Error('Group party is already cancelled.');
        }

        const eventDateTime = parseBookingDateTime(party.partyDate as any, party.startTime);
        const validation = await this.validateCancellationTime(BookingPolicyType.GROUP_PARTY, eventDateTime);
        const paidAmount = party.paymentStatus === GroupPartyPaymentStatus.PAID ? Number(party.totalAmount || 0) : 0;
        const refundCalc = await this.calculateRefund(BookingPolicyType.GROUP_PARTY, paidAmount);

        const venueName = (party as any)?.venue?.name || 'Venue';
        const venueAddress = (party as any)?.venue?.addressLine1 || (party as any)?.venue?.city || '';

        return {
            bookingId: party.id,
            bookingType: 'GROUP_PARTY',
            venueName,
            venueAddress,
            eventDate: formatDateFull(eventDateTime),
            eventTime: formatTime12Hour(eventDateTime),
            canCancel: validation.canCancel,
            cancellationReason: validation.reason,
            paidAmount,
            refundPolicy: {
                refundEnabled: refundCalc.refundEnabled,
                refundPercentage: refundCalc.refundPercentage,
                cancellationCutoffHours: validation.cancellationCutoffHours,
            },
            refundAmount: validation.canCancel ? refundCalc.refundAmount : 0,
            nonRefundableAmount: validation.canCancel ? refundCalc.nonRefundableAmount : paidAmount,
            refundMethod: 'Lunara Wallet',
        };
    }

    /**
     * Atomically cancels Small Group Party (<= 20), invalidates tickets, and issues wallet refund.
     */
    public static async cancelAndRefundGroupParty(
        partyId: string,
        userId: string,
        cancellationReason?: string
    ): Promise<{
        success: boolean;
        message: string;
        party: GroupParty;
        refundAmount: number;
        walletTransactionId?: string;
    }> {
        const party = await GroupParty.findOne({
            where: { id: partyId, userId },
            include: [{ model: Venue, as: 'venue' }],
        });

        if (!party) {
            throw new Error('Group party not found');
        }

        if (party.status === GroupPartyStatus.CANCELLED) {
            throw new Error('Group party has already been cancelled.');
        }

        const eventDateTime = parseBookingDateTime(party.partyDate as any, party.startTime);
        const validation = await this.validateCancellationTime(BookingPolicyType.GROUP_PARTY, eventDateTime);
        if (!validation.canCancel) {
            throw new Error(validation.reason || 'Cancellation cutoff window has passed.');
        }

        const wasPaid = party.paymentStatus === GroupPartyPaymentStatus.PAID;
        const paidAmount = wasPaid ? Number(party.totalAmount || 0) : 0;
        const refundCalc = await this.calculateRefund(BookingPolicyType.GROUP_PARTY, paidAmount);
        const refundAmount = wasPaid ? refundCalc.refundAmount : 0;

        const t = await sequelize.transaction();
        let walletTxId: string | undefined;

        try {
            // Update party status
            await party.update({
                status: GroupPartyStatus.CANCELLED,
                paymentStatus: refundAmount > 0 ? (GroupPartyPaymentStatus as any).REFUNDED || GroupPartyPaymentStatus.FAILED : party.paymentStatus,
            }, { transaction: t });

            // Invalidate tickets
            await Ticket.update(
                { ticketStatus: TicketStatus.CANCELLED, cancelledAt: new Date() },
                { where: { bookingId: party.id }, transaction: t }
            );

            // Release time locks
            await PlanEligibilityService.releaseLock(party.id);

            // Process Wallet Refund if eligible
            if (wasPaid && refundAmount > 0) {
                const refundResult = await WalletService.refundToWallet({
                    userId,
                    amount: refundAmount,
                    bookingId: null,
                    partyPlanId: null,
                    reference: `REFUND_GP_${party.id.substring(0, 8).toUpperCase()}_${Date.now()}`,
                    reason: cancellationReason || `Cancellation refund for Group Party (${refundCalc.refundPercentage}%)`,
                    metadata: {
                        originalAmountPaid: paidAmount,
                        refundPercentage: refundCalc.refundPercentage,
                        nonRefundableAmount: refundCalc.nonRefundableAmount,
                        groupPartyId: party.id,
                    },
                }, t);
                walletTxId = refundResult.transaction.id;
            }

            await t.commit();
        } catch (err) {
            await t.rollback();
            throw err;
        }

        const venueName = (party as any)?.venue?.name || 'Venue';

        // Dispatch notifications
        await NotificationService.dispatch({
            recipientUserId: userId,
            eventType: 'booking_cancelled',
            category: 'bookings',
            entityType: 'GroupParty',
            entityId: party.id,
            title: '❌ Group Party Cancelled',
            body: refundAmount > 0
                ? `Your group party at ${venueName} has been cancelled. ₹${refundAmount} has been refunded to your Lunara Wallet.`
                : `Your group party at ${venueName} has been cancelled.`,
            priority: 'HIGH',
            idempotencyKey: `gp_cancel_${party.id}`,
            actionType: 'view_details',
            deepLink: `/group-parties`,
        }).catch(() => {});

        RealtimeEventBroker.emitToUser(userId, 'group_party_updated', 'group_party', party.id, {
            partyId: party.id,
            status: GroupPartyStatus.CANCELLED,
            refundAmount,
        });

        return {
            success: true,
            message: refundAmount > 0
                ? `Group party cancelled successfully. ₹${refundAmount} refunded to your Lunara Wallet.`
                : 'Group party cancelled successfully.',
            party,
            refundAmount,
            walletTransactionId: walletTxId,
        };
    }
}

export default BookingPolicyService;
