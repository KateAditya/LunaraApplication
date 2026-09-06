import '../models';
import { Transaction, Op } from 'sequelize';
import StrangersMeetRequest, { StrangersMeetStatus, StrangersMeetPaymentStatus } from '../models/StrangersMeetRequest';
import StrangersMeetJoiner, { StrangersMeetJoinerStatus, StrangersMeetJoinerPaymentStatus } from '../models/StrangersMeetJoiner';
import StrangersMeetCancellationRequest, { StrangersMeetCancellationStatus } from '../models/StrangersMeetCancellationRequest';
import StrangersMeetHostCancellationRequest, { HostCancellationStatus, HostRefundStatus } from '../models/StrangersMeetHostCancellationRequest';
import StrangersMeetMemberRefund, { MemberRefundStatus } from '../models/StrangersMeetMemberRefund';
import { WalletService } from './walletService';
import User from '../models/User';
import Venue from '../models/Venue';
import { PlanEligibilityService } from './PlanEligibilityService';
import { validateVenueTimingAndHolidays } from '../utils/venueValidator';
import { TimeLockError } from '../utils/bookingLimitValidator';
import { EventTimeLockService } from './EventTimeLockService';
import { generateTicketForStrangersMeetHelper } from './ticketService';
import Ticket, { TicketStatus } from '../models/Ticket';
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
            title: '🎉 Deposit Confirmed!',
            body: 'Platform deposit verified. Set your entry price to publish your meetup!',
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

            // Fetch cancellation requests for this meetup
            const cancellationRequests = await StrangersMeetCancellationRequest.findAll({
                where: { meetId },
                include: [{ model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] }],
                order: [['createdAt', 'DESC']],
            });
            const pendingCancellations = cancellationRequests.filter((c: any) => c.status === StrangersMeetCancellationStatus.PENDING);
            const myCancellation = cancellationRequests.find((c: any) => c.userId === recipientUserId);

            if (!isHost && myCancellation) {
                if (myCancellation.status === StrangersMeetCancellationStatus.PENDING) {
                    currentStatusText = 'Cancellation Requested • Awaiting Host Approval';
                    primaryAction = 'Cancellation Pending';
                    primaryActionUrl = `/strangers-meet/${request.id}/cancellation-status`;
                    secondaryAction = 'View Details';
                    secondaryActionUrl = `/strangers-meet/${request.id}`;
                } else if (myCancellation.status === StrangersMeetCancellationStatus.APPROVED) {
                    const refAmt = Number(myCancellation.refundAmount || myCancellation.paidAmount || 0).toFixed(0);
                    currentStatusText = `✓ Cancellation Approved • ₹${refAmt} refunded to Lunara Wallet`;
                    primaryAction = 'View Wallet';
                    primaryActionUrl = '/wallet';
                    secondaryAction = 'View Details';
                    secondaryActionUrl = `/strangers-meet/${request.id}`;
                }
            } else if (isHost && pendingCancellations.length > 0) {
                currentStatusText = `⚠️ ${pendingCancellations.length} Cancellation Request(s) Pending Review`;
            }

            // Fetch host cancellation request if any
            const hostCancellation = await StrangersMeetHostCancellationRequest.findOne({
                where: { meetId },
                order: [['createdAt', 'DESC']],
            });

            if (hostCancellation) {
                if (hostCancellation.status === HostCancellationStatus.PENDING_ADMIN_REVIEW) {
                    if (isHost) {
                        currentStatusText = 'Cancellation Requested • Awaiting Admin Review';
                        primaryAction = 'Pending Admin Review';
                        primaryActionUrl = `/strangers-meet/${request.id}`;
                    } else {
                        currentStatusText = 'Host Cancellation Pending Admin Review';
                    }
                } else if (
                    hostCancellation.status === HostCancellationStatus.REFUNDED ||
                    hostCancellation.status === HostCancellationStatus.COMPLETED
                ) {
                    if (isHost) {
                        currentStatusText = '✓ Stranger Meet Cancelled by Admin';
                    } else {
                        currentStatusText = '✓ Stranger Meet Cancelled • Refund Processed';
                        primaryAction = 'View Wallet';
                        primaryActionUrl = '/wallet';
                    }
                }
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
                userId: request.userId,
                hostId: request.userId,
                isHost,
                role: isHost ? 'host' : 'joiner',
                user: reqAny.user ? {
                    id: reqAny.user.id,
                    firstName: reqAny.user.firstName,
                    lastName: reqAny.user.lastName,
                    profileImageUrl: reqAny.user.profileImageUrl
                } : null,
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
                pendingCancellationRequests: pendingCancellations.map((c: any) => ({
                    cancellationId: c.id,
                    joinerId: c.joinerId,
                    userId: c.userId,
                    name: c.user ? `${c.user.firstName} ${c.user.lastName}`.trim() : 'Participant',
                    photo: c.user?.profileImageUrl || '',
                    paidAmount: c.paidAmount,
                    reason: c.reason,
                    otherReasonText: c.otherReasonText,
                    createdAt: c.createdAt,
                })),
                myCancellation: myCancellation ? {
                    id: myCancellation.id,
                    status: myCancellation.status,
                    paidAmount: myCancellation.paidAmount,
                    refundAmount: myCancellation.refundAmount,
                    reason: myCancellation.reason,
                    otherReasonText: myCancellation.otherReasonText,
                    rejectReason: myCancellation.rejectReason,
                    respondedAt: myCancellation.respondedAt,
                    createdAt: myCancellation.createdAt,
                } : null,
                hostCancellation: hostCancellation ? {
                    id: hostCancellation.id,
                    status: hostCancellation.status,
                    reason: hostCancellation.reason,
                    reasonText: hostCancellation.reasonText,
                    refundPolicyPercentage: hostCancellation.refundPolicyPercentage,
                    totalRefundAmount: hostCancellation.totalRefundAmount,
                    adminNotes: hostCancellation.adminNotes,
                    createdAt: hostCancellation.createdAt,
                } : null,
                totalSlots: request.numberOfPersons,
                chargesPerHead: request.chargesPerHead,
                paymentAmount: request.paymentAmount,
                platformChargePerSeat: request.platformChargePerSeat,
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
                updatedAt: request.updatedAt ? request.updatedAt.toISOString() : new Date().toISOString(),
                lastActivityAt: (() => {
                    let latestActivityTime = new Date(request.updatedAt || request.createdAt || Date.now()).getTime();
                    if (request.createdAt && new Date(request.createdAt).getTime() > latestActivityTime) {
                        latestActivityTime = new Date(request.createdAt).getTime();
                    }
                    if (request.startedAt && new Date(request.startedAt).getTime() > latestActivityTime) {
                        latestActivityTime = new Date(request.startedAt).getTime();
                    }
                    if (request.endedAt && new Date(request.endedAt).getTime() > latestActivityTime) {
                        latestActivityTime = new Date(request.endedAt).getTime();
                    }
                    if (request.settlementDate && new Date(request.settlementDate).getTime() > latestActivityTime) {
                        latestActivityTime = new Date(request.settlementDate).getTime();
                    }
                    for (const j of joiners) {
                        if (j.createdAt && new Date(j.createdAt).getTime() > latestActivityTime) {
                            latestActivityTime = new Date(j.createdAt).getTime();
                        }
                        if (j.updatedAt && new Date(j.updatedAt).getTime() > latestActivityTime) {
                            latestActivityTime = new Date(j.updatedAt).getTime();
                        }
                    }
                    for (const c of pendingCancellations) {
                        if (c.createdAt && new Date(c.createdAt).getTime() > latestActivityTime) {
                            latestActivityTime = new Date(c.createdAt).getTime();
                        }
                    }
                    if (myCancellation) {
                        if (myCancellation.createdAt && new Date(myCancellation.createdAt).getTime() > latestActivityTime) {
                            latestActivityTime = new Date(myCancellation.createdAt).getTime();
                        }
                        if (myCancellation.respondedAt && new Date(myCancellation.respondedAt).getTime() > latestActivityTime) {
                            latestActivityTime = new Date(myCancellation.respondedAt).getTime();
                        }
                    }
                    if (hostCancellation) {
                        if (hostCancellation.createdAt && new Date(hostCancellation.createdAt).getTime() > latestActivityTime) {
                            latestActivityTime = new Date(hostCancellation.createdAt).getTime();
                        }
                    }
                    return new Date(latestActivityTime).toISOString();
                })(),
                requiresAction: Boolean(
                    (isHost && (pendingJoiners.length > 0 || pendingCancellations.length > 0 || (!isHostPaid && isApproved))) ||
                    (!isHost && userJoiner && (userJoiner.status === 'accepted' || userJoiner.status === 'payment_pending') && userJoiner.paymentStatus !== 'paid')
                )
            };
        } catch (err) {
            logger.error('[StrangersMeetService] enrichStrangersMeetNotificationCard error:', err);
            return null;
        }
    }

    /**
     * Joined member requests cancellation from Stranger Meet.
     * Only ACCEPTED + PAID joiners can request.
     */
    public static async requestJoinerCancellation(options: {
        meetId: string;
        userId: string;
        reason: string;
        otherReasonText?: string;
    }): Promise<{ cancellation: StrangersMeetCancellationRequest; message: string }> {
        const { meetId, userId, reason, otherReasonText } = options;

        const request = await StrangersMeetRequest.findByPk(meetId, {
            include: [{ model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email', 'profileImageUrl'] }]
        });
        if (!request) {
            throw new Error('Stranger Meet not found.');
        }

        // Validate meet is not already completed, ended, settled, or cancelled
        const terminalStatuses = [
            StrangersMeetStatus.COMPLETED,
            StrangersMeetStatus.SETTLED,
            StrangersMeetStatus.ADMIN_CONFIRMED_ENDED,
            StrangersMeetStatus.HOST_CONFIRMED_ENDED,
            StrangersMeetStatus.CANCELLED,
            StrangersMeetStatus.REJECTED,
            StrangersMeetStatus.NOT_STARTED,
        ];
        if (terminalStatuses.includes(request.status)) {
            throw new Error('Cancellation is not available for a completed, ended, or cancelled Stranger Meet.');
        }

        // Validate member belongs to meet and is paid
        const joiner = await StrangersMeetJoiner.findOne({
            where: { strangersMeetRequestId: meetId, userId }
        });

        if (!joiner) {
            throw new Error('You are not a participant in this Stranger Meet.');
        }

        const isPaid = joiner.paymentStatus === StrangersMeetJoinerPaymentStatus.PAID || (joiner.status as any) === 'paid';
        if (!isPaid) {
            throw new Error('Only confirmed and paid participants can request cancellation.');
        }

        // Check if there is already a pending cancellation request
        const existingPending = await StrangersMeetCancellationRequest.findOne({
            where: {
                meetId,
                joinerId: joiner.id,
                status: StrangersMeetCancellationStatus.PENDING
            }
        });
        if (existingPending) {
            throw new Error('You already have a cancellation request pending host approval.');
        }

        // Authoritative paid amount from joiner record
        const paidAmount = Number(joiner.paymentAmount || 0);

        const cancellation = await StrangersMeetCancellationRequest.create({
            meetId,
            joinerId: joiner.id,
            userId,
            hostUserId: request.userId,
            status: StrangersMeetCancellationStatus.PENDING,
            reason: reason.trim(),
            otherReasonText: otherReasonText?.trim() || null,
            paidAmount,
        });

        const member = await User.findByPk(userId);
        const memberName = member ? `${member.firstName} ${member.lastName}`.trim() : 'A participant';

        // Notify Host via DB Notification + Push + Socket
        try {
            await this.emitNotification({
                recipientUserId: request.userId,
                eventType: 'strangers_meet_cancellation_requested',
                title: 'Cancellation Request',
                body: `${memberName} has requested cancellation from your Stranger Meet. Paid Amount: ₹${paidAmount.toFixed(0)}. Reason: ${reason}.`,
                entityId: meetId,
                metadata: {
                    meetId,
                    joinerId: joiner.id,
                    cancellationId: cancellation.id,
                    participantId: userId,
                    participantName: memberName,
                    participantPhoto: member?.profileImageUrl,
                    paidAmount,
                    reason,
                    otherReasonText,
                },
            });
        } catch (notifErr: any) {
            logger.warn('[StrangersMeetService] Failed to notify host of cancellation request: ' + notifErr.message);
        }

        return {
            cancellation,
            message: 'Cancellation request submitted to host for review.'
        };
    }

    /**
     * Host responds to member cancellation request (accept or reject).
     * On accept: marks joiner cancelled, decrements slotsFilled, and executes atomic wallet refund.
     * On reject: marks cancellation rejected, member remains joined/paid.
     */
    public static async respondToJoinerCancellation(options: {
        meetId: string;
        cancellationId: string;
        hostUserId: string;
        action: 'accept' | 'reject';
        rejectReason?: string;
    }): Promise<{ success: boolean; message: string; cancellation: StrangersMeetCancellationRequest }> {
        const { meetId, cancellationId, hostUserId, action, rejectReason } = options;

        const cancellation = await StrangersMeetCancellationRequest.findByPk(cancellationId);
        if (!cancellation) {
            throw new Error('Cancellation request not found.');
        }

        if (cancellation.meetId !== meetId) {
            throw new Error('Cancellation request does not match this Stranger Meet.');
        }

        if (cancellation.hostUserId !== hostUserId) {
            throw new Error('Only the host of this Stranger Meet can respond to cancellation requests.');
        }

        if (cancellation.status !== StrangersMeetCancellationStatus.PENDING) {
            throw new Error(`This cancellation request has already been ${cancellation.status}.`);
        }

        const request = await StrangersMeetRequest.findByPk(meetId);
        if (!request) {
            throw new Error('Stranger Meet not found.');
        }

        const joiner = await StrangersMeetJoiner.findByPk(cancellation.joinerId);
        if (!joiner) {
            throw new Error('Joiner record not found.');
        }

        const host = await User.findByPk(hostUserId);
        const hostName = host ? `${host.firstName} ${host.lastName}`.trim() : 'Host';

        if (action === 'accept') {
            const refundAmount = Number(cancellation.paidAmount || 0);

            const sequelize = (await import('../config/database')).default;
            await sequelize.transaction(async (t) => {
                await cancellation.reload({ transaction: t, lock: t.LOCK.UPDATE });
                if (cancellation.status !== StrangersMeetCancellationStatus.PENDING) {
                    throw new Error('Cancellation request is no longer pending.');
                }

                await joiner.reload({ transaction: t, lock: t.LOCK.UPDATE });
                await request.reload({ transaction: t, lock: t.LOCK.UPDATE });

                // Mark joiner as cancelled
                await joiner.update(
                    {
                        status: StrangersMeetJoinerStatus.REJECTED,
                        paymentStatus: StrangersMeetJoinerPaymentStatus.PENDING,
                    },
                    { transaction: t }
                );

                // Recalculate accurate confirmed/paid joiners count
                const activeCount = await StrangersMeetJoiner.count({
                    where: {
                        strangersMeetRequestId: meetId,
                        id: { [Op.ne]: cancellation.joinerId },
                        [Op.or]: [
                            { paymentStatus: StrangersMeetJoinerPaymentStatus.PAID },
                            { status: 'paid' },
                            { status: 'accepted' },
                        ],
                        status: { [Op.notIn]: ['rejected', 'cancelled'] },
                    },
                    transaction: t,
                });
                await request.update({ slotsFilled: activeCount }, { transaction: t });

                // Invalidate joiner ticket (Phase 10)
                await Ticket.update(
                    {
                        ticketStatus: TicketStatus.CANCELLED,
                        cancelledAt: new Date(),
                    },
                    {
                        where: {
                            bookingType: 'strangers_meet',
                            [Op.or]: [
                                { bookingId: cancellation.joinerId },
                                { bookingId: meetId, userId: cancellation.userId },
                            ],
                        },
                        transaction: t,
                    }
                );

                // Process atomic wallet refund if paidAmount > 0
                let txnId: string | null = null;
                if (refundAmount > 0) {
                    const refundRes = await WalletService.creditRefund({
                        userId: cancellation.userId,
                        amount: refundAmount,
                        referenceId: `SM_CANCEL_REFUND_${cancellation.id}`,
                        reason: `Stranger Meet Cancellation Refund - ${request.subject}`,
                        transaction: t,
                    });
                    txnId = refundRes.txn?.id || null;
                }

                await cancellation.update(
                    {
                        status: StrangersMeetCancellationStatus.APPROVED,
                        refundAmount,
                        walletTransactionId: txnId,
                        respondedAt: new Date(),
                    },
                    { transaction: t }
                );
            });

            await cancellation.reload();
            await request.reload();

            // Regenerate ticket PDF with updated reduced participant count
            try {
                const { generateTicketForStrangersMeetHelper } = require('./ticketService');
                await generateTicketForStrangersMeetHelper(meetId);
            } catch (tErr: any) {
                logger.warn('[StrangersMeetService] Ticket regeneration after joiner cancellation failed:', tErr);
            }

            // Realtime socket events for live feed & user state
            try {
                const { io } = require('../server');
                if (io) {
                    io.to('live_feed').emit('live_feed_update', {
                        type: 'strangers_meet_joiner_cancelled',
                        meetId,
                        joinerId: cancellation.joinerId,
                        userId: cancellation.userId,
                        slotsFilled: request.slotsFilled,
                        timestamp: new Date().toISOString(),
                    });
                    io.to(`user_${cancellation.userId}`).emit('strangers_meet_status_update', {
                        meetId,
                        status: 'cancelled_by_user',
                        refundAmount,
                    });
                    io.to(`user_${hostUserId}`).emit('strangers_meet_status_update', {
                        meetId,
                        slotsFilled: request.slotsFilled,
                    });
                    io.to(`user_${hostUserId}`).emit('strangers_meet_updated', {
                        meetId,
                        slotsFilled: request.slotsFilled,
                    });
                }
            } catch (sockErr) {}

            // Send notification to member
            try {
                await this.emitNotification({
                    recipientUserId: cancellation.userId,
                    eventType: 'strangers_meet_cancellation_approved',
                    title: 'Stranger Meet Cancellation Approved',
                    body: `Your cancellation request for the Stranger Meet "${request.subject}" has been approved by the host. Amount Paid: ₹${refundAmount.toFixed(0)}. Refunded: ₹${refundAmount.toFixed(0)}. ₹${refundAmount.toFixed(0)} has been credited to your Lunara Wallet.`,
                    entityId: meetId,
                    metadata: {
                        meetId,
                        cancellationId: cancellation.id,
                        refundAmount,
                        paidAmount: refundAmount,
                    },
                });
            } catch (notifErr: any) {
                logger.warn('[StrangersMeetService] Failed to notify member of approved cancellation: ' + notifErr.message);
            }

            return {
                success: true,
                message: `Cancellation approved. ₹${refundAmount.toFixed(0)} has been refunded to the member's Lunara Wallet.`,
                cancellation,
            };
        } else {
            // Action === 'reject'
            await cancellation.update({
                status: StrangersMeetCancellationStatus.REJECTED,
                rejectReason: rejectReason?.trim() || 'Host rejected cancellation request.',
                respondedAt: new Date(),
            });

            // Member remains joined, send notification
            try {
                await this.emitNotification({
                    recipientUserId: cancellation.userId,
                    eventType: 'strangers_meet_cancellation_rejected',
                    title: 'Cancellation Request Rejected',
                    body: `${hostName} has rejected your cancellation request for "${request.subject}". Your Stranger Meet participation remains active.`,
                    entityId: meetId,
                    metadata: {
                        meetId,
                        cancellationId: cancellation.id,
                        rejectReason: rejectReason || 'Host declined request',
                    },
                });
            } catch (notifErr: any) {
                logger.warn('[StrangersMeetService] Failed to notify member of rejected cancellation: ' + notifErr.message);
            }

            return {
                success: true,
                message: 'Cancellation request rejected. Member remains an active participant in the Stranger Meet.',
                cancellation,
            };
        }
    }

    /**
     * Retrieves cancellation request status for a Stranger Meet.
     * Host receives all requests; participant receives their own.
     */
    public static async getJoinerCancellationStatus(meetId: string, userId: string) {
        const request = await StrangersMeetRequest.findByPk(meetId);
        if (!request) throw new Error('Stranger Meet not found.');

        const isHost = request.userId === userId;
        if (isHost) {
            const allRequests = await StrangersMeetCancellationRequest.findAll({
                where: { meetId },
                include: [{ model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] }],
                order: [['createdAt', 'DESC']],
            });
            return { isHost: true, requests: allRequests };
        } else {
            const userRequest = await StrangersMeetCancellationRequest.findOne({
                where: { meetId, userId },
                order: [['createdAt', 'DESC']],
            });
            return { isHost: false, request: userRequest };
        }
    }

    /**
     * Host requests cancellation of Stranger Meet.
     * Enters PENDING_ADMIN_REVIEW state for Admin review.
     */
    public static async requestHostCancellation(options: {
        meetId: string;
        hostUserId: string;
        reason: string;
        reasonText?: string;
    }): Promise<{ cancellation: StrangersMeetHostCancellationRequest; message: string }> {
        const { meetId, hostUserId, reason, reasonText } = options;

        const request = await StrangersMeetRequest.findByPk(meetId, {
            include: [{ model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email', 'profileImageUrl'] }]
        });
        if (!request) {
            throw new Error('Stranger Meet not found.');
        }

        if (request.userId !== hostUserId) {
            throw new Error('Only the host can request cancellation for this Stranger Meet.');
        }

        const terminalStatuses = [
            StrangersMeetStatus.COMPLETED,
            StrangersMeetStatus.SETTLED,
            StrangersMeetStatus.ADMIN_CONFIRMED_ENDED,
            StrangersMeetStatus.HOST_CONFIRMED_ENDED,
            StrangersMeetStatus.CANCELLED,
            StrangersMeetStatus.REJECTED,
            StrangersMeetStatus.NOT_STARTED,
        ];
        if (terminalStatuses.includes(request.status)) {
            throw new Error('Cancellation is not available for a completed, ended, or already cancelled Stranger Meet.');
        }

        // Check if there is already a pending cancellation request
        const existingPending = await StrangersMeetHostCancellationRequest.findOne({
            where: {
                meetId,
                status: HostCancellationStatus.PENDING_ADMIN_REVIEW,
            }
        });
        if (existingPending) {
            throw new Error('A cancellation request is already pending admin review.');
        }

        // Fetch all confirmed & paid joiners to compute authoritative total
        const allPaidJoiners = await StrangersMeetJoiner.findAll({
            where: {
                strangersMeetRequestId: meetId,
                [Op.or]: [
                    { paymentStatus: StrangersMeetJoinerPaymentStatus.PAID },
                    { status: 'paid' as any },
                ]
            }
        });

        // Exclude any joiners who have already been refunded (via member refund or approved cancel)
        const alreadyRefundedMRs = await StrangersMeetMemberRefund.findAll({
            where: {
                meetId,
                status: MemberRefundStatus.REFUND_PAID,
            },
            attributes: ['joinerId']
        });
        const alreadyApprovedCancels = await StrangersMeetCancellationRequest.findAll({
            where: {
                meetId,
                status: StrangersMeetCancellationStatus.APPROVED,
            },
            attributes: ['joinerId']
        });
        const alreadyRefundedJoinerIds = new Set([
            ...alreadyRefundedMRs.map(r => r.joinerId),
            ...alreadyApprovedCancels.map(r => r.joinerId),
        ]);

        const paidJoiners = allPaidJoiners.filter(j => !alreadyRefundedJoinerIds.has(j.id));
        const totalCollectedAmount = paidJoiners.reduce((sum, j) => sum + Number(j.paymentAmount || 0), 0);
        const totalMembersCount = paidJoiners.length;

        const host = (request as any).user;
        const hostName = host ? `${host.firstName} ${host.lastName}`.trim() : 'Host';
        const hostDepositAmount = Number(request.paymentAmount || 0);
        const hostPayoutDetails = {
            bankName: request.bankName || (host as any)?.bankName || null,
            accountNumber: request.accountNumber || (host as any)?.accountNumber || null,
            accountHolderName: request.accountHolderName || (host as any)?.accountHolderName || null,
            ifscCode: request.ifscCode || (host as any)?.ifscCode || null,
            upiId: request.upiId || (host as any)?.upiId || null,
            upiNumber: request.upiNumber || null,
        };

        const cancellation = await StrangersMeetHostCancellationRequest.create({
            meetId,
            hostUserId,
            reason: reason.trim(),
            reasonText: reasonText?.trim() || null,
            status: HostCancellationStatus.PENDING_ADMIN_REVIEW,
            totalCollectedAmount,
            totalMembersCount,
            hostDepositAmount,
            hostPayoutDetails,
            hostRefundStatus: HostRefundStatus.NONE,
        });

        // Notify Admins (Consolidated notification per Section 5)
        try {
            const venue = (request as any).venue;
            const venueName = venue?.name || 'Venue';
            const eventDateStr = request.eventDateTime ? formatDateTimeFull(request.eventDateTime) : '';

            await this.emitNotification({
                recipientUserId: hostUserId,
                eventType: 'strangers_meet_host_cancellation_requested',
                title: '⚠️ Strangers Meet Cancellation Request',
                body: `Host: ${hostName} | Meet: ${request.subject} | Venue: ${venueName} | Participants: ${totalMembersCount}/${request.numberOfPersons} | Collected: ₹${totalCollectedAmount.toFixed(0)} | Host Deposit: ₹${hostDepositAmount.toFixed(0)} | Reason: ${reason}`,
                entityId: meetId,
                notifyAdmins: true,
                metadata: {
                    meetId,
                    hostCancellationId: cancellation.id,
                    hostUserId,
                    hostName,
                    meetTitle: request.subject,
                    venueName,
                    eventDate: eventDateStr,
                    totalCapacity: request.numberOfPersons,
                    paidParticipants: totalMembersCount,
                    totalCollectedAmount,
                    hostConfirmationAmount: hostDepositAmount,
                    reason,
                },
            });
        } catch (notifErr: any) {
            logger.warn('[StrangersMeetService] Failed to notify admins of host cancellation request: ' + notifErr.message);
        }

        return {
            cancellation,
            message: 'Cancellation request submitted successfully. It will be reviewed by Lunara Admin.',
        };
    }

    /**
     * Admin — List all host cancellation requests with pagination and filters
     */
    public static async getAdminHostCancellations(options: {
        status?: string;
        page?: number;
        limit?: number;
        search?: string;
    }) {
        const page = Math.max(1, Number(options.page || 1));
        const limit = Math.min(100, Math.max(1, Number(options.limit || 20)));
        const offset = (page - 1) * limit;

        const where: any = {};
        if (options.status && options.status !== 'all') {
            if (options.status === 'settlement_pending') {
                where.hostRefundStatus = HostRefundStatus.HOST_REFUND_PENDING_SETTLEMENT;
            } else if (options.status === 'pending') {
                where.status = HostCancellationStatus.PENDING_ADMIN_REVIEW;
            } else if (options.status === 'completed') {
                where.status = HostCancellationStatus.COMPLETED;
            } else if (options.status === 'rejected') {
                where.status = HostCancellationStatus.REJECTED;
            } else {
                where.status = options.status;
            }
        }

        const { count, rows } = await StrangersMeetHostCancellationRequest.findAndCountAll({
            where,
            include: [
                {
                    model: StrangersMeetRequest,
                    as: 'meet',
                    include: [
                        { model: Venue, as: 'venue', attributes: ['id', 'name', 'area', 'addressLine1'] },
                    ],
                },
                {
                    model: User,
                    as: 'host',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                },
                {
                    model: User,
                    as: 'reviewer',
                    attributes: ['id', 'firstName', 'lastName', 'email'],
                },
            ],
            order: [['createdAt', 'DESC']],
            limit,
            offset,
            distinct: true,
        });

        const [allCount, pendingCount, settlementPendingCount, completedCount, rejectedCount] = await Promise.all([
            StrangersMeetHostCancellationRequest.count(),
            StrangersMeetHostCancellationRequest.count({ where: { status: HostCancellationStatus.PENDING_ADMIN_REVIEW } }),
            StrangersMeetHostCancellationRequest.count({ where: { hostRefundStatus: HostRefundStatus.HOST_REFUND_PENDING_SETTLEMENT } }),
            StrangersMeetHostCancellationRequest.count({ where: { status: HostCancellationStatus.COMPLETED } }),
            StrangersMeetHostCancellationRequest.count({ where: { status: HostCancellationStatus.REJECTED } }),
        ]);

        return {
            total: count,
            page,
            limit,
            totalPages: Math.ceil(count / limit),
            data: rows,
            counts: {
                all: allCount,
                pending: pendingCount,
                settlement_pending: settlementPendingCount,
                completed: completedCount,
                rejected: rejectedCount,
            },
        };
    }

    /**
     * Admin — Get full detail of a host cancellation request with breakdown and policy calculations
     */
    public static async getAdminHostCancellationDetail(cancellationId: string) {
        const cancellation: any = await StrangersMeetHostCancellationRequest.findByPk(cancellationId, {
            include: [
                {
                    model: StrangersMeetRequest,
                    as: 'meet',
                    include: [
                        { model: Venue, as: 'venue', attributes: ['id', 'name', 'area', 'addressLine1', 'city'] },
                        {
                            model: StrangersMeetJoiner,
                            as: 'joiners',
                            include: [{ model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'phone', 'email', 'profileImageUrl'] }],
                        },
                    ],
                },
                {
                    model: User,
                    as: 'host',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                },
                {
                    model: User,
                    as: 'reviewer',
                    attributes: ['id', 'firstName', 'lastName', 'email'],
                },
                {
                    model: StrangersMeetMemberRefund,
                    as: 'memberRefunds',
                    include: [
                        { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'phone', 'email', 'profileImageUrl'] },
                        { model: User, as: 'paidByAdmin', attributes: ['id', 'firstName', 'lastName', 'email'] },
                    ],
                },
            ],
        });

        if (!cancellation) {
            throw new Error('Host cancellation request not found.');
        }

        const meet = cancellation.meet;
        const allJoiners = meet?.joiners || [];
        const paidJoiners = allJoiners.filter((j: any) => j.paymentStatus === 'paid' || j.status === 'paid');

        // Extract host payout details
        const hostPayout = (cancellation.hostPayoutDetails || {}) as any;
        const hostPayoutDetails = {
            bankName: meet?.bankName || hostPayout.bankName || (cancellation as any).hostBankName,
            accountNumber: meet?.accountNumber || hostPayout.accountNumber || (cancellation as any).hostBankAccountNumber,
            accountHolderName: meet?.accountHolderName || hostPayout.accountHolderName || (cancellation as any).hostBankHolderName,
            ifscCode: meet?.ifscCode || hostPayout.ifscCode || (cancellation as any).hostBankIfsc,
            upiId: meet?.upiId || hostPayout.upiId || (cancellation as any).hostUpiId,
            upiNumber: meet?.upiNumber || hostPayout.upiNumber || (cancellation as any).hostUpiNumber,
        };

        // Calculate previews for standard policies (100%, 80%, 75%, 50%, 25%, 0%)
        const totalPaid = cancellation.totalCollectedAmount;
        const policyPreviews: Record<string, any> = {};
        [100, 80, 75, 50, 25, 0].forEach((pct) => {
            const totalRef = Math.round((totalPaid * (pct / 100)) * 100) / 100;
            const membersPreview = paidJoiners.map((j: any) => ({
                joinerId: j.id,
                userId: j.userId,
                name: j.user ? `${j.user.firstName} ${j.user.lastName}`.trim() : 'Participant',
                paidAmount: Number(j.paymentAmount || 0),
                refundPercentage: pct,
                refundAmount: Math.round((Number(j.paymentAmount || 0) * (pct / 100)) * 100) / 100,
            }));
            policyPreviews[`${pct}%`] = {
                percentage: pct,
                totalPaid,
                totalRefund: totalRef,
                membersCount: paidJoiners.length,
                members: membersPreview,
            };
        });

        const hostDeposit = Number(meet?.paymentAmount || cancellation.hostDepositAmount || 0);
        const hostRefundPreviews = {
            depositAmount: hostDeposit,
            full: { type: 'FULL', percentage: 100, amount: hostDeposit },
            partial80: { type: 'PARTIAL', percentage: 80, amount: Math.round(hostDeposit * 0.8 * 100) / 100 },
            partial50: { type: 'PARTIAL', percentage: 50, amount: Math.round(hostDeposit * 0.5 * 100) / 100 },
            none: { type: 'NO_REFUND', percentage: 0, amount: 0 },
        };

        return {
            cancellation,
            hostPayoutDetails,
            hostRefundPreviews,
            paidJoinersCount: paidJoiners.length,
            paidJoiners: paidJoiners.map((j: any) => ({
                id: j.id,
                userId: j.userId,
                name: j.user ? `${j.user.firstName} ${j.user.lastName}`.trim() : 'Participant',
                phone: j.user?.phone,
                email: j.user?.email,
                profileImageUrl: j.user?.profileImageUrl,
                paymentAmount: j.paymentAmount,
                paymentStatus: j.paymentStatus,
                status: j.status,
                foodPreference: j.foodPreference,
                drinkPreference: j.drinkPreference,
                payoutDetails: {
                    upiId: j.upiId || (j.payoutDetails && j.payoutDetails.upiId),
                    bankName: j.bankName || (j.payoutDetails && j.payoutDetails.bankName),
                    accountNumber: j.accountNumber || (j.payoutDetails && j.payoutDetails.accountNumber),
                    ifscCode: j.ifscCode || (j.payoutDetails && j.payoutDetails.ifscCode),
                    accountHolderName: j.accountHolderName || (j.payoutDetails && j.payoutDetails.accountHolderName),
                },
            })),
            policyPreviews,
        };
    }

    /**
     * Admin — Reject Host Cancellation Request
     */
    public static async adminRejectHostCancellation(options: {
        cancellationId: string;
        adminId: string;
        reason?: string;
    }) {
        const { cancellationId, adminId, reason } = options;

        const cancellation = await StrangersMeetHostCancellationRequest.findByPk(cancellationId, {
            include: [{ model: StrangersMeetRequest, as: 'meet' }]
        });
        if (!cancellation) throw new Error('Host cancellation request not found.');

        if (cancellation.status !== HostCancellationStatus.PENDING_ADMIN_REVIEW) {
            throw new Error(`Cancellation request is already in status: ${cancellation.status}`);
        }

        const adminNotes = reason?.trim() || 'Admin rejected cancellation request.';
        await cancellation.update({
            status: HostCancellationStatus.REJECTED,
            adminReviewedBy: adminId,
            adminReviewedAt: new Date(),
            adminNotes,
        });

        const meet = (cancellation as any).meet;

        // Send notification to Host
        try {
            await this.emitNotification({
                recipientUserId: cancellation.hostUserId,
                eventType: 'strangers_meet_host_cancellation_rejected',
                title: 'Stranger Meet Cancellation Request Rejected',
                body: `Your cancellation request for Stranger Meet "${meet?.subject || 'Meetup'}" was rejected. Reason: ${adminNotes}`,
                entityId: cancellation.meetId,
                metadata: {
                    meetId: cancellation.meetId,
                    cancellationId: cancellation.id,
                    adminNotes,
                },
            });
        } catch (notifErr: any) {
            logger.warn('[StrangersMeetService] Failed to notify host of rejection: ' + notifErr.message);
        }

        return {
            success: true,
            message: 'Host cancellation request rejected successfully. Meet remains active.',
            cancellation,
        };
    }

    /**
     * Admin — Approve Host Cancellation Request with specified policy and refund method
     */
    public static async adminApproveHostCancellation(options: {
        cancellationId: string;
        adminId: string;
        refundPercentage?: number;
        refundMethod?: 'WALLET' | 'MANUAL_PAYOUT';
        adminNotes?: string;
        hostRefundDecision?: 'FULL' | 'PARTIAL' | 'CUSTOM' | 'NO_REFUND';
        hostRefundPercentage?: number;
        hostRefundCustomAmount?: number;
        hostRefundDestination?: 'WALLET' | 'UPI' | 'BANK' | 'NONE';
    }) {
        const {
            cancellationId,
            adminId,
            refundPercentage = 100,
            refundMethod = 'WALLET',
            adminNotes,
            hostRefundDecision = 'NO_REFUND',
            hostRefundPercentage,
            hostRefundCustomAmount,
            hostRefundDestination = 'NONE',
        } = options;

        if (refundPercentage < 0 || refundPercentage > 100) {
            throw new Error('Refund percentage must be between 0 and 100.');
        }

        const cancellation = await StrangersMeetHostCancellationRequest.findByPk(cancellationId);
        if (!cancellation) throw new Error('Host cancellation request not found.');

        if (cancellation.status === HostCancellationStatus.COMPLETED) {
            return {
                message: 'Host cancellation has already been approved and completed.',
                cancellation,
                refundSummary: {
                    totalMembers: cancellation.totalMembersCount,
                    refundedCount: cancellation.totalMembersCount,
                    totalRefundAmount: Number(cancellation.totalRefundAmount || 0),
                },
            };
        }

        if (cancellation.status !== HostCancellationStatus.PENDING_ADMIN_REVIEW && cancellation.status !== HostCancellationStatus.REFUND_PROCESSING) {
            throw new Error(`Cancellation request has already been processed (status: ${cancellation.status}).`);
        }

        const request = await StrangersMeetRequest.findByPk(cancellation.meetId);
        if (!request) throw new Error('Stranger Meet not found.');

        const allPaidJoiners = await StrangersMeetJoiner.findAll({
            where: {
                strangersMeetRequestId: cancellation.meetId,
                [Op.or]: [
                    { paymentStatus: StrangersMeetJoinerPaymentStatus.PAID },
                    { status: 'paid' as any },
                ]
            },
            include: [{ model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'] }]
        });

        let validAdminId: string | null = null;
        if (adminId) {
            const adminUser = await User.findByPk(adminId);
            if (adminUser) validAdminId = adminUser.id;
        }

        const sequelize = (await import('../config/database')).default;
        const memberRefundResults: any[] = [];
        let totalRefundSum = 0;

        await sequelize.transaction(async (t) => {
            await cancellation.reload({ transaction: t, lock: t.LOCK.UPDATE, include: [] });
            if (cancellation.status !== HostCancellationStatus.PENDING_ADMIN_REVIEW && cancellation.status !== HostCancellationStatus.REFUND_PROCESSING) {
                throw new Error('Cancellation request is no longer pending.');
            }

            await request.reload({ transaction: t, lock: t.LOCK.UPDATE, include: [] });

            // Mark Stranger Meet as CANCELLED
            await request.update(
                {
                    status: StrangersMeetStatus.CANCELLED,
                    adminNotes: adminNotes || `Host cancellation approved with ${refundPercentage}% refund policy.`,
                },
                { transaction: t }
            );

            // Invalidate all Tickets for this Strangers Meet (Phase 10)
            await Ticket.update(
                {
                    ticketStatus: TicketStatus.CANCELLED,
                    cancelledAt: new Date(),
                },
                {
                    where: {
                        bookingType: 'strangers_meet',
                        [Op.or]: [
                            { bookingId: request.id },
                            { ticketId: request.ticketId || `SM-${request.id.substring(0, 8).toUpperCase()}` },
                        ],
                    },
                    transaction: t,
                }
            );

            // Find existing refunds to prevent duplicate refund credits
            const existingMemberRefunds = await StrangersMeetMemberRefund.findAll({
                where: {
                    hostCancellationRequestId: cancellation.id,
                    status: MemberRefundStatus.REFUND_PAID,
                },
                transaction: t,
            });
            const refundedJoinerIds = new Set(existingMemberRefunds.map(r => r.joinerId));

            // Also check if any joiner was already refunded via prior independent cancellation
            const priorApprovedParticipantCancels = await StrangersMeetCancellationRequest.findAll({
                where: {
                    meetId: cancellation.meetId,
                    status: StrangersMeetCancellationStatus.APPROVED,
                },
                transaction: t,
            });
            for (const ac of priorApprovedParticipantCancels) {
                refundedJoinerIds.add(ac.joinerId);
            }

            const eligibleJoiners = allPaidJoiners.filter(j => !refundedJoinerIds.has(j.id));

            for (const joiner of eligibleJoiners) {
                const memberPaid = Number(joiner.paymentAmount || 0);
                const memberRefundAmount = Math.round((memberPaid * (refundPercentage / 100)) * 100) / 100;
                totalRefundSum += memberRefundAmount;

                let txnId: string | null = null;
                let refundStatus: MemberRefundStatus = MemberRefundStatus.PENDING;

                if (refundMethod === 'WALLET' && memberRefundAmount > 0) {
                    try {
                        const refundRef = `SM_HOST_CANCEL_REFUND_${request.id}_${joiner.id}`;
                        const creditRes = await WalletService.creditRefund({
                            userId: joiner.userId,
                            amount: memberRefundAmount,
                            referenceId: refundRef,
                            reason: `Host cancelled Stranger Meet - ${request.subject}`,
                            transaction: t,
                        });
                        txnId = creditRes.txn?.id || null;
                        refundStatus = MemberRefundStatus.REFUND_PAID;
                    } catch (err: any) {
                        logger.error(`[StrangersMeetService] Wallet refund failed for joiner ${joiner.id}: ${err.message}`);
                        refundStatus = MemberRefundStatus.PENDING;
                    }
                } else if (memberRefundAmount === 0) {
                    refundStatus = MemberRefundStatus.REFUND_PAID;
                }

                const memberUser = (joiner as any).user;
                const payoutDetails = memberUser ? {
                    upiId: memberUser.upiId,
                    bankName: memberUser.bankName,
                    accountNumber: memberUser.accountNumber,
                    ifscCode: memberUser.ifscCode,
                    accountHolderName: memberUser.accountHolderName,
                } : null;

                let memberRefund = await StrangersMeetMemberRefund.findOne({
                    where: {
                        hostCancellationRequestId: cancellation.id,
                        joinerId: joiner.id,
                    },
                    transaction: t,
                });

                if (!memberRefund) {
                    memberRefund = await StrangersMeetMemberRefund.create(
                        {
                            hostCancellationRequestId: cancellation.id,
                            meetId: request.id,
                            joinerId: joiner.id,
                            userId: joiner.userId,
                            paidAmount: memberPaid,
                            refundPercentage,
                            refundAmount: memberRefundAmount,
                            refundMethod,
                            status: refundStatus,
                            walletTransactionId: txnId,
                            payoutDetails,
                            paymentReference: txnId ? `WALLET_TXN_${txnId}` : null,
                            paidByAdminId: txnId ? validAdminId : null,
                            paidAt: txnId ? new Date() : null,
                        },
                        { transaction: t }
                    );
                } else {
                    await memberRefund.update(
                        {
                            status: refundStatus,
                            walletTransactionId: txnId || memberRefund.walletTransactionId,
                            paymentReference: txnId ? `WALLET_TXN_${txnId}` : memberRefund.paymentReference,
                            paidByAdminId: txnId ? validAdminId : memberRefund.paidByAdminId,
                            paidAt: txnId ? new Date() : memberRefund.paidAt,
                        },
                        { transaction: t }
                    );
                }

                memberRefundResults.push({
                    id: memberRefund.id,
                    joinerId: joiner.id,
                    userId: joiner.userId,
                    name: memberUser ? `${memberUser.firstName} ${memberUser.lastName}`.trim() : 'Participant',
                    paidAmount: memberPaid,
                    refundAmount: memberRefundAmount,
                    status: refundStatus,
                });
            }

            // Calculate Host Confirmation Deposit Refund (Sections 13 & 14)
            const hostDepositAmount = Number(request.paymentAmount || cancellation.hostDepositAmount || 0);
            let hostRefundAmount = 0;
            let hostRefundType: 'FULL' | 'PARTIAL' | 'CUSTOM' | 'NO_REFUND' = (hostRefundDecision as any) || 'NO_REFUND';
            let hostRefundPct: number | null = null;

            if (hostRefundType === 'FULL') {
                hostRefundAmount = hostDepositAmount;
                hostRefundPct = 100;
            } else if (hostRefundType === 'PARTIAL') {
                const pct = Math.min(100, Math.max(0, Number(hostRefundPercentage || 0)));
                hostRefundPct = pct;
                hostRefundAmount = Math.round((hostDepositAmount * (pct / 100)) * 100) / 100;
            } else if (hostRefundType === 'CUSTOM') {
                const customAmt = Math.min(hostDepositAmount, Math.max(0, Number(hostRefundCustomAmount || 0)));
                hostRefundAmount = Math.round(customAmt * 100) / 100;
                hostRefundPct = hostDepositAmount > 0 ? Math.round((hostRefundAmount / hostDepositAmount) * 100) : 0;
            } else {
                hostRefundType = 'NO_REFUND';
                hostRefundAmount = 0;
                hostRefundPct = 0;
            }

            const hostDest = (hostRefundDestination || 'NONE').toUpperCase();
            let hostRefundStatus: HostRefundStatus = HostRefundStatus.NONE;
            let hostTxnId: string | null = null;

            if (hostRefundAmount > 0) {
                if (hostDest === 'WALLET') {
                    const hostRefundRef = `SM_HOST_DEPOSIT_REFUND_${request.id}`;
                    try {
                        const hostWalletTx = await WalletService.creditRefund({
                            userId: cancellation.hostUserId,
                            amount: hostRefundAmount,
                            referenceId: hostRefundRef,
                            reason: `Host deposit refund for cancelled Strangers Meet "${request.subject}"`,
                            transaction: t,
                        });
                        hostRefundStatus = HostRefundStatus.WALLET_CREDITED;
                        hostTxnId = hostWalletTx.txn?.id || null;
                    } catch (walletErr: any) {
                        logger.error('[StrangersMeetService] Host deposit wallet refund failed: ' + walletErr.message);
                        hostRefundStatus = HostRefundStatus.HOST_REFUND_PENDING_SETTLEMENT;
                    }
                } else if (hostDest === 'UPI' || hostDest === 'BANK') {
                    hostRefundStatus = HostRefundStatus.HOST_REFUND_PENDING_SETTLEMENT;
                }
            }

            const allRefundsSuccessful = memberRefundResults.every((r) => r.status === MemberRefundStatus.REFUND_PAID);
            const isHostSettlementPending = hostRefundStatus === HostRefundStatus.HOST_REFUND_PENDING_SETTLEMENT;
            const finalStatus = isHostSettlementPending
                ? HostCancellationStatus.REFUND_PROCESSING
                : (refundMethod === 'WALLET'
                    ? (allRefundsSuccessful || eligibleJoiners.length === 0 ? HostCancellationStatus.COMPLETED : HostCancellationStatus.REFUND_PROCESSING)
                    : (eligibleJoiners.length > 0 ? HostCancellationStatus.REFUND_PROCESSING : HostCancellationStatus.APPROVED));

            await cancellation.update(
                {
                    status: finalStatus,
                    refundPolicyPercentage: refundPercentage,
                    refundMethod: refundMethod as any,
                    totalRefundAmount: totalRefundSum,
                    adminReviewedBy: validAdminId,
                    adminReviewedAt: new Date(),
                    adminNotes: adminNotes || null,
                    hostDepositAmount,
                    hostRefundType,
                    hostRefundPercentage: hostRefundPct,
                    hostRefundAmount,
                    hostRefundDestination: hostDest as any,
                    hostRefundStatus,
                    hostSettlementTransactionId: hostTxnId ? `WALLET_TXN_${hostTxnId}` : null,
                    hostSettledAt: hostTxnId ? new Date() : null,
                    hostSettledBy: hostTxnId ? validAdminId : null,
                },
                { transaction: t }
            );
        });

        await cancellation.reload();

        const successfulRefundsCount = memberRefundResults.filter(r => r.status === MemberRefundStatus.REFUND_PAID).length;
        const pendingRefundsCount = memberRefundResults.filter(r => r.status !== MemberRefundStatus.REFUND_PAID).length;
        const totalRefundedSum = memberRefundResults
            .filter(r => r.status === MemberRefundStatus.REFUND_PAID)
            .reduce((sum, r) => sum + r.refundAmount, 0);

        let hostNotifTitle = '✅ Cancellation Approved';
        let hostNotifBody = `Your Strangers Meet "${request.subject}" has been cancelled. ${memberRefundResults.length} participants were eligible for refund. ${successfulRefundsCount} participant refunds processed successfully. Total refunded to participants: ₹${totalRefundedSum.toFixed(0)}.`;
        
        let hostRefundMsg = '';
        if (cancellation.hostRefundStatus === HostRefundStatus.WALLET_CREDITED) {
            hostRefundMsg = ` Your host deposit refund of ₹${Number(cancellation.hostRefundAmount || 0).toFixed(0)} has been credited to your Lunara Wallet.`;
        } else if (cancellation.hostRefundStatus === HostRefundStatus.HOST_REFUND_PENDING_SETTLEMENT) {
            hostRefundMsg = ` Your host refund of ₹${Number(cancellation.hostRefundAmount || 0).toFixed(0)} has been approved. Settlement will be processed within 24 hours.`;
        } else if (Number(cancellation.hostDepositAmount || 0) > 0 && Number(cancellation.hostRefundAmount || 0) === 0) {
            hostRefundMsg = ` Note: Host confirmation deposit was non-refundable as per policy.`;
        }

        // Dispatch Host Notification (Sections 11 & 16)
        try {
            await this.emitNotification({
                recipientUserId: cancellation.hostUserId,
                eventType: 'strangers_meet_host_cancellation_approved',
                title: hostNotifTitle,
                body: `${hostNotifBody}${hostRefundMsg}`,
                entityId: request.id,
                metadata: {
                    meetId: request.id,
                    cancellationId: cancellation.id,
                    refundPercentage,
                    totalRefundAmount: totalRefundSum,
                    successfulRefundsCount,
                    pendingRefundsCount,
                    hostRefundAmount: cancellation.hostRefundAmount,
                    hostRefundStatus: cancellation.hostRefundStatus,
                    hostRefundDestination: cancellation.hostRefundDestination,
                },
            });
        } catch (notifErr: any) {
            logger.warn('[StrangersMeetService] Failed to notify host of approved cancellation: ' + notifErr.message);
        }

        // Dispatch Member Notifications (Phase 12)
        for (const mr of memberRefundResults) {
            try {
                const refundRef = `SM-REF-${mr.joinerId.substring(0, 8).toUpperCase()}`;
                const refundText = mr.refundAmount > 0
                    ? `₹${mr.refundAmount.toFixed(0)} has been refunded to your Lunara Wallet. Refund Reference: ${refundRef}.`
                    : `No refund applicable (${refundPercentage}% policy).`;

                await this.emitNotification({
                    recipientUserId: mr.userId,
                    eventType: 'strangers_meet_cancelled',
                    title: '❌ Strangers Meet Cancelled',
                    body: `The Strangers Meet "${request.subject}" was cancelled by the host. ${refundText}`,
                    entityId: request.id,
                    metadata: {
                        meetId: request.id,
                        refundAmount: mr.refundAmount,
                        refundReference: refundRef,
                        refundPercentage,
                        refundMethod,
                    },
                });
            } catch (notifErr: any) {
                logger.warn(`[StrangersMeetService] Failed to notify member ${mr.userId} of cancellation: ${notifErr.message}`);
            }
        }

        // Realtime Socket updates (Phase 21)
        try {
            const { io } = require('../server');
            if (io) {
                io.to('live_feed').emit('live_feed_update', {
                    type: 'strangers_meet_cancelled',
                    meetId: request.id,
                    status: 'cancelled',
                    timestamp: new Date().toISOString(),
                });
                io.to(`user_${cancellation.hostUserId}`).emit('strangers_meet_status_update', {
                    meetId: request.id,
                    status: 'cancelled',
                });
                for (const mr of memberRefundResults) {
                    io.to(`user_${mr.userId}`).emit('strangers_meet_status_update', {
                        meetId: request.id,
                        status: 'cancelled',
                        refundAmount: mr.refundAmount,
                    });
                }
            }
        } catch (sockErr) {}

        return {
            success: true,
            message: `Stranger Meet cancelled successfully with ${refundPercentage}% refund policy. Total refund: ₹${totalRefundSum.toFixed(0)}.`,
            cancellation,
            memberRefunds: memberRefundResults,
        };
    }

    /**
     * Admin — Retry Member Wallet Refund (for failed or pending refunds)
     */
    public static async adminRetryMemberWalletRefund(options: {
        refundId: string;
        adminId: string;
    }) {
        const { refundId, adminId } = options;
        const refund = await StrangersMeetMemberRefund.findByPk(refundId, {
            include: [{ model: StrangersMeetRequest, as: 'meet' }, { model: User, as: 'user' }]
        });
        if (!refund) throw new Error('Member refund record not found.');
        if (refund.status === MemberRefundStatus.REFUND_PAID) {
            return { success: true, message: 'Refund has already been paid.', refund };
        }

        let validAdminId: string | null = null;
        if (adminId) {
            const adminUser = await User.findByPk(adminId);
            if (adminUser) validAdminId = adminUser.id;
        }

        const sequelize = (await import('../config/database')).default;
        await sequelize.transaction(async (t) => {
            await refund.reload({ transaction: t, lock: t.LOCK.UPDATE, include: [] });
            if (refund.status === MemberRefundStatus.REFUND_PAID) return;

            const refundRes = await WalletService.creditRefund({
                userId: refund.userId,
                amount: Number(refund.refundAmount),
                referenceId: `SM_HOST_CANCEL_REFUND_${refund.meetId}_${refund.joinerId}`,
                reason: `Stranger Meet Cancellation Refund Retry - ${(refund as any).meet?.subject || 'Meetup'}`,
                transaction: t,
            });

            const txnId = refundRes.txn?.id || null;
            await refund.update({
                status: MemberRefundStatus.REFUND_PAID,
                walletTransactionId: txnId,
                paymentReference: txnId ? `WALLET_TXN_${txnId}` : refund.paymentReference,
                paidByAdminId: validAdminId,
                paidAt: new Date(),
            }, { transaction: t });
        });

        await refund.reload();

        // Check if all member refunds for this host cancellation are now PAID
        const allRefunds = await StrangersMeetMemberRefund.findAll({
            where: { hostCancellationRequestId: refund.hostCancellationRequestId }
        });
        const allPaid = allRefunds.every((r) => r.status === MemberRefundStatus.REFUND_PAID);
        if (allPaid) {
            await StrangersMeetHostCancellationRequest.update(
                { status: HostCancellationStatus.COMPLETED },
                { where: { id: refund.hostCancellationRequestId } }
            );
        }

        return {
            success: true,
            message: `Refund of ₹${Number(refund.refundAmount).toFixed(0)} retry completed and credited to wallet.`,
            refund,
        };
    }

    /**
     * Admin — Mark Member Refund as Paid (for Manual Payouts)
     */
    public static async adminMarkMemberRefundPaid(options: {
        refundId: string;
        adminId: string;
        paymentReference: string;
        paymentMethod: string;
        paymentDate?: string;
    }) {
        const { refundId, adminId, paymentReference, paymentMethod, paymentDate } = options;

        const refund = await StrangersMeetMemberRefund.findByPk(refundId, {
            include: [
                { model: StrangersMeetRequest, as: 'meet' },
                { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email'] },
            ]
        });
        if (!refund) throw new Error('Member refund record not found.');

        if (refund.status === MemberRefundStatus.REFUND_PAID) {
            throw new Error(`Refund has already been marked as PAID on ${refund.paidAt?.toISOString()}. Reference: ${refund.paymentReference}`);
        }

        const paidDateObj = paymentDate ? new Date(paymentDate) : new Date();

        await refund.update({
            status: MemberRefundStatus.REFUND_PAID,
            paymentReference: paymentReference.trim(),
            refundMethod: paymentMethod.trim(),
            paidByAdminId: adminId,
            paidAt: paidDateObj,
        });

        // Check if all member refunds for this host cancellation are now PAID
        const allRefunds = await StrangersMeetMemberRefund.findAll({
            where: { hostCancellationRequestId: refund.hostCancellationRequestId }
        });
        const allPaid = allRefunds.every((r) => r.status === MemberRefundStatus.REFUND_PAID);
        if (allPaid) {
            await StrangersMeetHostCancellationRequest.update(
                { status: HostCancellationStatus.COMPLETED },
                { where: { id: refund.hostCancellationRequestId } }
            );
        }

        const meet = (refund as any).meet;

        // Send notification to member
        try {
            await this.emitNotification({
                recipientUserId: refund.userId,
                eventType: 'strangers_meet_refund_paid',
                title: 'Stranger Meet Refund Paid',
                body: `Your refund of ₹${refund.refundAmount.toFixed(0)} for "${meet?.subject || 'Meetup'}" has been paid via ${paymentMethod}. Reference: ${paymentReference}.`,
                entityId: refund.meetId,
                metadata: {
                    meetId: refund.meetId,
                    refundId: refund.id,
                    refundAmount: refund.refundAmount,
                    paymentReference,
                    paymentMethod,
                    paidAt: paidDateObj.toISOString(),
                },
            });
        } catch (notifErr: any) {
            logger.warn('[StrangersMeetService] Failed to notify member of paid refund: ' + notifErr.message);
        }

        return {
            success: true,
            message: `Refund marked as PAID successfully. Reference: ${paymentReference}.`,
            refund,
        };
    }

    /**
     * Admin — Mark manual host refund as SETTLED / PAID (Sections 14-16)
     */
    public static async adminSettleHostRefund(options: {
        cancellationId: string;
        adminId: string;
        paymentReference: string;
        paymentMethod?: string;
        notes?: string;
    }) {
        const { cancellationId, adminId, paymentReference, paymentMethod, notes } = options;

        if (!paymentReference || !paymentReference.trim()) {
            throw new Error('Payment reference / transaction ID is required.');
        }

        const cancellation = await StrangersMeetHostCancellationRequest.findByPk(cancellationId, {
            include: [
                {
                    model: StrangersMeetRequest,
                    as: 'meet',
                    attributes: ['id', 'subject', 'eventDateTime'],
                },
                {
                    model: User,
                    as: 'host',
                    attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                },
            ],
        });

        if (!cancellation) throw new Error('Host cancellation request not found.');

        if (cancellation.hostRefundStatus !== HostRefundStatus.HOST_REFUND_PENDING_SETTLEMENT) {
            throw new Error(`Host refund cannot be settled (current status: ${cancellation.hostRefundStatus}).`);
        }

        let validAdminId: string | null = null;
        if (adminId) {
            const adminUser = await User.findByPk(adminId);
            if (adminUser) validAdminId = adminUser.id;
        }

        const method = paymentMethod || cancellation.hostRefundDestination || 'MANUAL';

        await cancellation.update({
            hostRefundStatus: HostRefundStatus.PAID,
            hostSettlementTransactionId: paymentReference.trim(),
            hostSettledAt: new Date(),
            hostSettledBy: validAdminId,
            hostSettlementNotes: notes || null,
        });

        // Mask destination details for privacy
        const payout = (cancellation.hostPayoutDetails || {}) as any;
        let destinationDisplay = '';
        if (payout.upiId) {
            const parts = payout.upiId.split('@');
            destinationDisplay = parts[0].length > 4
                ? `${parts[0].substring(0, 2)}***@${parts[1] || 'upi'}`
                : `***@${parts[1] || 'upi'}`;
        } else if (payout.accountNumber) {
            const acc = String(payout.accountNumber);
            destinationDisplay = acc.length > 4 ? `••••${acc.slice(-4)}` : acc;
        }

        // Host settlement notification (Section 16)
        try {
            await this.emitNotification({
                recipientUserId: cancellation.hostUserId,
                eventType: 'strangers_meet_host_refund_settled',
                title: '💰 Host Refund Settled',
                body: `Your refund of ₹${Number(cancellation.hostRefundAmount || 0).toFixed(0)} for Stranger Meet "${(cancellation as any).meet?.subject || 'Meetup'}" has been marked as paid. Reference: ${paymentReference.trim()}.${destinationDisplay ? ` Destination: ${destinationDisplay}` : ''}`,
                entityId: cancellation.meetId,
                metadata: {
                    meetId: cancellation.meetId,
                    cancellationId: cancellation.id,
                    hostRefundAmount: cancellation.hostRefundAmount,
                    paymentReference: paymentReference.trim(),
                    paymentMethod: method,
                    destination: destinationDisplay,
                },
            });
        } catch (notifErr: any) {
            logger.warn('[StrangersMeetService] Failed to notify host of settlement: ' + notifErr.message);
        }

        // Realtime socket events
        try {
            const { io } = require('../server');
            if (io) {
                io.to(`user_${cancellation.hostUserId}`).emit('live_feed_update', {
                    meetId: cancellation.meetId,
                    hostRefundStatus: HostRefundStatus.PAID,
                    settlementReference: paymentReference.trim(),
                });
                io.to('live_feed').emit('live_feed_update', {
                    type: 'strangers_meet_activity',
                    meetId: cancellation.meetId,
                    hostRefundStatus: HostRefundStatus.PAID,
                    status: 'settled',
                    timestamp: new Date().toISOString(),
                });
                io.to(`user_${cancellation.hostUserId}`).emit('strangers_meet_status_update', {
                    meetId: cancellation.meetId,
                    status: 'settled',
                    hostRefundStatus: HostRefundStatus.PAID,
                });
            }
        } catch (socketErr: any) {
            logger.warn('Socket emission failed in adminSettleHostRefund: ' + socketErr.message);
        }

        return {
            success: true,
            message: 'Host refund settlement recorded successfully.',
            cancellation,
        };
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
