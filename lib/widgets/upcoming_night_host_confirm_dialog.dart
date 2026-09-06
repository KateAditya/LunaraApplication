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
  String _paymentMode = 'SELF_PAY'; // 'SELF_PAY' | 'SPLIT'
  String _paymentMethod = 'SmartWallet'; // 'SmartWallet' | 'Razorpay'
  double _walletBalance = 0.0;
  bool _loadingWallet = true;

  @override
  void initState() {
    super.initState();
    _fetchWallet();
  }

  Future<void> _fetchWallet() async {
    try {
      final res = await ApiService.fetchWalletData();
      if (mounted) {
        final dynamic rawBal = res?['wallet']?['balance'] ?? res?['balance'] ?? 0;
        final double bal = (rawBal is num) ? rawBal.toDouble() : (double.tryParse(rawBal.toString()) ?? 0.0);
        setState(() {
          _walletBalance = bal;
          _loadingWallet = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingWallet = false);
    }
  }

  Future<void> _processBookingAndPayment() async {
    setState(() => _isLoading = true);

    try {
      final payRes = await ApiService.initiateMatchPayment(
        matchId: widget.matchId,
        paymentMode: _paymentMode,
      );

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

      final String razorpayOrderId = payRes['razorpayOrderId'] ?? 'order_mock_${DateTime.now().millisecondsSinceEpoch}';

      // Verify payment with chosen payment method (SmartWallet or Razorpay)
      final verifyRes = await ApiService.verifyMatchPayment(
        matchId: widget.matchId,
        razorpayOrderId: razorpayOrderId,
        razorpayPaymentId: _paymentMethod == 'SmartWallet'
            ? 'wallet_tx_${DateTime.now().millisecondsSinceEpoch}'
            : 'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
        razorpaySignature: 'mock_signature',
        paymentMethod: _paymentMethod,
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Celebration Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
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
              '${widget.partnerName} accepted your invite to join Upcoming Night! Choose payment mode & confirm booking.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),

            // Partner Avatar & Event Details
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      LunaraProfileImage(
                        userData: {'profilePhotoUrl': widget.partnerPhoto},
                        radius: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Partner: ${widget.partnerName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Ready to join',
                              style: TextStyle(
                                color: Color(0xFF15803D),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: LunaraTheme.electricViolet, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.venueName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: LunaraTheme.electricViolet, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.date} • ${widget.time}',
                        style: TextStyle(
                          fontSize: 11,
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

            // Split vs Self Pay Selector
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'PAYMENT MODE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.black54,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _paymentMode = 'SELF_PAY'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      decoration: BoxDecoration(
                        color: _paymentMode == 'SELF_PAY' ? LunaraTheme.electricViolet.withValues(alpha: 0.1) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _paymentMode == 'SELF_PAY' ? LunaraTheme.electricViolet : Colors.grey[300]!,
                          width: _paymentMode == 'SELF_PAY' ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.person_rounded,
                            size: 20,
                            color: _paymentMode == 'SELF_PAY' ? LunaraTheme.electricViolet : Colors.grey[600],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Self Pay',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: _paymentMode == 'SELF_PAY' ? LunaraTheme.electricViolet : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Host pays 100%',
                            style: TextStyle(
                              fontSize: 10,
                              color: _paymentMode == 'SELF_PAY' ? LunaraTheme.electricViolet : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _paymentMode = 'SPLIT'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      decoration: BoxDecoration(
                        color: _paymentMode == 'SPLIT' ? LunaraTheme.electricViolet.withValues(alpha: 0.1) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _paymentMode == 'SPLIT' ? LunaraTheme.electricViolet : Colors.grey[300]!,
                          width: _paymentMode == 'SPLIT' ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.group_rounded,
                            size: 20,
                            color: _paymentMode == 'SPLIT' ? LunaraTheme.electricViolet : Colors.grey[600],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Split 50/50',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: _paymentMode == 'SPLIT' ? LunaraTheme.electricViolet : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pay 50% each',
                            style: TextStyle(
                              fontSize: 10,
                              color: _paymentMode == 'SPLIT' ? LunaraTheme.electricViolet : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Payment Method Selector
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'PAY VIA',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.black54,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _paymentMethod = 'SmartWallet'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(
                        color: _paymentMethod == 'SmartWallet' ? const Color(0xFFF0FDF4) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _paymentMethod == 'SmartWallet' ? const Color(0xFF16A34A) : Colors.grey[300]!,
                          width: _paymentMethod == 'SmartWallet' ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 16,
                            color: _paymentMethod == 'SmartWallet' ? const Color(0xFF16A34A) : Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Smart Wallet',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: _paymentMethod == 'SmartWallet' ? const Color(0xFF16A34A) : Colors.black87,
                                ),
                              ),
                              Text(
                                _loadingWallet ? '...' : '₹${_walletBalance.toInt()} bal',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: _paymentMethod == 'SmartWallet' ? const Color(0xFF16A34A) : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _paymentMethod = 'Razorpay'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(
                        color: _paymentMethod == 'Razorpay' ? const Color(0xFFEFF6FF) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _paymentMethod == 'Razorpay' ? const Color(0xFF2563EB) : Colors.grey[300]!,
                          width: _paymentMethod == 'Razorpay' ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.credit_card_rounded,
                            size: 16,
                            color: _paymentMethod == 'Razorpay' ? const Color(0xFF2563EB) : Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'UPI / Card',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: _paymentMethod == 'Razorpay' ? const Color(0xFF2563EB) : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

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
                    : Text(
                        _paymentMode == 'SELF_PAY' ? 'CONFIRM & SELF PAY' : 'CONFIRM & SPLIT PAY',
                        style: const TextStyle(
                          fontFamily: 'AllroundGothic',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: Colors.white,
                        ),
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: LunaraTheme.electricViolet,
                  padding: const EdgeInsets.symmetric(vertical: 15),
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
