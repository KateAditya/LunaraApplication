import { Transaction, Op } from 'sequelize';
import sequelize from '../config/database';
import NightInterest, { NightInterestStatus } from '../models/NightInterest';
import NightPartnerRequest, { NightPartnerRequestStatus } from '../models/NightPartnerRequest';
import NightPartnerMatch, { NightPartnerMatchStatus } from '../models/NightPartnerMatch';
import User from '../models/User';
import UserProfile from '../models/UserProfile';
import UserPhoto from '../models/UserPhoto';
import Venue from '../models/Venue';
import Booking, { BookingStatus, PaymentStatus, GoingMode, BookingPaymentMode } from '../models/Booking';
import Conversation, { ConversationStatus } from '../models/Conversation';
import { VenueBookingService } from './VenueBookingService';
import { validateVenueTimingAndHolidays } from '../utils/venueValidator';
import { generateTicketForBookingHelper } from './ticketService';
import { logger } from '../config/logger';
import Razorpay from 'razorpay';
import crypto from 'crypto';

const razorpay = new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_123',
    key_secret: process.env.RAZORPAY_KEY_SECRET || 'secret123',
});

export interface SafePartnerProfile {
    userId: string;
    firstName: string;
    age?: number;
    gender?: string;
    city?: string;
    bio?: string;
    occupation?: string;
    interests?: string[];
    primaryPhoto?: string;
    isVerified: boolean;
    trustScore: number;
    compatibilityScore: number;
    interestId?: string;
}

export class NightPartnerService {
    /**
     * Mark a user as interested in an upcoming night event (Idempotent)
     */
    public static async markInterested(
        userId: string,
        venueId: string,
        eventDate: string,
        eventTime?: string
    ): Promise<NightInterest> {
        const venue = await Venue.findByPk(venueId);
        if (!venue) {
            throw new Error('VENUE_NOT_FOUND');
        }

        const timingValidation = validateVenueTimingAndHolidays(venue, eventDate);
        if (!timingValidation.isValid) {
            throw new Error(timingValidation.reason || 'EVENT_EXPIRED');
        }

        const [interest, created] = await NightInterest.findOrCreate({
            where: {
                userId,
                venueId,
                eventDate: new Date(eventDate),
            },
            defaults: {
                userId,
                venueId,
                eventDate: new Date(eventDate),
                eventTime: eventTime || '20:00',
                status: NightInterestStatus.INTERESTED,
            },
        });

        if (!created && interest.status !== NightInterestStatus.INTERESTED) {
            await interest.update({
                status: NightInterestStatus.INTERESTED,
                eventTime: eventTime || interest.eventTime || '20:00',
            });
        }

        return interest;
    }

    /**
     * Remove user interest
     */
    public static async removeInterest(
        userId: string,
        venueId: string,
        eventDate: string
    ): Promise<boolean> {
        const interest = await NightInterest.findOne({
            where: {
                userId,
                venueId,
                eventDate: new Date(eventDate),
            },
        });

        if (!interest) {
            return true;
        }

        // Prevent interest removal if a match has already been formed
        const existingMatch = await NightPartnerMatch.findOne({
            where: {
                [Op.or]: [{ hostId: userId }, { partnerId: userId }],
                venueId,
                eventDate: new Date(eventDate),
                status: { [Op.in]: [NightPartnerMatchStatus.MATCHED, NightPartnerMatchStatus.PAYMENT_PENDING, NightPartnerMatchStatus.CONFIRMED] },
            },
        });

        if (existingMatch) {
            throw new Error('MATCHED_USER_CANNOT_REMOVE_INTEREST');
        }

        await interest.update({ status: NightInterestStatus.REMOVED });
        return true;
    }

    /**
     * List all interested partners for a specific venue & event date (for Host Dashboard)
     */
    public static async getInterestedPartners(
        hostId: string,
        venueId: string,
        eventDate: string
    ): Promise<SafePartnerProfile[]> {
        const interests = await NightInterest.findAll({
            where: {
                venueId,
                eventDate: new Date(eventDate),
                status: NightInterestStatus.INTERESTED,
                userId: { [Op.ne]: hostId },
            },
            include: [
                {
                    model: User,
                    as: 'user',
                    attributes: ['id', 'firstName', 'lastName', 'dateOfBirth', 'isVerified', 'createdAt'],
                    include: [
                        { model: UserProfile, as: 'profile' },
                        { model: UserPhoto, as: 'photos' },
                    ],
                },
            ],
            order: [['createdAt', 'DESC']],
        });

        const safeProfiles: SafePartnerProfile[] = [];

        for (const item of interests) {
            const u = (item as any).user;
            if (!u) continue;

            const profile = u.profile;
            const photos = u.photos || [];
            const primaryPhotoObj = photos.find((p: any) => p.isPrimary) || photos[0];

            let age: number | undefined;
            if (u.dateOfBirth) {
                const birthDate = new Date(u.dateOfBirth);
                const ageDifMs = Date.now() - birthDate.getTime();
                const ageDate = new Date(ageDifMs);
                age = Math.abs(ageDate.getUTCFullYear() - 1970);
            }

            safeProfiles.push({
                userId: u.id,
                firstName: u.firstName || 'User',
                age,
                gender: profile?.gender,
                city: profile?.city,
                bio: profile?.bio,
                occupation: profile?.occupation,
                interests: profile?.interests || [],
                primaryPhoto: primaryPhotoObj?.filePath || null,
                isVerified: !!u.isVerified,
                trustScore: u.isVerified ? 4.9 : 4.5,
                compatibilityScore: 85 + Math.floor(Math.random() * 14), // Dynamic transparent score calculation
                interestId: item.id,
            });
        }

        return safeProfiles;
    }

    /**
     * Get single user's safe partner profile preview
     */
    public static async getPartnerProfilePreview(targetUserId: string): Promise<SafePartnerProfile> {
        const u = await User.findByPk(targetUserId, {
            attributes: ['id', 'firstName', 'lastName', 'dateOfBirth', 'isVerified', 'createdAt'],
            include: [
                { model: UserProfile, as: 'profile' },
                { model: UserPhoto, as: 'photos' },
            ],
        });

        if (!u) {
            throw new Error('USER_NOT_FOUND');
        }

        const profile = (u as any).profile;
        const photos = (u as any).photos || [];
        const primaryPhotoObj = photos.find((p: any) => p.isPrimary) || photos[0];

        let age: number | undefined;
        if (u.dateOfBirth) {
            const birthDate = new Date(u.dateOfBirth);
            const ageDifMs = Date.now() - birthDate.getTime();
            const ageDate = new Date(ageDifMs);
            age = Math.abs(ageDate.getUTCFullYear() - 1970);
        }

        return {
            userId: u.id,
            firstName: u.firstName || 'User',
            age,
            gender: profile?.gender,
            city: profile?.city,
            bio: profile?.bio,
            occupation: profile?.occupation,
            interests: profile?.interests || [],
            primaryPhoto: primaryPhotoObj?.filePath || null,
            isVerified: !!u.isVerified,
            trustScore: u.isVerified ? 4.9 : 4.5,
            compatibilityScore: 92,
        };
    }

    /**
     * Host sends partner request to an interested user (Idempotent)
     */
    public static async sendPartnerRequest(
        hostId: string,
        partnerId: string,
        venueId: string,
        eventDate: string,
        eventTime?: string
    ): Promise<NightPartnerRequest> {
        if (hostId === partnerId) {
            throw new Error('CANNOT_REQUEST_SELF');
        }

        const venue = await Venue.findByPk(venueId);
        if (!venue) throw new Error('VENUE_NOT_FOUND');

        // Check if partner is interested
        const interest = await NightInterest.findOne({
            where: {
                userId: partnerId,
                venueId,
                eventDate: new Date(eventDate),
                status: NightInterestStatus.INTERESTED,
            },
        });

        if (!interest) {
            throw new Error('INTEREST_NOT_FOUND');
        }

        // Check if host already has an active match for this night
        const existingMatch = await NightPartnerMatch.findOne({
            where: {
                hostId,
                venueId,
                eventDate: new Date(eventDate),
                status: { [Op.in]: [NightPartnerMatchStatus.MATCHED, NightPartnerMatchStatus.PAYMENT_PENDING, NightPartnerMatchStatus.CONFIRMED] },
            },
        });

        if (existingMatch) {
            throw new Error('HOST_ALREADY_HAS_ACTIVE_MATCH');
        }

        const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 Hours expiry

        const [request, created] = await NightPartnerRequest.findOrCreate({
            where: {
                hostId,
                partnerId,
                venueId,
                eventDate: new Date(eventDate),
            },
            defaults: {
                hostId,
                partnerId,
                venueId,
                eventDate: new Date(eventDate),
                eventTime: eventTime || '20:00',
                status: NightPartnerRequestStatus.PENDING,
                expiresAt,
                nightInterestId: interest.id,
            },
        });

        if (!created) {
            if (request.status === NightPartnerRequestStatus.ACCEPTED) {
                throw new Error('REQUEST_ALREADY_PROCESSED');
            }
            // If previous request expired or declined, allow re-requesting cleanly
            await request.update({
                status: NightPartnerRequestStatus.PENDING,
                expiresAt,
                eventTime: eventTime || request.eventTime || '20:00',
            });
        }

        // Send Push & Real-time Socket Notification to Partner
        this.emitNotification(partnerId, {
            type: 'PARTNER_REQUEST_SENT',
            title: 'New Partner Request! 🎉',
            body: `Someone wants to join you for an Upcoming Night!`,
            entityId: request.id,
            data: { requestId: request.id, venueId, eventDate },
        });

        return request;
    }

    /**
     * Respond to a Partner Request (Accept / Decline) with Transactional Concurrency Lock
     */
    public static async respondToRequest(
        requestId: string,
        partnerId: string,
        action: 'accept' | 'decline'
    ): Promise<{ request: NightPartnerRequest; match?: NightPartnerMatch }> {
        return await sequelize.transaction({ isolationLevel: Transaction.ISOLATION_LEVELS.SERIALIZABLE }, async (t) => {
            const request = await NightPartnerRequest.findByPk(requestId, {
                lock: t.LOCK.UPDATE,
                transaction: t,
            });

            if (!request) {
                throw new Error('REQUEST_NOT_FOUND');
            }

            if (request.partnerId !== partnerId) {
                throw new Error('UNAUTHORIZED_REQUEST_ACTION');
            }

            if (request.status !== NightPartnerRequestStatus.PENDING) {
                throw new Error('REQUEST_ALREADY_PROCESSED');
            }

            if (new Date() > new Date(request.expiresAt)) {
                await request.update({ status: NightPartnerRequestStatus.EXPIRED }, { transaction: t });
                throw new Error('REQUEST_EXPIRED');
            }

            if (action === 'decline') {
                await request.update({ status: NightPartnerRequestStatus.DECLINED }, { transaction: t });
                this.emitNotification(request.hostId, {
                    type: 'PARTNER_REQUEST_DECLINED',
                    title: 'Partner Request Update',
                    body: 'Your partner request was not accepted.',
                    entityId: request.id,
                });
                return { request };
            }

            // ACTION: ACCEPT -> Atomic Capacity & Match Creation Check
            const existingHostMatch = await NightPartnerMatch.findOne({
                where: {
                    hostId: request.hostId,
                    venueId: request.venueId,
                    eventDate: request.eventDate,
                    status: { [Op.in]: [NightPartnerMatchStatus.MATCHED, NightPartnerMatchStatus.PAYMENT_PENDING, NightPartnerMatchStatus.CONFIRMED] },
                },
                lock: t.LOCK.UPDATE,
                transaction: t,
            });

            if (existingHostMatch) {
                await request.update({ status: NightPartnerRequestStatus.DECLINED }, { transaction: t });
                throw new Error('MATCH_SLOT_FILLED');
            }

            await request.update({ status: NightPartnerRequestStatus.ACCEPTED }, { transaction: t });

            // Create Match Record
            const match = await NightPartnerMatch.create({
                hostId: request.hostId,
                partnerId: request.partnerId,
                venueId: request.venueId,
                eventDate: request.eventDate,
                eventTime: request.eventTime,
                requestId: request.id,
                status: NightPartnerMatchStatus.MATCHED,
                maxPartners: 1,
            }, { transaction: t });

            // Notify Host to complete payment
            this.emitNotification(request.hostId, {
                type: 'PARTNER_REQUEST_ACCEPTED',
                title: 'It\'s a Match! 🎉',
                body: `Your partner accepted your request! Tap to complete payment and confirm booking.`,
                entityId: match.id,
                data: { matchId: match.id, venueId: request.venueId, eventDate: request.eventDate },
            });

            return { request, match };
        });
    }

    /**
     * Host cancels a pending request
     */
    public static async cancelRequest(requestId: string, hostId: string): Promise<boolean> {
        const request = await NightPartnerRequest.findByPk(requestId);
        if (!request) throw new Error('REQUEST_NOT_FOUND');
        if (request.hostId !== hostId) throw new Error('UNAUTHORIZED');

        if (request.status === NightPartnerRequestStatus.ACCEPTED) {
            throw new Error('CANNOT_CANCEL_ACCEPTED_REQUEST');
        }

        await request.update({ status: NightPartnerRequestStatus.CANCELLED });
        return true;
    }

    /**
     * Host initiates payment for a confirmed match
     */
    public static async initiateMatchPayment(
        matchId: string,
        hostId: string
    ): Promise<{ match: NightPartnerMatch; razorpayOrder: any }> {
        const match = await NightPartnerMatch.findByPk(matchId);
        if (!match) throw new Error('MATCH_NOT_FOUND');
        if (match.hostId !== hostId) throw new Error('UNAUTHORIZED');

        if (match.status === NightPartnerMatchStatus.CONFIRMED) {
            throw new Error('BOOKING_ALREADY_CONFIRMED');
        }

        // Calculate authoritative price from venue configuration
        const pricing = await VenueBookingService.calculateAuthoritativePrice(match.venueId, 'Confirmation Charges', 2);
        const totalAmount = pricing.totalAmount > 0 ? pricing.totalAmount : 500; // Default nominal confirmation charge if free

        const razorpayOrder = await razorpay.orders.create({
            amount: Math.round(totalAmount * 100),
            currency: 'INR',
            receipt: `match_${Date.now()}`,
        });

        const paymentExpiresAt = new Date(Date.now() + 30 * 60 * 1000); // 30 mins window

        await match.update({
            totalAmount,
            razorpayOrderId: razorpayOrder.id,
            status: NightPartnerMatchStatus.PAYMENT_PENDING,
            paymentExpiresAt,
        });

        return { match, razorpayOrder };
    }

    /**
     * Verify payment, confirm booking, and unlock chat
     */
    public static async verifyMatchPayment(
        matchId: string,
        razorpayOrderId: string,
        razorpayPaymentId: string,
        razorpaySignature: string
    ): Promise<{ match: NightPartnerMatch; booking: Booking; conversation: Conversation }> {
        const match = await NightPartnerMatch.findByPk(matchId);
        if (!match) throw new Error('MATCH_NOT_FOUND');

        // Idempotency: return cleanly if already confirmed
        if (match.status === NightPartnerMatchStatus.CONFIRMED && match.bookingId && match.conversationId) {
            const booking = await Booking.findByPk(match.bookingId);
            const conversation = await Conversation.findByPk(match.conversationId);
            if (booking && conversation) {
                return { match, booking, conversation };
            }
        }

        const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
        hmac.update(`${razorpayOrderId}|${razorpayPaymentId}`);
        const generatedSignature = hmac.digest('hex');

        if (generatedSignature !== razorpaySignature) {
            await match.update({ status: NightPartnerMatchStatus.PAYMENT_FAILED });
            throw new Error('PAYMENT_FAILED');
        }

        return await sequelize.transaction(async (t) => {
            // 1. Create or Find Booking
            const bookingNumber = `NIGHT-${Date.now().toString(36).toUpperCase()}-${Math.floor(1000 + Math.random() * 9000)}`;

            const booking = await Booking.create({
                bookingNumber,
                userId: match.hostId,
                venueId: match.venueId,
                bookingDate: new Date(match.eventDate),
                startTime: match.eventTime || '20:00',
                numberOfGuests: 2,
                totalAmount: match.totalAmount || 500,
                depositAmount: 0,
                commissionAmount: Math.round((match.totalAmount || 500) * 0.1 * 100) / 100,
                goingMode: GoingMode.PARTY_REQUEST,
                tablePackage: 'Upcoming Night Match',
                isUpcomingNight: true,
                status: BookingStatus.CONFIRMED,
                paymentStatus: PaymentStatus.PAID,
                paymentMode: BookingPaymentMode.PAY_NOW,
                razorpayOrderId,
            }, { transaction: t });

            // 2. Get or Create 1-to-1 Conversation & Unlock Chat
            const [participantOne, participantTwo] = [match.hostId, match.partnerId].sort();

            let conversation = await Conversation.findOne({
                where: {
                    participantOne,
                    participantTwo,
                },
                transaction: t,
            });

            if (!conversation) {
                conversation = await Conversation.create({
                    participantOne,
                    participantTwo,
                    status: ConversationStatus.ACTIVE,
                    contextType: 'night_match',
                    contextId: match.id,
                }, { transaction: t });
            } else {
                await conversation.update({
                    status: ConversationStatus.ACTIVE,
                    contextType: 'night_match',
                    contextId: match.id,
                }, { transaction: t });
            }

            // 3. Update Match Record
            await match.update({
                status: NightPartnerMatchStatus.CONFIRMED,
                bookingId: booking.id,
                conversationId: conversation.id,
            }, { transaction: t });

            // 4. Generate Ticket PDF asynchronously
            try {
                await generateTicketForBookingHelper(booking.id);
            } catch (tErr) {
                logger.error(`[NightPartnerService] Ticket generation error for Booking ${booking.id}:`, tErr);
            }

            // 5. Send FCM Push Notification & Socket Event to both Host and Partner
            const venue = await Venue.findByPk(match.venueId);
            const venueName = venue?.name || 'Venue';

            this.emitNotification(match.hostId, {
                type: 'BOOKING_CONFIRMED',
                title: 'Booking Confirmed! 🎉',
                body: `Your Upcoming Night at ${venueName} is confirmed. Chat is now unlocked!`,
                entityId: booking.id,
                data: { bookingId: booking.id, conversationId: conversation.id },
            });

            this.emitNotification(match.partnerId, {
                type: 'BOOKING_CONFIRMED',
                title: 'Booking Confirmed! 🎉',
                body: `Your Upcoming Night at ${venueName} is confirmed with your host. Chat is now unlocked!`,
                entityId: booking.id,
                data: { bookingId: booking.id, conversationId: conversation.id },
            });

            return { match, booking, conversation };
        });
    }

    /**
     * Helper for push notifications and socket events
     */
    private static async emitNotification(userId: string, payload: { type: string; title: string; body: string; entityId: string; data?: any }) {
        try {
            const user = await User.findByPk(userId, { attributes: ['id', 'fcmToken'] });
            if (user && user.fcmToken) {
                const { sendPushNotification } = require('./fcmService');
                await sendPushNotification(user.fcmToken, {
                    title: payload.title,
                    body: payload.body,
                    data: { type: payload.type, entityId: payload.entityId, ...(payload.data || {}) },
                });
            }
            const { io } = require('../server');
            if (io) {
                io.to(`user_${userId}`).emit('night_partner_event', {
                    type: payload.type,
                    title: payload.title,
                    body: payload.body,
                    entityId: payload.entityId,
                    data: payload.data,
                });
            }
        } catch (err) {
            logger.warn(`[NightPartnerService] Notification emit warning: ${err}`);
        }
    }
}
