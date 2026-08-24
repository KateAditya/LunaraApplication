import 'package:flutter/material.dart';

class TimeLockBlockedDialog extends StatelessWidget {
  final String conflictingEventType;
  final String conflictingEventTitle;
  final String conflictingDateTime;
  final String nextAvailableTime;
  final String message;
  final VoidCallback? onViewExistingPlan;

  const TimeLockBlockedDialog({
    super.key,
    required this.conflictingEventType,
    required this.conflictingEventTitle,
    required this.conflictingDateTime,
    required this.nextAvailableTime,
    required this.message,
    this.onViewExistingPlan,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> errorData,
    VoidCallback? onViewExistingPlan,
  }) async {
    String eventType = (errorData['conflictingEventType'] ?? '').toString().replaceAll('_', ' ').trim();
    String eventTitle = errorData['conflictingEventTitle']?.toString().trim() ?? '';
    String dateTimeRaw = errorData['conflictingDateTime']?.toString().trim() ?? '';
    String nextTimeRaw = errorData['nextAvailableTime']?.toString().trim() ?? '';
    final message = errorData['message']?.toString() ?? 'Your next event must be at least 4 hours apart.';

    // Try parsing from message if fields are missing
    if (message.isNotEmpty) {
      final match1 = RegExp(
        r'You already have a\s+(.+?)\s+scheduled for\s+([^.]+)',
        caseSensitive: false,
      ).firstMatch(message);
      if (match1 != null) {
        if (eventType.isEmpty) eventType = match1.group(1) ?? '';
        if (dateTimeRaw.isEmpty) dateTimeRaw = match1.group(2)?.trim() ?? '';
      }

      final match2 = RegExp(
        r'earliest available:\s*([^)]+)',
        caseSensitive: false,
      ).firstMatch(message);
      if (match2 != null && nextTimeRaw.isEmpty) {
        nextTimeRaw = match2.group(1)?.trim() ?? '';
      }
    }

    if (eventType.isEmpty) eventType = 'PARTY PLAN';
    if (eventTitle.isEmpty) eventTitle = 'Scheduled Event';

    String formattedDateTime = dateTimeRaw.isNotEmpty ? dateTimeRaw : 'Upcoming Time';
    if (dateTimeRaw.isNotEmpty) {
      try {
        final dt = DateTime.parse(dateTimeRaw).toLocal();
        formattedDateTime =
            '${dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour)}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
      } catch (_) {
        formattedDateTime = dateTimeRaw.toUpperCase();
      }
    }

    String formattedNextTime = nextTimeRaw.isNotEmpty ? nextTimeRaw : 'In 4 hours';
    if (nextTimeRaw.isNotEmpty) {
      try {
        final dt = DateTime.parse(nextTimeRaw).toLocal();
        formattedNextTime =
            '${dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour)}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
      } catch (_) {
        formattedNextTime = nextTimeRaw.toUpperCase();
      }
    }

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TimeLockBlockedDialog(
        conflictingEventType: eventType.toUpperCase(),
        conflictingEventTitle: eventTitle,
        conflictingDateTime: formattedDateTime,
        nextAvailableTime: formattedNextTime,
        message: message,
        onViewExistingPlan: onViewExistingPlan,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)),
      elevation: 12,
      backgroundColor: const Color(0xFF1E1E2E), // Modern sleek dark theme card
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header Icon Badge
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.hourglass_top_rounded,
                color: Colors.amber,
                size: 44,
              ),
            ),
            const SizedBox(height: 16),
            
            // Header Title
            const Text(
              '⏳ Time Locked',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),

            // Card Body with Conflicting Details
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A3C),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 1),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          conflictingEventType,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          conflictingEventTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.access_time_filled_rounded, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        'Scheduled: $conflictingDateTime',
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Message text
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFB0B0C3),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),

            // Earliest Available Time Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Earliest available: $nextAvailableTime',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Actions
            Column(
              children: [
                if (onViewExistingPlan != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onViewExistingPlan!();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('View Existing Plan', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white30),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Choose Another Time'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
