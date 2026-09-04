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

export interface RefundPayoutDetails {
    refundMethod?: string;
    payoutType?: 'UPI_ID' | 'UPI_NUMBER' | 'BANK_ACCOUNT' | string;
    upiId?: string;
    upiNumber?: string;
    bankAccountNumber?: string;
    bankIfsc?: string;
    bankHolderName?: string;
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
    requiresPayoutDetails: boolean;
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
        let booking = await Booking.findOne({
            where: { id: bookingId, userId },
            include: [{ model: Venue, as: 'venue' }],
        });

        if (!booking) {
            // Fallback: check GroupParty table
            const party = await GroupParty.findOne({
                where: { id: bookingId, userId },
                include: [{ model: Venue, as: 'venue' }],
            });
            if (party) {
                return this.getSmallGroupPartyCancellationPreview(bookingId, userId);
            }
            throw new Error('Solo booking not found');
        }

        if (booking.isLargePartyRequest || (booking.goingMode === GoingMode.PARTY_REQUEST && (booking.numberOfGuests || 1) > 20)) {
            throw new Error('This policy applies exclusively to Solo Bookings and small group parties.');
        }

        if (booking.status === BookingStatus.CANCELLED) {
            throw new Error('Booking is already cancelled.');
        }

        const isGroupBooking = booking.isGroupBooking || booking.goingMode === GoingMode.PARTY_REQUEST || (booking.numberOfGuests || 1) > 1;
        const eventDateTime = parseBookingDateTime(booking.bookingDate as any, booking.startTime);
        const policyType = isGroupBooking ? BookingPolicyType.GROUP_PARTY : BookingPolicyType.SOLO_BOOKING;
        const validation = await this.validateCancellationTime(policyType, eventDateTime);
        const paidAmount = booking.paymentStatus === PaymentStatus.PAID ? Number(booking.totalAmount || 0) : 0;
        const refundCalc = await this.calculateRefund(policyType, paidAmount);

        const venueName = (booking as any)?.venue?.name || 'Venue';
        const venueAddress = (booking as any)?.venue?.addressLine1 || (booking as any)?.venue?.city || '';
        const isLargeRefund = refundCalc.refundAmount > 1500;

        return {
            bookingId: booking.id,
            bookingType: isGroupBooking ? 'GROUP_PARTY' : 'SOLO_BOOKING',
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
            refundMethod: isLargeRefund ? 'UPI / Bank Transfer' : 'Lunara Wallet',
            requiresPayoutDetails: isLargeRefund,
        };
    }

    /**
     * Atomically cancels Solo Booking, invalidates tickets, and issues wallet refund (<= 1500) or saves payout details (> 1500).
     */
    public static async cancelAndRefundSoloBooking(
        bookingId: string,
        userId: string,
        cancellationReason?: string,
        payoutDetails?: RefundPayoutDetails,
        isGroupPartyContext: boolean = false
    ): Promise<{
        success: boolean;
        message: string;
        booking: any;
        refundAmount: number;
        walletTransactionId?: string;
        refundMethod: string;
    }> {
        let booking = await Booking.findOne({
            where: { id: bookingId, userId },
            include: [{ model: Venue, as: 'venue' }],
        });

        if (!booking) {
            // Fallback: check GroupParty table
            const party = await GroupParty.findOne({
                where: { id: bookingId, userId },
                include: [{ model: Venue, as: 'venue' }],
            });
            if (party) {
                const res = await this.cancelAndRefundGroupParty(bookingId, userId, cancellationReason, payoutDetails);
                return {
                    success: res.success,
                    message: res.message,
                    booking: res.party,
                    refundAmount: res.refundAmount,
                    walletTransactionId: res.walletTransactionId,
                    refundMethod: res.refundMethod,
                };
            }
            throw new Error('Solo booking not found');
        }

        if (booking.isLargePartyRequest || (booking.goingMode === GoingMode.PARTY_REQUEST && (booking.numberOfGuests || 1) > 20)) {
            throw new Error('This cancellation policy does not apply to Large Parties (>20 guests).');
        }

        if (booking.status === BookingStatus.CANCELLED) {
            throw new Error('Booking has already been cancelled.');
        }

        const isGroupBooking = isGroupPartyContext || booking.isGroupBooking || booking.goingMode === GoingMode.PARTY_REQUEST || (booking.numberOfGuests || 1) > 1;
        const policyType = isGroupBooking ? BookingPolicyType.GROUP_PARTY : BookingPolicyType.SOLO_BOOKING;
        const eventDateTime = parseBookingDateTime(booking.bookingDate as any, booking.startTime);
        const validation = await this.validateCancellationTime(policyType, eventDateTime);
        if (!validation.canCancel) {
            throw new Error(validation.reason || 'Cancellation cutoff window has passed.');
        }

        const wasPaid = booking.paymentStatus === PaymentStatus.PAID;
        const paidAmount = wasPaid ? Number(booking.totalAmount || 0) : 0;
        const refundCalc = await this.calculateRefund(policyType, paidAmount);
        const refundAmount = wasPaid ? refundCalc.refundAmount : 0;
        const isLargeRefund = refundAmount > 1500;

        if (wasPaid && isLargeRefund) {
            const hasUpiId = payoutDetails?.upiId && payoutDetails.upiId.trim().length > 0;
            const hasUpiNumber = payoutDetails?.upiNumber && payoutDetails.upiNumber.trim().length === 10;
            const hasBank = payoutDetails?.bankAccountNumber && payoutDetails.bankAccountNumber.trim().length > 0 &&
                            payoutDetails?.bankIfsc && payoutDetails.bankIfsc.trim().length > 0;
            if (!hasUpiId && !hasUpiNumber && !hasBank) {
                throw new Error('For refund amounts exceeding ₹1,500, please provide your UPI ID, UPI phone number, or Bank account details.');
            }
        }

        const t = await sequelize.transaction();
        let walletTxId: string | undefined;

        try {
            // Update booking status
            await booking.update({
                status: BookingStatus.CANCELLED,
                paymentStatus: (wasPaid && refundAmount > 0)
                    ? (isLargeRefund ? ('refund_processing' as any) : PaymentStatus.REFUNDED)
                    : booking.paymentStatus,
                cancellationReason: cancellationReason || 'Cancelled by user',
                cancelledAt: new Date(),
                refundMethod: isLargeRefund ? 'BANK_UPI' : 'WALLET',
                payoutType: isLargeRefund ? (payoutDetails?.payoutType || 'UPI_ID') : undefined,
                upiId: isLargeRefund ? payoutDetails?.upiId?.trim() : undefined,
                upiNumber: isLargeRefund ? payoutDetails?.upiNumber?.trim() : undefined,
                bankAccountNumber: isLargeRefund ? payoutDetails?.bankAccountNumber?.trim() : undefined,
                bankIfsc: isLargeRefund ? payoutDetails?.bankIfsc?.trim()?.toUpperCase() : undefined,
                bankHolderName: isLargeRefund ? payoutDetails?.bankHolderName?.trim() : undefined,
                refundAmount,
                refundStatus: (wasPaid && refundAmount > 0) ? (isLargeRefund ? 'PENDING_PAYOUT' : 'COMPLETED') : 'NONE',
            }, { transaction: t });

            // Invalidate tickets
            await Ticket.update(
                { ticketStatus: TicketStatus.CANCELLED, cancelledAt: new Date() },
                { where: { bookingId: booking.id }, transaction: t }
            );

            // Release time locks
            await PlanEligibilityService.releaseLock(booking.id);

            // Process Wallet Refund if eligible (<= ₹1500)
            if (wasPaid && refundAmount > 0 && !isLargeRefund) {
                const refundResult = await WalletService.refundToWallet({
                    userId,
                    amount: refundAmount,
                    bookingId: booking.id,
                    reference: isGroupBooking
                        ? `REFUND_GP_${booking.id.substring(0, 8).toUpperCase()}_${Date.now()}`
                        : `REFUND_SOLO_${booking.id.substring(0, 8).toUpperCase()}_${Date.now()}`,
                    reason: cancellationReason || (isGroupBooking ? 'GROUP PARTY CANCELLED' : 'SOLO BOOKING CANCELLED'),
                    metadata: {
                        originalAmountPaid: paidAmount,
                        refundPercentage: refundCalc.refundPercentage,
                        nonRefundableAmount: refundCalc.nonRefundableAmount,
                        refundAmount,
                        bookingId: booking.id,
                        transactionLabel: isGroupBooking ? 'GROUP PARTY CANCELLED' : 'SOLO BOOKING CANCELLED',
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
        const entityLabel = isGroupBooking ? 'Group Party' : 'Booking';
        const notifTitle = isGroupBooking ? 'Group Party Cancelled' : 'Booking Cancelled';
        const notifBody = refundAmount > 0
            ? (isLargeRefund
                ? `Your ${entityLabel} at ${venueName} has been cancelled.\nAmount Paid: ₹${paidAmount}\nRefund Percentage: ${refundCalc.refundPercentage}%\nRefund Amount: ₹${refundAmount}\nA refund of ₹${refundAmount} will be transferred to your provided payout account within 24-48 hours.`
                : `Your ${entityLabel} at ${venueName} has been cancelled.\nAmount Paid: ₹${paidAmount}\nRefund Percentage: ${refundCalc.refundPercentage}%\nRefund Amount: ₹${refundAmount}\n₹${refundAmount} has been credited to your Lunara Wallet.`)
            : `Your ${entityLabel} at ${venueName} has been cancelled.`;

        // Dispatch notifications
        await NotificationService.dispatch({
            recipientUserId: userId,
            eventType: 'booking_cancelled',
            category: 'bookings',
            entityType: isGroupBooking ? 'GroupParty' : 'Booking',
            entityId: booking.id,
            title: notifTitle,
            body: notifBody,
            priority: 'HIGH',
            idempotencyKey: `${isGroupBooking ? 'gp' : 'solo'}_cancel_${booking.id}`,
            actionType: 'view_details',
            deepLink: isGroupBooking ? '/group-parties' : '/bookings',
        }).catch(() => {});

        RealtimeEventBroker.emitToUser(userId, 'booking_updated', 'ticket', booking.id, {
            bookingId: booking.id,
            status: BookingStatus.CANCELLED,
            refundAmount,
            refundMethod: isLargeRefund ? 'BANK_UPI' : 'WALLET',
        });
        if (isGroupBooking) {
            RealtimeEventBroker.emitToUser(userId, 'group_party_updated', 'group_party', booking.id, {
                partyId: booking.id,
                status: BookingStatus.CANCELLED,
                refundAmount,
                refundMethod: isLargeRefund ? 'BANK_UPI' : 'WALLET',
            });
        }

        try {
            const { VenueBookingService } = await import('./VenueBookingService');
            const enrichedCard = await VenueBookingService.enrichVenueBookingNotificationCard(booking.id, userId);
            if (enrichedCard) {
                RealtimeEventBroker.emitToUser(userId, 'notification_updated', 'notification', booking.id, enrichedCard);
            }
        } catch (_) {}

        try {
            const { GroupPartyService } = await import('./GroupPartyService');
            const enrichedCard = await GroupPartyService.enrichGroupPartyNotificationCard(booking.id, userId);
            if (enrichedCard) {
                RealtimeEventBroker.emitToUser(userId, 'notification_updated', 'notification', booking.id, enrichedCard);
            }
        } catch (_) {}

        return {
            success: true,
            message: refundAmount > 0
                ? (isLargeRefund
                    ? `${entityLabel} cancelled successfully. A refund of ₹${refundAmount} will be transferred to your provided payout account within 24-48 hours.`
                    : `${entityLabel} cancelled successfully. ₹${refundAmount} refunded to your Lunara Wallet.`)
                : `${entityLabel} cancelled successfully.`,
            booking,
            refundAmount,
            walletTransactionId: walletTxId,
            refundMethod: isLargeRefund ? 'BANK_UPI' : 'WALLET',
        };
    }

    /**
     * Preview cancellation details for Small Group Party (<= 20).
     */
    public static async getSmallGroupPartyCancellationPreview(
        partyId: string,
        userId: string
    ): Promise<CancellationPreviewResult> {
        // 1. Check GroupParty table
        const party = await GroupParty.findOne({
            where: { id: partyId, userId },
            include: [{ model: Venue, as: 'venue' }],
        });

        if (party) {
            if (party.status === GroupPartyStatus.CANCELLED) {
                throw new Error('Group party is already cancelled.');
            }

            const eventDateTime = parseBookingDateTime(party.partyDate as any, party.startTime);
            const validation = await this.validateCancellationTime(BookingPolicyType.GROUP_PARTY, eventDateTime);
            const paidAmount = party.paymentStatus === GroupPartyPaymentStatus.PAID ? Number(party.totalAmount || 0) : 0;
            const refundCalc = await this.calculateRefund(BookingPolicyType.GROUP_PARTY, paidAmount);

            const venueName = (party as any)?.venue?.name || 'Venue';
            const venueAddress = (party as any)?.venue?.addressLine1 || (party as any)?.venue?.city || '';
            const isLargeRefund = refundCalc.refundAmount > 1500;

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
                refundMethod: isLargeRefund ? 'UPI / Bank Transfer' : 'Lunara Wallet',
                requiresPayoutDetails: isLargeRefund,
            };
        }

        // 2. Fallback: Check Booking table (group party / with_friends reservation <= 20)
        const booking = await Booking.findOne({
            where: { id: partyId, userId },
            include: [{ model: Venue, as: 'venue' }],
        });

        if (booking) {
            if (booking.isLargePartyRequest || (booking.goingMode === GoingMode.PARTY_REQUEST && (booking.numberOfGuests || 1) > 20)) {
                throw new Error('This cancellation policy does not apply to Large Parties (>20 guests).');
            }

            if (booking.status === BookingStatus.CANCELLED) {
                throw new Error('Booking is already cancelled.');
            }

            const eventDateTime = parseBookingDateTime(booking.bookingDate as any, booking.startTime);
            const validation = await this.validateCancellationTime(BookingPolicyType.GROUP_PARTY, eventDateTime);
            const paidAmount = booking.paymentStatus === PaymentStatus.PAID ? Number(booking.totalAmount || 0) : 0;
            const refundCalc = await this.calculateRefund(BookingPolicyType.GROUP_PARTY, paidAmount);

            const venueName = (booking as any)?.venue?.name || 'Venue';
            const venueAddress = (booking as any)?.venue?.addressLine1 || (booking as any)?.venue?.city || '';
            const isLargeRefund = refundCalc.refundAmount > 1500;

            return {
                bookingId: booking.id,
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
                refundMethod: isLargeRefund ? 'UPI / Bank Transfer' : 'Lunara Wallet',
                requiresPayoutDetails: isLargeRefund,
            };
        }

        throw new Error('Group party not found');
    }

    /**
     * Atomically cancels Small Group Party (<= 20), invalidates tickets, and issues wallet refund (<= 1500) or saves payout details (> 1500).
     */
    public static async cancelAndRefundGroupParty(
        partyId: string,
        userId: string,
        cancellationReason?: string,
        payoutDetails?: RefundPayoutDetails
    ): Promise<{
        success: boolean;
        message: string;
        party: any;
        refundAmount: number;
        walletTransactionId?: string;
        refundMethod: string;
    }> {
        let party = await GroupParty.findOne({
            where: { id: partyId, userId },
            include: [{ model: Venue, as: 'venue' }],
        });

        if (!party) {
            // Fallback: check Booking table!
            const booking = await Booking.findOne({
                where: { id: partyId, userId },
                include: [{ model: Venue, as: 'venue' }],
            });

            if (booking) {
                const res = await this.cancelAndRefundSoloBooking(partyId, userId, cancellationReason, payoutDetails, true);
                return {
                    success: res.success,
                    message: res.message,
                    party: res.booking,
                    refundAmount: res.refundAmount,
                    walletTransactionId: res.walletTransactionId,
                    refundMethod: res.refundMethod,
                };
            }

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
        const isLargeRefund = refundAmount > 1500;

        if (wasPaid && isLargeRefund) {
            const hasUpiId = payoutDetails?.upiId && payoutDetails.upiId.trim().length > 0;
            const hasUpiNumber = payoutDetails?.upiNumber && payoutDetails.upiNumber.trim().length === 10;
            const hasBank = payoutDetails?.bankAccountNumber && payoutDetails.bankAccountNumber.trim().length > 0 &&
                            payoutDetails?.bankIfsc && payoutDetails.bankIfsc.trim().length > 0;
            if (!hasUpiId && !hasUpiNumber && !hasBank) {
                throw new Error('For refund amounts exceeding ₹1,500, please provide your UPI ID, UPI phone number, or Bank account details.');
            }
        }

        const t = await sequelize.transaction();
        let walletTxId: string | undefined;

        try {
            // Update party status and refund/payout details
            await party.update({
                status: GroupPartyStatus.CANCELLED,
                paymentStatus: (wasPaid && refundAmount > 0)
                    ? (isLargeRefund ? ('refund_processing' as any) : ((GroupPartyPaymentStatus as any).REFUNDED || GroupPartyPaymentStatus.FAILED))
                    : party.paymentStatus,
                cancellationReason: cancellationReason || 'Cancelled by user',
                cancelledAt: new Date(),
                refundMethod: isLargeRefund ? 'BANK_UPI' : 'WALLET',
                payoutType: isLargeRefund ? (payoutDetails?.payoutType || 'UPI_ID') : undefined,
                upiId: isLargeRefund ? payoutDetails?.upiId?.trim() : undefined,
                upiNumber: isLargeRefund ? payoutDetails?.upiNumber?.trim() : undefined,
                bankAccountNumber: isLargeRefund ? payoutDetails?.bankAccountNumber?.trim() : undefined,
                bankIfsc: isLargeRefund ? payoutDetails?.bankIfsc?.trim()?.toUpperCase() : undefined,
                bankHolderName: isLargeRefund ? payoutDetails?.bankHolderName?.trim() : undefined,
                refundAmount,
                refundStatus: (wasPaid && refundAmount > 0) ? (isLargeRefund ? 'PENDING_PAYOUT' : 'COMPLETED') : 'NONE',
            } as any, { transaction: t });

            // Invalidate tickets
            await Ticket.update(
                { ticketStatus: TicketStatus.CANCELLED, cancelledAt: new Date() },
                { where: { bookingId: party.id }, transaction: t }
            );

            // Release time locks
            await PlanEligibilityService.releaseLock(party.id);

            // Process Wallet Refund if eligible (<= ₹1500)
            if (wasPaid && refundAmount > 0 && !isLargeRefund) {
                const refundResult = await WalletService.refundToWallet({
                    userId,
                    amount: refundAmount,
                    bookingId: null,
                    partyPlanId: null,
                    reference: `REFUND_GP_${party.id.substring(0, 8).toUpperCase()}_${Date.now()}`,
                    reason: cancellationReason || 'GROUP PARTY CANCELLED',
                    metadata: {
                        originalAmountPaid: paidAmount,
                        refundPercentage: refundCalc.refundPercentage,
                        nonRefundableAmount: refundCalc.nonRefundableAmount,
                        refundAmount,
                        groupPartyId: party.id,
                        transactionLabel: 'GROUP PARTY CANCELLED',
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
        const notifBody = refundAmount > 0
            ? (isLargeRefund
                ? `Your Group Party at ${venueName} has been cancelled.\nAmount Paid: ₹${paidAmount}\nRefund Percentage: ${refundCalc.refundPercentage}%\nRefund Amount: ₹${refundAmount}\nA refund of ₹${refundAmount} will be transferred to your provided payout account within 24-48 hours.`
                : `Your Group Party at ${venueName} has been cancelled.\nAmount Paid: ₹${paidAmount}\nRefund Percentage: ${refundCalc.refundPercentage}%\nRefund Amount: ₹${refundAmount}\n₹${refundAmount} has been credited to your Lunara Wallet.`)
            : `Your Group Party at ${venueName} has been cancelled.`;

        // Dispatch notifications
        await NotificationService.dispatch({
            recipientUserId: userId,
            eventType: 'booking_cancelled',
            category: 'bookings',
            entityType: 'GroupParty',
            entityId: party.id,
            title: 'Group Party Cancelled',
            body: notifBody,
            priority: 'HIGH',
            idempotencyKey: `gp_cancel_${party.id}`,
            actionType: 'view_details',
            deepLink: `/group-parties`,
        }).catch(() => {});

        RealtimeEventBroker.emitToUser(userId, 'group_party_updated', 'group_party', party.id, {
            partyId: party.id,
            status: GroupPartyStatus.CANCELLED,
            refundAmount,
            refundMethod: isLargeRefund ? 'BANK_UPI' : 'WALLET',
        });

        try {
            const { GroupPartyService } = await import('./GroupPartyService');
            const enrichedCard = await GroupPartyService.enrichGroupPartyNotificationCard(party.id, userId);
            if (enrichedCard) {
                RealtimeEventBroker.emitToUser(userId, 'notification_updated', 'notification', party.id, enrichedCard);
            }
        } catch (_) {}

        return {
            success: true,
            message: refundAmount > 0
                ? (isLargeRefund
                    ? `Group party cancelled successfully. A refund of ₹${refundAmount} will be transferred to your provided payout account within 24-48 hours.`
                    : `Group party cancelled successfully. ₹${refundAmount} refunded to your Lunara Wallet.`)
                : 'Group party cancelled successfully.',
            party,
            refundAmount,
            walletTransactionId: walletTxId,
            refundMethod: isLargeRefund ? 'BANK_UPI' : 'WALLET',
        };
    }
}

export default BookingPolicyService;
