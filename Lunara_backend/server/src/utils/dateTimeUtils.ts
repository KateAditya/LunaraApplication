/**
 * Centralized Date & Time Utility for Lunara Backend
 *
 * Rules:
 * 1. Database & Internal standard: Canonical UTC (Date objects / ISO-8601 UTC strings).
 * 2. Default event timezone: 'Asia/Kolkata'.
 * 3. User-facing display time: Clean 12-hour format ('8:00 PM', '10:30 AM', '12:00 AM', '12:00 PM').
 * 4. Never format with system-local toLocaleTimeString without explicit timeZone.
 */

export const DEFAULT_TIMEZONE = 'Asia/Kolkata';

export interface DateParts {
    year: number;
    month: number; // 1-12
    day: number;
    hour: number;  // 0-23
    minute: number;
    second: number;
}

/**
 * Normalizes any time string ('8:00 PM', '08:00 PM', '20:00', '8:00') into 24-hour [hours, minutes].
 */
export function parseTimeParts(timeStr?: string | null): [number, number] {
    if (!timeStr || !timeStr.trim()) return [20, 0]; // default 8:00 PM (20:00)
    const clean = timeStr.trim().toUpperCase();
    const isPm = clean.includes('PM');
    const isAm = clean.includes('AM');

    if (isPm || isAm) {
        const timeOnly = clean.replace('AM', '').replace('PM', '').trim();
        const parts = timeOnly.split(':');
        if (parts.length >= 1) {
            let h = parseInt(parts[0], 10);
            if (isNaN(h)) h = isPm ? 20 : 8;
            const m = parts.length > 1 ? parseInt(parts[1], 10) || 0 : 0;
            if (isPm && h < 12) h += 12;
            if (isAm && h === 12) h = 0;
            return [h, m];
        }
    }

    const parts = clean.split(':');
    if (parts.length >= 1) {
        const h = parseInt(parts[0], 10);
        const m = parts.length > 1 ? parseInt(parts[1], 10) || 0 : 0;
        return [isNaN(h) ? 20 : h, m];
    }

    return [20, 0];
}

const MONTH_MAP: Record<string, number> = {
    jan: 1, january: 1,
    feb: 2, february: 2,
    mar: 3, march: 3,
    apr: 4, april: 4,
    may: 5,
    jun: 6, june: 6,
    jul: 7, july: 7,
    aug: 8, august: 8,
    sep: 9, sept: 9, september: 9,
    oct: 10, october: 10,
    nov: 11, november: 11,
    dec: 12, december: 12,
};

/**
 * Extracts [year, month (1-12), day] from any Date object or date string.
 * Accurately parses standard formats (YYYY-MM-DD, DD-MM-YYYY), ISO timestamps,
 * natural language strings ("Wed, 16 Sep", "16 Sep 2026", "Sep 16"), and relative keywords ("Tonight", "Tomorrow").
 */
export function extractDateParts(dateInput: Date | string, timezone: string = DEFAULT_TIMEZONE): [number, number, number] {
    if (dateInput instanceof Date && !isNaN(dateInput.getTime())) {
        const formatter = new Intl.DateTimeFormat('en-US', {
            timeZone: timezone,
            year: 'numeric',
            month: 'numeric',
            day: 'numeric',
        });
        const parts = formatter.formatToParts(dateInput);
        let y = dateInput.getFullYear();
        let m = dateInput.getMonth() + 1;
        let d = dateInput.getDate();
        for (const p of parts) {
            if (p.type === 'year') y = parseInt(p.value, 10);
            if (p.type === 'month') m = parseInt(p.value, 10);
            if (p.type === 'day') d = parseInt(p.value, 10);
        }
        return [y, m, d];
    }

    const rawStr = String(dateInput || '').trim();
    if (!rawStr) {
        const now = new Date();
        return extractDateParts(now, timezone);
    }

    const lower = rawStr.toLowerCase();

    // 1. Relative keyword handling
    if (lower.includes('tonight') || lower.includes('today')) {
        return extractDateParts(new Date(), timezone);
    }
    if (lower.includes('tomorrow')) {
        const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000);
        return extractDateParts(tomorrow, timezone);
    }
    if (lower.includes('yesterday')) {
        const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
        return extractDateParts(yesterday, timezone);
    }

    // 2. YYYY-MM-DD or YYYY/MM/DD
    const ymdMatch = rawStr.match(/(\d{4})[-/](\d{1,2})[-/](\d{1,2})/);
    if (ymdMatch) {
        return [parseInt(ymdMatch[1], 10), parseInt(ymdMatch[2], 10), parseInt(ymdMatch[3], 10)];
    }

    // 3. DD-MM-YYYY or DD/MM/YYYY
    const dmyMatch = rawStr.match(/(\d{1,2})[-/](\d{1,2})[-/](\d{4})/);
    if (dmyMatch) {
        return [parseInt(dmyMatch[3], 10), parseInt(dmyMatch[2], 10), parseInt(dmyMatch[1], 10)];
    }

    // Reference current date in target timezone
    const [currY, currM] = extractDateParts(new Date(), timezone);

    // 4. Natural text: Day Month [Year] (e.g. "16 Sep", "Wed, 16 Sep 2026", "16th September", "16-Sep-2026")
    const dayMonthMatch = rawStr.match(/(\b\d{1,2})(?:st|nd|rd|th)?\s*[-/, ]\s*([a-zA-Z]{3,9})(?:\s*[-/, ]\s*(\d{4}))?/i);
    if (dayMonthMatch) {
        const day = parseInt(dayMonthMatch[1], 10);
        const monthKey = dayMonthMatch[2].toLowerCase();
        const month = MONTH_MAP[monthKey];
        if (month && day >= 1 && day <= 31) {
            let year = dayMonthMatch[3] ? parseInt(dayMonthMatch[3], 10) : currY;
            if (!dayMonthMatch[3] && month < currM - 6) {
                year = currY + 1;
            }
            return [year, month, day];
        }
    }

    // 5. Natural text: Month Day [Year] (e.g. "Sep 16", "September 16, 2026", "Sep 16th")
    const monthDayMatch = rawStr.match(/([a-zA-Z]{3,9})\s*[-/, ]\s*(\b\d{1,2})(?:st|nd|rd|th)?(?:\s*[-/, ]\s*(\d{4}))?/i);
    if (monthDayMatch) {
        const monthKey = monthDayMatch[1].toLowerCase();
        const month = MONTH_MAP[monthKey];
        const day = parseInt(monthDayMatch[2], 10);
        if (month && day >= 1 && day <= 31) {
            let year = monthDayMatch[3] ? parseInt(monthDayMatch[3], 10) : currY;
            if (!monthDayMatch[3] && month < currM - 6) {
                year = currY + 1;
            }
            return [year, month, day];
        }
    }

    // 6. Native JS Date parse fallback
    const parsed = new Date(rawStr);
    if (!isNaN(parsed.getTime())) {
        return extractDateParts(parsed, timezone);
    }

    return extractDateParts(new Date(), timezone);
}

/**
 * Calculates the UTC Date from local Date components in a specific timezone.
 * Uses Intl to accurately resolve the timezone offset (including DST if applicable).
 */
export function createDateInTimezone(year: number, month: number, day: number, hour: number, minute: number, second: number = 0, timezone: string = DEFAULT_TIMEZONE): Date {
    // 1. Create a baseline UTC timestamp
    const utcGuess = new Date(Date.UTC(year, month - 1, day, hour, minute, second));

    // 2. Format the guess in target timezone to see how far off it is
    const formatter = new Intl.DateTimeFormat('en-US', {
        timeZone: timezone,
        year: 'numeric',
        month: 'numeric',
        day: 'numeric',
        hour: 'numeric',
        minute: 'numeric',
        second: 'numeric',
        hour12: false,
    });

    const parts = formatter.formatToParts(utcGuess);
    let tY = year, tM = month, tD = day, tH = hour, tMin = minute, tS = second;
    for (const p of parts) {
        if (p.type === 'year') tY = parseInt(p.value, 10);
        if (p.type === 'month') tM = parseInt(p.value, 10);
        if (p.type === 'day') tD = parseInt(p.value, 10);
        if (p.type === 'hour') tH = parseInt(p.value, 10);
        if (p.type === 'minute') tMin = parseInt(p.value, 10);
        if (p.type === 'second') tS = parseInt(p.value, 10);
    }

    // Correct for midnight / 24 hour representation
    if (tH === 24) tH = 0;

    const formattedAsUtc = Date.UTC(tY, tM - 1, tD, tH, tMin, tS);
    const offsetMs = formattedAsUtc - utcGuess.getTime();

    // 3. Exact target UTC instant
    return new Date(utcGuess.getTime() - offsetMs);
}

/**
 * Robustly parses any bookingDate / eventDateTime input (plus optional startTime string)
 * into a canonical UTC Date representing the intended local event time in the given timezone.
 */
export function parseEventDateTimeToUTC(dateInput: Date | string, startTimeStr?: string | null, timezone: string = DEFAULT_TIMEZONE): Date {
    if (!dateInput) return new Date();

    // Check if dateInput itself contains a time string if startTimeStr is not explicitly provided
    let effectiveTimeStr = startTimeStr;
    if (!effectiveTimeStr && typeof dateInput === 'string') {
        const timeMatch = dateInput.match(/(\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)/);
        if (timeMatch) {
            effectiveTimeStr = timeMatch[1];
        }
    }

    // If explicit or extracted startTimeStr is present, combine date with that time
    if (effectiveTimeStr && effectiveTimeStr.trim()) {
        const [year, month, day] = extractDateParts(dateInput, timezone);
        const [hours, minutes] = parseTimeParts(effectiveTimeStr);
        return createDateInTimezone(year, month, day, hours, minutes, 0, timezone);
    }

    // If no explicit time provided, but dateInput is a Date instance with time or ISO string with T
    if (dateInput instanceof Date) {
        if (!isNaN(dateInput.getTime())) {
            return dateInput;
        }
    } else if (typeof dateInput === 'string' && dateInput.trim()) {
        const str = dateInput.trim();
        if (str.includes('T')) {
            const parsed = new Date(str);
            if (!isNaN(parsed.getTime())) {
                return parsed;
            }
        }
    }

    const [year, month, day] = extractDateParts(dateInput, timezone);
    // Default to 20:00 (8:00 PM) for event dates where no time is provided
    return createDateInTimezone(year, month, day, 20, 0, 0, timezone);
}

/**
 * Formats any Date or ISO string into a user-facing 12-hour time string ('8:00 PM', '10:30 AM').
 * Always respects the specified timezone.
 */
export function formatTime12Hour(dateInput: Date | string | null | undefined, timezone: string = DEFAULT_TIMEZONE): string {
    if (!dateInput) return '8:00 PM';
    const d = dateInput instanceof Date ? dateInput : new Date(dateInput);
    if (isNaN(d.getTime())) return '8:00 PM';

    const formatter = new Intl.DateTimeFormat('en-US', {
        timeZone: timezone,
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
    });

    return formatter.format(d);
}

/**
 * Formats a Date or ISO string into a clean date string ('Tue, 25 Aug 2026' or '25 Aug 2026').
 */
export function formatDateFull(dateInput: Date | string | null | undefined, timezone: string = DEFAULT_TIMEZONE, includeWeekday: boolean = true): string {
    if (!dateInput) return '';
    const d = dateInput instanceof Date ? dateInput : new Date(dateInput);
    if (isNaN(d.getTime())) return '';

    const options: Intl.DateTimeFormatOptions = {
        timeZone: timezone,
        year: 'numeric',
        month: 'short',
        day: '2-digit',
    };
    if (includeWeekday) {
        options.weekday = 'short';
    }

    return new Intl.DateTimeFormat('en-US', options).format(d);
}

/**
 * Formats combined date + time: 'Tue, 25 Aug 2026 • 8:00 PM'.
 */
export function formatDateTimeFull(dateInput: Date | string | null | undefined, timezone: string = DEFAULT_TIMEZONE): string {
    if (!dateInput) return '';
    const d = dateInput instanceof Date ? dateInput : new Date(dateInput);
    if (isNaN(d.getTime())) return '';

    const dateStr = formatDateFull(d, timezone, true);
    const timeStr = formatTime12Hour(d, timezone);
    return `${dateStr} • ${timeStr}`;
}

/**
 * Formats 24h hours and minutes into clean 12h string directly.
 */
export function format12HourFromParts(hours: number, minutes: number): string {
    const ampm = hours >= 12 && hours < 24 ? 'PM' : 'AM';
    const h = hours % 12 === 0 ? 12 : hours % 12;
    return `${h}:${String(minutes || 0).padStart(2, '0')} ${ampm}`;
}
