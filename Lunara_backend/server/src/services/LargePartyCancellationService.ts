import sequelize from '../config/database';
import Booking, { BookingStatus } from '../models/Booking';
import User from '../models/User';
import Venue from '../models/Venue';
import Ticket, { TicketStatus } from '../models/Ticket';
import LargePartyCancellationRequest, {
    LargePartyCancellationStatus,
    LargePartyRefundMethod,
} from '../models/LargePartyCancellationRequest';
import { WalletService } from './walletService';
import { logger } from '../config/logger';

export interface MaskedPayoutDetails {
    upiId?: string;
    mobileNumber?: string;
    accountHolderName?: string;
    accountNumber?: string;
    ifscCode?: string;
}

export function maskPaymentDetails(details: MaskedPayoutDetails): MaskedPayoutDetails {
    const masked: MaskedPayoutDetails = {};

    if (details.upiId) {
        const parts = details.upiId.split('@');
        if (parts.length === 2) {
            const handle = parts[0];
            const psp = parts[1];
            const visibleLen = Math.min(2, handle.length);
            masked.upiId = `${handle.substring(0, visibleLen)}***@${psp}`;
        } else {
            masked.upiId = `${details.upiId.substring(0, 2)}***`;
        }
    }

    if (details.mobileNumber) {
        const clean = details.mobileNumber.trim();
        if (clean.length >= 4) {
            masked.mobileNumber = `******${clean.substring(clean.length - 4)}`;
        } else {
            masked.mobileNumber = '******';
        }
    }

    if (details.accountNumber) {
        const clean = details.accountNumber.trim();
        if (clean.length >= 4) {
            masked.accountNumber = `******${clean.substring(clean.length - 4)}`;
        } else {
            masked.accountNumber = '******';
        }
    }

    if (details.accountHolderName) {
        masked.accountHolderName = details.accountHolderName;
    }

    if (details.ifscCode) {
        masked.ifscCode = details.ifscCode.toUpperCase();
    }

    return masked;
}

export class LargePartyCancellationService {
    /**
     * Submit a Host Large Party Cancellation Request
     */
    public static async requestCancellation(params: {
        bookingId: string;
        userId: string;
        reason: string;
        reasonDetails?: string;
        upiId?: string;
        mobileNumber?: string;
        accountHolderName?: string;
        accountNumber?: string;
        ifscCode?: string;
    }): Promise<{ success: boolean; message: string; data?: any }> {
        const {
            bookingId,
            userId,
            reason,
            reasonDetails,
            upiId,
            mobileNumber,
            accountHolderName,
            accountNumber,
            ifscCode,
        } = params;

        if (!bookingId || !userId) {
            return { success: false, message: 'Booking ID and User ID are required' };
        }

        if (!reason || reason.trim().length === 0) {
            return { success: false, message: 'Cancellation reason is required' };
        }

        // Validate booking
        const booking = await Booking.findByPk(bookingId, {
            include: [
                { model: Venue, as: 'venue', attributes: ['id', 'name', 'city'] },
                { model: User, as: 'customer', attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'fcmToken'] },
            ],
        });

        if (!booking) {
            return { success: false, message: 'Booking not found' };
        }

        // Validate that this is a Large Party (>20)
        const isLargeParty = booking.isLargePartyRequest || (booking.numberOfGuests && booking.numberOfGuests > 20);
        if (!isLargeParty) {
            return { success: false, message: 'This cancellation workflow applies only to Large Party (>20) bookings' };
        }

        // Validate ownership
        if (String(booking.userId).trim() !== String(userId).trim()) {
            return { success: false, message: 'Unauthorized: You can only cancel your own Large Party booking' };
        }

        // Validate status
        const bStatus = (booking.status || '').toLowerCase();
        const pStatus = (booking.paymentStatus || '').toLowerCase();

        if (bStatus === 'cancelled') {
            return { success: false, message: 'This Large Party is already cancelled' };
        }
        if (bStatus === 'completed') {
            return { success: false, message: 'Completed Large Parties cannot be cancelled' };
        }

        if (pStatus !== 'paid' && bStatus !== 'confirmed') {
            return { success: false, message: 'Only confirmed and paid Large Parties can be submitted for cancellation' };
        }

        // Check if there is already an active pending request
        const existingPending = await LargePartyCancellationRequest.findOne({
            where: {
                bookingId,
                status: [
                    LargePartyCancellationStatus.PENDING_ADMIN_REVIEW,
                    LargePartyCancellationStatus.REFUND_PROCESSING,
                    LargePartyCancellationStatus.APPROVED,
                ],
            },
        });

        if (existingPending) {
            return {
                success: false,
                message: 'A cancellation request for this Large Party is already pending admin review',
                data: existingPending,
            };
        }

        // Authoritative paid amount from booking
        const originalPaidAmount = Number(booking.totalAmount || booking.adminPaymentAmount || 0);

        // Create cancellation request
        const cancellationRequest = await LargePartyCancellationRequest.create({
            bookingId: booking.id,
            userId: booking.userId,
            venueId: booking.venueId || undefined,
            originalPaidAmount,
            reason: reason.trim(),
            reasonDetails: reasonDetails?.trim() || undefined,
            upiId: upiId?.trim() || undefined,
            mobileNumber: mobileNumber?.trim() || undefined,
            accountHolderName: accountHolderName?.trim() || undefined,
            accountNumber: accountNumber?.trim() || undefined,
            ifscCode: ifscCode?.trim() || undefined,
            status: LargePartyCancellationStatus.PENDING_ADMIN_REVIEW,
        });

        // Notify Admins & Host via Socket/Push
        try {
            const { io } = require('../server');
            const venueName = (booking as any)?.venue?.name || 'Venue';
            const hostName = (booking as any)?.customer
                ? `${(booking as any).customer.firstName || ''} ${(booking as any).customer.lastName || ''}`.trim()
                : 'Host';

            if (io) {
                // Realtime broadcast to admin room
                io.to('admin_room').emit('large_party_cancellation_requested', {
                    requestId: cancellationRequest.id,
                    bookingId: booking.id,
                    hostName,
                    venueName,
                    amount: originalPaidAmount,
                    reason: cancellationRequest.reason,
                    requestedAt: cancellationRequest.createdAt,
                });

                // Realtime update to host
                io.to(`user_${userId}`).emit('large_party_status_update', {
                    bookingId: booking.id,
                    cancellationStatus: LargePartyCancellationStatus.PENDING_ADMIN_REVIEW,
                });
            }
        } catch (notifErr) {
            logger.warn('Failed to dispatch notifications for large party cancellation request:', notifErr);
        }

        return {
            success: true,
            message: 'Cancellation request submitted successfully. It will be reviewed by Lunara Admin.',
            data: {
                id: cancellationRequest.id,
                bookingId: cancellationRequest.bookingId,
                status: cancellationRequest.status,
                originalPaidAmount: cancellationRequest.originalPaidAmount,
                createdAt: cancellationRequest.createdAt,
            },
        };
    }

    /**
     * Admin: Get all cancellation requests with pagination and filters
     */
    public static async getAdminCancellations(params: {
        status?: LargePartyCancellationStatus;
        page?: number;
        limit?: number;
    }): Promise<{ success: boolean; data: any; pagination: any }> {
        const page = Math.max(1, Number(params.page) || 1);
        const limit = Math.max(1, Math.min(100, Number(params.limit) || 20));
        const offset = (page - 1) * limit;

        const where: any = {};
        if (params.status) {
            where.status = params.status;
        }

        const { count, rows } = await LargePartyCancellationRequest.findAndCountAll({
            where,
            include: [
                {
                    model: User,
                    as: 'user',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                },
                {
                    model: Venue,
                    as: 'venue',
                    attributes: ['id', 'name', 'addressLine1', 'city'],
                },
                {
                    model: Booking,
                    as: 'booking',
                    attributes: ['id', 'bookingDate', 'startTime', 'numberOfGuests', 'status', 'paymentStatus', 'partySubject', 'partyDescription', 'totalAmount'],
                },
            ],
            order: [['createdAt', 'DESC']],
            limit,
            offset,
        });

        const formatted = rows.map((r: any) => {
            const hostUser = r.user ? {
                id: r.user.id,
                fullName: `${r.user.firstName || ''} ${r.user.lastName || ''}`.trim() || 'Host',
                email: r.user.email,
                phone: r.user.phone,
                profileImageUrl: r.user.profileImageUrl,
            } : null;

            const maskedDetails = maskPaymentDetails({
                upiId: r.upiId,
                mobileNumber: r.mobileNumber,
                accountHolderName: r.accountHolderName,
                accountNumber: r.accountNumber,
                ifscCode: r.ifscCode,
            });

            return {
                id: r.id,
                bookingId: r.bookingId,
                host: hostUser,
                venue: r.venue,
                booking: r.booking,
                partySubject: r.booking?.partySubject || `${r.venue?.name || 'Venue'} Large Party`,
                scheduledDate: r.booking?.bookingDate,
                scheduledTime: r.booking?.startTime || '20:00',
                numberOfGuests: r.booking?.numberOfGuests || 0,
                originalPaidAmount: r.originalPaidAmount,
                refundPercentage: r.refundPercentage,
                refundAmount: r.refundAmount,
                nonRefundableAmount: r.nonRefundableAmount,
                refundMethod: r.refundMethod,
                reason: r.reason,
                reasonDetails: r.reasonDetails,
                payoutDetails: maskedDetails,
                status: r.status,
                adminNotes: r.adminNotes,
                paymentReference: r.paymentReference,
                requestedAt: r.createdAt,
                updatedAt: r.updatedAt,
            };
        });

        return {
            success: true,
            data: formatted,
            pagination: {
                total: count,
                page,
                limit,
                totalPages: Math.ceil(count / limit),
            },
        };
    }

    /**
     * Admin: Get detail of a specific cancellation request with precalculated refund policy previews
     */
    public static async getAdminCancellationDetail(requestId: string): Promise<{ success: boolean; message?: string; data?: any }> {
        const r = await LargePartyCancellationRequest.findByPk(requestId, {
            include: [
                {
                    model: User,
                    as: 'user',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl', 'walletBalance'],
                },
                {
                    model: Venue,
                    as: 'venue',
                    attributes: ['id', 'name', 'addressLine1', 'city'],
                },
                {
                    model: Booking,
                    as: 'booking',
                    attributes: ['id', 'bookingDate', 'startTime', 'numberOfGuests', 'status', 'paymentStatus', 'partySubject', 'partyRequirement', 'partyDescription', 'totalAmount'],
                },
                {
                    model: User,
                    as: 'adminReviewer',
                    attributes: ['id', 'firstName', 'lastName', 'email'],
                },
            ],
        });

        if (!r) {
            return { success: false, message: 'Large party cancellation request not found' };
        }

        const originalPaid = Number(r.originalPaidAmount || 0);

        // Precalculate standard refund policy previews (100%, 90%, 80%, 75%, 50%, 25%, 10%, 0%)
        const policyPercentages = [100, 90, 80, 75, 50, 25, 10, 0];
        const policyPreviews = policyPercentages.map((pct) => {
            const refundAmount = Math.round((originalPaid * (pct / 100)) * 100) / 100;
            const nonRefundable = Math.round((originalPaid - refundAmount) * 100) / 100;
            return {
                percentage: pct,
                label: pct === 100 ? 'Full Refund (100%)' : (pct === 0 ? 'No Refund (0%)' : `${pct}% Refund`),
                refundAmount,
                nonRefundableAmount: nonRefundable,
            };
        });

        const rawUser = (r as any).user;
        const hostUser = rawUser ? {
            id: rawUser.id,
            fullName: `${rawUser.firstName || ''} ${rawUser.lastName || ''}`.trim() || 'Host',
            email: rawUser.email,
            phone: rawUser.phone,
            profileImageUrl: rawUser.profileImageUrl,
            walletBalance: Number(rawUser.walletBalance || 0),
        } : null;

        return {
            success: true,
            data: {
                id: r.id,
                bookingId: r.bookingId,
                host: hostUser,
                venue: (r as any).venue,
                booking: (r as any).booking,
                partySubject: (r as any).booking?.partySubject || `${(r as any).venue?.name || 'Venue'} Large Party`,
                scheduledDate: (r as any).booking?.bookingDate,
                scheduledTime: (r as any).booking?.startTime || '20:00',
                numberOfGuests: (r as any).booking?.numberOfGuests || 0,
                originalPaidAmount: originalPaid,
                refundPercentage: r.refundPercentage,
                refundAmount: r.refundAmount,
                nonRefundableAmount: r.nonRefundableAmount,
                refundMethod: r.refundMethod,
                reason: r.reason,
                reasonDetails: r.reasonDetails,
                // Masked for safety, but admin also has access to raw values when executing payouts
                payoutDetails: {
                    upiId: r.upiId,
                    mobileNumber: r.mobileNumber,
                    accountHolderName: r.accountHolderName,
                    accountNumber: r.accountNumber,
                    ifscCode: r.ifscCode,
                    masked: maskPaymentDetails({
                        upiId: r.upiId,
                        mobileNumber: r.mobileNumber,
                        accountHolderName: r.accountHolderName,
                        accountNumber: r.accountNumber,
                        ifscCode: r.ifscCode,
                    }),
                },
                status: r.status,
                adminReviewer: r.adminReviewedBy ? (r as any).adminReviewer : null,
                adminReviewedAt: r.adminReviewedAt,
                adminNotes: r.adminNotes,
                paymentReference: r.paymentReference,
                paidAt: r.paidAt,
                policyPreviews,
                requestedAt: r.createdAt,
            },
        };
    }

    /**
     * Admin: Approve Large Party Cancellation with Chosen Policy
     */
    public static async adminApproveCancellation(params: {
        requestId: string;
        adminUserId: string;
        refundPercentage: number;
        refundMethod?: LargePartyRefundMethod;
        adminNotes?: string;
    }): Promise<{ success: boolean; message: string; data?: any }> {
        const { requestId, adminUserId, refundPercentage, adminNotes } = params;
        const refundMethod = params.refundMethod || LargePartyRefundMethod.WALLET;

        if (refundPercentage === undefined || isNaN(refundPercentage) || refundPercentage < 0 || refundPercentage > 100) {
            return { success: false, message: 'Valid refund percentage between 0 and 100 is required' };
        }

        const cancelReq = await LargePartyCancellationRequest.findByPk(requestId, {
            include: [
                { model: Booking, as: 'booking' },
                { model: User, as: 'user' },
                { model: Venue, as: 'venue' },
            ],
        });

        if (!cancelReq) {
            return { success: false, message: 'Large party cancellation request not found' };
        }

        if (cancelReq.status !== LargePartyCancellationStatus.PENDING_ADMIN_REVIEW) {
            return { success: false, message: `Request is already in '${cancelReq.status}' status and cannot be approved again` };
        }

        const originalPaid = Number(cancelReq.originalPaidAmount || 0);
        const calculatedRefund = Math.round((originalPaid * (refundPercentage / 100)) * 100) / 100;
        const nonRefundable = Math.round((originalPaid - calculatedRefund) * 100) / 100;

        const booking = (cancelReq as any).booking;
        if (!booking) {
            return { success: false, message: 'Associated booking not found' };
        }

        const hostUserId = cancelReq.userId;
        const finalStatus = refundMethod === LargePartyRefundMethod.WALLET || calculatedRefund === 0
            ? LargePartyCancellationStatus.COMPLETED
            : LargePartyCancellationStatus.REFUND_PROCESSING;

        // Atomic transaction execution
        await sequelize.transaction(async (t) => {
            // Update cancellation request
            await cancelReq.update(
                {
                    status: finalStatus,
                    refundPercentage,
                    refundAmount: calculatedRefund,
                    nonRefundableAmount: nonRefundable,
                    refundMethod,
                    adminReviewedBy: adminUserId,
                    adminReviewedAt: new Date(),
                    adminNotes: adminNotes?.trim() || undefined,
                    paidAt: refundMethod === LargePartyRefundMethod.WALLET ? new Date() : undefined,
                    paidByAdminId: refundMethod === LargePartyRefundMethod.WALLET ? adminUserId : undefined,
                },
                { transaction: t }
            );

            // Mark Booking as CANCELLED
            await booking.update(
                {
                    status: BookingStatus.CANCELLED,
                    cancellationReason: `Host Cancellation Approved by Admin (${refundPercentage}% refund): ${cancelReq.reason}`,
                },
                { transaction: t }
            );

            // Invalidate tickets
            await Ticket.update(
                { ticketStatus: TicketStatus.CANCELLED },
                { where: { bookingId: booking.id }, transaction: t }
            );

            // If Wallet refund and amount > 0, credit host's wallet atomically
            if (refundMethod === LargePartyRefundMethod.WALLET && calculatedRefund > 0) {
                const idempotentRef = `LP_REFUND_${booking.id}_${cancelReq.id}`;
                const refundRes = await WalletService.creditRefund({
                    userId: hostUserId,
                    amount: calculatedRefund,
                    referenceId: idempotentRef,
                    reason: `Large Party Cancellation Refund (${refundPercentage}%) for booking #${booking.id.substring(0, 8)}`,
                    transaction: t,
                });

                if (!refundRes.success) {
                    throw new Error(`Failed to credit host wallet`);
                }
            }
        });

        // Socket & Push Notifications
        try {
            const { io } = require('../server');
            const { sendPushNotification } = require('./fcmService');
            const venueName = (cancelReq as any)?.venue?.name || 'Venue';
            const hostUser = (cancelReq as any)?.user;

            const notifTitle = 'Large Party Cancellation Approved ✓';
            const notifBody = calculatedRefund > 0
                ? (refundMethod === LargePartyRefundMethod.WALLET
                    ? `Your Large Party at ${venueName} is cancelled. ₹${calculatedRefund} (${refundPercentage}%) has been credited to your Lunara Wallet.`
                    : `Your Large Party at ${venueName} is cancelled. A refund of ₹${calculatedRefund} (${refundPercentage}%) is being processed to your payout account.`)
                : `Your Large Party at ${venueName} is cancelled. As per policy, no refund applies.`;

            if (hostUser?.fcmToken) {
                await sendPushNotification(hostUser.fcmToken, {
                    title: notifTitle,
                    body: notifBody,
                    data: {
                        type: 'large_party_cancellation_approved',
                        bookingId: booking.id,
                        requestId: cancelReq.id,
                        refundAmount: String(calculatedRefund),
                    },
                });
            }

            if (io) {
                io.to(`user_${hostUserId}`).emit('large_party_cancellation_approved', {
                    bookingId: booking.id,
                    requestId: cancelReq.id,
                    refundAmount: calculatedRefund,
                    refundPercentage,
                    refundMethod,
                    status: finalStatus,
                });

                io.to(`user_${hostUserId}`).emit('large_party_status_update', {
                    bookingId: booking.id,
                    status: 'cancelled',
                    cancellationStatus: finalStatus,
                });

                io.to(`user_${hostUserId}`).emit('notification_created', {
                    id: `lp_cancel_${cancelReq.id}`,
                    title: notifTitle,
                    body: notifBody,
                    createdAt: new Date().toISOString(),
                    read: false,
                    data: {
                        type: 'large_party_cancellation_approved',
                        bookingId: booking.id,
                        refundAmount: calculatedRefund,
                    },
                });
            }
        } catch (pushErr) {
            logger.warn('Failed to send push/socket for large party approval:', pushErr);
        }

        return {
            success: true,
            message: `Large Party cancelled successfully with ${refundPercentage}% refund. Total refund: ₹${calculatedRefund}.`,
            data: {
                id: cancelReq.id,
                bookingId: booking.id,
                status: finalStatus,
                refundPercentage,
                refundAmount: calculatedRefund,
                nonRefundableAmount: nonRefundable,
                refundMethod,
            },
        };
    }

    /**
     * Admin: Reject Large Party Cancellation Request
     */
    public static async adminRejectCancellation(params: {
        requestId: string;
        adminUserId: string;
        rejectionReason: string;
    }): Promise<{ success: boolean; message: string; data?: any }> {
        const { requestId, adminUserId, rejectionReason } = params;

        if (!rejectionReason || rejectionReason.trim().length === 0) {
            return { success: false, message: 'Rejection reason is required' };
        }

        const cancelReq = await LargePartyCancellationRequest.findByPk(requestId, {
            include: [
                { model: Booking, as: 'booking' },
                { model: User, as: 'user' },
                { model: Venue, as: 'venue' },
            ],
        });

        if (!cancelReq) {
            return { success: false, message: 'Large party cancellation request not found' };
        }

        if (cancelReq.status !== LargePartyCancellationStatus.PENDING_ADMIN_REVIEW) {
            return { success: false, message: `Request is already in '${cancelReq.status}' status and cannot be rejected` };
        }

        // Update cancellation request to REJECTED. Large Party booking remains active/confirmed.
        await cancelReq.update({
            status: LargePartyCancellationStatus.REJECTED,
            adminNotes: rejectionReason.trim(),
            adminReviewedBy: adminUserId,
            adminReviewedAt: new Date(),
        });

        // Socket & Push Notifications
        try {
            const { io } = require('../server');
            const { sendPushNotification } = require('./fcmService');
            const venueName = (cancelReq as any)?.venue?.name || 'Venue';
            const hostUser = (cancelReq as any)?.user;
            const hostUserId = cancelReq.userId;
            const bookingId = cancelReq.bookingId;

            const notifTitle = 'Large Party Cancellation Not Approved';
            const notifBody = `Your cancellation request for Large Party at ${venueName} was not approved by Lunara Admin. Reason: ${rejectionReason.trim()}. Your Large Party remains active.`;

            if (hostUser?.fcmToken) {
                await sendPushNotification(hostUser.fcmToken, {
                    title: notifTitle,
                    body: notifBody,
                    data: {
                        type: 'large_party_cancellation_rejected',
                        bookingId,
                        requestId: cancelReq.id,
                        reason: rejectionReason.trim(),
                    },
                });
            }

            if (io) {
                io.to(`user_${hostUserId}`).emit('large_party_cancellation_rejected', {
                    bookingId,
                    requestId: cancelReq.id,
                    reason: rejectionReason.trim(),
                    status: LargePartyCancellationStatus.REJECTED,
                });

                io.to(`user_${hostUserId}`).emit('large_party_status_update', {
                    bookingId,
                    cancellationStatus: LargePartyCancellationStatus.REJECTED,
                });

                io.to(`user_${hostUserId}`).emit('notification_created', {
                    id: `lp_cancel_rej_${cancelReq.id}`,
                    title: notifTitle,
                    body: notifBody,
                    createdAt: new Date().toISOString(),
                    read: false,
                    data: {
                        type: 'large_party_cancellation_rejected',
                        bookingId,
                        reason: rejectionReason.trim(),
                    },
                });
            }
        } catch (pushErr) {
            logger.warn('Failed to send push/socket for large party rejection:', pushErr);
        }

        return {
            success: true,
            message: 'Cancellation request rejected successfully. Large Party remains active.',
            data: {
                id: cancelReq.id,
                bookingId: cancelReq.bookingId,
                status: LargePartyCancellationStatus.REJECTED,
                rejectionReason: rejectionReason.trim(),
            },
        };
    }

    /**
     * Admin: Mark Manual Refund as Paid
     */
    public static async adminMarkRefundPaid(params: {
        requestId: string;
        adminUserId: string;
        paymentReference: string;
        paymentNotes?: string;
    }): Promise<{ success: boolean; message: string; data?: any }> {
        const { requestId, adminUserId, paymentReference, paymentNotes } = params;

        if (!paymentReference || paymentReference.trim().length === 0) {
            return { success: false, message: 'Payment reference / transaction ID is required' };
        }

        const cancelReq = await LargePartyCancellationRequest.findByPk(requestId, {
            include: [
                { model: Booking, as: 'booking' },
                { model: User, as: 'user' },
                { model: Venue, as: 'venue' },
            ],
        });

        if (!cancelReq) {
            return { success: false, message: 'Large party cancellation request not found' };
        }

        if (cancelReq.status !== LargePartyCancellationStatus.REFUND_PROCESSING &&
            cancelReq.status !== LargePartyCancellationStatus.APPROVED) {
            return { success: false, message: `Request status is '${cancelReq.status}'. Only processing refunds can be marked as paid.` };
        }

        await cancelReq.update({
            status: LargePartyCancellationStatus.COMPLETED,
            paymentReference: paymentReference.trim(),
            paidByAdminId: adminUserId,
            paidAt: new Date(),
            adminNotes: paymentNotes?.trim() ? `${cancelReq.adminNotes ? cancelReq.adminNotes + ' | ' : ''}${paymentNotes.trim()}` : cancelReq.adminNotes,
        });

        // Socket & Push Notifications
        try {
            const { io } = require('../server');
            const { sendPushNotification } = require('./fcmService');
            const venueName = (cancelReq as any)?.venue?.name || 'Venue';
            const hostUser = (cancelReq as any)?.user;
            const hostUserId = cancelReq.userId;
            const refundAmt = cancelReq.refundAmount || 0;

            const notifTitle = 'Large Party Refund Transferred ✓';
            const notifBody = `Your refund of ₹${refundAmt} for Large Party at ${venueName} has been transferred. Reference: ${paymentReference.trim()}.`;

            if (hostUser?.fcmToken) {
                await sendPushNotification(hostUser.fcmToken, {
                    title: notifTitle,
                    body: notifBody,
                    data: {
                        type: 'large_party_refund_paid',
                        bookingId: cancelReq.bookingId,
                        requestId: cancelReq.id,
                        paymentReference: paymentReference.trim(),
                        refundAmount: String(refundAmt),
                    },
                });
            }

            if (io) {
                io.to(`user_${hostUserId}`).emit('large_party_refund_paid', {
                    bookingId: cancelReq.bookingId,
                    requestId: cancelReq.id,
                    refundAmount: refundAmt,
                    paymentReference: paymentReference.trim(),
                });

                io.to(`user_${hostUserId}`).emit('notification_created', {
                    id: `lp_refund_paid_${cancelReq.id}`,
                    title: notifTitle,
                    body: notifBody,
                    createdAt: new Date().toISOString(),
                    read: false,
                    data: {
                        type: 'large_party_refund_paid',
                        bookingId: cancelReq.bookingId,
                        paymentReference: paymentReference.trim(),
                    },
                });
            }
        } catch (pushErr) {
            logger.warn('Failed to send push/socket for large party refund paid:', pushErr);
        }

        return {
            success: true,
            message: 'Refund marked as paid successfully.',
            data: {
                id: cancelReq.id,
                bookingId: cancelReq.bookingId,
                status: LargePartyCancellationStatus.COMPLETED,
                paymentReference: paymentReference.trim(),
                paidAt: cancelReq.paidAt,
            },
        };
    }
}
