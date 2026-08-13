import 'dart:async';
import 'package:flutter/material.dart';

class LunaraCountdownButton extends StatefulWidget {
  final dynamic paymentDeadlineAt;
  final dynamic serverTime;
  final dynamic acceptedAt;
  final double amount;
  final VoidCallback onTap;
  final VoidCallback? onExpired;
  final Color backgroundColor;
  final TextStyle? textStyle;

  const LunaraCountdownButton({
    super.key,
    required this.paymentDeadlineAt,
    this.serverTime,
    this.acceptedAt,
    required this.amount,
    required this.onTap,
    this.onExpired,
    this.backgroundColor = const Color(0xFF7C3AED),
    this.textStyle,
  });

  @override
  State<LunaraCountdownButton> createState() => _LunaraCountdownButtonState();
}

class _LunaraCountdownButtonState extends State<LunaraCountdownButton> {
  Timer? _timer;
  String _formattedCountdown = 'Unavailable';
  Duration _serverClockOffset = Duration.zero;
  bool _hasExpired = false;

  @override
  void initState() {
    super.initState();
    _syncServerClock();
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

  @override
  void didUpdateWidget(covariant LunaraCountdownButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverTime != widget.serverTime) {
      _syncServerClock();
      _hasExpired = false;
    }
  }

  void _syncServerClock() {
    try {
      if (widget.serverTime != null) {
        final serverNow = DateTime.parse(widget.serverTime.toString()).toUtc();
        _serverClockOffset = serverNow.difference(DateTime.now().toUtc());
      }
    } catch (_) {
      _serverClockOffset = Duration.zero;
    }
  }

  void _updateCountdown() {
    final deadlineRaw = widget.paymentDeadlineAt;

    if (deadlineRaw == null) {
      if (_formattedCountdown != 'Unavailable') {
        setState(() => _formattedCountdown = 'Unavailable');
      }
      return;
    }

    try {
      DateTime deadline;
      if (deadlineRaw is DateTime) {
        deadline = deadlineRaw;
      } else {
        deadline = DateTime.parse(deadlineRaw.toString()).toUtc();
      }

      final Duration diff = deadline.difference(DateTime.now().toUtc().add(_serverClockOffset));

      if (diff.inSeconds <= 0) {
        if (_formattedCountdown != 'Expired') {
          setState(() => _formattedCountdown = 'Expired');
        }
        if (!_hasExpired) {
          _hasExpired = true;
          widget.onExpired?.call();
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
      if (_formattedCountdown != 'Unavailable') {
        setState(() => _formattedCountdown = 'Unavailable');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String amountStr = widget.amount > 0 ? ' (₹${widget.amount.toStringAsFixed(0)})' : '';
    final isUnavailable = _formattedCountdown == 'Unavailable';
    final isExpired = _formattedCountdown == 'Expired';
    final String label = isUnavailable
        ? 'Payment status unavailable$amountStr'
        : 'Pay Deposit ($_formattedCountdown)$amountStr';

    return ElevatedButton.icon(
      onPressed: isUnavailable || isExpired ? null : widget.onTap,
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
