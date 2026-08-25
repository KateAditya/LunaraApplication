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
import { parseEventDateTimeToUTC, formatTime12Hour } from '../utils/dateTimeUtils';

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
        options?: { transaction?: Transaction }
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

        // 1. Party Plans (Host & Partner)
        try {
            const hostPlans = await PartyPlan.findAll({
                where: {
                    userId,
                    status: { [Op.ne]: 'cancelled' },
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
            });

            for (const plan of hostPlans) {
                if (excludeEventId && plan.id === excludeEventId) continue;
                const p = plan as any;
                const hostPaidStr = (plan.hostPaymentStatus || '').toString().toLowerCase();
                const hasAcceptedRequest = p.requests?.some((r: any) =>
                    ['accepted', 'payment_pending', 'confirmed', 'paid'].includes(r.status) && !r.cancelledAt
                ) || hostPaidStr === 'paid' || plan.matchedRequestId;

                if (hasAcceptedRequest || plan.isLive || plan.status === 'active') {
                    const venueName = (plan as any).venue?.name;
                    activeEvents.push({
                        id: plan.id,
                        type: 'PARTY_PLAN',
                        title: venueName ? `${venueName} (Party Plan)` : (plan.message || 'Party Plan'),
                        dateTime: new Date(plan.planDateTime),
                    });
                }
            }

            const partnerRequests = await PartyPlanRequest.findAll({
                where: {
                    requesterId: userId,
                    [Op.or]: [
                        { status: { [Op.in]: [PartyPlanRequestStatus.ACCEPTED, PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.WAITING] } },
                        { joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID },
                    ],
                },
                transaction,
            });

            for (const req of partnerRequests) {
                if (req.cancelledAt) continue;
                const plan = await PartyPlan.findByPk(req.planId, {
                    include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                    transaction
                });
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
        } catch (err: any) {
            console.error('Error fetching Party Plans for time lock:', err?.message || err);
        }

        // 2. Group Parties
        try {
            const groupParties = await GroupParty.findAll({
                where: {
                    userId,
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

        // 3. Stranger Meets (Host & Joiner)
        try {
            const hostMeets = await StrangersMeetRequest.findAll({
                where: {
                    userId,
                    status: { [Op.notIn]: [StrangersMeetStatus.CANCELLED, StrangersMeetStatus.REJECTED] },
                },
                include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                transaction,
            });

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

            const joinerMeets = await StrangersMeetJoiner.findAll({
                where: {
                    userId,
                    [Op.or]: [
                        { status: { [Op.in]: ['accepted', 'paid'] } },
                        { paymentStatus: StrangersMeetJoinerPaymentStatus.PAID },
                    ],
                },
                transaction,
            });

            for (const jm of joinerMeets) {
                const sm = await StrangersMeetRequest.findByPk(jm.strangersMeetRequestId, {
                    include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                    transaction,
                });
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
        } catch (err: any) {
            console.error('Error fetching Stranger Meets for time lock:', err?.message || err);
        }

        // 4. Solo Bookings, With Friends bookings & Large Parties
        try {
            const bookings = await Booking.findAll({
                where: {
                    userId,
                    status: { [Op.in]: [BookingStatus.CONFIRMED, BookingStatus.PENDING, BookingStatus.COMPLETED] },
                },
                include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
                transaction,
            });

            for (const b of bookings) {
                if (excludeEventId && b.id === excludeEventId) continue;
                if (b.status === BookingStatus.CANCELLED) continue;

                const isLargeParty = b.goingMode === 'party_request' || (b as any).isLargePartyRequest;
                const isPending = b.status === BookingStatus.PENDING;
                const isPaid = b.paymentStatus === PaymentStatus.PAID || b.paymentStatus === PaymentStatus.PARTIALLY_PAID;

                // Ignore stale abandoned unpaid small bookings (> 30 mins old)
                if (isPending && !isPaid && !isLargeParty) {
                    const createdAtMs = b.createdAt ? new Date(b.createdAt).getTime() : 0;
                    if (Date.now() - createdAtMs > 30 * 60 * 1000) {
                        continue;
                    }
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

            // Also check bookings where user is a paid group split member
            const memberSplits = await BookingMember.findAll({
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
            });

            for (const mb of memberSplits) {
                const groupBooking = (mb as any).groupBooking;
                const b = groupBooking?.booking;
                if (b && b.status !== BookingStatus.CANCELLED) {
                    if (excludeEventId && (b.id === excludeEventId || mb.id === excludeEventId)) continue;
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
}

export default EventTimeLockService;
