import { EventTimeLockService, TimeLockConflict, parseBookingDateTime } from '../services/EventTimeLockService';

export class TimeLockError extends Error {
    public timeLock: TimeLockConflict;
    public code: string = 'FOUR_HOUR_TIME_LOCK';
    public reason: string = 'FOUR_HOUR_TIME_LOCK';

    constructor(timeLock: TimeLockConflict) {
        super(timeLock.message);
        this.name = 'TimeLockError';
        this.timeLock = timeLock;
    }
}

/**
 * Universal Event Booking Limit & Time Lock Validator
 * Delegates to EventTimeLockService to enforce the strict 4-hour gap rule
 * across Party Plan, Group Party, Stranger Meet, Solo Booking, and Large Party.
 *
 * Returns an error message string if a conflict exists (< 4 hours gap), otherwise null.
 */
export const checkExistingBookingForDate = async (
    userId: string,
    dateInput: Date | string,
    forType?: 'party_plan' | 'strangers_meet' | 'group_party' | 'booking' | string,
    startTimeStr?: string
): Promise<string | null> => {
    try {
        const targetDate = parseBookingDateTime(dateInput, startTimeStr);
        if (!targetDate || isNaN(targetDate.getTime())) {
            return null; // Let standard payload validation handle invalid dates
        }

        const mapType = (forType || 'party_plan').toLowerCase();
        let normalizedType: 'party_plan' | 'group_party' | 'stranger_meet' | 'solo_booking' | 'large_party' = 'party_plan';
        if (mapType.includes('group')) normalizedType = 'group_party';
        else if (mapType.includes('stranger')) normalizedType = 'stranger_meet';
        else if (mapType.includes('solo')) normalizedType = 'solo_booking';
        else if (mapType.includes('large')) normalizedType = 'large_party';

        const result = await EventTimeLockService.validateFourHourGap(userId, targetDate, normalizedType);

        if (!result.allowed) {
            return result.message;
        }

        return null;
    } catch (error) {
        // Fallback: log error and allow continuation if validator hits unexpected system issue
        console.error('Error in checkExistingBookingForDate time-lock validation:', error);
        return null;
    }
};

/**
 * Validates universal 4-hour time lock and throws TimeLockError if conflict is found.
 */
export const validateTimeLockOrThrow = async (
    userId: string,
    dateInput: Date | string,
    forType: 'party_plan' | 'strangers_meet' | 'group_party' | 'booking' | 'solo_booking' | 'large_party' | string,
    startTimeStr?: string,
    excludeEventId?: string
): Promise<void> => {
    const targetDate = parseBookingDateTime(dateInput, startTimeStr);
    if (!targetDate || isNaN(targetDate.getTime())) return;

    const mapType = (forType || 'party_plan').toLowerCase();
    let normalizedType: 'party_plan' | 'group_party' | 'stranger_meet' | 'solo_booking' | 'large_party' = 'party_plan';
    if (mapType.includes('group')) normalizedType = 'group_party';
    else if (mapType.includes('stranger')) normalizedType = 'stranger_meet';
    else if (mapType.includes('solo')) normalizedType = 'solo_booking';
    else if (mapType.includes('large')) normalizedType = 'large_party';

    const result = await EventTimeLockService.validateFourHourGap(userId, targetDate, normalizedType, excludeEventId);
    if (!result.allowed) {
        throw new TimeLockError(result);
    }
};

export default checkExistingBookingForDate;
