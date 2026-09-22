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
        const venueId = req.query?.venueId || req.body?.venueId;
        const eventDate = req.query?.eventDate || req.body?.eventDate;
        const userId = req.user?.id || req.query?.userId || req.body?.userId;
        if (!userId) {
            res.status(401).json({ success: false, message: 'Unauthorized' });
            return;
        }
        if (!venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'venueId and eventDate are required' });
            return;
        }

        const isInterested = await NightPartnerService.checkUserInterest(
            String(userId),
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
        const venueId = req.body?.venueId || req.query?.venueId;
        const eventDate = req.body?.eventDate || req.query?.eventDate;
        const eventTime = req.body?.eventTime || req.query?.eventTime;
        const userId = req.user?.id || req.body?.userId || req.query?.userId;
        if (!userId) {
            res.status(401).json({ success: false, message: 'Unauthorized' });
            return;
        }
        if (!venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'venueId and eventDate are required' });
            return;
        }

        const interest = await NightPartnerService.markInterested(
            String(userId),
            String(venueId),
            String(eventDate),
            eventTime ? String(eventTime) : undefined
        );
        res.json({ success: true, message: 'Marked as interested', data: interest });
    } catch (err: any) {
        logger.error('markInterested error:', err);
        res.status(400).json({ success: false, message: err.message || 'Failed to mark interest' });
    }
};

export const removeInterest = async (req: Request, res: Response): Promise<void> => {
    try {
        const venueId = req.body?.venueId || req.query?.venueId;
        const eventDate = req.body?.eventDate || req.query?.eventDate;
        const userId = req.user?.id || req.body?.userId || req.query?.userId;
        if (!userId) {
            res.status(401).json({ success: false, message: 'Unauthorized' });
            return;
        }
        if (!venueId || !eventDate) {
            res.status(400).json({ success: false, message: 'venueId and eventDate are required' });
            return;
        }

        await NightPartnerService.removeInterest(String(userId), String(venueId), String(eventDate));
        res.json({ success: true, message: 'Interest removed successfully' });
    } catch (err: any) {
        logger.error('removeInterest error:', err);
        const isMatchedErr = err?.message === 'MATCHED_USER_CANNOT_REMOVE_INTEREST';
        const msg = isMatchedErr
            ? 'You have an active partner match for this night. Please cancel your match first before removing interest.'
            : (err.message || 'Failed to remove interest');
        res.status(400).json({
            success: false,
            message: msg,
            code: isMatchedErr ? 'MATCHED_USER_CANNOT_REMOVE_INTEREST' : 'REMOVE_INTEREST_FAILED',
        });
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
        // Optional event context. The live feed groups a night by venue + date,
        // so the id it can offer is not always the request's own; when it isn't,
        // this lets the service find the partner's pending invite for that night
        // instead of rejecting an otherwise valid Accept.
        const { venueId, eventDate, hostId } = req.body || {};
        if ((!cleanId && !venueId) || !['accept', 'decline'].includes(action)) {
            res.status(400).json({ success: false, message: 'requestId and valid action (accept/decline) are required' });
            return;
        }

        const result = await NightPartnerService.respondToRequest(
            cleanId,
            partnerId,
            action as 'accept' | 'decline',
            {
                venueId: venueId ? String(venueId) : undefined,
                eventDate: eventDate || undefined,
                hostId: hostId ? String(hostId) : undefined,
            }
        );
        res.json({ success: true, message: `Request ${action}ed successfully`, data: result });
    } catch (err: any) {
        logger.error('respondToRequest error:', err);
        const code = err.code || (err.timeLock ? 'FOUR_HOUR_TIME_LOCK' : undefined);
        const isSlotFilled = err.message === 'MATCH_SLOT_FILLED';
        const isExpired = err.message === 'REQUEST_EXPIRED';
        const isAlreadyProcessed = err.message === 'REQUEST_ALREADY_PROCESSED';
        // REQUEST_NOT_FOUND means the id we were handed did not resolve to any
        // night request, match or booking — which is just as often a client
        // sending the wrong id as it is a genuinely finished invite. It must not
        // be reported as "no longer available", because the client deletes the
        // card on that signal and would throw away an invite that is still open.
        const isUnresolved = err.message === 'REQUEST_NOT_FOUND';
        const isUnauthorized = err.message === 'UNAUTHORIZED_REQUEST_ACTION';
        const isWrongEndpoint = err.code === 'WRONG_ENDPOINT_PARTY_PLAN_REQUEST';
        let userMessage = err.message || 'Failed to process request response';
        if (isSlotFilled) {
            userMessage = 'This invitation is no longer available as the host is already matched with another guest.';
        } else if (isExpired) {
            userMessage = 'This invitation has expired.';
        } else if (isAlreadyProcessed) {
            userMessage = 'This invitation has already been responded to.';
        } else if (isUnresolved) {
            userMessage = 'We could not find this invitation. Pull to refresh and try again.';
        } else if (isUnauthorized) {
            userMessage = 'This invitation was not sent to you.';
        } else if (isWrongEndpoint) {
            userMessage = 'This is a Party Plan request. Please respond to it from the Party Plan card.';
        }
        res.status(400).json({
            success: false,
            code: code || err.message,
            reason: code || err.message,
            notAvailable: isSlotFilled || isExpired || isAlreadyProcessed,
            unresolved: isUnresolved,
            message: userMessage,
            ...(isWrongEndpoint && err.correctEndpoint ? { correctEndpoint: err.correctEndpoint } : {}),
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
        const code = err.code || (err.timeLock ? 'FOUR_HOUR_TIME_LOCK' : undefined);
        res.status(400).json({
            success: false,
            code,
            reason: code,
            message: err.message || 'Failed to initiate payment',
            ...(err.timeLock || {}),
        });
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
        const code = err.code || (err.timeLock ? 'FOUR_HOUR_TIME_LOCK' : undefined);
        res.status(err.statusCode || 400).json({
            success: false,
            code,
            reason: code,
            message: err.message || 'Failed to verify payment',
            ...(err.timeLock || {}),
        });
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
