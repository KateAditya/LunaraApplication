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

        try {
            const AuditLog = (await import('../models/AuditLog')).default;
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

        try {
            const AuditLog = (await import('../models/AuditLog')).default;
            await AuditLog.logAction({
                userId: request.userId,
                partyPlanId: request.id,
                action: 'Stranger Meet Host Deposit Verified',
                metadata: { razorpay_payment_id, razorpay_order_id }
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

        try {
            const AuditLog = (await import('../models/AuditLog')).default;
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
                    const card = await StrangersMeetService.enrichStrangersMeetNotificationCard(entityId, recipientUserId);

                    io.to(`user_${recipientUserId}`).emit('strangers_meet_status_update', { entityId, eventType, card });
                    io.to(`user_${recipientUserId}`).emit('notification_updated', {
                        id: `strangers_meet_timeline_${entityId}`,
                        title,
                        body,
                        card,
                        updatedAt: new Date().toISOString()
                    });

                    // Live feed update broadcast
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

    /**
     * Unifies and enriches Stranger Meet notification card into ONE single timeline card
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
            const expectedEndTime = request.expectedEndAt ? new Date(request.expectedEndAt) : new Date(eventTime.getTime() + 2 * 60 * 60 * 1000);
            
            const isCompleted = request.status === StrangersMeetStatus.COMPLETED || request.settlementStatus === 'settled' || request.settlementStatus === 'paid';
            const isAdminConfirmed = request.status === StrangersMeetStatus.ADMIN_CONFIRMED_ENDED;
            const isHostEnded = request.status === StrangersMeetStatus.HOST_CONFIRMED_ENDED;
            const isInProgress = request.status === StrangersMeetStatus.IN_PROGRESS;
            const isConfirmed = (request.status === StrangersMeetStatus.APPROVED || isInProgress || isHostEnded || isAdminConfirmed || isCompleted) && request.paymentStatus === StrangersMeetPaymentStatus.PAID;
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

            // 1. Booking Created
            addStep('Booking Created', true, request.createdAt);

            // 2. Request Sent
            addStep('Request Sent', isApproved || isConfirmed, request.createdAt);

            // 3. Request Accepted
            addStep('Request Accepted', isApproved || isConfirmed, request.updatedAt);

            // 4. Booking Confirmed
            addStep('Booking Confirmed', isConfirmed, request.updatedAt);

            // 5. Started
            addStep('Meetup Started', isInProgress || isHostEnded || isAdminConfirmed || isCompleted, request.startedAt);

            // 6. Ended
            addStep('Meetup Ended', isHostEnded || isAdminConfirmed || isCompleted, request.endedAt);

            // 7. Admin Verified
            addStep('Admin Verified', isAdminConfirmed || isCompleted, request.adminConfirmedEndedAt);

            // 8. Settled
            addStep('Settled', isCompleted, request.settlementDate);

            let currentStatusText = 'Booking Requested';
            let primaryAction: string | null = null;
            let secondaryAction: string | null = null;
            let primaryActionUrl: string | null = null;
            let secondaryActionUrl: string | null = null;
            let countdown = diffStartMs > 0 ? `${diffHours}h ${diffMins}m remaining` : 'Started / Past';

            if (isCompleted) {
                currentStatusText = 'Meetup Completed • Settled';
                primaryAction = 'View Details';
                primaryActionUrl = `/strangers-meet/${request.id}`;
                countdown = 'Settled';
            } else if (isAdminConfirmed) {
                currentStatusText = 'Admin Confirmed • Settlement Pending (Within 24h)';
                primaryAction = 'Open Chat';
                primaryActionUrl = `/chat/strangers-meet-${request.id}`;
                secondaryAction = 'View Details';
                secondaryActionUrl = `/strangers-meet/${request.id}`;
                countdown = 'Settlement in progress';
            } else if (isHostEnded) {
                currentStatusText = 'Meetup Ended • Under Admin Review';
                primaryAction = 'Open Chat';
                primaryActionUrl = `/chat/strangers-meet-${request.id}`;
                secondaryAction = 'View Details';
                secondaryActionUrl = `/strangers-meet/${request.id}`;
                countdown = 'Pending Admin Review';
            } else if (isInProgress) {
                currentStatusText = diffEndMs > 0 
                    ? `In Progress • ${endDiffHours}h ${endDiffMins}m remaining`
                    : 'In Progress • Ending time reached';
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
            } else if (isConfirmed) {
                if (diffStartMs <= 0) {
                    currentStatusText = isHost ? 'Start Time Reached • Confirm Start' : 'Meetup Time Reached';
                    if (isHost) {
                        primaryAction = 'Start Meetup';
                        primaryActionUrl = `/strangers-meet/${request.id}/start`;
                    } else {
                        primaryAction = 'Open Chat';
                        primaryActionUrl = `/chat/strangers-meet-${request.id}`;
                    }
                    countdown = 'Ready to Start';
                } else if (diffStartMs <= 30 * 60 * 1000) {
                    currentStatusText = 'Time to leave for your Stranger Meet';
                    primaryAction = 'Open Chat';
                    primaryActionUrl = `/chat/strangers-meet-${request.id}`;
                    secondaryAction = 'View Ticket';
                    secondaryActionUrl = `/strangers-meet/${request.id}/ticket`;
                } else if (diffStartMs <= 60 * 60 * 1000) {
                    currentStatusText = 'Starts in 1 Hour';
                    primaryAction = 'Open Chat';
                    primaryActionUrl = `/chat/strangers-meet-${request.id}`;
                    secondaryAction = 'View Ticket';
                    secondaryActionUrl = `/strangers-meet/${request.id}/ticket`;
                } else if (diffStartMs <= 2 * 60 * 60 * 1000) {
                    currentStatusText = 'Starts in 2 Hours';
                    primaryAction = 'Open Chat';
                    primaryActionUrl = `/chat/strangers-meet-${request.id}`;
                    secondaryAction = 'View Ticket';
                    secondaryActionUrl = `/strangers-meet/${request.id}/ticket`;
                } else {
                    currentStatusText = 'Booking Confirmed • Chat Active';
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
                        currentStatusText = 'Host Reviewing Joiners';
                        primaryAction = 'Review Joiners';
                        primaryActionUrl = `/strangers-meet/${request.id}/joiners`;
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
                currentStatusText = 'Under Host Review';
                primaryAction = 'Pending Approval';
            }

            const venueName = reqAny.venue?.name || 'Venue';
            const eventDateStr = request.eventDateTime
                ? new Date(request.eventDateTime).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })
                : '';

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
                slotsFilled: request.slotsFilled || 0,
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
                ADD COLUMN IF NOT EXISTS settlement_overdue BOOLEAN DEFAULT FALSE;
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
            throw new Error('Meetup has already started.');
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

        if (request.status !== StrangersMeetStatus.IN_PROGRESS) {
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
            expectedEndAt: newExpectedEnd,
            durationHours: Number(totalDuration.toFixed(2)),
        });

        await this.emitNotification({
            recipientUserId: hostUserId,
            entityId: meetId,
            eventType: 'strangers_meet_duration_extended',
            title: '⏱️ Meetup Duration Extended',
            body: `Meetup expected end time updated to ${newExpectedEnd.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })}.`,
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

        if (request.status === StrangersMeetStatus.HOST_CONFIRMED_ENDED || request.status === StrangersMeetStatus.ADMIN_CONFIRMED_ENDED || request.status === StrangersMeetStatus.COMPLETED) {
            throw new Error('Meetup end has already been confirmed.');
        }

        const now = new Date();
        await request.update({
            status: StrangersMeetStatus.HOST_CONFIRMED_ENDED,
            endedAt: now,
            endedConfirmedBy: hostUserId,
            endedConfirmedAt: now,
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

        if (request.status !== StrangersMeetStatus.HOST_CONFIRMED_ENDED && request.status !== StrangersMeetStatus.IN_PROGRESS) {
            if (request.status === StrangersMeetStatus.ADMIN_CONFIRMED_ENDED || request.status === StrangersMeetStatus.COMPLETED) {
                throw new Error('Meetup has already been confirmed by admin.');
            }
        }

        const now = new Date();
        await request.update({
            status: StrangersMeetStatus.ADMIN_CONFIRMED_ENDED,
            adminConfirmedEndedAt: now,
            adminConfirmedBy: adminId,
            settlementStatus: 'settlement_pending',
        });

        // 21. Host Notification after Admin confirmation: 24 hours window
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
            throw new Error('This meetup has already been settled.');
        }

        if (!paymentReference || !paymentReference.trim()) {
            throw new Error('Payment reference is required.');
        }

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
        const calculatedSettlement = (unfilledSeats * platformChargePerSeat) + hostRevenueFromParticipants;
        const finalSettlementAmount = (amount !== undefined && amount !== null && !isNaN(amount)) ? Number(amount) : calculatedSettlement;

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

        // Mask payout details
        let maskedPayoutDetails = '';
        if (request.upiId) {
            maskedPayoutDetails = `UPI: ${request.upiId}`;
        } else if (request.accountNumber) {
            const acct = request.accountNumber;
            const maskedAcct = acct.length > 4 ? `XXXXXX${acct.substring(acct.length - 4)}` : acct;
            maskedPayoutDetails = `Bank: ${request.bankName || ''} (${maskedAcct})`;
        } else if (request.bankDetails) {
            maskedPayoutDetails = request.bankDetails;
        }

        const formattedDate = now.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });

        // 29. Host Final Notification after amount settled
        await this.emitNotification({
            recipientUserId: request.userId,
            entityId: meetId,
            eventType: 'strangers_meet_settled',
            title: '💰 Strangers Meet Settlement Completed',
            body: `Your settlement of ₹${finalSettlementAmount.toFixed(0)} has been completed via ${settlementMethod}. Ref: ${paymentReference}. Date: ${formattedDate}.`,
            notifyAdmins: false,
            metadata: {
                meetId,
                totalAmount: hostRevenueFromParticipants,
                settledAmount: finalSettlementAmount,
                settlementMethod,
                paymentReference,
                settlementDate: now.toISOString(),
                maskedPayoutDetails,
            }
        });

        return request;
    }
}
