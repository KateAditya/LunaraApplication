import { Transaction } from 'sequelize';
import StrangersMeetRequest, { StrangersMeetStatus, StrangersMeetPaymentStatus } from '../models/StrangersMeetRequest';
import StrangersMeetJoiner, { StrangersMeetJoinerStatus, StrangersMeetJoinerPaymentStatus } from '../models/StrangersMeetJoiner';
import Venue from '../models/Venue';
import { PlanEligibilityService } from './PlanEligibilityService';
import { validateVenueTimingAndHolidays } from '../utils/venueValidator';
import { TimeLockError } from '../utils/bookingLimitValidator';
import { EventTimeLockService } from './EventTimeLockService';
import { generateTicketForStrangersMeetHelper } from './ticketService';
import { logger } from '../config/logger';
import Razorpay from 'razorpay';
import crypto from 'crypto';
import AuditLog from '../models/AuditLog';
import { formatTime12Hour, formatDateTimeFull } from '../utils/dateTimeUtils';

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

        // ── Universal 4-Hour Time-Lock Validation ─────────────────────────────
        const timeLockCheck = await EventTimeLockService.validateFourHourGap(userId, eventDate, 'stranger_meet');
        if (!timeLockCheck.allowed) {
            throw new TimeLockError(timeLockCheck);
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

        try {
            await AuditLog.logAction({
                userId,
                partyPlanId: request.id,
                action: 'Stranger Meet Created',
                metadata: { subject, venueId, numberOfPersons }
            });
        } catch (_) {}

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

        const ticketId = `SM-${Date.now().toString(36).toUpperCase()}-${Math.random().toString(36).substring(2, 6).toUpperCase()}`;

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

        try {
            await AuditLog.logAction({
                userId: request.userId,
                partyPlanId: request.id,
                action: 'Stranger Meet Host Deposit Verified',
                metadata: { razorpay_payment_id, razorpay_order_id, ticketId }
            });
        } catch (_) {}

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

        if (
            request.status !== StrangersMeetStatus.APPROVED &&
            request.status !== StrangersMeetStatus.START_CONFIRMATION_PENDING &&
            request.status !== StrangersMeetStatus.IN_PROGRESS
        ) {
            throw new Error('This Stranger Meetup is not active or live for booking.');
        }

        if (request.paymentStatus !== StrangersMeetPaymentStatus.PAID) {
            throw new Error('Host deposit payment is pending for this meetup.');
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

        try {
            await AuditLog.logAction({
                userId,
                partyPlanId: requestId,
                action: 'Stranger Meet Join Requested',
                metadata: { joinerId: joiner.id, chargesPerHead }
            });
        } catch (_) {}

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

            // 1. Create or Update Single DB Notification Record for Recipient (One Stranger Meet = One Card)
            try {
                const Notification = (await import('../models/Notification')).default;
                const existingNotif = await Notification.findOne({
                    where: {
                        recipientUserId,
                        entityType: 'strangers_meet',
                        entityId,
                    }
                });

                if (existingNotif) {
                    await existingNotif.update({
                        eventType,
                        title,
                        body,
                        isRead: false,
                        updatedAt: new Date(),
                        metadata: metadata || { entityId }
                    });
                } else {
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
                }
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
                    const card = await StrangersMeetService.enrichStrangersMeetNotificationCard(entityId, recipientUserId);

                    io.to(`user_${recipientUserId}`).emit('strangers_meet_status_update', { entityId, eventType, card });
                    io.to(`user_${recipientUserId}`).emit('notification_updated', {
                        id: `strangers_meet_timeline_${entityId}`,
                        title,
                        body,
                        card,
                        updatedAt: new Date().toISOString()
                    });

                    // Broadcast single-card update
                    io.emit('live_feed_update', {
                        type: 'strangers_meet_update',
                        entityId,
                        eventType
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
                    const adminTitle = title.includes('🚨') ? title : `🚨 Strangers Meet Alert: ${title}`;
                    const adminBody = body;

                    for (const admin of admins) {
                        await Notification.create({
                            recipientUserId: admin.id,
                            eventType: eventType || 'strangers_meet_admin_alert',
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
                                data: { type: eventType, entityId }
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

    /**
     * Unifies and enriches Stranger Meet notification card into ONE single timeline card
     * Source of truth for the entire lifecycle in Live Feed
     */
    public static async enrichStrangersMeetNotificationCard(
        meetId: string,
        recipientUserId: string
    ): Promise<Record<string, any> | null> {
        try {
            const User = (await import('../models/User')).default;
            const Venue = (await import('../models/Venue')).default;

            const request = await StrangersMeetRequest.findByPk(meetId, {
                include: [
                    { model: Venue, as: 'venue', attributes: ['name', 'area'] },
                    { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] },
                    {
                        model: StrangersMeetJoiner,
                        as: 'joiners',
                        include: [{ model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] }]
                    }
                ]
            });

            if (!request) return null;

            const reqAny = request as any;
            const isHost = request.userId === recipientUserId;
            const joiners: any[] = reqAny.joiners || [];
            const userJoiner = joiners.find((j: any) => j.userId === recipientUserId);
            const isParticipant = isHost || Boolean(userJoiner);

            if (!isParticipant) return null;

            const now = new Date();
            const eventTime = new Date(request.eventDateTime);
            const expectedEndTime = request.expectedEndAt
                ? new Date(request.expectedEndAt)
                : new Date(eventTime.getTime() + 2 * 60 * 60 * 1000);

            const isCompleted = request.status === StrangersMeetStatus.COMPLETED || request.status === StrangersMeetStatus.SETTLED || request.settlementStatus === 'settled' || request.settlementStatus === 'paid';
            const isAdminConfirmed = request.status === StrangersMeetStatus.ADMIN_CONFIRMED_ENDED;
            const isHostEnded = request.status === StrangersMeetStatus.HOST_CONFIRMED_ENDED;
            const isEndConfirmationPending = request.status === StrangersMeetStatus.END_CONFIRMATION_PENDING;
            const isInProgress = request.status === StrangersMeetStatus.IN_PROGRESS;
            const isStartConfirmationPending = request.status === StrangersMeetStatus.START_CONFIRMATION_PENDING;
            const isNeedsHostContact = request.status === StrangersMeetStatus.NEEDS_HOST_CONTACT;
            const isNotStarted = request.status === StrangersMeetStatus.NOT_STARTED;
            const isCancelled = request.status === StrangersMeetStatus.CANCELLED || request.status === StrangersMeetStatus.REJECTED;
            const isAdminResolved = request.status === StrangersMeetStatus.ADMIN_RESOLVED;

            const isConfirmed = (request.status === StrangersMeetStatus.APPROVED || isStartConfirmationPending || isInProgress || isEndConfirmationPending || isHostEnded || isAdminConfirmed || isCompleted) && request.paymentStatus === StrangersMeetPaymentStatus.PAID;
            const isHostPaid = request.paymentStatus === StrangersMeetPaymentStatus.PAID;
            const isApproved = request.status === StrangersMeetStatus.APPROVED;

            // Countdown calculation
            const diffStartMs = eventTime.getTime() - now.getTime();
            const diffEndMs = expectedEndTime.getTime() - now.getTime();

            const diffHours = Math.max(0, Math.floor(Math.abs(diffStartMs) / (1000 * 60 * 60)));
            const diffMins = Math.max(0, Math.floor((Math.abs(diffStartMs) % (1000 * 60 * 60)) / (1000 * 60)));

            const endDiffHours = Math.max(0, Math.floor(Math.abs(diffEndMs) / (1000 * 60 * 60)));
            const endDiffMins = Math.max(0, Math.floor((Math.abs(diffEndMs) % (1000 * 60 * 60)) / (1000 * 60)));

            const timeline: any[] = [];
            const addStep = (title: string, completed: boolean, dateVal?: Date | null) => {
                timeline.push({
                    title,
                    completed,
                    timestamp: dateVal ? dateVal.toISOString() : null
                });
            };

            addStep('Booking Created', true, request.createdAt);
            addStep('Admin Approved', isApproved || isConfirmed, request.createdAt);
            addStep('Deposit Paid', isConfirmed, request.updatedAt);
            addStep('Meetup Started', isInProgress || isEndConfirmationPending || isHostEnded || isAdminConfirmed || isCompleted, request.startedAt);
            addStep('Meetup Ended', isHostEnded || isAdminConfirmed || isCompleted, request.endedAt);
            addStep('Admin Verified', isAdminConfirmed || isCompleted, request.adminConfirmedEndedAt);
            addStep('Settled', isCompleted, request.settlementDate);

            let currentStatusText = 'Booking Requested';
            let primaryAction: string | null = null;
            let secondaryAction: string | null = null;
            let primaryActionUrl: string | null = null;
            let secondaryActionUrl: string | null = null;
            let countdown = diffStartMs > 0 ? `${diffHours}h ${diffMins}m remaining` : 'Scheduled time reached';

            if (isCompleted) {
                const amountText = request.settlementAmount ? `₹${Number(request.settlementAmount).toFixed(0)}` : 'Completed';
                currentStatusText = `✓ Meet Completed • Settlement: ${amountText}`;
                primaryAction = 'View Settlement';
                primaryActionUrl = `/strangers-meet/${request.id}/settlement`;
                secondaryAction = 'View Details';
                secondaryActionUrl = `/strangers-meet/${request.id}`;
                countdown = 'Settled & Closed';
            } else if (isAdminConfirmed) {
                currentStatusText = 'Admin Confirmed • Settlement Processing within 24h';
                primaryAction = 'View Details';
                primaryActionUrl = `/strangers-meet/${request.id}`;
                secondaryAction = 'Open Chat';
                secondaryActionUrl = `/chat/strangers-meet-${request.id}`;
                countdown = 'Settlement in progress';
            } else if (isHostEnded) {
                currentStatusText = 'Meetup Ended • Under Admin Review';
                primaryAction = 'View Details';
                primaryActionUrl = `/strangers-meet/${request.id}`;
                secondaryAction = 'Open Chat';
                secondaryActionUrl = `/chat/strangers-meet-${request.id}`;
                countdown = 'Pending Admin Review';
            } else if (isEndConfirmationPending) {
                currentStatusText = 'End Confirmation Required';
                countdown = 'Expected end time reached';
                if (isHost) {
                    primaryAction = 'Yes, Ended';
                    primaryActionUrl = `/strangers-meet/${request.id}/confirm-ended`;
                    secondaryAction = 'Still Going';
                    secondaryActionUrl = `/strangers-meet/${request.id}/extend`;
                } else {
                    primaryAction = 'Open Chat';
                    primaryActionUrl = `/chat/strangers-meet-${request.id}`;
                }
            } else if (isInProgress) {
                const startedFormatted = request.startedAt
                    ? formatTime12Hour(request.startedAt)
                    : '';
                currentStatusText = `✓ Strangers Meet Started • ${startedFormatted}`;
                countdown = diffEndMs > 0 ? `${endDiffHours}h ${endDiffMins}m remaining` : 'Ending time reached';
                if (isHost) {
                    primaryAction = 'End Meetup';
                    primaryActionUrl = `/strangers-meet/${request.id}/end`;
                    secondaryAction = 'Open Chat';
                    secondaryActionUrl = `/chat/strangers-meet-${request.id}`;
                } else {
                    primaryAction = 'Open Chat';
                    primaryActionUrl = `/chat/strangers-meet-${request.id}`;
                    secondaryAction = 'View Ticket';
                    secondaryActionUrl = `/strangers-meet/${request.id}/ticket`;
                }
            } else if (isStartConfirmationPending) {
                currentStatusText = 'Start Confirmation Required';
                countdown = 'Scheduled Time Reached';
                if (isHost) {
                    primaryAction = 'Yes, Started';
                    primaryActionUrl = `/strangers-meet/${request.id}/start`;
                    secondaryAction = 'Not Started';
                    secondaryActionUrl = `/strangers-meet/${request.id}/not-started`;
                } else {
                    primaryAction = 'Open Chat';
                    primaryActionUrl = `/chat/strangers-meet-${request.id}`;
                }
            } else if (isNeedsHostContact) {
                currentStatusText = 'Action Required: No host confirmation within 24h';
                countdown = 'Under Admin Investigation';
                if (isHost) {
                    primaryAction = 'Update Status';
                    primaryActionUrl = `/strangers-meet/${request.id}/manual-status`;
                } else {
                    primaryAction = 'View Details';
                    primaryActionUrl = `/strangers-meet/${request.id}`;
                }
            } else if (isNotStarted) {
                currentStatusText = 'Meetup Not Started';
                countdown = 'Closed';
                primaryAction = 'View Details';
                primaryActionUrl = `/strangers-meet/${request.id}`;
            } else if (isCancelled) {
                currentStatusText = 'Meetup Cancelled';
                countdown = 'Cancelled';
                primaryAction = 'View Details';
                primaryActionUrl = `/strangers-meet/${request.id}`;
            } else if (isAdminResolved) {
                currentStatusText = `Admin Resolved: ${request.adminResolution || 'Completed'}`;
                countdown = 'Resolved';
                primaryAction = 'View Details';
                primaryActionUrl = `/strangers-meet/${request.id}`;
            } else if (isConfirmed) {
                if (diffStartMs <= 0) {
                    currentStatusText = isHost ? 'Start Confirmation Required' : 'Meetup Time Reached';
                    if (isHost) {
                        primaryAction = 'Yes, Started';
                        primaryActionUrl = `/strangers-meet/${request.id}/start`;
                        secondaryAction = 'Not Started';
                        secondaryActionUrl = `/strangers-meet/${request.id}/not-started`;
                    } else {
                        primaryAction = 'Open Chat';
                        primaryActionUrl = `/chat/strangers-meet-${request.id}`;
                    }
                    countdown = 'Ready to Start';
                } else {
                    currentStatusText = 'Upcoming Strangers Meet';
                    countdown = `Starts in ${diffHours}h ${diffMins}m`;
                    primaryAction = 'Open Chat';
                    primaryActionUrl = `/chat/strangers-meet-${request.id}`;
                    secondaryAction = 'View Ticket';
                    secondaryActionUrl = `/strangers-meet/${request.id}/ticket`;
                }
            } else if (isApproved) {
                if (isHost) {
                    if (!isHostPaid) {
                        currentStatusText = 'Action Required: Pay Deposit';
                        primaryAction = 'Pay Deposit';
                        primaryActionUrl = `/strangers-meet/${request.id}/pay-deposit`;
                    } else {
                        const acceptedCount = joiners.filter((j: any) => j.status === 'accepted' || j.status === 'paid' || j.paymentStatus === 'paid').length;
                        const remainingSlots = Math.max(0, request.numberOfPersons - acceptedCount);
                        const isFull = acceptedCount >= request.numberOfPersons;
                        currentStatusText = isFull
                            ? `✓ ${acceptedCount} / ${request.numberOfPersons} Accepted • FULL`
                            : `✓ ${acceptedCount} / ${request.numberOfPersons} Accepted • ${remainingSlots} slots remaining`;
                        primaryAction = 'View Meet';
                        primaryActionUrl = `/strangers-meet/${request.id}`;
                    }
                } else {
                    if (userJoiner?.status === 'accepted' && userJoiner?.paymentStatus !== 'paid') {
                        currentStatusText = 'Action Required: Pay Seat Fee';
                        primaryAction = 'Pay Now';
                        primaryActionUrl = `/strangers-meet/${request.id}/pay-joiner`;
                    } else {
                        currentStatusText = 'Booking Requested';
                        primaryAction = 'Pending Review';
                    }
                }
            } else {
                currentStatusText = 'Awaiting Admin Approval';
                primaryAction = 'Pending Approval';
            }

            const venueName = reqAny.venue?.name || 'Venue';
            const eventDateStr = request.eventDateTime
                ? formatDateTimeFull(request.eventDateTime)
                : '';

            const acceptedCount = joiners.filter((j: any) => j.status === 'accepted' || j.status === 'paid' || j.paymentStatus === 'paid').length;
            const pendingJoiners = joiners.filter((j: any) => j.status === 'pending');
            const maximumCapacity = request.numberOfPersons;
            const remainingSlots = Math.max(0, maximumCapacity - acceptedCount);
            const isFull = acceptedCount >= maximumCapacity;

            return {
                id: `strangers_meet_timeline_${request.id}`,
                meetId: request.id,
                title: request.subject || 'Stranger Meetup',
                tagline: request.tagline || '',
                venueName,
                venueArea: reqAny.venue?.area || 'Pune',
                eventDate: eventDateStr,
                host: reqAny.user ? {
                    id: reqAny.user.id,
                    name: `${reqAny.user.firstName} ${reqAny.user.lastName}`.trim(),
                    photo: reqAny.user.profileImageUrl
                } : null,
                slotsFilled: acceptedCount,
                acceptedCount,
                maximumCapacity,
                remainingSlots,
                isFull,
                pendingRequestsCount: pendingJoiners.length,
                pendingRequests: pendingJoiners.map((j: any) => ({
                    joinerId: j.id,
                    userId: j.user?.id || j.userId,
                    name: j.user ? `${j.user.firstName} ${j.user.lastName}`.trim() : 'Participant',
                    photo: j.user?.profileImageUrl || '',
                    foodPreference: j.foodPreference,
                    drinkPreference: j.drinkPreference,
                    status: j.status,
                    createdAt: j.createdAt,
                })),
                totalSlots: request.numberOfPersons,
                chargesPerHead: request.chargesPerHead,
                currentStatusText,
                timeline,
                countdown,
                status: request.status,
                settlementStatus: request.settlementStatus,
                startedAt: request.startedAt,
                expectedEndAt: request.expectedEndAt,
                endedAt: request.endedAt,
                primaryAction,
                secondaryAction,
                primaryActionUrl,
                secondaryActionUrl,
                updatedAt: request.updatedAt ? request.updatedAt.toISOString() : new Date().toISOString()
            };
        } catch (err) {
            logger.error('[StrangersMeetService] enrichStrangersMeetNotificationCard error:', err);
            return null;
        }
    }

    /**
     * Database migration helper: creates lifecycle columns if missing
     */
    public static async ensureStrangersMeetLifecycleColumns(): Promise<void> {
        try {
            const sequelize = (await import('../config/database')).default;
            await sequelize.query(`
                ALTER TABLE strangers_meet_requests 
                ADD COLUMN IF NOT EXISTS started_at TIMESTAMP WITH TIME ZONE,
                ADD COLUMN IF NOT EXISTS started_by UUID,
                ADD COLUMN IF NOT EXISTS duration_hours DOUBLE PRECISION,
                ADD COLUMN IF NOT EXISTS expected_end_at TIMESTAMP WITH TIME ZONE,
                ADD COLUMN IF NOT EXISTS ended_at TIMESTAMP WITH TIME ZONE,
                ADD COLUMN IF NOT EXISTS ended_confirmed_by UUID,
                ADD COLUMN IF NOT EXISTS ended_confirmed_at TIMESTAMP WITH TIME ZONE,
                ADD COLUMN IF NOT EXISTS admin_confirmed_ended_at TIMESTAMP WITH TIME ZONE,
                ADD COLUMN IF NOT EXISTS admin_confirmed_by UUID,
                ADD COLUMN IF NOT EXISTS settlement_overdue BOOLEAN DEFAULT FALSE,
                ADD COLUMN IF NOT EXISTS escalated_at TIMESTAMP WITH TIME ZONE,
                ADD COLUMN IF NOT EXISTS escalation_reason TEXT,
                ADD COLUMN IF NOT EXISTS admin_resolution VARCHAR(100),
                ADD COLUMN IF NOT EXISTS admin_resolution_notes TEXT,
                ADD COLUMN IF NOT EXISTS admin_resolved_at TIMESTAMP WITH TIME ZONE,
                ADD COLUMN IF NOT EXISTS admin_resolved_by UUID,
                ADD COLUMN IF NOT EXISTS host_not_started_at TIMESTAMP WITH TIME ZONE,
                ADD COLUMN IF NOT EXISTS host_not_started_reason TEXT;
            `);
        } catch (err) {
            logger.warn('[StrangersMeetService] ensureStrangersMeetLifecycleColumns warning:', err);
        }
    }

    /**
     * Host confirms meetup started and chooses duration
     */
    public static async confirmMeetupStarted(
        meetId: string,
        hostUserId: string,
        durationHours: number,
        customEndDateTime?: string
    ): Promise<StrangersMeetRequest> {
        await this.ensureStrangersMeetLifecycleColumns();
        const request = await StrangersMeetRequest.findByPk(meetId);
        if (!request) throw new Error('Strangers Meet not found');
        if (request.userId !== hostUserId) throw new Error('Only the host can start this meetup');

        if (request.status === StrangersMeetStatus.REJECTED || request.status === StrangersMeetStatus.COMPLETED) {
            throw new Error('This meetup is already completed or cancelled.');
        }

        if (request.paymentStatus !== StrangersMeetPaymentStatus.PAID) {
            throw new Error('Host deposit payment must be completed before starting meetup.');
        }

        const now = new Date();
        const eventTime = new Date(request.eventDateTime);
        if (now.getTime() < eventTime.getTime() - 15 * 60 * 1000) {
            throw new Error('Scheduled start time has not been reached yet.');
        }

        if (request.status === StrangersMeetStatus.IN_PROGRESS && request.startedAt) {
            logger.info(`[StrangersMeetService] Meet ${meetId} already started. Idempotent return.`);
            return request;
        }

        let finalDuration = durationHours || 1;
        let expectedEnd = new Date(now.getTime() + finalDuration * 60 * 60 * 1000);

        if (customEndDateTime) {
            const parsedCustom = new Date(customEndDateTime);
            if (isNaN(parsedCustom.getTime()) || parsedCustom <= now) {
                throw new Error('Custom end time must be in the future.');
            }
            expectedEnd = parsedCustom;
            finalDuration = (expectedEnd.getTime() - now.getTime()) / (1000 * 60 * 60);
        }

        await request.update({
            status: StrangersMeetStatus.IN_PROGRESS,
            startedAt: now,
            startedBy: hostUserId,
            durationHours: Number(finalDuration.toFixed(2)),
            expectedEndAt: expectedEnd,
        });

        await AuditLog.logAction({
            userId: hostUserId,
            partyPlanId: meetId,
            action: 'Strangers Meet Started',
            metadata: { startedAt: now, durationHours: finalDuration, expectedEndAt: expectedEnd }
        });

        await this.emitNotification({
            recipientUserId: hostUserId,
            entityId: meetId,
            eventType: 'strangers_meet_started',
            title: '🎉 Strangers Meet In Progress',
            body: `Your meetup is active! Expected duration: ${finalDuration >= 1 ? finalDuration.toFixed(0) + ' hour(s)' : finalDuration.toFixed(1) + ' hours'}.`,
            notifyAdmins: false,
            metadata: { meetId, startedAt: now, expectedEndAt: expectedEnd }
        });

        return request;
    }

    /**
     * Host marks meetup as NOT STARTED
     */
    public static async hostReportNotStarted(
        meetId: string,
        hostUserId: string,
        reason?: string
    ): Promise<StrangersMeetRequest> {
        await this.ensureStrangersMeetLifecycleColumns();
        const request = await StrangersMeetRequest.findByPk(meetId);
        if (!request) throw new Error('Strangers Meet not found');
        if (request.userId !== hostUserId) throw new Error('Only the host can update status');

        if (request.status === StrangersMeetStatus.IN_PROGRESS || request.status === StrangersMeetStatus.COMPLETED) {
            throw new Error('Cannot mark as not started after meetup has already started or completed.');
        }

        const now = new Date();
        await request.update({
            status: StrangersMeetStatus.NOT_STARTED,
            hostNotStartedAt: now,
            hostNotStartedReason: reason || 'Host indicated meetup did not take place',
        });

        await AuditLog.logAction({
            userId: hostUserId,
            partyPlanId: meetId,
            action: 'Strangers Meet Marked Not Started',
            metadata: { hostNotStartedAt: now, reason }
        });

        await this.emitNotification({
            recipientUserId: hostUserId,
            entityId: meetId,
            eventType: 'strangers_meet_not_started',
            title: '⚠️ Strangers Meet Closed',
            body: 'You indicated that this Strangers Meet did not take place.',
            notifyAdmins: true,
            metadata: { meetId, status: StrangersMeetStatus.NOT_STARTED }
        });

        return request;
    }

    /**
     * Host extends in-progress meetup duration
     */
    public static async extendMeetupDuration(
        meetId: string,
        hostUserId: string,
        additionalHours?: number,
        customEndDateTime?: string
    ): Promise<StrangersMeetRequest> {
        await this.ensureStrangersMeetLifecycleColumns();
        const request = await StrangersMeetRequest.findByPk(meetId);
        if (!request) throw new Error('Strangers Meet not found');
        if (request.userId !== hostUserId) throw new Error('Only the host can extend this meetup');

        if (request.status !== StrangersMeetStatus.IN_PROGRESS && request.status !== StrangersMeetStatus.END_CONFIRMATION_PENDING) {
            throw new Error('Only in-progress meetups can be extended.');
        }

        const now = new Date();
        const currentEnd = request.expectedEndAt ? new Date(request.expectedEndAt) : now;
        const baseTime = currentEnd > now ? currentEnd : now;

        let newExpectedEnd = new Date(baseTime.getTime() + (additionalHours || 1) * 60 * 60 * 1000);
        if (customEndDateTime) {
            const parsedCustom = new Date(customEndDateTime);
            if (isNaN(parsedCustom.getTime()) || parsedCustom <= now) {
                throw new Error('Custom end time must be in the future.');
            }
            newExpectedEnd = parsedCustom;
        }

        const startRef = request.startedAt ? new Date(request.startedAt) : now;
        const totalDuration = (newExpectedEnd.getTime() - startRef.getTime()) / (1000 * 60 * 60);

        await request.update({
            status: StrangersMeetStatus.IN_PROGRESS,
            expectedEndAt: newExpectedEnd,
            durationHours: Number(totalDuration.toFixed(2)),
        });

        await this.emitNotification({
            recipientUserId: hostUserId,
            entityId: meetId,
            eventType: 'strangers_meet_duration_extended',
            title: '⏱️ Meetup Duration Extended',
            body: `Meetup expected end time updated to ${formatTime12Hour(newExpectedEnd)}.`,
            notifyAdmins: false,
            metadata: { meetId, expectedEndAt: newExpectedEnd }
        });

        return request;
    }

    /**
     * Host confirms meetup ended
     */
    public static async confirmMeetupEnded(
        meetId: string,
        hostUserId: string
    ): Promise<StrangersMeetRequest> {
        await this.ensureStrangersMeetLifecycleColumns();
        const request = await StrangersMeetRequest.findByPk(meetId);
        if (!request) throw new Error('Strangers Meet not found');
        if (request.userId !== hostUserId) throw new Error('Only the host can confirm the end of this meetup');

        if (
            request.status === StrangersMeetStatus.HOST_CONFIRMED_ENDED ||
            request.status === StrangersMeetStatus.ADMIN_CONFIRMED_ENDED ||
            request.status === StrangersMeetStatus.COMPLETED
        ) {
            logger.info(`[StrangersMeetService] Meet ${meetId} already ended. Idempotent return.`);
            return request;
        }

        const now = new Date();
        await request.update({
            status: StrangersMeetStatus.HOST_CONFIRMED_ENDED,
            endedAt: now,
            endedConfirmedBy: hostUserId,
            endedConfirmedAt: now,
        });

        await AuditLog.logAction({
            userId: hostUserId,
            partyPlanId: meetId,
            action: 'Strangers Meet Ended by Host',
            metadata: { endedAt: now }
        });

        await this.emitNotification({
            recipientUserId: hostUserId,
            entityId: meetId,
            eventType: 'strangers_meet_host_confirmed_ended',
            title: '✅ Strangers Meet Ended',
            body: 'You confirmed the meetup ended. Admin review & settlement verification is in progress.',
            notifyAdmins: true,
            metadata: { meetId, endedAt: now }
        });

        return request;
    }

    /**
     * Admin verifies completed meetup
     */
    public static async adminConfirmMeetupEnded(
        meetId: string,
        adminId: string
    ): Promise<StrangersMeetRequest> {
        await this.ensureStrangersMeetLifecycleColumns();
        const request = await StrangersMeetRequest.findByPk(meetId);
        if (!request) throw new Error('Strangers Meet not found');

        if (request.status === StrangersMeetStatus.ADMIN_CONFIRMED_ENDED || request.status === StrangersMeetStatus.COMPLETED) {
            return request;
        }

        const now = new Date();
        await request.update({
            status: StrangersMeetStatus.ADMIN_CONFIRMED_ENDED,
            adminConfirmedEndedAt: now,
            adminConfirmedBy: adminId,
            settlementStatus: 'settlement_pending',
        });

        await AuditLog.logAction({
            userId: adminId,
            partyPlanId: meetId,
            action: 'Strangers Meet End Confirmed by Admin',
            metadata: { adminConfirmedEndedAt: now }
        });

        // Host Notification after Admin confirmation: 24 hours window
        await this.emitNotification({
            recipientUserId: request.userId,
            entityId: meetId,
            eventType: 'strangers_meet_admin_confirmed_ended',
            title: '🎉 Strangers Meet Confirmed Completed',
            body: 'Your Strangers Meet has been confirmed as completed. Your settlement will be processed within 24 hours.',
            notifyAdmins: false,
            metadata: { meetId, adminConfirmedEndedAt: now }
        });

        return request;
    }

    /**
     * Admin resolves 24-hour escalation case
     */
    public static async adminResolveEscalation(
        meetId: string,
        adminId: string,
        resolution: string,
        resolutionNotes?: string
    ): Promise<StrangersMeetRequest> {
        await this.ensureStrangersMeetLifecycleColumns();
        const request = await StrangersMeetRequest.findByPk(meetId);
        if (!request) throw new Error('Strangers Meet not found');

        const now = new Date();
        let newStatus = StrangersMeetStatus.ADMIN_RESOLVED;

        if (resolution === 'meet_completed') {
            newStatus = StrangersMeetStatus.ADMIN_CONFIRMED_ENDED;
        } else if (resolution === 'meet_cancelled') {
            newStatus = StrangersMeetStatus.CANCELLED;
        } else if (resolution === 'not_started') {
            newStatus = StrangersMeetStatus.NOT_STARTED;
        }

        await request.update({
            status: newStatus,
            adminResolution: resolution,
            adminResolutionNotes: resolutionNotes || undefined,
            adminResolvedAt: now,
            adminResolvedBy: adminId,
            settlementStatus: resolution === 'meet_completed' ? 'settlement_pending' : request.settlementStatus,
        });

        await AuditLog.logAction({
            userId: adminId,
            partyPlanId: meetId,
            action: 'Strangers Meet Escalation Resolved by Admin',
            metadata: { resolution, resolutionNotes, resolvedAt: now }
        });

        await this.emitNotification({
            recipientUserId: request.userId,
            entityId: meetId,
            eventType: 'strangers_meet_escalation_resolved',
            title: '🛡️ Strangers Meet Resolution',
            body: `Admin has reviewed and resolved your meetup: ${resolution.replace(/_/g, ' ')}.`,
            notifyAdmins: false,
            metadata: { meetId, resolution }
        });

        return request;
    }

    /**
     * Automatically calculates settlement breakdown
     */
    public static async calculateSettlementSummary(meetId: string): Promise<Record<string, any>> {
        const request = await StrangersMeetRequest.findByPk(meetId, {
            include: [{ model: StrangersMeetJoiner, as: 'joiners' }]
        });
        if (!request) throw new Error('Strangers Meet not found');

        const reqAny = request as any;
        const joiners: any[] = reqAny.joiners || [];
        const paidJoiners = joiners.filter((j: any) => j.status === 'paid' || j.paymentStatus === 'paid');
        const totalSeats = request.numberOfPersons;
        const paidSlots = paidJoiners.length;
        const unfilledSeats = Math.max(0, totalSeats - paidSlots);
        const platformDepositTotal = Number(request.paymentAmount || 0);
        const platformChargePerSeat = request.platformChargePerSeat ? Number(request.platformChargePerSeat) :
            (platformDepositTotal > 0 && totalSeats > 0 ? platformDepositTotal / totalSeats : 0);
        const hostChargePerHead = Number(request.chargesPerHead || 0);
        const hostRevenueFromParticipants = paidSlots * hostChargePerHead;
        const unfilledDepositRefund = unfilledSeats * platformChargePerSeat;
        const calculatedSettlement = unfilledDepositRefund + hostRevenueFromParticipants;

        let maskedPayoutDetails = '';
        if (request.upiId) {
            maskedPayoutDetails = `UPI: ${request.upiId}`;
        } else if (request.accountNumber) {
            const acct = request.accountNumber;
            const maskedAcct = acct.length > 4 ? `••••${acct.substring(acct.length - 4)}` : acct;
            maskedPayoutDetails = `Bank: ${request.bankName || 'A/C'} (${maskedAcct})`;
        } else if (request.bankDetails) {
            maskedPayoutDetails = request.bankDetails;
        }

        return {
            meetId: request.id,
            totalSeats,
            paidSlots,
            unfilledSeats,
            platformDepositTotal,
            platformChargePerSeat,
            hostChargePerHead,
            grossCollection: hostRevenueFromParticipants,
            unfilledDepositRefund,
            calculatedSettlement,
            maskedPayoutDetails,
            upiId: request.upiId || null,
            upiNumber: request.upiNumber || null,
            accountNumber: request.accountNumber ? `••••${request.accountNumber.slice(-4)}` : null,
            bankName: request.bankName || null,
            ifscCode: request.ifscCode || null,
            accountHolderName: request.accountHolderName || null,
            status: request.status,
            settlementStatus: request.settlementStatus || 'none',
        };
    }

    /**
     * Admin executes payout and marks settlement as settled
     */
    public static async adminMarkSettled(
        meetId: string,
        adminId: string,
        paymentReference: string,
        settlementMethod: string = 'UPI',
        amount?: number
    ): Promise<StrangersMeetRequest> {
        await this.ensureStrangersMeetLifecycleColumns();
        const request = await StrangersMeetRequest.findByPk(meetId, {
            include: [{ model: StrangersMeetJoiner, as: 'joiners' }]
        });
        if (!request) throw new Error('Strangers Meet not found');

        if (request.settlementStatus === 'paid' || request.settlementStatus === 'settled') {
            logger.info(`[StrangersMeetService] Meet ${meetId} already settled. Idempotent return.`);
            return request;
        }

        if (!paymentReference || !paymentReference.trim()) {
            throw new Error('Payment reference is required.');
        }

        const summary = await this.calculateSettlementSummary(meetId);
        const finalSettlementAmount = (amount !== undefined && amount !== null && !isNaN(amount))
            ? Number(amount)
            : summary.calculatedSettlement;

        const now = new Date();
        await request.update({
            status: StrangersMeetStatus.COMPLETED,
            settlementStatus: 'settled',
            settlementAmount: finalSettlementAmount,
            settlementTransactionId: paymentReference.trim(),
            settlementMethod: settlementMethod.trim(),
            settlementDate: now,
            settlementOverdue: false,
            adminConfirmedBy: adminId,
        });

        await AuditLog.logAction({
            userId: adminId,
            partyPlanId: meetId,
            action: 'Strangers Meet Settlement Marked Settled by Admin',
            metadata: {
                settlementAmount: finalSettlementAmount,
                paymentReference,
                settlementMethod,
                settledAt: now,
            }
        });

        const formattedDate = now.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });

        // Host Final Notification after amount settled - updates existing card in-place
        await this.emitNotification({
            recipientUserId: request.userId,
            entityId: meetId,
            eventType: 'strangers_meet_settled',
            title: '💰 Strangers Meet Settlement Completed',
            body: `Your settlement of ₹${finalSettlementAmount.toFixed(0)} has been completed via ${settlementMethod}. Ref: ${paymentReference}. Date: ${formattedDate}.`,
            notifyAdmins: false,
            metadata: {
                meetId,
                totalAmount: summary.grossCollection,
                settledAmount: finalSettlementAmount,
                settlementMethod,
                paymentReference,
                settlementDate: now.toISOString(),
                maskedPayoutDetails: summary.maskedPayoutDetails,
            }
        });

        return request;
    }
}
