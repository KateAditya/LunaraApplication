import { Request, Response } from 'express';
import { Op } from 'sequelize';
import GroupParty, { GroupPartyStatus, GroupPartyPaymentStatus } from '../models/GroupParty';
import Venue from '../models/Venue';
import VenueImage from '../models/VenueImage';
import User from '../models/User';
import UserProfile from '../models/UserProfile';
import UserPhoto from '../models/UserPhoto';
import { logger } from '../config/logger';
import { generateTicketForGroupPartyHelper } from '../services/ticketService';
import { GroupPartyService, PartyType } from '../services/GroupPartyService';
import { TimeLockError } from '../utils/bookingLimitValidator';
import { BookingPolicyService } from '../services/BookingPolicyService';

// Calculate pricing
export const calculatePricing = async (req: Request, res: Response): Promise<void> => {
    try {
        const { venueId, numberOfFriends } = req.body;
        const result = await GroupPartyService.calculateAuthoritativePricing(venueId, Number(numberOfFriends));

        res.json({
            success: true,
            data: {
                numberOfFriends: result.numberOfFriends,
                tableBookingCharge: result.tableBookingCharge,
                discountPercentage: result.discountPercentage,
                discountAmount: result.discountAmount,
                totalAmount: result.totalAmount
            }
        });
    } catch (err: any) {
        logger.error('calculatePricing error:', err);
        res.status(err.message === 'Venue not found' ? 404 : 400).json({ success: false, error: err.message });
    }
};

// Create Group Party & Razorpay Order
export const createGroupParty = async (req: Request, res: Response): Promise<void> => {
    try {
        const { venueId, numberOfFriends, partyDate, mobileNumber, optionalMobileNumber, foodPreference, drinkPreference, partySubject, partyRequirement, partyDescription, startTime, paymentMode } = req.body;
        const userId = req.user!.id;

        const result = await GroupPartyService.createParty({
            userId,
            venueId,
            numberOfFriends: Number(numberOfFriends),
            partyDate,
            mobileNumber,
            optionalMobileNumber,
            foodPreference,
            drinkPreference,
            partySubject,
            partyRequirement,
            partyDescription,
            startTime,
            paymentMode,
        });

        res.status(201).json({
            success: true,
            partyType: result.partyType,
            data: result.record,
            razorpayOrderId: result.razorpayOrderId || '',
            razorpayKeyId: result.razorpayKeyId || process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
            amount: result.amount || 0,
            currency: result.currency || 'INR'
        });

        if ((result.partyType as string) === 'large_party_request' || result.partyType === PartyType.LARGE || Number(numberOfFriends) > 20) {
            try {
                const { io } = require('../server');
                io.to('admin').emit('admin_notification', {
                    title: 'New Group Party Request',
                    message: `A new Group Party request for ${numberOfFriends} friends requires admin attention.`,
                    type: 'group_party_request'
                });
            } catch (adminErr: any) {
                logger.warn('Failed to emit admin_notification: ' + adminErr.message);
            }
        }

    } catch (err: any) {
        logger.error('createGroupParty error:', err);
        if (err instanceof TimeLockError || err.name === 'TimeLockError' || err.timeLock || err.reason === 'FOUR_HOUR_TIME_LOCK') {
            const tl = err.timeLock || err;
            res.status(400).json({
                success: false,
                reason: 'FOUR_HOUR_TIME_LOCK',
                conflictingEventType: tl.conflictingEventType,
                conflictingEventId: tl.conflictingEventId,
                conflictingEventTitle: tl.conflictingEventTitle,
                conflictingDateTime: tl.conflictingDateTime,
                nextAvailableTime: tl.nextAvailableTime,
                message: tl.message,
            });
            return;
        }
        if (err.code && err.code.startsWith('PLAN_')) {
            res.status(409).json({
                success: false,
                code: err.code,
                message: err.message,
                lock: err.details
            });
            return;
        }
        res.status(400).json({ success: false, message: err.message || 'Failed to create group party' });
    }
};

export const verifyPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature, partyId, groupPartyId, id } = req.body;

        const groupParty = await GroupPartyService.verifySmallPartyPayment(
            razorpay_order_id,
            razorpay_payment_id,
            razorpay_signature,
            req.user!.id,
            partyId || groupPartyId || id
        );

        res.json({ success: true, message: 'Payment verified successfully', data: groupParty });
    } catch (err: any) {
        logger.error('verifyPayment error:', err);
        const status = err.statusCode || (err.message === 'Group party booking not found' ? 404 : 400);
        res.status(status).json({ success: false, message: err.message });
    }
};

export const cancelPendingGroupParty = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const partyId = id || req.body.partyId || req.body.id;
        if (!partyId) {
            res.status(400).json({ success: false, message: 'Party ID is required' });
            return;
        }

        const success = await GroupPartyService.cancelPendingParty(partyId, req.user!.id);
        res.json({ success, message: success ? 'Pending group party cancelled successfully' : 'No pending group party found to cancel' });
    } catch (err: any) {
        logger.error('cancelPendingGroupParty error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

export const getMyGroupParties = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = req.user!.id;

        const groupParties = await GroupParty.findAll({
            where: {
                userId,
                status: { [Op.ne]: GroupPartyStatus.CANCELLED }
            },
            include: [
                {
                    model: Venue,
                    as: 'venue',
                    attributes: ['id', 'name', 'addressLine1', 'city', 'area', 'latitude', 'longitude'],
                    include: [
                        { model: VenueImage, as: 'images', attributes: ['id', 'filePath', 'imageType', 'isPrimary'], required: false },
                    ],
                },
                {
                    model: User,
                    as: 'user',
                    attributes: ['id', 'firstName', 'lastName', 'profileImageUrl', 'isVerified'],
                    include: [
                        { model: UserProfile, as: 'profile', attributes: ['bio', 'city', 'displayName'], required: false },
                        { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary'], required: false },
                    ],
                },
            ],
            order: [['createdAt', 'DESC']],
        });

        res.json({
            success: true,
            data: groupParties,
        });
    } catch (err: any) {
        logger.error('getMyGroupParties error:', err);
        res.status(500).json({ success: false, error: err.message });
    }
};

export const getGroupPartyTicket = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const groupPartyInclude = [
            {
                model: Venue,
                as: 'venue',
                attributes: ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone', 'latitude', 'longitude'],
                include: [
                    { model: VenueImage, as: 'images', attributes: ['id', 'filePath', 'imageType', 'isPrimary'], required: false },
                ],
            },
            {
                model: User,
                as: 'user',
                attributes: ['id', 'firstName', 'lastName', 'profileImageUrl', 'isVerified'],
                include: [
                    { model: UserProfile, as: 'profile', attributes: ['bio', 'city', 'displayName'], required: false },
                    { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary'], required: false },
                ],
            },
        ];

        let groupParty = await GroupParty.findByPk(id, {
            include: groupPartyInclude,
        });

        if (!groupParty) {
            try {
                const TicketModel = (await import('../models/Ticket')).default;
                const ticket = await TicketModel.findByPk(id);
                if (ticket && ticket.bookingId) {
                    groupParty = await GroupParty.findByPk(ticket.bookingId, {
                        include: groupPartyInclude,
                    });
                }
            } catch (_) {}
        }

        if (!groupParty) {
            res.status(404).json({ success: false, message: 'Group party not found' });
            return;
        }
        if (groupParty.userId !== req.user!.id) {
            res.status(403).json({ success: false, message: 'You can only view your own group party ticket' });
            return;
        }

        const resolveUserPhoto = (u: any): string | null => {
            if (!u) return null;
            let photoUrl: string | null = u.profileImageUrl ?? null;
            if (u.photos && u.photos.length > 0) {
                const primary = u.photos.find((p: any) => p.isPrimary) || u.photos[0];
                if (primary?.filePath) {
                    photoUrl = '/' + primary.filePath.replace(/\\/g, '/');
                }
            }
            return photoUrl;
        };

        const hostRaw = (groupParty as any).user;
        const hostPhoto = resolveUserPhoto(hostRaw);
        const hostName = hostRaw ? `${hostRaw.firstName || ''} ${hostRaw.lastName || ''}`.trim() : 'Party Host';
        const hostUsername = hostRaw?.profile?.displayName || (hostRaw?.firstName ? `${hostRaw.firstName}_${hostRaw.lastName || ''}`.toLowerCase().replace(/_+$/, '') : 'host');

        const hostData = hostRaw ? {
            id: hostRaw.id,
            firstName: hostRaw.firstName,
            lastName: hostRaw.lastName,
            name: hostName,
            username: hostUsername,
            profilePhotoUrl: hostPhoto,
            profileImageUrl: hostPhoto,
            isVerified: hostRaw.isVerified || false,
            subscriptionTier: 'FREE',
        } : null;

        let ticketUrl = groupParty.ticketUrl ?? null;
        let ticketCode = groupParty.ticketCode || groupParty.paymentId || `GP-${groupParty.id.substring(0, 8).toUpperCase()}`;

        // Generate ticket on-the-fly ONLY for verified paid parties
        const isVerifiedPaid = groupParty.paymentStatus === GroupPartyPaymentStatus.PAID && groupParty.status === GroupPartyStatus.CONFIRMED;

        if (!isVerifiedPaid && Number(groupParty.totalAmount) > 0) {
            res.status(402).json({
                success: false,
                message: 'Payment has not been completed or verified for this group party ticket.'
            });
            return;
        }

        if (!ticketUrl && isVerifiedPaid) {
            try {
                ticketUrl = await generateTicketForGroupPartyHelper(groupParty.id);
            } catch (tErr: any) {
                logger.warn(`On-the-fly group party ticket generation failed: ${tErr.message}`);
            }
        }

        const totalParticipants = Number(groupParty.numberOfFriends);
        const hostCount = 1;
        const memberCount = Math.max(1, totalParticipants - hostCount);

        res.json({
            success: true,
            data: {
                groupParty: {
                    id: groupParty.id,
                    partyDate: groupParty.partyDate,
                    startTime: groupParty.startTime,
                    totalParticipants,
                    hostCount,
                    memberCount,
                    numberOfFriends: totalParticipants,
                    numberOfMembers: totalParticipants,
                    totalAmount: Number(groupParty.totalAmount),
                    tableBookingCharge: Number(groupParty.tableBookingCharge),
                    discountAmount: Number(groupParty.discountAmount),
                    status: groupParty.status,
                    paymentStatus: groupParty.paymentStatus,
                    paymentMethod: Number(groupParty.totalAmount) <= 0
                        ? 'No Payment Required'
                        : (groupParty.paymentId?.startsWith('wallet_') ? 'LUNARA Wallet' : 'Razorpay'),
                    ticketCode: ticketCode,
                    ticketUrl: ticketUrl,
                    host: hostData,
                    venue: (groupParty as any).venue,
                },
                ticketCode: ticketCode,
                ticketUrl: ticketUrl,
            },
        });
    } catch (err: any) {
        logger.error('getGroupPartyTicket error:', err);
        res.status(500).json({ success: false, error: err.message });
    }
};

export const getSmallPartyCancellationPreview = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const userId = req.user!.id;

        const preview = await BookingPolicyService.getSmallGroupPartyCancellationPreview(id, userId);
        res.json({ success: true, data: preview });
    } catch (err: any) {
        logger.error('getSmallPartyCancellationPreview error:', err);
        res.status(400).json({ success: false, message: err.message });
    }
};

export const cancelSmallGroupParty = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const userId = req.user!.id;
        const { reason } = req.body;

        const result = await BookingPolicyService.cancelAndRefundGroupParty(id, userId, reason);
        res.json({
            success: true,
            message: result.message,
            data: {
                partyId: result.party.id,
                status: result.party.status,
                refundAmount: result.refundAmount,
                walletTransactionId: result.walletTransactionId,
            },
        });
    } catch (err: any) {
        logger.error('cancelSmallGroupParty error:', err);
        res.status(400).json({ success: false, message: err.message });
    }
};
