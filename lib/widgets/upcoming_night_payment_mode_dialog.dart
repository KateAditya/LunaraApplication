import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../widgets/lunara_profile_image.dart';
import '../utils/lunara_date_formatter.dart';

class UpcomingNightPaymentModeDialog extends StatelessWidget {
  final Map<String, dynamic> partner;
  final String venueName;
  final String date;
  final String? time;
  final String? eventTitle;
  final double ticketPrice;
  final Function(String paymentMode) onSelectMode;

  const UpcomingNightPaymentModeDialog({
    super.key,
    required this.partner,
    required this.venueName,
    required this.date,
    this.time,
    this.eventTitle,
    this.ticketPrice = 1000.0,
    required this.onSelectMode,
  });

  static Future<String?> show(
    BuildContext context, {
    required Map<String, dynamic> partner,
    required String venueName,
    required String date,
    String? time,
    String? eventTitle,
    double ticketPrice = 1000.0,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => UpcomingNightPaymentModeDialog(
        partner: partner,
        venueName: venueName,
        date: date,
        time: time,
        eventTitle: eventTitle,
        ticketPrice: ticketPrice,
        onSelectMode: (mode) => Navigator.pop(ctx, mode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final partnerName = partner['firstName'] ?? 'Partner';
    final partnerPhoto = partner['primaryPhoto'] ?? partner['profilePhotoUrl'] ?? partner['photoUrl'];
    final displayEvent = eventTitle ?? venueName;
    final formattedTime = LunaraDateFormatter.normalizeTimeTo12Hour(time ?? '20:00');
    
    String formattedDate = date;
    final parsedDt = LunaraDateFormatter.parseToLocal(date);
    if (parsedDt != null) {
      formattedDate = DateFormat('dd MMM yyyy').format(parsedDt);
    }

    final double selfPayHostAmount = ticketPrice * 2;
    final double selfPayPartnerAmount = 0;

    final double splitHostAmount = ticketPrice;
    final double splitPartnerAmount = ticketPrice;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Badge & Close
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.style_rounded, size: 14, color: LunaraTheme.electricViolet),
                        SizedBox(width: 6),
                        Text(
                          'TICKET PAYMENT MODE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            color: LunaraTheme.electricViolet,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Title
              const Text(
                'HOW DO YOU WANT TO SPLIT THE TICKET?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'AllroundGothic',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose how ticket confirmation will be paid for $displayEvent.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const SizedBox(height: 16),

              // Event & Partner Summary Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF7F7FC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  children: [
                    LunaraProfileImage(
                      userData: {'profilePhotoUrl': partnerPhoto},
                      radius: 23,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Inviting $partnerName',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$venueName • $formattedDate • $formattedTime',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ticket Price: ₹${ticketPrice.toStringAsFixed(0)} / person',
                            style: const TextStyle(
                              fontSize: 12,
                              color: LunaraTheme.electricViolet,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Option 1: SELF PAY
              _buildPaymentOptionCard(
                context: context,
                isDark: isDark,
                mode: 'SELF_PAY',
                title: 'SELF PAY',
                subtitle: 'You pay for the full booking. Your partner joins without paying separately.',
                badgeText: 'HOST COVERS FULL',
                badgeColor: const Color(0xFF10B981),
                hostAmount: selfPayHostAmount,
                partnerAmount: selfPayPartnerAmount,
                onTap: () => onSelectMode('SELF_PAY'),
              ),
              const SizedBox(height: 12),

              // Option 2: SPLIT
              _buildPaymentOptionCard(
                context: context,
                isDark: isDark,
                mode: 'SPLIT',
                title: 'SPLIT',
                subtitle: 'You pay for your ticket. Your partner pays for their own ticket after accepting.',
                badgeText: '50 / 50 SPLIT',
                badgeColor: LunaraTheme.electricViolet,
                hostAmount: splitHostAmount,
                partnerAmount: splitPartnerAmount,
                onTap: () => onSelectMode('SPLIT'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentOptionCard({
    required BuildContext context,
    required bool isDark,
    required String mode,
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required double hostAmount,
    required double partnerAmount,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF252538) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: mode == 'SELF_PAY' ? const Color(0xFF10B981).withValues(alpha: 0.4) : LunaraTheme.electricViolet.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (mode == 'SELF_PAY' ? const Color(0xFF10B981) : LunaraTheme.electricViolet).withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'AllroundGothic',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: badgeColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.black54,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),

            // Price Breakdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'You pay: ₹${hostAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Partner pays: ₹${partnerAmount.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: partnerAmount == 0 ? const Color(0xFF10B981) : LunaraTheme.electricViolet,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Action Button
            ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: mode == 'SELF_PAY' ? const Color(0xFF10B981) : LunaraTheme.electricViolet,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
              ),
              child: Text(
                'SELECT $title',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
