import { Request, Response } from 'express';
import GroupParty, { GroupPartyPaymentStatus } from '../models/GroupParty';
import Venue from '../models/Venue';
import VenueImage from '../models/VenueImage';
import User from '../models/User';
import UserProfile from '../models/UserProfile';
import UserPhoto from '../models/UserPhoto';
import { logger } from '../config/logger';
import { generateTicketForGroupPartyHelper } from '../services/ticketService';
import { GroupPartyService, PartyType } from '../services/GroupPartyService';

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
        const { userId, venueId, numberOfFriends, partyDate, mobileNumber, optionalMobileNumber, foodPreference, drinkPreference, partySubject, partyRequirement, partyDescription, startTime } = req.body;

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
            startTime
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
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        const groupParty = await GroupPartyService.verifySmallPartyPayment(
            razorpay_order_id,
            razorpay_payment_id,
            razorpay_signature
        );

        res.json({ success: true, message: 'Payment verified successfully', data: groupParty });
    } catch (err: any) {
        logger.error('verifyPayment error:', err);
        res.status(err.message === 'Group party booking not found' ? 404 : 400).json({ success: false, message: err.message });
    }
};

export const getMyGroupParties = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.query;
        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

        const groupParties = await GroupParty.findAll({
            where: { userId: userId as string },
            include: [
                {
                    model: Venue,
                    as: 'venue',
                    attributes: ['id', 'name', 'addressLine1', 'city'],
                    include: [
                        { model: VenueImage, as: 'images', attributes: ['id', 'filePath', 'imageType', 'isPrimary'], required: false },
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
        const groupParty = await GroupParty.findByPk(id, {
            include: [
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
                    attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                    include: [
                        { model: UserProfile, as: 'profile', attributes: ['bio', 'city'], required: false },
                        { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary'], required: false },
                    ],
                },
            ],
        });

        if (!groupParty) {
            res.status(404).json({ success: false, message: 'Group party not found' });
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
        const hostData = hostRaw ? {
            id: hostRaw.id,
            firstName: hostRaw.firstName,
            lastName: hostRaw.lastName,
            username: hostRaw.profile?.displayName || (hostRaw.firstName ? `${hostRaw.firstName}_${hostRaw.lastName}`.toLowerCase() : 'user'),
            profilePhotoUrl: resolveUserPhoto(hostRaw),
            subscriptionTier: 'FREE',
        } : null;

        let ticketUrl = groupParty.ticketUrl ?? null;
        let ticketCode = groupParty.ticketCode || groupParty.paymentId || `GP-${groupParty.id.substring(0, 8).toUpperCase()}`;

        if (!ticketUrl && groupParty.paymentStatus === GroupPartyPaymentStatus.PAID) {
            try {
                ticketUrl = await generateTicketForGroupPartyHelper(groupParty.id);
            } catch (tErr: any) {
                logger.warn(`On-the-fly group party ticket generation failed: ${tErr.message}`);
            }
        }

        res.json({
            success: true,
            data: {
                groupParty: {
                    id: groupParty.id,
                    partyDate: groupParty.partyDate,
                    numberOfFriends: groupParty.numberOfFriends,
                    numberOfMembers: groupParty.numberOfFriends + 1,
                    totalAmount: groupParty.totalAmount,
                    status: groupParty.status,
                    paymentStatus: groupParty.paymentStatus,
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
