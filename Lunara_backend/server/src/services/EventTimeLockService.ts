import { Op, Transaction } from 'sequelize';
import PartyPlan from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus, PartyPlanJoinerPaymentStatus } from '../models/PartyPlanRequest';
import GroupParty from '../models/GroupParty';
import StrangersMeetRequest, { StrangersMeetStatus } from '../models/StrangersMeetRequest';
import StrangersMeetJoiner, { StrangersMeetJoinerPaymentStatus } from '../models/StrangersMeetJoiner';
import Booking, { BookingStatus, PaymentStatus } from '../models/Booking';
import BookingMember, { MemberPaymentStatus } from '../models/BookingMember';
import GroupBooking from '../models/GroupBooking';
import Venue from '../models/Venue';
import { parseEventDateTimeToUTC, formatTime12Hour, extractDateParts, DEFAULT_TIMEZONE } from '../utils/dateTimeUtils';

export interface TimeLockConflict {
    allowed: false;
    reason: 'FOUR_HOUR_TIME_LOCK';
    conflictingEventType: 'PARTY_PLAN' | 'GROUP_PARTY' | 'STRANGER_MEET' | 'SOLO_BOOKING' | 'LARGE_PARTY';
    conflictingEventId: string;
    conflictingEventTitle: string;
    conflictingDateTime: string;
    nextAvailableTime: string;
    message: string;
}

export interface TimeLockSuccess {
    allowed: true;
}

export type TimeLockValidationResult = TimeLockConflict | TimeLockSuccess;

const FOUR_HOURS_MS = 4 * 60 * 60 * 1000; // Exact 4-hour threshold in milliseconds (14,400,000 ms)

export function parseBookingDateTime(bookingDate: Date | string, startTimeStr?: string): Date {
    return parseEventDateTimeToUTC(bookingDate, startTimeStr);
}

export class EventTimeLockService {
    /**
     * Universal 4-Hour Time-Lock Validation Service
     * Checks if a user has any conflicting locked/confirmed event within 4 hours
     * across Party Plan, Group Party, Stranger Meet, Solo Booking, and Large Party.
     *
     * Exact Boundary Rule:
     * - Gap >= 4.0 hours: ALLOWED
     * - Gap < 4.0 hours: BLOCKED
     */
    public static async validateFourHourGap(
        userId: string,
        proposedDateTimeInput: Date | string,
        _eventType: 'party_plan' | 'group_party' | 'stranger_meet' | 'solo_booking' | 'large_party',
        excludeEventId?: string,
        options?: { transaction?: Transaction; excludeVenueId?: string }
    ): Promise<TimeLockValidationResult> {
        const proposedTime = typeof proposedDateTimeInput === 'string'
            ? new Date(proposedDateTimeInput)
            : proposedDateTimeInput;

        if (!proposedTime || isNaN(proposedTime.getTime())) {
            return {
                allowed: false,
                reason: 'FOUR_HOUR_TIME_LOCK',
                conflictingEventType: 'PARTY_PLAN',
                conflictingEventId: '',
                conflictingEventTitle: 'Invalid Time',
                conflictingDateTime: '',
                nextAvailableTime: '',
                message: 'Invalid event date and time provided.'
            };
        }

        const transaction = options?.transaction;
        const activeEvents: Array<{
            id: string;
            type: 'PARTY_PLAN' | 'GROUP_PARTY' | 'STRANGER_MEET' | 'SOLO_BOOKING' | 'LARGE_PARTY';
            title: string;
            dateTime: Date;
        }> = [];

        // Calculate search window: proposedTime +/- 5 hours to leverage DB indexes and avoid table scans
        const windowStart = new Date(proposedTime.getTime() - 5 * 60 * 60 * 1000);
        const windowEnd = new Date(proposedTime.getTime() + 5 * 60 * 60 * 1000);
        const [startY, startM, startD] = extractDateParts(windowStart, DEFAULT_TIMEZONE);
        const [endY, endM, endD] = extractDateParts(windowEnd, DEFAULT_TIMEZONE);
        const windowStartDateStr = `${startY}-${String(startM).padStart(2, '0')}-${String(startD).padStart(2, '0')}`;
        const windowEndDateStr = `${endY}-${String(endM).padStart(2, '0')}-${String(endD).padStart(2, '0')}`;

        // Parallelize fetching across all event categories (Party Plans, Group Parties, Stranger Meets, Bookings)
        await Promise.all([
            // 1. Party Plans (Host & Partner)
            (async () => {
                try {
                    const [hostPlans, partnerRequests] = await Promise.all([
                        PartyPlan.findAll({
                            where: {
                                userId,
                                status: { [Op.ne]: 'cancelled' },
                                planDateTime: { [Op.between]: [windowStart, windowEnd] },
                                [Op.or]: [
                                    { lifecycleStatus: { [Op.eq]: null as any } },
                                    { lifecycleStatus: { [Op.notIn]: ['cancelled', 'expired'] } }
                                ]
                            },
                            include: [
                                { model: PartyPlanRequest, as: 'requests' },
                                { model: Venue, as: 'venue', attributes: ['id', 'name'] },
                            ],
                            transaction,
                        }),
                        PartyPlanRequest.findAll({
                            where: {
                                requesterId: userId,
                                [Op.or]: [
                                    { status: { [Op.in]: [PartyPlanRequestStatus.ACCEPTED, PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.WAITING] } },
                                    { joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID },
                                ],
                            },
                            transaction,
                        })
                    ]);

                    for (const plan of hostPlans) {
                        if (excludeEventId && plan.id === excludeEventId) continue;
                        const p = plan as any;
                        const hostPaidStr = (plan.hostPaymentStatus || (plan as any).paymentStatus || '').toString().toLowerCase();
                        const isHostPaid = hostPaidStr === 'paid';
                        const hasAcceptedRequest = p.requests?.some((r: any) =>
                            ['accepted', 'payment_pending', 'confirmed', 'paid'].includes((r.status || '').toLowerCase()) && !r.cancelledAt
                        ) || isHostPaid || Boolean(plan.matchedRequestId);

                        const isHostUnpaidDraft = !isHostPaid && !hasAcceptedRequest && !plan.isLive;
                        if (!isHostUnpaidDraft && (hasAcceptedRequest || plan.isLive || (isHostPaid && plan.status === 'active'))) {
                            const venueName = (plan as any).venue?.name;
                            activeEvents.push({
                                id: plan.id,
                                type: 'PARTY_PLAN',
                                title: venueName ? `${venueName} (Party Plan)` : (plan.message || 'Party Plan'),
                                dateTime: new Date(plan.planDateTime),
                            });
                        }
                    }

                    // Batch fetch partner plans without N+1 findByPk loops
                    const partnerPlanIds = partnerRequests
                        .filter(r => !r.cancelledAt && r.planId)
                        .map(r => r.planId);

                    if (partnerPlanIds.length > 0) {
                        const partnerPlans = await PartyPlan.findAll({
                            where: { id: { [Op.in]: partnerPlanIds } },
                            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                            transaction,
                        });

                        const planMap = new Map<string, any>();
                        for (const p of partnerPlans) planMap.set(p.id, p);

                        for (const req of partnerRequests) {
                            if (req.cancelledAt) continue;
                            const plan = planMap.get(req.planId);
                            if (!plan) continue;
                            if (excludeEventId && (plan.id === excludeEventId || req.id === excludeEventId)) continue;
                            const planStatStr = (plan.status || '').toString().toLowerCase();
                            const planLifeStr = (plan.lifecycleStatus || '').toString().toLowerCase();
                            if (planStatStr === 'cancelled' || planStatStr === 'expired' || planLifeStr === 'cancelled' || planLifeStr === 'expired') continue;

                            const venueName = (plan as any).venue?.name;
                            activeEvents.push({
                                id: plan.id,
                                type: 'PARTY_PLAN',
                                title: venueName ? `${venueName} (Party Plan)` : (plan.message || 'Party Plan'),
                                dateTime: new Date(plan.planDateTime),
                            });
                        }
                    }
                } catch (err: any) {
                    console.error('Error fetching Party Plans for time lock:', err?.message || err);
                }
            })(),

            // 2. Group Parties
            (async () => {
                try {
                    const groupParties = await GroupParty.findAll({
                        where: {
                            userId,
                            partyDate: { [Op.between]: [windowStartDateStr, windowEndDateStr] },
                            status: { [Op.notIn]: ['cancelled', 'expired', 'rejected'] },
                        },
                        include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                        transaction,
                    });

                    for (const gp of groupParties) {
                        if (excludeEventId && gp.id === excludeEventId) continue;
                        const gpTime = parseBookingDateTime(gp.partyDate, gp.startTime);
                        const venueName = (gp as any).venue?.name;
                        activeEvents.push({
                            id: gp.id,
                            type: 'GROUP_PARTY',
                            title: venueName ? `${venueName} (Group Party)` : 'Group Party',
                            dateTime: gpTime,
                        });
                    }
                } catch (err: any) {
                    console.error('Error fetching Group Parties for time lock:', err?.message || err);
                }
            })(),

            // 3. Stranger Meets (Host & Joiner)
            (async () => {
                try {
                    const [hostMeets, joinerMeets] = await Promise.all([
                        StrangersMeetRequest.findAll({
                            where: {
                                userId,
                                eventDateTime: { [Op.between]: [windowStart, windowEnd] },
                                status: { [Op.notIn]: [StrangersMeetStatus.CANCELLED, StrangersMeetStatus.REJECTED] },
                            },
                            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                            transaction,
                        }),
                        StrangersMeetJoiner.findAll({
                            where: {
                                userId,
                                [Op.or]: [
                                    { status: { [Op.in]: ['accepted', 'paid'] } },
                                    { paymentStatus: StrangersMeetJoinerPaymentStatus.PAID },
                                ],
                            },
                            transaction,
                        })
                    ]);

                    for (const sm of hostMeets) {
                        if (excludeEventId && sm.id === excludeEventId) continue;
                        const meetDate = sm.eventDateTime || (sm as any).meetDateTime;
                        if (!meetDate) continue;
                        const venueName = (sm as any).venue?.name;
                        activeEvents.push({
                            id: sm.id,
                            type: 'STRANGER_MEET',
                            title: venueName ? `${venueName} (Strangers Meet)` : (sm.subject || 'Strangers Meet'),
                            dateTime: new Date(meetDate),
                        });
                    }

                    // Batch fetch joiner meet requests without N+1 findByPk loops
                    const joinerMeetIds = joinerMeets
                        .map(jm => jm.strangersMeetRequestId)
                        .filter(Boolean);

                    if (joinerMeetIds.length > 0) {
                        const strangerMeets = await StrangersMeetRequest.findAll({
                            where: {
                                id: { [Op.in]: joinerMeetIds },
                                eventDateTime: { [Op.between]: [windowStart, windowEnd] },
                            },
                            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                            transaction,
                        });

                        const meetMap = new Map<string, any>();
                        for (const sm of strangerMeets) meetMap.set(sm.id, sm);

                        for (const jm of joinerMeets) {
                            const sm = meetMap.get(jm.strangersMeetRequestId);
                            if (!sm) continue;
                            if (excludeEventId && (sm.id === excludeEventId || jm.id === excludeEventId)) continue;
                            if ([StrangersMeetStatus.CANCELLED, StrangersMeetStatus.REJECTED].includes(sm.status)) continue;
                            const meetDate = sm.eventDateTime || (sm as any).meetDateTime;
                            if (!meetDate) continue;

                            const venueName = (sm as any).venue?.name;
                            activeEvents.push({
                                id: sm.id,
                                type: 'STRANGER_MEET',
                                title: venueName ? `${venueName} (Strangers Meet)` : (sm.subject || 'Strangers Meet'),
                                dateTime: new Date(meetDate),
                            });
                        }
                    }
                } catch (err: any) {
                    console.error('Error fetching Stranger Meets for time lock:', err?.message || err);
                }
            })(),

            // 4. Solo Bookings, With Friends bookings & Large Parties
            (async () => {
                try {
                    const [bookings, memberSplits] = await Promise.all([
                        Booking.findAll({
                            where: {
                                userId,
                                bookingDate: { [Op.between]: [windowStartDateStr, windowEndDateStr] },
                                status: { [Op.in]: [BookingStatus.CONFIRMED, BookingStatus.PENDING, BookingStatus.COMPLETED] },
                            },
                            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                            transaction,
                        }),
                        BookingMember.findAll({
                            where: {
                                userId,
                                paymentStatus: MemberPaymentStatus.PAID,
                            },
                            include: [
                                {
                                    model: GroupBooking,
                                    as: 'groupBooking',
                                    include: [
                                        {
                                            model: Booking,
                                            as: 'booking',
                                            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                                        },
                                    ],
                                },
                            ],
                            transaction,
                        })
                    ]);

                    for (const b of bookings) {
                        if (excludeEventId) {
                            if (b.id === excludeEventId) continue;
                            // Exclude booking if it was created for this party plan
                            if (b.specialRequests && b.specialRequests.includes(excludeEventId)) continue;
                            if ((b as any).partyEventId && (b as any).partyEventId === excludeEventId) continue;
                        }
                        if (options?.excludeVenueId && b.venueId === options.excludeVenueId) {
                            continue;
                        }
                        if (b.status === BookingStatus.CANCELLED) continue;

                        const isLargeParty = b.goingMode === 'party_request' || (b as any).isLargePartyRequest;
                        const isPending = b.status === BookingStatus.PENDING;
                        const isPaid = b.paymentStatus === PaymentStatus.PAID || b.paymentStatus === PaymentStatus.PARTIALLY_PAID;

                        // Ignore unpaid pending bookings (drafts)
                        if (isPending && !isPaid && !isLargeParty) {
                            continue;
                        }

                        const bookingDateTime = parseBookingDateTime(b.bookingDate, b.startTime);
                        const bType = isLargeParty ? 'LARGE_PARTY' : 'SOLO_BOOKING';
                        const venueName = (b as any).venue?.name;

                        activeEvents.push({
                            id: b.id,
                            type: bType,
                            title: b.partySubject || (venueName ? `${venueName} (${isLargeParty ? 'With Friends' : 'Solo'})` : (isLargeParty ? 'With Friends Booking' : 'Solo Venue Booking')),
                            dateTime: bookingDateTime,
                        });
                    }

                    for (const mb of memberSplits) {
                        const groupBooking = (mb as any).groupBooking;
                        const b = groupBooking?.booking;
                        if (b && b.status !== BookingStatus.CANCELLED) {
                            if (excludeEventId) {
                                if (b.id === excludeEventId || mb.id === excludeEventId) continue;
                                if (b.specialRequests && b.specialRequests.includes(excludeEventId)) continue;
                                if ((b as any).partyEventId && (b as any).partyEventId === excludeEventId) continue;
                            }
                            const bookingDateTime = parseBookingDateTime(b.bookingDate, b.startTime);
                            const venueName = b.venue?.name;
                            activeEvents.push({
                                id: b.id,
                                type: 'LARGE_PARTY',
                                title: venueName ? `${venueName} (Group Member)` : 'Group Table Booking',
                                dateTime: bookingDateTime,
                            });
                        }
                    }
                } catch (err: any) {
                    console.error('Error fetching Bookings for time lock:', err?.message || err);
                }
            })(),

            // 5. Night Partner Matches (Host & Partner)
            (async () => {
                try {
                    const NightPartnerMatch = (await import('../models/NightPartnerMatch')).default;
                    const { NightPartnerMatchStatus } = await import('../models/NightPartnerMatch');
                    const matches = await NightPartnerMatch.findAll({
                        where: {
                            [Op.or]: [{ hostId: userId }, { partnerId: userId }],
                            eventDate: { [Op.between]: [windowStartDateStr, windowEndDateStr] },
                            status: { [Op.in]: [NightPartnerMatchStatus.MATCHED, NightPartnerMatchStatus.PAYMENT_PENDING, NightPartnerMatchStatus.CONFIRMED] },
                        },
                        include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                        transaction,
                    });

                    for (const m of matches) {
                        if (excludeEventId && (m.id === excludeEventId || m.requestId === excludeEventId)) continue;
                        const vName = (m as any).venue?.name;
                        const matchTime = parseBookingDateTime(m.eventDate, m.eventTime || '20:00');
                        activeEvents.push({
                            id: m.id,
                            type: 'PARTY_PLAN',
                            title: vName ? `${vName} (Upcoming Night)` : 'Upcoming Night Event',
                            dateTime: matchTime,
                        });
                    }
                } catch (err: any) {
                    console.error('Error fetching Night Partner Matches for time lock:', err?.message || err);
                }
            })()
        ]);

        // Check for conflicts within the 4-hour gap
        for (const event of activeEvents) {
            const existingTimeMs = event.dateTime.getTime();
            const proposedTimeMs = proposedTime.getTime();
            const timeDiffMs = Math.abs(proposedTimeMs - existingTimeMs);

            if (timeDiffMs < FOUR_HOURS_MS) {
                const nextAvailableMs = existingTimeMs + FOUR_HOURS_MS;
                const nextAvailableDate = new Date(nextAvailableMs);

                const existingDateStr = formatTime12Hour(event.dateTime);
                const nextAvailableStr = formatTime12Hour(nextAvailableDate);

                const friendlyTypeName = event.type.replace(/_/g, ' ');
                const message = `You already have a ${friendlyTypeName} scheduled for ${existingDateStr}. Your next event must be scheduled at least 4 hours apart (earliest available: ${nextAvailableStr}).`;

                return {
                    allowed: false,
                    reason: 'FOUR_HOUR_TIME_LOCK',
                    conflictingEventType: event.type,
                    conflictingEventId: event.id,
                    conflictingEventTitle: event.title,
                    conflictingDateTime: event.dateTime.toISOString(),
                    nextAvailableTime: nextAvailableDate.toISOString(),
                    message,
                };
            }
        }

        return { allowed: true };
    }

    /**
     * Batch validation for multiple users in a single parallel query set.
     * Prevents database pool exhaustion when checking 10-50 invited users simultaneously.
     */
    public static async validateFourHourGapBatch(
        userIds: string[],
        proposedDateTimeInput: Date | string,
        _eventType: 'party_plan' | 'group_party' | 'stranger_meet' | 'solo_booking' | 'large_party',
        options?: { transaction?: Transaction; excludeVenueId?: string }
    ): Promise<Map<string, TimeLockValidationResult>> {
        const resultMap = new Map<string, TimeLockValidationResult>();
        const uniqueUserIds = [...new Set(userIds.filter(Boolean))];
        if (uniqueUserIds.length === 0) return resultMap;

        const proposedTime = typeof proposedDateTimeInput === 'string'
            ? new Date(proposedDateTimeInput)
            : proposedDateTimeInput;

        if (!proposedTime || isNaN(proposedTime.getTime())) {
            for (const uid of uniqueUserIds) {
                resultMap.set(uid, {
                    allowed: false,
                    reason: 'FOUR_HOUR_TIME_LOCK',
                    conflictingEventType: 'PARTY_PLAN',
                    conflictingEventId: '',
                    conflictingEventTitle: 'Invalid Time',
                    conflictingDateTime: '',
                    nextAvailableTime: '',
                    message: 'Invalid event date and time provided.'
                });
            }
            return resultMap;
        }

        const transaction = options?.transaction;
        const windowStart = new Date(proposedTime.getTime() - 5 * 60 * 60 * 1000);
        const windowEnd = new Date(proposedTime.getTime() + 5 * 60 * 60 * 1000);
        const [startY, startM, startD] = extractDateParts(windowStart, DEFAULT_TIMEZONE);
        const [endY, endM, endD] = extractDateParts(windowEnd, DEFAULT_TIMEZONE);
        const windowStartDateStr = `${startY}-${String(startM).padStart(2, '0')}-${String(startD).padStart(2, '0')}`;
        const windowEndDateStr = `${endY}-${String(endM).padStart(2, '0')}-${String(endD).padStart(2, '0')}`;

        const userEventsMap = new Map<string, Array<{
            id: string;
            type: 'PARTY_PLAN' | 'GROUP_PARTY' | 'STRANGER_MEET' | 'SOLO_BOOKING' | 'LARGE_PARTY';
            title: string;
            dateTime: Date;
        }>>();

        for (const uid of uniqueUserIds) {
            userEventsMap.set(uid, []);
        }

        await Promise.all([
            // 1. Party Plans (Host & Partner)
            (async () => {
                try {
                    const [hostPlans, partnerRequests] = await Promise.all([
                        PartyPlan.findAll({
                            where: {
                                userId: { [Op.in]: uniqueUserIds },
                                status: { [Op.ne]: 'cancelled' },
                                planDateTime: { [Op.between]: [windowStart, windowEnd] },
                                [Op.or]: [
                                    { lifecycleStatus: { [Op.eq]: null as any } },
                                    { lifecycleStatus: { [Op.notIn]: ['cancelled', 'expired'] } }
                                ]
                            },
                            include: [
                                { model: PartyPlanRequest, as: 'requests' },
                                { model: Venue, as: 'venue', attributes: ['id', 'name'] },
                            ],
                            transaction,
                        }),
                        PartyPlanRequest.findAll({
                            where: {
                                requesterId: { [Op.in]: uniqueUserIds },
                                [Op.or]: [
                                    { status: { [Op.in]: [PartyPlanRequestStatus.ACCEPTED, PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.WAITING] } },
                                    { joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID },
                                ],
                            },
                            transaction,
                        })
                    ]);

                    for (const plan of hostPlans) {
                        const p = plan as any;
                        const hostPaidStr = (plan.hostPaymentStatus || (plan as any).paymentStatus || '').toString().toLowerCase();
                        const isHostPaid = hostPaidStr === 'paid';
                        const hasAcceptedRequest = p.requests?.some((r: any) =>
                            ['accepted', 'payment_pending', 'confirmed', 'paid'].includes((r.status || '').toLowerCase()) && !r.cancelledAt
                        ) || isHostPaid || Boolean(plan.matchedRequestId);

                        const isHostUnpaidDraft = !isHostPaid && !hasAcceptedRequest && !plan.isLive;
                        if (!isHostUnpaidDraft && (hasAcceptedRequest || plan.isLive || (isHostPaid && plan.status === 'active'))) {
                            const venueName = (plan as any).venue?.name;
                            const events = userEventsMap.get(plan.userId);
                            if (events) {
                                events.push({
                                    id: plan.id,
                                    type: 'PARTY_PLAN',
                                    title: venueName ? `${venueName} (Party Plan)` : (plan.message || 'Party Plan'),
                                    dateTime: new Date(plan.planDateTime),
                                });
                            }
                        }
                    }

                    const partnerPlanIds = partnerRequests
                        .filter(r => !r.cancelledAt && r.planId)
                        .map(r => r.planId);

                    if (partnerPlanIds.length > 0) {
                        const partnerPlans = await PartyPlan.findAll({
                            where: { id: { [Op.in]: partnerPlanIds } },
                            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                            transaction,
                        });

                        const planMap = new Map<string, any>();
                        for (const p of partnerPlans) planMap.set(p.id, p);

                        for (const req of partnerRequests) {
                            if (req.cancelledAt) continue;
                            const plan = planMap.get(req.planId);
                            if (!plan) continue;
                            const planStatStr = (plan.status || '').toString().toLowerCase();
                            const planLifeStr = (plan.lifecycleStatus || '').toString().toLowerCase();
                            if (planStatStr === 'cancelled' || planStatStr === 'expired' || planLifeStr === 'cancelled' || planLifeStr === 'expired') continue;

                            const venueName = (plan as any).venue?.name;
                            const events = userEventsMap.get(req.requesterId);
                            if (events) {
                                events.push({
                                    id: plan.id,
                                    type: 'PARTY_PLAN',
                                    title: venueName ? `${venueName} (Party Plan)` : (plan.message || 'Party Plan'),
                                    dateTime: new Date(plan.planDateTime),
                                });
                            }
                        }
                    }
                } catch (err: any) {
                    console.error('Error fetching Party Plans for batch time lock:', err?.message || err);
                }
            })(),

            // 2. Group Parties
            (async () => {
                try {
                    const groupParties = await GroupParty.findAll({
                        where: {
                            userId: { [Op.in]: uniqueUserIds },
                            partyDate: { [Op.between]: [windowStartDateStr, windowEndDateStr] },
                            status: { [Op.notIn]: ['cancelled', 'expired', 'rejected'] },
                        },
                        include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                        transaction,
                    });

                    for (const gp of groupParties) {
                        const gpTime = parseBookingDateTime(gp.partyDate, gp.startTime);
                        const venueName = (gp as any).venue?.name;
                        const events = userEventsMap.get(gp.userId);
                        if (events) {
                            events.push({
                                id: gp.id,
                                type: 'GROUP_PARTY',
                                title: venueName ? `${venueName} (Group Party)` : 'Group Party',
                                dateTime: gpTime,
                            });
                        }
                    }
                } catch (err: any) {
                    console.error('Error fetching Group Parties for batch time lock:', err?.message || err);
                }
            })(),

            // 3. Stranger Meets
            (async () => {
                try {
                    const [hostMeets, joinerMeets] = await Promise.all([
                        StrangersMeetRequest.findAll({
                            where: {
                                userId: { [Op.in]: uniqueUserIds },
                                eventDateTime: { [Op.between]: [windowStart, windowEnd] },
                                status: { [Op.notIn]: [StrangersMeetStatus.CANCELLED, StrangersMeetStatus.REJECTED] },
                            },
                            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                            transaction,
                        }),
                        StrangersMeetJoiner.findAll({
                            where: {
                                userId: { [Op.in]: uniqueUserIds },
                                [Op.or]: [
                                    { paymentStatus: StrangersMeetJoinerPaymentStatus.PAID },
                                    { status: 'joined' },
                                ],
                            },
                            include: [
                                {
                                    model: StrangersMeetRequest,
                                    as: 'strangersMeetRequest',
                                    where: {
                                        eventDateTime: { [Op.between]: [windowStart, windowEnd] },
                                        status: { [Op.notIn]: [StrangersMeetStatus.CANCELLED, StrangersMeetStatus.REJECTED] },
                                    },
                                    include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                                },
                            ],
                            transaction,
                        }),
                    ]);

                    for (const sm of hostMeets) {
                        const venueName = (sm as any).venue?.name;
                        const events = userEventsMap.get(sm.userId);
                        if (events) {
                            events.push({
                                id: sm.id,
                                type: 'STRANGER_MEET',
                                title: venueName ? `${venueName} (Stranger Meet Host)` : (sm.subject || 'Stranger Meet'),
                                dateTime: new Date(sm.eventDateTime),
                            });
                        }
                    }

                    for (const jm of joinerMeets) {
                        const req = (jm as any).strangersMeetRequest || (jm as any).request;
                        if (req) {
                            const venueName = req.venue?.name;
                            const events = userEventsMap.get(jm.userId);
                            if (events) {
                                events.push({
                                    id: req.id,
                                    type: 'STRANGER_MEET',
                                    title: venueName ? `${venueName} (Stranger Meet)` : (req.subject || 'Stranger Meet'),
                                    dateTime: new Date(req.eventDateTime),
                                });
                            }
                        }
                    }
                } catch (err: any) {
                    console.error('Error fetching Stranger Meets for batch time lock:', err?.message || err);
                }
            })(),

            // 4. Bookings
            (async () => {
                try {
                    const [bookings, memberSplits] = await Promise.all([
                        Booking.findAll({
                            where: {
                                userId: { [Op.in]: uniqueUserIds },
                                bookingDate: { [Op.between]: [windowStartDateStr, windowEndDateStr] },
                                status: { [Op.ne]: BookingStatus.CANCELLED },
                            },
                            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                            transaction,
                        }),
                        BookingMember.findAll({
                            where: {
                                userId: { [Op.in]: uniqueUserIds },
                                paymentStatus: { [Op.in]: [MemberPaymentStatus.PAID, MemberPaymentStatus.PENDING] },
                            },
                            include: [
                                {
                                    model: GroupBooking,
                                    as: 'groupBooking',
                                    include: [
                                        {
                                            model: Booking,
                                            as: 'booking',
                                            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                                        },
                                    ],
                                },
                            ],
                            transaction,
                        })
                    ]);

                    for (const b of bookings) {
                        if (options?.excludeVenueId && b.venueId === options.excludeVenueId) continue;
                        if (b.status === BookingStatus.CANCELLED) continue;
                        const isLargeParty = b.goingMode === 'party_request' || (b as any).isLargePartyRequest;
                        const isPending = b.status === BookingStatus.PENDING;
                        const isPaid = b.paymentStatus === PaymentStatus.PAID || b.paymentStatus === PaymentStatus.PARTIALLY_PAID;
                        if (isPending && !isPaid && !isLargeParty) continue;
                        const bookingDateTime = parseBookingDateTime(b.bookingDate, b.startTime);
                        const bType = isLargeParty ? 'LARGE_PARTY' : 'SOLO_BOOKING';
                        const venueName = (b as any).venue?.name;
                        const events = userEventsMap.get(b.userId);
                        if (events) {
                            events.push({
                                id: b.id,
                                type: bType,
                                title: b.partySubject || (venueName ? `${venueName} (${isLargeParty ? 'With Friends' : 'Solo'})` : (isLargeParty ? 'With Friends Booking' : 'Solo Venue Booking')),
                                dateTime: bookingDateTime,
                            });
                        }
                    }

                    for (const mb of memberSplits) {
                        const groupBooking = (mb as any).groupBooking;
                        const b = groupBooking?.booking;
                        if (b && b.status !== BookingStatus.CANCELLED && mb.userId) {
                            const bookingDateTime = parseBookingDateTime(b.bookingDate, b.startTime);
                            const venueName = b.venue?.name;
                            const events = userEventsMap.get(mb.userId);
                            if (events) {
                                events.push({
                                    id: b.id,
                                    type: 'LARGE_PARTY',
                                    title: venueName ? `${venueName} (Group Member)` : 'Group Table Booking',
                                    dateTime: bookingDateTime,
                                });
                            }
                        }
                    }
                } catch (err: any) {
                    console.error('Error fetching Bookings for batch time lock:', err?.message || err);
                }
            })(),
        ]);

        // Evaluate conflicts per user
        for (const uid of uniqueUserIds) {
            const activeEvents = userEventsMap.get(uid) || [];
            let userConflict: TimeLockConflict | null = null;

            for (const event of activeEvents) {
                const existingTimeMs = event.dateTime.getTime();
                const proposedTimeMs = proposedTime.getTime();
                const timeDiffMs = Math.abs(proposedTimeMs - existingTimeMs);

                if (timeDiffMs < FOUR_HOURS_MS) {
                    const nextAvailableMs = existingTimeMs + FOUR_HOURS_MS;
                    const nextAvailableDate = new Date(nextAvailableMs);
                    const existingDateStr = formatTime12Hour(event.dateTime);
                    const nextAvailableStr = formatTime12Hour(nextAvailableDate);
                    const friendlyTypeName = event.type.replace(/_/g, ' ');
                    const message = `User already has a ${friendlyTypeName} scheduled for ${existingDateStr}. Next event must be scheduled at least 4 hours apart (earliest available: ${nextAvailableStr}).`;

                    userConflict = {
                        allowed: false,
                        reason: 'FOUR_HOUR_TIME_LOCK',
                        conflictingEventType: event.type,
                        conflictingEventId: event.id,
                        conflictingEventTitle: event.title,
                        conflictingDateTime: event.dateTime.toISOString(),
                        nextAvailableTime: nextAvailableDate.toISOString(),
                        message,
                    };
                    break;
                }
            }

            resultMap.set(uid, userConflict || { allowed: true });
        }

        return resultMap;
    }
}

export default EventTimeLockService;
