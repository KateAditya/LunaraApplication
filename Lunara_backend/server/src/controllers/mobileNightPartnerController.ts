import { Request, Response } from 'express';
import { NightPartnerService } from '../services/NightPartnerService';
import { logger } from '../config/logger';

export const markInterested = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId, venueId, eventDate, eventTime } = req.body;
        if (!userId || !venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'userId, venueId, and eventDate are required' });
            return;
        }

        const interest = await NightPartnerService.markInterested(userId, venueId, eventDate, eventTime);
        res.json({ success: true, message: 'Marked as interested', data: interest });
    } catch (err: any) {
        logger.error('markInterested error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to mark interest' });
    }
};

export const removeInterest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId, venueId, eventDate } = req.body;
        if (!userId || !venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'userId, venueId, and eventDate are required' });
            return;
        }

        await NightPartnerService.removeInterest(userId, venueId, eventDate);
        res.json({ success: true, message: 'Interest removed successfully' });
    } catch (err: any) {
        logger.error('removeInterest error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to remove interest' });
    }
};

export const getInterestedPartners = async (req: Request, res: Response): Promise<void> => {
    try {
        const { hostId, venueId, eventDate } = req.query;
        if (!hostId || !venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'hostId, venueId, and eventDate query parameters are required' });
            return;
        }

        const partners = await NightPartnerService.getInterestedPartners(
            String(hostId),
            String(venueId),
            String(eventDate)
        );
        res.json({ success: true, data: partners });
    } catch (err: any) {
        logger.error('getInterestedPartners error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to fetch interested partners' });
    }
};

export const getAvailableInvitees = async (req: Request, res: Response): Promise<void> => {
    try {
        const { hostId, venueId, eventDate, search } = req.query;
        if (!hostId || !venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'hostId, venueId, and eventDate query parameters are required' });
            return;
        }

        const invitees = await NightPartnerService.getAvailableInvitees(
            String(hostId),
            String(venueId),
            String(eventDate),
            search ? String(search) : undefined
        );
        res.json({ success: true, data: invitees });
    } catch (err: any) {
        logger.error('getAvailableInvitees error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to fetch available invitees' });
    }
};

export const getPartnerProfilePreview = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;
        if (!userId) {
            res.status(400).json({ success: false, message: 'userId parameter is required' });
            return;
        }

        const profile = await NightPartnerService.getPartnerProfilePreview(userId);
        res.json({ success: true, data: profile });
    } catch (err: any) {
        logger.error('getPartnerProfilePreview error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to fetch partner profile preview' });
    }
};

export const sendPartnerRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { hostId, partnerId, venueId, eventDate, eventTime } = req.body;
        if (!hostId || !partnerId || !venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'hostId, partnerId, venueId, and eventDate are required' });
            return;
        }

        const partnerRequest = await NightPartnerService.sendPartnerRequest(
            hostId,
            partnerId,
            venueId,
            eventDate,
            eventTime
        );
        res.status(201).json({ success: true, message: 'Partner request sent successfully', data: partnerRequest });
    } catch (err: any) {
        logger.error('sendPartnerRequest error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to send partner request' });
    }
};

export const respondToRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { partnerId, action } = req.body;
        if (!id || !partnerId || !['accept', 'decline'].includes(action)) {
            res.status(400).json({ success: false, message: 'requestId, partnerId, and valid action (accept/decline) are required' });
            return;
        }

        const result = await NightPartnerService.respondToRequest(id, partnerId, action);
        res.json({ success: true, message: `Request ${action}ed successfully`, data: result });
    } catch (err: any) {
        logger.error('respondToRequest error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to process request response' });
    }
};

export const cancelRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { hostId } = req.body;
        if (!id || !hostId) {
            res.status(400).json({ success: false, message: 'requestId and hostId are required' });
            return;
        }

        await NightPartnerService.cancelRequest(id, hostId);
        res.json({ success: true, message: 'Request cancelled successfully' });
    } catch (err: any) {
        logger.error('cancelRequest error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to cancel request' });
    }
};

export const initiateMatchPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { hostId } = req.body;
        if (!id || !hostId) {
            res.status(400).json({ success: false, message: 'matchId and hostId are required' });
            return;
        }

        const { match, razorpayOrder } = await NightPartnerService.initiateMatchPayment(id, hostId);
        res.json({
            success: true,
            data: match,
            razorpayOrderId: razorpayOrder.id,
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
            amount: razorpayOrder.amount,
            currency: razorpayOrder.currency,
        });
    } catch (err: any) {
        logger.error('initiateMatchPayment error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to initiate payment' });
    }
};

export const verifyMatchPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        if (!id || !razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
            res.status(400).json({ success: false, message: 'matchId and all Razorpay verification params are required' });
            return;
        }

        const result = await NightPartnerService.verifyMatchPayment(
            id,
            razorpay_order_id,
            razorpay_payment_id,
            razorpay_signature
        );

        res.json({
            success: true,
            message: 'Payment verified and booking confirmed! Chat is unlocked.',
            data: result,
        });
    } catch (err: any) {
        logger.error('verifyMatchPayment error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to verify payment' });
    }
};

export default {
    markInterested,
    removeInterest,
    getInterestedPartners,
    getAvailableInvitees,
    getPartnerProfilePreview,
    sendPartnerRequest,
    respondToRequest,
    cancelRequest,
    initiateMatchPayment,
    verifyMatchPayment,
};
