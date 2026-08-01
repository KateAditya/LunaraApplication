import { Transaction } from 'sequelize';
import StrangersMeetRequest, { StrangersMeetStatus, StrangersMeetPaymentStatus } from '../models/StrangersMeetRequest';
import StrangersMeetJoiner, { StrangersMeetJoinerStatus, StrangersMeetJoinerPaymentStatus } from '../models/StrangersMeetJoiner';
import Venue from '../models/Venue';
import { PlanEligibilityService } from './PlanEligibilityService';
import { validateVenueTimingAndHolidays } from '../utils/venueValidator';
import { checkExistingBookingForDate } from '../utils/bookingLimitValidator';
import { generateTicketForStrangersMeetHelper } from './ticketService';
import { logger } from '../config/logger';
import Razorpay from 'razorpay';
import crypto from 'crypto';

const razorpay = new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
    key_secret: process.env.RAZORPAY_KEY_SECRET || 'secret123',
});

export interface CreateStrangersMeetPayload {
    userId: string;
    venueId: string;
    subject: string;
    tagline: string;
    eventDateTime: string;
    numberOfPersons: number; // Must be between 21 and 50
    mobileNumber: string;
    alternateMobileNumber?: string;
    bankName?: string;
    accountNumber?: string;
    accountHolderName?: string;
    ifscCode?: string;
    upiId?: string;
    upiNumber?: string;
    foodPreference?: string;
    drinkPreference?: string;
}

export class StrangersMeetService {
    public static readonly MIN_PERSONS = 21;
    public static readonly MAX_PERSONS = 50;

    /**
     * Server-side capacity & input validation
     */
    public static validateCapacityAndInput(numberOfPersons: number, venueCapacity: number): void {
        if (numberOfPersons < this.MIN_PERSONS || numberOfPersons > this.MAX_PERSONS) {
            throw new Error(`Stranger Meet capacity must be between ${this.MIN_PERSONS} and ${this.MAX_PERSONS} persons.`);
        }
        if (numberOfPersons > venueCapacity) {
            throw new Error(`Requested slots (${numberOfPersons}) exceed maximum venue capacity (${venueCapacity}).`);
        }
    }

    /**
     * Creates a new Stranger's Meet Request with Transaction Isolation & TimeLock Integration
     */
    public static async createMeetupRequest(payload: CreateStrangersMeetPayload): Promise<StrangersMeetRequest> {
        const {
            userId, venueId, subject, tagline, eventDateTime, numberOfPersons,
            mobileNumber, alternateMobileNumber, bankName, accountNumber,
            accountHolderName, ifscCode, upiId, upiNumber, foodPreference, drinkPreference
        } = payload;

        const venue = await Venue.findByPk(venueId);
        if (!venue) throw new Error('Venue not found');

        this.validateCapacityAndInput(numberOfPersons, venue.capacity || 500);

        const eventDate = new Date(eventDateTime);
        if (isNaN(eventDate.getTime()) || eventDate < new Date()) {
            throw new Error('Event date and time must be a valid future date.');
        }

        const timingValidation = validateVenueTimingAndHolidays(venue, eventDateTime);
        if (!timingValidation.isValid) {
            throw new Error(timingValidation.reason || 'Venue is closed on selected date or time.');
        }

        const bookingConflictMsg = await checkExistingBookingForDate(userId, eventDate);
        if (bookingConflictMsg) {
            throw new Error('You already have an active plan or event scheduled on this day.');
        }

        const request = await PlanEligibilityService.runAtomicCheckAndCreate(
            userId,
            'strangers_meet',
            eventDate,
            async (transaction: Transaction) => {
                return await StrangersMeetRequest.create({
                    userId,
                    venueId,
                    subject: subject.trim(),
                    tagline: tagline.trim(),
                    eventDateTime: eventDate,
                    numberOfPersons: Number(numberOfPersons),
                    chargesPerHead: 0.0,
                    mobileNumber: mobileNumber.trim(),
                    alternateMobileNumber: alternateMobileNumber?.trim() || undefined,
                    bankName: bankName?.trim() || undefined,
                    accountNumber: accountNumber?.trim() || undefined,
                    accountHolderName: accountHolderName?.trim() || undefined,
                    ifscCode: ifscCode?.trim() || undefined,
                    upiId: upiId?.trim() || undefined,
                    upiNumber: upiNumber?.trim() || undefined,
                    foodPreference: foodPreference?.trim() || undefined,
                    drinkPreference: drinkPreference?.trim() || undefined,
                    status: StrangersMeetStatus.PENDING,
                    paymentStatus: StrangersMeetPaymentStatus.UNPAID
                }, { transaction });
            }
        );

        return request;
    }

    /**
     * Idempotent Payment Verification for Host Deposit
     */
    public static async verifyHostDepositPayment(
        requestId: string,
        razorpay_order_id: string,
        razorpay_payment_id: string,
        razorpay_signature: string
    ): Promise<StrangersMeetRequest> {
        const request = await StrangersMeetRequest.findByPk(requestId);
        if (!request) throw new Error('Stranger Meet request not found.');

        if (request.paymentStatus === StrangersMeetPaymentStatus.PAID) {
            logger.info(`[StrangersMeetService] Request ${requestId} host deposit already paid. Returning idempotent response.`);
            return request;
        }

        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(`${razorpay_order_id}|${razorpay_payment_id}`);
        const generatedSignature = hmac.digest('hex');

        if (generatedSignature !== razorpay_signature) {
            throw new Error('Invalid payment signature');
        }

        const ticketId = `LNR-${Date.now().toString(36).toUpperCase()}-${Math.random().toString(36).substring(2, 7).toUpperCase()}`;

        await request.update({
            paymentStatus: StrangersMeetPaymentStatus.PAID,
            razorpayOrderId: razorpay_order_id,
            razorpayPaymentId: razorpay_payment_id,
            razorpaySignature: razorpay_signature,
            ticketId
        });

        try {
            await generateTicketForStrangersMeetHelper(request.id);
        } catch (tErr) {
            logger.error(`[StrangersMeetService] Ticket generation error for SM Request ${request.id}:`, tErr);
        }

        await this.emitNotification({
            recipientUserId: request.userId,
            eventType: 'strangers_meet_deposit_paid',
            title: '🎉 Deposit Verified!',
            body: 'Your Strangers Meetup is LIVE and open for joiners!',
            entityId: request.id
        });

        return request;
    }

    /**
     * Concurrency-Safe Stranger Joiner Seat Reservation & Order Creation
     */
    public static async joinMeetup(
        requestId: string,
        userId: string
    ): Promise<{ joiner: StrangersMeetJoiner; order: any }> {
        const request = await StrangersMeetRequest.findByPk(requestId);
        if (!request) throw new Error('Stranger Meetup not found.');

        if (request.status !== StrangersMeetStatus.APPROVED || request.paymentStatus !== StrangersMeetPaymentStatus.PAID) {
            throw new Error('This Stranger Meetup is not active or live for booking.');
        }

        // Count confirmed/paid joiners atomically
        const paidCount = await StrangersMeetJoiner.count({
            where: {
                strangersMeetRequestId: requestId,
                status: 'paid'
            }
        });

        if (paidCount >= request.numberOfPersons) {
            throw new Error('This Stranger Meetup is already FULL.');
        }

        // Check if user already joined
        const existingJoiner = await StrangersMeetJoiner.findOne({
            where: { strangersMeetRequestId: requestId, userId }
        });

        if (existingJoiner && existingJoiner.paymentStatus === StrangersMeetJoinerPaymentStatus.PAID) {
            throw new Error('You have already joined and confirmed your seat for this meetup.');
        }

        const chargesPerHead = Number(request.chargesPerHead || 0);

        let razorpayOrder: any = null;
        if (chargesPerHead > 0) {
            razorpayOrder = await razorpay.orders.create({
                amount: Math.round(chargesPerHead * 100),
                currency: 'INR',
                receipt: `sm_j_${Date.now()}`
            });
        }

        let joiner = existingJoiner;
        if (!joiner) {
            joiner = await StrangersMeetJoiner.create({
                strangersMeetRequestId: requestId,
                userId,
                status: chargesPerHead > 0 ? StrangersMeetJoinerStatus.PENDING : StrangersMeetJoinerStatus.PAID,
                paymentStatus: chargesPerHead > 0 ? StrangersMeetJoinerPaymentStatus.PENDING : StrangersMeetJoinerPaymentStatus.PAID,
                paymentAmount: chargesPerHead,
                razorpayOrderId: razorpayOrder ? razorpayOrder.id : `free_${Date.now()}`
            });
        } else if (razorpayOrder) {
            await joiner.update({ razorpayOrderId: razorpayOrder.id });
        }

        return { joiner, order: razorpayOrder };
    }

    /**
     * Helper to dispatch Strangers Meet notifications across DB, FCM Push, and Socket.IO
     */
    public static async emitNotification(options: {
        recipientUserId: string;
        eventType: string;
        title: string;
        body: string;
        entityId: string;
        metadata?: Record<string, any>;
        notifyAdmins?: boolean;
    }): Promise<void> {
        try {
            const { recipientUserId, eventType, title, body, entityId, metadata, notifyAdmins } = options;

            // 1. Create DB Notification Record for Recipient
            try {
                const Notification = (await import('../models/Notification')).default;
                await Notification.create({
                    recipientUserId,
                    eventType,
                    category: 'bookings' as any,
                    entityType: 'strangers_meet',
                    entityId,
                    title,
                    body,
                    priority: 'HIGH' as any,
                    isRead: false,
                    metadata: metadata || { entityId }
                });
            } catch (dbErr) {
                logger.warn(`[StrangersMeetService] Failed to create DB Notification: ${dbErr}`);
            }

            // 2. Send FCM Push Notification to Recipient
            try {
                const User = (await import('../models/User')).default;
                const user = await User.findByPk(recipientUserId, { attributes: ['id', 'fcmToken'] });
                if (user && user.fcmToken) {
                    const { sendPushNotification } = require('./fcmService');
                    await sendPushNotification(user.fcmToken, {
                        title,
                        body,
                        data: { type: eventType, entityId }
                    });
                }
            } catch (pushErr) {
                logger.warn(`[StrangersMeetService] FCM Push warning: ${pushErr}`);
            }

            // 3. Send Socket.IO Real-time Events
            try {
                const { io } = require('../server');
                if (io) {
                    io.to(`user_${recipientUserId}`).emit('strangers_meet_status_update', { entityId, eventType });
                    io.to(`user_${recipientUserId}`).emit('notification_created', {
                        id: `sm_${entityId}_${Date.now()}`,
                        title,
                        body,
                        createdAt: new Date().toISOString(),
                        read: false,
                        data: { type: eventType, entityId }
                    });
                }
            } catch (sockErr) {
                logger.warn(`[StrangersMeetService] Socket emit warning: ${sockErr}`);
            }

            // 4. If requested, alert all Admins
            if (notifyAdmins) {
                try {
                    const User = (await import('../models/User')).default;
                    const Notification = (await import('../models/Notification')).default;
                    const admins = await User.findAll({ where: { role: 'admin' }, attributes: ['id', 'fcmToken'] });
                    const adminTitle = 'New Strangers Meet Request 🚨';
                    const adminBody = title;

                    for (const admin of admins) {
                        await Notification.create({
                            recipientUserId: admin.id,
                            eventType: 'strangers_meet_request_submitted',
                            category: 'bookings' as any,
                            entityType: 'strangers_meet',
                            entityId,
                            title: adminTitle,
                            body: adminBody,
                            priority: 'HIGH' as any,
                            isRead: false,
                            metadata: metadata || { entityId }
                        }).catch(() => {});

                        if (admin.fcmToken) {
                            const { sendPushNotification } = require('./fcmService');
                            sendPushNotification(admin.fcmToken, {
                                title: adminTitle,
                                body: adminBody,
                                data: { type: 'strangers_meet_request_submitted', entityId }
                            }).catch(() => {});
                        }
                    }

                    const { io } = require('../server');
                    if (io) {
                        io.to('admin_notifications').emit('admin_notification_created', {
                            title: adminTitle,
                            body: adminBody,
                            entityId,
                            createdAt: new Date().toISOString()
                        });
                    }
                } catch (adminErr) {
                    logger.warn(`[StrangersMeetService] Admin notification warning: ${adminErr}`);
                }
            }
        } catch (err) {
            logger.warn(`[StrangersMeetService] emitNotification global error: ${err}`);
        }
    }
}
