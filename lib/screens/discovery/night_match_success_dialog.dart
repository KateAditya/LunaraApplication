import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../social/chat_screen.dart';

class NightMatchSuccessDialog extends StatelessWidget {
  final String partnerName;
  final String? partnerPhoto;
  final String venueName;
  final String date;
  final String time;
  final String? conversationId;
  final String? partnerId;

  const NightMatchSuccessDialog({
    super.key,
    required this.partnerName,
    this.partnerPhoto,
    required this.venueName,
    required this.date,
    required this.time,
    this.conversationId,
    this.partnerId,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 0,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Celebration Icon Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF3EEFF), Color(0xFFEEE6FF)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Text(
                '🎉',
                style: TextStyle(fontSize: 40),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            const Text(
              'Booking Confirmed!',
              style: TextStyle(
                fontFamily: 'AllroundGothic',
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            // Description
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  height: 1.4,
                ),
                children: [
                  const TextSpan(text: 'You and '),
                  TextSpan(
                    text: partnerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: LunaraTheme.electricViolet,
                    ),
                  ),
                  const TextSpan(text: ' are going to Upcoming Night together!'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Event Details Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: LunaraTheme.electricViolet, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          venueName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: LunaraTheme.electricViolet, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '$date • $time',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Chat Unlocked Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_open_rounded, color: Color(0xFF15803D), size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Chat is now unlocked!',
                    style: TextStyle(
                      color: Color(0xFF15803D),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Primary Action Button: Let's Chat
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  if (conversationId != null || partnerId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          user: {
                            'id': partnerId ?? '',
                            'conversationId': conversationId,
                            'name': partnerName,
                            'profileUrl': partnerPhoto,
                            'contextType': 'night_match',
                          },
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 18),
                label: const Text('LET\'S CHAT'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: LunaraTheme.electricViolet,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Close',
                style: TextStyle(
                  color: Colors.grey[600],
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
