import 'package:flutter/material.dart';

class VenueTimingErrorDialog extends StatelessWidget {
  final String venueName;
  final List<dynamic>? daysOpen;
  final String? openingTime;
  final String? closingTime;
  final List<dynamic>? closedDates;

  const VenueTimingErrorDialog({
    super.key,
    required this.venueName,
    this.daysOpen,
    this.openingTime,
    this.closingTime,
    this.closedDates,
  });

  static void show(
    BuildContext context, {
    required String venueName,
    List<dynamic>? daysOpen,
    String? openingTime,
    String? closingTime,
    List<dynamic>? closedDates,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => VenueTimingErrorDialog(
        venueName: venueName,
        daysOpen: daysOpen,
        openingTime: openingTime,
        closingTime: closingTime,
        closedDates: closedDates,
      ),
    );
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 'N/A';
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        final ampm = hour >= 12 ? 'PM' : 'AM';
        final formattedHour = hour % 12 == 0 ? 12 : hour % 12;
        final formattedMinute = minute.toString().padLeft(2, '0');
        return '$formattedHour:$formattedMinute $ampm';
      }
    } catch (_) {}
    return timeStr;
  }

  @override
  Widget build(BuildContext context) {
    final String openHours = (openingTime != null && closingTime != null)
        ? '${_formatTime(openingTime)} - ${_formatTime(closingTime)}'
        : 'Not Specified';

    final String openDays = (daysOpen != null && daysOpen!.isNotEmpty)
        ? daysOpen!.join(', ')
        : 'Everyday';

    final String holidays = (closedDates != null && closedDates!.isNotEmpty)
        ? closedDates!.join(', ')
        : 'None scheduled';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 10,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.alarm_off_rounded,
                color: Colors.red.shade700,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Timing Conflict',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.black87,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your selected date or time is not available for $venueName. Please check the venue schedule below:',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  _buildScheduleRow(
                    'Open Days',
                    openDays,
                    Icons.calendar_month_rounded,
                  ),
                  const Divider(height: 16),
                  _buildScheduleRow(
                    'Working Hours',
                    openHours,
                    Icons.access_time_filled_rounded,
                  ),
                  if (closedDates != null && closedDates!.isNotEmpty) ...[
                    const Divider(height: 16),
                    _buildScheduleRow(
                      'Closed Dates (Holidays)',
                      holidays,
                      Icons.event_busy_rounded,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Select Proper Time & Date',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF7C3AED)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
