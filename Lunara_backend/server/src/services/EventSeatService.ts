
import { Transaction } from 'sequelize';
import sequelize from '../config/database';
import Ad from '../models/Ad';
import { logger } from '../config/logger';

/**
 * Capacity accounting for Upcoming Night events (Ads of type 'Party').
 *
 * Seats used to be taken with a read-then-write against `filledSeats`: the
 * caller read the remaining count, decided, and saved — with no lock and no
 * transaction. Two bookings landing together both read the same remaining count
 * and both wrote, so an event with one seat left could sell two. Everything that
 * touches capacity now goes through here, where the row is locked for the whole
 * check-and-write.
 *
 * Seats were also only ever added. Nothing released them when a booking was
 * cancelled, so cancelled bookings permanently consumed capacity until the event
 * read as sold out. `release` is the other half of that pair.
 */
export class EventSeatService {
    /**
     * Takes `qty` seats on an event, or throws without taking any.
     *
     * Runs inside `transaction` when given one so the reservation commits or
     * rolls back with the booking it belongs to; otherwise it manages its own.
     */
    static async reserve(
        eventId: string,
        qty: number,
        transaction?: Transaction
    ): Promise<{ filledSeats: number; remainingSeats: number | null }> {
        if (!eventId) throw new Error('EVENT_NOT_FOUND');
        const seats = Math.max(0, Math.floor(Number(qty) || 0));
        if (seats === 0) {
            const ad = await Ad.findByPk(eventId, { transaction });
            if (!ad) throw new Error('EVENT_NOT_FOUND');
            return {
                filledSeats: ad.filledSeats || 0,
                remainingSeats: ad.isUnlimited ? null : (ad.seatLimit || 0) - (ad.filledSeats || 0),
            };
        }

        const run = async (t: Transaction) => {
            // The lock is the whole point: it serialises every concurrent
            // reservation for this event so the remaining count each caller
            // reads is the count it actually gets to act on.
            const ad = await Ad.findByPk(eventId, {
                lock: t.LOCK.UPDATE,
                transaction: t,
            });
            if (!ad) throw new Error('EVENT_NOT_FOUND');
            if (ad.type !== 'Party') throw new Error('NOT_AN_EVENT');
            if (!ad.isActive) throw new Error('EVENT_INACTIVE');

            const filled = ad.filledSeats || 0;

            if (!ad.isUnlimited) {
                const limit = ad.seatLimit || 0;
                const remaining = limit - filled;
                if (remaining < seats) {
                    const err: any = new Error('EVENT_SOLD_OUT');
                    err.code = 'EVENT_SOLD_OUT';
                    err.remainingSeats = Math.max(0, remaining);
                    err.requestedSeats = seats;
                    throw err;
                }
            }

            const next = filled + seats;
            await ad.update({ filledSeats: next }, { transaction: t });

            return {
                filledSeats: next,
                remainingSeats: ad.isUnlimited ? null : (ad.seatLimit || 0) - next,
            };
        };

        if (transaction) return run(transaction);
        return sequelize.transaction(run);
    }

    /**
     * Gives `qty` seats back, clamped at zero so a double-release can never
     * drive the count negative and hand out capacity the event does not have.
     */
    static async release(
        eventId: string,
        qty: number,
        transaction?: Transaction
    ): Promise<number> {
        if (!eventId) return 0;
        const seats = Math.max(0, Math.floor(Number(qty) || 0));
        if (seats === 0) return 0;

        const run = async (t: Transaction) => {
            const ad = await Ad.findByPk(eventId, {
                lock: t.LOCK.UPDATE,
                transaction: t,
            });
            if (!ad) return 0;
            const next = Math.max(0, (ad.filledSeats || 0) - seats);
            await ad.update({ filledSeats: next }, { transaction: t });
            return next;
        };

        try {
            if (transaction) return await run(transaction);
            return await sequelize.transaction(run);
        } catch (err: any) {
            // A failed release must never fail the cancellation or refund it is
            // part of — the seats are recoverable, the refund is not.
            logger.error(`[EventSeatService] Failed to release ${seats} seat(s) on event ${eventId}: ${err?.message}`);
            return 0;
        }
    }

    /**
     * Releases whatever seats a party plan is currently holding on its event.
     *
     * A plan reaches a cancelled state through several different routes (host
     * cancels, joiner-approved cancellation, admin, expiry sweep), and some of
     * those can run more than once for the same plan. So the count is read and
     * zeroed under the same lock that releases it: the first caller takes the
     * seats to give back, every later caller finds zero and does nothing. That
     * makes the release idempotent no matter which path — or how many — gets
     * there.
     *
     * Returns the number of seats actually given back.
     */
    static async releaseForPlan(planId: string): Promise<number> {
        if (!planId) return 0;
        const PartyPlan = (await import('../models/PartyPlan')).default;

        try {
            return await sequelize.transaction(async (t) => {
                const plan: any = await PartyPlan.findByPk(planId, {
                    lock: t.LOCK.UPDATE,
                    transaction: t,
                });
                if (!plan || !plan.partyEventId) return 0;

                const held = Number(plan.eventSeatsReserved) || 0;
                if (held <= 0) return 0;

                await plan.update({ eventSeatsReserved: 0 }, { transaction: t });
                await EventSeatService.release(plan.partyEventId, held, t);
                return held;
            });
        } catch (err: any) {
            logger.error(`[EventSeatService] releaseForPlan failed for plan ${planId}: ${err?.message}`);
            return 0;
        }
    }

    /**
     * Gives back exactly one of a plan's seats — the joiner's — when the host
     * converts an unmatched plan into a solo ticket. Same read-zero-release
     * discipline as `releaseForPlan`, so it cannot release a seat twice.
     */
    static async releaseOneForPlan(planId: string): Promise<number> {
        if (!planId) return 0;
        const PartyPlan = (await import('../models/PartyPlan')).default;

        try {
            return await sequelize.transaction(async (t) => {
                const plan: any = await PartyPlan.findByPk(planId, {
                    lock: t.LOCK.UPDATE,
                    transaction: t,
                });
                if (!plan || !plan.partyEventId) return 0;

                const held = Number(plan.eventSeatsReserved) || 0;
                if (held <= 1) return 0;

                await plan.update({ eventSeatsReserved: held - 1 }, { transaction: t });
                await EventSeatService.release(plan.partyEventId, 1, t);
                return 1;
            });
        } catch (err: any) {
            logger.error(`[EventSeatService] releaseOneForPlan failed for plan ${planId}: ${err?.message}`);
            return 0;
        }
    }

    /** Remaining seats, or null when the event is unlimited. */
    static async remaining(eventId: string): Promise<number | null> {
        const ad = await Ad.findByPk(eventId);
        if (!ad) return 0;
        if (ad.isUnlimited) return null;
        return Math.max(0, (ad.seatLimit || 0) - (ad.filledSeats || 0));
    }
}

export default EventSeatService;
