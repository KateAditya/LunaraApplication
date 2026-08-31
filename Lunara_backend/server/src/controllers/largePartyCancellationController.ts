import { Request, Response } from 'express';
import { LargePartyCancellationService } from '../services/LargePartyCancellationService';
import { LargePartyCancellationStatus, LargePartyRefundMethod } from '../models/LargePartyCancellationRequest';
import { logger } from '../config/logger';

export class LargePartyCancellationController {
    /**
     * Mobile: Host submits Large Party Cancellation Request
     * POST /api/mobile/bookings/:id/cancel-request
     * or POST /api/mobile/large-party/:id/cancel-request
     */
    public static async requestCancellation(req: Request, res: Response): Promise<Response> {
        try {
            const bookingId = req.params.id;
            const userId = (req as any).user?.id || (req as any).user?.userId || req.body?.userId;

            if (!userId) {
                return res.status(401).json({ success: false, message: 'Authentication required' });
            }

            const {
                reason,
                reasonDetails,
                upiId,
                mobileNumber,
                accountHolderName,
                accountNumber,
                ifscCode,
            } = req.body;

            const result = await LargePartyCancellationService.requestCancellation({
                bookingId,
                userId,
                reason,
                reasonDetails,
                upiId,
                mobileNumber,
                accountHolderName,
                accountNumber,
                ifscCode,
            });

            return res.status(result.success ? 200 : 400).json(result);
        } catch (err: any) {
            logger.error('[LargePartyCancellationController] requestCancellation error:', err);
            return res.status(500).json({ success: false, message: err?.message || 'Failed to submit cancellation request' });
        }
    }

    /**
     * Mobile: Get cancellation status for a Large Party
     * GET /api/mobile/bookings/:id/cancellation-status
     */
    public static async getCancellationStatus(req: Request, res: Response): Promise<Response> {
        try {
            const bookingId = req.params.id;
            const userId = (req as any).user?.id || (req as any).user?.userId;

            const LargePartyCancellationRequest = (await import('../models/LargePartyCancellationRequest')).default;
            const cancelReq = await LargePartyCancellationRequest.findOne({
                where: { bookingId },
                order: [['createdAt', 'DESC']],
            });

            if (!cancelReq) {
                return res.json({ success: true, hasCancellation: false });
            }

            // Check if user is host
            if (userId && String(cancelReq.userId).trim() !== String(userId).trim()) {
                return res.status(403).json({ success: false, message: 'Unauthorized' });
            }

            return res.json({
                success: true,
                hasCancellation: true,
                data: {
                    id: cancelReq.id,
                    bookingId: cancelReq.bookingId,
                    status: cancelReq.status,
                    reason: cancelReq.reason,
                    originalPaidAmount: cancelReq.originalPaidAmount,
                    refundPercentage: cancelReq.refundPercentage,
                    refundAmount: cancelReq.refundAmount,
                    refundMethod: cancelReq.refundMethod,
                    adminNotes: cancelReq.adminNotes,
                    requestedAt: cancelReq.createdAt,
                },
            });
        } catch (err: any) {
            logger.error('[LargePartyCancellationController] getCancellationStatus error:', err);
            return res.status(500).json({ success: false, message: err?.message || 'Failed to get cancellation status' });
        }
    }

    /**
     * Admin: List all Large Party Cancellation Requests
     * GET /api/admin/large-party/cancellations
     */
    public static async getAdminCancellations(req: Request, res: Response): Promise<Response> {
        try {
            const { status, page, limit } = req.query;
            const result = await LargePartyCancellationService.getAdminCancellations({
                status: status as LargePartyCancellationStatus,
                page: page ? Number(page) : undefined,
                limit: limit ? Number(limit) : undefined,
            });

            return res.json(result);
        } catch (err: any) {
            logger.error('[LargePartyCancellationController] getAdminCancellations error:', err);
            return res.status(500).json({ success: false, message: err?.message || 'Failed to list cancellations' });
        }
    }

    /**
     * Admin: Get Large Party Cancellation Detail
     * GET /api/admin/large-party/cancellations/:id
     */
    public static async getAdminCancellationDetail(req: Request, res: Response): Promise<Response> {
        try {
            const { id } = req.params;
            const result = await LargePartyCancellationService.getAdminCancellationDetail(id);

            return res.status(result.success ? 200 : 404).json(result);
        } catch (err: any) {
            logger.error('[LargePartyCancellationController] getAdminCancellationDetail error:', err);
            return res.status(500).json({ success: false, message: err?.message || 'Failed to get cancellation details' });
        }
    }

    /**
     * Admin: Approve Large Party Cancellation with chosen refund percentage & method
     * POST /api/admin/large-party/cancellations/:id/approve
     */
    public static async adminApproveCancellation(req: Request, res: Response): Promise<Response> {
        try {
            const { id } = req.params;
            const adminUserId = (req as any).user?.id || (req as any).user?.userId || 'admin';
            const { refundPercentage, refundMethod, adminNotes } = req.body;

            const result = await LargePartyCancellationService.adminApproveCancellation({
                requestId: id,
                adminUserId,
                refundPercentage: Number(refundPercentage),
                refundMethod: refundMethod as LargePartyRefundMethod,
                adminNotes,
            });

            return res.status(result.success ? 200 : 400).json(result);
        } catch (err: any) {
            logger.error('[LargePartyCancellationController] adminApproveCancellation error:', err);
            return res.status(500).json({ success: false, message: err?.message || 'Failed to approve cancellation' });
        }
    }

    /**
     * Admin: Reject Large Party Cancellation
     * POST /api/admin/large-party/cancellations/:id/reject
     */
    public static async adminRejectCancellation(req: Request, res: Response): Promise<Response> {
        try {
            const { id } = req.params;
            const adminUserId = (req as any).user?.id || (req as any).user?.userId || 'admin';
            const { rejectionReason } = req.body;

            const result = await LargePartyCancellationService.adminRejectCancellation({
                requestId: id,
                adminUserId,
                rejectionReason,
            });

            return res.status(result.success ? 200 : 400).json(result);
        } catch (err: any) {
            logger.error('[LargePartyCancellationController] adminRejectCancellation error:', err);
            return res.status(500).json({ success: false, message: err?.message || 'Failed to reject cancellation' });
        }
    }

    /**
     * Admin: Mark Manual Refund as Paid
     * POST /api/admin/large-party/cancellations/:id/mark-paid
     */
    public static async adminMarkRefundPaid(req: Request, res: Response): Promise<Response> {
        try {
            const { id } = req.params;
            const adminUserId = (req as any).user?.id || (req as any).user?.userId || 'admin';
            const { paymentReference, paymentNotes } = req.body;

            const result = await LargePartyCancellationService.adminMarkRefundPaid({
                requestId: id,
                adminUserId,
                paymentReference,
                paymentNotes,
            });

            return res.status(result.success ? 200 : 400).json(result);
        } catch (err: any) {
            logger.error('[LargePartyCancellationController] adminMarkRefundPaid error:', err);
            return res.status(500).json({ success: false, message: err?.message || 'Failed to mark refund as paid' });
        }
    }
}

export default LargePartyCancellationController;
