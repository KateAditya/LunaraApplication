import 'package:flutter/material.dart';
import '../screens/profile/vip_membership_screen.dart';

class VipExpirationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String planName;
  final int remainingHours;
  final bool isExpired;

  const VipExpirationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.planName,
    this.remainingHours = 0,
    this.isExpired = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    required String planName,
    int remainingHours = 0,
    bool isExpired = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => VipExpirationDialog(
        title: title,
        message: message,
        planName: planName,
        remainingHours: remainingHours,
        isExpired: isExpired,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = isExpired ? Colors.redAccent : const Color(0xFF7C3AED);

    String durationText = isExpired
        ? 'EXPIRED'
        : (remainingHours >= 24
            ? '${(remainingHours / 24).round()} Day Remaining'
            : '$remainingHours Hours Remaining');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 16,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color: primaryColor.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Badge Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: isExpired
                      ? [Colors.red.shade400, Colors.red.shade700]
                      : [const Color(0xFF7C3AED), const Color(0xFFC084FC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                isExpired ? Icons.stars_rounded : Icons.workspace_premium_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),

            // Expiry Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isExpired ? Icons.error_outline_rounded : Icons.timer_outlined,
                    size: 16,
                    color: primaryColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    durationText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: primaryColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),

            // Message Body
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const VIPMembershipScreen(),
                    ),
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.flash_on_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      isExpired ? 'RENEW VIP NOW' : 'EXTEND VIP MEMBERSHIP',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Secondary Dismiss Button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Remind Me Later',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
