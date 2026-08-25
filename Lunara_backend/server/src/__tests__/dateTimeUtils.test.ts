import {
    parseEventDateTimeToUTC,
    formatTime12Hour,
    formatDateFull,
    formatDateTimeFull,
    format12HourFromParts,
    parseTimeParts
} from '../utils/dateTimeUtils';

describe('dateTimeUtils Central Architecture', () => {
    describe('parseTimeParts', () => {
        it('should correctly parse 12-hour AM/PM formats', () => {
            expect(parseTimeParts('8:00 PM')).toEqual([20, 0]);
            expect(parseTimeParts('8:00 AM')).toEqual([8, 0]);
            expect(parseTimeParts('12:00 AM')).toEqual([0, 0]);
            expect(parseTimeParts('12:00 PM')).toEqual([12, 0]);
            expect(parseTimeParts('2:30 PM')).toEqual([14, 30]);
            expect(parseTimeParts('11:59 PM')).toEqual([23, 59]);
        });

        it('should correctly parse 24-hour formats', () => {
            expect(parseTimeParts('20:00')).toEqual([20, 0]);
            expect(parseTimeParts('08:00')).toEqual([8, 0]);
            expect(parseTimeParts('00:00')).toEqual([0, 0]);
            expect(parseTimeParts('14:30')).toEqual([14, 30]);
        });
    });

    describe('createDateInTimezone & parseEventDateTimeToUTC in Asia/Kolkata (+05:30)', () => {
        it('should convert 25 Aug 2026 8:00 PM IST to canonical UTC 14:30', () => {
            const utcDate = parseEventDateTimeToUTC('2026-08-25', '8:00 PM', 'Asia/Kolkata');
            expect(utcDate.toISOString()).toBe('2026-08-25T14:30:00.000Z');
        });

        it('should convert 25 Aug 2026 8:00 AM IST to canonical UTC 02:30', () => {
            const utcDate = parseEventDateTimeToUTC('2026-08-25', '8:00 AM', 'Asia/Kolkata');
            expect(utcDate.toISOString()).toBe('2026-08-25T02:30:00.000Z');
        });

        it('should convert 25 Aug 2026 12:00 AM (midnight) IST to canonical UTC 24 Aug 18:30', () => {
            const utcDate = parseEventDateTimeToUTC('2026-08-25', '12:00 AM', 'Asia/Kolkata');
            expect(utcDate.toISOString()).toBe('2026-08-24T18:30:00.000Z');
        });

        it('should convert 25 Aug 2026 12:00 PM (noon) IST to canonical UTC 06:30', () => {
            const utcDate = parseEventDateTimeToUTC('2026-08-25', '12:00 PM', 'Asia/Kolkata');
            expect(utcDate.toISOString()).toBe('2026-08-25T06:30:00.000Z');
        });

        it('should convert 25 Aug 2026 2:30 PM IST to canonical UTC 09:00', () => {
            const utcDate = parseEventDateTimeToUTC('2026-08-25', '2:30 PM', 'Asia/Kolkata');
            expect(utcDate.toISOString()).toBe('2026-08-25T09:00:00.000Z');
        });

        it('should convert 25 Aug 2026 11:59 PM IST to canonical UTC 18:29', () => {
            const utcDate = parseEventDateTimeToUTC('2026-08-25', '11:59 PM', 'Asia/Kolkata');
            expect(utcDate.toISOString()).toBe('2026-08-25T18:29:00.000Z');
        });
    });

    describe('formatTime12Hour & formatDateTimeFull in Asia/Kolkata', () => {
        it('should format UTC 2026-08-25T14:30:00.000Z back to 8:00 PM', () => {
            const timeStr = formatTime12Hour('2026-08-25T14:30:00.000Z', 'Asia/Kolkata');
            expect(timeStr.replace(/\s+/g, ' ')).toBe('8:00 PM');
        });

        it('should format UTC 2026-08-24T18:30:00.000Z back to 12:00 AM on 25 Aug', () => {
            const timeStr = formatTime12Hour('2026-08-24T18:30:00.000Z', 'Asia/Kolkata');
            const dateStr = formatDateFull('2026-08-24T18:30:00.000Z', 'Asia/Kolkata', false);
            expect(timeStr.replace(/\s+/g, ' ')).toBe('12:00 AM');
            expect(dateStr).toContain('Aug 25, 2026');
        });

        it('should format combined full date-time without drift', () => {
            const fullStr = formatDateTimeFull('2026-08-25T14:30:00.000Z', 'Asia/Kolkata');
            expect(fullStr).toContain('Aug 25, 2026');
            expect(fullStr).toContain('8:00 PM');
        });
    });

    describe('format12HourFromParts', () => {
        it('should format 24h hour/min to 12h representation', () => {
            expect(format12HourFromParts(20, 0)).toBe('8:00 PM');
            expect(format12HourFromParts(0, 0)).toBe('12:00 AM');
            expect(format12HourFromParts(12, 0)).toBe('12:00 PM');
            expect(format12HourFromParts(14, 30)).toBe('2:30 PM');
        });
    });
});
