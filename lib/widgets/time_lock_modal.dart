import 'dart:async';
import 'package:flutter/material.dart';

class TimeLockModal extends StatefulWidget {
  final String reasonCode;
  final String message;
  final int remainingSeconds;
  final String? existingPlanId;
  final String? existingPlanType;

  const TimeLockModal({
    super.key,
    required this.reasonCode,
    required this.message,
    required this.remainingSeconds,
    this.existingPlanId,
    this.existingPlanType,
  });

  static Future<void> show({
    required BuildContext context,
    required String reasonCode,
    required String message,
    required int remainingSeconds,
    String? existingPlanId,
    String? existingPlanType,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TimeLockModal(
        reasonCode: reasonCode,
        message: message,
        remainingSeconds: remainingSeconds,
        existingPlanId: existingPlanId,
        existingPlanType: existingPlanType,
      ),
    );
  }

  @override
  State<TimeLockModal> createState() => _TimeLockModalState();
}

class _TimeLockModalState extends State<TimeLockModal> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.remainingSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        setState(() {
          _secondsLeft = 0;
        });
        _timer?.cancel();
        // Automatically close modal when timer ends
        Navigator.of(context).pop();
      } else {
        setState(() {
          _secondsLeft--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    return [
      hours.toString().padLeft(2, '0'),
      minutes.toString().padLeft(2, '0'),
      seconds.toString().padLeft(2, '0'),
    ].join(':');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            spreadRadius: 5,
          )
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: MainModalContent(
        secondsLeft: _secondsLeft,
        theme: theme,
        isDark: isDark,
        widget: widget,
        formatDuration: _formatDuration,
      ),
    );
  }
}

class MainModalContent extends StatelessWidget {
  final int secondsLeft;
  final ThemeData theme;
  final bool isDark;
  final TimeLockModal widget;
  final String Function(int) formatDuration;

  const MainModalContent({
    super.key,
    required this.secondsLeft,
    required this.theme,
    required this.isDark,
    required this.widget,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Handle bar
        Container(
          width: 48,
          height: 5,
          decoration: BoxDecoration(
            color: isDark ? Colors.white24 : Colors.black12,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(height: 24),

        // Lock Icon Container
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFF5252).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.lock_clock_outlined,
            color: Color(0xFFFF5252),
            size: 48,
          ),
        ),
        const SizedBox(height: 20),

        // Title
        Text(
          'Plan Creation Locked',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 12),

        // Subtitle / message
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            widget.message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.white70 : Colors.black54,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Timer widget
        if (secondsLeft > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black12,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Text(
                  'COOLDOWN TIME REMAINING',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: const Color(0xFFFF5252),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  formatDuration(secondsLeft),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],

        // Conflicting Activity Details
        if (widget.existingPlanId != null) ...[
          Text(
            'Conflict detected with active ${widget.existingPlanType?.replaceAll('_', ' ')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.amber[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Dismiss / View schedules Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  side: BorderSide(
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
                ),
                child: Text(
                  'Dismiss',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Trigger navigation to My Schedule screen
                  Navigator.of(context).pushNamed('/my-plans');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5252),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'My Schedule',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
