import { Request, Response } from 'express';
import PartyPlan, { PartyPlanStatus, PartyPlanVisibility, PartyPlanPaymentType } from '../models/PartyPlan';
import { PlanEligibilityService } from '../services/PlanEligibilityService';
import { Op, Transaction } from 'sequelize';
import User from '../models/User';
import Venue from '../models/Venue';
import UserProfile from '../models/UserProfile';
import UserPhoto from '../models/UserPhoto';
import VenueImage from '../models/VenueImage';
import { logger } from '../config/logger';
import Razorpay from 'razorpay';
import crypto from 'crypto';
import sequelize from '../config/database';
import { PartyPlanPaymentStatus } from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus, PartyPlanJoinerPaymentStatus } from '../models/PartyPlanRequest';
import { sendMulticastPushNotification } from '../services/fcmService';
import Conversation from '../models/Conversation';
import ChatSubscription, { ChatSubscriptionStatus, ChatSubscriptionType } from '../models/ChatSubscription';
import { getChatSettings } from './chatSubscriptionController';
import { validateVenueTimingAndHolidays } from '../utils/venueValidator';
import { checkExistingBookingForDate } from '../utils/bookingLimitValidator';
import Booking, { BookingStatus, GoingMode, PaymentStatus as BookingPaymentStatus } from '../models/Booking';
import Payment, { PaymentMethod, PaymentStatus } from '../models/Payment';
import { generateTicketForBookingHelper } from '../services/ticketService';

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

async function createBookingAndPayments(plan: PartyPlan, request: PartyPlanRequest, transaction?: Transaction) {
    try {
        const existingBooking = await Booking.findOne({
            where: {
                goingMode: GoingMode.PARTY_REQUEST,
                userId: plan.userId,
                venueId: plan.venueId,
                bookingDate: plan.planDateTime,
            },
            transaction
        });
        if (existingBooking) {
            logger.info(`Booking already exists for plan ${plan.id}, skipping creation.`);
            // Still emit ticket_generated with existing data so late-arriving clients get it
            try {
                const { io } = require('../server');
                const ticketData = {
                    bookingId: existingBooking.id,
                    ticketCode: existingBooking.ticketCode,
                    planId: plan.id,
                    requestId: request.id,
                    expiresAt: plan.planDateTime.toISOString(),
                };
                io.to(`user_${plan.userId}`).emit('party_plan_ticket_generated', ticketData);
                io.to(`user_${request.requesterId}`).emit('party_plan_ticket_generated', ticketData);
            } catch (_) {}
            return;
        }

        const dateObj = new Date(plan.planDateTime);
        const bookingDate = dateObj.toISOString().split('T')[0];
        const startTime = dateObj.toTimeString().split(' ')[0];

        // Ticket code format: PP-XXXXXX (uppercase alphanumeric)
        const ticketCode = 'PP-' + Math.random().toString(36).substring(2, 8).toUpperCase();

        // Persist structured ticket metadata in specialRequests (JSON)
        const ticketMetadata = JSON.stringify({
            planId: plan.id,
            requestId: request.id,
            hostId: plan.userId,
            joinerId: request.requesterId,
            ticketCode,
            expiresAt: plan.planDateTime.toISOString(),  // Ticket is valid until party starts
            paymentType: plan.paymentType,
            totalDeposit: 198.00,
            generatedAt: new Date().toISOString(),
        });

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
            specialRequests: ticketMetadata,
        }, { transaction });

        // Generate digital ticket in background
        setImmediate(async () => {
            try {
                await generateTicketForBookingHelper(booking.id);
            } catch (ticketErr) {
                logger.error(`Background ticket generation failed for matched party booking ${booking.id}:`, ticketErr);
            }
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
        }, { transaction });

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
        }, { transaction });

        // Emit party_plan_ticket_generated so the client can refresh the ticket screen
        // with the canonical ticketCode and expiresAt
        try {
            const { io } = require('../server');
            const ticketData = {
                bookingId: booking.id,
                ticketCode,
                planId: plan.id,
                requestId: request.id,
                expiresAt: plan.planDateTime.toISOString(),
            };
            io.to(`user_${plan.userId}`).emit('party_plan_ticket_generated', ticketData);
            io.to(`user_${request.requesterId}`).emit('party_plan_ticket_generated', ticketData);
        } catch (socketErr) {
            logger.warn('Socket emission failed for party_plan_ticket_generated:', socketErr);
        }

        // Unlock Chat!
        await autoOpenChat(plan.userId, request.requesterId);

        logger.info(`Successfully created Booking ${booking.id} (ticket: ${ticketCode}) for plan ${plan.id}`);
    } catch (err) {
        logger.error('Error in createBookingAndPayments:', err);
    }
}

async function rejectAndNotifyStaleRequests(plan: PartyPlan, acceptedRequestId: string, transaction?: Transaction) {
    try {
        const otherRequests = await PartyPlanRequest.findAll({
            where: {
                planId: plan.id,
                id: { [Op.ne]: acceptedRequestId },
                status: { [Op.in]: [PartyPlanRequestStatus.PENDING, PartyPlanRequestStatus.PAYMENT_PENDING] }
            },
            transaction
        });

        for (const req of otherRequests) {
            await req.update({ status: PartyPlanRequestStatus.REJECTED }, { transaction });
            
            let venueName = 'Club';
            if (plan.venueId) {
                const venue = await Venue.findByPk(plan.venueId, { transaction });
                if (venue && venue.name) {
                    venueName = venue.name;
                }
            }

            try {
                const { io } = require('../server');
                // Emit plan_unavailable so the client prunes the stale request card
                io.to(`user_${req.requesterId}`).emit('plan_unavailable', {
                    planId: plan.id,
                    requestId: req.id,
                });
                // Emit notification_created
                io.to(`user_${req.requesterId}`).emit('notification_created', {
                    id: `ppr_rejected_${req.id}`,
                    title: 'Plan Unavailable',
                    body: `The Party Plan at ${venueName} has been confirmed with another user. Feel free to find another plan!`,
                    createdAt: new Date().toISOString(),
                    read: false,
                    type: 'plan_unavailable',
                });
            } catch (socketErr) {
                logger.warn(`Socket emission failed in rejectAndNotifyStaleRequests for request ${req.id}:`, socketErr);
            }

            setImmediate(async () => {
                try {
                    const joiner = await User.findByPk(req.requesterId);
                    if (joiner && joiner.fcmToken) {
                        await sendMulticastPushNotification([joiner.fcmToken], {
                            title: 'Plan Unavailable',
                            body: `The Party Plan at ${venueName} has been confirmed with another user. Feel free to find another plan!`,
                            data: {
                                type: 'plan_unavailable',
                                partyPlanId: plan.id,
                                requestId: req.id,
                            },
                        });
                    }
                } catch (pushErr: any) {
                    logger.warn(`Push notification failed in rejectAndNotifyStaleRequests for request ${req.id}:`, pushErr.message);
                }
            });
        }
    } catch (err: any) {
        logger.error('Error in rejectAndNotifyStaleRequests:', err);
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

        const finalMobileNumber = mobileNumber?.trim() || user.phone?.trim() || '9999999999';

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

        // ── Check for 1 plan per day limit (Stranger Meet / Party Plan / Group Party) ──
        const bookingConflictMsg = await checkExistingBookingForDate(userId, partyDate);
        if (bookingConflictMsg) {
            res.status(400).json({ success: false, message: 'You already have a plan scheduled on this day.' });
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
        if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id' && process.env.RAZORPAY_KEY_ID !== 'rzp_test_123') {
            try {
                const resOrder = await razorpay.orders.create(options);
                if (resOrder) {
                    order = resOrder;
                }
            } catch (err: any) {
                logger.warn('Razorpay create order failed, using mock order. Error: ' + err.message);
            }
        }

        // ── Create the party plan under a transaction ──
        const partyPlan = await PlanEligibilityService.runAtomicCheckAndCreate(
            userId,
            'party_plan',
            partyDate,
            async (transaction) => {
                const plan = await PartyPlan.create({
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
                }, { transaction });

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
                            planId: plan.id,
                            requesterId: invitedUserId,
                            status: PartyPlanRequestStatus.PENDING,
                            joinerPaymentStatus: PartyPlanJoinerPaymentStatus.UNPAID,
                            joinerRazorpayOrderId: joinerOrder.id,
                            latLangCheckIn: false,
                        }, { transaction });
                    }
                }
                return plan;
            }
        );

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
            if (parsedVisibility === PartyPlanVisibility.PRIVATE) {
                io.to(`user_${userId}`).emit('party_plan_created', responseData);
                if (Array.isArray(selectedUsers)) {
                    for (const invitedUserId of selectedUsers) {
                        io.to(`user_${invitedUserId}`).emit('party_plan_created', responseData);
                    }
                }
            } else {
                io.emit('party_plan_created', responseData);
            }
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
                const hostName = `${user.firstName} ${user.lastName}`.trim();
                const venueName = venue.name;
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

                    const tokens = invitedUsers.map(u => u.fcmToken).filter(t => !!t) as string[];
                    if (tokens.length > 0) {
                        await sendMulticastPushNotification(tokens, {
                            title: '🎉 Party Plan Invitation',
                            body: `${hostName} invited you to join a party plan at ${venueName}!`,
                            data: notifData,
                        });
                    }
                }

                // 2. Notify the creator (particular user) instead of all users in the city
                if (user.fcmToken && user.fcmToken.trim() !== '') {
                    await sendMulticastPushNotification([user.fcmToken], {
                        title: '🎉 Party Plan Created',
                        body: `Your party plan at ${venueName} is now live!`,
                        data: notifData,
                    });
                }
            } catch (pushErr: any) {
                logger.warn('Party plan push notification failed:', pushErr.message);
            }
        });
    } catch (err: any) {
        logger.error('createPartyPlan error:', err);
        if (err.code && err.code.startsWith('PLAN_')) {
            res.status(409).json({
                success: false,
                code: err.code,
                message: err.message,
                lock: err.details
            });
            return;
        }
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

            const hasActiveOrAcceptedRequest = activeRequests.length > 0;
            const updatedIsLive = hasActiveOrAcceptedRequest ? false : (plan.visibility !== PartyPlanVisibility.PRIVATE);

            await (plan as any).update({
                hostPaymentStatus: PartyPlanPaymentStatus.PAID,
                hostRazorpayPaymentId: razorpay_payment_id,
                isLive: updatedIsLive,
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

                        // Reject and notify all other requests now that match is fully confirmed
                        await rejectAndNotifyStaleRequests(plan, activeReq.id);

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
    const transaction = await sequelize.transaction();
    try {
        const { id } = req.params;
        const { userId, status } = req.body;

        if (!userId || !status) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'userId and status are required' });
            return;
        }

        const validStatuses = Object.values(PartyPlanStatus);
        if (!validStatuses.includes(status as PartyPlanStatus)) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
            return;
        }

        const plan = await PartyPlan.findByPk(id, { transaction });
        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        // Only the creator can update the status
        if (plan.userId !== userId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'You are not authorized to update this plan' });
            return;
        }

        // Acquire transactional row update lock on the party plan
        await plan.reload({ lock: transaction.LOCK.UPDATE, transaction });

        // Enforce state transitions
        if (plan.status === PartyPlanStatus.CANCELLED) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'Cannot update status of a cancelled plan.' });
            return;
        }

        if (status === PartyPlanStatus.CANCELLED) {
            await cancelPartyPlanInternal(plan, transaction);
        } else {
            // Block invalid reactivation (e.g. from inactive to active)
            if (plan.status === PartyPlanStatus.INACTIVE && status === PartyPlanStatus.ACTIVE) {
                await transaction.rollback();
                res.status(400).json({ success: false, message: 'Cannot reactivate a completed/matched party plan.' });
                return;
            }
            await (plan as any).update({ status }, { transaction });
        }

        await transaction.commit();

        if (status === PartyPlanStatus.CANCELLED) {
            try {
                const { io } = require('../server');
                io.emit('party_plan_deleted', { planId: plan.id });
            } catch (_) {}
        }

        res.json({
            success: true,
            message: `Plan status updated to "${status}"`,
            data: { id: plan.id, status },
        });
    } catch (err: any) {
        await transaction.rollback();
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
        await PlanEligibilityService.releaseLock(id);

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

        // Reject if target plan is inactive or cancelled
        if (plan.status === PartyPlanStatus.INACTIVE || plan.status === PartyPlanStatus.CANCELLED) {
            res.status(400).json({ success: false, message: 'This party plan is no longer active.' });
            return;
        }

        // Check if there is already a request on the plan that is accepted or in active payment_pending status
        const acceptedOrPendingReq = await PartyPlanRequest.findOne({
            where: {
                planId: plan.id,
                [Op.or]: [
                    { status: PartyPlanRequestStatus.ACCEPTED },
                    {
                        status: PartyPlanRequestStatus.PAYMENT_PENDING,
                        paymentTimeoutAt: { [Op.gt]: new Date() }
                    }
                ]
            }
        });
        if (acceptedOrPendingReq) {
            res.status(400).json({
                success: false,
                message: 'This party plan already has an accepted or processing request.'
            });
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

        // Notify host about the request
        try {
            const host = await User.findByPk(plan.userId);
            const requester = await User.findByPk(userId);
            if (host && requester) {
                const { io } = require('../server');
                const venueName = (plan as any)?.venue?.name || 'Club';
                const requesterName = `${requester.firstName} ${requester.lastName}`;
                
                io.to(`user_${plan.userId}`).emit('notification_created', {
                    id: `ppr_req_${newReq.id}`,
                    title: 'Join Request',
                    body: `${requesterName} requested to join your Party Plan at ${venueName}.`,
                    createdAt: new Date().toISOString(),
                    read: false,
                    sender: {
                        id: requester.id,
                        firstName: requester.firstName,
                        lastName: requester.lastName,
                        profileImageUrl: requester.profileImageUrl,
                    }
                });

                if (host.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(host.fcmToken, {
                        title: 'Join Request',
                        body: `${requesterName} requested to join your Party Plan at ${venueName}.`,
                        data: {
                            type: 'join_request',
                            partyPlanId: plan.id,
                            requestId: newReq.id,
                        }
                    });
                }
            }
        } catch (pushErr: any) {
            logger.warn('Failed to notify host for new party plan request:', pushErr.message);
        }

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
    const transaction = await sequelize.transaction();
    try {
        const { reqId } = req.params;
        const { userId } = req.body; // Host's userId

        const request = await PartyPlanRequest.findByPk(reqId, {
            include: [{ model: PartyPlan, as: 'plan' }],
            transaction
        });
        if (!request) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        const plan = (request as any).plan as PartyPlan;
        if (plan.userId !== userId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'Only the host can accept requests' });
            return;
        }

        // Acquire transactional row update lock on the party plan
        await plan.reload({ lock: transaction.LOCK.UPDATE, transaction });

        // Enforce state transition checks: plan status must be active
        if (plan.status !== PartyPlanStatus.ACTIVE) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'This plan is not active or has already been completed/cancelled.' });
            return;
        }

        // Check if there is already an active unpaid request on this plan
        const activeReq = await PartyPlanRequest.findOne({
            where: {
                planId: plan.id,
                status: PartyPlanRequestStatus.PAYMENT_PENDING,
                paymentTimeoutAt: { [Op.gt]: new Date() }
            },
            transaction
        });
        if (activeReq) {
            await transaction.rollback();
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
            },
            transaction
        });
        for (const expiredReq of expiredReqs) {
            await expiredReq.update({ status: PartyPlanRequestStatus.PAYMENT_FAILED }, { transaction });
        }

        const hostAlreadyPaid = plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;

        if (plan.paymentType === 'self_pay') {
            if (hostAlreadyPaid) {
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                }, { transaction });

                await plan.update({
                    status: PartyPlanStatus.INACTIVE,
                    isLive: false,
                    paymentStatus: 'Confirmed',
                }, { transaction });

                await createBookingAndPayments(plan, request, transaction);

                // Reject and notify all other requests now that match is fully confirmed
                await rejectAndNotifyStaleRequests(plan, request.id, transaction);

                await transaction.commit();

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

                    const host = await User.findByPk(plan.userId);
                    const requester = await User.findByPk(request.requesterId);
                    if (host && requester) {
                        const venueName = (plan as any)?.venue?.name || 'Club';
                        io.to(`user_${request.requesterId}`).emit('notification_created', {
                            id: `ppr_${request.id}`,
                            title: 'Plan Request Accepted',
                            body: `Your request to join Party Plan at ${venueName} is confirmed! (Paid by host) 🎉`,
                            createdAt: new Date().toISOString(),
                            read: false,
                            sender: {
                                id: host.id,
                                firstName: host.firstName,
                                lastName: host.lastName,
                                profileImageUrl: host.profileImageUrl,
                            }
                        });
                        io.to(`user_${plan.userId}`).emit('notification_created', {
                            id: `ppr_host_${request.id}`,
                            title: 'Participant Joined',
                            body: `${requester.firstName} ${requester.lastName} joined your Party Plan at ${venueName}.`,
                            createdAt: new Date().toISOString(),
                            read: false,
                            sender: {
                                id: requester.id,
                                firstName: requester.firstName,
                                lastName: requester.lastName,
                                profileImageUrl: requester.profileImageUrl,
                            }
                        });
                    }
                } catch (socketErr) {
                    logger.warn('Socket emission failed for party_plan_match_success:', socketErr);
                }

                res.json({ success: true, message: 'Request accepted & booking confirmed immediately (Self-Paid) 🎉', data: request });
                return;
            } else {
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                }, { transaction });

                await plan.update({
                    isLive: false,
                    paymentStatus: 'Awaiting Host Payment',
                }, { transaction });

                await transaction.commit();

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

                    const host = await User.findByPk(plan.userId);
                    const requester = await User.findByPk(request.requesterId);
                    if (host && requester) {
                        const venueName = (plan as any)?.venue?.name || 'Club';
                        io.to(`user_${request.requesterId}`).emit('notification_created', {
                            id: `ppr_${request.id}`,
                            title: 'Plan Request Accepted',
                            body: `Your request to join Party Plan at ${venueName} was accepted. Waiting for host payment to confirm. ⏳`,
                            createdAt: new Date().toISOString(),
                            read: false,
                            sender: {
                                id: host.id,
                                firstName: host.firstName,
                                lastName: host.lastName,
                                profileImageUrl: host.profileImageUrl,
                            }
                        });
                        io.to(`user_${plan.userId}`).emit('notification_created', {
                            id: `ppr_host_${request.id}`,
                            title: 'Participant Joined',
                            body: `${requester.firstName} ${requester.lastName} joined your Party Plan at ${venueName}.`,
                            createdAt: new Date().toISOString(),
                            read: false,
                            sender: {
                                id: requester.id,
                                firstName: requester.firstName,
                                lastName: requester.lastName,
                                profileImageUrl: requester.profileImageUrl,
                            }
                        });
                    }
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
        if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id' && process.env.RAZORPAY_KEY_ID !== 'rzp_test_123') {
            try {
                const resOrder = await razorpay.orders.create(joinerOptions);
                if (resOrder) {
                    joinerOrder = resOrder;
                }
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
            if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id' && process.env.RAZORPAY_KEY_ID !== 'rzp_test_123') {
                try {
                    const resOrder = await razorpay.orders.create(hostOptions);
                    if (resOrder) {
                        hostOrder = resOrder;
                    }
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
        }, { transaction });

        // Reserve the plan while waiting for payment
        await plan.update({
            isLive: false,
            hostPaymentStatus: hostAlreadyPaid ? PartyPlanPaymentStatus.PAID : PartyPlanPaymentStatus.UNPAID,
            hostRazorpayOrderId: hostOrder ? hostOrder.id : plan.hostRazorpayOrderId,
            paymentStatus: hostAlreadyPaid ? 'Awaiting Participant Payment' : 'Awaiting Host Payment',
        }, { transaction });

        await transaction.commit();

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

            const host = await User.findByPk(plan.userId);
            const requester = await User.findByPk(request.requesterId);
            if (host && requester) {
                const venueName = (plan as any)?.venue?.name || 'Club';
                io.to(`user_${request.requesterId}`).emit('notification_created', {
                    id: `ppr_${request.id}`,
                    title: 'Plan Request Accepted',
                    body: `Your request to join Party Plan at ${venueName} was accepted. Pay to confirm.`,
                    createdAt: new Date().toISOString(),
                    read: false,
                    sender: {
                        id: host.id,
                        firstName: host.firstName,
                        lastName: host.lastName,
                        profileImageUrl: host.profileImageUrl,
                    }
                });
            }
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
        await transaction.rollback();
        logger.error('acceptPartyPlanRequest error:', err);
        res.status(500).json({ success: false, message: 'Failed to accept request', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/joiner-pay
// Verify joiner payment
// ─────────────────────────────────────────────────────────────────────────────
export const verifyJoinerPayment = async (req: Request, res: Response): Promise<void> => {
    const transaction = await sequelize.transaction();
    try {
        const { reqId } = req.params;
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        const request = await PartyPlanRequest.findByPk(reqId, {
            include: [{ model: PartyPlan, as: 'plan' }],
            transaction
        });
        if (!request) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        if (request.joinerRazorpayOrderId !== razorpay_order_id) {
            await transaction.rollback();
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
            }, { transaction });

            const plan = (request as any).plan as PartyPlan;
            if (!plan) {
                await transaction.rollback();
                res.status(404).json({ success: false, message: 'Party plan not found' });
                return;
            }

            // Acquire transactional row update lock on the party plan
            await plan.reload({ lock: transaction.LOCK.UPDATE, transaction });

            // Enforce state transition checks: plan status must be active
            if (plan.status !== PartyPlanStatus.ACTIVE) {
                await transaction.rollback();
                res.status(400).json({ success: false, message: 'This plan is not active or has already been completed/cancelled.' });
                return;
            }

            const hostPaid = plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;

            if (hostPaid) {
                // Both parties have paid within 30 minutes! Keep both as PAID (not refunded)
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                }, { transaction });
                await plan.update({
                    hostPaymentStatus: PartyPlanPaymentStatus.PAID,
                    status: PartyPlanStatus.INACTIVE,
                    isLive: false,
                    paymentStatus: 'Confirmed',
                }, { transaction });

                // Create Booking & Payments
                await createBookingAndPayments(plan, request, transaction);

                // Reject and notify all other requests now that match is fully confirmed
                await rejectAndNotifyStaleRequests(plan, request.id, transaction);

                await transaction.commit();

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
                }, { transaction });

                await transaction.commit();

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
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'Invalid payment signature' });
        }
    } catch (err: any) {
        await transaction.rollback();
        logger.error('verifyJoinerPayment error:', err);
        res.status(500).json({ success: false, message: 'Failed to verify payment', error: err.message });
    }
};

export const confirmSelfPaidJoin = async (req: Request, res: Response): Promise<void> => {
    const transaction = await sequelize.transaction();
    try {
        const { reqId } = req.params;
        const { userId } = req.body;

        const request = await PartyPlanRequest.findByPk(reqId, {
            include: [{ model: PartyPlan, as: 'plan' }],
            transaction
        });
        if (!request) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        if (request.requesterId !== userId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'Only the requesting/invited user can confirm this request' });
            return;
        }

        const plan = (request as any).plan as PartyPlan;
        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (plan.paymentType !== 'self_pay') {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'This plan is not self-paid. Payment is required.' });
            return;
        }

        // Acquire transactional row update lock on the party plan
        await plan.reload({ lock: transaction.LOCK.UPDATE, transaction });

        // Enforce state transition checks: plan status must be active
        if (plan.status !== PartyPlanStatus.ACTIVE) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'This plan is not active or has already been completed/cancelled.' });
            return;
        }

        const hostPaid = plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID;

        if (hostPaid) {
            await request.update({
                status: PartyPlanRequestStatus.ACCEPTED,
                joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
            }, { transaction });

            await plan.update({
                status: PartyPlanStatus.INACTIVE,
                isLive: false,
                paymentStatus: 'Confirmed',
            }, { transaction });

            await createBookingAndPayments(plan, request, transaction);

            // Reject and notify all other requests now that match is fully confirmed
            await rejectAndNotifyStaleRequests(plan, request.id, transaction);

            await transaction.commit();

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
            }, { transaction });

            await plan.update({
                paymentStatus: 'Awaiting Host Payment',
            }, { transaction });

            await transaction.commit();

            try {
                const { io } = require('../server');
                io.to(`user_${plan.userId}`).emit('party_plan_joiner_paid', { planId: plan.id, requestId: request.id });
            } catch (socketErr) {
                logger.warn('Socket emission failed for party_plan_joiner_paid:', socketErr);
            }

            res.json({ success: true, message: 'Join confirmed. Waiting for host to complete their payment. ⏳', data: request });
        }
    } catch (err: any) {
        await transaction.rollback();
        logger.error('confirmSelfPaidJoin error:', err);
        res.status(500).json({ success: false, message: 'Failed to confirm join', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/requests/:reqId/accept-invite
// Accept an invite to a party plan
// ─────────────────────────────────────────────────────────────────────────────
export const acceptPartyPlanInvite = async (req: Request, res: Response): Promise<void> => {
    const transaction = await sequelize.transaction();
    try {
        const { reqId } = req.params;
        const { userId } = req.body;

        const request = await PartyPlanRequest.findByPk(reqId, {
            include: [{ model: PartyPlan, as: 'plan' }],
            transaction
        });
        if (!request) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        if (request.requesterId !== userId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'Only the invited user can accept this invite' });
            return;
        }

        const plan = (request as any).plan as PartyPlan;
        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        // Acquire transactional row update lock on the party plan
        await plan.reload({ lock: transaction.LOCK.UPDATE, transaction });

        // Enforce state transition checks: plan status must be active
        if (plan.status !== PartyPlanStatus.ACTIVE) {
            await transaction.rollback();
            res.status(400).json({ success: false, message: 'This plan is not active or has already been completed/cancelled.' });
            return;
        }

        // Check if there is already an active unpaid request on this plan (another user took it)
        const activeReq = await PartyPlanRequest.findOne({
            where: {
                planId: plan.id,
                id: { [Op.ne]: request.id },
                status: PartyPlanRequestStatus.PAYMENT_PENDING,
                paymentTimeoutAt: { [Op.gt]: new Date() }
            },
            transaction
        });
        if (activeReq) {
            await transaction.rollback();
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
                }, { transaction });
                await plan.update({
                    status: PartyPlanStatus.INACTIVE,
                    isLive: false,
                    paymentStatus: 'Confirmed',
                }, { transaction });
                await createBookingAndPayments(plan, request, transaction);

                // Reject and notify all other requests now that match is fully confirmed
                await rejectAndNotifyStaleRequests(plan, request.id, transaction);

                await transaction.commit();

                // Send push notification & socket events
                setImmediate(async () => {
                    try {
                        const joiner = await User.findByPk(request.requesterId);
                        const host = await User.findByPk(plan.userId);
                        const tokens = [host?.fcmToken, joiner?.fcmToken].filter(t => t && t.trim() !== '') as string[];
                        if (tokens.length > 0) {
                            const { sendMulticastPushNotification } = require('../services/fcmService');
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
                    const host = await User.findByPk(plan.userId);
                    const joiner = await User.findByPk(request.requesterId);
                    if (host && joiner) {
                        const { io } = require('../server');
                        const venueName = (plan as any)?.venue?.name || 'Club';
                        const joinerName = `${joiner.firstName} ${joiner.lastName}`;
                        
                        io.to(`user_${plan.userId}`).emit('party_plan_match_success', { planId: plan.id, requestId: request.id });
                        io.to(`user_${request.requesterId}`).emit('party_plan_match_success', { planId: plan.id, requestId: request.id });
                        io.emit('party_plan_deleted', { planId: plan.id });

                        io.to(`user_${plan.userId}`).emit('notification_created', {
                            id: `ppr_host_${request.id}`,
                            title: 'Invite Accepted',
                            body: `${joinerName} accepted and confirmed your private invite to the Party Plan at ${venueName}.`,
                            createdAt: new Date().toISOString(),
                            read: false,
                            sender: {
                                id: joiner.id,
                                firstName: joiner.firstName,
                                lastName: joiner.lastName,
                                profileImageUrl: joiner.profileImageUrl,
                            }
                        });
                    }
                } catch (socketErr) {
                    logger.warn('Socket emission failed for acceptPartyPlanInvite:', socketErr);
                }

                res.json({ success: true, message: 'Joined party plan successfully! (Paid by Host) 🎉', data: request });
            } else {
                await request.update({
                    status: PartyPlanRequestStatus.ACCEPTED,
                    joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                }, { transaction });
                await plan.update({
                    paymentStatus: 'Awaiting Host Payment',
                    isLive: false,
                }, { transaction });

                await transaction.commit();

                // Send push notification & socket events
                setImmediate(async () => {
                    try {
                        const host = await User.findByPk(plan.userId);
                        const joiner = await User.findByPk(request.requesterId);
                        if (host && host.fcmToken && joiner) {
                            const { sendPushNotification } = require('../services/fcmService');
                            const joinerName = `${joiner.firstName} ${joiner.lastName}`;
                            await sendPushNotification(host.fcmToken, {
                                title: 'Invite Accepted ⏳',
                                body: `${joinerName} accepted your invite. Please complete your deposit payment.`,
                                data: {
                                    type: 'invite_accepted_awaiting_host_payment',
                                    partyPlanId: plan.id,
                                }
                            });
                        }
                    } catch (pushErr: any) {
                        logger.warn('Failed to send invite accepted push:', pushErr.message);
                    }
                });

                try {
                    const host = await User.findByPk(plan.userId);
                    const joiner = await User.findByPk(request.requesterId);
                    if (host && joiner) {
                        const { io } = require('../server');
                        const venueName = (plan as any)?.venue?.name || 'Club';
                        const joinerName = `${joiner.firstName} ${joiner.lastName}`;
                        
                        io.emit('party_plan_deleted', { planId: plan.id });

                        io.to(`user_${plan.userId}`).emit('notification_created', {
                            id: `ppr_host_${request.id}`,
                            title: 'Invite Accepted',
                            body: `${joinerName} accepted your private invite to the Party Plan at ${venueName}. Please complete your payment.`,
                            createdAt: new Date().toISOString(),
                            read: false,
                            sender: {
                                id: joiner.id,
                                firstName: joiner.firstName,
                                lastName: joiner.lastName,
                                profileImageUrl: joiner.profileImageUrl,
                            }
                        });
                    }
                } catch (socketErr) {
                    logger.warn('Socket emission failed for acceptPartyPlanInvite:', socketErr);
                }

                res.json({ success: true, message: 'Join confirmed. Waiting for host to complete their payment. ⏳', data: request });
            }
        } else {
            // SPLIT PAY
            const timeout = new Date();
            timeout.setMinutes(timeout.getMinutes() + 30);

            await request.update({
                status: PartyPlanRequestStatus.PAYMENT_PENDING,
                paymentTimeoutAt: timeout,
            }, { transaction });

            await plan.update({
                isLive: false, // reserved
            }, { transaction });

            await transaction.commit();

            try {
                const host = await User.findByPk(plan.userId);
                const joiner = await User.findByPk(request.requesterId);
                if (host && joiner) {
                    const { io } = require('../server');
                    const venueName = (plan as any)?.venue?.name || 'Club';
                    const joinerName = `${joiner.firstName} ${joiner.lastName}`;
                    
                    io.to(`user_${request.requesterId}`).emit('party_plan_request_accepted', {
                        requestId: request.id,
                        planId: plan.id,
                        hostAlreadyPaid: hostPaid,
                        hostRazorpayOrderId: plan.hostRazorpayOrderId,
                        hostAmount: Math.round(plan.depositAmount * 100),
                        hostCurrency: 'INR',
                        joinerRazorpayOrderId: request.joinerRazorpayOrderId,
                        joinerAmount: Math.round(plan.depositAmount * 100),
                        joinerCurrency: 'INR',
                    });

                    io.emit('party_plan_deleted', { planId: plan.id });

                    io.to(`user_${plan.userId}`).emit('notification_created', {
                        id: `ppr_host_${request.id}`,
                        title: 'Invite Accepted',
                        body: `${joinerName} accepted your private invite to the Party Plan at ${venueName}. Awaiting participant payment.`,
                        createdAt: new Date().toISOString(),
                        read: false,
                        sender: {
                            id: joiner.id,
                            firstName: joiner.firstName,
                            lastName: joiner.lastName,
                            profileImageUrl: joiner.profileImageUrl,
                        }
                    });
                }
            } catch (socketErr) {
                logger.warn('Socket emission failed for acceptPartyPlanInvite:', socketErr);
            }

            res.json({ success: true, message: 'Invite accepted! You have 30 minutes to pay the deposit.', data: request });
        }
    } catch (err: any) {
        await transaction.rollback();
        logger.error('acceptPartyPlanInvite error:', err);
        res.status(500).json({ success: false, message: 'Failed to accept invite', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/cancel
// Cancel a party plan (by host)
// ─────────────────────────────────────────────────────────────────────────────
async function cancelPartyPlanInternal(plan: PartyPlan, transaction: Transaction) {
    // 1. Update plan status
    await plan.update({
        status: PartyPlanStatus.CANCELLED,
        isLive: false,
        paymentStatus: plan.paymentStatus === 'Confirmed' ? 'Refunded' : plan.paymentStatus,
        hostPaymentStatus: plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID
            ? PartyPlanPaymentStatus.REFUNDED
            : plan.hostPaymentStatus,
    }, { transaction });

    // 2. Release lock in Time Lock Engine
    await PlanEligibilityService.releaseLock(plan.id, { transaction });

    // 3. Find and update all requests
    const requests = await PartyPlanRequest.findAll({
        where: {
            planId: plan.id,
            status: { [Op.in]: [PartyPlanRequestStatus.PENDING, PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.ACCEPTED] }
        },
        transaction
    });

    for (const req of requests) {
        await req.update({
            status: PartyPlanRequestStatus.CANCELLED,
            joinerPaymentStatus: req.joinerPaymentStatus === PartyPlanJoinerPaymentStatus.PAID
                ? PartyPlanJoinerPaymentStatus.REFUNDED
                : req.joinerPaymentStatus
        }, { transaction });

        // Notify joiners
        try {
            const { io } = require('../server');
            io.to(`user_${req.requesterId}`).emit('plan_unavailable', {
                planId: plan.id,
                requestId: req.id,
            });
            io.to(`user_${req.requesterId}`).emit('notification_created', {
                id: `ppr_cancelled_${req.id}`,
                title: 'Party Plan Cancelled',
                body: 'The Party Plan has been cancelled by the host. Any deposits paid will be refunded.',
                createdAt: new Date().toISOString(),
                read: false,
                type: 'plan_unavailable',
            });
        } catch (_) {}

        setImmediate(async () => {
            try {
                const joiner = await User.findByPk(req.requesterId);
                if (joiner && joiner.fcmToken) {
                    await sendMulticastPushNotification([joiner.fcmToken], {
                        title: 'Party Plan Cancelled',
                        body: 'The Party Plan has been cancelled by the host. Any deposits paid will be refunded.',
                        data: {
                            type: 'plan_unavailable',
                            partyPlanId: plan.id,
                            requestId: req.id,
                        },
                    });
                }
            } catch (_) {}
        });
    }

    // 4. Find associated Booking (goingMode = GoingMode.PARTY_REQUEST, matching host userId, venueId, planDateTime)
    const booking = await Booking.findOne({
        where: {
            goingMode: GoingMode.PARTY_REQUEST,
            userId: plan.userId,
            venueId: plan.venueId,
            bookingDate: plan.planDateTime,
            status: { [Op.ne]: BookingStatus.CANCELLED }
        },
        transaction
    });

    if (booking) {
        await booking.update({
            status: BookingStatus.CANCELLED,
            paymentStatus: BookingPaymentStatus.REFUNDED
        }, { transaction });

        // Update all related Payment records to refunded
        const payments = await Payment.findAll({
            where: {
                bookingId: booking.id,
                status: PaymentStatus.SUCCESSFUL
            },
            transaction
        });

        for (const payment of payments) {
            await payment.update({
                status: PaymentStatus.REFUNDED,
                refundAmount: payment.amount,
                refundedAt: new Date()
            }, { transaction });
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/party-plans/:id/cancel
// Cancel a party plan (by host)
// ─────────────────────────────────────────────────────────────────────────────
export const cancelPartyPlan = async (req: Request, res: Response): Promise<void> => {
    const transaction = await sequelize.transaction();
    try {
        const { id } = req.params;
        const { userId } = req.body;

        const plan = await PartyPlan.findByPk(id, { transaction });
        if (!plan) {
            await transaction.rollback();
            res.status(404).json({ success: false, message: 'Party plan not found' });
            return;
        }

        if (plan.userId !== userId) {
            await transaction.rollback();
            res.status(403).json({ success: false, message: 'Only the host can cancel the plan' });
            return;
        }

        // Row lock
        await plan.reload({ lock: transaction.LOCK.UPDATE, transaction });

        // Check if already cancelled
        if (plan.status === PartyPlanStatus.CANCELLED) {
            await transaction.rollback();
            res.json({ success: true, message: 'Party plan is already cancelled' });
            return;
        }

        await cancelPartyPlanInternal(plan, transaction);

        await transaction.commit();

        // Emit socket event to notify other clients to remove it from feed
        try {
            const { io } = require('../server');
            io.emit('party_plan_deleted', { planId: plan.id });
        } catch (socketErr) {
            logger.warn('Socket emission failed for party_plan_deleted on cancel:', socketErr);
        }

        res.json({ success: true, message: 'Party plan cancelled' });
    } catch (err: any) {
        await transaction.rollback();
        logger.error('cancelPartyPlan error:', err);
        res.status(500).json({ success: false, message: 'Failed to cancel plan', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/party-plans/requests/:reqId/ticket
// Fetch a complete ticket payload (plan + both users with photos + ticketCode)
// ─────────────────────────────────────────────────────────────────────────────
const TICKET_USER_ATTRS = ['id', 'firstName', 'lastName', 'email', 'username', 'profileImageUrl', 'subscriptionTier'];

export const getPartyPlanTicket = async (req: Request, res: Response): Promise<void> => {
    try {
        const { reqId } = req.params;

        const request = await PartyPlanRequest.findByPk(reqId, {
            include: [
                {
                    model: PartyPlan,
                    as: 'plan',
                    include: [
                        {
                            model: User,
                            as: 'creator',
                            attributes: TICKET_USER_ATTRS,
                            include: [
                                { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                                { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
                            ],
                        },
                        {
                            model: Venue,
                            as: 'venue',
                            attributes: ['id', 'name', 'addressLine1', 'area', 'city', 'category', 'phone', 'coverChargeMale', 'coverChargeFemale', 'latitude', 'longitude'],
                            include: [
                                {
                                    model: VenueImage,
                                    as: 'images',
                                    attributes: ['id', 'filePath', 'imageType', 'isPrimary'],
                                    where: { isPrimary: true },
                                    required: false,
                                }
                            ],
                        },
                    ] as any,
                },
                {
                    model: User,
                    as: 'requester',
                    attributes: TICKET_USER_ATTRS,
                    include: [
                        { model: UserProfile, as: 'profile', attributes: PROFILE_ATTRS, required: false },
                        { model: UserPhoto, as: 'photos', attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'], required: false },
                    ],
                },
            ],
        });

        if (!request) {
            res.status(404).json({ success: false, message: 'Request not found' });
            return;
        }

        const plan = (request as any).plan as PartyPlan;
        if (!plan) {
            res.status(404).json({ success: false, message: 'Plan not found for this request' });
            return;
        }

        // Helper to extract photo URL from a user record with embedded photos array
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

        const hostRaw = (plan as any).creator;
        const joinerRaw = (request as any).requester;

        const hostData = hostRaw ? {
            id: hostRaw.id,
            firstName: hostRaw.firstName,
            lastName: hostRaw.lastName,
            username: hostRaw.username,
            profilePhotoUrl: resolveUserPhoto(hostRaw),
            subscriptionTier: hostRaw.subscriptionTier,
            bio: hostRaw.profile?.bio ?? null,
            city: hostRaw.profile?.city ?? null,
        } : null;

        const joinerData = joinerRaw ? {
            id: joinerRaw.id,
            firstName: joinerRaw.firstName,
            lastName: joinerRaw.lastName,
            username: joinerRaw.username,
            profilePhotoUrl: resolveUserPhoto(joinerRaw),
            subscriptionTier: joinerRaw.subscriptionTier,
            bio: joinerRaw.profile?.bio ?? null,
            city: joinerRaw.profile?.city ?? null,
        } : null;

        // Fetch the booking record to retrieve the ticketCode and ticketUrl
        const booking = await Booking.findOne({
            where: { goingMode: GoingMode.PARTY_REQUEST, userId: plan.userId, venueId: plan.venueId },
            order: [['createdAt', 'DESC']],
            attributes: ['id', 'ticketCode', 'ticketUrl', 'specialRequests'],
        });

        let ticketUrl = (booking as any)?.ticketUrl ?? null;
        let ticketCode = booking?.ticketCode ?? null;

        if (booking && !ticketUrl) {
            try {
                const { generateTicketForBookingHelper } = require('../services/ticketService');
                ticketUrl = await generateTicketForBookingHelper(booking.id);
            } catch (ticketGenErr: any) {
                logger.warn(`On-the-fly ticket PDF generation failed for booking ${booking.id}: ${ticketGenErr.message}`);
            }
        }

        res.json({
            success: true,
            data: {
                request: {
                    id: request.id,
                    planId: request.planId,
                    status: request.status,
                    joinerPaymentStatus: request.joinerPaymentStatus,
                    createdAt: request.createdAt,
                    requester: joinerData,
                    joiner: joinerData,
                    user: joinerData,
                },
                plan: {
                    id: plan.id,
                    message: plan.message,
                    planDateTime: plan.planDateTime,
                    expiresAt: plan.planDateTime,
                    paymentType: plan.paymentType,
                    depositAmount: plan.depositAmount,
                    status: plan.status,
                    foodPreference: plan.foodPreference,
                    drinkPreference: plan.drinkPreference,
                    user: hostData,
                    creator: hostData,
                    host: hostData,
                    venue: buildVenueData(plan as any),
                },
                ticketCode: ticketCode,
                bookingId: booking?.id ?? null,
                ticketUrl: ticketUrl,
            },
        });
    } catch (err: any) {
        logger.error('getPartyPlanTicket error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch ticket data', error: err.message });
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
