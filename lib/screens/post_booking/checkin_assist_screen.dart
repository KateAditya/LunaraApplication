import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/lunara_cached_image.dart';

class CheckInAssistScreen extends StatefulWidget {
  final String? venueName;
  final String? table;
  final String? guests;
  final String? date;
  final String? time;
  final String? status;
  final String? imageUrl;

  const CheckInAssistScreen({
    super.key,
    this.venueName,
    this.table,
    this.guests,
    this.date,
    this.time,
    this.status,
    this.imageUrl,
  });

  @override
  State<CheckInAssistScreen> createState() => _CheckInAssistScreenState();
}

class _CheckInAssistScreenState extends State<CheckInAssistScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Simulated countdown (event starts in 2h 15m)
  Duration _countdown = const Duration(hours: 2, minutes: 15, seconds: 0);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.2, end: 0.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Dynamic countdown if date/time are provided and future
    if (widget.date != null) {
      try {
        // Try parsing the date/time string
        // If it starts with a weekday like "SAT, FEB 22 • 10:30 PM", split or clean it.
        String dateStr = widget.date!;
        if (dateStr.contains('•')) {
          final parts = dateStr.split('•');
          dateStr = parts[0].trim();
        }
        // If it has day of week like "SAT, FEB 22", remove weekday
        if (dateStr.contains(',')) {
          final parts = dateStr.split(',');
          if (parts.length > 1) {
            dateStr = parts[1].trim();
          }
        }

        // Try to parse the clean dateStr
        // We'll append current year if year is missing
        if (!dateStr.contains(RegExp(r'\d{4}'))) {
          dateStr = '$dateStr, ${DateTime.now().year}';
        }

        final timeStr = widget.time ?? '10:30 PM';
        // Parse "10:30 PM"
        final timeParts = timeStr.trim().split(RegExp(r'[: ]'));
        int hour = 22;
        int minute = 30;
        if (timeParts.length >= 2) {
          hour = int.tryParse(timeParts[0]) ?? 22;
          minute = int.tryParse(timeParts[1]) ?? 30;
          if (timeStr.toUpperCase().contains('PM') && hour < 12) {
            hour += 12;
          } else if (timeStr.toUpperCase().contains('AM') && hour == 12) {
            hour = 0;
          }
        }

        // Standardize month names to digits for simple parsing
        final months = {
          'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6,
          'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12
        };

        final dateUpper = dateStr.toUpperCase();
        int month = DateTime.now().month;
        for (final m in months.keys) {
          if (dateUpper.contains(m)) {
            month = months[m]!;
            break;
          }
        }

        final dayMatch = RegExp(r'\b\d{1,2}\b').firstMatch(dateUpper);
        int day = DateTime.now().day;
        if (dayMatch != null) {
          day = int.tryParse(dayMatch.group(0) ?? '') ?? day;
        }

        final yearMatch = RegExp(r'\b\d{4}\b').firstMatch(dateUpper);
        int year = DateTime.now().year;
        if (yearMatch != null) {
          year = int.tryParse(yearMatch.group(0) ?? '') ?? year;
        }

        final targetDateTime = DateTime(year, month, day, hour, minute);
        final diff = targetDateTime.difference(DateTime.now());
        if (diff.inSeconds > 0) {
          _countdown = diff;
        }
      } catch (e) {
        debugPrint('Error parsing event countdown date: $e');
      }
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_countdown.inSeconds > 0) {
        setState(() => _countdown -= const Duration(seconds: 1));
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String get _formattedCountdown {
    final h = _countdown.inHours;
    final m = _countdown.inMinutes.remainder(60);
    final s = _countdown.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    _buildCountdown(),
                    const SizedBox(height: 48),
                    _buildQRSection(),
                    const SizedBox(height: 48),
                    _buildVenueInfo(),
                    const SizedBox(height: 32),
                    _buildInstructions(),
                    const SizedBox(height: 32),
                    _buildBrightnessIndicator(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'CHECK-IN',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildCountdown() {
    return Column(
      children: [
        const Text(
          'EVENT STARTS IN',
          style: TextStyle(
            color: Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _formattedCountdown,
          style: const TextStyle(
            fontSize: 42,
            color: LunaraTheme.electricViolet,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
          ),
        ),
      ],
    );
  }

  Widget _buildQRSection() {
    final String cleanVenue = widget.venueName ?? 'ELARA';
    final String cleanDate = widget.date ?? '20260222';
    final String qrData = 'LUNARA-CHECKIN-$cleanVenue-$cleanDate'.replaceAll(RegExp(r'\s+'), '-');

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: LunaraTheme.electricViolet.withValues(
                alpha: _pulseAnimation.value,
              ),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: LunaraTheme.electricViolet.withValues(
                  alpha: _pulseAnimation.value * 0.2,
                ),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: LunaraTheme.premiumCardShadow,
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey[100]!),
              ),
              child: LunaraCachedImage(
                'https://api.qrserver.com/v1/create-qr-code/?size=220x220&data=$qrData',
                width: 200,
                height: 200,
                errorBuilder: (_, _, _) => Container(
                  width: 200,
                  height: 200,
                  color: Colors.white,
                  child: Icon(
                    Icons.qr_code_rounded,
                    size: 100,
                    color: Colors.grey[200],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'SCAN AT ENTRY',
              style: TextStyle(
                color: Colors.black,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVenueInfo() {
    final String cleanVenueName = widget.venueName ?? 'ELARA VELVET';
    final String cleanTable = widget.table ?? 'VIP V1';
    final String cleanGuests = widget.guests ?? '6';
    final String cleanDate = widget.date ?? 'FEB 22, 2026';
    final String cleanTime = widget.time ?? '10:30 PM';
    final String cleanStatus = widget.status ?? 'VERIFIED';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LunaraTheme.cardGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: LunaraTheme.premiumCardShadow,
        border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _labelValue('VENUE', cleanVenueName),
              _labelValue('TABLE', cleanTable),
              _labelValue('GUESTS', cleanGuests),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _labelValue('DATE', cleanDate),
              _labelValue('TIME', cleanTime),
              _labelValue('STATUS', cleanStatus),
            ],
          ),
        ],
      ),
    );
  }

  Widget _labelValue(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: 0.5 + (_pulseAnimation.value / 2),
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  color: LunaraTheme.electricViolet,
                  size: 28,
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SHOW QR TO HOST',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Hold your phone screen-up at the entrance. The host will scan your code.',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrightnessIndicator() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.brightness_high_rounded,
          color: LunaraTheme.electricViolet,
          size: 18,
        ),
        SizedBox(width: 10),
        Text(
          'AUTO-BRIGHTNESS ACTIVE',
          style: TextStyle(
            color: LunaraTheme.electricViolet,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
