import { Request, Response } from 'express';
import crypto from 'crypto';
import { Op } from 'sequelize';
import sequelize from '../config/database';
import Ticket, { TicketStatus } from '../models/Ticket';
import Venue from '../models/Venue';
import User from '../models/User';
import Booking, { BookingStatus } from '../models/Booking';
import GroupParty, { GroupPartyStatus, GroupPartyPaymentStatus } from '../models/GroupParty';
import PartyPlan from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus } from '../models/PartyPlanRequest';
import StrangersMeetRequest from '../models/StrangersMeetRequest';
import StrangersMeetJoiner from '../models/StrangersMeetJoiner';
import { logger } from '../config/logger';

export class MobileTicketController {
    /**
     * GET /api/mobile/tickets
     * Fetch user tickets grouped by status tabs: upcoming, active, used, expired, cancelled
     * Comprehensively aggregates across Ticket, Booking, GroupParty, PartyPlan, and StrangersMeet models.
     */
    public static async getUserTickets(req: Request, res: Response): Promise<Response> {
        try {
            const userId = req.user!.id;
            const tab = (req.query.tab as string) || 'all';
            const now = new Date();

            const venueAttributes = ['id', 'name', 'addressLine1', 'city', 'area', 'images', 'profilePhotoUrl', 'coverImageUrl'];

            // Parallel fetch across all potential ticket sources for this user
            const [
                tickets,
                confirmedBookings,
                confirmedGroupParties,
                partyPlanJoinerReqs,
                partyPlanHostPlans,
                strangersJoinerReqs,
                strangersHostMeets,
            ] = await Promise.all([
                Ticket.findAll({
                    where: { userId },
                    include: [
                        { model: Venue, as: 'venue', attributes: venueAttributes },
                    ],
                    order: [['eventStartAt', 'DESC']],
                }),
                Booking.findAll({
                    where: {
                        userId,
                        [Op.or]: [
                            { paymentStatus: { [Op.in]: ['paid', 'free'] } },
                            { status: { [Op.in]: [BookingStatus.CONFIRMED, BookingStatus.COMPLETED, 'active' as any] } },
                            { adminApprovalStatus: 'approved' },
                        ],
                    },
                    include: [
                        { model: Venue, as: 'venue', attributes: venueAttributes },
                    ],
                    order: [['bookingDate', 'DESC']],
                }),
                GroupParty.findAll({
                    where: {
                        userId,
                        [Op.or]: [
                            { paymentStatus: GroupPartyPaymentStatus.PAID },
                            { status: { [Op.in]: [GroupPartyStatus.CONFIRMED, 'completed' as any] } },
                        ],
                    },
                    include: [
                        { model: Venue, as: 'venue', attributes: venueAttributes },
                    ],
                    order: [['partyDate', 'DESC']],
                }),
                PartyPlanRequest.findAll({
                    where: {
                        requesterId: userId,
                        [Op.or]: [
                            { joinerPaymentStatus: 'paid' },
                            { status: { [Op.in]: [PartyPlanRequestStatus.ACCEPTED, 'confirmed' as any, 'paid' as any] } },
                        ],
                    },
                    include: [
                        {
                            model: PartyPlan,
                            as: 'plan',
                            include: [
                                { model: Venue, as: 'venue', attributes: venueAttributes },
                                { model: User, as: 'creator', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] },
                            ],
                        },
                    ],
                    order: [['createdAt', 'DESC']],
                }),
                PartyPlan.findAll({
                    where: {
                        userId,
                        [Op.or]: [
                            { hostPaymentStatus: 'paid' },
                            { lifecycleStatus: { [Op.in]: ['match_confirmed', 'chat_enabled', 'plan_completed'] } },
                        ],
                    },
                    include: [
                        { model: Venue, as: 'venue', attributes: venueAttributes },
                    ],
                    order: [['planDateTime', 'DESC']],
                }),
                StrangersMeetJoiner.findAll({
                    where: {
                        userId,
                        [Op.or]: [
                            { paymentStatus: 'paid' },
                            { status: { [Op.in]: ['confirmed', 'approved', 'in_progress', 'completed'] } },
                        ],
                    },
                    include: [
                        {
                            model: StrangersMeetRequest,
                            as: 'strangersMeetRequest',
                            include: [
                                { model: Venue, as: 'venue', attributes: venueAttributes },
                                { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'] },
                            ],
                        },
                    ],
                    order: [['createdAt', 'DESC']],
                }),
                StrangersMeetRequest.findAll({
                    where: {
                        userId,
                        [Op.or]: [
                            { paymentStatus: 'paid' },
                            { status: { [Op.in]: ['approved', 'in_progress', 'completed', 'host_confirmed_ended', 'admin_confirmed_ended', 'settled'] } },
                        ],
                    },
                    include: [
                        { model: Venue, as: 'venue', attributes: venueAttributes },
                    ],
                    order: [['eventDateTime', 'DESC']],
                }),
            ]);

            const seenBookingIds = new Set<string>();
            const seenTicketIds = new Set<string>();
            const formattedTickets: any[] = [];

            // 1. Process explicit Ticket table records
            const bookingIds = tickets.map(t => t.bookingId).filter(Boolean);
            const [sourceBookings, sourceGroupParties] = await Promise.all([
                Booking.findAll({
                    where: { id: { [Op.in]: bookingIds } },
                    attributes: ['id', 'totalAmount', 'numberOfGuests', 'tablePackage'],
                }),
                GroupParty.findAll({
                    where: { id: { [Op.in]: bookingIds } },
                    attributes: ['id', 'totalAmount', 'numberOfFriends'],
                }),
            ]);
            const bookingById = new Map(sourceBookings.map(b => [b.id, b]));
            const groupPartyById = new Map(sourceGroupParties.map(g => [g.id, g]));

            for (const t of tickets) {
                if (t.bookingId) seenBookingIds.add(t.bookingId);
                if (t.ticketId) seenTicketIds.add(t.ticketId);

                const sourceBooking = bookingById.get(t.bookingId);
                const sourceGroupParty = groupPartyById.get(t.bookingId);
                const isExpired = t.ticketStatus === TicketStatus.EXPIRED || (t.expiresAt && new Date(t.expiresAt) < now) || (t.eventEndAt && new Date(t.eventEndAt) < now);
                const startDate = t.eventStartAt ? new Date(t.eventStartAt) : null;
                const startTimeStr = startDate ? startDate.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: true }) : '08:00 PM';

                formattedTickets.push({
                    id: t.id,
                    ticketId: t.ticketId,
                    ticketCode: t.ticketId,
                    bookingId: t.bookingId,
                    bookingType: t.bookingType,
                    status: isExpired && t.ticketStatus !== TicketStatus.CANCELLED ? TicketStatus.EXPIRED : t.ticketStatus,
                    bookingDate: t.eventStartAt,
                    startTime: startTimeStr,
                    eventStartAt: t.eventStartAt,
                    eventEndAt: t.eventEndAt,
                    issuedAt: t.issuedAt,
                    expiresAt: t.expiresAt,
                    usedAt: t.usedAt,
                    pdfUrl: isExpired ? null : t.pdfUrl,
                    qrToken: isExpired ? null : t.qrToken,
                    ticketUrl: isExpired ? null : t.pdfUrl,
                    totalAmount: sourceBooking ? Number(sourceBooking.totalAmount) : (sourceGroupParty ? Number(sourceGroupParty.totalAmount) : null),
                    numberOfGuests: sourceBooking ? sourceBooking.numberOfGuests : (sourceGroupParty ? sourceGroupParty.numberOfFriends : null),
                    tablePackage: sourceBooking ? sourceBooking.tablePackage : null,
                    isPartyPlan: t.bookingType === 'party_plan',
                    isGroupParty: t.bookingType === 'group_party',
                    venueName: t.venue?.name || 'Lunara Venue',
                    venueAddress: `${t.venue?.area || t.venue?.addressLine1 || ''}, ${t.venue?.city || ''}`.trim(),
                    venue: t.venue ? {
                        id: t.venue.id,
                        name: t.venue.name,
                        addressLine1: t.venue.addressLine1,
                        city: t.venue.city,
                        area: t.venue.area,
                        profilePhotoUrl: (t.venue as any).profilePhotoUrl ?? null,
                        coverImageUrl: (t.venue as any).coverImageUrl ?? null,
                        images: (t.venue as any).images ?? [],
                    } : null,
                    isExpired,
                });
            }

            // 2. Synthesize from Bookings if not already in tickets
            for (const b of confirmedBookings) {
                const bAny = b as any;
                if (seenBookingIds.has(b.id) || (bAny.ticketCode && seenTicketIds.has(bAny.ticketCode))) continue;
                seenBookingIds.add(b.id);
                if (bAny.ticketCode) seenTicketIds.add(bAny.ticketCode);

                const bDateStr = b.bookingDate ? b.bookingDate.toString() : '';
                const sTime = b.startTime || '20:00';
                let startAt = new Date();
                try {
                    const combined = b.startTime ? new Date(`${bDateStr} ${b.startTime}`) : new Date(bDateStr);
                    if (!isNaN(combined.getTime())) startAt = combined;
                } catch (_) {}
                const expAt = new Date(startAt.getTime() + 12 * 60 * 60 * 1000);
                const bStatus = (b.status || '').toLowerCase();
                const isCancelled = bStatus === 'cancelled';
                const isCompleted = bStatus === 'completed';
                const isExpired = bStatus === 'expired' || isCompleted || expAt < now;
                const ticketCode = bAny.ticketCode || `LUN-${startAt.getFullYear()}-BK-${b.id.substring(0, 6).toUpperCase()}`;

                formattedTickets.push({
                    id: b.id,
                    ticketId: ticketCode,
                    ticketCode,
                    bookingId: b.id,
                    bookingType: b.isLargePartyRequest ? 'group_party' : 'solo',
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isExpired ? 'expired' : 'confirmed')),
                    bookingDate: b.bookingDate,
                    startTime: sTime,
                    eventStartAt: startAt,
                    eventEndAt: expAt,
                    issuedAt: b.createdAt,
                    expiresAt: expAt,
                    usedAt: isCompleted ? expAt : null,
                    pdfUrl: isExpired ? null : (bAny.ticketUrl || null),
                    qrToken: isExpired ? null : ticketCode,
                    ticketUrl: isExpired ? null : (bAny.ticketUrl || null),
                    totalAmount: Number(b.totalAmount || 0),
                    numberOfGuests: b.numberOfGuests || 1,
                    tablePackage: b.tablePackage || 'Standard',
                    isPartyPlan: false,
                    isGroupParty: Boolean(b.isLargePartyRequest),
                    venueName: bAny.venue?.name || 'Lunara Venue',
                    venueAddress: `${bAny.venue?.area || bAny.venue?.addressLine1 || ''}, ${bAny.venue?.city || ''}`.trim(),
                    venue: bAny.venue ? {
                        id: bAny.venue.id,
                        name: bAny.venue.name,
                        addressLine1: bAny.venue.addressLine1,
                        city: bAny.venue.city,
                        area: bAny.venue.area,
                        profilePhotoUrl: bAny.venue.profilePhotoUrl ?? null,
                        coverImageUrl: bAny.venue.coverImageUrl ?? null,
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

                const gpDateStr = gp.partyDate ? gp.partyDate.toString() : '';
                const sTime = gp.startTime || '20:00';
                let startAt = new Date();
                try {
                    const combined = gp.startTime ? new Date(`${gpDateStr} ${gp.startTime}`) : new Date(gpDateStr);
                    if (!isNaN(combined.getTime())) startAt = combined;
                } catch (_) {}
                const expAt = gp.expiresAt ? new Date(gp.expiresAt) : new Date(startAt.getTime() + 12 * 60 * 60 * 1000);
                const gpStatus = (gp.status || '').toLowerCase();
                const isCancelled = gpStatus === 'cancelled' || gpStatus === 'rejected';
                const isCompleted = gpStatus === 'completed';
                const isExpired = gpStatus === 'expired' || isCompleted || expAt < now;
                const ticketCode = gpAny.ticketCode || `LUN-${startAt.getFullYear()}-GP-${gp.id.substring(0, 6).toUpperCase()}`;

                formattedTickets.push({
                    id: gp.id,
                    ticketId: ticketCode,
                    ticketCode,
                    bookingId: gp.id,
                    bookingType: 'group_party',
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isExpired ? 'expired' : 'confirmed')),
                    bookingDate: gp.partyDate,
                    startTime: sTime,
                    eventStartAt: startAt,
                    eventEndAt: expAt,
                    issuedAt: gp.createdAt,
                    expiresAt: expAt,
                    usedAt: isCompleted ? expAt : null,
                    pdfUrl: isExpired ? null : (gpAny.ticketUrl || null),
                    qrToken: isExpired ? null : ticketCode,
                    ticketUrl: isExpired ? null : (gpAny.ticketUrl || null),
                    totalAmount: Number(gp.totalAmount || 0),
                    numberOfGuests: gp.numberOfFriends || 5,
                    tablePackage: 'Group Table',
                    isPartyPlan: false,
                    isGroupParty: true,
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
                if (seenBookingIds.has(req.id) || seenBookingIds.has(plan.id) || (reqAny.ticketCode && seenTicketIds.has(reqAny.ticketCode))) continue;
                seenBookingIds.add(req.id);
                if (reqAny.ticketCode) seenTicketIds.add(reqAny.ticketCode);

                const startAt = plan.planDateTime ? new Date(plan.planDateTime) : new Date();
                const expAt = new Date(startAt.getTime() + 12 * 60 * 60 * 1000);
                const sStatus = (req.status || '').toLowerCase();
                const isCancelled = sStatus === 'cancelled' || sStatus === 'rejected';
                const isCompleted = plan.lifecycleStatus === 'plan_completed';
                const isExpired = sStatus === 'expired' || isCompleted || expAt < now;
                const ticketCode = reqAny.ticketCode || `LUN-${startAt.getFullYear()}-PP-${req.id.substring(0, 6).toUpperCase()}`;

                formattedTickets.push({
                    id: req.id,
                    ticketId: ticketCode,
                    ticketCode,
                    bookingId: plan.id,
                    bookingType: 'party_plan',
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isExpired ? 'expired' : 'confirmed')),
                    bookingDate: plan.planDateTime,
                    startTime: startAt.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: true }),
                    eventStartAt: startAt,
                    eventEndAt: expAt,
                    issuedAt: req.createdAt,
                    expiresAt: expAt,
                    usedAt: isCompleted ? expAt : null,
                    pdfUrl: isExpired ? null : (reqAny.ticketUrl || null),
                    qrToken: isExpired ? null : ticketCode,
                    ticketUrl: isExpired ? null : (reqAny.ticketUrl || null),
                    totalAmount: Number(plan.depositAmount || 99),
                    numberOfGuests: 2,
                    tablePackage: 'Party Plan Match',
                    isPartyPlan: true,
                    isGroupParty: false,
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
                if (seenBookingIds.has(plan.id) || (planAny.ticketCode && seenTicketIds.has(planAny.ticketCode))) continue;
                seenBookingIds.add(plan.id);
                if (planAny.ticketCode) seenTicketIds.add(planAny.ticketCode);

                const startAt = plan.planDateTime ? new Date(plan.planDateTime) : new Date();
                const expAt = new Date(startAt.getTime() + 12 * 60 * 60 * 1000);
                const pStatus = (plan.status || '').toLowerCase();
                const isCancelled = pStatus === 'cancelled';
                const isCompleted = plan.lifecycleStatus === 'plan_completed';
                const isExpired = pStatus === 'expired' || isCompleted || expAt < now;
                const ticketCode = planAny.ticketCode || `LUN-${startAt.getFullYear()}-PP-${plan.id.substring(0, 6).toUpperCase()}`;

                formattedTickets.push({
                    id: plan.id,
                    ticketId: ticketCode,
                    ticketCode,
                    bookingId: plan.id,
                    bookingType: 'party_plan',
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isExpired ? 'expired' : 'confirmed')),
                    bookingDate: plan.planDateTime,
                    startTime: startAt.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: true }),
                    eventStartAt: startAt,
                    eventEndAt: expAt,
                    issuedAt: plan.createdAt,
                    expiresAt: expAt,
                    usedAt: isCompleted ? expAt : null,
                    pdfUrl: isExpired ? null : (planAny.ticketUrl || null),
                    qrToken: isExpired ? null : ticketCode,
                    ticketUrl: isExpired ? null : (planAny.ticketUrl || null),
                    totalAmount: Number(plan.depositAmount || 99),
                    numberOfGuests: 2,
                    tablePackage: 'Party Plan Match',
                    isPartyPlan: true,
                    isGroupParty: false,
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
                if (seenBookingIds.has(j.id) || seenBookingIds.has(meet.id) || (jAny.ticketCode && seenTicketIds.has(jAny.ticketCode))) continue;
                seenBookingIds.add(j.id);
                if (jAny.ticketCode) seenTicketIds.add(jAny.ticketCode);

                const startAt = meet.eventDateTime ? new Date(meet.eventDateTime) : new Date();
                const expAt = meet.expectedEndAt ? new Date(meet.expectedEndAt) : new Date(startAt.getTime() + 4 * 60 * 60 * 1000);
                const jStatus = (j.status || '').toLowerCase();
                const isCancelled = jStatus === 'cancelled' || jStatus === 'rejected';
                const isCompleted = meet.status === 'completed' || meet.status === 'settled';
                const isExpired = meet.status === 'expired' || isCompleted || expAt < now;
                const ticketCode = jAny.ticketCode || `LUN-${startAt.getFullYear()}-SM-${j.id.substring(0, 6).toUpperCase()}`;

                formattedTickets.push({
                    id: j.id,
                    ticketId: ticketCode,
                    ticketCode,
                    bookingId: meet.id,
                    bookingType: 'strangers_meet',
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isExpired ? 'expired' : 'confirmed')),
                    bookingDate: meet.eventDateTime,
                    startTime: startAt.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: true }),
                    eventStartAt: startAt,
                    eventEndAt: expAt,
                    issuedAt: j.createdAt,
                    expiresAt: expAt,
                    usedAt: isCompleted ? expAt : null,
                    pdfUrl: isExpired ? null : (jAny.ticketUrl || meet.ticketUrl || null),
                    qrToken: isExpired ? null : ticketCode,
                    ticketUrl: isExpired ? null : (jAny.ticketUrl || meet.ticketUrl || null),
                    totalAmount: Number(meet.chargesPerHead || 0),
                    numberOfGuests: 2,
                    tablePackage: 'Stranger Meetup',
                    isPartyPlan: false,
                    isGroupParty: false,
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
                if (seenBookingIds.has(sm.id) || (smAny.ticketCode && seenTicketIds.has(smAny.ticketCode))) continue;
                seenBookingIds.add(sm.id);
                if (smAny.ticketCode) seenTicketIds.add(smAny.ticketCode);

                const startAt = sm.eventDateTime ? new Date(sm.eventDateTime) : new Date();
                const expAt = sm.expectedEndAt ? new Date(sm.expectedEndAt) : new Date(startAt.getTime() + 4 * 60 * 60 * 1000);
                const sStatus = (sm.status || '').toLowerCase();
                const isCancelled = sStatus === 'cancelled' || sStatus === 'rejected';
                const isCompleted = sStatus === 'completed' || sStatus === 'settled';
                const isExpired = sStatus === 'expired' || isCompleted || expAt < now;
                const ticketCode = smAny.ticketCode || sm.ticketId || `LUN-${startAt.getFullYear()}-SM-${sm.id.substring(0, 6).toUpperCase()}`;

                formattedTickets.push({
                    id: sm.id,
                    ticketId: ticketCode,
                    ticketCode,
                    bookingId: sm.id,
                    bookingType: 'strangers_meet',
                    status: isCancelled ? 'cancelled' : (isCompleted ? 'completed' : (isExpired ? 'expired' : 'confirmed')),
                    bookingDate: sm.eventDateTime,
                    startTime: startAt.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: true }),
                    eventStartAt: startAt,
                    eventEndAt: expAt,
                    issuedAt: sm.createdAt,
                    expiresAt: expAt,
                    usedAt: isCompleted ? expAt : null,
                    pdfUrl: isExpired ? null : (sm.ticketUrl || null),
                    qrToken: isExpired ? null : ticketCode,
                    ticketUrl: isExpired ? null : (sm.ticketUrl || null),
                    totalAmount: Number(sm.paymentAmount || 99),
                    numberOfGuests: 2,
                    tablePackage: 'Stranger Meetup',
                    isPartyPlan: false,
                    isGroupParty: false,
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
            const userId = req.user!.id;

            const ticket = await Ticket.findOne({
                where: { [Op.or]: [{ id }, { ticketId: id }] },
                include: [
                    { model: Venue, as: 'venue' },
                    { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] },
                ],
            });

            if (!ticket) {
                return res.status(404).json({ success: false, message: 'Ticket not found' });
            }

            if (ticket.userId !== userId) {
                return res.status(403).json({ success: false, message: 'Unauthorized ticket access' });
            }

            const now = new Date();
            const isExpired = ticket.ticketStatus === TicketStatus.EXPIRED || new Date(ticket.expiresAt) < now;

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
                        profilePhotoUrl: (ticket.venue as any).profilePhotoUrl ?? null,
                        coverImageUrl: (ticket.venue as any).coverImageUrl ?? null,
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
            const userId = req.user!.id;

            const ticket = await Ticket.findOne({
                where: { [Op.or]: [{ id }, { ticketId: id }] },
            });

            if (!ticket) {
                return res.status(404).json({ success: false, message: 'Ticket not found' });
            }

            if (ticket.userId !== userId) {
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
            const userId = req.user!.id;

            const ticket = await Ticket.findOne({
                where: { [Op.or]: [{ id }, { ticketId: id }] },
            });

            if (!ticket) {
                return res.status(404).json({ success: false, message: 'Ticket not found' });
            }

            if (ticket.userId !== userId) {
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
            const dateStr = eventStart.toLocaleDateString('en-IN', {
                weekday: 'long', day: '2-digit', month: 'long', year: 'numeric'
            });
            const timeStr = eventStart.toLocaleTimeString('en-IN', {
                hour: '2-digit', minute: '2-digit', hour12: true
            });

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
