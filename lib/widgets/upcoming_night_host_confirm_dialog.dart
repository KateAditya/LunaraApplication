import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../widgets/lunara_profile_image.dart';
import '../screens/discovery/night_match_success_dialog.dart';

class UpcomingNightHostConfirmDialog extends StatefulWidget {
  final String matchId;
  final String partnerName;
  final String? partnerPhoto;
  final String venueName;
  final String date;
  final String time;

  const UpcomingNightHostConfirmDialog({
    super.key,
    required this.matchId,
    required this.partnerName,
    this.partnerPhoto,
    required this.venueName,
    required this.date,
    required this.time,
  });

  @override
  State<UpcomingNightHostConfirmDialog> createState() => _UpcomingNightHostConfirmDialogState();
}

class _UpcomingNightHostConfirmDialogState extends State<UpcomingNightHostConfirmDialog> {
  bool _isLoading = false;

  Future<void> _processBookingAndPayment() async {
    setState(() => _isLoading = true);

    try {
      final payRes = await ApiService.initiateMatchPayment(widget.matchId);

      if (payRes == null || payRes['success'] != true) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(payRes?['message'] ?? 'Failed to initiate payment. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final String razorpayOrderId = payRes['razorpayOrderId'] ?? 'order_mock_123';

      // Verify payment (Mock verification for seamless demo or Razorpay integration)
      final verifyRes = await ApiService.verifyMatchPayment(
        matchId: widget.matchId,
        razorpayOrderId: razorpayOrderId,
        razorpayPaymentId: 'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
        razorpaySignature: 'mock_signature',
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (verifyRes != null) {
        Navigator.pop(context); // Close confirm dialog

        final conversationId = verifyRes['conversationId']?.toString();
        final partnerId = verifyRes['partnerId']?.toString();
        final ticketId = verifyRes['ticketCode']?.toString() ?? verifyRes['booking']?['ticketCode']?.toString();

        // Show Match Success Celebratory Dialog with Ticket & Let's Chat!
        showDialog(
          context: context,
          builder: (_) => NightMatchSuccessDialog(
            partnerName: widget.partnerName,
            partnerPhoto: widget.partnerPhoto,
            venueName: widget.venueName,
            date: widget.date,
            time: widget.time,
            conversationId: conversationId,
            partnerId: partnerId,
            ticketId: ticketId,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment verification failed. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

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
            // Celebration Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_read_rounded,
                color: Color(0xFF15803D),
                size: 36,
              ),
            ),
            const SizedBox(height: 16),

            // Title
            const Text(
              'INVITE ACCEPTED! 🎉',
              style: TextStyle(
                fontFamily: 'AllroundGothic',
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            Text(
              '${widget.partnerName} accepted your invite to join Upcoming Night! Confirm booking to lock your match and unlock chat.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // Partner Avatar & Event Details
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      LunaraProfileImage(
                        userData: {'profilePhotoUrl': widget.partnerPhoto},
                        radius: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Partner: ${widget.partnerName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Ready to join',
                              style: TextStyle(
                                color: Color(0xFF15803D),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: LunaraTheme.electricViolet, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.venueName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: LunaraTheme.electricViolet, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.date} • ${widget.time}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action Button: Confirm & Pay
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _processBookingAndPayment,
                icon: _isLoading
                    ? const SizedBox.shrink()
                    : const Icon(Icons.payment_rounded, color: Colors.white, size: 18),
                label: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'CONFIRM BOOKING & PAY',
                        style: TextStyle(
                          fontFamily: 'AllroundGothic',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: Colors.white,
                        ),
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: LunaraTheme.electricViolet,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
