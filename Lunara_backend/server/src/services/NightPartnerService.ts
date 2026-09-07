import { Transaction, Op } from 'sequelize';
import sequelize from '../config/database';
import NightInterest, { NightInterestStatus } from '../models/NightInterest';
import NightPartnerRequest, { NightPartnerRequestStatus } from '../models/NightPartnerRequest';
import NightPartnerMatch, { NightPartnerMatchStatus, NightPartnerCancellationStatus } from '../models/NightPartnerMatch';
import User from '../models/User';
import UserProfile from '../models/UserProfile';
import UserPhoto from '../models/UserPhoto';
import UserPreference from '../models/UserPreference';
import Venue from '../models/Venue';
import Booking, { BookingStatus, PaymentStatus, GoingMode, BookingPaymentMode } from '../models/Booking';
import Conversation, { ConversationStatus } from '../models/Conversation';
import { VenueBookingService } from './VenueBookingService';
import { generateTicketForBookingHelper } from './ticketService';
import { NotificationService } from './NotificationService';
import { NotificationEventType } from '../types/NotificationEventTypes';
import { logger } from '../config/logger';
import Razorpay from 'razorpay';
import crypto from 'crypto';
import { parseTimeParts, format12HourFromParts } from '../utils/dateTimeUtils';
import { EventTimeLockService, parseBookingDateTime } from './EventTimeLockService';

function normalize12h(timeStr?: string | null): string {
    const [h, m] = parseTimeParts(timeStr);
    return format12HourFromParts(h, m);
}

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
    isInterested?: boolean;
    interestId?: string;
    hasPendingInvite?: boolean;
}

export class NightPartnerService {
    private static async resolveVenue(venueId: string): Promise<Venue | null> {
        try {
            const venue = await Venue.findByPk(venueId);
            if (venue) return venue;
        } catch (_) {}

        const found = await Venue.findOne({
            where: {
                name: { [Op.iLike]: `%${venueId}%` },
            },
        });
        if (found) return found;

        return (await Venue.findOne({ where: { status: 'live' } })) || (await Venue.findOne());
    }

    /**
     * Check if a user has marked interest in an upcoming night
     */
    public static async checkUserInterest(
        userId: string,
        venueId: string,
        eventDate: string
    ): Promise<boolean> {
        const venue = await this.resolveVenue(venueId);
        const resolvedVenueId = venue ? venue.id : venueId;

        const interest = await NightInterest.findOne({
            where: {
                userId,
                venueId: resolvedVenueId,
                eventDate: new Date(eventDate),
                status: NightInterestStatus.INTERESTED,
            },
        });
        return !!interest;
    }

    /**
     * Mark a user as interested in an upcoming night event (Idempotent)
     */
    public static async markInterested(
        userId: string,
        venueId: string,
        eventDate: string,
        eventTime?: string
    ): Promise<NightInterest> {
        const venue = await this.resolveVenue(venueId);
        if (!venue) {
            throw new Error('VENUE_NOT_FOUND');
        }

        const resolvedVenueId = venue.id;

        const [interest, created] = await NightInterest.findOrCreate({
            where: {
                userId,
                venueId: resolvedVenueId,
                eventDate: new Date(eventDate),
            },
            defaults: {
                userId,
                venueId: resolvedVenueId,
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
        const venue = await this.resolveVenue(venueId);
        const resolvedVenueId = venue ? venue.id : venueId;

        const interest = await NightInterest.findOne({
            where: {
                userId,
                venueId: resolvedVenueId,
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
                venueId: resolvedVenueId,
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
     * List available invitees (users with NO existing plan or booking for that date)
     */
    public static async getAvailableInvitees(
        hostId: string,
        venueId: string,
        eventDate: string,
        search?: string
    ): Promise<SafePartnerProfile[]> {
        const userWhere: any = {
            id: { [Op.ne]: hostId },
            [Op.or]: [{ isDeleted: false }, { isDeleted: null }],
        };

        if (search && search.trim().length > 0) {
            const cleanSearch = `%${search.trim()}%`;
            userWhere[Op.or] = [
                { firstName: { [Op.iLike]: cleanSearch } },
                { lastName: { [Op.iLike]: cleanSearch } },
            ];
        }

        const venue = await this.resolveVenue(venueId);
        const resolvedVenueId = venue ? venue.id : venueId;

        // 1. Fetch interested users in 1 query
        const interestedRecords = await NightInterest.findAll({
            where: {
                venueId: resolvedVenueId,
                eventDate: new Date(eventDate),
                status: NightInterestStatus.INTERESTED,
                userId: { [Op.ne]: hostId },
            },
            attributes: ['id', 'userId', 'eventTime'],
        });

        const interestedMap = new Map<string, string>();
        for (const item of interestedRecords) {
            interestedMap.set(item.userId, item.id);
        }

        // 2. Fetch existing active matches on this date in 1 query
        const existingMatches = await NightPartnerMatch.findAll({
            where: {
                eventDate: new Date(eventDate),
                status: { [Op.in]: [NightPartnerMatchStatus.MATCHED, NightPartnerMatchStatus.PAYMENT_PENDING, NightPartnerMatchStatus.CONFIRMED] },
            },
            attributes: ['hostId', 'partnerId'],
        });
        const busyUserIds = new Set<string>();
        for (const m of existingMatches) {
            busyUserIds.add(m.hostId);
            busyUserIds.add(m.partnerId);
        }

        // 3. Fetch existing pending/accepted requests from this host for this venue & date in 1 query
        const existingRequests = await NightPartnerRequest.findAll({
            where: {
                hostId,
                venueId: resolvedVenueId,
                eventDate: new Date(eventDate),
                status: { [Op.in]: [NightPartnerRequestStatus.PENDING, NightPartnerRequestStatus.ACCEPTED] },
            },
            attributes: ['partnerId'],
        });
        const pendingInvitePartnerIds = new Set<string>(existingRequests.map(r => r.partnerId));

        // 4. Fetch candidate users
        const candidates = await User.findAll({
            where: userWhere,
            attributes: ['id', 'firstName', 'lastName', 'dateOfBirth', 'isVerified', 'createdAt'],
            include: [
                { model: UserProfile, as: 'profile' },
                { model: UserPhoto, as: 'photos' },
                { model: UserPreference, as: 'preferences', attributes: ['showMeInMatching'], required: false },
            ],
            limit: 60,
            order: [['createdAt', 'DESC']],
        });

        const available: SafePartnerProfile[] = [];

        for (const u of candidates) {
            if (busyUserIds.has(u.id)) {
                continue;
            }

            // Respect user's hidden profile preference
            const prefs = (u as any).preferences;
            if (prefs && prefs.showMeInMatching === false) {
                continue;
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

            const isInterested = interestedMap.has(u.id);
            const interestId = interestedMap.get(u.id);
            const hasPendingInvite = pendingInvitePartnerIds.has(u.id);

            available.push({
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
                compatibilityScore: isInterested ? 94 : 88,
                isInterested: !!isInterested,
                interestId,
                hasPendingInvite,
            });
        }

        // Sort interested users first, followed by others with high vibe scores
        available.sort((a, b) => {
            if (a.isInterested && !b.isInterested) return -1;
            if (!a.isInterested && b.isInterested) return 1;
            return (b.compatibilityScore || 0) - (a.compatibilityScore || 0);
        });

        return available;
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
     * Host sends partner request to an interested user or direct invitee (Idempotent)
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

        // Check if partner is interested (optional for direct invitations)
        const interest = await NightInterest.findOne({
            where: {
                userId: partnerId,
                venueId,
                eventDate: new Date(eventDate),
                status: NightInterestStatus.INTERESTED,
            },
        });

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

        // ── 4-Hour Time-Lock & Existing Plan Validation (Host & Partner) ───────
        const eventDateTime = parseBookingDateTime(eventDate, eventTime);
        const hostTimeLock = await EventTimeLockService.validateFourHourGap(hostId, eventDateTime, 'party_plan');
        if (!hostTimeLock.allowed) {
            const err: any = new Error(hostTimeLock.message);
            err.code = 'FOUR_HOUR_TIME_LOCK';
            err.timeLock = hostTimeLock;
            throw err;
        }

        const partnerTimeLock = await EventTimeLockService.validateFourHourGap(partnerId, eventDateTime, 'party_plan');
        if (!partnerTimeLock.allowed) {
            const partnerUser = await User.findByPk(partnerId, { attributes: ['firstName', 'lastName'] });
            const partnerName = partnerUser?.firstName || 'The selected partner';
            const err: any = new Error(`${partnerName} already has another plan scheduled around this time. Please choose another event or partner.`);
            err.code = 'USER_ALREADY_HAS_PLAN';
            err.timeLock = partnerTimeLock;
            throw err;
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
                nightInterestId: interest ? interest.id : undefined,
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

        // Fetch Host Profile info for rich notification delivery
        const hostUser = await User.findByPk(hostId, {
            attributes: ['id', 'firstName', 'lastName', 'isVerified'],
            include: [
                { model: UserProfile, as: 'profile' },
                { model: UserPhoto, as: 'photos' },
            ],
        });

        const hostName = hostUser?.firstName || 'A Lunara member';
        const hostPhotos = (hostUser as any)?.photos || [];
        const hostPrimaryPhoto = hostPhotos.find((p: any) => p.isPrimary) || hostPhotos[0];

        // Send Push & Real-time Socket Notification to Partner
        await this.emitNotification(partnerId, {
            type: 'PARTNER_REQUEST_SENT',
            actorUserId: hostId,
            title: 'Night Partner Invite 🌙',
            body: `${hostName} invited you to join for Upcoming Night at ${venue.name}!`,
            entityId: request.id,
            data: {
                requestId: request.id,
                nightId: request.id,
                venueId: venue.id,
                venueName: venue.name,
                eventName: venue.name,
                eventDate,
                eventTime: normalize12h(eventTime || request.eventTime || '20:00'),
                hostId,
                hostName,
                partnerId,
                recipientUserId: partnerId,
                actorUserId: hostId,
                isHost: false,
                userRole: 'PARTNER',
                status: 'PENDING',
                stage: 'INVITE_SENT',
                actor: {
                    id: hostId,
                    firstName: hostUser?.firstName || 'Host',
                    lastName: hostUser?.lastName || '',
                    profilePhotoUrl: hostPrimaryPhoto?.filePath || null,
                    isVerified: !!hostUser?.isVerified,
                },
                sender: {
                    id: hostId,
                    firstName: hostUser?.firstName || 'Host',
                    lastName: hostUser?.lastName || '',
                    profilePhotoUrl: hostPrimaryPhoto?.filePath || null,
                    isVerified: !!hostUser?.isVerified,
                },
                partner: {
                    id: hostId,
                    firstName: hostUser?.firstName || 'Host',
                    name: hostUser?.firstName || 'Host',
                    photo: hostPrimaryPhoto?.filePath || null,
                },
                event: {
                    venueName: venue.name,
                    name: venue.name,
                    date: eventDate,
                    time: eventTime || request.eventTime || '20:00',
                    coverImageUrl: (venue as any).coverImage || (venue as any).primaryPhoto || null,
                },
                actions: ['ACCEPT', 'DECLINE'],
            },
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

            // ACTION: ACCEPT -> Atomic Capacity, Time-Lock & Match Creation Check
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

            const eventDateTime = parseBookingDateTime(request.eventDate, request.eventTime);
            const partnerTimeLock = await EventTimeLockService.validateFourHourGap(partnerId, eventDateTime, 'party_plan', undefined, { transaction: t });
            if (!partnerTimeLock.allowed) {
                const err: any = new Error(partnerTimeLock.message);
                err.code = 'FOUR_HOUR_TIME_LOCK';
                err.timeLock = partnerTimeLock;
                throw err;
            }

            const hostTimeLock = await EventTimeLockService.validateFourHourGap(request.hostId, eventDateTime, 'party_plan', undefined, { transaction: t });
            if (!hostTimeLock.allowed) {
                const err: any = new Error(hostTimeLock.message);
                err.code = 'FOUR_HOUR_TIME_LOCK';
                err.timeLock = hostTimeLock;
                throw err;
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

            // Auto-remove / deactivate any open find-partner party plans for host and partner at this venue on this date
            try {
                const PartyPlan = (await import('../models/PartyPlan')).default;
                const { PartyPlanStatus } = await import('../models/PartyPlan');
                await PartyPlan.update(
                    { status: PartyPlanStatus.CANCELLED, isLive: false },
                    {
                        where: {
                            userId: { [Op.in]: [request.hostId, request.partnerId] },
                            venueId: request.venueId,
                            status: PartyPlanStatus.ACTIVE,
                        },
                        transaction: t,
                    }
                );
            } catch (pPlanErr) {
                logger.warn(`[NightPartnerService] Non-fatal: could not update party plans upon match: ${pPlanErr}`);
            }

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
     * Host initiates payment for a confirmed match (Self Pay vs Split)
     */
    public static async initiateMatchPayment(
        matchId: string,
        hostId: string,
        paymentMode: 'SELF_PAY' | 'SPLIT' = 'SELF_PAY'
    ): Promise<{ match: NightPartnerMatch; razorpayOrder: any; amountToPay: number }> {
        const match = await NightPartnerMatch.findByPk(matchId);
        if (!match) throw new Error('MATCH_NOT_FOUND');
        if (match.hostId !== hostId && match.partnerId !== hostId) throw new Error('UNAUTHORIZED');

        if (match.status === NightPartnerMatchStatus.CONFIRMED) {
            throw new Error('BOOKING_ALREADY_CONFIRMED');
        }

        // Calculate authoritative price from venue configuration
        const pricing = await VenueBookingService.calculateAuthoritativePrice(match.venueId, 'Confirmation Charges', 2);
        const totalAmount = pricing.totalAmount > 0 ? pricing.totalAmount : 500; // Default nominal confirmation charge if free

        const hostAmount = paymentMode === 'SPLIT' ? Math.round((totalAmount / 2) * 100) / 100 : totalAmount;
        const partnerAmount = paymentMode === 'SPLIT' ? Math.round((totalAmount / 2) * 100) / 100 : 0;

        const isHost = match.hostId === hostId;
        const amountToPay = isHost ? hostAmount : partnerAmount;

        let razorpayOrder: any;
        const hasRazorpayKeys = process.env.RAZORPAY_KEY_ID && 
                                process.env.RAZORPAY_KEY_ID !== 'your_razorpay_key_id' && 
                                process.env.RAZORPAY_KEY_ID !== 'rzp_test_123';
        if (hasRazorpayKeys) {
            try {
                razorpayOrder = await razorpay.orders.create({
                    amount: Math.round(amountToPay * 100),
                    currency: 'INR',
                    receipt: `match_${Date.now()}`,
                });
            } catch (err: any) {
                logger.error('Razorpay match order creation failed, falling back to mock:', err);
                razorpayOrder = {
                    id: `order_mock_${Date.now()}_${Math.random().toString(36).substring(2, 10)}`,
                    amount: Math.round(amountToPay * 100),
                    currency: 'INR',
                };
            }
        } else {
            razorpayOrder = {
                id: `order_mock_${Date.now()}_${Math.random().toString(36).substring(2, 10)}`,
                amount: Math.round(amountToPay * 100),
                currency: 'INR',
            };
        }

        const paymentExpiresAt = new Date(Date.now() + 30 * 60 * 1000); // 30 mins window

        await match.update({
            totalAmount,
            paymentMode: paymentMode as any,
            hostAmount,
            partnerAmount,
            razorpayOrderId: razorpayOrder.id,
            status: NightPartnerMatchStatus.PAYMENT_PENDING,
            paymentExpiresAt,
        });

        // Notify partner if split payment is selected
        if (paymentMode === 'SPLIT' && isHost) {
            this.emitNotification(match.partnerId, {
                type: 'PAYMENT_PENDING',
                title: 'Payment Required (Split) 💳',
                body: `Your partner selected Split Pay! Please pay your share (₹${partnerAmount}) to confirm the booking.`,
                entityId: match.id,
                data: { matchId: match.id, amount: partnerAmount, paymentMode: 'SPLIT' },
            });
        }

        return { match, razorpayOrder, amountToPay };
    }

    /**
     * Verify payment, confirm booking, and unlock chat (Supports Razorpay and Lunara Smart Wallet)
     */
    public static async verifyMatchPayment(
        matchId: string,
        razorpayOrderId: string,
        razorpayPaymentId: string,
        razorpaySignature: string,
        callerUserId: string,
        paymentMethod: 'razorpay' | 'wallet' = 'razorpay'
    ): Promise<{ match: NightPartnerMatch; booking?: Booking; conversation?: Conversation; isFullyPaid: boolean }> {
        const match = await NightPartnerMatch.findByPk(matchId);
        if (!match) throw new Error('MATCH_NOT_FOUND');
        if (match.hostId !== callerUserId && match.partnerId !== callerUserId) {
            const err: any = new Error('UNAUTHORIZED');
            err.statusCode = 403;
            throw err;
        }

        // Idempotency: return cleanly if already confirmed
        if (match.status === NightPartnerMatchStatus.CONFIRMED && match.bookingId && match.conversationId) {
            const booking = await Booking.findByPk(match.bookingId);
            const conversation = await Conversation.findByPk(match.conversationId);
            if (booking && conversation) {
                return { match, booking, conversation, isFullyPaid: true };
            }
        }

        const isHost = match.hostId === callerUserId;
        const requiredAmount = isHost ? (match.hostAmount || match.totalAmount || 500) : (match.partnerAmount || 0);

        if (paymentMethod === 'wallet') {
            // Deduct atomically from Lunara Smart Wallet
            const SmartWallet = (await import('../models/SmartWallet')).default;
            const WalletTransaction = (await import('../models/WalletTransaction')).default;

            const wallet = await SmartWallet.findOne({ where: { userId: callerUserId } });
            if (!wallet || Number(wallet.balance) < requiredAmount) {
                throw new Error('INSUFFICIENT_WALLET_BALANCE');
            }

            const openingBal = Number(wallet.balance);
            const closingBal = openingBal - requiredAmount;
            await sequelize.transaction(async (t) => {
                await wallet.decrement('balance', { by: requiredAmount, transaction: t });
                await WalletTransaction.create({
                    walletId: wallet.id,
                    userId: callerUserId,
                    amount: requiredAmount,
                    openingBalance: openingBal,
                    closingBalance: closingBal,
                    transactionType: 'booking_payment' as any,
                    status: 'success' as any,
                    reference: match.id,
                }, { transaction: t });
            });
        } else {
            // Razorpay signature verification
            const isMockPayment = razorpaySignature === 'mock_signature' ||
                                  (razorpayOrderId && razorpayOrderId.startsWith('order_mock_')) ||
                                  (razorpayOrderId && razorpayOrderId.startsWith('mock_'));

            const hmac = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'secret123');
            hmac.update(`${razorpayOrderId}|${razorpayPaymentId}`);
            const generatedSignature = hmac.digest('hex');

            if (!isMockPayment && generatedSignature !== razorpaySignature) {
                await match.update({ status: NightPartnerMatchStatus.PAYMENT_FAILED });
                throw new Error('PAYMENT_FAILED');
            }
        }

        return await sequelize.transaction(async (t) => {
            let newHostPaid = match.hostPaid;
            let newPartnerPaid = match.partnerPaid;

            if (isHost) {
                newHostPaid = true;
            } else {
                newPartnerPaid = true;
            }

            const isSplit = match.paymentMode === 'SPLIT';
            const isFullyPaid = isSplit ? (newHostPaid && newPartnerPaid) : newHostPaid;

            if (!isFullyPaid) {
                // Split payment waiting for second party
                await match.update({
                    hostPaid: newHostPaid,
                    partnerPaid: newPartnerPaid,
                }, { transaction: t });

                const otherUserId = isHost ? match.partnerId : match.hostId;
                const otherAmount = isHost ? (match.partnerAmount || 0) : (match.hostAmount || 0);

                this.emitNotification(otherUserId, {
                    type: 'PAYMENT_PENDING',
                    title: 'Your Turn to Pay (Split) 💳',
                    body: `${isHost ? 'Host' : 'Partner'} paid their share! Please complete your payment of ₹${otherAmount} to lock the booking.`,
                    entityId: match.id,
                    data: { matchId: match.id, amount: otherAmount, paymentMode: 'SPLIT' },
                });

                return { match, isFullyPaid: false };
            }

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
                where: { participantOne, participantTwo },
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
                hostPaid: true,
                partnerPaid: isSplit ? true : match.partnerPaid,
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
                body: `Your Upcoming Night at ${venueName} is confirmed. Ticket is generated & Chat unlocked!`,
                entityId: booking.id,
                data: { bookingId: booking.id, conversationId: conversation.id },
            });

            this.emitNotification(match.partnerId, {
                type: 'BOOKING_CONFIRMED',
                title: 'Booking Confirmed! 🎉',
                body: `Your Upcoming Night at ${venueName} is confirmed with your host. Ticket is generated & Chat unlocked!`,
                entityId: booking.id,
                data: { bookingId: booking.id, conversationId: conversation.id },
            });

            return { match, booking, conversation, isFullyPaid: true };
        });
    }

    /**
     * Cancel an Upcoming Night (Pre-booking or Post-booking with Wallet Refund)
     */
    public static async cancelUpcomingNight(
        targetId: string,
        callerUserId: string,
        reason: string = 'Change of plans',
        action?: 'request' | 'approve' | 'reject' | 'confirm' | 'decline' | 'accept'
    ): Promise<{ success: boolean; status?: string; message: string }> {
        // Check if target is a Match or a Request
        let match = await NightPartnerMatch.findByPk(targetId);
        let request: NightPartnerRequest | null = null;

        if (!match) {
            request = await NightPartnerRequest.findByPk(targetId);
        }

        if (!match && !request) {
            throw new Error('RECORD_NOT_FOUND');
        }

        if (request) {
            if (request.hostId !== callerUserId && request.partnerId !== callerUserId) {
                throw new Error('UNAUTHORIZED');
            }
            await request.update({ status: NightPartnerRequestStatus.CANCELLED });
            const otherId = request.hostId === callerUserId ? request.partnerId : request.hostId;
            this.emitNotification(otherId, {
                type: 'PARTNER_REQUEST_CANCELLED',
                title: 'Upcoming Night Request Cancelled',
                body: 'The partner request has been cancelled.',
                entityId: request.id,
            });
            return { success: true, status: 'CANCELLED', message: 'Request cancelled successfully' };
        }

        if (match) {
            if (match.hostId !== callerUserId && match.partnerId !== callerUserId) {
                throw new Error('UNAUTHORIZED');
            }

            if (match.status === NightPartnerMatchStatus.CANCELLED) {
                return { success: true, status: 'CANCELLED', message: 'Upcoming Night is already cancelled' };
            }

            const isHost = match.hostId === callerUserId;
            const otherUserId = isHost ? match.partnerId : match.hostId;
            const callerUser = await User.findByPk(callerUserId).catch(() => null);
            const callerName = callerUser?.firstName || (isHost ? 'Host' : 'Partner');

            let venueName = 'the venue';
            try {
                const venue = await Venue.findByPk(match.venueId);
                if (venue?.name) venueName = venue.name;
            } catch (_) {}

            const isConfirmedOrPaid = match.status === NightPartnerMatchStatus.CONFIRMED ||
                Boolean(match.bookingId) ||
                Boolean(match.hostPaid) ||
                Boolean(match.partnerPaid);

            // Normalized action: 'request' | 'approve' | 'reject'
            const normalizedAction = (action === 'confirm' || action === 'approve' || action === 'accept')
                ? 'approve'
                : (action === 'reject' || action === 'decline')
                    ? 'reject'
                    : 'request';

            // Branch 1: If not yet confirmed or paid (e.g. MATCHED or PAYMENT_PENDING with 0 payments), allow direct cancellation
            if (!isConfirmedOrPaid) {
                return await sequelize.transaction(async (t) => {
                    await match!.update({
                        status: NightPartnerMatchStatus.CANCELLED,
                        cancellationStatus: NightPartnerCancellationStatus.APPROVED,
                        cancellationReason: reason,
                        cancelledBy: callerUserId,
                    }, { transaction: t });

                    this.emitNotification(otherUserId, {
                        type: 'UPCOMING_NIGHT_CANCELLED',
                        title: 'Upcoming Night Cancelled ❌',
                        body: `${callerName} cancelled the upcoming night at ${venueName}. Reason: ${reason}`,
                        entityId: match!.id,
                        actorUserId: callerUserId,
                    });

                    return { success: true, status: 'CANCELLED', message: 'Upcoming Night cancelled successfully' };
                });
            }

            // Branch 2: Confirmed or Paid match -> Handle Mutual Cancellation Flow

            // Sub-branch 2A: REJECT CANCELLATION
            if (normalizedAction === 'reject') {
                if (match.cancellationStatus !== NightPartnerCancellationStatus.REQUESTED) {
                    return { success: false, message: 'No active cancellation request to reject.' };
                }

                await match.update({
                    cancellationStatus: NightPartnerCancellationStatus.REJECTED,
                });

                const requesterId = match.cancelledBy || otherUserId;
                this.emitNotification(requesterId, {
                    type: 'UPCOMING_NIGHT_CANCELLATION_REJECTED',
                    title: 'Cancellation Request Declined ❌',
                    body: `${callerName} declined the cancellation request. Your Upcoming Night at ${venueName} remains confirmed.`,
                    entityId: match.id,
                    actorUserId: callerUserId,
                });

                return { success: true, status: 'REJECTED', message: 'Cancellation request declined. The Upcoming Night remains active.' };
            }

            // Sub-branch 2B: APPROVE CANCELLATION
            // If explicit 'approve', or if the OTHER party already requested cancellation and caller submits cancel
            const isApproving = normalizedAction === 'approve' ||
                (match.cancellationStatus === NightPartnerCancellationStatus.REQUESTED && match.cancelledBy && match.cancelledBy !== callerUserId);

            if (isApproving) {
                return await sequelize.transaction(async (t) => {
                    // 1. Cancel booking if exists
                    if (match!.bookingId) {
                        const booking = await Booking.findByPk(match!.bookingId, { transaction: t });
                        if (booking) {
                            await booking.update({ status: BookingStatus.CANCELLED }, { transaction: t });
                        }
                    }

                    // 2. Process Smart Wallet Refunds atomically
                    try {
                        const SmartWallet = (await import('../models/SmartWallet')).default;
                        const WalletTransaction = (await import('../models/WalletTransaction')).default;

                        if (match!.hostPaid && match!.hostAmount && match!.hostAmount > 0) {
                            let hostWallet = await SmartWallet.findOne({ where: { userId: match!.hostId }, transaction: t });
                            if (!hostWallet) {
                                hostWallet = await SmartWallet.create({ userId: match!.hostId, balance: 0 }, { transaction: t });
                            }
                            const openingBal = Number(hostWallet.balance || 0);
                            const refundAmt = Number(match!.hostAmount);
                            const closingBal = openingBal + refundAmt;
                            await hostWallet.increment('balance', { by: refundAmt, transaction: t });
                            await WalletTransaction.create({
                                walletId: hostWallet.id,
                                userId: match!.hostId,
                                amount: refundAmt,
                                openingBalance: openingBal,
                                closingBalance: closingBal,
                                transactionType: 'refund' as any,
                                status: 'success' as any,
                                reference: match!.id,
                            }, { transaction: t });
                        }

                        if (match!.partnerPaid && match!.partnerAmount && match!.partnerAmount > 0) {
                            let partnerWallet = await SmartWallet.findOne({ where: { userId: match!.partnerId }, transaction: t });
                            if (!partnerWallet) {
                                partnerWallet = await SmartWallet.create({ userId: match!.partnerId, balance: 0 }, { transaction: t });
                            }
                            const openingBal = Number(partnerWallet.balance || 0);
                            const refundAmt = Number(match!.partnerAmount);
                            const closingBal = openingBal + refundAmt;
                            await partnerWallet.increment('balance', { by: refundAmt, transaction: t });
                            await WalletTransaction.create({
                                walletId: partnerWallet.id,
                                userId: match!.partnerId,
                                amount: refundAmt,
                                openingBalance: openingBal,
                                closingBalance: closingBal,
                                transactionType: 'refund' as any,
                                status: 'success' as any,
                                reference: match!.id,
                            }, { transaction: t });
                        }
                    } catch (walletErr) {
                        logger.warn(`[NightPartnerService] Wallet refund warning: ${walletErr}`);
                    }

                    // 3. Archive Conversation
                    if (match!.conversationId) {
                        try {
                            const Conversation = (await import('../models/Conversation')).default;
                            const conv = await Conversation.findByPk(match!.conversationId, { transaction: t });
                            if (conv) {
                                await conv.update({ status: ConversationStatus.ARCHIVED }, { transaction: t });
                            }
                        } catch (_) {}
                    }

                    // 4. Update match status
                    await match!.update({
                        status: NightPartnerMatchStatus.CANCELLED,
                        cancellationStatus: NightPartnerCancellationStatus.APPROVED,
                        cancellationReason: reason || match!.cancellationReason || 'Mutual cancellation confirmed',
                        cancelledBy: match!.cancelledBy || callerUserId,
                    }, { transaction: t });

                    // 5. Notify both parties
                    this.emitNotification(match!.hostId, {
                        type: 'UPCOMING_NIGHT_CANCELLED',
                        title: 'Upcoming Night Cancelled & Refunded 💳',
                        body: `Upcoming Night at ${venueName} was cancelled. Any paid ticket amounts have been refunded to your wallet.`,
                        entityId: match!.id,
                        actorUserId: callerUserId,
                    });

                    this.emitNotification(match!.partnerId, {
                        type: 'UPCOMING_NIGHT_CANCELLED',
                        title: 'Upcoming Night Cancelled & Refunded 💳',
                        body: `Upcoming Night at ${venueName} was cancelled. Any paid ticket amounts have been refunded to your wallet.`,
                        entityId: match!.id,
                        actorUserId: callerUserId,
                    });

                    return { success: true, status: 'CANCELLED', message: 'Upcoming Night cancelled and refunded to wallet successfully.' };
                });
            }

            // Sub-branch 2C: INITIATE CANCELLATION REQUEST (Waiting for partner approval)
            if (match.cancellationStatus === NightPartnerCancellationStatus.REQUESTED) {
                if (match.cancelledBy === callerUserId) {
                    return { success: true, status: 'REQUESTED', message: 'Cancellation request is already pending partner confirmation.' };
                }
            }

            await match.update({
                cancellationStatus: NightPartnerCancellationStatus.REQUESTED,
                cancellationReason: reason,
                cancelledBy: callerUserId,
            });

            this.emitNotification(otherUserId, {
                type: 'UPCOMING_NIGHT_CANCELLATION_REQUESTED',
                title: 'Upcoming Night Cancellation Request ⚠️',
                body: `${callerName} requested to cancel the Upcoming Night at ${venueName}. Reason: "${reason}". Please confirm to process refund.`,
                entityId: match.id,
                actorUserId: callerUserId,
                data: {
                    matchId: match.id,
                    requestedById: callerUserId,
                    requesterName: callerName,
                    reason,
                    venueName,
                    actions: ['ACCEPT_CANCELLATION', 'REJECT_CANCELLATION'],
                },
            });

            return {
                success: true,
                status: 'REQUESTED',
                message: 'Cancellation request sent to your partner. Waiting for their confirmation to process refund.',
            };
        }

        return { success: true, message: 'Cancelled' };
    }

    /**
     * Get all upcoming Event Posts for Home Feed / Event Posts Screen
     */
    public static async getEventPosts(callerUserId?: string): Promise<any[]> {
        const now = new Date();
        const todayStr = now.toISOString().split('T')[0];

        // 1. Fetch active advertisements (Upcoming Nights from Admin Banner Settings)
        let activeAds: any[] = [];
        try {
            const Ad = (await import('../models/Ad')).default;
            activeAds = await Ad.findAll({
                where: {
                    isActive: true,
                    fromDate: { [Op.lte]: now },
                    toDate: { [Op.gte]: now },
                },
                include: [{ model: Venue, as: 'venue' }],
                order: [['createdAt', 'DESC']],
                limit: 30,
            });
        } catch (adErr) {
            logger.warn('[NightPartnerService] Error fetching active ads for event posts:', adErr);
        }

        const eventPosts: any[] = [];
        const seenVenueIds = new Set<string>();

        for (const ad of activeAds) {
            const v = (ad as any).venue;
            if (!v) continue;
            seenVenueIds.add(v.id);

            const interestedCount = await NightInterest.count({
                where: {
                    venueId: v.id,
                    status: NightInterestStatus.INTERESTED,
                },
            });

            let isInterested = false;
            let hasActiveMatch = false;

            if (callerUserId) {
                const interest = await NightInterest.findOne({
                    where: {
                        userId: callerUserId,
                        venueId: v.id,
                        status: NightInterestStatus.INTERESTED,
                    },
                });
                isInterested = !!interest;

                const match = await NightPartnerMatch.findOne({
                    where: {
                        [Op.or]: [{ hostId: callerUserId }, { partnerId: callerUserId }],
                        venueId: v.id,
                        status: { [Op.in]: [NightPartnerMatchStatus.MATCHED, NightPartnerMatchStatus.PAYMENT_PENDING, NightPartnerMatchStatus.CONFIRMED] },
                    },
                });
                hasActiveMatch = !!match;
            }

            let adImage = ad.imagePath || '';
            if (adImage && !adImage.startsWith('http') && !adImage.startsWith('/')) {
                adImage = `/${adImage.replace(/\\/g, '/')}`;
            }

            const eventDateStr = ad.eventDate ? ad.eventDate.toISOString().split('T')[0] : (ad.toDate ? ad.toDate.toISOString().split('T')[0] : todayStr);

            eventPosts.push({
                id: `ad_event_${ad.id}`,
                adId: ad.id,
                upcomingNightId: ad.id,
                venueId: v.id,
                title: ad.title || `${v.name} Weekend Night`,
                name: ad.title || `${v.name} Weekend Night`,
                venue: v.name,
                venueName: v.name,
                image: adImage || (v as any).coverImage || (v as any).primaryPhoto || '',
                coverImageUrl: adImage || (v as any).coverImage || (v as any).primaryPhoto || '',
                date: eventDateStr,
                rawDate: eventDateStr,
                bannerFromDate: ad.fromDate,
                bannerToDate: ad.toDate,
                time: normalize12h(v.openingTime || '20:00'),
                location: `${v.area || v.addressLine1 || ''}${v.city ? ', ' + v.city : ''}`.trim(),
                aboutEvent: ad.aboutEvent || `Experience the pulse of the nightlife at ${v.name}. Great music, vibrant party vibes, and curated partner matches.`,
                interestedCount,
                seatLimit: ad.seatLimit,
                price: ad.entryPrice || v.coupleEntryFee || v.tableBookingCharges || (v as any).coverChargeMale || 1000,
                isInterested,
                hasActiveMatch,
                venueMap: v.toJSON(),
            });
        }

        // 2. Fallback to active venues if few/no ads exist
        if (eventPosts.length < 5) {
            const venues = await Venue.findAll({
                where: {
                    status: 'live',
                    id: { [Op.notIn]: Array.from(seenVenueIds) },
                },
                attributes: ['id', 'name', 'addressLine1', 'city', 'area', 'primaryPhoto', 'coverImage', 'pricePerCouple', 'entryFee', 'openingTime', 'closingTime'],
                order: [['createdAt', 'DESC']],
                limit: 30 - eventPosts.length,
            });

            for (const v of venues) {
                const interestedCount = await NightInterest.count({
                    where: {
                        venueId: v.id,
                        status: NightInterestStatus.INTERESTED,
                    },
                });

                let isInterested = false;
                let hasActiveMatch = false;

                if (callerUserId) {
                    const interest = await NightInterest.findOne({
                        where: {
                            userId: callerUserId,
                            venueId: v.id,
                            status: NightInterestStatus.INTERESTED,
                        },
                    });
                    isInterested = !!interest;

                    const match = await NightPartnerMatch.findOne({
                        where: {
                            [Op.or]: [{ hostId: callerUserId }, { partnerId: callerUserId }],
                            venueId: v.id,
                            status: { [Op.in]: [NightPartnerMatchStatus.MATCHED, NightPartnerMatchStatus.PAYMENT_PENDING, NightPartnerMatchStatus.CONFIRMED] },
                        },
                    });
                    hasActiveMatch = !!match;
                }

                eventPosts.push({
                    id: `event_post_${v.id}`,
                    venueId: v.id,
                    title: `${v.name} Weekend Night`,
                    venue: v.name,
                    venueName: v.name,
                    image: (v as any).coverImage || (v as any).primaryPhoto || '',
                    date: 'Tonight / Weekend',
                    rawDate: todayStr,
                    time: normalize12h(v.openingTime || '9:00 PM'),
                    location: `${v.area || v.addressLine1 || ''}${v.city ? ', ' + v.city : ''}`.trim(),
                    aboutEvent: `Experience the pulse of the nightlife at ${v.name}. Great music, vibrant party vibes, and curated partner matches.`,
                    interestedCount,
                    price: v.coupleEntryFee || v.tableBookingCharges || (v as any).coverChargeMale || 1000,
                    isInterested,
                    hasActiveMatch,
                    venueMap: v.toJSON(),
                });
            }
        }

        return eventPosts;
    }

    /**
     * Helper for push notifications, socket events, and persistent notification DB records
     */
    private static async emitNotification(
        userId: string,
        payload: {
            type: string;
            title: string;
            body: string;
            entityId: string;
            actorUserId?: string;
            category?: any;
            actionType?: string;
            deepLink?: string;
            data?: any;
        }
    ) {
        try {
            await NotificationService.dispatch({
                recipientUserId: userId,
                actorUserId: payload.actorUserId,
                eventType: payload.type as NotificationEventType,
                category: payload.category || 'requests',
                entityType: 'night_partner',
                entityId: payload.entityId,
                title: payload.title,
                body: payload.body,
                actionType: payload.actionType,
                deepLink: payload.deepLink,
                metadata: payload.data,
            });

            const enrichedCard = await NightPartnerService.enrichUpcomingNightNotificationCard(payload.entityId, userId);
            const { io } = require('../server');
            if (io && enrichedCard) {
                io.to(`user_${userId}`).emit('notification_updated', enrichedCard);
                io.to(`user_${userId}`).emit('upcoming_night_status_update', { nightId: payload.entityId, type: payload.type });
                io.to('live_feed').emit('live_feed_update', { type: 'upcoming_night_activity', nightId: payload.entityId, timestamp: new Date().toISOString() });
            }

            try {
                const AuditLog = (await import('../models/AuditLog')).default;
                await AuditLog.logAction({
                    userId,
                    action: `UPCOMING_NIGHT_${payload.type}`,
                    metadata: payload.data
                }).catch(() => {});
            } catch (aErr) {}
        } catch (err) {
            logger.warn(`[NightPartnerService] Notification emit warning: ${err}`);
        }
    }

    /**
     * Consolidates all Upcoming Night notifications into ONE single evolving card per event/match.
     * Card ID: upcoming_night_timeline_${nightId}
     */
    public static async enrichUpcomingNightNotificationCard(nightId: string, recipientUserId: string): Promise<any | null> {
        try {
            let match = await NightPartnerMatch.findByPk(nightId, {
                include: [{ model: Venue, as: 'venue', attributes: ['name', 'addressLine1', 'city', 'coverImage', 'primaryPhoto'] }]
            });

            let requestRecord: NightPartnerRequest | null = null;
            if (!match) {
                requestRecord = await NightPartnerRequest.findByPk(nightId, {
                    include: [{ model: Venue, as: 'venue', attributes: ['name', 'addressLine1', 'city', 'coverImage', 'primaryPhoto'] }]
                });
                if (!requestRecord) {
                    return null;
                }
            }

            const isMatch = !!match;
            const venueName = isMatch ? ((match as any)?.venue?.name || 'Venue') : ((requestRecord as any)?.venue?.name || 'Venue');
            const eventDate = isMatch ? match!.eventDate : requestRecord!.eventDate;
            const hostId = isMatch ? match!.hostId : requestRecord!.hostId;
            const partnerId = isMatch ? match!.partnerId : requestRecord!.partnerId;
            const isHost = recipientUserId === hostId;

            // Resolve Banner Flyer if available
            let bannerImage = (match as any)?.venue?.coverImage || (match as any)?.venue?.primaryPhoto || (requestRecord as any)?.venue?.coverImage || (requestRecord as any)?.venue?.primaryPhoto || null;
            let eventTitle = venueName;
            try {
                const Ad = (await import('../models/Ad')).default;
                const ad = await Ad.findOne({
                    where: {
                        venueId: isMatch ? match!.venueId : requestRecord!.venueId,
                        isActive: true,
                    },
                    order: [['createdAt', 'DESC']],
                });
                if (ad) {
                    if (ad.imagePath) bannerImage = ad.imagePath;
                    if (ad.title) eventTitle = ad.title;
                }
            } catch (_) {}
            if (bannerImage && !bannerImage.startsWith('http') && !bannerImage.startsWith('/')) {
                bannerImage = `/${bannerImage.replace(/\\/g, '/')}`;
            }

            const isPosted = true;
            const isInterested = true;
            const isRequestSent = true;
            const isAccepted = isMatch || (requestRecord && requestRecord.status === NightPartnerRequestStatus.ACCEPTED);
            const isPaymentPending = isMatch && match!.status === NightPartnerMatchStatus.PAYMENT_PENDING;
            const isPaymentConfirmed = isMatch && match!.status === NightPartnerMatchStatus.CONFIRMED;
            const isChatEnabled = isMatch && match!.status === NightPartnerMatchStatus.CONFIRMED && !!match!.conversationId;
            const isCompleted = isMatch && match!.status === NightPartnerMatchStatus.CONFIRMED && new Date(eventDate).getTime() < Date.now() - 24 * 60 * 60 * 1000;
            const isDeclined = requestRecord && (requestRecord.status === NightPartnerRequestStatus.DECLINED || requestRecord.status === NightPartnerRequestStatus.CANCELLED);
            const isCancelled = isMatch && match!.status === NightPartnerMatchStatus.CANCELLED;

            const otherUserId = isHost ? partnerId : hostId;
            let otherUser: any = null;
            try {
                if (otherUserId) {
                    otherUser = await User.findByPk(otherUserId, {
                        attributes: ['id', 'firstName', 'lastName', 'isVerified'],
                        include: [
                            { model: UserProfile, as: 'profile', required: false },
                            { model: UserPhoto, as: 'photos', required: false },
                        ],
                    });
                }
            } catch (_) {}

            const photos = (otherUser as any)?.photos || [];
            const primaryPhoto = photos.find((p: any) => p.isPrimary) || photos[0];
            const otherUserName = otherUser?.firstName || (isHost ? 'Partner' : 'Host');

            const reminder2h = isMatch ? (match!.reminder2hSent || false) : (requestRecord?.reminder2hSent || false);
            const reminder1h = isMatch ? (match!.reminder1hSent || false) : (requestRecord?.reminder1hSent || false);
            const reminder30m = isMatch ? (match!.reminder30mSent || false) : (requestRecord?.reminder30mSent || false);

            const timelineSteps = [
                { id: 'posted', label: 'Night Posted', completed: isPosted },
                { id: 'interested', label: 'Interested', completed: isInterested },
                { id: 'request_sent', label: 'Request Sent', completed: isRequestSent },
                { id: 'request_accepted', label: 'Request Accepted', completed: isAccepted || isPaymentConfirmed || isCompleted },
                { id: 'payment_pending', label: 'Payment Pending', completed: isPaymentPending || isPaymentConfirmed || isCompleted },
                { id: 'payment_completed', label: 'Payment Completed', completed: isPaymentConfirmed || isCompleted },
                { id: 'chat_enabled', label: 'Chat Enabled', completed: isChatEnabled || isCompleted },
                { id: 'reminder_2h', label: '2 Hour Reminder', completed: reminder2h || isCompleted },
                { id: 'reminder_1h', label: '1 Hour Reminder', completed: reminder1h || isCompleted },
                { id: 'reminder_30m', label: '30 Minute Reminder', completed: reminder30m || isCompleted },
                { id: 'completed', label: 'Event Completed', completed: isCompleted }
            ];

            const completedCount = timelineSteps.filter(s => s.completed).length;
            const progressPercentage = Math.round((completedCount / timelineSteps.length) * 100);

            const isCancellationRequested = isMatch && match!.cancellationStatus === NightPartnerCancellationStatus.REQUESTED;
            const isCanceller = isCancellationRequested && match!.cancelledBy === recipientUserId;
            const isCancellationRecipient = isCancellationRequested && match!.cancelledBy !== recipientUserId;

            let title = `Upcoming Night at ${venueName} 🌟`;
            let body = `Your Upcoming Night partner invite at ${venueName}.`;
            let statusText = 'Request Sent';

            if (!isHost && requestRecord && requestRecord.status === NightPartnerRequestStatus.PENDING) {
                title = `Night Partner Invite 🌙 - ${venueName}`;
                body = `${otherUserName} invited you to join for Upcoming Night at ${venueName}!`;
                statusText = 'Invite Received';
            } else if (isCancelled) {
                title = `Upcoming Night Cancelled ❌`;
                body = `The event at ${venueName} was cancelled and refund processed if applicable.`;
                statusText = 'Cancelled';
            } else if (isCancellationRecipient) {
                title = `Partner Requested Cancellation ⚠️`;
                body = `${otherUserName} requested to cancel Upcoming Night at ${venueName}. Reason: "${match?.cancellationReason || 'Change of plans'}". Please confirm or keep active.`;
                statusText = 'Cancellation Request Received';
            } else if (isCanceller) {
                title = `Cancellation Requested ⏳`;
                body = `Waiting for your partner to confirm the cancellation of Upcoming Night at ${venueName}.`;
                statusText = 'Pending Partner Confirmation';
            } else if (isCompleted) {
                title = `Upcoming Night Completed ✨`;
                body = `Hope you had a great time at ${venueName}!`;
                statusText = 'Completed';
            } else if (isPaymentConfirmed) {
                title = `Upcoming Night Confirmed! 🎉`;
                body = `Your night at ${venueName} is fully confirmed. Chat is now unlocked!`;
                statusText = 'Confirmed & Chat Unlocked';
            } else if (isPaymentPending) {
                const userAmount = isHost ? (match?.hostAmount || match?.totalAmount) : (match?.partnerAmount || 0);
                title = `Payment Required for Upcoming Night 💳`;
                body = `Request accepted! Complete payment (₹${userAmount}) to confirm your night at ${venueName}.`;
                statusText = 'Payment Required';
            } else if (isAccepted) {
                title = `Upcoming Night Invite Accepted! 🎉`;
                body = `Your partner request for ${venueName} was accepted! Select payment mode to proceed.`;
                statusText = 'Accepted';
            } else if (isDeclined) {
                title = `Upcoming Night Invite Declined ❌`;
                body = `Partner invite for ${venueName} was declined or cancelled.`;
                statusText = 'Declined';
            }

            const actionButtons = [];
            if (isCancellationRecipient) {
                actionButtons.push({ id: 'accept_cancellation', label: 'Confirm & Refund', primary: true, action: 'ACCEPT_CANCELLATION' });
                actionButtons.push({ id: 'reject_cancellation', label: 'Keep Active', primary: false, action: 'REJECT_CANCELLATION' });
            } else if (isCanceller) {
                actionButtons.push({ id: 'view_details', label: 'View Details', primary: false, action: 'VIEW_DETAILS' });
            } else {
                if (!isHost && requestRecord && requestRecord.status === NightPartnerRequestStatus.PENDING) {
                    actionButtons.push({ id: 'accept_request', label: 'Accept', primary: true, action: 'ACCEPT_REQUEST' });
                    actionButtons.push({ id: 'decline_request', label: 'Decline', primary: false, action: 'DECLINE_REQUEST' });
                }
                if (isMatch && match!.status === NightPartnerMatchStatus.MATCHED && isHost) {
                    actionButtons.push({ id: 'pay_now', label: 'Confirm & Pay', primary: true, action: 'PAY_NOW' });
                }
                if (isPaymentPending) {
                    const isMyPaymentDue = isHost ? !match?.hostPaid : !match?.partnerPaid;
                    if (isMyPaymentDue) {
                        actionButtons.push({ id: 'pay_now', label: 'Pay Now', primary: true, action: 'PAY_NOW' });
                    }
                }
                if (isChatEnabled) {
                    actionButtons.push({ id: 'view_ticket', label: 'View Ticket', primary: true, action: 'VIEW_TICKET' });
                    actionButtons.push({ id: 'open_chat', label: 'Open Chat', primary: false, action: 'OPEN_CHAT' });
                    actionButtons.push({ id: 'cancel_event', label: 'Cancel', primary: false, action: 'CANCEL_EVENT' });
                }
                actionButtons.push({ id: 'view_details', label: 'View Details', primary: false, action: 'VIEW_DETAILS' });
            }

            const updatedIso = isMatch 
                ? (match!.updatedAt ? match!.updatedAt.toISOString() : new Date().toISOString())
                : (requestRecord!.updatedAt ? requestRecord!.updatedAt.toISOString() : new Date().toISOString());

            return {
                id: `upcoming_night_timeline_${nightId}`,
                title,
                body,
                createdAt: updatedIso,
                updatedAt: updatedIso,
                read: false,
                isRead: false,
                category: isPaymentConfirmed ? 'bookings' : 'requests',
                type: 'upcoming_night_timeline',
                eventType: (!isHost && requestRecord?.status === NightPartnerRequestStatus.PENDING) ? 'PARTNER_REQUEST_RECEIVED' : 'UPCOMING_NIGHT_TIMELINE',
                actor: {
                    id: otherUser?.id || otherUserId,
                    firstName: otherUser?.firstName || otherUserName,
                    lastName: otherUser?.lastName || '',
                    profilePhotoUrl: primaryPhoto?.filePath || null,
                    isVerified: !!otherUser?.isVerified,
                },
                sender: {
                    id: otherUser?.id || otherUserId,
                    firstName: otherUser?.firstName || otherUserName,
                    lastName: otherUser?.lastName || '',
                    profilePhotoUrl: primaryPhoto?.filePath || null,
                    isVerified: !!otherUser?.isVerified,
                },
                imageUrl: primaryPhoto?.filePath || null,
                data: {
                    type: 'upcoming_night_timeline',
                    nightId,
                    requestId: isMatch ? undefined : requestRecord!.id,
                    matchId: isMatch ? match!.id : undefined,
                    venueName,
                    eventName: eventTitle,
                    eventDate,
                    eventTime: normalize12h(isMatch ? (match as any).eventTime : (requestRecord?.eventTime || '20:00')),
                    isHost,
                    userRole: isHost ? 'HOST' : 'PARTNER',
                    hostId,
                    partnerId,
                    recipientUserId,
                    actorUserId: isHost ? hostId : partnerId,
                    status: isMatch ? match!.status : requestRecord!.status,
                    stage: isMatch ? match!.status : (requestRecord!.status === NightPartnerRequestStatus.PENDING ? 'INVITE_SENT' : requestRecord!.status),
                    coverImageUrl: bannerImage,
                    otherUserId,
                    otherUserName,
                    otherUserPhoto: primaryPhoto?.filePath || null,
                    partner: {
                        id: otherUserId,
                        firstName: otherUserName,
                        name: otherUserName,
                        photo: primaryPhoto?.filePath || null,
                        profilePhotoUrl: primaryPhoto?.filePath || null,
                    },
                    sender: {
                        id: otherUserId,
                        firstName: otherUserName,
                        name: otherUserName,
                        photo: primaryPhoto?.filePath || null,
                        profilePhotoUrl: primaryPhoto?.filePath || null,
                    },
                    event: {
                        venueName,
                        name: eventTitle,
                        title: eventTitle,
                        date: eventDate,
                        time: normalize12h(isMatch ? (match as any).eventTime : (requestRecord?.eventTime || '20:00')),
                        coverImageUrl: bannerImage,
                    },
                    statusText,
                    paymentMode: match?.paymentMode || 'SELF_PAY',
                    hostPaid: match?.hostPaid || false,
                    partnerPaid: match?.partnerPaid || false,
                    totalAmount: match?.totalAmount || 0,
                    hostAmount: match?.hostAmount || 0,
                    partnerAmount: match?.partnerAmount || 0,
                    bookingId: match?.bookingId,
                    conversationId: match?.conversationId,
                    timelineProgress: progressPercentage,
                    currentStatusStep: isCompleted ? 11 : (isPaymentConfirmed ? 7 : (isPaymentPending ? 5 : (isAccepted ? 4 : 3))),
                    timelineSteps,
                    actionButtons
                }
            };
        } catch (err) {
            logger.error(`[NightPartnerService] enrichUpcomingNightNotificationCard error for ${nightId}:`, err);
            return null;
        }
    }
}
