import 'package:flutter/material.dart';
import '../../core/theme.dart';

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

  static bool isConflictError(dynamic error) {
    if (error == null) return false;
    final str = error.toString().toLowerCase();
    return str.contains('4 hours apart') ||
        str.contains('already have a') ||
        str.contains('time lock') ||
        str.contains('earliest available') ||
        str.contains('schedule conflict') ||
        str.contains('active plan');
  }

  static String cleanErrorMessage(dynamic error) {
    if (error == null) return 'An unexpected error occurred.';
    var str = error.toString().trim();
    if (str.startsWith('Exception: ')) {
      str = str.substring('Exception: '.length).trim();
    }
    if (str.startsWith('Error: ')) {
      str = str.substring('Error: '.length).trim();
    }
    return str;
  }

  static Future<void> showWithMessage(
    BuildContext context,
    String rawMessage, {
    VoidCallback? onViewExistingPlan,
  }) async {
    final clean = cleanErrorMessage(rawMessage);
    return show(
      context,
      errorData: {'message': clean},
      onViewExistingPlan: onViewExistingPlan,
    );
  }

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> errorData,
    VoidCallback? onViewExistingPlan,
  }) async {
    String eventType = (errorData['conflictingEventType'] ?? '')
        .toString()
        .replaceAll('_', ' ')
        .trim();
    String eventTitle =
        errorData['conflictingEventTitle']?.toString().trim() ?? '';
    String dateTimeRaw =
        errorData['conflictingDateTime']?.toString().trim() ?? '';
    String nextTimeRaw =
        errorData['nextAvailableTime']?.toString().trim() ?? '';
    final message = errorData['message']?.toString() ??
        'Your next event must be at least 4 hours apart.';

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

    if (eventType.isEmpty) eventType = 'ACTIVE EVENT';
    if (eventTitle.isEmpty) eventTitle = 'Scheduled Booking';

    String formattedDateTime =
        dateTimeRaw.isNotEmpty ? dateTimeRaw : 'Upcoming Time';
    if (dateTimeRaw.isNotEmpty) {
      try {
        final dt = DateTime.parse(dateTimeRaw).toLocal();
        formattedDateTime =
            '${dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour)}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
      } catch (_) {
        formattedDateTime = dateTimeRaw.toUpperCase();
      }
    }

    String formattedNextTime =
        nextTimeRaw.isNotEmpty ? nextTimeRaw : 'In 4 hours';
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
      barrierDismissible: true,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28.0)),
      elevation: 20,
      backgroundColor: const Color(0xFF14141E),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28.0),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1F1C2C),
              Color(0xFF14141E),
            ],
          ),
          border: Border.all(
            color: LunaraTheme.electricViolet.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header Glowing Icon Badge
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.amber.shade400.withValues(alpha: 0.25),
                    LunaraTheme.electricViolet.withValues(alpha: 0.2),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.amber.shade300.withValues(alpha: 0.6),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.hourglass_top_rounded,
                color: Color(0xFFFFC107),
                size: 42,
              ),
            ),
            const SizedBox(height: 18),

            // Header Title
            const Text(
              'Schedule Conflict',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '4-Hour Window Policy',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFFC107),
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 18),

            // Card Body with Conflicting Details
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF222034),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFC107), Color(0xFFFF9800)],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          conflictingEventType,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                            letterSpacing: 0.5,
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
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: Color(0xFF9E9EB8),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Scheduled for: $conflictingDateTime',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFD4D4E8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Message text explanation
            const Text(
              'To ensure a seamless experience and prevent overlapping plans, your next event must be scheduled at least 4 hours apart.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFFA5A5C0),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),

            // Earliest Available Time Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF10B981).withValues(alpha: 0.15),
                    const Color(0xFF059669).withValues(alpha: 0.15),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.event_available_rounded,
                    color: Color(0xFF34D399),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Next Available: $nextAvailableTime',
                      style: const TextStyle(
                        color: Color(0xFF34D399),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Actions
            Column(
              children: [
                if (onViewExistingPlan != null) ...[
                  Container(
                    width: double.infinity,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LunaraTheme.purpleGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color:
                              LunaraTheme.electricViolet.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onViewExistingPlan!();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'VIEW MY EXISTING PLAN',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'GOT IT',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
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
