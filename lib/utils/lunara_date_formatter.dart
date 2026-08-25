import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Centralized Date & Time Utility for Lunara Mobile App
///
/// Rules:
/// 1. Internal/API canonical standard: UTC ISO-8601 strings.
/// 2. User-facing display: Always clean 12-hour format ('8:00 PM', '10:30 AM', '12:00 AM', '12:00 PM').
/// 3. Never hardcode manual offset arithmetic (+5:30) or brittle heuristic checks (hour == 5 && minute == 30).
/// 4. All countdowns and duration differences are computed using absolute UTC instants.
class LunaraDateFormatter {
  /// Converts any 24h or 12h time string ('20:00', '08:00 PM', '8:00 PM', '20:00:00') into
  /// a clean 12-hour display string ('8:00 PM').
  static String normalizeTimeTo12Hour(String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty) return '8:00 PM';
    final clean = timeStr.trim();
    final upper = clean.toUpperCase();

    if (upper.contains('AM') || upper.contains('PM')) {
      // Re-format to ensure consistent spacing ('8:00 PM' vs '8:00PM' vs '08:00 PM')
      final isPm = upper.contains('PM');
      final raw = upper.replaceAll('AM', '').replaceAll('PM', '').trim();
      final parts = raw.split(':');
      if (parts.isNotEmpty) {
        int h = int.tryParse(parts[0]) ?? (isPm ? 8 : 8);
        final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        if (h == 0) h = 12;
        final ampm = isPm ? 'PM' : 'AM';
        return '$h:${m.toString().padLeft(2, '0')} $ampm';
      }
      return clean;
    }

    final parts = clean.split(':');
    if (parts.isNotEmpty) {
      final h = int.tryParse(parts[0]) ?? 20;
      final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      final ampm = h >= 12 && h < 24 ? 'PM' : 'AM';
      final displayH = (h % 12 == 0) ? 12 : h % 12;
      return '$displayH:${m.toString().padLeft(2, '0')} $ampm';
    }

    return clean;
  }

  /// Parses any date / ISO string / DateTime object with an optional separate time string
  /// into a local DateTime instance representing the event time in the user's local timezone.
  static DateTime? parseToLocal(dynamic dateVal, {String? explicitTime}) {
    if (dateVal == null) return null;

    DateTime? baseDt;
    if (dateVal is DateTime) {
      baseDt = dateVal.toLocal();
    } else {
      final str = dateVal.toString().trim();
      if (str.isEmpty) return null;

      // Handle ISO strings
      final parsed = DateTime.tryParse(str);
      if (parsed != null) {
        baseDt = parsed.toLocal();
      } else {
        // Fallback: match YYYY-MM-DD
        final ymdMatch = RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(str);
        if (ymdMatch != null) {
          final y = int.parse(ymdMatch.group(1)!);
          final m = int.parse(ymdMatch.group(2)!);
          final d = int.parse(ymdMatch.group(3)!);
          baseDt = DateTime(y, m, d);
        } else {
          final dmyMatch = RegExp(r'(\d{1,2})[-/](\d{1,2})[-/](\d{4})').firstMatch(str);
          if (dmyMatch != null) {
            final d = int.parse(dmyMatch.group(1)!);
            final m = int.parse(dmyMatch.group(2)!);
            final y = int.parse(dmyMatch.group(3)!);
            baseDt = DateTime(y, m, d);
          }
        }
      }
    }

    if (baseDt == null) return null;

    // If explicitTime is provided, combine date parts with the explicit time
    if (explicitTime != null && explicitTime.trim().isNotEmpty) {
      final cleanTime = explicitTime.trim().toUpperCase();
      final isPm = cleanTime.contains('PM');
      final isAm = cleanTime.contains('AM');
      final timeOnly = cleanTime.replaceAll('AM', '').replaceAll('PM', '').trim();
      final parts = timeOnly.split(':');
      if (parts.isNotEmpty) {
        int h = int.tryParse(parts[0]) ?? 20;
        final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        if (isPm && h < 12) h += 12;
        if (isAm && h == 12) h = 0;
        return DateTime(baseDt.year, baseDt.month, baseDt.day, h, m);
      }
    }

    return baseDt;
  }

  /// Formats any date input into a 12-hour time string ('8:00 PM', '10:30 AM').
  static String formatEventTime(dynamic dateVal, {String? explicitTime, String fallback = '8:00 PM'}) {
    if (explicitTime != null && explicitTime.trim().isNotEmpty) {
      return normalizeTimeTo12Hour(explicitTime);
    }
    final dt = parseToLocal(dateVal);
    if (dt == null) return fallback;
    return DateFormat('h:mm a').format(dt);
  }

  /// Formats any date input into a clean date string ('Tue, 25 Aug 2026' or '25 Aug 2026').
  static String formatEventDate(dynamic dateVal, {String pattern = 'EEE, d MMM yyyy', String fallback = ''}) {
    final dt = parseToLocal(dateVal);
    if (dt == null) return fallback;
    return DateFormat(pattern).format(dt);
  }

  /// Formats combined date + time: '25 Aug 2026 • 8:00 PM'.
  static String formatEventDateTime(dynamic dateVal, {String? explicitTime, String fallback = ''}) {
    final dt = parseToLocal(dateVal, explicitTime: explicitTime);
    if (dt == null) return fallback;
    final datePart = DateFormat('d MMM yyyy').format(dt);
    final timePart = DateFormat('h:mm a').format(dt);
    return '$datePart • $timePart';
  }

  /// Calculates the exact remaining duration between now and the target event time.
  static Duration getRemainingDuration(dynamic targetDateVal, {String? explicitTime}) {
    final target = parseToLocal(targetDateVal, explicitTime: explicitTime);
    if (target == null) return Duration.zero;
    final diff = target.difference(DateTime.now());
    return diff;
  }

  /// Formats remaining time into a user-friendly countdown string:
  /// e.g. 'Starts in 2h 30m', 'Starts in 45m', 'Event started'.
  static String formatCountdown(dynamic targetDateVal, {String? explicitTime}) {
    final diff = getRemainingDuration(targetDateVal, explicitTime: explicitTime);
    if (diff.isNegative) {
      if (diff.inHours.abs() < 6) {
        return 'Live Now';
      }
      return 'Event ended';
    }

    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;

    if (days > 0) {
      return 'Starts in ${days}d ${hours}h';
    } else if (hours > 0) {
      return 'Starts in ${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return 'Starts in ${minutes}m';
    } else {
      return 'Starting soon';
    }
  }

  /// Converts a user's selected DateTime and TimeOfDay on mobile into a standard canonical
  /// UTC ISO-8601 string for sending to the API.
  static String formatToIsoUtc(DateTime date, TimeOfDay time) {
    final localDt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    return localDt.toUtc().toIso8601String();
  }
}
