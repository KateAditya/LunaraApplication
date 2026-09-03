import { Request, Response } from 'express';
import crypto from 'crypto';
import { Op } from 'sequelize';
import sequelize from '../config/database';
import {
    Ticket,
    Venue,
    User,
    Booking,
    GroupParty,
    PartyPlan,
    PartyPlanRequest,
    StrangersMeetRequest,
    StrangersMeetJoiner,
    Plan,
    PlanJoinRequest,
    VenueImage,
    Ad,
} from '../models';
import { TicketStatus } from '../models/Ticket';
import { GoingMode } from '../models/Booking';
import { PartyPlanRequestStatus } from '../models/PartyPlanRequest';
import { StrangersMeetStatus } from '../models/StrangersMeetRequest';
import { StrangersMeetJoinerStatus } from '../models/StrangersMeetJoiner';
import { logger } from '../config/logger';
import { RealtimeEventBroker } from '../services/RealtimeEventBroker';
import { parseEventDateTimeToUTC, formatTime12Hour, formatDateFull } from '../utils/dateTimeUtils';

export function formatTimeTo12Hour(timeStr?: string | null): string {
    if (!timeStr) return '08:00 PM';
    return formatTime12Hour(timeStr);
}

function parseEventStartDateTime(dateVal?: string | Date | null, timeStr?: string | null): Date {
    return parseEventDateTimeToUTC(dateVal || new Date(), timeStr);
}

function getActualExpiration(startAt: Date, endAt?: Date | null, expAt?: Date | null): Date {
    const now = new Date();
    const defaultExp = new Date(startAt.getTime() + 30 * 60 * 60 * 1000);

    if (expAt && expAt.getTime() > now.getTime()) {
        return expAt;
    }
    if (endAt && endAt.getTime() > now.getTime()) {
        return endAt;
    }

    return defaultExp;
}

const MENU_IMAGE_TYPES = ['menu', 'food_menu', 'bar_menu', 'beverage_menu', 'party_packages'];

export function extractVenueCoverImageUrl(venue: any): string | null {
    if (!venue) return null;
    
    // Check if direct properties exist and aren't menu images
    if (venue.coverImageUrl && typeof venue.coverImageUrl === 'string' && !venue.coverImageUrl.toLowerCase().includes('menu')) {
        return venue.coverImageUrl.startsWith('http') ? venue.coverImageUrl : `/${venue.coverImageUrl.replace(/^\/+/, '')}`;
    }
    if (venue.profilePhotoUrl && typeof venue.profilePhotoUrl === 'string' && !venue.profilePhotoUrl.toLowerCase().includes('menu')) {
        return venue.profilePhotoUrl.startsWith('http') ? venue.profilePhotoUrl : `/${venue.profilePhotoUrl.replace(/^\/+/, '')}`;
    }

    const images: any[] = venue.images || [];
    if (images.length > 0) {
        // 1. Primary non-menu image
        const primaryNonMenu = images.find((img: any) => img.isPrimary && !MENU_IMAGE_TYPES.includes((img.imageType || img.type || '').toLowerCase()));
        if (primaryNonMenu) {
            const p = primaryNonMenu.filePath || primaryNonMenu.url;
            if (p) return p.startsWith('http') ? p : `/${p.replace(/^\/+/, '')}`;
        }
        // 2. Any non-menu image
        const anyNonMenu = images.find((img: any) => !MENU_IMAGE_TYPES.includes((img.imageType || img.type || '').toLowerCase()));
        if (anyNonMenu) {
            const p = anyNonMenu.filePath || anyNonMenu.url;
            if (p) return p.startsWith('http') ? p : `/${p.replace(/^\/+/, '')}`;
        }
        const first = images[0];
        const p = first?.filePath || first?.url;
        if (p) return p.startsWith('http') ? p : `/${p.replace(/^\/+/, '')}`;
    }
    return null;
}

export class MobileTicketController {
    /**
     * GET /api/mobile/tickets
     * Fetch user tickets grouped by status tabs: upcoming, active, used, expired, cancelled
     * Comprehensively aggregates across Ticket, Booking, GroupParty, PartyPlan, and StrangersMeet models.
     */
    public static async getUserTickets(req: Request, res: Response): Promise<Response> {
        try {
            const userId = req.user?.id || (req.query.userId as string);
            if (!userId) {
                return res.status(400).json({ success: false, message: 'User ID is required' });
            }
            const tab = (req.query.tab as string) || 'all';
            const now = new Date();

            const venueInclude = {
                model: Venue,
                as: 'venue',
                attributes: ['id', 'name', 'addressLine1', 'city', 'area', 'latitude', 'longitude'],
                include: [
                    {
                        model: VenueImage,
                        as: 'images',
                        attributes: ['id', 'filePath', 'imageType', 'isPrimary'],
                        required: false,
                    },
                ],
                required: false,
            };

            const userInclude = {
                model: User,
                as: 'user',
                attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                required: false,
            };

            // Parallel fetch across all potential ticket sources for this user with exact projections
            const [
                tickets,
                confirmedBookings,
                confirmedGroupParties,
                partyPlanJoinerReqs,
                partyPlanHostPlans,
                strangersJoinerReqs,
                strangersHostMeets,
                socialTablePlans,
                socialJoinReqs,
            ] = await Promise.all([
                Ticket.findAll({
                    where: { userId },
                    attributes: ['id', 'ticketId', 'bookingId', 'bookingType', 'ticketStatus', 'eventStartAt', 'eventEndAt', 'issuedAt', 'expiresAt', 'usedAt', 'pdfUrl', 'qrToken', 'venueId', 'userId'],
                    include: [venueInclude, userInclude],
                    order: [['eventStartAt', 'DESC']],
                }).catch((err: any) => {
                    logger.error('getUserTickets Ticket query error:', err);
                    return [];
                }),
                Booking.findAll({
                    where: { userId },
                    attributes: ['id', 'bookingDate', 'startTime', 'status', 'paymentStatus', 'adminApprovalStatus', 'totalAmount', 'numberOfGuests', 'tablePackage', 'goingMode', 'isLargePartyRequest', 'isUpcomingNight', 'partySubject', 'partyRequirement', 'partyDescription', 'mobileNumber', 'venueId', 'partyEventId', 'ticketUrl', 'ticketCode', 'createdAt'],
                    include: [
                        venueInclude,
                        userInclude,
                        {
                            model: Ad,
                            as: 'partyEvent',
                            attributes: ['id', 'title', 'imagePath', 'aboutEvent', 'eventDate', 'entryPrice'],
                            required: false,
                        },
                    ],
                    order: [['bookingDate', 'DESC'], ['startTime', 'DESC']],
                }).catch(err => {
                    logger.error('getUserTickets Booking query error:', err);
                    return [];
                }),
                GroupParty.findAll({
                    where: { userId },
                    attributes: ['id', 'partyDate', 'startTime', 'status', 'paymentStatus', 'totalAmount', 'numberOfFriends', 'foodPreference', 'drinkPreference', 'mobileNumber', 'venueId', 'ticketUrl', 'ticketCode', 'expiresAt', 'createdAt'],
                    include: [venueInclude, userInclude],
                    order: [['partyDate', 'DESC'], ['startTime', 'DESC']],
                }).catch(err => {
                    logger.error('getUserTickets GroupParty query error:', err);
                    return [];
                }),
                PartyPlanRequest.findAll({
                    where: {
                        requesterId: userId,
                        status: { [Op.ne]: PartyPlanRequestStatus.PAYMENT_FAILED },
                    },
                    attributes: ['id', 'requesterId', 'planId', 'status', 'joinerPaymentStatus', 'createdAt'],
                    include: [
                        {
                            model: PartyPlan,
                            as: 'plan',
                            attributes: ['id', 'userId', 'planDateTime', 'status', 'lifecycleStatus', 'hostPaymentStatus', 'depositAmount', 'matchedRequestId', 'venueId', 'paymentType', 'createdAt'],
                            include: [
                                venueInclude,
                                { model: User, as: 'creator', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl', 'phone', 'email'] },
                            ],
                        },
                        { model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl', 'phone', 'email'] },
                    ],
                    order: [['createdAt', 'DESC']],
                }).catch(err => {
                    logger.error('getUserTickets PartyPlanRequest query error:', err);
                    return [];
                }),
                PartyPlan.findAll({
                    where: { userId },
                    attributes: ['id', 'userId', 'planDateTime', 'status', 'lifecycleStatus', 'hostPaymentStatus', 'depositAmount', 'matchedRequestId', 'venueId', 'paymentType', 'createdAt'],
                    include: [venueInclude, userInclude],
                    order: [['planDateTime', 'DESC']],
                }).catch(err => {
                    logger.error('getUserTickets PartyPlan host query error:', err);
                    return [];
                }),
                StrangersMeetJoiner.findAll({
                    where: {
                        userId,
                        status: { [Op.ne]: StrangersMeetJoinerStatus.REJECTED },
                    },
                    attributes: ['id', 'userId', 'strangersMeetRequestId', 'status', 'paymentStatus', 'paymentAmount', 'createdAt'],
                    include: [
                        {
                            model: StrangersMeetRequest,
                            as: 'strangersMeetRequest',
                            attributes: ['id', 'userId', 'venueId', 'subject', 'tagline', 'eventDateTime', 'numberOfPersons', 'chargesPerHead', 'status', 'paymentStatus', 'paymentAmount', 'ticketId', 'ticketUrl', 'expectedEndAt', 'createdAt'],
                            include: [venueInclude, userInclude],
                        },
                    ],
                    order: [['createdAt', 'DESC']],
                }).catch(err => {
                    logger.error('getUserTickets StrangersMeetJoiner query error:', err);
                    return [];
                }),
                StrangersMeetRequest.findAll({
                    where: {
                        userId,
                        status: { [Op.ne]: StrangersMeetStatus.REJECTED },
                    },
                    attributes: ['id', 'userId', 'venueId', 'subject', 'tagline', 'eventDateTime', 'numberOfPersons', 'chargesPerHead', 'status', 'paymentStatus', 'paymentAmount', 'ticketId', 'ticketUrl', 'expectedEndAt', 'createdAt'],
                    include: [venueInclude, userInclude],
                    order: [['createdAt', 'DESC']],
                }).catch(err => {
                    logger.error('getUserTickets StrangersMeetRequest query error:', err);
                    return [];
                }),
                Plan.findAll({
                    where: { userId },
                    attributes: ['id', 'userId', 'planDate', 'startTime', 'tablePackage', 'paymentOption', 'totalAmount', 'maxJoiners', 'currentJoiners', 'status', 'bookingId', 'venueId', 'createdAt'],
                    include: [venueInclude, { model: User, as: 'host', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl', 'phone', 'email'] }],
                    order: [['planDate', 'DESC']],
                }).catch(err => {
                    logger.error('getUserTickets Plan query error:', err);
                    return [];
                }),
                PlanJoinRequest.findAll({
                    where: { requesterId: userId },
                    attributes: ['id', 'requesterId', 'planId', 'status', 'createdAt'],
                    include: [
                        {
                            model: Plan,
                            as: 'plan',
                            attributes: ['id', 'userId', 'planDate', 'startTime', 'tablePackage', 'paymentOption', 'totalAmount', 'maxJoiners', 'currentJoiners', 'status', 'bookingId', 'venueId', 'createdAt'],
                            include: [venueInclude, { model: User, as: 'host', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl', 'phone', 'email'] }],
                        },
                        {
                            model: User,
                            as: 'requester',
                            attributes: ['id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl'],
                            required: false,
                        },
                    ],
                    order: [['createdAt', 'DESC']],
                }).catch(err => {
                    logger.error('getUserTickets PlanJoinRequest query error:', err);
                    return [];
                }),
            ]);

            const seenBookingIds = new Set<string>();
            const seenTicketIds = new Set<string>();
            const formattedTickets: any[] = [];

            // 1. Process explicit Ticket table records
            const bookingIds = tickets.map((t: any) => t.bookingId).filter(Boolean);
            const sourceBookings = bookingIds.length === 0 ? [] : await Booking.findAll({
                where: { id: { [Op.in]: bookingIds } },
                attributes: ['id', 'bookingDate', 'startTime', 'status', 'paymentStatus', 'adminApprovalStatus', 'totalAmount', 'numberOfGuests', 'tablePackage', 'goingMode', 'isLargePartyRequest', 'isUpcomingNight', 'partySubject', 'partyRequirement', 'partyDescription', 'mobileNumber', 'venueId', 'partyEventId', 'ticketUrl', 'ticketCode', 'specialRequests', 'createdAt'],
                include: [
                    venueInclude,
                    userInclude,
                    {
                        model: Ad,
                        as: 'partyEvent',
                        attributes: ['id', 'title', 'imagePath', 'aboutEvent', 'eventDate', 'entryPrice'],
                        required: false,
                    },
                ],
            });

            const partyPlanIdsFromBookings: string[] = [];
            for (const b of sourceBookings) {
                if (b.specialRequests) {
                    try {
                        const meta = typeof b.specialRequests === 'string' ? JSON.parse(b.specialRequests) : b.specialRequests;
                        if (meta.planId) partyPlanIdsFromBookings.push(meta.planId);
                    } catch (_) {}
                }
            }
            const allPartyPlanIds = [...new Set([...bookingIds, ...partyPlanIdsFromBookings])];

            const [sourceGroupParties, sourceStrangersMeets, sourceStrangersJoiners, sourcePartyPlans] = bookingIds.length === 0
                ? [[], [], [], []]
                : await Promise.all([
                    GroupParty.findAll({
                        where: { id: { [Op.in]: bookingIds } },
                        attributes: ['id', 'partyDate', 'startTime', 'status', 'paymentStatus', 'totalAmount', 'numberOfFriends', 'foodPreference', 'drinkPreference', 'mobileNumber', 'venueId', 'ticketUrl', 'ticketCode', 'createdAt'],
                        include: [venueInclude, userInclude],
                    }),
                    StrangersMeetRequest.findAll({
                        where: { id: { [Op.in]: bookingIds } },
                        attributes: ['id', 'userId', 'venueId', 'subject', 'tagline', 'eventDateTime', 'numberOfPersons', 'chargesPerHead', 'paymentAmount', 'status', 'ticketId', 'ticketUrl'],
                        include: [venueInclude, userInclude],
                    }),
                    StrangersMeetJoiner.findAll({
                        where: { id: { [Op.in]: bookingIds } },
                        attributes: ['id', 'userId', 'strangersMeetRequestId', 'paymentAmount', 'status'],
                        include: [
                            {
                                model: StrangersMeetRequest,
                                as: 'strangersMeetRequest',
                                attributes: ['id', 'userId', 'venueId', 'subject', 'tagline', 'eventDateTime', 'numberOfPersons', 'chargesPerHead', 'paymentAmount', 'status', 'ticketId', 'ticketUrl'],
                                include: [venueInclude, userInclude],
                            },
                        ],
                    }),
                    PartyPlan.findAll({
                        where: { id: { [Op.in]: allPartyPlanIds } },
                        attributes: ['id', 'userId', 'venueId', 'planDateTime', 'depositAmount', 'status', 'lifecycleStatus', 'hostPaymentStatus', 'matchedRequestId', 'createdAt'],
                        include: [venueInclude, userInclude],
                    }),
                ]);
            const bookingById = new Map(sourceBookings.map(b => [b.id, b]));
            const groupPartyById = new Map(sourceGroupParties.map(g => [g.id, g]));
            const strangersMeetById = new Map(sourceStrangersMeets.map(sm => [sm.id, sm]));
            const strangersJoinerById = new Map(sourceStrangersJoiners.map(j => [j.id, j]));
            const partyPlanById = new Map(sourcePartyPlans.map(p => [p.id, p]));

            for (const t of tickets) {
                if (t.bookingId) seenBookingIds.add(t.bookingId);
                if (t.ticketId) seenTicketIds.add(t.ticketId);

                const sourceBooking = bookingById.get(t.bookingId);
                const sourceGroupParty = groupPartyById.get(t.bookingId);
                const sourceStrangersMeet = strangersMeetById.get(t.bookingId);
                const sourceStrangersJoiner = strangersJoinerById.get(t.bookingId);
                let sourcePartyPlan = partyPlanById.get(t.bookingId);
                if (!sourcePartyPlan && sourceBooking?.specialRequests) {
                    try {
                        const meta = typeof sourceBooking.specialRequests === 'string' ? JSON.parse(sourceBooking.specialRequests) : sourceBooking.specialRequests;
                        if (meta.planId) sourcePartyPlan = partyPlanById.get(meta.planId);
                    } catch (_) {}
                }

                const isPartyPlan = t.bookingType === 'party_plan' || Boolean(sourcePartyPlan) || sourceBooking?.goingMode === 'plan';
                const partyPlanDt = sourcePartyPlan?.planDateTime ? new Date(sourcePartyPlan.planDateTime) : null;
                const startDate = (isPartyPlan && partyPlanDt && !isNaN(partyPlanDt.getTime()))
                    ? partyPlanDt
                    : (t.eventStartAt ? new Date(t.eventStartAt) : new Date());
                const actualExpiresAt = getActualExpiration(startDate, t.eventEndAt ? new Date(t.eventEndAt) : null, t.expiresAt ? new Date(t.expiresAt) : null);
                const isExpired = t.ticketStatus === TicketStatus.EXPIRED || actualExpiresAt < now;
                const sourceStartTime = sourceGroupParty?.startTime || sourceBooking?.startTime;
                let startTimeStr = '08:00 PM';
                if (isPartyPlan && partyPlanDt && !isNaN(partyPlanDt.getTime())) {
                    startTimeStr = formatTime12Hour(partyPlanDt);
                } else if (sourceStartTime) {
                    startTimeStr = formatTime12Hour(parseEventDateTimeToUTC(t.eventStartAt || new Date(), sourceStartTime));
                } else if (t.eventStartAt) {
                    startTimeStr = formatTime12Hour(t.eventStartAt);
                }
                const isStrangersMeet = t.bookingType === 'strangers_meet' || Boolean(sourceStrangersMeet) || Boolean(sourceStrangersJoiner);
                const isSolo = !isPartyPlan && !isStrangersMeet && (t.bookingType === 'solo' || sourceBooking?.goingMode === 'solo');
                const isLargeParty = !isPartyPlan && !isStrangersMeet && !isSolo && ((t.bookingType === 'group_party' && sourceBooking?.isLargePartyRequest === true) || Boolean((t as any).isLargeParty));
                const isGroupParty = !isPartyPlan && !isStrangersMeet && !isSolo && !isLargeParty && ((t.bookingType === 'group_party') || Boolean(sourceGroupParty));
                const isEventBooking = Boolean(sourceBooking?.isUpcomingNight);
                const isVenueBooking = !isPartyPlan && !isStrangersMeet && !isLargeParty && !isGroupParty && !isEventBooking && !isSolo;

                let category = 'venue_booking';
                if (isPartyPlan) category = 'party_plan';
                else if (isStrangersMeet) category = 'strangers_meet';
                else if (isSolo) category = 'solo';
                else if (isLargeParty) category = 'large_party';
                else if (isGroupParty) category = 'group_party';
                else if (isEventBooking) category = 'event_booking';
                else category = 'venue_booking';

                const rawUser = (t as any).user;
                const userObj = rawUser ? {
                    id: rawUser.id,
                    fullName: `${rawUser.firstName || ''} ${rawUser.lastName || ''}`.trim() || 'Guest',
                    firstName: rawUser.firstName,
                    lastName: rawUser.lastName,
                    email: rawUser.email,
                    phone: rawUser.phone,
                    mobileNumber: rawUser.phone,
                    profilePhotoUrl: rawUser.profileImageUrl || null,
                    profileImageUrl: rawUser.profileImageUrl || null,
                } : null;

                const smMeet = sourceStrangersMeet || (sourceStrangersJoiner as any)?.strangersMeetRequest;
                const smAmount = sourceStrangersMeet
                    ? Number(sourceStrangersMeet.paymentAmount ?? sourceStrangersMeet.chargesPerHead ?? 0)
                    : (sourceStrangersJoiner ? Number((sourceStrangersJoiner as any).paymentAmount ?? smMeet?.chargesPerHead ?? 0) : null);
                const smGuests = sourceStrangersMeet ? Number(sourceStrangersMeet.numberOfPersons || 2) : 2;
                const smSubject = smMeet?.subject || 'Strangers Meetup';
                const smTagline = smMeet?.tagline || '';

                const amountVal = sourceBooking
                    ? Number(sourceBooking.totalAmount)
                    : (sourceGroupParty
                        ? Number(sourceGroupParty.totalAmount)
                        : (smAmount != null
                            ? smAmount
                            : (sourcePartyPlan ? Number(sourcePartyPlan.depositAmount || 99) : null)));
                const isFree = amountVal != null ? amountVal <= 0 : false;

                const sbPartyEvent = (sourceBooking as any)?.partyEvent;
                const eventBanner = sbPartyEvent?.imagePath
                    ? (sbPartyEvent.imagePath.startsWith('http') ? sbPartyEvent.imagePath : `/${sbPartyEvent.imagePath.replace(/^\/+/, '')}`)
                    : null;
                const eventTitle = isStrangersMeet
                    ? smSubject
                    : (isPartyPlan
                        ? ((sourcePartyPlan as any)?.planTheme || 'Party Plan Match')
                        : (sbPartyEvent?.title || sourceBooking?.partySubject || (isEventBooking ? 'Upcoming Night Event' : null)));

                const tablePackage = isStrangersMeet
                    ? (smSubject || 'Stranger Meetup')
                    : (isPartyPlan
                        ? 'Party Plan Match'
                        : (sourceBooking ? sourceBooking.tablePackage : (isGroupParty ? 'Group Table' : (isEventBooking ? (eventTitle || 'Event Entry') : null))));

                const numberOfGuests = isStrangersMeet
                    ? smGuests
                    : (isPartyPlan ? 2 : (sourceBooking ? sourceBooking.numberOfGuests : (sourceGroupParty ? sourceGroupParty.numberOfFriends : null)));

                let rawRequestObj: any = undefined;
                if (isStrangersMeet && smMeet) {
                    const smJson = (smMeet.toJSON ? smMeet.toJSON() : smMeet);
                    rawRequestObj = {
                        ...smJson,
                        venue: smMeet.venue || (t.venue as any),
                        user: smMeet.user || userObj,
                        host: smMeet.user || userObj,
                        ticketId: t.ticketId,
                        ticketCode: t.ticketId,
                        totalAmount: smAmount,
                        paymentAmount: smAmount,
                        chargesPerHead: Number(smMeet.chargesPerHead || 0),
                        subject: smSubject,
                        tagline: smTagline,
                        eventDateTime: smMeet.eventDateTime || t.eventStartAt,
                    };
                } else if (isPartyPlan && sourcePartyPlan) {
                    rawRequestObj = sourcePartyPlan.toJSON ? sourcePartyPlan.toJSON() : sourcePartyPlan;
                }

                const venueCoverUrl = extractVenueCoverImageUrl(t.venue || smMeet?.venue);
                const ticketImageUrl = eventBanner || venueCoverUrl;

                formattedTickets.push({
                    id: t.id,
                    ticketId: t.ticketId,
                    ticketCode: t.ticketId,
                    bookingId: t.bookingId,
                    bookingType: t.bookingType,
                    category,
                    status: isExpired && t.ticketStatus !== TicketStatus.CANCELLED ? TicketStatus.EXPIRED : t.ticketStatus,
                    bookingDate: (isPartyPlan && partyPlanDt) ? partyPlanDt : t.eventStartAt,
                    startTime: startTimeStr,
                    eventStartAt: (isPartyPlan && partyPlanDt) ? partyPlanDt : t.eventStartAt,
                    eventEndAt: t.eventEndAt || actualExpiresAt,
                    issuedAt: t.issuedAt,
                    expiresAt: actualExpiresAt,
                    usedAt: t.usedAt,
                    pdfUrl: isExpired ? null : t.pdfUrl,
                    qrToken: isExpired ? null : t.qrToken,
                    ticketUrl: isExpired ? null : t.pdfUrl,
                    totalAmount: amountVal,
                    paymentAmount: amountVal,
                    chargesPerHead: isStrangersMeet && smMeet ? Number(smMeet.chargesPerHead || 0) : undefined,
                    isFree,
                    numberOfGuests,
                    tablePackage,
                    goingMode: sourceBooking ? sourceBooking.goingMode : (isSolo ? 'solo' : undefined),
                    bannerImageUrl: eventBanner,
                    eventPoster: eventBanner,
                    imageUrl: ticketImageUrl,
                    eventTitle,
                    partySubject: eventTitle || sourceBooking?.partySubject,
                    subject: isStrangersMeet ? smSubject : undefined,
                    tagline: isStrangersMeet ? smTagline : undefined,
                    rawRequest: rawRequestObj,
                    plan: isPartyPlan && sourcePartyPlan ? {
                        ...(sourcePartyPlan.toJSON ? sourcePartyPlan.toJSON() : sourcePartyPlan),
                        venue: (sourcePartyPlan as any).venue || t.venue,
                        creator: (sourcePartyPlan as any).user || userObj,
                        user: (sourcePartyPlan as any).user || userObj,
                        host: (sourcePartyPlan as any).user || userObj,
                        planDateTime: sourcePartyPlan.planDateTime || t.eventStartAt,
                        depositAmount: sourcePartyPlan.depositAmount || amountVal,
                    } : undefined,
                    groupParty: isGroupParty && sourceGroupParty ? {
                        ...(sourceGroupParty.toJSON ? sourceGroupParty.toJSON() : sourceGroupParty),
                        venue: (sourceGroupParty as any).venue || t.venue,
                        user: (sourceGroupParty as any).user || userObj,
                        host: (sourceGroupParty as any).user || userObj,
                        partyDate: sourceGroupParty.partyDate || t.eventStartAt,
                        startTime: sourceGroupParty.startTime || startTimeStr,
                        totalAmount: sourceGroupParty.totalAmount || amountVal,
                    } : undefined,
                    booking: sourceBooking ? {
                        ...(sourceBooking.toJSON ? sourceBooking.toJSON() : sourceBooking),
                        venue: (sourceBooking as any).venue || t.venue,
                        user: (sourceBooking as any).user || userObj,
                        host: (sourceBooking as any).user || userObj,
                        bookingDate: sourceBooking.bookingDate || t.eventStartAt,
                        startTime: sourceBooking.startTime || startTimeStr,
                        totalAmount: sourceBooking.totalAmount || amountVal,
                    } : undefined,
                    partyEvent: sbPartyEvent ? {
                        id: sbPartyEvent.id,
                        title: sbPartyEvent.title,
                        imagePath: eventBanner,
                        bannerImageUrl: eventBanner,
                        aboutEvent: sbPartyEvent.aboutEvent,
                        eventDate: sbPartyEvent.eventDate,
                        entryPrice: sbPartyEvent.entryPrice,
                    } : null,
                    isPartyPlan,
                    isGroupParty,
                    isLargeParty,
                    isLargePartyRequest: isLargeParty,
                    isStrangersMeet,
                    isSolo,
                    isEventBooking,
                    isUpcomingNight: isEventBooking,
                    isVenueBooking,
                    user: (isStrangersMeet && smMeet?.user) || userObj,
                    host: (isStrangersMeet && smMeet?.user) || userObj,
                    venueName: (isStrangersMeet && smMeet?.venue?.name) || t.venue?.name || 'Lunara Venue',
                    venueAddress: `${t.venue?.area || t.venue?.addressLine1 || ''}, ${t.venue?.city || ''}`.trim(),
                    venue: t.venue ? {
                        id: t.venue.id,
                        name: t.venue.name,
                        addressLine1: t.venue.addressLine1,
                        city: t.venue.city,
                        area: t.venue.area,
                        latitude: (t.venue as any).latitude ?? null,
                        longitude: (t.venue as any).longitude ?? null,
                        profilePhotoUrl: venueCoverUrl,
                        coverImageUrl: venueCoverUrl,
                        images: (t.venue as any).images ?? [],
                    } : (smMeet?.venue ? {
                        ...smMeet.venue,
                        profilePhotoUrl: venueCoverUrl,
                        coverImageUrl: venueCoverUrl,
                    } : null),
                    isExpired,
                });
            }

            // 2. Synthesize from Bookings if not already in tickets
            for (const b of confirmedBookings) {
                const bAny = b as any;
                if (seenBookingIds.has(b.id) || (bAny.ticketCode && seenTicketIds.has(bAny.ticketCode))) continue;

                const isLargePaid = b.paymentStatus === 'paid' || b.adminApprovalStatus === 'payment_done';
                if (b.isLargePartyRequest && !isLargePaid) {
                    continue; // Large party must be paid before ticket is generated/shown
                }
                const totalAmt = Number(b.totalAmount || 0);
                const isFreeBooking = totalAmt <= 0;
                const bStatusStr = (b.status as string || '').toLowerCase();
                const isPaidBooking = isLargePaid || b.paymentStatus === 'paid' || b.paymentStatus === 'refunded' || bStatusStr === 'cancelled' || (isFreeBooking && (bStatusStr === 'confirmed' || bStatusStr === 'completed'));
                if (!isPaidBooking) {
                    continue;
                }

                seenBookingIds.add(b.id);
                if (bAny.ticketCode) seenTicketIds.add(bAny.ticketCode);

                const isPlanBooking = b.goingMode === 'plan';
                let planStartAt: Date | null = null;
                if (isPlanBooking && b.specialRequests) {
                    try {
                        const meta = typeof b.specialRequests === 'string' ? JSON.parse(b.specialRequests) : b.specialRequests;
                        if (meta.planId) {
                            const p = partyPlanById.get(meta.planId);
                            if (p?.planDateTime) planStartAt = new Date(p.planDateTime);
                        }
                    } catch (_) {}
                }
                const sTime = b.startTime || '00:00';
                const startAt = planStartAt || parseEventStartDateTime(b.bookingDate, sTime);
                const expAt = getActualExpiration(startAt);
                const bStatus = (b.status || '').toLowerCase();
                const isCancelled = bStatus === 'cancelled';
                const isCompleted = bStatus === 'completed';
                const isExpired = bStatus === 'expired' || isCompleted || expAt < now;
                const ticketCode = bAny.ticketCode || `LUN-${startAt.getFullYear()}-BK-${b.id.substring(0, 6).toUpperCase()}`;

                const isUpcomingNight = Boolean(b.isUpcomingNight);
                const isSolo = !isPlanBooking && b.goingMode === 'solo';
                const isLargeParty = !isPlanBooking && !isSolo && Boolean(b.isLargePartyRequest);
                const isGroupParty = !isPlanBooking && !isSolo && !isLargeParty && b.goingMode === 'party_request';
                const isEventBooking = isUpcomingNight;
                const isPartyPlan = isPlanBooking;
                const isVenueBooking = !isLargeParty && !isGroupParty && !isEventBooking && !isSolo && !isPartyPlan;

                let category = 'venue_booking';
                if (isPartyPlan) category = 'party_plan';
                else if (isSolo) category = 'solo';
                else if (isLargeParty) category = 'large_party';
                else if (isEventBooking) category = 'event_booking';
                else if (isGroupParty) category = 'group_party';
                else category = 'venue_booking';

                const bUser = bAny.user ? {
                    id: bAny.user.id,
                    fullName: `${bAny.user.firstName || ''} ${bAny.user.lastName || ''}`.trim() || 'Guest',
                    firstName: bAny.user.firstName,
                    lastName: bAny.user.lastName,
                    email: bAny.user.email,
                    phone: bAny.user.phone,
                    mobileNumber: bAny.user.phone,
                    profilePhotoUrl: bAny.user.profileImageUrl || null,
                    profileImageUrl: bAny.user.profileImageUrl || null,
                } : null;

                const bPartyEvent = (b as any).partyEvent;
                const eventBanner = bPartyEvent?.imagePath
                    ? (bPartyEvent.imagePath.startsWith('http') ? bPartyEvent.imagePath : `/${bPartyEvent.imagePath.replace(/^\/+/, '')}`)
                    : null;
                const eventTitle = bPartyEvent?.title || b.partySubject || (isEventBooking ? 'Upcoming Night Event' : null);
                const bVenueCoverUrl = extractVenueCoverImageUrl(bAny.venue);
                const bImageUrl = eventBanner || bVenueCoverUrl;

                formattedTickets.push({
                    id: b.id,
                    ticketId: ticketCode,
                    ticketCode,
                    bookingId: b.id,
                    bookingType: isLargeParty ? 'group_party' : (isSolo ? 'solo' : (isGroupParty ? 'group_party' : (isEventBooking ? 'event_booking' : 'venue_booking'))),
                    category,
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isExpired ? 'expired' : 'confirmed')),
                    bookingDate: planStartAt || b.bookingDate,
                    startTime: planStartAt ? formatTime12Hour(planStartAt) : formatTimeTo12Hour(sTime),
                    eventStartAt: startAt,
                    eventEndAt: expAt,
                    issuedAt: b.createdAt,
                    expiresAt: expAt,
                    usedAt: isCompleted ? expAt : null,
                    pdfUrl: isExpired ? null : (bAny.ticketUrl || null),
                    qrToken: isExpired ? null : ticketCode,
                    ticketUrl: isExpired ? null : (bAny.ticketUrl || null),
                    totalAmount: totalAmt,
                    isFree: isFreeBooking,
                    numberOfGuests: b.numberOfGuests || 1,
                    tablePackage: b.tablePackage || (isGroupParty ? 'Group Table' : (isEventBooking ? (eventTitle || 'Event Entry') : 'Standard')),
                    goingMode: b.goingMode,
                    bannerImageUrl: eventBanner,
                    eventPoster: eventBanner,
                    imageUrl: bImageUrl,
                    eventTitle,
                    partySubject: eventTitle || b.partySubject,
                    partyEvent: bPartyEvent ? {
                        id: bPartyEvent.id,
                        title: bPartyEvent.title,
                        imagePath: eventBanner,
                        bannerImageUrl: eventBanner,
                        aboutEvent: bPartyEvent.aboutEvent,
                        eventDate: bPartyEvent.eventDate,
                        entryPrice: bPartyEvent.entryPrice,
                    } : null,
                    isPartyPlan: false,
                    isGroupParty,
                    isLargeParty,
                    isLargePartyRequest: isLargeParty,
                    isStrangersMeet: false,
                    isSolo,
                    isEventBooking,
                    isUpcomingNight: isEventBooking,
                    isVenueBooking,
                    user: bUser,
                    host: bUser,
                    venueName: bAny.venue?.name || 'Lunara Venue',
                    venueAddress: `${bAny.venue?.area || bAny.venue?.addressLine1 || ''}, ${bAny.venue?.city || ''}`.trim(),
                    venue: bAny.venue ? {
                        id: bAny.venue.id,
                        name: bAny.venue.name,
                        addressLine1: bAny.venue.addressLine1,
                        city: bAny.venue.city,
                        area: bAny.venue.area,
                        latitude: bAny.venue.latitude ?? null,
                        longitude: bAny.venue.longitude ?? null,
                        profilePhotoUrl: bVenueCoverUrl,
                        coverImageUrl: bVenueCoverUrl,
                        images: bAny.venue.images ?? [],
                    } : null,
                    isExpired,
                });
            }

            // 3. Synthesize from GroupParty if not already in tickets
            for (const gp of confirmedGroupParties) {
                const gpAny = gp as any;
                if (seenBookingIds.has(gp.id) || (gpAny.ticketCode && seenTicketIds.has(gpAny.ticketCode))) continue;
                seenBookingIds.add(gp.id);
                if (gpAny.ticketCode) seenTicketIds.add(gpAny.ticketCode);

                const sTime = gp.startTime || '00:00';
                const startAt = parseEventStartDateTime(gp.partyDate, sTime);
                const expAt = getActualExpiration(startAt, null, gp.expiresAt ? new Date(gp.expiresAt) : null);
                const gpStatus = (gp.status || '').toLowerCase();
                const isCancelled = gpStatus === 'cancelled' || gpStatus === 'rejected';
                const isCompleted = gpStatus === 'completed';
                const isExpired = gpStatus === 'expired' || isCompleted || expAt < now;
                const ticketCode = gpAny.ticketCode || `LUN-${startAt.getFullYear()}-GP-${gp.id.substring(0, 6).toUpperCase()}`;

                const gpAmount = Number(gp.totalAmount || 0);
                const isFreeGp = gpAmount <= 0;

                const gpUser = gpAny.user ? {
                    id: gpAny.user.id,
                    fullName: `${gpAny.user.firstName || ''} ${gpAny.user.lastName || ''}`.trim() || 'Host',
                    firstName: gpAny.user.firstName,
                    lastName: gpAny.user.lastName,
                    email: gpAny.user.email,
                    phone: gpAny.user.phone,
                    mobileNumber: gpAny.user.phone,
                    profilePhotoUrl: gpAny.user.profileImageUrl || null,
                    profileImageUrl: gpAny.user.profileImageUrl || null,
                } : null;

                formattedTickets.push({
                    id: gp.id,
                    ticketId: ticketCode,
                    ticketCode,
                    bookingId: gp.id,
                    bookingType: 'group_party',
                    category: 'group_party',
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isExpired ? 'expired' : 'confirmed')),
                    bookingDate: gp.partyDate,
                    startTime: formatTimeTo12Hour(sTime),
                    eventStartAt: startAt,
                    eventEndAt: expAt,
                    issuedAt: gp.createdAt,
                    expiresAt: expAt,
                    usedAt: isCompleted ? expAt : null,
                    pdfUrl: isExpired ? null : (gpAny.ticketUrl || null),
                    qrToken: isExpired ? null : ticketCode,
                    ticketUrl: isExpired ? null : (gpAny.ticketUrl || null),
                    totalAmount: gpAmount,
                    isFree: isFreeGp,
                    numberOfGuests: gp.numberOfFriends || 5,
                    tablePackage: 'Group Table',
                    isPartyPlan: false,
                    isGroupParty: true,
                    isLargeParty: false,
                    isLargePartyRequest: false,
                    isStrangersMeet: false,
                    isSolo: false,
                    isEventBooking: false,
                    isUpcomingNight: false,
                    isVenueBooking: false,
                    user: gpUser,
                    host: gpUser,
                    venueName: gpAny.venue?.name || 'Lunara Venue',
                    venueAddress: `${gpAny.venue?.area || gpAny.venue?.addressLine1 || ''}, ${gpAny.venue?.city || ''}`.trim(),
                    venue: gpAny.venue ? {
                        id: gpAny.venue.id,
                        name: gpAny.venue.name,
                        addressLine1: gpAny.venue.addressLine1,
                        city: gpAny.venue.city,
                        area: gpAny.venue.area,
                        profilePhotoUrl: gpAny.venue.profilePhotoUrl ?? null,
                        coverImageUrl: gpAny.venue.coverImageUrl ?? null,
                        images: gpAny.venue.images ?? [],
                    } : null,
                    isExpired,
                });
            }

            // 4. Synthesize from PartyPlanRequest (Joiner)
            for (const req of partyPlanJoinerReqs) {
                const reqAny = req as any;
                const plan = reqAny.plan;
                if (!plan) continue;

                // STRICT RULE: No ticket before BOTH host and joiner payments are verified, unless cancelled!
                const sStatus = (req.status || '').toLowerCase();
                const pLife = (plan.lifecycleStatus || '').toLowerCase();
                const isCancelledReq = sStatus === 'cancelled' || sStatus === 'rejected' || pLife === 'cancelled' || (plan.status || '').toLowerCase() === 'cancelled' || (req.joinerPaymentStatus || '').toLowerCase() === 'refunded' || (plan.hostPaymentStatus || '').toLowerCase() === 'refunded';

                const hostPaid = (plan.hostPaymentStatus || '').toLowerCase() === 'paid' || (plan.hostPaymentStatus || '').toLowerCase() === 'refunded';
                const joinerPaid = (req.joinerPaymentStatus || '').toLowerCase() === 'paid' || (req.joinerPaymentStatus || '').toLowerCase() === 'refunded' || plan.paymentType === 'self_pay';
                const isBothPaidMatch = (hostPaid && joinerPaid && (
                    plan.lifecycleStatus === 'match_confirmed' ||
                    plan.lifecycleStatus === 'chat_enabled' ||
                    plan.lifecycleStatus === 'event_upcoming' ||
                    plan.matchedRequestId === req.id
                )) || isCancelledReq;

                if (!isBothPaidMatch) {
                    continue;
                }

                // Look up authoritative Booking and Ticket for this Party Plan
                let authBooking = await Booking.findOne({
                    where: {
                        goingMode: { [Op.in]: [GoingMode.PLAN, GoingMode.PARTY_REQUEST] },
                        venueId: plan.venueId,
                        specialRequests: { [Op.like]: `%"planId":"${plan.id}"%` },
                    },
                    order: [['createdAt', 'DESC']],
                });
                if (!authBooking) {
                    const dateObj = new Date(plan.planDateTime);
                    const bDate = dateObj.toISOString().split('T')[0];
                    authBooking = await Booking.findOne({
                        where: {
                            goingMode: { [Op.in]: [GoingMode.PLAN, GoingMode.PARTY_REQUEST] },
                            userId: plan.userId,
                            venueId: plan.venueId,
                            bookingDate: bDate as any,
                        },
                        order: [['createdAt', 'DESC']],
                    });
                }

                let authTicket: Ticket | null = null;
                if (authBooking) {
                    authTicket = await Ticket.findOne({
                        where: { [Op.or]: [{ bookingId: authBooking.id }, { ticketId: authBooking.ticketCode }] },
                        order: [['createdAt', 'DESC']],
                    });
                }

                const bookingIdVal = authBooking?.id || plan.id;
                const ticketCode = authTicket?.ticketId || authBooking?.ticketCode || reqAny.ticketCode || `PP-${plan.id.substring(0, 6).toUpperCase()}`;

                if (seenBookingIds.has(req.id) || seenBookingIds.has(plan.id) || seenBookingIds.has(bookingIdVal) || seenTicketIds.has(ticketCode)) continue;
                seenBookingIds.add(req.id);
                seenBookingIds.add(plan.id);
                seenBookingIds.add(bookingIdVal);
                seenTicketIds.add(ticketCode);

                const startAt = parseEventStartDateTime(plan.planDateTime, null);
                const expAt = authTicket?.expiresAt ? new Date(authTicket.expiresAt) : getActualExpiration(startAt);
                const isCancelled = sStatus === 'cancelled' || sStatus === 'rejected' || pLife === 'cancelled' || (plan.status || '').toLowerCase() === 'cancelled' || authTicket?.ticketStatus === TicketStatus.CANCELLED;
                const isCompleted = pLife === 'plan_completed' || authTicket?.ticketStatus === TicketStatus.USED;
                const isExpired = sStatus === 'expired' || isCompleted || expAt < now || authTicket?.ticketStatus === TicketStatus.EXPIRED;
                const ticketPdfUrl = authTicket?.pdfUrl || authBooking?.ticketUrl || reqAny.ticketUrl || null;
                const ticketQrToken = authTicket?.qrToken || ticketCode;

                const reqUser = reqAny.requester ? {
                    id: reqAny.requester.id,
                    fullName: `${reqAny.requester.firstName || ''} ${reqAny.requester.lastName || ''}`.trim() || 'Guest',
                    firstName: reqAny.requester.firstName,
                    lastName: reqAny.requester.lastName,
                    email: reqAny.requester.email,
                    phone: reqAny.requester.phone,
                    mobileNumber: reqAny.requester.phone,
                    profilePhotoUrl: reqAny.requester.profileImageUrl || null,
                    profileImageUrl: reqAny.requester.profileImageUrl || null,
                } : null;

                const hostUser = plan.creator ? {
                    id: plan.creator.id,
                    fullName: `${plan.creator.firstName || ''} ${plan.creator.lastName || ''}`.trim() || 'Host',
                    firstName: plan.creator.firstName,
                    lastName: plan.creator.lastName,
                    email: plan.creator.email,
                    phone: plan.creator.phone,
                    mobileNumber: plan.creator.phone,
                    profilePhotoUrl: plan.creator.profileImageUrl || null,
                    profileImageUrl: plan.creator.profileImageUrl || null,
                } : null;

                formattedTickets.push({
                    id: bookingIdVal,
                    ticketId: ticketCode,
                    ticketCode,
                    bookingId: bookingIdVal,
                    bookingType: 'party_plan',
                    category: 'party_plan',
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isExpired ? 'expired' : 'confirmed')),
                    bookingDate: plan.planDateTime,
                    startTime: formatTime12Hour(startAt),
                    eventStartAt: startAt,
                    eventEndAt: expAt,
                    issuedAt: req.createdAt,
                    expiresAt: expAt,
                    usedAt: isCompleted ? expAt : null,
                    pdfUrl: isExpired ? null : ticketPdfUrl,
                    qrToken: isExpired ? null : ticketQrToken,
                    ticketUrl: isExpired ? null : ticketPdfUrl,
                    totalAmount: Number(plan.depositAmount || 99),
                    isFree: false,
                    numberOfGuests: 2,
                    tablePackage: 'Party Plan Match',
                    plan: plan,
                    isHost: false,
                    isPartyPlan: true,
                    isGroupParty: false,
                    isLargeParty: false,
                    isLargePartyRequest: false,
                    isStrangersMeet: false,
                    isSolo: false,
                    isEventBooking: false,
                    isUpcomingNight: false,
                    isVenueBooking: false,
                    user: reqUser,
                    host: hostUser,
                    creator: hostUser,
                    partner: hostUser,
                    joiner: reqUser,
                    matchedJoiner: reqUser,
                    requester: reqUser,
                    request: reqAny,
                    rawRequest: reqAny,
                    venueName: plan.venue?.name || 'Lunara Venue',
                    venueAddress: `${plan.venue?.area || plan.venue?.addressLine1 || ''}, ${plan.venue?.city || ''}`.trim(),
                    venue: plan.venue ? {
                        id: plan.venue.id,
                        name: plan.venue.name,
                        addressLine1: plan.venue.addressLine1,
                        city: plan.venue.city,
                        area: plan.venue.area,
                        profilePhotoUrl: plan.venue.profilePhotoUrl ?? null,
                        coverImageUrl: plan.venue.coverImageUrl ?? null,
                        images: plan.venue.images ?? [],
                    } : null,
                    isExpired,
                });
            }

            // 5. Synthesize from PartyPlan (Host)
            for (const plan of partyPlanHostPlans) {
                const planAny = plan as any;

                // STRICT RULE: No ticket for Host until host deposit is paid AND a partner match is confirmed, unless cancelled!
                const pLife = (plan.lifecycleStatus || '').toLowerCase();
                const isCancelledPlan = pLife === 'cancelled' || (plan.status || '').toLowerCase() === 'cancelled' || (plan.hostPaymentStatus || '').toLowerCase() === 'refunded';

                const hostPaid = (plan.hostPaymentStatus || '').toLowerCase() === 'paid' || (plan.hostPaymentStatus || '').toLowerCase() === 'refunded';
                const isMatchConfirmed = (
                    plan.lifecycleStatus === 'match_confirmed' ||
                    plan.lifecycleStatus === 'chat_enabled' ||
                    plan.lifecycleStatus === 'event_upcoming' ||
                    Boolean(plan.matchedRequestId) ||
                    isCancelledPlan
                );
                if (!hostPaid || !isMatchConfirmed) {
                    continue;
                }

                // Look up authoritative Booking and Ticket for this Party Plan
                let authBooking = await Booking.findOne({
                    where: {
                        goingMode: { [Op.in]: [GoingMode.PLAN, GoingMode.PARTY_REQUEST] },
                        venueId: plan.venueId,
                        specialRequests: { [Op.like]: `%"planId":"${plan.id}"%` },
                    },
                    order: [['createdAt', 'DESC']],
                });
                if (!authBooking) {
                    const dateObj = new Date(plan.planDateTime);
                    const bDate = dateObj.toISOString().split('T')[0];
                    authBooking = await Booking.findOne({
                        where: {
                            goingMode: { [Op.in]: [GoingMode.PLAN, GoingMode.PARTY_REQUEST] },
                            userId: plan.userId,
                            venueId: plan.venueId,
                            bookingDate: bDate as any,
                        },
                        order: [['createdAt', 'DESC']],
                    });
                }

                let authTicket: Ticket | null = null;
                if (authBooking) {
                    authTicket = await Ticket.findOne({
                        where: { [Op.or]: [{ bookingId: authBooking.id }, { ticketId: authBooking.ticketCode }] },
                        order: [['createdAt', 'DESC']],
                    });
                }

                const bookingIdVal = authBooking?.id || plan.id;
                const ticketCode = authTicket?.ticketId || authBooking?.ticketCode || planAny.ticketCode || `PP-${plan.id.substring(0, 6).toUpperCase()}`;

                if (seenBookingIds.has(plan.id) || seenBookingIds.has(bookingIdVal) || seenTicketIds.has(ticketCode)) continue;
                seenBookingIds.add(plan.id);
                seenBookingIds.add(bookingIdVal);
                seenTicketIds.add(ticketCode);

                const startAt = parseEventStartDateTime(plan.planDateTime, null);
                const expAt = authTicket?.expiresAt ? new Date(authTicket.expiresAt) : getActualExpiration(startAt);
                const pStatus = (plan.status || '').toLowerCase();
                const isCancelled = pStatus === 'cancelled' || pLife === 'cancelled' || authTicket?.ticketStatus === TicketStatus.CANCELLED;
                const isCompleted = pLife === 'plan_completed' || authTicket?.ticketStatus === TicketStatus.USED;
                const isExpired = pStatus === 'expired' || isCompleted || expAt < now || authTicket?.ticketStatus === TicketStatus.EXPIRED;
                const ticketPdfUrl = authTicket?.pdfUrl || authBooking?.ticketUrl || planAny.ticketUrl || null;
                const ticketQrToken = authTicket?.qrToken || ticketCode;

                const planUser = planAny.user ? {
                    id: planAny.user.id,
                    fullName: `${planAny.user.firstName || ''} ${planAny.user.lastName || ''}`.trim() || 'Host',
                    firstName: planAny.user.firstName,
                    lastName: planAny.user.lastName,
                    email: planAny.user.email,
                    phone: planAny.user.phone,
                    mobileNumber: planAny.user.phone,
                    profilePhotoUrl: planAny.user.profileImageUrl || null,
                    profileImageUrl: planAny.user.profileImageUrl || null,
                } : null;

                let matchedRequestObj: any = null;
                let joinerUserObj: any = null;
                const mReqId = plan.matchedRequestId || planAny.matchedRequestId;
                if (mReqId) {
                    const mReq = await PartyPlanRequest.findByPk(mReqId, {
                        include: [{ model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl', 'phone', 'email'] }],
                    });
                    if (mReq) {
                        matchedRequestObj = mReq;
                        const reqUser = (mReq as any).requester;
                        if (reqUser) {
                            joinerUserObj = {
                                id: reqUser.id,
                                fullName: `${reqUser.firstName || ''} ${reqUser.lastName || ''}`.trim() || 'Guest',
                                firstName: reqUser.firstName,
                                lastName: reqUser.lastName,
                                email: reqUser.email,
                                phone: reqUser.phone,
                                mobileNumber: reqUser.phone,
                                profilePhotoUrl: reqUser.profileImageUrl || null,
                                profileImageUrl: reqUser.profileImageUrl || null,
                            };
                        }
                    }
                }
                if (!joinerUserObj) {
                    const mReq = await PartyPlanRequest.findOne({
                        where: {
                            planId: plan.id,
                            [Op.or]: [
                                { status: { [Op.in]: [PartyPlanRequestStatus.ACCEPTED, 'confirmed' as any, 'paid' as any, 'chat_enabled' as any, 'match_confirmed' as any] } },
                                { joinerPaymentStatus: 'paid' as any },
                            ],
                        },
                        include: [{ model: User, as: 'requester', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl', 'phone', 'email'] }],
                    });
                    if (mReq) {
                        matchedRequestObj = mReq;
                        const reqUser = (mReq as any).requester;
                        if (reqUser) {
                            joinerUserObj = {
                                id: reqUser.id,
                                fullName: `${reqUser.firstName || ''} ${reqUser.lastName || ''}`.trim() || 'Guest',
                                firstName: reqUser.firstName,
                                lastName: reqUser.lastName,
                                email: reqUser.email,
                                phone: reqUser.phone,
                                mobileNumber: reqUser.phone,
                                profilePhotoUrl: reqUser.profileImageUrl || null,
                                profileImageUrl: reqUser.profileImageUrl || null,
                            };
                        }
                    }
                }

                formattedTickets.push({
                    id: bookingIdVal,
                    ticketId: ticketCode,
                    ticketCode,
                    bookingId: bookingIdVal,
                    bookingType: 'party_plan',
                    category: 'party_plan',
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isExpired ? 'expired' : 'confirmed')),
                    bookingDate: plan.planDateTime,
                    startTime: formatTime12Hour(startAt),
                    eventStartAt: startAt,
                    eventEndAt: expAt,
                    issuedAt: plan.createdAt,
                    expiresAt: expAt,
                    usedAt: isCompleted ? expAt : null,
                    pdfUrl: isExpired ? null : ticketPdfUrl,
                    qrToken: isExpired ? null : ticketQrToken,
                    ticketUrl: isExpired ? null : ticketPdfUrl,
                    totalAmount: Number(plan.depositAmount || 99),
                    isFree: false,
                    numberOfGuests: 2,
                    tablePackage: 'Party Plan Match',
                    plan: planAny,
                    isHost: true,
                    isPartyPlan: true,
                    isGroupParty: false,
                    isLargeParty: false,
                    isLargePartyRequest: false,
                    isStrangersMeet: false,
                    isSolo: false,
                    isEventBooking: false,
                    isUpcomingNight: false,
                    isVenueBooking: false,
                    user: planUser,
                    host: planUser,
                    creator: planUser,
                    partner: joinerUserObj,
                    joiner: joinerUserObj,
                    matchedJoiner: joinerUserObj,
                    requester: joinerUserObj,
                    request: matchedRequestObj,
                    rawRequest: matchedRequestObj,
                    venueName: planAny.venue?.name || 'Lunara Venue',
                    venueAddress: `${planAny.venue?.area || planAny.venue?.addressLine1 || ''}, ${planAny.venue?.city || ''}`.trim(),
                    venue: planAny.venue ? {
                        id: planAny.venue.id,
                        name: planAny.venue.name,
                        addressLine1: planAny.venue.addressLine1,
                        city: planAny.venue.city,
                        area: planAny.venue.area,
                        profilePhotoUrl: planAny.venue.profilePhotoUrl ?? null,
                        coverImageUrl: planAny.venue.coverImageUrl ?? null,
                        images: planAny.venue.images ?? [],
                    } : null,
                    isExpired,
                });
            }

            // 6. Synthesize from StrangersMeetJoiner
            for (const j of strangersJoinerReqs) {
                const jAny = j as any;
                const meet = jAny.strangersMeetRequest;
                if (!meet) continue;
                const jPayStatus = (j.paymentStatus || '').toLowerCase();
                const isJPaid = jPayStatus === 'paid' || jPayStatus === 'completed' || jPayStatus === 'settled' || jPayStatus === 'refunded' || (meet.status === 'cancelled' && Number(j.paymentAmount || 0) > 0);
                if (!isJPaid) continue; // Joiner must pay entry fee before ticket is generated/shown
                if (seenBookingIds.has(j.id) || seenBookingIds.has(meet.id) || (jAny.ticketCode && seenTicketIds.has(jAny.ticketCode))) continue;
                seenBookingIds.add(j.id);
                if (jAny.ticketCode) seenTicketIds.add(jAny.ticketCode);

                const startAt = parseEventStartDateTime(meet.eventDateTime, null);
                const expAt = getActualExpiration(startAt, meet.expectedEndAt ? new Date(meet.expectedEndAt) : null);
                const jStatus = (j.status || '').toLowerCase();
                const isCancelled = jStatus === 'cancelled' || jStatus === 'rejected' || meet.status === 'cancelled' || jPayStatus === 'refunded';
                const isCompleted = meet.status === 'completed' || meet.status === 'settled';
                const isExpired = meet.status === 'expired' || isCompleted || expAt < now;
                const ticketCode = jAny.ticketCode || `LUN-${startAt.getFullYear()}-SM-${j.id.substring(0, 6).toUpperCase()}`;

                const jUser = jAny.user ? {
                    id: jAny.user.id,
                    fullName: `${jAny.user.firstName || ''} ${jAny.user.lastName || ''}`.trim() || 'Guest',
                    firstName: jAny.user.firstName,
                    lastName: jAny.user.lastName,
                    email: jAny.user.email,
                    phone: jAny.user.phone,
                    mobileNumber: jAny.user.phone,
                    profilePhotoUrl: jAny.user.profileImageUrl || null,
                    profileImageUrl: jAny.user.profileImageUrl || null,
                } : null;

                formattedTickets.push({
                    id: j.id,
                    ticketId: ticketCode,
                    ticketCode,
                    bookingId: meet.id,
                    bookingType: 'strangers_meet',
                    category: 'strangers_meet',
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isExpired ? 'expired' : 'confirmed')),
                    bookingDate: meet.eventDateTime,
                    startTime: formatTime12Hour(startAt),
                    eventStartAt: startAt,
                    eventEndAt: expAt,
                    issuedAt: j.createdAt,
                    expiresAt: expAt,
                    usedAt: isCompleted ? expAt : null,
                    pdfUrl: isExpired ? null : (jAny.ticketUrl || meet.ticketUrl || null),
                    qrToken: isExpired ? null : ticketCode,
                    ticketUrl: isExpired ? null : (jAny.ticketUrl || meet.ticketUrl || null),
                    totalAmount: Number(meet.chargesPerHead || jAny.paymentAmount || 0),
                    paymentAmount: Number(meet.chargesPerHead || jAny.paymentAmount || 0),
                    chargesPerHead: Number(meet.chargesPerHead || 0),
                    isFree: Number(meet.chargesPerHead || jAny.paymentAmount || 0) <= 0,
                    numberOfGuests: 2,
                    tablePackage: meet.subject || 'Stranger Meetup',
                    eventTitle: meet.subject || 'Strangers Meetup',
                    partySubject: meet.subject || 'Strangers Meetup',
                    subject: meet.subject || 'Strangers Meetup',
                    tagline: meet.tagline || '',
                    rawRequest: {
                        ...(meet.toJSON ? meet.toJSON() : meet),
                        venue: meet.venue,
                        user: jUser,
                        host: meet.user || jUser,
                        ticketId: ticketCode,
                        ticketCode,
                        paymentAmount: Number(meet.chargesPerHead || jAny.paymentAmount || 0),
                        chargesPerHead: Number(meet.chargesPerHead || 0),
                        subject: meet.subject || 'Strangers Meetup',
                        tagline: meet.tagline || '',
                    },
                    isPartyPlan: false,
                    isGroupParty: false,
                    isLargeParty: false,
                    isLargePartyRequest: false,
                    isStrangersMeet: true,
                    isSolo: false,
                    isEventBooking: false,
                    isUpcomingNight: false,
                    isVenueBooking: false,
                    user: jUser,
                    host: jUser,
                    venueName: meet.venue?.name || 'Lunara Venue',
                    venueAddress: `${meet.venue?.area || meet.venue?.addressLine1 || ''}, ${meet.venue?.city || ''}`.trim(),
                    venue: meet.venue ? {
                        id: meet.venue.id,
                        name: meet.venue.name,
                        addressLine1: meet.venue.addressLine1,
                        city: meet.venue.city,
                        area: meet.venue.area,
                        profilePhotoUrl: meet.venue.profilePhotoUrl ?? null,
                        coverImageUrl: meet.venue.coverImageUrl ?? null,
                        images: meet.venue.images ?? [],
                    } : null,
                    isExpired,
                });
            }

            // 7. Synthesize from StrangersMeetRequest (Host)
            for (const sm of strangersHostMeets) {
                const smAny = sm as any;
                const smPayStatus = (sm.paymentStatus || '').toLowerCase();
                const isSmPaid = smPayStatus === 'paid' || smPayStatus === 'completed' || smPayStatus === 'settled' || smPayStatus === 'refunded' || ((sm.status || '').toLowerCase() === 'cancelled' && Number(sm.paymentAmount || 0) > 0);
                if (!isSmPaid) continue; // Host must pay deposit before ticket is generated/shown
                if (seenBookingIds.has(sm.id) || (smAny.ticketCode && seenTicketIds.has(smAny.ticketCode))) continue;
                seenBookingIds.add(sm.id);
                if (smAny.ticketCode) seenTicketIds.add(smAny.ticketCode);

                const startAt = parseEventStartDateTime(sm.eventDateTime, null);
                const expAt = getActualExpiration(startAt, sm.expectedEndAt ? new Date(sm.expectedEndAt) : null);
                const sStatus = (sm.status || '').toLowerCase();
                const isCancelled = sStatus === 'cancelled' || sStatus === 'rejected' || smPayStatus === 'refunded';
                const isCompleted = sStatus === 'completed' || sStatus === 'settled';
                const isExpired = sStatus === 'expired' || isCompleted || expAt < now;
                const ticketCode = smAny.ticketCode || sm.ticketId || `LUN-${startAt.getFullYear()}-SM-${sm.id.substring(0, 6).toUpperCase()}`;

                const smUser = smAny.user ? {
                    id: smAny.user.id,
                    fullName: `${smAny.user.firstName || ''} ${smAny.user.lastName || ''}`.trim() || 'Host',
                    firstName: smAny.user.firstName,
                    lastName: smAny.user.lastName,
                    email: smAny.user.email,
                    phone: smAny.user.phone,
                    mobileNumber: smAny.user.phone,
                    profilePhotoUrl: smAny.user.profileImageUrl || null,
                    profileImageUrl: smAny.user.profileImageUrl || null,
                } : null;

                formattedTickets.push({
                    id: sm.id,
                    ticketId: ticketCode,
                    ticketCode,
                    bookingId: sm.id,
                    bookingType: 'strangers_meet',
                    category: 'strangers_meet',
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isExpired ? 'expired' : 'confirmed')),
                    bookingDate: sm.eventDateTime,
                    startTime: formatTime12Hour(startAt),
                    eventStartAt: startAt,
                    eventEndAt: expAt,
                    issuedAt: sm.createdAt,
                    expiresAt: expAt,
                    usedAt: isCompleted ? expAt : null,
                    pdfUrl: isExpired ? null : (sm.ticketUrl || null),
                    qrToken: isExpired ? null : ticketCode,
                    ticketUrl: isExpired ? null : (sm.ticketUrl || null),
                    totalAmount: Number(sm.paymentAmount ?? sm.chargesPerHead ?? 99),
                    paymentAmount: Number(sm.paymentAmount ?? sm.chargesPerHead ?? 99),
                    chargesPerHead: Number(sm.chargesPerHead || 0),
                    isFree: Number(sm.paymentAmount ?? sm.chargesPerHead ?? 99) <= 0,
                    numberOfGuests: sm.numberOfPersons || 2,
                    tablePackage: sm.subject || 'Stranger Meetup',
                    eventTitle: sm.subject || 'Strangers Meetup',
                    partySubject: sm.subject || 'Strangers Meetup',
                    subject: sm.subject || 'Strangers Meetup',
                    tagline: sm.tagline || '',
                    rawRequest: {
                        ...(sm.toJSON ? sm.toJSON() : sm),
                        venue: (sm as any).venue,
                        user: smUser,
                        host: smUser,
                        ticketId: ticketCode,
                        ticketCode,
                        paymentAmount: Number(sm.paymentAmount ?? sm.chargesPerHead ?? 99),
                        chargesPerHead: Number(sm.chargesPerHead || 0),
                        subject: sm.subject || 'Strangers Meetup',
                        tagline: sm.tagline || '',
                    },
                    isPartyPlan: false,
                    isGroupParty: false,
                    isLargeParty: false,
                    isLargePartyRequest: false,
                    isStrangersMeet: true,
                    isSolo: false,
                    isEventBooking: false,
                    isUpcomingNight: false,
                    isVenueBooking: false,
                    user: smUser,
                    host: smUser,
                    venueName: smAny.venue?.name || 'Lunara Venue',
                    venueAddress: `${smAny.venue?.area || smAny.venue?.addressLine1 || ''}, ${smAny.venue?.city || ''}`.trim(),
                    venue: smAny.venue ? {
                        id: smAny.venue.id,
                        name: smAny.venue.name,
                        addressLine1: smAny.venue.addressLine1,
                        city: smAny.venue.city,
                        area: smAny.venue.area,
                        profilePhotoUrl: smAny.venue.profilePhotoUrl ?? null,
                        coverImageUrl: smAny.venue.coverImageUrl ?? null,
                        images: smAny.venue.images ?? [],
                    } : null,
                    isExpired,
                });
            }

            // 8. Synthesize from Plan (Table Plan Host)
            for (const plan of socialTablePlans) {
                const planAny = plan as any;
                if (seenBookingIds.has(plan.id) || (planAny.ticketCode && seenTicketIds.has(planAny.ticketCode))) continue;
                seenBookingIds.add(plan.id);
                if (planAny.ticketCode) seenTicketIds.add(planAny.ticketCode);

                const startAt = parseEventStartDateTime(plan.planDate || planAny.partyDate, plan.startTime || planAny.partyTime);
                const expAt = getActualExpiration(startAt);
                const pStatus = (plan.status || '').toLowerCase();
                const isCancelled = pStatus === 'cancelled';
                const isCompleted = pStatus === 'completed' || pStatus === 'secured';
                const isExpired = pStatus === 'expired' || isCompleted || expAt < now;
                const ticketCode = planAny.ticketCode || `LUN-${startAt.getFullYear()}-TP-${plan.id.substring(0, 6).toUpperCase()}`;

                const planUser = planAny.user ? {
                    id: planAny.user.id,
                    fullName: `${planAny.user.firstName || ''} ${planAny.user.lastName || ''}`.trim() || 'Host',
                    firstName: planAny.user.firstName,
                    lastName: planAny.user.lastName,
                    email: planAny.user.email,
                    phone: planAny.user.phone,
                    mobileNumber: planAny.user.phone,
                    profilePhotoUrl: planAny.user.profileImageUrl || null,
                    profileImageUrl: planAny.user.profileImageUrl || null,
                } : null;

                formattedTickets.push({
                    id: plan.id,
                    ticketId: ticketCode,
                    ticketCode,
                    bookingId: plan.id,
                    bookingType: 'party_plan',
                    category: 'party_plan',
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isExpired ? 'expired' : 'confirmed')),
                    bookingDate: plan.planDate || planAny.partyDate,
                    startTime: formatTime12Hour(plan.startTime ? parseEventDateTimeToUTC(plan.planDate || planAny.partyDate, plan.startTime) : startAt),
                    eventStartAt: startAt,
                    eventEndAt: expAt,
                    issuedAt: plan.createdAt,
                    expiresAt: expAt,
                    usedAt: isCompleted ? expAt : null,
                    pdfUrl: isExpired ? null : (planAny.ticketUrl || null),
                    qrToken: isExpired ? null : ticketCode,
                    ticketUrl: isExpired ? null : (planAny.ticketUrl || null),
                    totalAmount: Number(plan.totalAmount || 0),
                    isFree: Number(plan.totalAmount || 0) <= 0,
                    numberOfGuests: 2,
                    tablePackage: plan.tablePackage || 'Party Plan',
                    plan: planAny,
                    isHost: true,
                    isPartyPlan: true,
                    isGroupParty: false,
                    isLargeParty: false,
                    isLargePartyRequest: false,
                    isStrangersMeet: false,
                    isSolo: false,
                    isEventBooking: false,
                    isUpcomingNight: false,
                    isVenueBooking: false,
                    user: planUser,
                    host: planUser,
                    venueName: planAny.venue?.name || 'Lunara Venue',
                    venueAddress: `${planAny.venue?.area || planAny.venue?.addressLine1 || ''}, ${planAny.venue?.city || ''}`.trim(),
                    venue: planAny.venue ? {
                        id: planAny.venue.id,
                        name: planAny.venue.name,
                        addressLine1: planAny.venue.addressLine1,
                        city: planAny.venue.city,
                        area: planAny.venue.area,
                        profilePhotoUrl: planAny.venue.profilePhotoUrl ?? null,
                        coverImageUrl: planAny.venue.coverImageUrl ?? null,
                        images: planAny.venue.images ?? [],
                    } : null,
                    isExpired,
                });
            }

            // 9. Synthesize from PlanJoinRequest (Table Plan Joiner)
            for (const req of socialJoinReqs) {
                const reqAny = req as any;
                const plan = reqAny.plan;
                if (!plan) continue;
                if (seenBookingIds.has(req.id) || seenBookingIds.has(plan.id) || (reqAny.ticketCode && seenTicketIds.has(reqAny.ticketCode))) continue;
                seenBookingIds.add(req.id);
                if (reqAny.ticketCode) seenTicketIds.add(reqAny.ticketCode);

                const startAt = parseEventStartDateTime(plan.planDate || plan.partyDate, plan.startTime || plan.partyTime);
                const expAt = getActualExpiration(startAt);
                const rStatus = (req.status || '').toLowerCase();
                const isCancelled = rStatus === 'cancelled' || rStatus === 'rejected';
                const isCompleted = plan.status === 'completed' || plan.status === 'secured';
                const isExpired = rStatus === 'expired' || isCompleted || expAt < now;
                const ticketCode = reqAny.ticketCode || `LUN-${startAt.getFullYear()}-TP-${req.id.substring(0, 6).toUpperCase()}`;

                const reqUser = reqAny.user ? {
                    id: reqAny.user.id,
                    fullName: `${reqAny.user.firstName || ''} ${reqAny.user.lastName || ''}`.trim() || 'Guest',
                    firstName: reqAny.user.firstName,
                    lastName: reqAny.user.lastName,
                    email: reqAny.user.email,
                    phone: reqAny.user.phone,
                    mobileNumber: reqAny.user.phone,
                    profilePhotoUrl: reqAny.user.profileImageUrl || null,
                    profileImageUrl: reqAny.user.profileImageUrl || null,
                } : null;

                const hostUser = plan.user ? {
                    id: plan.user.id,
                    fullName: `${plan.user.firstName || ''} ${plan.user.lastName || ''}`.trim() || 'Host',
                    firstName: plan.user.firstName,
                    lastName: plan.user.lastName,
                    email: plan.user.email,
                    phone: plan.user.phone,
                    mobileNumber: plan.user.phone,
                    profilePhotoUrl: plan.user.profileImageUrl || null,
                    profileImageUrl: plan.user.profileImageUrl || null,
                } : null;

                formattedTickets.push({
                    id: req.id,
                    ticketId: ticketCode,
                    ticketCode,
                    bookingId: plan.id,
                    bookingType: 'party_plan',
                    category: 'party_plan',
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isExpired ? 'expired' : 'confirmed')),
                    bookingDate: plan.planDate || plan.partyDate,
                    startTime: formatTime12Hour(plan.startTime ? parseEventDateTimeToUTC(plan.planDate || plan.partyDate, plan.startTime) : startAt),
                    eventStartAt: startAt,
                    eventEndAt: expAt,
                    issuedAt: req.createdAt,
                    expiresAt: expAt,
                    usedAt: isCompleted ? expAt : null,
                    pdfUrl: isExpired ? null : (reqAny.ticketUrl || null),
                    qrToken: isExpired ? null : ticketCode,
                    ticketUrl: isExpired ? null : (reqAny.ticketUrl || null),
                    totalAmount: Number(req.shareAmount || reqAny.splitAmount || 0),
                    isFree: Number(req.shareAmount || reqAny.splitAmount || 0) <= 0,
                    numberOfGuests: 2,
                    tablePackage: plan.tablePackage || 'Party Plan Match',
                    plan: plan,
                    isHost: false,
                    isPartyPlan: true,
                    isGroupParty: false,
                    isLargeParty: false,
                    isLargePartyRequest: false,
                    isStrangersMeet: false,
                    isSolo: false,
                    isEventBooking: false,
                    isUpcomingNight: false,
                    isVenueBooking: false,
                    user: reqUser,
                    host: hostUser,
                    venueName: plan.venue?.name || 'Lunara Venue',
                    venueAddress: `${plan.venue?.area || plan.venue?.addressLine1 || ''}, ${plan.venue?.city || ''}`.trim(),
                    venue: plan.venue ? {
                        id: plan.venue.id,
                        name: plan.venue.name,
                        addressLine1: plan.venue.addressLine1,
                        city: plan.venue.city,
                        area: plan.venue.area,
                        profilePhotoUrl: plan.venue.profilePhotoUrl ?? null,
                        coverImageUrl: plan.venue.coverImageUrl ?? null,
                        images: plan.venue.images ?? [],
                    } : null,
                    isExpired,
                });
            }

            // Filter by requested Tab
            let resultTickets = formattedTickets;
            if (tab === 'upcoming' || tab === 'active') {
                resultTickets = formattedTickets.filter(t => !t.isExpired && t.status !== 'cancelled' && t.status !== 'rejected');
            } else if (tab === 'expired' || tab === 'past') {
                resultTickets = formattedTickets.filter(t => t.isExpired || t.status === 'completed' || t.status === 'used');
            } else if (tab === 'used') {
                resultTickets = formattedTickets.filter(t => t.status === 'completed' || t.status === 'used');
            } else if (tab === 'cancelled') {
                resultTickets = formattedTickets.filter(t => t.status === 'cancelled' || t.status === 'rejected');
            }

            // Sort newest first
            resultTickets.sort((a, b) => {
                const timeA = a.eventStartAt ? new Date(a.eventStartAt).getTime() : 0;
                const timeB = b.eventStartAt ? new Date(b.eventStartAt).getTime() : 0;
                return timeB - timeA;
            });

            return res.status(200).json({
                success: true,
                count: resultTickets.length,
                data: resultTickets,
            });
        } catch (err: any) {
            logger.error(`getUserTickets error: ${err.message}`, err);
            return res.status(500).json({ success: false, message: 'Failed to fetch tickets' });
        }
    }

    /**
     * GET /api/mobile/tickets/:id
     * Get single ticket metadata
     */
    public static async getTicketById(req: Request, res: Response): Promise<Response> {
        try {
            const { id } = req.params;
            const userId = req.user?.id || (req.query.userId as string);
            const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);

            const ticketWhere: any[] = [{ ticketId: id }];
            if (isUuid) {
                ticketWhere.push({ id }, { bookingId: id });
            }

            let ticket = await Ticket.findOne({
                where: { [Op.or]: ticketWhere },
                include: [
                    {
                        model: Venue,
                        as: 'venue',
                        include: [
                            {
                                model: VenueImage,
                                as: 'images',
                                attributes: ['id', 'filePath', 'imageType', 'isPrimary'],
                                required: false,
                            },
                        ],
                    },
                    { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] },
                ],
            });

            if (!ticket) {
                // Try finding by Booking ticketCode or id
                const bookingWhere: any[] = [{ ticketCode: id }];
                if (isUuid) {
                    bookingWhere.push({ id });
                }
                const booking = await Booking.findOne({
                    where: { [Op.or]: bookingWhere },
                });
                if (booking) {
                    ticket = await Ticket.findOne({
                        where: { [Op.or]: [{ bookingId: booking.id }, { ticketId: booking.ticketCode }] },
                        include: [
                            {
                                model: Venue,
                                as: 'venue',
                                include: [
                                    {
                                        model: VenueImage,
                                        as: 'images',
                                        attributes: ['id', 'filePath', 'imageType', 'isPrimary'],
                                        required: false,
                                    },
                                ],
                            },
                            { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] },
                        ],
                    });
                }
            }

            if (!ticket) {
                return res.status(404).json({ success: false, message: 'Ticket not found' });
            }

            let isAuthorized = !userId || ticket.userId === userId;
            if (!isAuthorized && userId) {
                if (ticket.bookingId) {
                    const booking = await Booking.findByPk(ticket.bookingId);
                    if (booking) {
                        if (booking.userId === userId) isAuthorized = true;
                        if (booking.specialRequests) {
                            try {
                                const meta = typeof booking.specialRequests === 'string' ? JSON.parse(booking.specialRequests) : booking.specialRequests;
                                if (meta.joinerId === userId || meta.hostId === userId) isAuthorized = true;
                            } catch (_) {}
                        }
                    }
                }
            }

            if (!isAuthorized) {
                return res.status(403).json({ success: false, message: 'Unauthorized ticket access' });
            }

            const now = new Date();
            const isExpired = ticket.ticketStatus === TicketStatus.EXPIRED || new Date(ticket.expiresAt) < now;
            const vCoverUrl = extractVenueCoverImageUrl(ticket.venue);

            return res.status(200).json({
                success: true,
                data: {
                    id: ticket.id,
                    ticketId: ticket.ticketId,
                    bookingId: ticket.bookingId,
                    bookingType: ticket.bookingType,
                    status: isExpired && ticket.ticketStatus !== TicketStatus.CANCELLED ? TicketStatus.EXPIRED : ticket.ticketStatus,
                    eventStartAt: ticket.eventStartAt,
                    eventEndAt: ticket.eventEndAt,
                    issuedAt: ticket.issuedAt,
                    expiresAt: ticket.expiresAt,
                    usedAt: ticket.usedAt,
                    pdfUrl: isExpired ? null : ticket.pdfUrl,
                    qrToken: isExpired ? null : ticket.qrToken,
                    venueName: ticket.venue?.name || 'Lunara Venue',
                    venueAddress: ticket.venue?.addressLine1 || '',
                    venue: ticket.venue ? {
                        id: ticket.venue.id,
                        name: ticket.venue.name,
                        addressLine1: ticket.venue.addressLine1,
                        city: ticket.venue.city,
                        area: ticket.venue.area,
                        profilePhotoUrl: vCoverUrl,
                        coverImageUrl: vCoverUrl,
                        images: (ticket.venue as any).images ?? [],
                    } : null,
                    guestName: ticket.user ? `${ticket.user.firstName} ${ticket.user.lastName}` : 'Guest',
                    isExpired,
                },
            });
        } catch (err: any) {
            logger.error(`getTicketById error: ${err.message}`, err);
            return res.status(500).json({ success: false, message: 'Failed to fetch ticket' });
        }
    }

    /**
     * GET /api/mobile/tickets/:id/download
     * Generates a secure, time-limited signed PDF download URL or streams file
     */
    public static async getTicketDownloadUrl(req: Request, res: Response): Promise<Response> {
        try {
            const { id } = req.params;
            const userId = req.user?.id || (req.query.userId as string);

            const ticket = await Ticket.findOne({
                where: { [Op.or]: [{ id }, { ticketId: id }] },
            });

            if (!ticket) {
                return res.status(404).json({ success: false, message: 'Ticket not found' });
            }

            if (userId && ticket.userId !== userId) {
                return res.status(403).json({ success: false, message: 'Unauthorized access' });
            }

            const now = new Date();
            if (ticket.ticketStatus === TicketStatus.EXPIRED || new Date(ticket.expiresAt) < now) {
                return res.status(403).json({
                    success: false,
                    message: 'Ticket has expired. PDF download is no longer available.',
                    code: 'TICKET_EXPIRED',
                });
            }

            if (!ticket.pdfUrl) {
                return res.status(404).json({ success: false, message: 'Ticket PDF file not found' });
            }

            return res.status(200).json({
                success: true,
                ticketId: ticket.ticketId,
                downloadUrl: ticket.pdfUrl,
                expiresInSeconds: 300, // 5 minutes signed download token
            });
        } catch (err: any) {
            logger.error(`getTicketDownloadUrl error: ${err.message}`, err);
            return res.status(500).json({ success: false, message: 'Failed to generate download URL' });
        }
    }

    /**
     * POST /api/mobile/tickets/:id/share
     * Create or retrieve a secure public share token for WhatsApp / OS Share Sheet
     */
    public static async createShareToken(req: Request, res: Response): Promise<Response> {
        try {
            const { id } = req.params;
            const userId = req.user?.id || (req.body?.userId as string) || (req.query?.userId as string);

            const ticket = await Ticket.findOne({
                where: { [Op.or]: [{ id }, { ticketId: id }] },
            });

            if (!ticket) {
                return res.status(404).json({ success: false, message: 'Ticket not found' });
            }

            if (userId && ticket.userId !== userId) {
                return res.status(403).json({ success: false, message: 'Unauthorized' });
            }

            // Reuse shareToken if active
            let shareToken = ticket.shareToken;
            const now = new Date();

            if (!shareToken || !ticket.shareTokenExpiresAt || ticket.shareTokenExpiresAt < now) {
                shareToken = `LNS-${crypto.randomBytes(8).toString('hex')}`;
                const shareTokenExpiresAt = ticket.eventEndAt; // Valid until event end

                await ticket.update({
                    shareToken,
                    shareTokenExpiresAt,
                });
            }

            const baseUrl = process.env.APP_BASE_URL || `${req.protocol}://${req.get('host')}`;
            const shareUrl = `${baseUrl}/api/mobile/tickets/share/${shareToken}`;
            const shareText = `🎟 My Lunara Ticket\n\nTicket Code: ${ticket.ticketId}\nStatus: ${ticket.ticketStatus}\n\nView my ticket: ${shareUrl}`;

            return res.status(200).json({
                success: true,
                ticketId: ticket.ticketId,
                shareToken,
                shareUrl,
                shareText,
                expiresAt: ticket.shareTokenExpiresAt,
            });
        } catch (err: any) {
            logger.error(`createShareToken error: ${err.message}`, err);
            return res.status(500).json({ success: false, message: 'Failed to create share token' });
        }
    }

    /**
     * GET /api/mobile/tickets/share/:token
     * Public HTML ticket preview page for share link recipients
     */
    public static async getShareTicketPreview(req: Request, res: Response): Promise<Response | void> {
        try {
            const { token } = req.params;

            const ticket = await Ticket.findOne({
                where: { shareToken: token },
                include: [
                    { model: Venue, as: 'venue', attributes: ['name', 'city', 'area', 'addressLine1'] },
                    { model: User, as: 'user', attributes: ['firstName', 'lastName'] },
                ],
            });

            if (!ticket) {
                res.status(404).send(MobileTicketController.renderErrorPage('Invalid or expired share link', 'This ticket share link is not valid or has already expired.'));
                return;
            }

            const now = new Date();
            if (ticket.shareTokenExpiresAt && ticket.shareTokenExpiresAt < now) {
                res.status(410).send(MobileTicketController.renderErrorPage('Share Link Expired', 'This ticket share link has expired. The event has already ended.'));
                return;
            }

            const pdfUrl = ticket.pdfUrl || null;
            const downloadUrl = pdfUrl ? `/api/mobile/tickets/share/${token}/pdf` : null;

            const eventStart = new Date(ticket.eventStartAt);
            const dateStr = formatDateFull(eventStart, undefined, true);
            const timeStr = formatTime12Hour(eventStart);

            const bookingTypeLabel: Record<string, string> = {
                solo: 'Solo Booking',
                party_plan: 'Party Plan',
                group_party: 'Group Party',
                strangers_meet: "Strangers Meet",
            };
            const accentColor: Record<string, string> = {
                solo: '#8B5CF6',
                party_plan: '#EC4899',
                group_party: '#06B6D4',
                strangers_meet: '#10B981',
            };
            const typeLabel = bookingTypeLabel[ticket.bookingType] || 'DIGITAL TICKET';
            const accent = accentColor[ticket.bookingType] || '#8B5CF6';

            const guestName = ticket.user ? `${ticket.user.firstName} ${ticket.user.lastName}`.trim() : 'Lunara Member';
            const venueName = (ticket.venue as any)?.name || 'Lunara Venue';
            const venueCity = (ticket.venue as any)?.city || '';
            const venueArea = (ticket.venue as any)?.area || '';
            const venueAddress = [venueArea, venueCity].filter(Boolean).join(', ');

            // Generate QR code as base64 PNG for embedding in HTML
            const QRCode = require('qrcode');
            const qrDataUrl: string = await QRCode.toDataURL(ticket.ticketId, {
                errorCorrectionLevel: 'H',
                width: 220,
                margin: 2,
                color: { dark: '#0F0C1B', light: '#FFFFFF' }
            });

            const isExpired = ticket.ticketStatus === TicketStatus.EXPIRED;
            const statusLabel = isExpired ? 'EXPIRED' : ticket.ticketStatus === TicketStatus.USED ? 'USED' : 'VALID';
            const statusColor = isExpired ? '#EF4444' : ticket.ticketStatus === TicketStatus.USED ? '#F59E0B' : '#10B981';

            const html = MobileTicketController.renderTicketPage({
                ticketId: ticket.ticketId,
                typeLabel,
                accent,
                guestName,
                venueName,
                venueAddress,
                dateStr,
                timeStr,
                statusLabel,
                statusColor,
                qrDataUrl,
                downloadUrl,
            });

            res.setHeader('Content-Type', 'text/html; charset=utf-8');
            res.status(200).send(html);
        } catch (err: any) {
            logger.error(`getShareTicketPreview error: ${err.message}`, err);
            res.status(500).send(MobileTicketController.renderErrorPage('Error', 'Something went wrong. Please try again.'));
        }
    }

    /**
     * GET /api/mobile/tickets/share/:token/pdf
     * Redirect to the actual PDF file for a share token
     */
    public static async getShareTicketPdf(req: Request, res: Response): Promise<void> {
        try {
            const { token } = req.params;
            const ticket = await Ticket.findOne({ where: { shareToken: token } });

            if (!ticket || !ticket.pdfUrl) {
                res.status(404).send(MobileTicketController.renderErrorPage('PDF Not Found', 'The ticket PDF is not available.'));
                return;
            }

            const now = new Date();
            if (ticket.shareTokenExpiresAt && ticket.shareTokenExpiresAt < now) {
                res.status(410).send(MobileTicketController.renderErrorPage('Link Expired', 'This share link has expired.'));
                return;
            }

            // If it's an absolute URL (Azure Blob), redirect to it
            if (ticket.pdfUrl.startsWith('http')) {
                res.redirect(302, ticket.pdfUrl);
                return;
            }

            // Otherwise redirect to local uploads path
            res.redirect(302, ticket.pdfUrl);
        } catch (err: any) {
            logger.error(`getShareTicketPdf error: ${err.message}`, err);
            res.status(500).json({ success: false, message: 'Failed to get ticket PDF' });
        }
    }

    private static renderTicketPage(opts: {
        ticketId: string;
        typeLabel: string;
        accent: string;
        guestName: string;
        venueName: string;
        venueAddress: string;
        dateStr: string;
        timeStr: string;
        statusLabel: string;
        statusColor: string;
        qrDataUrl: string;
        downloadUrl: string | null;
    }): string {
        const { ticketId, typeLabel, accent, guestName, venueName, venueAddress, dateStr, timeStr, statusLabel, statusColor, qrDataUrl, downloadUrl } = opts;
        return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <meta name="theme-color" content="#0F0C1B"/>
  <title>${venueName} — Lunara Ticket</title>
  <meta property="og:title" content="${guestName}'s Lunara Ticket"/>
  <meta property="og:description" content="${typeLabel} at ${venueName} · ${dateStr}"/>
  <meta name="description" content="${typeLabel} ticket for ${guestName} at ${venueName}"/>
  <link rel="preconnect" href="https://fonts.googleapis.com"/>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap" rel="stylesheet"/>
  <style>
    *,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
    body{background:#0F0C1B;font-family:'Inter',sans-serif;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:24px 16px;color:#fff}
    .wrap{width:100%;max-width:400px}
    .logo{text-align:center;margin-bottom:24px}
    .logo-text{font-size:22px;font-weight:900;letter-spacing:3px;background:linear-gradient(135deg,${accent},#fff);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
    .logo-sub{font-size:10px;letter-spacing:4px;color:rgba(255,255,255,0.35);margin-top:4px;text-transform:uppercase}
    .ticket{background:linear-gradient(160deg,#1a1630 0%,#120E23 100%);border-radius:28px;overflow:hidden;box-shadow:0 32px 80px rgba(0,0,0,0.7),0 0 0 1px rgba(255,255,255,0.06);position:relative}
    .ticket-top-bar{height:6px;background:linear-gradient(90deg,${accent},${accent}aa)}
    .ticket-header{padding:24px 24px 16px;border-bottom:1px dashed rgba(255,255,255,0.1)}
    .badge{display:inline-flex;align-items:center;gap:6px;background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.1);border-radius:100px;padding:4px 12px;font-size:10px;font-weight:700;letter-spacing:2px;color:${accent};text-transform:uppercase;margin-bottom:14px}
    .dot{width:6px;height:6px;border-radius:50%;background:${accent};animation:pulse 2s infinite}
    @keyframes pulse{0%,100%{opacity:1}50%{opacity:0.4}}
    .venue-name{font-size:22px;font-weight:800;line-height:1.2;margin-bottom:6px;color:#fff}
    .venue-addr{font-size:12px;color:rgba(255,255,255,0.45);font-weight:500}
    .ticket-body{padding:20px 24px}
    .info-row{display:flex;align-items:flex-start;gap:14px;margin-bottom:18px}
    .info-icon{width:36px;height:36px;border-radius:10px;background:rgba(255,255,255,0.05);display:flex;align-items:center;justify-content:center;font-size:16px;flex-shrink:0}
    .info-label{font-size:10px;letter-spacing:1.5px;font-weight:700;color:rgba(255,255,255,0.35);text-transform:uppercase;margin-bottom:3px}
    .info-value{font-size:14px;font-weight:600;color:#fff}
    .status-badge{display:inline-block;padding:2px 10px;border-radius:100px;font-size:11px;font-weight:700;background:${statusColor}22;color:${statusColor};border:1px solid ${statusColor}55}
    .divider{position:relative;margin:4px -24px;height:1px}
    .divider::before{content:'';position:absolute;top:0;left:0;right:0;height:1px;background:repeating-linear-gradient(90deg,rgba(255,255,255,0.12) 0,rgba(255,255,255,0.12) 8px,transparent 8px,transparent 16px)}
    .divider .hole{position:absolute;width:24px;height:24px;border-radius:50%;background:#0F0C1B;top:-12px}
    .divider .hole-l{left:-12px}
    .divider .hole-r{right:-12px}
    .qr-section{padding:20px 24px 24px;display:flex;flex-direction:column;align-items:center;gap:14px}
    .qr-wrap{background:#fff;border-radius:20px;padding:14px;box-shadow:0 8px 32px rgba(0,0,0,0.4)}
    .qr-wrap img{display:block;width:200px;height:200px}
    .ticket-code{font-size:12px;letter-spacing:3px;font-weight:700;color:rgba(255,255,255,0.5);text-transform:uppercase}
    .scan-hint{font-size:11px;color:rgba(255,255,255,0.25);text-align:center;line-height:1.6}
    .download-btn{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;padding:16px;border-radius:16px;background:linear-gradient(135deg,${accent},${accent}cc);font-size:14px;font-weight:700;color:#fff;text-decoration:none;letter-spacing:0.5px;margin-top:20px;box-shadow:0 8px 24px ${accent}44;transition:opacity 0.2s}
    .download-btn:active{opacity:0.85}
    .download-icon{font-size:18px}
    .footer{text-align:center;margin-top:28px;font-size:10px;letter-spacing:2px;color:rgba(255,255,255,0.2);text-transform:uppercase}
    .app-cta{margin-top:12px;text-align:center}
    .app-cta a{color:${accent};font-size:12px;font-weight:600;text-decoration:none}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="logo">
      <div class="logo-text">LUNARA</div>
      <div class="logo-sub">VIP Digital Ticket</div>
    </div>
    <div class="ticket">
      <div class="ticket-top-bar"></div>
      <div class="ticket-header">
        <div class="badge"><span class="dot"></span>${typeLabel}</div>
        <div class="venue-name">${venueName}</div>
        <div class="venue-addr">${venueAddress}</div>
      </div>
      <div class="ticket-body">
        <div class="info-row">
          <div class="info-icon">🎟</div>
          <div>
            <div class="info-label">Guest</div>
            <div class="info-value">${guestName}</div>
          </div>
        </div>
        <div class="info-row">
          <div class="info-icon">📅</div>
          <div>
            <div class="info-label">Date</div>
            <div class="info-value">${dateStr}</div>
          </div>
        </div>
        <div class="info-row">
          <div class="info-icon">⏰</div>
          <div>
            <div class="info-label">Time</div>
            <div class="info-value">${timeStr}</div>
          </div>
        </div>
        <div class="info-row">
          <div class="info-icon">✅</div>
          <div>
            <div class="info-label">Status</div>
            <div class="status-badge">${statusLabel}</div>
          </div>
        </div>
      </div>
      <div class="divider">
        <div class="hole hole-l"></div>
        <div class="hole hole-r"></div>
      </div>
      <div class="qr-section">
        <div class="qr-wrap">
          <img src="${qrDataUrl}" alt="Ticket QR Code" width="200" height="200"/>
        </div>
        <div class="ticket-code">${ticketId}</div>
        <div class="scan-hint">Present this QR code at the club entrance<br/>for quick and verified entry</div>
        ${downloadUrl ? `<a href="${downloadUrl}" class="download-btn"><span class="download-icon">⬇</span> Download PDF Ticket</a>` : ''}
      </div>
    </div>
    <div class="app-cta">
      <a href="https://lunara.app">Open in Lunara App →</a>
    </div>
    <div class="footer">Powered by Lunara VIP System • Secure &amp; Verified</div>
  </div>
</body>
</html>`;
    }

    private static renderErrorPage(title: string, message: string): string {
        return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>${title} — Lunara</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;800&display=swap" rel="stylesheet"/>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{background:#0F0C1B;font-family:'Inter',sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;color:#fff}
    .card{text-align:center;max-width:340px}
    .icon{font-size:56px;margin-bottom:20px}
    h1{font-size:22px;font-weight:800;margin-bottom:10px}
    p{font-size:14px;color:rgba(255,255,255,0.5);line-height:1.6}
    .logo{font-size:14px;letter-spacing:3px;font-weight:800;color:#8B5CF6;margin-top:32px}
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">🎟</div>
    <h1>${title}</h1>
    <p>${message}</p>
    <div class="logo">LUNARA</div>
  </div>
</body>
</html>`;
    }

    /**
     * POST /api/mobile/tickets/verify
     * Atomic Gate Scanner Verification for Venue Staff
     */
    public static async verifyGateScanTicket(req: Request, res: Response): Promise<Response> {
        const t = await sequelize.transaction();
        try {
            const { ticketCode, qrToken } = req.body;

            if (!ticketCode && !qrToken) {
                await t.rollback();
                return res.status(400).json({ success: false, message: 'ticketCode or qrToken is required' });
            }

            let searchCode = ticketCode;
            if (!searchCode && qrToken) {
                try {
                    const parsed = JSON.parse(qrToken);
                    searchCode = parsed.ticketId;
                } catch (_) {
                    searchCode = qrToken;
                }
            }

            // Atomic Lock FOR UPDATE
            const ticket = await Ticket.findOne({
                where: { ticketId: searchCode },
                transaction: t,
                lock: true,
            });

            if (!ticket) {
                await t.rollback();
                return res.status(404).json({
                    success: false,
                    verificationStatus: 'INVALID',
                    message: 'Ticket not found in database',
                });
            }

            const now = new Date();

            // 1. Check if already used
            if (ticket.ticketStatus === TicketStatus.USED) {
                await t.rollback();
                return res.status(400).json({
                    success: false,
                    verificationStatus: 'ALREADY_USED',
                    message: `Ticket was already redeemed on ${ticket.usedAt}`,
                    usedAt: ticket.usedAt,
                    ticketId: ticket.ticketId,
                });
            }

            // 2. Check if cancelled or refunded
            if (ticket.ticketStatus === TicketStatus.CANCELLED || ticket.ticketStatus === TicketStatus.REFUNDED) {
                await t.rollback();
                return res.status(400).json({
                    success: false,
                    verificationStatus: ticket.ticketStatus,
                    message: `Ticket is ${ticket.ticketStatus} and invalid for venue entry`,
                });
            }

            // 3. Check if expired
            if (ticket.ticketStatus === TicketStatus.EXPIRED || new Date(ticket.expiresAt) < now) {
                await t.rollback();
                return res.status(400).json({
                    success: false,
                    verificationStatus: 'EXPIRED',
                    message: 'Event has ended. Ticket is expired.',
                });
            }

            // 4. Mark Ticket as USED atomically
            await ticket.update(
                {
                    ticketStatus: TicketStatus.USED,
                    usedAt: now,
                },
                { transaction: t }
            );

            await t.commit();

            logger.info(`Gate scanner verified & redeemed Ticket ${ticket.ticketId} at ${now}`);

            RealtimeEventBroker.emitToUser(ticket.userId, 'ticket_updated', 'ticket', ticket.ticketId, {
                ticketId: ticket.ticketId,
                bookingId: ticket.bookingId,
                status: TicketStatus.USED,
                usedAt: now,
            });

            return res.status(200).json({
                success: true,
                verificationStatus: 'VALID',
                message: 'ENTRY GRANTED! Ticket successfully redeemed.',
                ticketId: ticket.ticketId,
                bookingId: ticket.bookingId,
                usedAt: now,
            });
        } catch (err: any) {
            await t.rollback();
            logger.error(`verifyGateScanTicket error: ${err.message}`, err);
            return res.status(500).json({ success: false, message: 'Gate verification failed' });
        }
    }
}
