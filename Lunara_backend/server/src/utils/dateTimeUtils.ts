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

/**
 * Extracts [year, month (1-12), day] from any Date object or date string.
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

    const str = String(dateInput || '').trim();
    // Match YYYY-MM-DD
    const ymdMatch = str.match(/(\d{4})[-/](\d{1,2})[-/](\d{1,2})/);
    if (ymdMatch) {
        return [parseInt(ymdMatch[1], 10), parseInt(ymdMatch[2], 10), parseInt(ymdMatch[3], 10)];
    }

    // Match DD-MM-YYYY
    const dmyMatch = str.match(/(\d{1,2})[-/](\d{1,2})[-/](\d{4})/);
    if (dmyMatch) {
        return [parseInt(dmyMatch[3], 10), parseInt(dmyMatch[2], 10), parseInt(dmyMatch[1], 10)];
    }

    const parsed = new Date(str);
    if (!isNaN(parsed.getTime())) {
        return extractDateParts(parsed, timezone);
    }

    const now = new Date();
    return [now.getFullYear(), now.getMonth() + 1, now.getDate()];
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

    // If input is already an ISO string with explicit time and NO separate startTime is passed
    if (typeof dateInput === 'string' && dateInput.includes('T') && (!startTimeStr || !startTimeStr.trim())) {
        const parsed = new Date(dateInput);
        if (!isNaN(parsed.getTime())) {
            return parsed;
        }
    }

    const [year, month, day] = extractDateParts(dateInput, timezone);
    const [hours, minutes] = parseTimeParts(startTimeStr);

    return createDateInTimezone(year, month, day, hours, minutes, 0, timezone);
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
