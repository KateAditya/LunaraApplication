import { Request, Response } from 'express';
import NightPartnerService from '../services/NightPartnerService';
import NightPartnerRequest from '../models/NightPartnerRequest';
import NightPartnerMatch from '../models/NightPartnerMatch';
import Booking from '../models/Booking';
import Venue from '../models/Venue';
import User from '../models/User';
import { logger } from '../config/logger';

export const checkUserInterest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { venueId, eventDate } = req.query;
        const userId = req.user!.id;
        if (!venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'venueId and eventDate are required' });
            return;
        }

        const isInterested = await NightPartnerService.checkUserInterest(
            userId,
            String(venueId),
            String(eventDate)
        );
        res.json({ success: true, isInterested });
    } catch (err: any) {
        logger.error('checkUserInterest error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to check interest' });
    }
};

export const markInterested = async (req: Request, res: Response): Promise<void> => {
    try {
        const { venueId, eventDate, eventTime } = req.body;
        const userId = req.user!.id;
        if (!venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'venueId and eventDate are required' });
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
        const { venueId, eventDate } = req.body;
        const userId = req.user!.id;
        if (!venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'venueId and eventDate are required' });
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
        const { venueId, eventDate } = req.query;
        const hostId = req.user!.id;
        if (!venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'venueId and eventDate query parameters are required' });
            return;
        }

        const partners = await NightPartnerService.getInterestedPartners(
            hostId,
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
        const { venueId, eventDate, search } = req.query;
        const hostId = req.user!.id;
        if (!venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'venueId and eventDate query parameters are required' });
            return;
        }

        const invitees = await NightPartnerService.getAvailableInvitees(
            hostId,
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

export const initiateInviteOrder = async (req: Request, res: Response): Promise<void> => {
    try {
        const { venueId, eventDate, eventTime, paymentMode, ticketPrice, partnerId, partnerIds } = req.body;
        const hostId = req.user!.id;
        if (!venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'venueId and eventDate are required' });
            return;
        }

        const resolvedPartnerIds = Array.isArray(partnerIds) && partnerIds.length > 0
            ? partnerIds
            : (partnerId ? [partnerId] : []);

        const parsedTicketPrice = ticketPrice ? Number(ticketPrice) : undefined;
        const orderData = await NightPartnerService.initiateInviteOrder(
            hostId,
            String(venueId),
            String(eventDate),
            paymentMode === 'SPLIT' ? 'SPLIT' : 'SELF_PAY',
            parsedTicketPrice,
            resolvedPartnerIds,
            eventTime ? String(eventTime) : undefined
        );
        res.json({
            success: true,
            ...orderData,
        });
    } catch (err: any) {
        logger.error('initiateInviteOrder error:', err);
        const code = err.code || (err.timeLock ? 'FOUR_HOUR_TIME_LOCK' : undefined);
        res.status(400).json({
            success: false,
            code,
            reason: code,
            message: err.message || 'Failed to initiate invite payment',
            ...(err.timeLock || {}),
        });
    }
};

export const verifyInvitePaymentAndSend = async (req: Request, res: Response): Promise<void> => {
    try {
        const {
            partnerId,
            partnerIds,
            venueId,
            eventDate,
            eventTime,
            paymentMode,
            razorpay_order_id,
            razorpay_payment_id,
            razorpay_signature,
            razorpayOrderId,
            razorpayPaymentId,
            razorpaySignature,
            paymentMethod,
        } = req.body;
        const hostId = req.user!.id;

        const resolvedPartnerIds = Array.isArray(partnerIds) && partnerIds.length > 0
            ? partnerIds
            : (partnerId ? [partnerId] : []);

        if (resolvedPartnerIds.length === 0 || !venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'partnerId (or partnerIds), venueId, and eventDate are required' });
            return;
        }

        const effectiveOrderId = razorpayOrderId || razorpay_order_id;
        const effectivePaymentId = razorpayPaymentId || razorpay_payment_id;
        const effectiveSignature = razorpaySignature || razorpay_signature;

        const isWallet = paymentMethod?.toString().toLowerCase().includes('wallet');
        if (!isWallet && (!effectiveOrderId || !effectivePaymentId || !effectiveSignature)) {
            res.status(400).json({ success: false, message: 'Payment verification parameters are required' });
            return;
        }

        const partnerRequest = await NightPartnerService.verifyInvitePaymentAndSend({
            hostId,
            partnerId: resolvedPartnerIds[0],
            partnerIds: resolvedPartnerIds,
            venueId,
            eventDate,
            eventTime,
            paymentMode: paymentMode === 'SPLIT' ? 'SPLIT' : 'SELF_PAY',
            razorpayOrderId: effectiveOrderId || 'wallet_payment',
            razorpayPaymentId: effectivePaymentId || 'wallet_payment',
            razorpaySignature: effectiveSignature || 'mock_signature',
            paymentMethod: isWallet ? 'wallet' : 'razorpay',
        });

        res.status(201).json({
            success: true,
            message: 'Payment verified and invitation sent successfully! 🎉',
            data: partnerRequest,
        });
    } catch (err: any) {
        logger.error('verifyInvitePaymentAndSend error:', err);
        const code = err.code || (err.timeLock ? 'FOUR_HOUR_TIME_LOCK' : undefined);
        res.status(400).json({
            success: false,
            code,
            reason: code,
            message: err.message || 'Failed to verify payment and send invitation',
            ...(err.timeLock || {}),
        });
    }
};

export const sendPartnerRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { partnerId, venueId, eventDate, eventTime, paymentMode } = req.body;
        const hostId = req.user!.id;
        if (!partnerId || !venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'partnerId, venueId, and eventDate are required' });
            return;
        }

        const partnerRequest = await NightPartnerService.sendPartnerRequest(
            hostId,
            partnerId,
            venueId,
            eventDate,
            eventTime,
            paymentMode === 'SPLIT' ? 'SPLIT' : 'SELF_PAY'
        );
        res.status(201).json({ success: true, message: 'Partner request sent successfully', data: partnerRequest });
    } catch (err: any) {
        logger.error('sendPartnerRequest error:', err);
        const code = err.code || (err.timeLock ? 'FOUR_HOUR_TIME_LOCK' : undefined);
        res.status(400).json({
            success: false,
            code,
            reason: code,
            message: err.message || 'Failed to send partner request',
            ...(err.timeLock || {}),
        });
    }
};

export const respondToRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        let { id } = req.params;
        const cleanId = NightPartnerService.cleanEntityId(id);
        const action = (req.body.action || '').toString().toLowerCase();
        const partnerId = req.user!.id;
        if (!cleanId || !['accept', 'decline'].includes(action)) {
            res.status(400).json({ success: false, message: 'requestId and valid action (accept/decline) are required' });
            return;
        }

        const result = await NightPartnerService.respondToRequest(cleanId, partnerId, action as 'accept' | 'decline');
        res.json({ success: true, message: `Request ${action}ed successfully`, data: result });
    } catch (err: any) {
        logger.error('respondToRequest error:', err);
        const code = err.code || (err.timeLock ? 'FOUR_HOUR_TIME_LOCK' : undefined);
        const isSlotFilled = err.message === 'MATCH_SLOT_FILLED';
        const isExpired = err.message === 'REQUEST_EXPIRED';
        const isNotFound = err.message === 'REQUEST_NOT_FOUND' || err.message === 'REQUEST_ALREADY_PROCESSED';
        let userMessage = err.message || 'Failed to process request response';
        if (isSlotFilled) {
            userMessage = 'This invitation is no longer available as the host is already matched with another guest.';
        } else if (isExpired) {
            userMessage = 'This invitation has expired.';
        } else if (isNotFound) {
            userMessage = 'This invitation is no longer available.';
        }
        res.status(400).json({
            success: false,
            code: code || err.message,
            reason: code || err.message,
            notAvailable: isSlotFilled || isExpired || isNotFound,
            message: userMessage,
            ...(err.timeLock || {}),
        });
    }
};

export const getRequestById = async (req: Request, res: Response): Promise<void> => {
    try {
        let { id } = req.params;
        const cleanId = NightPartnerService.cleanEntityId(id);
        if (!cleanId) {
            res.status(400).json({ success: false, message: 'requestId is required' });
            return;
        }

        const request = await NightPartnerRequest.findByPk(cleanId, {
            include: [
                { model: Venue, as: 'venue' },
                { model: User, as: 'host', attributes: ['id', 'firstName', 'lastName'] },
                { model: User, as: 'partner', attributes: ['id', 'firstName', 'lastName'] },
            ]
        });
        if (request) {
            res.json({ success: true, data: request });
            return;
        }

        const match = await NightPartnerMatch.findByPk(cleanId, {
            include: [{ model: Venue, as: 'venue' }]
        });
        if (match) {
            res.json({ success: true, data: match });
            return;
        }

        const booking = await Booking.findByPk(cleanId, {
            include: [{ model: Venue, as: 'venue' }]
        });
        if (booking) {
            res.json({ success: true, data: booking });
            return;
        }

        res.status(404).json({ success: false, message: 'Request not found' });
    } catch (err: any) {
        logger.error('getRequestById error:', err);
        res.status(500).json({ success: false, message: err.message || 'Internal server error' });
    }
};

export const cancelRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        let { id } = req.params;
        const cleanId = NightPartnerService.cleanEntityId(id);
        const hostId = req.user!.id;
        if (!cleanId) {
            res.status(400).json({ success: false, message: 'requestId is required' });
            return;
        }

        await NightPartnerService.cancelRequest(cleanId, hostId);
        res.json({ success: true, message: 'Request cancelled successfully' });
    } catch (err: any) {
        logger.error('cancelRequest error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to cancel request' });
    }
};

export const initiateMatchPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        let { id } = req.params;
        const cleanId = NightPartnerService.cleanEntityId(id);
        const { paymentMode } = req.body;
        const hostId = req.user!.id;
        if (!cleanId) {
            res.status(400).json({ success: false, message: 'matchId is required' });
            return;
        }

        const { match, razorpayOrder, amountToPay } = await NightPartnerService.initiateMatchPayment(
            cleanId,
            hostId,
            paymentMode === 'SPLIT' ? 'SPLIT' : 'SELF_PAY'
        );
        res.json({
            success: true,
            data: match,
            razorpayOrderId: razorpayOrder.id,
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
            amount: razorpayOrder.amount,
            amountToPay,
            currency: razorpayOrder.currency,
        });
    } catch (err: any) {
        logger.error('initiateMatchPayment error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to initiate payment' });
    }
};

export const verifyMatchPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        let { id } = req.params;
        const cleanId = NightPartnerService.cleanEntityId(id);
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature, paymentMethod } = req.body;
        const isWallet = paymentMethod?.toString().toLowerCase().includes('wallet');

        if (!isWallet && (!cleanId || !razorpay_order_id || !razorpay_payment_id || !razorpay_signature)) {
            res.status(400).json({ success: false, message: 'matchId and all Razorpay verification params are required' });
            return;
        }

        const result = await NightPartnerService.verifyMatchPayment(
            cleanId,
            razorpay_order_id || 'wallet_payment',
            razorpay_payment_id || 'wallet_payment',
            razorpay_signature || 'mock_signature',
            req.user!.id,
            isWallet ? 'wallet' : 'razorpay'
        );

        res.json({
            success: true,
            message: result.isFullyPaid
                ? 'Payment verified and booking confirmed! Chat is unlocked.'
                : 'Payment processed! Waiting for partner payment.',
            data: result,
        });
    } catch (err: any) {
        logger.error('verifyMatchPayment error:', err);
        res.status(err.statusCode || 400).json({ success: false, message: err.message || 'Failed to verify payment' });
    }
};

export const cancelUpcomingNight = async (req: Request, res: Response): Promise<void> => {
    try {
        let { id } = req.params;
        const cleanId = NightPartnerService.cleanEntityId(id);
        const { reason, action } = req.body;
        const userId = req.user!.id;
        if (!cleanId) {
            res.status(400).json({ success: false, message: 'id is required' });
            return;
        }

        const result = await NightPartnerService.cancelUpcomingNight(cleanId, userId, reason, action);
        res.json(result);
    } catch (err: any) {
        logger.error('cancelUpcomingNight error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to cancel upcoming night' });
    }
};

export const getEventPosts = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = req.user?.id;
        const eventPosts = await NightPartnerService.getEventPosts(userId);
        res.json({ success: true, data: eventPosts });
    } catch (err: any) {
        logger.error('getEventPosts error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to fetch event posts' });
    }
};

export default {
    checkUserInterest,
    markInterested,
    removeInterest,
    getInterestedPartners,
    getAvailableInvitees,
    getPartnerProfilePreview,
    initiateInviteOrder,
    verifyInvitePaymentAndSend,
    sendPartnerRequest,
    respondToRequest,
    getRequestById,
    cancelRequest,
    initiateMatchPayment,
    verifyMatchPayment,
    cancelUpcomingNight,
    getEventPosts,
};
