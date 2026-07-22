import { Request, Response } from 'express';
import GroupParty, { GroupPartyStatus, GroupPartyPaymentStatus } from '../models/GroupParty';
import { PlanEligibilityService } from '../services/PlanEligibilityService';
import Venue from '../models/Venue';
import User from '../models/User';
import UserProfile from '../models/UserProfile';
import UserPhoto from '../models/UserPhoto';
import Razorpay from 'razorpay';
import crypto from 'crypto';
import { logger } from '../config/logger';
import { validateVenueTimingAndHolidays } from '../utils/venueValidator';
import { checkExistingBookingForDate } from '../utils/bookingLimitValidator';
import { generateTicketForGroupPartyHelper } from '../services/ticketService';

const razorpay = new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
    key_secret: process.env.RAZORPAY_KEY_SECRET || 'secret123',
});

// Calculate pricing
export const calculatePricing = async (req: Request, res: Response): Promise<void> => {
    try {
        const { venueId, numberOfFriends } = req.body;
        const venue = await Venue.findByPk(venueId);
        if (!venue) {
            res.status(404).json({ success: false, message: 'Venue not found' });
            return;
        }

        if (numberOfFriends > 20) {
            res.status(400).json({ success: false, message: 'Maximum 20 friends allowed for a group party' });
            return;
        }

        const chargePerPerson = venue.groupPartyChargePerPerson || venue.tableBookingCharges || 0;
        const discountPct = venue.groupPartyDiscountPercentage || venue.discountPercentage || 0;

        const tableBookingCharge = chargePerPerson * numberOfFriends;
        const discountAmount = (tableBookingCharge * discountPct) / 100;
        const totalAmount = tableBookingCharge - discountAmount;

        res.json({
            success: true,
            data: {
                numberOfFriends,
                tableBookingCharge,
                discountPercentage: discountPct,
                discountAmount,
                totalAmount
            }
        });
    } catch (err: any) {
        logger.error('calculatePricing error:', err);
        res.status(500).json({ success: false, error: err.message });
    }
};

// Create Group Party & Razorpay Order
export const createGroupParty = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId, venueId, numberOfFriends, partyDate, mobileNumber, optionalMobileNumber, foodPreference, drinkPreference } = req.body;

        if (!mobileNumber?.trim()) {
            res.status(400).json({ success: false, message: 'Mobile number is required' });
            return;
        }

        if (numberOfFriends > 20) {
            res.status(400).json({ success: false, message: 'Maximum 20 friends allowed' });
            return;
        }

        const venue = await Venue.findByPk(venueId);
        if (!venue) {
            res.status(404).json({ success: false, message: 'Venue not found' });
            return;
        }

        // ── Validate Venue Timings and Holidays ────────────────────────────────
        const timingValidation = validateVenueTimingAndHolidays(venue, partyDate);
        if (!timingValidation.isValid) {
            res.status(400).json({ success: false, message: timingValidation.reason });
            return;
        }

        // Check for 1 plan per day limit (Stranger Meet / Party Plan / Group Party)
        const bookingConflictMsg = await checkExistingBookingForDate(userId, partyDate);
        if (bookingConflictMsg) {
            res.status(400).json({ success: false, message: 'You already have a plan scheduled on this day.' });
            return;
        }

        const chargePerPerson = venue.groupPartyChargePerPerson || venue.tableBookingCharges || 0;
        const discountPct = venue.groupPartyDiscountPercentage || venue.discountPercentage || 0;

        const tableBookingCharge = chargePerPerson * numberOfFriends;
        const discountAmount = (tableBookingCharge * discountPct) / 100;
        const totalAmount = tableBookingCharge - discountAmount;

        let order: any = null;
        if (totalAmount > 0) {
            // Create razorpay order
            const options = {
                amount: Math.round(totalAmount * 100), // in paise
                currency: 'INR',
                receipt: `gp_${Date.now()}`
            };
            order = await razorpay.orders.create(options);
        }

        const groupParty = await PlanEligibilityService.runAtomicCheckAndCreate(
            userId,
            'group_party',
            partyDate,
            async (transaction) => {
                return await GroupParty.create({
                    userId,
                    venueId,
                    numberOfFriends,
                    tableBookingCharge,
                    discountAmount,
                    totalAmount,
                    partyDate,
                    mobileNumber: mobileNumber.trim(),
                    optionalMobileNumber: optionalMobileNumber?.trim(),
                    foodPreference: foodPreference?.trim(),
                    drinkPreference: drinkPreference?.trim(),
                    status: totalAmount > 0 ? GroupPartyStatus.PENDING : GroupPartyStatus.CONFIRMED,
                    paymentStatus: totalAmount > 0 ? GroupPartyPaymentStatus.PENDING : GroupPartyPaymentStatus.PAID,
                    paymentId: order ? order.id : `free_${Date.now()}`
                }, { transaction });
            }
        );

        try {
            const isPaid = totalAmount <= 0;
            if (isPaid) {
                try {
                    await generateTicketForGroupPartyHelper(groupParty.id);
                } catch (tErr) {
                    logger.error('Group party ticket generation error:', tErr);
                }
            }
            const host = await User.findByPk(userId, { attributes: ['id', 'fcmToken'] });
            if (isPaid && host && host.fcmToken) {
                const { sendPushNotification } = require('../services/fcmService');
                await sendPushNotification(host.fcmToken, {
                    title: 'Group Party Booked! 🎉',
                    body: `Your group party of ${numberOfFriends} friends at ${venue.name} is confirmed!`,
                    data: {
                        type: 'group_party_confirmed',
                        partyId: groupParty.id,
                    }
                });
            }
            const { io } = require('../server');
            io.to(`user_${userId}`).emit('group_party_status_update', {
                partyId: groupParty.id,
                status: groupParty.status
            });
        } catch (pushErr) {
            logger.warn('Failed to send push/socket for group party creation: ' + pushErr);
        }

        res.status(201).json({
            success: true,
            data: groupParty,
            razorpayOrderId: order ? order.id : '',
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
            amount: order ? order.amount : 0,
            currency: order ? order.currency : 'INR'
        });

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
        res.status(500).json({ success: false, error: err.message });
    }
};

export const verifyPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        const groupParty = await GroupParty.findOne({ where: { paymentId: razorpay_order_id } });
        if (!groupParty) {
            res.status(404).json({ success: false, message: 'Group party booking not found' });
            return;
        }

        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(razorpay_order_id + '|' + razorpay_payment_id);
        const generatedSignature = hmac.digest('hex');

        if (generatedSignature === razorpay_signature) {
            await groupParty.update({
                paymentStatus: GroupPartyPaymentStatus.PAID,
                status: GroupPartyStatus.CONFIRMED
            });

            try {
                await generateTicketForGroupPartyHelper(groupParty.id);
            } catch (tErr) {
                logger.error('Group party ticket generation error on verify:', tErr);
            }

            try {
                const host = await User.findByPk(groupParty.userId, { attributes: ['id', 'fcmToken'] });
                const venue = await Venue.findByPk(groupParty.venueId, { attributes: ['id', 'name'] });
                const venueName = venue?.name || 'Venue';
                if (host && host.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(host.fcmToken, {
                        title: 'Group Party Booked! 🎉',
                        body: `Your payment is verified. Group party at ${venueName} is confirmed!`,
                        data: {
                            type: 'group_party_confirmed',
                            partyId: groupParty.id,
                        }
                    });
                }
                const { io } = require('../server');
                io.to(`user_${groupParty.userId}`).emit('group_party_payment_success', { partyId: groupParty.id });
            } catch (pushErr) {
                logger.warn('Failed to send push/socket for group party verification: ' + pushErr);
            }

            res.json({ success: true, message: 'Payment verified successfully', data: groupParty });
        } else {
            await groupParty.update({ paymentStatus: GroupPartyPaymentStatus.FAILED });
            res.status(400).json({ success: false, message: 'Invalid payment signature' });
        }
    } catch (err: any) {
        logger.error('verifyPayment error:', err);
        res.status(500).json({ success: false, error: err.message });
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
                    attributes: ['id', 'name', 'addressLine1', 'city', 'images', 'imageUrl'],
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
                    attributes: ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone', 'latitude', 'longitude', 'images', 'imageUrl'],
                },
                {
                    model: User,
                    as: 'user',
                    attributes: ['id', 'firstName', 'lastName', 'username', 'profileImageUrl', 'subscriptionTier'],
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
            username: hostRaw.username,
            profilePhotoUrl: resolveUserPhoto(hostRaw),
            subscriptionTier: hostRaw.subscriptionTier,
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
