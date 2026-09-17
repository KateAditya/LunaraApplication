import { Op } from 'sequelize';
import sequelize from '../config/database';
import PartyPlan, {
    PartyPlanStatus,
    PartyPlanLifecycleStatus,
    PartyPlanPaymentStatus,
    PartyPlanPaymentType,
} from '../models/PartyPlan';
import PartyPlanRequest, { PartyPlanRequestStatus } from '../models/PartyPlanRequest';
import Booking, { BookingStatus, PaymentStatus, BookingPaymentMode } from '../models/Booking';
import Ad from '../models/Ad';
import Venue from '../models/Venue';
import { NotificationService } from './NotificationService';
import { EventSeatService } from './EventSeatService';
import { WalletService } from './walletService';
import { generateTicketForBookingHelper } from './ticketService';
import { PlanEligibilityService } from './PlanEligibilityService';
import { logger } from '../config/logger';
import { v4 as uuidv4 } from 'uuid';

/**
 * The 24-hour "nobody joined yet" decision point for event-linked party plans.
 *
 * A host who buys event tickets to find a partner should not be left holding two
 * seats indefinitely. A day after posting, if no one has been accepted, they are
 * asked what they want to do — and every option settles both the money and the
 * seats, so the event's capacity never stays locked up by a plan that is going
 * nowhere.
 */
export class EventPlanNoMatchService {
    static readonly NO_MATCH_AFTER_MS = 24 * 60 * 60 * 1000;

    /**
     * Finds event-linked plans that have gone 24 hours without a match and asks
     * the host what to do. Notifies each plan once — `eventNoMatchNotifiedAt` is
     * stamped before the dispatch, so a slow or retried sweep cannot send twice.
     */
    static async notifyUnmatchedPlans(): Promise<number> {
        const cutoff = new Date(Date.now() - this.NO_MATCH_AFTER_MS);
        let notified = 0;

        try {
            const candidates = await PartyPlan.findAll({
                where: {
                    partyEventId: { [Op.ne]: null },
                    status: PartyPlanStatus.ACTIVE,
                    hostPaymentStatus: PartyPlanPaymentStatus.PAID,
                    eventNoMatchNotifiedAt: null,
                    createdAt: { [Op.lte]: cutoff },
                    // The event itself must still be ahead of us; a plan for a
                    // night that has already happened is the expiry sweep's
                    // problem, not this one's.
                    planDateTime: { [Op.gt]: new Date() },
                },
                limit: 200,
            });

            for (const plan of candidates) {
                try {
                    const matched = await PartyPlanRequest.count({
                        where: {
                            planId: plan.id,
                            status: {
                                [Op.in]: [
                                    PartyPlanRequestStatus.ACCEPTED,
                                    PartyPlanRequestStatus.PAYMENT_PENDING,
                                ],
                            },
                        },
                    });
                    if (matched > 0) continue;

                    // Stamped first: if the dispatch below throws, the host has
                    // simply missed one notification, which is far better than a
                    // retry loop sending it every sweep.
                    await plan.update({ eventNoMatchNotifiedAt: new Date() });

                    const [event, venue] = await Promise.all([
                        Ad.findByPk(plan.partyEventId!),
                        Venue.findByPk(plan.venueId, { attributes: ['id', 'name'] }),
                    ]);

                    const perTicket = Number(plan.depositAmount) || 0;
                    const paidSeats =
                        plan.paymentType === PartyPlanPaymentType.SELF_PAY ? 2 : 1;
                    const paidTotal = perTicket * paidSeats;
                    const venueName = venue?.name || 'the venue';
                    const eventName = event?.title || 'your event';

                    await NotificationService.dispatch({
                        recipientUserId: plan.userId,
                        actorUserId: plan.userId,
                        eventType: 'event_plan_no_match',
                        category: 'requests',
                        entityType: 'party_plan',
                        entityId: plan.id,
                        title: '⏳ No partner yet for your night',
                        body: `Nobody has joined your plan for ${eventName} at ${venueName} yet. Keep waiting, go solo, or cancel for a refund.`,
                        priority: 'HIGH',
                        idempotencyKey: `event_plan_no_match_${plan.id}`,
                        metadata: {
                            type: 'event_plan_no_match',
                            partyPlanId: plan.id,
                            planId: plan.id,
                            partyEventId: plan.partyEventId,
                            eventName,
                            venueName,
                            perTicketAmount: perTicket,
                            paidAmount: paidTotal,
                            paymentType: plan.paymentType,
                            seatsHeld: plan.eventSeatsReserved || 0,
                            // The client renders exactly these; anything not
                            // listed here is not an option the server accepts.
                            choices: ['keep', 'solo', 'cancel'],
                        },
                    });

                    try {
                        const { io } = require('../server');
                        io?.to(`user_${plan.userId}`).emit('party_plan_updated', {
                            planId: plan.id,
                            partyPlanId: plan.id,
                            eventType: 'event_plan_no_match',
                            updatedAt: new Date().toISOString(),
                        });
                    } catch { /* socket is best-effort */ }

                    notified++;
                } catch (planErr: any) {
                    logger.error(`[EventPlanNoMatch] Failed for plan ${plan.id}: ${planErr?.message}`);
                }
            }
        } catch (err: any) {
            logger.error(`[EventPlanNoMatch] Sweep failed: ${err?.message}`);
        }

        return notified;
    }

    /**
     * Converts an unmatched event plan into a solo booking for the host.
     *
     * The host keeps one ticket and the partner's seat goes back to the event.
     * On SELF_PAY they paid for two, so the second ticket's money is refunded to
     * their wallet; on SPLIT they only ever paid for their own and nothing is
     * owed back.
     */
    static async convertToSolo(planId: string, userId: string) {
        const plan = await PartyPlan.findByPk(planId);
        if (!plan) throw new Error('PLAN_NOT_FOUND');
        if (plan.userId !== userId) throw new Error('NOT_PLAN_OWNER');
        if (!plan.partyEventId) throw new Error('NOT_AN_EVENT_PLAN');
        if (plan.status === PartyPlanStatus.CANCELLED) throw new Error('PLAN_ALREADY_CANCELLED');
        if (plan.hostPaymentStatus !== PartyPlanPaymentStatus.PAID) {
            throw new Error('HOST_HAS_NOT_PAID');
        }

        const matched = await PartyPlanRequest.count({
            where: {
                planId: plan.id,
                status: {
                    [Op.in]: [
                        PartyPlanRequestStatus.ACCEPTED,
                        PartyPlanRequestStatus.PAYMENT_PENDING,
                    ],
                },
            },
        });
        if (matched > 0) throw new Error('PLAN_ALREADY_MATCHED');

        const event = await Ad.findByPk(plan.partyEventId);
        if (!event) throw new Error('EVENT_NOT_FOUND');

        const perTicket = Number(plan.depositAmount) || 0;
        const isSelfPay = plan.paymentType === PartyPlanPaymentType.SELF_PAY;
        // Only SELF_PAY hosts paid for the seat they are giving up.
        const refundAmount = isSelfPay ? perTicket : 0;

        const eventDateStr = (event.eventDate ? new Date(event.eventDate) : plan.planDateTime)
            .toISOString()
            .split('T')[0];
        const startTime = plan.planDateTime
            ? `${String(plan.planDateTime.getHours()).padStart(2, '0')}:${String(plan.planDateTime.getMinutes()).padStart(2, '0')}`
            : '20:00';

        const ticketCode = uuidv4();
        let bookingId = '';

        await sequelize.transaction(async (t) => {
            // The host's own seat carries over to the booking, so it is not
            // released and re-taken — that would briefly expose it to someone
            // else and could leave the host with nothing.
            const booking = await Booking.create({
                bookingNumber: `BKG-${Math.random().toString(36).substring(2, 8).toUpperCase()}`,
                userId: plan.userId,
                venueId: plan.venueId,
                bookingDate: eventDateStr as any,
                startTime,
                numberOfGuests: 1,
                totalAmount: perTicket,
                depositAmount: 0,
                commissionAmount: 0,
                status: BookingStatus.CONFIRMED,
                paymentStatus: PaymentStatus.PAID,
                paymentMode: BookingPaymentMode.PAY_NOW,
                isGroupBooking: false,
                isUpcomingNight: true,
                partyEventId: event.id,
                ticketCode,
            } as any, { transaction: t });
            bookingId = booking.id;

            // The partner's seat goes back inside the same transaction that
            // creates the booking. Doing it afterwards left a window where a
            // crash would strand the seat: the plan would be marked done while
            // the event still counted two against its capacity.
            //
            // The host's own seat is deliberately *not* released and re-taken —
            // it transfers to the booking as-is, so it is never momentarily
            // available for someone else to claim out from under them.
            await EventSeatService.release(plan.partyEventId!, 1, t);

            await plan.update({
                status: PartyPlanStatus.INACTIVE,
                lifecycleStatus: PartyPlanLifecycleStatus.COMPLETED,
                isLive: false,
                // The booking owns the remaining seat now, so the plan holds
                // none — this also stops a later release double-counting it.
                eventSeatsReserved: 0,
                paymentStatus: 'Converted to solo ticket',
            }, { transaction: t });
        });

        await PlanEligibilityService.releaseLock(plan.id).catch(() => { });

        if (refundAmount > 0) {
            try {
                await WalletService.creditRefund({
                    userId: plan.userId,
                    amount: refundAmount,
                    referenceId: `SOLO_CONV_${plan.id.substring(0, 8).toUpperCase()}_${Date.now()}`,
                    reason: 'Unused partner ticket refunded (solo conversion)',
                    partyPlanId: plan.id,
                });
            } catch (refundErr: any) {
                logger.error(`[EventPlanNoMatch] Solo-conversion refund failed for plan ${plan.id}: ${refundErr?.message}`);
            }
        }

        // The ticket is only generated once the booking is committed and paid.
        try {
            await generateTicketForBookingHelper(bookingId);
        } catch (ticketErr: any) {
            logger.error(`[EventPlanNoMatch] Ticket generation failed for booking ${bookingId}: ${ticketErr?.message}`);
        }

        try {
            await NotificationService.dispatch({
                recipientUserId: plan.userId,
                eventType: 'booking_confirmed',
                category: 'bookings',
                entityType: 'Booking',
                entityId: bookingId,
                title: '🎟 Solo ticket confirmed',
                body: refundAmount > 0
                    ? `Your solo ticket is ready. ₹${refundAmount} for the unused second ticket has been credited to your wallet.`
                    : 'Your solo ticket is ready. Enjoy your night!',
                priority: 'HIGH',
                idempotencyKey: `event_plan_solo_${plan.id}`,
                actionType: 'view_ticket',
                deepLink: `/ticket/${bookingId}`,
            });
        } catch { /* notification is best-effort */ }

        return { bookingId, ticketCode, refundAmount, seatsReleased: 1 };
    }
}

export default EventPlanNoMatchService;
