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
    eventDateTime: Date | string
): { isValid: boolean; reason?: string } => {
    try {
        const date = new Date(eventDateTime);
        if (isNaN(date.getTime())) {
            return { isValid: false, reason: 'Invalid date format' };
        }

        // We need to work in the local timezone of the venue (assuming India IST +05:30 for Lunara)
        // Since the Node server might run in UTC or another timezone, we'll extract the local time components.
        // A simple way is to use the Date object which uses the server's local time, but to be safe, 
        // let's format it in Asia/Kolkata explicitly.
        
        const formatter = new Intl.DateTimeFormat('en-US', {
            timeZone: 'Asia/Kolkata',
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            weekday: 'short',
            hour12: false
        });

        // Parts looks like: [ { type: 'weekday', value: 'Sat' }, ..., { type: 'hour', value: '01' } ]
        const parts = formatter.formatToParts(date);
        const getPart = (type: string) => parts.find(p => p.type === type)?.value || '';

        const year = parseInt(getPart('year'));
        const month = parseInt(getPart('month')) - 1; // 0-indexed
        const day = parseInt(getPart('day'));
        const hour = parseInt(getPart('hour'));
        const minute = parseInt(getPart('minute'));

        // Reconstruct local date for business logic
        const localDate = new Date(year, month, day, hour, minute);
        
        // Nightlife venues often operate past midnight. 
        // If the time is before 6 AM, it belongs to the previous business day.
        const businessDate = new Date(localDate);
        if (hour < 6) {
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

        // 3. Check operating hours
        if (venue.openingTime && venue.closingTime) {
            const [openHour, openMin] = venue.openingTime.split(':').map(Number);
            const [closeHour, closeMin] = venue.closingTime.split(':').map(Number);

            // Convert everything to minutes from the start of the business day
            // e.g., 18:00 -> 1080
            // e.g., 02:00 -> 120 + 1440 = 1560 (since it's next day)
            let openTimeMins = openHour * 60 + openMin;
            let closeTimeMins = closeHour * 60 + closeMin;
            if (closeTimeMins < openTimeMins) {
                closeTimeMins += 24 * 60; // Next day
            }

            let eventTimeMins = hour * 60 + minute;
            if (hour < 6 && closeTimeMins > 24 * 60) {
                eventTimeMins += 24 * 60; // Next day relative to business day
            } else if (hour < openHour && closeTimeMins <= 24 * 60) {
                 // Early morning event but venue doesn't close past midnight, this means it's outside hours.
                 eventTimeMins -= 24 * 60; // Push back to show it's before open
            } else if (hour < 6 && hour >= closeHour) {
                eventTimeMins += 24 * 60;
            }

            if (eventTimeMins < openTimeMins || eventTimeMins >= closeTimeMins) {
                // Determine AM/PM formatted strings for nice error messages
                const formatTime = (h: number, m: number) => {
                    const ampm = h >= 12 && h < 24 ? 'PM' : 'AM';
                    const displayH = h % 12 === 0 ? 12 : h % 12;
                    return `${displayH}:${String(m).padStart(2, '0')} ${ampm}`;
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
