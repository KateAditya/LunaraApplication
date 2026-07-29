import { VenueAttributes } from '../models/Venue';
import { logger } from '../config/logger';

/**
 * Validates if a proposed event date/time is valid for a given venue's operating hours and holidays.
 * @param venue The venue object containing openingTime, closingTime, daysOpen, and closedDates
 * @param eventDateTime The proposed date/time for the event
 * @returns { isValid: boolean, reason?: string }
 */
export const validateVenueTimingAndHolidays = (
    venue: Partial<VenueAttributes>,
    eventDateTime: Date | string,
    startTime?: string
): { isValid: boolean; reason?: string } => {
    try {
        let year: number;
        let month: number;
        let day: number;
        let hour: number | null = null;
        let minute: number | null = null;

        // If a separate startTime (e.g. '20:00' or '19:30') is passed alongside a date string or object
        let combinedString: string | null = null;
        if (typeof eventDateTime === 'string') {
            const trimmed = eventDateTime.trim();
            if (startTime && /^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
                combinedString = `${trimmed}T${startTime.trim()}:00`;
            } else {
                combinedString = trimmed;
            }
        }

        const inputStr = combinedString || (typeof eventDateTime === 'string' ? eventDateTime.trim() : null);

        if (inputStr) {
            const hasTimezone = /Z|[+-]\d{2}(:?\d{2})?$/.test(inputStr);
            const matchFull = !hasTimezone ? inputStr.match(/^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})/) : null;
            if (matchFull) {
                year = parseInt(matchFull[1], 10);
                month = parseInt(matchFull[2], 10) - 1;
                day = parseInt(matchFull[3], 10);
                hour = parseInt(matchFull[4], 10);
                minute = parseInt(matchFull[5], 10);
            } else {
                const matchDateOnly = inputStr.match(/^(\d{4})-(\d{2})-(\d{2})$/);
                if (matchDateOnly) {
                    year = parseInt(matchDateOnly[1], 10);
                    month = parseInt(matchDateOnly[2], 10) - 1;
                    day = parseInt(matchDateOnly[3], 10);
                    if (startTime && startTime.includes(':')) {
                        const [sH, sM] = startTime.split(':').map(Number);
                        hour = sH;
                        minute = sM || 0;
                    } else {
                        hour = null;
                        minute = null;
                    }
                } else {
                    const date = new Date(inputStr);
                    if (isNaN(date.getTime())) {
                        return { isValid: false, reason: 'Invalid date format' };
                    }
                    const formatter = new Intl.DateTimeFormat('en-US', {
                        timeZone: 'Asia/Kolkata',
                        year: 'numeric',
                        month: '2-digit',
                        day: '2-digit',
                        hour: '2-digit',
                        minute: '2-digit',
                        hour12: false
                    });
                    const parts = formatter.formatToParts(date);
                    const getPart = (type: string) => parts.find(p => p.type === type)?.value || '';
                    year = parseInt(getPart('year'), 10);
                    month = parseInt(getPart('month'), 10) - 1;
                    day = parseInt(getPart('day'), 10);
                    hour = parseInt(getPart('hour'), 10);
                    minute = parseInt(getPart('minute'), 10);
                }
            }
        } else {
            const date = eventDateTime as Date;
            if (isNaN(date.getTime())) {
                return { isValid: false, reason: 'Invalid date format' };
            }
            const formatter = new Intl.DateTimeFormat('en-US', {
                timeZone: 'Asia/Kolkata',
                year: 'numeric',
                month: '2-digit',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit',
                hour12: false
            });
            const parts = formatter.formatToParts(date);
            const getPart = (type: string) => parts.find(p => p.type === type)?.value || '';
            year = parseInt(getPart('year'), 10);
            month = parseInt(getPart('month'), 10) - 1;
            day = parseInt(getPart('day'), 10);
            hour = parseInt(getPart('hour'), 10);
            minute = parseInt(getPart('minute'), 10);
        }

        // Reconstruct local date for business logic
        const evalHour = hour !== null ? hour : 12;
        const evalMinute = minute !== null ? minute : 0;
        const localDate = new Date(year, month, day, evalHour, evalMinute);
        
        // Nightlife venues operate past midnight. 
        // If the time is before 6 AM, it belongs to the previous business day.
        const businessDate = new Date(localDate);
        if (hour !== null && hour < 6) {
            businessDate.setDate(businessDate.getDate() - 1);
        }

        // Get business day of week (Mon, Tue, Wed, Thu, Fri, Sat, Sun)
        const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        const businessDayOfWeek = days[businessDate.getDay()];

        // Get business date string YYYY-MM-DD
        const yyyy = businessDate.getFullYear();
        const mm = String(businessDate.getMonth() + 1).padStart(2, '0');
        const dd = String(businessDate.getDate()).padStart(2, '0');
        const businessDateStr = `${yyyy}-${mm}-${dd}`;

        // 1. Check if closed on this business date (Holidays)
        if (venue.closedDates && Array.isArray(venue.closedDates)) {
            if (venue.closedDates.includes(businessDateStr)) {
                return { isValid: false, reason: `The venue is closed on ${businessDateStr} (Holiday).` };
            }
        }

        // 2. Check if open on this day of the week
        if (venue.daysOpen && Array.isArray(venue.daysOpen)) {
            if (!venue.daysOpen.includes(businessDayOfWeek)) {
                return { isValid: false, reason: `The venue is not open on ${businessDayOfWeek}s.` };
            }
        }

        // 3. Check operating hours if explicit hour was provided
        if (hour !== null && venue.openingTime && venue.closingTime) {
            const [openHour, openMin] = venue.openingTime.split(':').map(Number);
            const [closeHour, closeMin] = venue.closingTime.split(':').map(Number);

            let openMins = openHour * 60 + (openMin || 0);
            let closeMins = closeHour * 60 + (closeMin || 0);
            const isOvernight = closeMins <= openMins;
            if (isOvernight) {
                closeMins += 24 * 60; // Extend past midnight (e.g. 02:00 -> 26:00 = 1560 mins)
            }

            let eventMins = hour * 60 + (minute || 0);
            if (isOvernight && hour < 6) {
                eventMins += 24 * 60; // Early morning (e.g. 1 AM = 25:00 = 1500 mins)
            }

            if (eventMins < openMins || eventMins >= closeMins) {
                const formatTime = (h: number, m: number) => {
                    const ampm = h >= 12 && h < 24 ? 'PM' : 'AM';
                    const displayH = h % 12 === 0 ? 12 : h % 12;
                    return `${displayH}:${String(m || 0).padStart(2, '0')} ${ampm}`;
                };
                
                const displayOpen = formatTime(openHour, openMin);
                const displayClose = formatTime(closeHour, closeMin);
                
                return { 
                    isValid: false, 
                    reason: `Selected time is outside venue operating hours. The venue is open from ${displayOpen} to ${displayClose}.` 
                };
            }
        }

        return { isValid: true };
    } catch (err) {
        logger.error('Error in validateVenueTimingAndHolidays:', err);
        return { isValid: false, reason: 'Failed to validate venue timings. Please try again.' };
    }
};
