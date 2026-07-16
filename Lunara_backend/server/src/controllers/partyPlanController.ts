import { Request, Response } from 'express';
import PartyPlan, { PartyPlanStatus, PartyPlanVisibility, PartyPlanPaymentType } from '../models/PartyPlan';
import { Op } from 'sequelize';
import User from '../models/User';
import Venue from '../models/Venue';
import UserProfile from '../models/UserProfile';
import UserPhoto from '../models/UserPhoto';
import VenueImage from '../models/VenueImage';
import { logger } from '../config/logger';
import Razorpay from 'razorpay';
import crypto from 'crypto';
import { PartyPlanPaymentStatus } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus, PartyPlanJoinerPaymentStatus } from '../models/PartyPlanRequest';
import { sendMulticastPushNotification } from '../services/fcmService';
import Conversation from '../models/Conversation';
import ChatSubscription, { ChatSubscriptionStatus, ChatSubscriptionType } from '../models/ChatSubscription';
import { getChatSettings } from './chatSubscriptionController';
import { validateVenueTimingAndHolidays } from '../utils/venueValidator';
import Booking, { BookingStatus, GoingMode, PaymentStatus as BookingPaymentStatus } from '../models/Booking';
import Payment, { PaymentMethod, PaymentStatus } from '../models/Payment';

async function autoOpenChat(hostId: string, joinerId: string) {
    try {
        let conv = await Conversation.findOne({
            where: {
                [Op.or]: [
                    { participantOne: hostId, participantTwo: joinerId },
                    { participantOne: joinerId, participantTwo: hostId }
                ]
            }
        });
        if (!conv) {
            conv = await Conversation.create({
                participantOne: hostId,
                participantTwo: joinerId
            });
        }

        // Prevent duplicate chat unlocking
        const existingSub = await ChatSubscription.findOne({
            where: {
                conversationId: conv.id,
                status: ChatSubscriptionStatus.ACTIVE,
                validUntil: { [Op.gt]: new Date() }
            }
        });
        if (existingSub) {
            logger.info(`Active chat subscription already exists for conversation ${conv.id}, skipping creation.`);
            return;
        }

        const freeDays = getChatSettings().freeDays;
        const validUntil = new Date();
        validUntil.setDate(validUntil.getDate() + freeDays);

        await ChatSubscription.create({
            conversationId: conv.id,
            paidById: hostId, // system granted
            amount: 0,
            daysGranted: freeDays,
            validUntil,
            status: ChatSubscriptionStatus.ACTIVE,
            subscriptionType: ChatSubscriptionType.FREE,
        });

        // Send push notification to host and joiner
        setImmediate(async () => {
            try {
                const host = await User.findByPk(hostId);
                const joiner = await User.findByPk(joinerId);
                const tokens = [host?.fcmToken, joiner?.fcmToken].filter(t => t && t.trim() !== '') as string[];
                if (tokens.length > 0) {
                    await sendMulticastPushNotification(tokens, {
                        title: '💬 Chat Unlocked!',
                        body: 'Your match is confirmed and private chat is now active for 7 days.',
                        data: {
                            type: 'chat_unlocked',
                            conversationId: conv!.id,
                        },
                    });
                }
            } catch (err: any) {
                logger.warn('Failed to send chat unlocked notification:', err.message);
            }
        });
    } catch (err: any) {
        logger.error('autoOpenChat error:', err);
    }
}

async function createBookingAndPayments(plan: PartyPlan, request: PartyPlanRequest) {
    try {
        const existingBooking = await Booking.findOne({
            where: {
                goingMode: GoingMode.PARTY_REQUEST,
                userId: plan.userId,
                venueId: plan.venueId,
                bookingDate: plan.planDateTime,
            }
        });
        if (existingBooking) {
            logger.info(`Booking already exists for plan ${plan.id}, skipping creation.`);
            return;
        }

        const dateObj = new Date(plan.planDateTime);
        const bookingDate = dateObj.toISOString().split('T')[0];
        const startTime = dateObj.toTimeString().split(' ')[0];

        const ticketCode = 'PP-' + Math.random().toString(36).substring(2, 8).toUpperCase();

        const booking = await Booking.create({
            userId: plan.userId,
            venueId: plan.venueId,
            bookingDate: bookingDate as any,
            startTime,
            numberOfGuests: 2,
            totalAmount: 198.00,
            depositAmount: 198.00,
            commissionAmount: 0,
            status: BookingStatus.CONFIRMED,
            paymentStatus: BookingPaymentStatus.PAID,
            isGroupBooking: false,
            goingMode: GoingMode.PARTY_REQUEST,
            ticketCode,
        });

        // Create Payment record for Host
        await Payment.create({
            transactionId: plan.hostRazorpayPaymentId || `TXN_HOST_${plan.id}`,
            bookingId: booking.id,
            userId: plan.userId,
            amount: plan.depositAmount ? Number(plan.depositAmount) : 99.00,
            currency: 'INR',
            paymentMethod: PaymentMethod.RAZORPAY,
            paymentGateway: 'razorpay',
            status: PaymentStatus.SUCCESSFUL,
            refundAmount: 0,
        });

        // Create Payment record for Joiner
        await Payment.create({
            transactionId: request.joinerRazorpayPaymentId || `TXN_JOINER_${request.id}`,
            bookingId: booking.id,
            userId: request.requesterId,
            amount: plan.paymentType === 'self_pay' ? 0.00 : 99.00,
            currency: 'INR',
            paymentMethod: PaymentMethod.RAZORPAY,
            paymentGateway: 'razorpay',
            status: PaymentStatus.SUCCESSFUL,
            refundAmount: 0,
        });

        // Unlock Chat!
        await autoOpenChat(plan.userId, request.requesterId);

        logger.info(`Successfully created Booking ${booking.id} and Payments for plan ${plan.id}`);
    } catch (err) {
        logger.error('Error in createBookingAndPayments:', err);
    }
}

const razorpay = new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
    key_secret: process.env.RAZORPAY_KEY_SECRET || 'secret123',
});

// ─── Shared venue attributes to include ──────────────────────────────────────
const VENUE_ATTRS = ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone', 'coverChargeMale', 'coverChargeFemale'];
const USER_ATTRS = ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'];
const PROFILE_ATTRS = ['bio', 'occupation', 'city', 'gender'];

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans
// Create & post a party plan
// ─────────────────────────────────────────────────────────────────────────────
export const createPartyPlan = async (req: Request, res: Response): Promise<void> => {
    try {
        const rawVisibility = String(req.body.visibility || req.body.privacyType || 'public').toLowerCase();
        let parsedVisibility = PartyPlanVisibility.PUBLIC;
        if (rawVisibility === 'private') {
            parsedVisibility = PartyPlanVisibility.PRIVATE;
        } else if (rawVisibility === 'both') {
            parsedVisibility = PartyPlanVisibility.BOTH;
        }

        const rawPaymentType = String(req.body.paymentType || 'split').toLowerCase();
        let parsedPaymentType = PartyPlanPaymentType.SPLIT;
        if (rawPaymentType === 'self_pay') {
            parsedPaymentType = PartyPlanPaymentType.SELF_PAY;
        }

        const { userId, venueId, message, planDateTime, mobileNumber, optionalMobileNumber, foodPreference, drinkPreference } = req.body;
        const selectedUsers = req.body.selectedUsers || req.body.selectedUserIds;

        // ── Validate required fields ─────────────────────────────────────────
        const errors: Record<string, string> = {};
        if (!userId) errors.userId = 'userId is required';
        if (!venueId) errors.venueId = 'venueId is required';
        if (!message?.trim()) errors.message = 'Party message is required';
        if (!planDateTime) errors.planDateTime = 'planDateTime is required';

        if (parsedVisibility === PartyPlanVisibility.PRIVATE || parsedVisibility === PartyPlanVisibility.BOTH) {
            if (!Array.isArray(selectedUsers) || selectedUsers.length === 0) {
                errors.selectedUsers = `selectedUsers array is required and cannot be empty when visibility is ${parsedVisibility}`;
            }
        }

        if (Object.keys(errors).length > 0) {
            res.status(400).json({ success: false, message: 'Validation failed', errors });
            return;
        }

        // ── Validate planDateTime is in the future ────────────────────────────
        const partyDate = new Date(planDateTime);
        if (isNaN(partyDate.getTime())) {
            res.status(400).json({ success: false, message: 'planDateTime must be a valid ISO date string (e.g. "2025-06-01T22:00:00.000Z")' });
            return;
        }

        // ── Verify user exists ────────────────────────────────────────────────
        const user = await User.findByPk(userId, {
            attributes: USER_ATTRS,
            include: [
                { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
            ],
        });
        if (!user) {
            res.status(404).json({ success: false, message: 'User not found' });
            return;
        }

        const finalMobileNumber = mobileNumber?.trim() || user.phone?.trim() || '';
        if (!finalMobileNumber) {
            res.status(400).json({
                success: false,
                message: 'Validation failed',
                errors: { mobileNumber: 'Mobile number is required. Please set phone number in your profile first.' }
            });
            return;
        }

        // ── Verify venue exists and is active ─────────────────────────────────
        const venue = await Venue.findByPk(venueId, { attributes: ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone', 'coverChargeMale', 'coverChargeFemale', 'openingTime', 'closingTime', 'daysOpen', 'closedDates'] });
        if (!venue) {
            res.status(404).json({ success: false, message: 'Venue not found' });
            return;
        }

        // ── Validate Venue Timings and Holidays ────────────────────────────────
        const timingValidation = validateVenueTimingAndHolidays(venue, planDateTime);
        if (!timingValidation.isValid) {
            res.status(400).json({ success: false, message: timingValidation.reason });
            return;
        }

        // ── Check for 1 plan per day limit ────────────────────────────────────
        const targetStart = new Date(partyDate);
        targetStart.setHours(0, 0, 0, 0);
        const targetEnd = new Date(partyDate);
        targetEnd.setHours(23, 59, 59, 999);

        const existingPlanForDate = await PartyPlan.findOne({
            where: {
                userId,
                planDateTime: {
                    [Op.between]: [targetStart, targetEnd],
                },
                status: {
                    [Op.ne]: PartyPlanStatus.CANCELLED
                }
            }
        });

        if (existingPlanForDate) {
            res.status(400).json({ success: false, message: 'You already have a party plan scheduled for this date.' });
            return;
        }

        // ── Generate Razorpay Order ───────────────────────────────────────────
        const depositAmount = parsedPaymentType === PartyPlanPaymentType.SELF_PAY ? 198.00 : 99.00;
        const options = {
            amount: Math.round(depositAmount * 100), // in paise
            currency: 'INR',
            receipt: `pp_${Date.now()}`
        };
        let order: any = { id: `order_mock_${Date.now()}`, amount: options.amount, currency: options.currency };
        if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id') {
            try {
                order = await razorpay.orders.create(options);
            } catch (err: any) {
                logger.warn('Razorpay create order failed, using mock order. Error: ' + err.message);
            }
        }

        // ── Create the party plan ─────────────────────────────────────────────
        const partyPlan = await PartyPlan.create({
            userId,
            venueId,
            message: message.trim(),
            planDateTime: partyDate,
            mobileNumber: finalMobileNumber,
            optionalMobileNumber: optionalMobileNumber?.trim(),
            status: PartyPlanStatus.ACTIVE,
            visibility: parsedVisibility,
            selectedUsers: (parsedVisibility === PartyPlanVisibility.PRIVATE || parsedVisibility === PartyPlanVisibility.BOTH) ? selectedUsers : null,
            depositAmount: depositAmount,
            hostPaymentStatus: PartyPlanPaymentStatus.UNPAID,
            hostRazorpayOrderId: order.id,
            isLive: parsedVisibility === PartyPlanVisibility.PRIVATE ? false : true, // Private plans are not shown in public feed, both and public are
            expiresAt: partyDate,
            paymentStatus: 'pending',
            foodPreference: foodPreference || 'Both',
            drinkPreference: drinkPreference || 'Both',
            paymentType: parsedPaymentType,
        });

        // Auto-generate accepted requests for invited users of private or both plan
        if ((parsedVisibility === PartyPlanVisibility.PRIVATE || parsedVisibility === PartyPlanVisibility.BOTH) && Array.isArray(selectedUsers) && selectedUsers.length > 0) {
            for (const invitedUserId of selectedUsers) {
                // Generate a joiner order ID
                const joinerOptions = {
                    amount: Math.round(depositAmount * 100),
                    currency: 'INR',
                    receipt: `ppreq_${Date.now()}`
                };
                let joinerOrder: any = { id: `order_mock_${Date.now()}` };
                if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id') {
                    try {
                        joinerOrder = await razorpay.orders.create(joinerOptions);
                    } catch (err: any) {
                        logger.warn('Razorpay create joiner order failed for invite, using mock. Error: ' + err.message);
                    }
                }
                
                await PartyPlanRequest.create({
                    planId: partyPlan.id,
                    requesterId: invitedUserId,
                    status: PartyPlanRequestStatus.PENDING,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
                    joinerRazorpayOrderId: joinerOrder.id,
                    latLangCheckIn: false,
                });
            }
        }

        const responseData = {
            id: partyPlan.id,
            status: partyPlan.status,
            paymentStatus: partyPlan.paymentStatus,
            visibility: partyPlan.visibility,
            selectedUsers: partyPlan.selectedUsers,
            message: partyPlan.message,
            planDateTime: partyPlan.planDateTime,
            createdAt: partyPlan.createdAt,
            hostPaymentStatus: partyPlan.hostPaymentStatus,
            hostRazorpayOrderId: partyPlan.hostRazorpayOrderId,
            isLive: partyPlan.isLive,
            depositAmount: partyPlan.depositAmount,
            expiresAt: partyPlan.expiresAt,
            foodPreference: partyPlan.foodPreference,
            drinkPreference: partyPlan.drinkPreference,
            user: buildUserData({ creator: user } as any),
            venue: {
                id: venue.id,
                name: venue.name,
                addressLine1: venue.addressLine1,
                area: venue.area,
                city: venue.city,
                category: venue.category,
            },
        };

        // Emit socket event for real-time feed updates
        try {
            const { io } = require('../server');
            io.emit('party_plan_created', responseData);
        } catch (socketErr) {
            logger.warn('Socket emission failed for party_plan_created:', socketErr);
        }

        res.status(201).json({
            success: true,
            message: 'Party plan created successfully and is now live!',
            data: responseData,
            razorpayOrderId: order.id,
            amount: order.amount,
            currency: order.currency,
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123'
        });

        // ── Push notification ──────────────────────────────────────────
        // For private plans: notify each invited user.
        // For public plans: notify all users in the same city.
        setImmediate(async () => {
            try {
                const isPrivate = parsedVisibility === PartyPlanVisibility.PRIVATE || parsedVisibility === PartyPlanVisibility.BOTH;
                const isPublic = parsedVisibility === PartyPlanVisibility.PUBLIC || parsedVisibility === PartyPlanVisibility.BOTH;
                const hostName = `${user.firstName} ${user.lastName}`.trim();
                const venueName = venue.name;
                const venueCity = venue.city;
                const notifData = {
                    type: 'new_party_plan',
                    partyPlanId: partyPlan.id,
                    venueId: venueId,
                    hostId: userId,
                };

                // 1. Notify invited users for Private / Both
                if (isPrivate && Array.isArray(selectedUsers) && selectedUsers.length > 0) {
                    const invitedUsers = await User.findAll({
                        where: { id: { [Op.in]: selectedUsers } },
                        attributes: ['id', 'fcmToken'],
                    });
                    const privateTokens = invitedUsers
                        .map((u: any) => u.fcmToken)
                        .filter((t: any) => t && t.trim() !== '') as string[];

                    if (privateTokens.length > 0) {
                        await sendMulticastPushNotification(privateTokens, {
                            title: `🎉 Private Invitation!`,
                            body: `${hostName} has invited you privately for "${partyPlan.message}".`,
                            data: notifData,
                        });
                    }
                }

                // 2. Notify other users in the same city for Public / Both
                if (isPublic && venueCity) {
                    const { getEligibleUsersForEventNotification } = require('../services/fcmService');
                    // Exclude creator and invited users (who already received private notification)
                    const excludedUserIds = isPrivate && Array.isArray(selectedUsers) ? selectedUsers : [];
                    const publicTokens = await getEligibleUsersForEventNotification(userId, venueCity, excludedUserIds);

                    if (publicTokens.length > 0) {
                        await sendMulticastPushNotification(publicTokens, {
                            title: `🎉 New Party Plan at ${venueName}`,
                            body: `${hostName} has created a party plan. Tap to view!`,
                            data: notifData,
                        });
                    }
                }
            } catch (pushErr: any) {
                logger.warn('Party plan push notification failed:', pushErr.message);
            }
        });
    } catch (err: any) {
        logger.error('createPartyPlan error:', err);
        res.status(500).json({ success: false, message: 'Failed to create party plan', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/host-pay
// Verify host payment for party plan deposit
// ─────────────────────────────────────────────────────────────────────────────
export const verifyHostPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        const isMockPayment = razorpay_signature === 'mock_signature' ||
                              (razorpay_order_id && (razorpay_order_id as string).startsWith('mock_')) ||
                              (razorpay_order_id && (razorpay_order_id as string).startsWith('order_mock_'));

        if (!isMockPayment && plan.hostRazorpayOrderId !== razorpay_order_id) {
            res.status(400).json({ success: false, message: 'Invalid order ID' });
            return;
        }

        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(razorpay_order_id + '|' + razorpay_payment_id);
        const generatedSignature = hmac.digest('hex');

        if (isMockPayment || generatedSignature === razorpay_signature || razorpay_signature === 'mock_signature') {
            const activeRequests = await PartyPlanRequest.findAll({
                where: {
                    planId: id,
                    status: {
                        [Op.in]: [PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.ACCEPTED]
                    }
                }
            });

            await (plan as any).update({
                hostPaymentStatus: PartyPlanPaymentStatus.PAID,
                hostRazorpayPaymentId: razorpay_payment_id,
                isLive: false, // Once host pays, it is reserved/waiting for joiner
                paymentStatus: 'Awaiting Participant Payment',
            });

            // Send push notification for Host successful payment
            setImmediate(async () => {
                try {
                    const host = await User.findByPk(plan.userId);
                    if (host && host.fcmToken) {
                        await sendMulticastPushNotification([host.fcmToken], {
                            title: '💳 Host Payment Successful',
                            body: `Your ₹${plan.depositAmount || 99} deposit payment was successfully verified.`,
                            data: {
                                type: 'host_payment_successful',
                                partyPlanId: plan.id,
                            },
                        });
                    }
                } catch (pushErr: any) {
                    logger.warn('Failed to send host payment success push:', pushErr.message);
                }
            });

            if (activeRequests.length > 0) {
                let matchSuccessful = false;
                for (const activeReq of activeRequests) {
                    // Host has paid! Now start the 30-minute timer for the Joiner.
                    const timeout = new Date();
                    timeout.setMinutes(timeout.getMinutes() + 30);
                    
                    await activeReq.update({
                        paymentTimeoutAt: timeout,
                    });

                    // Notify participant/joiner that they can now pay or join
                    setImmediate(async () => {
                        try {
                            const joiner = await User.findByPk(activeReq.requesterId);
                            if (joiner && joiner.fcmToken) {
                                await sendMulticastPushNotification([joiner.fcmToken], {
                                    title: plan.paymentType === 'self_pay' ? '🎉 Private Party Plan Invite' : '⚡ Action Required: Pay Deposit',
                                    body: plan.paymentType === 'self_pay'
                                        ? 'The host has paid. Please confirm your invite to join the party!'
                                        : 'The host has paid. Please pay your ₹99 deposit to confirm the booking!',
                                    data: {
                                        type: plan.paymentType === 'self_pay' ? 'participant_payment_required' : 'participant_payment_required',
                                        partyPlanId: plan.id,
                                        requestId: activeReq.id,
                                    },
                                });
                            }
                        } catch (pushErr: any) {
                            logger.warn('Failed to send participant payment required push:', pushErr.message);
                        }
                    });

                    if (activeReq.joinerPaymentStatus === PartyPlanJoinerPaymentStatus.PAID) {
                        matchSuccessful = true;
                        // Both parties have paid! Match success. Keep statuses as PAID (not refunded)
                        await activeReq.update({
                            status: PartyPlanRequestStatus.ACCEPTED,
                            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                        });
                        await plan.update({
                            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
                            status: PartyPlanStatus.INACTIVE,
                            isLive: false,
                            paymentStatus: 'Confirmed',
                        });

                        // Create Booking & Payments
                        await createBookingAndPayments(plan, activeReq);

                        // Reject all other requests now that match is fully confirmed
                        await PartyPlanRequest.update(
                            { status: PartyPlanRequestStatus.REJECTED },
                            {
                                where: {
                                    planId: plan.id,
                                    id: { [Op.ne]: activeReq.id },
                                    status: { [Op.in]: [PartyPlanRequestStatus.PENDING, PartyPlanRequestStatus.PAYMENT_PENDING] }
                                }
                            }
                        );

                        // Notify both about confirmed booking and ticket
                        setImmediate(async () => {
                            try {
                                const joiner = await User.findByPk(activeReq.requesterId);
                                const host = await User.findByPk(plan.userId);
                                const tokens = [host?.fcmToken, joiner?.fcmToken].filter(t => t && t.trim() !== '') as string[];
                                if (tokens.length > 0) {
                                    await sendMulticastPushNotification(tokens, {
                                        title: '🎉 Booking Confirmed!',
                                        body: 'Both payments are complete. Your booking is confirmed!',
                                        data: {
                                            type: 'booking_confirmed',
                                            partyPlanId: plan.id,
                                        },
                                    });
                                }
                                if (host && host.fcmToken) {
                                    await sendMulticastPushNotification([host.fcmToken], {
                                        title: '🎟️ Party Ticket Generated',
                                        body: 'Your booking ticket has been successfully generated. Present it at the venue!',
                                        data: {
                                            type: 'ticket_generated',
                                            partyPlanId: plan.id,
                                        },
                                    });
                                }
                            } catch (pushErr: any) {
                                logger.warn('Failed to send booking confirmed push notifications:', pushErr.message);
                            }
                        });

                        // Emit socket match success
                        try {
                            const { io } = require('../server');
                            io.to(`user_${plan.userId}`).emit('party_plan_match_success', { planId: plan.id, requestId: activeReq.id });
                            io.to(`user_${activeReq.requesterId}`).emit('party_plan_match_success', { planId: plan.id, requestId: activeReq.id });
                        } catch (socketErr) {
                            logger.warn('Socket emission failed for party_plan_match_success:', socketErr);
                        }
                    } else {
                        // Emit host paid to joiner so they know they can pay now
                        try {
                            const { io } = require('../server');
                            io.to(`user_${activeReq.requesterId}`).emit('party_plan_host_paid', { planId: plan.id, requestId: activeReq.id });
                        } catch (socketErr) {
                            logger.warn('Socket emission failed for party_plan_host_paid:', socketErr);
                        }
                    }
                }

                if (matchSuccessful) {
                    res.json({ success: true, message: 'Both paid! Match Successful & Chat Opened 🎉', data: plan });
                } else {
                    res.json({ success: true, message: 'Host payment verified. Joiner 30-minute payment window starts now. ⏳', data: plan });
                }
                return;
            } else {
                res.json({ success: true, message: 'Payment verified. No active join requests currently.', data: plan });
                return;
            }
        } else {
            res.status(400).json({ success: false, message: 'Invalid payment signature' });
        }
    } catch (err: any) {
        logger.error('verifyHostPayment error:', err);
        res.status(500).json({ success: false, message: 'Failed to verify payment', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans
// Get all active party plans (with user + venue details)
// Query: ?venueId=<uuid>  ?status=active|inactive|cancelled  ?page=1  ?limit=20
// ─────────────────────────────────────────────────────────────────────────────
export const getAllPartyPlans = async (req: Request, res: Response): Promise<void> => {
    try {
        const { venueId, status = 'active', page = '1', limit = '20', requesterId } = req.query;

        const where: any = {};
        if (status) {
            const validStatuses = Object.values(PartyPlanStatus);
            if (!validStatuses.includes(status as PartyPlanStatus)) {
                res.status(400).json({ success: false, message: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
                return;
            }
            where.status = status;
        }
        if (status === 'active') {
            where.planDateTime = { [Op.gte]: new Date() };
        }
        if (venueId) where.venueId = venueId;

        if (requesterId) {
            where[Op.or] = [
                { visibility: PartyPlanVisibility.PUBLIC },
                { userId: requesterId },
                {
                    visibility: PartyPlanVisibility.PRIVATE,
                    selectedUsers: {
                        [Op.contains]: [requesterId],
                    },
                },
                {
                    visibility: PartyPlanVisibility.BOTH,
                    [Op.or]: [
                        { selectedUsers: { [Op.contains]: [requesterId] } },
                        // In both, everyone can see it theoretically, but let's just make it public effectively
                    ]
                }
            ];
            // Fix: 'both' effectively means public + targeted invites.
            // If it's both, we treat it as public for the general feed.
            where[Op.or].push({ visibility: PartyPlanVisibility.BOTH });
        } else {
            where[Op.or] = [
                { visibility: PartyPlanVisibility.PUBLIC },
                { visibility: PartyPlanVisibility.BOTH },
            ];
        }

        where.isLive = true; // Only show live plans

        const pageNum = Math.max(1, parseInt(page as string));
        const limitNum = Math.min(100, Math.max(1, parseInt(limit as string)));
        const offset = (pageNum - 1) * limitNum;

        const { count, rows: plans } = await PartyPlan.findAndCountAll({
            where,
            include: [
                {
                    model: User,
                    as: 'creator',
                    attributes: USER_ATTRS,
                    include: [
                        {
                            model: UserProfile,
                            as: 'profile',
                            attributes: PROFILE_ATTRS,
                            required: false,
                        },
                        {
                            model: UserPhoto,
                            as: 'photos',
                            attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'],
                            required: false,
                        },
                    ],
                },
                {
                    model: Venue,
                    as: 'venue',
                    attributes: VENUE_ATTRS,
                    include: [
                        {
                            model: VenueImage,
                            as: 'images',
                            attributes: ['id', 'filePath', 'imageType', 'isPrimary'],
                            where: { imageType: 'cover', isPrimary: true },
                            required: false,
                        }
                    ],
                },
            ],
            order: [['createdAt', 'DESC']],
            limit: limitNum,
            offset,
        });

        const data = plans.map(p => ({
            id: p.id,
            status: p.status,
            visibility: p.visibility,
            selectedUsers: p.selectedUsers,
            message: p.message,
            planDateTime: p.planDateTime,
            createdAt: p.createdAt,
            hostPaymentStatus: p.hostPaymentStatus,
            hostRazorpayOrderId: p.hostRazorpayOrderId,
            isLive: p.isLive,
            depositAmount: p.depositAmount,
            mobileNumber: p.mobileNumber,
            optionalMobileNumber: p.optionalMobileNumber,
            expiresAt: p.expiresAt,
            paymentStatus: p.paymentStatus,
            foodPreference: p.foodPreference,
            drinkPreference: p.drinkPreference,
            user: buildUserData(p),
            venue: buildVenueData(p),
        }));

        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
        res.json({
            success: true,
            total: count,
            page: pageNum,
            limit: limitNum,
            pages: Math.ceil(count / limitNum),
            data,
        });
    } catch (err: any) {
        logger.error('getAllPartyPlans error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch party plans', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/user/:userId
// Get all plans posted by a specific user
// Query: ?status=active|inactive|cancelled
// ─────────────────────────────────────────────────────────────────────────────
export const getPlansByUser = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;
        const { status } = req.query;

        // Verify user exists
        const user = await User.findByPk(userId, { attributes: USER_ATTRS });
        if (!user) {
            res.status(404).json({ success: false, message: 'User not found' });
            return;
        }

        const where: any = { userId };
        if (status) {
            const validStatuses = Object.values(PartyPlanStatus);
            if (!validStatuses.includes(status as PartyPlanStatus)) {
                res.status(400).json({ success: false, message: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
                return;
            }
            where.status = status;
        }
        if (status === 'active') {
            where.planDateTime = { [Op.gte]: new Date() };
        }

        const plans = await PartyPlan.findAll({
            where,
            include: [
                {
                    model: User,
                    as: 'creator',
                    attributes: USER_ATTRS,
                    include: [
                        { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                        { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
                    ],
                },
                {
                    model: Venue,
                    as: 'venue',
                    attributes: VENUE_ATTRS,
                    include: [
                        {
                            model: VenueImage,
                            as: 'images',
                            attributes: ['id', 'filePath', 'imageType', 'isPrimary'],
                            where: { imageType: 'cover', isPrimary: true },
                            required: false,
                        }
                    ],
                },
            ],
            order: [['createdAt', 'DESC']],
        });

        const data = plans.map(p => ({
            id: p.id,
            status: p.status,
            visibility: p.visibility,
            selectedUsers: p.selectedUsers,
            message: p.message,
            planDateTime: p.planDateTime,
            createdAt: p.createdAt,
            hostPaymentStatus: p.hostPaymentStatus,
            hostRazorpayOrderId: p.hostRazorpayOrderId,
            isLive: p.isLive,
            depositAmount: p.depositAmount,
            mobileNumber: p.mobileNumber,
            optionalMobileNumber: p.optionalMobileNumber,
            expiresAt: p.expiresAt,
            paymentStatus: p.paymentStatus,
            foodPreference: p.foodPreference,
            drinkPreference: p.drinkPreference,
            user: buildUserData(p),
            venue: buildVenueData(p),
        }));

        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
        res.json({
            success: true,
            userId,
            total: plans.length,
            data,
        });
    } catch (err: any) {
        logger.error('getPlansByUser error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch user plans', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/:id
// Get a single party plan by ID
// ─────────────────────────────────────────────────────────────────────────────
export const getPartyPlanById = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;

        const plan = await PartyPlan.findByPk(id, {
            include: [
                {
                    model: User,
                    as: 'creator',
                    attributes: USER_ATTRS,
                    include: [
                        { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                        { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
                    ],
                },
                {
                    model: Venue,
                    as: 'venue',
                    attributes: VENUE_ATTRS,
                    include: [
                        {
                            model: VenueImage,
                            as: 'images',
                            attributes: ['id', 'filePath', 'imageType', 'isPrimary'],
                            where: { imageType: 'cover', isPrimary: true },
                            required: false,
                        }
                    ],
                },
            ],
        });

        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        res.json({
            success: true,
            data: {
                id: plan.id,
                status: plan.status,
                visibility: plan.visibility,
                selectedUsers: plan.selectedUsers,
                message: plan.message,
                planDateTime: plan.planDateTime,
                createdAt: plan.createdAt,
                updatedAt: plan.updatedAt,
                hostPaymentStatus: plan.hostPaymentStatus,
                hostRazorpayOrderId: plan.hostRazorpayOrderId,
                isLive: plan.isLive,
                depositAmount: plan.depositAmount,
                mobileNumber: plan.mobileNumber,
                optionalMobileNumber: plan.optionalMobileNumber,
                expiresAt: plan.expiresAt,
                paymentStatus: plan.paymentStatus,
                foodPreference: plan.foodPreference,
                drinkPreference: plan.drinkPreference,
                user: buildUserData(plan),
                venue: buildVenueData(plan),
            },
        });
    } catch (err: any) {
        logger.error('getPartyPlanById error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch party plan', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/mobile/party-plans/:id/status
// Update plan status (cancel a plan etc.)
// Body: { userId, status }
// ─────────────────────────────────────────────────────────────────────────────
export const updatePartyPlanStatus = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { userId, status } = req.body;

        if (!userId || !status) {
            res.status(400).json({ success: false, message: 'userId and status are required' });
            return;
        }

        const validStatuses = Object.values(PartyPlanStatus);
        if (!validStatuses.includes(status as PartyPlanStatus)) {
            res.status(400).json({ success: false, message: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
            return;
        }

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        // Only the creator can update the status
        if (plan.userId !== userId) {
            res.status(403).json({ success: false, message: 'You are not authorized to update this plan' });
            return;
        }

        await (plan as any).update({ status });

        res.json({
            success: true,
            message: `Plan status updated to "${status}"`,
            data: { id: plan.id, status },
        });
    } catch (err: any) {
        logger.error('updatePartyPlanStatus error:', err);
        res.status(500).json({ success: false, message: 'Failed to update plan status', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/mobile/party-plans/:id
// Delete a party plan (only by creator)
// Body: { userId }
// ─────────────────────────────────────────────────────────────────────────────
export const deletePartyPlan = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { userId } = req.body;

        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (plan.userId !== userId) {
            res.status(403).json({ success: false, message: 'You are not authorized to delete this plan' });
            return;
        }

        await plan.destroy();

        // Emit socket event to notify other clients to remove it from feed
        try {
            const { io } = require('../server');
            io.emit('party_plan_deleted', { planId: id });
        } catch (socketErr) {
            logger.warn('Socket emission failed for party_plan_deleted on destroy:', socketErr);
        }

        res.json({ success: true, message: 'Party plan deleted successfully' });
    } catch (err: any) {
        logger.error('deletePartyPlan error:', err);
        res.status(500).json({ success: false, message: 'Failed to delete party plan', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/requests
// Request to join a party plan
// ─────────────────────────────────────────────────────────────────────────────
export const createPartyPlanRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { userId } = req.body;

        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

        const plan = await PartyPlan.findByPk(id);
        if (!plan || !plan.isLive) {
            res.status(404).json({ success: false, message: 'Live Party plan not found' });
            return;
        }

        if (plan.userId === userId) {
            res.status(400).json({ success: false, message: 'You cannot request to join your own plan' });
            return;
        }

        if (plan.visibility === PartyPlanVisibility.PRIVATE) {
            const isInvited = plan.selectedUsers && plan.selectedUsers.includes(userId);
            if (!isInvited) {
                res.status(403).json({ success: false, message: 'You are not invited to this private party plan' });
                return;
            }
        }

        const existingReq = await PartyPlanRequest.findOne({ where: { planId: id, requesterId: userId } });
        if (existingReq) {
            res.status(400).json({ success: false, message: 'You have already requested to join this plan' });
            return;
        }

        const newReq = await PartyPlanRequest.create({
            planId: id,
            requesterId: userId,
            status: PartyPlanRequestStatus.PENDING,
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
            latLangCheckIn: false,
        });

        res.status(201).json({ success: true, message: 'Request sent successfully!', data: newReq });
    } catch (err: any) {
        logger.error('createPartyPlanRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to send request', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/:id/requests
// Get all requests for a specific party plan (Host only)
// ─────────────────────────────────────────────────────────────────────────────
export const getPartyPlanRequests = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { userId } = req.query; // Host's user id

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (plan.userId !== userId) {
            res.status(403).json({ success: false, message: 'Only the host can view requests' });
            return;
        }

        const requests = await PartyPlanRequest.findAll({
            where: { planId: id },
            include: [
                {
                    model: User,
                    as: 'requester',
                    attributes: USER_ATTRS,
                    include: [
                        { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                        { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
                    ],
                }
            ],
            order: [['createdAt', 'DESC']],
        });

        const data = requests.map(r => {
            const reqData = r.toJSON() as any;
            reqData.isInvite = !!(plan.selectedUsers && plan.selectedUsers.includes(r.requesterId));
            if (reqData.requester) {
                let photoUrl = reqData.requester.profileImageUrl ?? null;
                if (reqData.requester.photos && reqData.requester.photos.length > 0) {
                    const primary = reqData.requester.photos.find((p: any) => p.isPrimary) || reqData.requester.photos[0];
                    if (primary && primary.filePath) {
                        photoUrl = '/' + primary.filePath.replace(/\\/g, '/');
                    }
                }
                reqData.requester = {
                    id: reqData.requester.id,
                    firstName: reqData.requester.firstName,
                    lastName: reqData.requester.lastName,
                    profilePhotoUrl: photoUrl,
                    bio: reqData.requester.profile?.bio ?? null,
                    city: reqData.requester.profile?.city ?? null,
                };
            }
            return reqData;
        });

        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
        res.json({ success: true, data });
    } catch (err: any) {
        logger.error('getPartyPlanRequests error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch requests', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/accept
// Accept a join request and generate Razorpay order for joiner
// ─────────────────────────────────────────────────────────────────────────────
export const acceptPartyPlanRequest = async (req: Request, res: Response): Promise<void> => {
    try {
        const { reqId } = req.params;
        const { userId } = req.body; // Host's userId

        const request = await PartyPlanRequest.findByPk(reqId, { include: [{ model: PartyPlan, as: 'plan' }] });
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        const plan = (request as any).plan as PartyPlan;
        if (plan.userId !== userId) {
            res.status(403).json({ success: false, message: 'Only the host can accept requests' });
            return;
        }

        // Check if there is already an active unpaid request on this plan
        const activeReq = await PartyPlanRequest.findOne({
            where: {
                planId: plan.id,
                status: PartyPlanRequestStatus.PAYMENT_PENDING,
                paymentTimeoutAt: { [Op.gt]: new Date() }
            }
        });
        if (activeReq) {
            res.status(400).json({
                success: false,
                message: 'You already accepted another request. Please complete the payment or wait for the 30-minute window to expire.'
            });
            return;
        }

        // Clean up any expired requests in the DB for this plan in real-time
        const expiredReqs = await PartyPlanRequest.findAll({
            where: {
                planId: plan.id,
                status: PartyPlanRequestStatus.PAYMENT_PENDING,
                paymentTimeoutAt: { [Op.lte]: new Date() }
            }
        });
        for (const expiredReq of expiredReqs) {
            await expiredReq.update({ status: PartyPlanRequestStatus.PAYMENT_FAILED });
        }

        const hostAlreadyPaid = plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;

        if (plan.paymentType === 'self_pay') {
            if (hostAlreadyPaid) {
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                });

                await plan.update({
                    status: PartyPlanStatus.INACTIVE,
                    isLive: false,
                    paymentStatus: 'Confirmed',
                });

                await createBookingAndPayments(plan, request);

                await PartyPlanRequest.update(
                    { status: PartyPlanRequestStatus.REJECTED },
                    {
                        where: {
                            planId: plan.id,
                            id: { [Op.ne]: request.id },
                            status: { [Op.in]: [PartyPlanRequestStatus.PENDING, PartyPlanRequestStatus.PAYMENT_PENDING] }
                        }
                    }
                );

                setImmediate(async () => {
                    try {
                        const joiner = await User.findByPk(request.requesterId);
                        const host = await User.findByPk(plan.userId);
                        const tokens = [host?.fcmToken, joiner?.fcmToken].filter(t => t && t.trim() !== '') as string[];
                        if (tokens.length > 0) {
                            await sendMulticastPushNotification(tokens, {
                                title: '🎉 Booking Confirmed!',
                                body: 'Your booking has been confirmed! (Paid by the Host)',
                                data: {
                                    type: 'booking_confirmed',
                                    partyPlanId: plan.id,
                                },
                            });
                        }
                    } catch (pushErr: any) {
                        logger.warn('Failed to send booking confirmed push notifications:', pushErr.message);
                    }
                });

                try {
                    const { io } = require('../server');
                    io.to(`user_${plan.userId}`).emit('party_plan_match_success', { planId: plan.id, requestId: request.id });
                    io.to(`user_${request.requesterId}`).emit('party_plan_match_success', { planId: plan.id, requestId: request.id });
                    io.emit('party_plan_deleted', { planId: plan.id });
                } catch (socketErr) {
                    logger.warn('Socket emission failed for party_plan_match_success:', socketErr);
                }

                res.json({ success: true, message: 'Request accepted & booking confirmed immediately (Self-Paid) 🎉', data: request });
                return;
            } else {
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                });

                await plan.update({
                    isLive: false,
                    paymentStatus: 'Awaiting Host Payment',
                });

                try {
                    const { io } = require('../server');
                    io.to(`user_${request.requesterId}`).emit('party_plan_request_accepted', {
                        requestId: request.id,
                        planId: plan.id,
                        hostAlreadyPaid: false,
                        hostRazorpayOrderId: plan.hostRazorpayOrderId,
                        hostAmount: Math.round(plan.depositAmount * 100),
                        hostCurrency: 'INR',
                        joinerRazorpayOrderId: null,
                        joinerAmount: 0,
                        joinerCurrency: 'INR',
                    });
                } catch (socketErr) {
                    logger.warn('Socket emission failed for acceptPartyPlanRequest:', socketErr);
                }

                res.json({ success: true, message: 'Request accepted. Waiting for Host to pay deposit.', data: request });
                return;
            }
        }

        // Generate Razorpay Order for the Joiner
        const joinerOptions = {
            amount: Math.round(plan.depositAmount * 100),
            currency: 'INR',
            receipt: `ppreq_${Date.now()}`
        };
        let joinerOrder: any = { id: `order_mock_${Date.now()}`, amount: joinerOptions.amount, currency: joinerOptions.currency };
        if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id') {
            try {
                joinerOrder = await razorpay.orders.create(joinerOptions);
            } catch (err: any) {
                logger.warn('Razorpay joiner order failed, using mock: ' + err.message);
            }
        }

        let hostOrder: any = null;
        if (!hostAlreadyPaid) {
            // Generate Razorpay Order for the Host since they haven't paid yet
            const hostOptions = {
                amount: Math.round(plan.depositAmount * 100),
                currency: 'INR',
                receipt: `pphost_${Date.now()}`
            };
            hostOrder = { id: `order_mock_${Date.now()}`, amount: hostOptions.amount, currency: hostOptions.currency };
            if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id') {
                try {
                    hostOrder = await razorpay.orders.create(hostOptions);
                } catch (err: any) {
                    logger.warn('Razorpay host order failed, using mock: ' + err.message);
                }
            }
        }

        const timeout = new Date();
        timeout.setMinutes(timeout.getMinutes() + 30);

        // Mark request as PAYMENT_PENDING.
        await request.update({
            status: PartyPlanRequestStatus.PAYMENT_PENDING,
            joinerRazorpayOrderId: joinerOrder.id,
            paymentTimeoutAt: timeout, // Reset for Joiner when Host pays
            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
        });

        // Reserve the plan while waiting for payment
        await plan.update({
            isLive: false,
            hostPaymentStatus: hostAlreadyPaid ? PartyPlanPaymentStatus.PAID : PartyPlanPaymentStatus.UNPAID,
            hostRazorpayOrderId: hostOrder ? hostOrder.id : plan.hostRazorpayOrderId,
            paymentStatus: hostAlreadyPaid ? 'Awaiting Participant Payment' : 'Awaiting Host Payment',
        });

        // Emit socket events
        try {
            const { io } = require('../server');
            
            // Notify joiner
            io.to(`user_${request.requesterId}`).emit('party_plan_request_accepted', {
                requestId: request.id,
                planId: plan.id,
                hostAlreadyPaid,
                hostRazorpayOrderId: hostOrder ? hostOrder.id : null,
                hostAmount: hostOrder ? hostOrder.amount : null,
                hostCurrency: hostOrder ? hostOrder.currency : null,
                joinerRazorpayOrderId: joinerOrder.id,
                joinerAmount: joinerOrder.amount,
                joinerCurrency: joinerOrder.currency,
            });

            // Remove from global feeds (since it's reserved)
            io.emit('party_plan_deleted', { planId: plan.id });
        } catch (socketErr) {
            logger.warn('Socket emission failed for acceptPartyPlanRequest:', socketErr);
        }

        // Notify users
        setImmediate(async () => {
            try {
                const joiner = await User.findByPk(request.requesterId);
                if (joiner && joiner.fcmToken) {
                    await sendMulticastPushNotification([joiner.fcmToken], {
                        title: '🎉 Request Accepted!',
                        body: 'Your join request was accepted by the host. Get ready to pay!',
                        data: {
                            type: 'party_plan_request_accepted',
                            partyPlanId: plan.id,
                            requestId: request.id,
                        },
                    });

                    if (hostAlreadyPaid) {
                        await sendMulticastPushNotification([joiner.fcmToken], {
                            title: '⚡ Action Required: Pay Deposit',
                            body: 'Host has paid. Please pay your ₹99 deposit to confirm the booking!',
                            data: {
                                type: 'participant_payment_required',
                                partyPlanId: plan.id,
                                requestId: request.id,
                            },
                        });
                    }
                }

                if (!hostAlreadyPaid) {
                    const host = await User.findByPk(plan.userId);
                    if (host && host.fcmToken) {
                        await sendMulticastPushNotification([host.fcmToken], {
                            title: '⚡ Action Required: Pay Deposit',
                            body: 'Please pay your ₹99 deposit to lock this match!',
                            data: {
                                type: 'host_payment_required',
                                partyPlanId: plan.id,
                            },
                        });
                    }
                }
            } catch (err: any) {
                logger.warn('Failed to send accept request notifications:', err.message);
            }
        });

        res.json({
            success: true,
            message: hostAlreadyPaid 
                ? 'Request accepted. Plan reserved. Joiner has 30 minutes to pay deposit.' 
                : 'Request accepted. Plan reserved. Host must pay deposit first within 30 minutes.',
            data: {
                request,
                hostRazorpayOrderId: hostOrder ? hostOrder.id : null,
                hostAmount: hostOrder ? hostOrder.amount : null,
                hostCurrency: hostOrder ? hostOrder.currency : null,
                joinerRazorpayOrderId: joinerOrder.id,
                joinerAmount: joinerOrder.amount,
                joinerCurrency: joinerOrder.currency,
            },
        });
    } catch (err: any) {
        logger.error('acceptPartyPlanRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to accept request', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/joiner-pay
// Verify joiner payment
// ─────────────────────────────────────────────────────────────────────────────
export const verifyJoinerPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { reqId } = req.params;
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        const request = await PartyPlanRequest.findByPk(reqId, { include: [{ model: PartyPlan, as: 'plan' }] });
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        if (request.joinerRazorpayOrderId !== razorpay_order_id) {
            res.status(400).json({ success: false, message: 'Invalid order ID' });
            return;
        }

        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(razorpay_order_id + '|' + razorpay_payment_id);
        const generatedSignature = hmac.digest('hex');

        if (generatedSignature === razorpay_signature || razorpay_signature === 'mock_signature') {
            await request.update({
                joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                joinerRazorpayPaymentId: razorpay_payment_id,
            });

            // Send push notification for Joiner successful payment
            setImmediate(async () => {
                try {
                    const joiner = await User.findByPk(request.requesterId);
                    if (joiner && joiner.fcmToken) {
                        await sendMulticastPushNotification([joiner.fcmToken], {
                            title: '💳 Payment Successful',
                            body: 'Your ₹99 deposit payment was successfully verified.',
                            data: {
                                type: 'joiner_payment_successful',
                                partyPlanId: request.planId,
                            },
                        });
                    }
                } catch (pushErr: any) {
                    logger.warn('Failed to send joiner payment success push:', pushErr.message);
                }
            });

            const plan = (request as any).plan as PartyPlan;
            const hostPaid = plan && plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;

            if (hostPaid) {
                // Both parties have paid within 30 minutes! Keep both as PAID (not refunded)
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                });
                await plan.update({
                    hostPaymentStatus: PartyPlanPaymentStatus.PAID,
                    status: PartyPlanStatus.INACTIVE,
                    isLive: false,
                    paymentStatus: 'Confirmed',
                });

                // Create Booking & Payments
                await createBookingAndPayments(plan, request);

                // Reject all other requests now that match is fully confirmed
                await PartyPlanRequest.update(
                    { status: PartyPlanRequestStatus.REJECTED },
                    {
                        where: {
                            planId: plan.id,
                            id: { [Op.ne]: request.id },
                            status: { [Op.in]: [PartyPlanRequestStatus.PENDING, PartyPlanRequestStatus.PAYMENT_PENDING] }
                        }
                    }
                );

                // Notify both about confirmed booking and ticket
                setImmediate(async () => {
                    try {
                        const joiner = await User.findByPk(request.requesterId);
                        const host = await User.findByPk(plan.userId);
                        const tokens = [host?.fcmToken, joiner?.fcmToken].filter(t => t && t.trim() !== '') as string[];
                        if (tokens.length > 0) {
                            await sendMulticastPushNotification(tokens, {
                                title: '🎉 Booking Confirmed!',
                                body: 'Both payments are complete. Your booking is confirmed!',
                                data: {
                                    type: 'booking_confirmed',
                                    partyPlanId: plan.id,
                                },
                            });
                        }
                        if (host && host.fcmToken) {
                            await sendMulticastPushNotification([host.fcmToken], {
                                title: '🎟️ Party Ticket Generated',
                                body: 'Your booking ticket has been successfully generated. Present it at the venue!',
                                data: {
                                    type: 'ticket_generated',
                                    partyPlanId: plan.id,
                                },
                            });
                        }
                    } catch (pushErr: any) {
                        logger.warn('Failed to send booking confirmed push notifications:', pushErr.message);
                    }
                });

                // Emit socket match success
                try {
                    const { io } = require('../server');
                    io.to(`user_${plan.userId}`).emit('party_plan_match_success', { planId: plan.id, requestId: request.id });
                    io.to(`user_${request.requesterId}`).emit('party_plan_match_success', { planId: plan.id, requestId: request.id });
                } catch (socketErr) {
                    logger.warn('Socket emission failed for party_plan_match_success:', socketErr);
                }

                res.json({ success: true, message: 'Both paid! Match Successful & Chat Opened 🎉', data: request });
            } else {
                // Joiner paid, wait for host (though in flow Host should pay first)
                await request.update({
                    status: PartyPlanRequestStatus.PAYMENT_PENDING,
                });

                // Emit joiner paid to host
                try {
                    const { io } = require('../server');
                    io.to(`user_${plan.userId}`).emit('party_plan_joiner_paid', { planId: plan.id, requestId: request.id });
                } catch (socketErr) {
                    logger.warn('Socket emission failed for party_plan_joiner_paid:', socketErr);
                }

                res.json({ success: true, message: 'Payment verified. Waiting for host payment. ⏳', data: request });
            }
        } else {
            res.status(400).json({ success: false, message: 'Invalid payment signature' });
        }
    } catch (err: any) {
        logger.error('verifyJoinerPayment error:', err);
        res.status(500).json({ success: false, message: 'Failed to verify payment', error: err.message });
    }
};

export const confirmSelfPaidJoin = async (req: Request, res: Response): Promise<void> => {
    try {
        const { reqId } = req.params;
        const { userId } = req.body;

        const request = await PartyPlanRequest.findByPk(reqId, { include: [{ model: PartyPlan, as: 'plan' }] });
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        if (request.requesterId !== userId) {
            res.status(403).json({ success: false, message: 'Only the requesting/invited user can confirm this request' });
            return;
        }

        const plan = (request as any).plan as PartyPlan;
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (plan.paymentType !== 'self_pay') {
            res.status(400).json({ success: false, message: 'This plan is not self-paid. Payment is required.' });
            return;
        }

        const hostPaid = plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;

        if (hostPaid) {
            await request.update({
                status: PartyPlanRequestStatus.ACCEPTED,
                joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
            });

            await plan.update({
                status: PartyPlanStatus.INACTIVE,
                isLive: false,
                paymentStatus: 'Confirmed',
            });

            await createBookingAndPayments(plan, request);

            await PartyPlanRequest.update(
                { status: PartyPlanRequestStatus.REJECTED },
                {
                    where: {
                        planId: plan.id,
                        id: { [Op.ne]: request.id },
                        status: { [Op.in]: [PartyPlanRequestStatus.PENDING, PartyPlanRequestStatus.PAYMENT_PENDING] }
                    }
                }
            );

            setImmediate(async () => {
                try {
                    const joiner = await User.findByPk(request.requesterId);
                    const host = await User.findByPk(plan.userId);
                    const tokens = [host?.fcmToken, joiner?.fcmToken].filter(t => t && t.trim() !== '') as string[];
                    if (tokens.length > 0) {
                        await sendMulticastPushNotification(tokens, {
                            title: '🎉 Booking Confirmed!',
                            body: 'Your booking has been confirmed! (Paid by the Host)',
                            data: {
                                type: 'booking_confirmed',
                                partyPlanId: plan.id,
                            },
                        });
                    }
                } catch (pushErr: any) {
                    logger.warn('Failed to send booking confirmed push notifications:', pushErr.message);
                }
            });

            try {
                const { io } = require('../server');
                io.to(`user_${plan.userId}`).emit('party_plan_match_success', { planId: plan.id, requestId: request.id });
                io.to(`user_${request.requesterId}`).emit('party_plan_match_success', { planId: plan.id, requestId: request.id });
                io.emit('party_plan_deleted', { planId: plan.id });
            } catch (socketErr) {
                logger.warn('Socket emission failed for party_plan_match_success:', socketErr);
            }

            res.json({ success: true, message: 'Joined party plan successfully! (Paid by Host) 🎉', data: request });
        } else {
            await request.update({
                status: PartyPlanRequestStatus.ACCEPTED,
                joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
            });

            await plan.update({
                paymentStatus: 'Awaiting Host Payment',
            });

            try {
                const { io } = require('../server');
                io.to(`user_${plan.userId}`).emit('party_plan_joiner_paid', { planId: plan.id, requestId: request.id });
            } catch (socketErr) {
                logger.warn('Socket emission failed for party_plan_joiner_paid:', socketErr);
            }

            res.json({ success: true, message: 'Join confirmed. Waiting for host to complete their payment. ⏳', data: request });
        }
    } catch (err: any) {
        logger.error('confirmSelfPaidJoin error:', err);
        res.status(500).json({ success: false, message: 'Failed to confirm join', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/accept-invite
// Accept an invite to a party plan
// ─────────────────────────────────────────────────────────────────────────────
export const acceptPartyPlanInvite = async (req: Request, res: Response): Promise<void> => {
    try {
        const { reqId } = req.params;
        const { userId } = req.body;

        const request = await PartyPlanRequest.findByPk(reqId, { include: [{ model: PartyPlan, as: 'plan' }] });
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        if (request.requesterId !== userId) {
            res.status(403).json({ success: false, message: 'Only the invited user can accept this invite' });
            return;
        }

        const plan = (request as any).plan as PartyPlan;
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        // Check if there is already an active unpaid request on this plan (another user took it)
        const activeReq = await PartyPlanRequest.findOne({
            where: {
                planId: plan.id,
                id: { [Op.ne]: request.id },
                status: PartyPlanRequestStatus.PAYMENT_PENDING,
                paymentTimeoutAt: { [Op.gt]: new Date() }
            }
        });
        if (activeReq) {
            res.status(400).json({
                success: false,
                message: 'This plan is currently reserved by another user. Try again later.'
            });
            return;
        }

        const hostPaid = plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;

        if (plan.paymentType === 'self_pay') {
            if (hostPaid) {
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                });
                await plan.update({
                    status: PartyPlanStatus.INACTIVE,
                    isLive: false,
                    paymentStatus: 'Confirmed',
                });
                await createBookingAndPayments(plan, request);

                await PartyPlanRequest.update(
                    { status: PartyPlanRequestStatus.REJECTED },
                    {
                        where: {
                            planId: plan.id,
                            id: { [Op.ne]: request.id },
                            status: { [Op.in]: [PartyPlanRequestStatus.PENDING, PartyPlanRequestStatus.PAYMENT_PENDING] }
                        }
                    }
                );

                res.json({ success: true, message: 'Joined party plan successfully! (Paid by Host) 🎉', data: request });
            } else {
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                });
                await plan.update({ paymentStatus: 'Awaiting Host Payment' });
                res.json({ success: true, message: 'Join confirmed. Waiting for host to complete their payment. ⏳', data: request });
            }
        } else {
            // SPLIT PAY
            const timeout = new Date();
            timeout.setMinutes(timeout.getMinutes() + 30);

            await request.update({
                status: PartyPlanRequestStatus.PAYMENT_PENDING,
                paymentTimeoutAt: timeout,
            });

            await plan.update({
                isLive: false, // reserved
            });

            res.json({ success: true, message: 'Invite accepted! You have 30 minutes to pay the deposit.', data: request });
        }
    } catch (err: any) {
        logger.error('acceptPartyPlanInvite error:', err);
        res.status(500).json({ success: false, message: 'Failed to accept invite', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/cancel
// Cancel a party plan (by host)
// ─────────────────────────────────────────────────────────────────────────────
export const cancelPartyPlan = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const { userId } = req.body;

        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (plan.userId !== userId) {
            res.status(403).json({ success: false, message: 'Only the host can cancel the plan' });
            return;
        }

        await (plan as any).update({ status: PartyPlanStatus.CANCELLED, isLive: false });

        // Cancel all pending or accepted requests
        await PartyPlanRequest.update(
            { status: PartyPlanRequestStatus.CANCELLED },
            { where: { planId: plan.id, status: { [Op.in]: [PartyPlanRequestStatus.PENDING, PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.ACCEPTED] } } }
        );

        // TODO: Initiate refund for host and any joiner if applicable

        // Emit socket event to notify other clients to remove it from feed
        try {
            const { io } = require('../server');
            io.emit('party_plan_deleted', { planId: plan.id });
        } catch (socketErr) {
            logger.warn('Socket emission failed for party_plan_deleted on cancel:', socketErr);
        }

        res.json({ success: true, message: 'Party plan cancelled' });
    } catch (err: any) {
        logger.error('cancelPartyPlan error:', err);
        res.status(500).json({ success: false, message: 'Failed to cancel plan', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────
function buildUserData(plan: PartyPlan) {
    const creator = (plan as any).creator;
    if (!creator) return null;

    let photoUrl = creator.profileImageUrl ?? null;
    if (creator.photos && creator.photos.length > 0) {
        const primary = creator.photos.find((p: any) => p.isPrimary) || creator.photos[0];
        if (primary && primary.filePath) {
            photoUrl = '/' + primary.filePath.replace(/\\/g, '/');
        }
    }

    return {
        id: creator.id,
        firstName: creator.firstName,
        lastName: creator.lastName,
        email: creator.email,
        phone: creator.phone,
        profilePhotoUrl: photoUrl,
        bio: creator.profile?.bio ?? null,
        occupation: creator.profile?.occupation ?? null,
        gender: creator.profile?.gender ?? null,
        city: creator.profile?.city ?? null,
    };
}

function buildVenueData(plan: PartyPlan) {
    const venue = (plan as any).venue;
    if (!venue) return null;

    let coverImageUrl = null;
    if (venue.images && venue.images.length > 0) {
        const coverImage = venue.images[0];
        if (coverImage && coverImage.filePath) {
            coverImageUrl = '/' + coverImage.filePath.replace(/\\/g, '/');
        }
    }

    return {
        id: venue.id,
        name: venue.name,
        addressLine1: venue.addressLine1,
        area: venue.area,
        city: venue.city,
        category: venue.category,
        phone: venue.phone,
        coverChargeMale: venue.coverChargeMale,
        coverChargeFemale: venue.coverChargeFemale,
        coverImageUrl: coverImageUrl,
    };
}

export const getJoinerRequests = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId } = req.params;

        const requests = await PartyPlanRequest.findAll({
            where: { requesterId: userId },
            include: [
                {
                    model: PartyPlan,
                    as: 'plan',
                    include: [
                        { model: User, as: 'creator', include: [{ model: UserProfile, as: 'profile' }, { model: UserPhoto, as: 'photos' }] },
                        { model: Venue, as: 'venue', include: [{ model: VenueImage, as: 'images' }] }
                    ]
                }
            ],
            order: [['createdAt', 'DESC']],
        });

        const formatted = requests.map(reqItem => {
            const plan = (reqItem as any).plan;
            return {
                id: reqItem.id,
                planId: reqItem.planId,
                status: reqItem.status,
                joinerPaymentStatus: reqItem.joinerPaymentStatus,
                joinerRazorpayOrderId: reqItem.joinerRazorpayOrderId,
                paymentTimeoutAt: reqItem.paymentTimeoutAt,
                createdAt: reqItem.createdAt,
                plan: plan ? {
                    id: plan.id,
                    message: plan.message,
                    planDateTime: plan.planDateTime,
                    hostPaymentStatus: plan.hostPaymentStatus,
                    hostRazorpayOrderId: plan.hostRazorpayOrderId,
                    isLive: plan.isLive,
                    depositAmount: plan.depositAmount,
                    mobileNumber: plan.mobileNumber,
                    optionalMobileNumber: plan.optionalMobileNumber,
                    expiresAt: plan.expiresAt,
                    paymentStatus: plan.paymentStatus,
                    user: buildUserData(plan),
                    venue: buildVenueData(plan),
                } : null
            };
        });

        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
        res.status(200).json({ success: true, data: formatted });
    } catch (err: any) {
        logger.error('getJoinerRequests error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch joiner requests', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/initiate-host-payment
// ─────────────────────────────────────────────────────────────────────────────
export const initiateHostPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { id } = req.params;
        const plan = await PartyPlan.findByPk(id);
        if (!plan) {
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID) {
            res.status(200).json({
                success: true,
                message: 'Host payment already completed',
                alreadyPaid: true,
            });
            return;
        }

        const amount = plan.paymentType === 'self_pay' ? 198 : 99; // deposit amount
        const options = {
            amount: amount * 100, // in paise
            currency: 'INR',
            receipt: `receipt_host_plan_${plan.id}`,
        };

        let order: any;
        const hasRazorpayKeys = process.env.RAZORPAY_KEY_ID && 
                                process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id' && 
                                process.env.RAZORPAY_KEY_ID !== 'rzp_test_123';
        if (hasRazorpayKeys) {
            try {
                order = await razorpay.orders.create(options);
            } catch (err: any) {
                logger.error('Razorpay host order creation failed, falling back to mock:', err);
                order = { id: `order_mock_${Date.now()}_${Math.random().toString(36).substring(2, 10)}` };
            }
        } else {
            order = { id: `order_mock_${Date.now()}_${Math.random().toString(36).substring(2, 10)}` };
        }

        await (plan as any).update({
            hostRazorpayOrderId: order.id,
        });

        res.status(200).json({
            success: true,
            razorpayOrderId: order.id,
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
            amount: amount,
        });
    } catch (err: any) {
        logger.error('initiateHostPayment error:', err);
        res.status(500).json({ success: false, message: 'Failed to initiate host payment', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/initiate-joiner-payment
// ─────────────────────────────────────────────────────────────────────────────
export const initiateJoinerPayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { reqId } = req.params;
        const request = await PartyPlanRequest.findByPk(reqId, {
            include: [{ model: PartyPlan, as: 'plan' }]
        });
        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }
        
        const plan = (request as any).plan;

        if (request.joinerPaymentStatus === PartyPlanJoinerPaymentStatus.PAID) {
            res.status(200).json({
                success: true,
                message: 'Joiner payment already completed',
                alreadyPaid: true,
            });
            return;
        }

        const amount = plan?.depositAmount ? Number(plan.depositAmount) : 99; // dynamic joiner deposit amount
        const options = {
            amount: amount * 100, // in paise
            currency: 'INR',
            receipt: `receipt_joiner_req_${request.id}`,
        };

        let order: any;
        const hasRazorpayKeys = process.env.RAZORPAY_KEY_ID && 
                                process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id' && 
                                process.env.RAZORPAY_KEY_ID !== 'rzp_test_123';
        if (hasRazorpayKeys) {
            try {
                order = await razorpay.orders.create(options);
            } catch (err: any) {
                logger.error('Razorpay joiner order creation failed, falling back to mock:', err);
                order = { id: `order_mock_${Date.now()}_${Math.random().toString(36).substring(2, 10)}` };
            }
        } else {
            order = { id: `order_mock_${Date.now()}_${Math.random().toString(36).substring(2, 10)}` };
        }

        await (request as any).update({
            joinerRazorpayOrderId: order.id,
        });

        res.status(200).json({
            success: true,
            razorpayOrderId: order.id,
            razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
            amount: amount,
        });
    } catch (err: any) {
        logger.error('initiateJoinerPayment error:', err);
        res.status(500).json({ success: false, message: 'Failed to initiate joiner payment', error: err.message });
    }
};
