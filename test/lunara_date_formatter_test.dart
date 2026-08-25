import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunara_app/utils/lunara_date_formatter.dart';

void main() {
  group('LunaraDateFormatter Unit Tests', () {
    test('normalizeTimeTo12Hour converts 24h and 12h formats to clean 12h strings', () {
      expect(LunaraDateFormatter.normalizeTimeTo12Hour('20:00'), '8:00 PM');
      expect(LunaraDateFormatter.normalizeTimeTo12Hour('08:00 PM'), '8:00 PM');
      expect(LunaraDateFormatter.normalizeTimeTo12Hour('8:00 PM'), '8:00 PM');
      expect(LunaraDateFormatter.normalizeTimeTo12Hour('8:00PM'), '8:00 PM');
      expect(LunaraDateFormatter.normalizeTimeTo12Hour('10:30'), '10:30 AM');
      expect(LunaraDateFormatter.normalizeTimeTo12Hour('10:30 AM'), '10:30 AM');
      expect(LunaraDateFormatter.normalizeTimeTo12Hour('00:00'), '12:00 AM');
      expect(LunaraDateFormatter.normalizeTimeTo12Hour('12:00 AM'), '12:00 AM');
      expect(LunaraDateFormatter.normalizeTimeTo12Hour('12:00'), '12:00 PM');
      expect(LunaraDateFormatter.normalizeTimeTo12Hour('12:00 PM'), '12:00 PM');
      expect(LunaraDateFormatter.normalizeTimeTo12Hour('23:45'), '11:45 PM');
    });

    test('parseToLocal handles date string with explicit time', () {
      final dt = LunaraDateFormatter.parseToLocal('2026-08-25', explicitTime: '8:00 PM');
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
      expect(dt.month, 8);
      expect(dt.day, 25);
      expect(dt.hour, 20);
      expect(dt.minute, 0);
    });

    test('formatEventTime returns correct 12h representation', () {
      final dt = DateTime(2026, 8, 25, 20, 0);
      expect(LunaraDateFormatter.formatEventTime(dt), '8:00 PM');

      final morningDt = DateTime(2026, 8, 25, 9, 30);
      expect(LunaraDateFormatter.formatEventTime(morningDt), '9:30 AM');
    });

    test('formatEventDateTime combines date and 12h time', () {
      final dt = DateTime(2026, 8, 25, 20, 0);
      expect(LunaraDateFormatter.formatEventDateTime(dt), '25 Aug 2026 • 8:00 PM');
    });

    test('formatToIsoUtc produces valid ISO-8601 UTC string', () {
      final date = DateTime(2026, 8, 25);
      const time = TimeOfDay(hour: 20, minute: 0);
      final iso = LunaraDateFormatter.formatToIsoUtc(date, time);

      expect(iso.contains('T'), isTrue);
      expect(iso.endsWith('Z'), isTrue);

      final parsed = DateTime.parse(iso).toLocal();
      expect(parsed.year, 2026);
      expect(parsed.month, 8);
      expect(parsed.day, 25);
      expect(parsed.hour, 20);
      expect(parsed.minute, 0);
    });
  });
}
