import sequelize from '../config/database';
import Booking, { BookingStatus, PaymentStatus } from '../models/Booking';
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
     * Phase 2, 3, 19, 22
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

        // Idempotency: Check if there is already an active pending request (Phase 19)
        const existingPending = await LargePartyCancellationRequest.findOne({
            where: {
                bookingId,
                status: [
                    LargePartyCancellationStatus.PENDING_ADMIN_REVIEW,
                    LargePartyCancellationStatus.REFUND_PROCESSING,
                    LargePartyCancellationStatus.APPROVED,
                    LargePartyCancellationStatus.COMPLETED,
                ],
            },
        });

        if (existingPending) {
            if (existingPending.status === LargePartyCancellationStatus.COMPLETED) {
                return {
                    success: false,
                    message: 'This Large Party has already been cancelled and refund processed',
                    data: existingPending,
                };
            }
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

        // Notify Admins & Host via Socket/Push (Phase 17)
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

                io.to(`user_${userId}`).emit('large_party_cancellation_requested', {
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
     * Phase 4, 21
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
     * Phase 5, 6
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
                    attributes: ['id', 'bookingDate', 'startTime', 'numberOfGuests', 'status', 'paymentStatus', 'partySubject', 'partyRequirement', 'partyDescription', 'totalAmount', 'razorpayOrderId'],
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
     * Phase 7, 8, 11, 12, 13, 18, 19
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

        let calculatedRefund = 0;
        let nonRefundable = 0;
        let finalStatus = LargePartyCancellationStatus.REFUND_PROCESSING;
        let bookingId = '';
        let hostUserId = '';
        let partySubject = 'Large Party';
        let venueName = 'Venue';
        let originalPaid = 0;
        let hostUser: any = null;

        // Atomic transaction execution with Row-Level Lock to prevent duplicate approvals (Phase 19)
        await sequelize.transaction(async (t) => {
            const cancelReq = await LargePartyCancellationRequest.findByPk(requestId, {
                transaction: t,
                lock: t.LOCK.UPDATE,
            });

            if (!cancelReq) {
                throw new Error('Large party cancellation request not found');
            }

            if (cancelReq.status !== LargePartyCancellationStatus.PENDING_ADMIN_REVIEW) {
                throw new Error(`Request is already in '${cancelReq.status}' status and cannot be approved again`);
            }

            const booking = await Booking.findByPk(cancelReq.bookingId, {
                include: [
                    { model: Venue, as: 'venue' },
                    { model: User, as: 'customer' },
                ],
                transaction: t,
            });
            if (!booking) {
                throw new Error('Associated booking not found');
            }

            const user = await User.findByPk(cancelReq.userId, { transaction: t });

            originalPaid = Number(cancelReq.originalPaidAmount || 0);
            calculatedRefund = Math.round((originalPaid * (refundPercentage / 100)) * 100) / 100;
            nonRefundable = Math.round((originalPaid - calculatedRefund) * 100) / 100;

            bookingId = booking.id;
            hostUserId = cancelReq.userId;
            hostUser = user;
            venueName = (booking as any)?.venue?.name || 'Venue';
            partySubject = booking.partySubject || `${venueName} Large Party`;

            finalStatus = refundMethod === LargePartyRefundMethod.WALLET || calculatedRefund === 0
                ? LargePartyCancellationStatus.COMPLETED
                : LargePartyCancellationStatus.REFUND_PROCESSING;

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
                    paymentReference: refundMethod === LargePartyRefundMethod.WALLET && calculatedRefund > 0 ? `WALLET_CREDIT_${booking.id.substring(0, 8)}` : undefined,
                    paidAt: refundMethod === LargePartyRefundMethod.WALLET ? new Date() : undefined,
                    paidByAdminId: refundMethod === LargePartyRefundMethod.WALLET ? adminUserId : undefined,
                },
                { transaction: t }
            );

            // Mark Booking as CANCELLED, but separately track payment status (Phase 12, 18)
            const targetPaymentStatus = refundMethod === LargePartyRefundMethod.WALLET || calculatedRefund === 0
                ? PaymentStatus.REFUNDED
                : PaymentStatus.PENDING;

            await booking.update(
                {
                    status: BookingStatus.CANCELLED,
                    paymentStatus: targetPaymentStatus,
                    cancellationReason: `Host Cancellation Approved by Admin (${refundPercentage}% refund): ${cancelReq.reason}`,
                },
                { transaction: t }
            );

            // Invalidate tickets so CANCELLED is never treated as ACTIVE / CONFIRMED (Phase 18)
            await Ticket.update(
                { ticketStatus: TicketStatus.CANCELLED },
                { where: { bookingId: booking.id }, transaction: t }
            );

            // Phase 13: If Wallet refund and amount > 0, credit host's wallet atomically with complete audit metadata
            if (refundMethod === LargePartyRefundMethod.WALLET && calculatedRefund > 0) {
                const idempotentRef = `LP_REFUND_${booking.id}_${cancelReq.id}`;
                const refundRes = await WalletService.creditRefund({
                    userId: hostUserId,
                    amount: calculatedRefund,
                    referenceId: idempotentRef,
                    reason: `Large Party Cancellation Refund`,
                    bookingId: booking.id,
                    transaction: t,
                });

                if (!refundRes.success) {
                    throw new Error(`Failed to credit host wallet`);
                }
            }
        });

        // Phase 11 & Phase 16: Socket & Push Notifications matching exact required copy
        try {
            const { io } = require('../server');
            const { sendPushNotification } = require('./fcmService');

            const notifTitle = 'Large Party Cancellation Approved';
            const notifBody = calculatedRefund > 0
                ? (refundMethod === LargePartyRefundMethod.WALLET
                    ? `Your cancellation request for ${partySubject} has been approved.\nOriginal Amount: ₹${originalPaid.toLocaleString('en-IN')}\nApproved Refund: ₹${calculatedRefund.toLocaleString('en-IN')}\nRefund Percentage: ${refundPercentage}%\n₹${calculatedRefund.toLocaleString('en-IN')} has been credited to your Lunara Wallet.`
                    : `Your cancellation request for ${partySubject} has been approved.\nOriginal Amount: ₹${originalPaid.toLocaleString('en-IN')}\nApproved Refund: ₹${calculatedRefund.toLocaleString('en-IN')}\nRefund Percentage: ${refundPercentage}%\nYour refund/payment will be processed within 24 hours.`)
                : `Your cancellation request for ${partySubject} has been approved.\nOriginal Amount: ₹${originalPaid.toLocaleString('en-IN')}\nRefund Percentage: 0%\nAs per policy, no refund applies.`;

            if (hostUser?.fcmToken) {
                await sendPushNotification(hostUser.fcmToken, {
                    title: notifTitle,
                    body: notifBody,
                    data: {
                        type: 'large_party_cancellation_approved',
                        bookingId,
                        requestId,
                        refundAmount: String(calculatedRefund),
                        refundPercentage: String(refundPercentage),
                    },
                });
            }

            if (io) {
                io.to(`user_${hostUserId}`).emit('large_party_cancellation_approved', {
                    bookingId,
                    requestId,
                    refundAmount: calculatedRefund,
                    refundPercentage,
                    refundMethod,
                    status: finalStatus,
                });

                io.to(`user_${hostUserId}`).emit('large_party_status_update', {
                    bookingId,
                    status: 'cancelled',
                    cancellationStatus: finalStatus,
                    cancellationRefundAmount: calculatedRefund,
                    cancellationRefundPercentage: refundPercentage,
                });

                io.to(`user_${hostUserId}`).emit('notification_created', {
                    id: `lp_cancel_${requestId}`,
                    title: notifTitle,
                    body: notifBody,
                    createdAt: new Date().toISOString(),
                    read: false,
                    data: {
                        type: 'large_party_cancellation_approved',
                        bookingId,
                        refundAmount: calculatedRefund,
                        refundPercentage,
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
                id: requestId,
                bookingId,
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
     * Phase 9, 11, 17, 20
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

        let bookingId = '';
        let hostUserId = '';
        let venueName = 'Venue';
        let hostUser: any = null;

        await sequelize.transaction(async (t) => {
            const cancelReq = await LargePartyCancellationRequest.findByPk(requestId, {
                transaction: t,
                lock: t.LOCK.UPDATE,
            });

            if (!cancelReq) {
                throw new Error('Large party cancellation request not found');
            }

            if (cancelReq.status !== LargePartyCancellationStatus.PENDING_ADMIN_REVIEW) {
                throw new Error(`Request is already in '${cancelReq.status}' status and cannot be rejected`);
            }

            const booking = await Booking.findByPk(cancelReq.bookingId, {
                include: [{ model: Venue, as: 'venue' }],
                transaction: t,
            });
            const user = await User.findByPk(cancelReq.userId, { transaction: t });

            bookingId = cancelReq.bookingId;
            hostUserId = cancelReq.userId;
            hostUser = user;
            venueName = (booking as any)?.venue?.name || 'Venue';

            // Update cancellation request to REJECTED. Large Party booking remains active/confirmed.
            await cancelReq.update(
                {
                    status: LargePartyCancellationStatus.REJECTED,
                    adminNotes: rejectionReason.trim(),
                    adminReviewedBy: adminUserId,
                    adminReviewedAt: new Date(),
                },
                { transaction: t }
            );
        });

        // Socket & Push Notifications
        try {
            const { io } = require('../server');
            const { sendPushNotification } = require('./fcmService');

            const notifTitle = 'Large Party Cancellation Not Approved';
            const notifBody = `Your cancellation request for Large Party at ${venueName} was not approved by Lunara Admin.\nReason: ${rejectionReason.trim()}\nYour Large Party remains active.`;

            if (hostUser?.fcmToken) {
                await sendPushNotification(hostUser.fcmToken, {
                    title: notifTitle,
                    body: notifBody,
                    data: {
                        type: 'large_party_cancellation_rejected',
                        bookingId,
                        requestId,
                        reason: rejectionReason.trim(),
                    },
                });
            }

            if (io) {
                io.to(`user_${hostUserId}`).emit('large_party_cancellation_rejected', {
                    bookingId,
                    requestId,
                    reason: rejectionReason.trim(),
                    status: LargePartyCancellationStatus.REJECTED,
                });

                io.to(`user_${hostUserId}`).emit('large_party_status_update', {
                    bookingId,
                    cancellationStatus: LargePartyCancellationStatus.REJECTED,
                    cancellationRejectionReason: rejectionReason.trim(),
                });

                io.to(`user_${hostUserId}`).emit('notification_created', {
                    id: `lp_cancel_rej_${requestId}`,
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
                id: requestId,
                bookingId,
                status: LargePartyCancellationStatus.REJECTED,
                rejectionReason: rejectionReason.trim(),
            },
        };
    }

    /**
     * Admin: Mark Manual Refund as Paid
     * Phase 14, 15, 16, 19
     */
    public static async adminMarkRefundPaid(params: {
        requestId: string;
        adminUserId: string;
        paymentReference: string;
        paymentNotes?: string;
        paymentMethod?: string;
    }): Promise<{ success: boolean; message: string; data?: any }> {
        const { requestId, adminUserId, paymentReference, paymentNotes, paymentMethod } = params;

        if (!paymentReference || paymentReference.trim().length === 0) {
            return { success: false, message: 'Payment reference / transaction ID is required' };
        }

        if (!adminUserId) {
            return { success: false, message: 'Admin authorization required' };
        }

        let bookingId = '';
        let hostUserId = '';
        let refundAmt = 0;
        let refundPct = 0;
        let originalPaid = 0;
        let hostUser: any = null;
        let methodDisplay = paymentMethod || 'Bank Transfer';

        // Atomic row-level lock transaction to prevent double payout settlement (Phase 15, 19)
        await sequelize.transaction(async (t) => {
            const cancelReq = await LargePartyCancellationRequest.findByPk(requestId, {
                transaction: t,
                lock: t.LOCK.UPDATE,
            });

            if (!cancelReq) {
                throw new Error('Large party cancellation request not found');
            }

            // Phase 15: Validate not already paid and state is eligible
            if (cancelReq.status === LargePartyCancellationStatus.COMPLETED && cancelReq.paidAt) {
                throw new Error('Refund has already been marked as paid and settled');
            }

            if (
                cancelReq.status !== LargePartyCancellationStatus.REFUND_PROCESSING &&
                cancelReq.status !== LargePartyCancellationStatus.APPROVED
            ) {
                throw new Error(`Request status is '${cancelReq.status}'. Only approved or processing refunds can be marked as paid.`);
            }

            refundAmt = Number(cancelReq.refundAmount || 0);
            if (refundAmt <= 0) {
                throw new Error('Refund amount must be greater than 0 to mark as paid');
            }

            const booking = await Booking.findByPk(cancelReq.bookingId, {
                include: [{ model: Venue, as: 'venue' }],
                transaction: t,
            });
            const user = await User.findByPk(cancelReq.userId, { transaction: t });

            bookingId = cancelReq.bookingId;
            hostUserId = cancelReq.userId;
            hostUser = user;
            refundPct = cancelReq.refundPercentage || 0;
            originalPaid = Number(cancelReq.originalPaidAmount || 0);

            if (cancelReq.upiId) {
                methodDisplay = 'UPI';
            } else if (cancelReq.accountNumber) {
                methodDisplay = 'Bank Transfer';
            }

            await cancelReq.update(
                {
                    status: LargePartyCancellationStatus.COMPLETED,
                    paymentReference: paymentReference.trim(),
                    paidByAdminId: adminUserId,
                    paidAt: new Date(),
                    adminNotes: paymentNotes?.trim() ? `${cancelReq.adminNotes ? cancelReq.adminNotes + ' | ' : ''}${paymentNotes.trim()}` : cancelReq.adminNotes,
                },
                { transaction: t }
            );

            // Mark booking payment status as refunded (Phase 12)
            if (booking) {
                await booking.update({ paymentStatus: PaymentStatus.REFUNDED }, { transaction: t });
            }
        });

        // Phase 16: Socket & Push Notifications matching exact required copy
        try {
            const { io } = require('../server');
            const { sendPushNotification } = require('./fcmService');

            const notifTitle = 'Large Party Refund Completed';
            const notifBody = `Your Large Party cancellation has been processed.\nOriginal Amount: ₹${originalPaid.toLocaleString('en-IN')}\nRefund Percentage: ${refundPct}%\nRefund Amount: ₹${refundAmt.toLocaleString('en-IN')}\nRefund Status: PAID\nPayment Method: ${methodDisplay}\nPayment Reference: ${paymentReference.trim()}\nThe amount has been paid successfully.`;

            if (hostUser?.fcmToken) {
                await sendPushNotification(hostUser.fcmToken, {
                    title: notifTitle,
                    body: notifBody,
                    data: {
                        type: 'large_party_refund_paid',
                        bookingId,
                        requestId,
                        paymentReference: paymentReference.trim(),
                        refundAmount: String(refundAmt),
                    },
                });
            }

            if (io) {
                io.to(`user_${hostUserId}`).emit('large_party_refund_paid', {
                    bookingId,
                    requestId,
                    refundAmount: refundAmt,
                    paymentReference: paymentReference.trim(),
                });

                io.to(`user_${hostUserId}`).emit('large_party_status_update', {
                    bookingId,
                    status: 'cancelled',
                    cancellationStatus: LargePartyCancellationStatus.COMPLETED,
                    cancellationRefundAmount: refundAmt,
                });

                io.to(`user_${hostUserId}`).emit('notification_created', {
                    id: `lp_refund_paid_${requestId}`,
                    title: notifTitle,
                    body: notifBody,
                    createdAt: new Date().toISOString(),
                    read: false,
                    data: {
                        type: 'large_party_refund_paid',
                        bookingId,
                        paymentReference: paymentReference.trim(),
                        refundAmount: refundAmt,
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
                id: requestId,
                bookingId,
                status: LargePartyCancellationStatus.COMPLETED,
                paymentReference: paymentReference.trim(),
            },
        };
    }
}
