import 'dart:async';
import 'package:flutter/material.dart';

class LunaraCountdownButton extends StatefulWidget {
  final dynamic paymentDeadlineAt;
  final dynamic acceptedAt;
  final double amount;
  final VoidCallback onTap;
  final Color backgroundColor;
  final TextStyle? textStyle;

  const LunaraCountdownButton({
    super.key,
    required this.paymentDeadlineAt,
    this.acceptedAt,
    required this.amount,
    required this.onTap,
    this.backgroundColor = const Color(0xFF7C3AED),
    this.textStyle,
  });

  @override
  State<LunaraCountdownButton> createState() => _LunaraCountdownButtonState();
}

class _LunaraCountdownButtonState extends State<LunaraCountdownButton> {
  Timer? _timer;
  String _formattedCountdown = '30m';

  @override
  void initState() {
    super.initState();
    _updateCountdown();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateCountdown();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    dynamic deadlineRaw = widget.paymentDeadlineAt ?? widget.acceptedAt;

    if (deadlineRaw == null) {
      if (_formattedCountdown != '30m') {
        setState(() => _formattedCountdown = '30m');
      }
      return;
    }

    try {
      DateTime deadline;
      if (deadlineRaw is DateTime) {
        deadline = deadlineRaw;
      } else {
        deadline = DateTime.parse(deadlineRaw.toString()).toLocal();
      }

      if (widget.paymentDeadlineAt == null && widget.acceptedAt != null) {
        deadline = deadline.add(const Duration(minutes: 30));
      }

      final Duration diff = deadline.difference(DateTime.now());

      if (diff.inSeconds <= 0) {
        if (_formattedCountdown != 'Expired') {
          setState(() => _formattedCountdown = 'Expired');
        }
        return;
      }

      final int mins = diff.inMinutes;
      final int secs = diff.inSeconds % 60;
      final String secStr = secs < 10 ? '0$secs' : '$secs';
      final String formatted = '${mins}m ${secStr}s';

      if (_formattedCountdown != formatted) {
        setState(() => _formattedCountdown = formatted);
      }
    } catch (_) {
      if (_formattedCountdown != '30m') {
        setState(() => _formattedCountdown = '30m');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String amountStr = widget.amount > 0 ? ' (₹${widget.amount.toStringAsFixed(0)})' : '';
    final String label = 'Pay Deposit ($_formattedCountdown)$amountStr';

    return ElevatedButton.icon(
      onPressed: widget.onTap,
      icon: const Icon(Icons.payment_rounded, size: 14, color: Colors.white),
      label: Text(
        label,
        style: widget.textStyle ??
            const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: widget.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
