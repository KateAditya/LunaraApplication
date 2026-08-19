import { Op } from 'sequelize';
import { PartyPlan, StrangersMeetRequest, GroupParty, Booking } from '../models';

/**
 * Checks if the user already has a Party Plan, Strangers Meet, or Group Party
 * scheduled for the given date.
 * Returns the error message string if a conflict exists, otherwise null.
 */
export const checkExistingBookingForDate = async (
    userId: string,
    dateInput: Date | string,
    forType?: 'party_plan' | 'strangers_meet' | 'group_party' | 'booking' | string
): Promise<string | null> => {
    try {
        const targetDate = typeof dateInput === 'string' ? new Date(dateInput) : dateInput;
        if (isNaN(targetDate.getTime())) {
            return null; // Invalid date, skip validation to let standard validators catch it
        }

        // Define start and end of that day in UTC/server timezone
        const startOfDay = new Date(targetDate);
        startOfDay.setHours(0, 0, 0, 0);
        const endOfDay = new Date(targetDate);
        endOfDay.setHours(23, 59, 59, 999);

        // Format targetDate string for DATEONLY matching in PostgreSQL (YYYY-MM-DD)
        const yyyy = targetDate.getFullYear();
        const mm = String(targetDate.getMonth() + 1).padStart(2, '0');
        const dd = String(targetDate.getDate()).padStart(2, '0');
        const dateStr = `${yyyy}-${mm}-${dd}`;

        // 1. Check PartyPlan (checks 4-hour cooldown time window)
        if (!forType || forType === 'party_plan') {
            const fourHoursMs = 4 * 60 * 60 * 1000;
            const windowStart = new Date(targetDate.getTime() - fourHoursMs);
            const windowEnd = new Date(targetDate.getTime() + fourHoursMs);

            const existingPartyPlan = await PartyPlan.findOne({
                where: {
                    userId,
                    status: { [Op.ne]: 'cancelled' },
                    planDateTime: {
                        [Op.between]: [windowStart, windowEnd]
                    }
                }
            });
            if (existingPartyPlan) {
                const planTime = new Date(existingPartyPlan.planDateTime);
                const timeStr = planTime.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
                return `You already have a party plan scheduled near this time (${timeStr}). Party plans must be at least 4 hours apart.`;
            }
        }

        // 2. Check StrangersMeetRequest
        if (!forType || forType === 'strangers_meet') {
            const existingStrangersMeet = await StrangersMeetRequest.findOne({
                where: {
                    userId,
                    status: { [Op.notIn]: ['cancelled', 'rejected'] },
                    eventDateTime: {
                        [Op.between]: [startOfDay, endOfDay]
                    }
                }
            });
            if (existingStrangersMeet) {
                return 'You already have a strangers meetup scheduled on this day.';
            }
        }

        // 3. Check GroupParty
        if (!forType || forType === 'group_party') {
            const existingGroupParty = await GroupParty.findOne({
                where: {
                    userId,
                    status: { [Op.notIn]: ['cancelled', 'rejected', 'pending', 'expired'] },
                    partyDate: dateStr
                }
            });
            if (existingGroupParty) {
                return 'You already have a group party booked on this day.';
            }

            // 4. Check Booking (where goingMode = 'party_request')
            const existingLargePartyBooking = await Booking.findOne({
                where: {
                    userId,
                    status: { [Op.ne]: 'cancelled' },
                    goingMode: 'party_request',
                    bookingDate: dateStr
                }
            });
            if (existingLargePartyBooking) {
                return 'You already have a group party booked on this day.';
            }
        }

        return null;
    } catch (error) {
        // Fallback: log the error and allow booking creation rather than breaking completely
        return null;
    }
};
