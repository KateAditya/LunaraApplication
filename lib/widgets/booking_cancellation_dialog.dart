import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../core/theme.dart';

class BookingCancellationDialog extends StatefulWidget {
  final String bookingId;
  final bool isGroupParty;
  final String? initialVenueName;
  final String? initialDate;
  final String? initialTime;
  final double? initialAmountPaid;
  final VoidCallback? onCancelled;

  const BookingCancellationDialog({
    super.key,
    required this.bookingId,
    this.isGroupParty = false,
    this.initialVenueName,
    this.initialDate,
    this.initialTime,
    this.initialAmountPaid,
    this.onCancelled,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String bookingId,
    bool isGroupParty = false,
    String? initialVenueName,
    String? initialDate,
    String? initialTime,
    double? initialAmountPaid,
    VoidCallback? onCancelled,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BookingCancellationDialog(
        bookingId: bookingId,
        isGroupParty: isGroupParty,
        initialVenueName: initialVenueName,
        initialDate: initialDate,
        initialTime: initialTime,
        initialAmountPaid: initialAmountPaid,
        onCancelled: onCancelled,
      ),
    );
  }

  @override
  State<BookingCancellationDialog> createState() => _BookingCancellationDialogState();
}

class _BookingCancellationDialogState extends State<BookingCancellationDialog> {
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _errorMessage;
  Map<String, dynamic>? _previewData;

  String _payoutType = 'UPI_ID'; // 'UPI_ID', 'UPI_NUMBER', 'BANK_ACCOUNT'
  final TextEditingController _upiIdController = TextEditingController();
  final TextEditingController _upiNumberController = TextEditingController();
  final TextEditingController _bankAccountController = TextEditingController();
  final TextEditingController _bankIfscController = TextEditingController();
  final TextEditingController _bankHolderController = TextEditingController();

  @override
  void dispose() {
    _upiIdController.dispose();
    _upiNumberController.dispose();
    _bankAccountController.dispose();
    _bankIfscController.dispose();
    _bankHolderController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCancellationPreview();
  }

  Future<void> _loadCancellationPreview() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final preview = await ApiService.fetchBookingCancellationPreview(
      widget.bookingId,
      isGroupParty: widget.isGroupParty,
    );

    if (!mounted) return;

    if (preview != null && preview['error'] == null) {
      setState(() {
        _isLoading = false;
        _previewData = preview;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = preview?['error'] ?? 'Could not calculate refund preview.';
      });
    }
  }

  Future<void> _confirmCancellation() async {
    final refundAmount = double.tryParse(_previewData?['refundAmount']?.toString() ?? '0') ?? 0.0;
    final isLargeRefund = refundAmount > 1500 || (_previewData?['requiresPayoutDetails'] == true);

    Map<String, dynamic>? payoutDetails;
    if (isLargeRefund) {
      if (_payoutType == 'UPI_ID') {
        final upi = _upiIdController.text.trim();
        if (upi.isEmpty || !upi.contains('@')) {
          setState(() => _errorMessage = 'Please enter a valid UPI ID (e.g. user@okhdfcbank)');
          return;
        }
        payoutDetails = {
          'payoutType': 'UPI_ID',
          'upiId': upi,
        };
      } else if (_payoutType == 'UPI_NUMBER') {
        final num = _upiNumberController.text.trim();
        if (num.length != 10 || int.tryParse(num) == null) {
          setState(() => _errorMessage = 'Please enter a valid 10-digit UPI phone number');
          return;
        }
        payoutDetails = {
          'payoutType': 'UPI_NUMBER',
          'upiNumber': num,
        };
      } else if (_payoutType == 'BANK_ACCOUNT') {
        final acct = _bankAccountController.text.trim();
        final ifsc = _bankIfscController.text.trim().toUpperCase();
        final holder = _bankHolderController.text.trim();
        if (acct.isEmpty) {
          setState(() => _errorMessage = 'Please enter your bank account number');
          return;
        }
        if (ifsc.length < 5) {
          setState(() => _errorMessage = 'Please enter a valid IFSC code');
          return;
        }
        if (holder.isEmpty) {
          setState(() => _errorMessage = 'Please enter account holder name');
          return;
        }
        payoutDetails = {
          'payoutType': 'BANK_ACCOUNT',
          'bankAccountNumber': acct,
          'bankIfsc': ifsc,
          'bankHolderName': holder,
        };
      }
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    final result = await ApiService.confirmBookingCancellation(
      widget.bookingId,
      isGroupParty: widget.isGroupParty,
      payoutDetails: payoutDetails,
    );

    if (!mounted) return;

    setState(() => _isProcessing = false);

    if (result != null && result['success'] == true) {
      Navigator.of(context).pop(true);
      widget.onCancelled?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message'] ?? 'Booking cancelled successfully.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } else {
      setState(() {
        _errorMessage = result?['message'] ?? 'Failed to cancel booking.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E28) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    final venueName = _previewData?['venueName'] ?? widget.initialVenueName ?? 'Venue';
    String eventDate = (_previewData?['eventDate'] ?? '').toString().trim();
    if (eventDate.isEmpty && widget.initialDate != null && widget.initialDate!.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(widget.initialDate!.trim());
      if (parsed != null) {
        try {
          eventDate = DateFormat('EEEE, d MMMM yyyy').format(parsed);
        } catch (_) {
          eventDate = widget.initialDate!.trim();
        }
      } else {
        eventDate = widget.initialDate!.trim();
      }
    }
    if (eventDate.isEmpty) {
      eventDate = 'Event Date';
    }

    final eventTime = _previewData?['eventTime'] ?? widget.initialTime ?? '';
    final paidAmount = double.tryParse(_previewData?['paidAmount']?.toString() ?? widget.initialAmountPaid?.toString() ?? '0') ?? 0.0;

    final policy = _previewData?['refundPolicy'];
    final refundPercentage = policy != null ? (policy['refundPercentage'] ?? 80) : 80;
    final refundAmount = _previewData != null
        ? (double.tryParse(_previewData!['refundAmount']?.toString() ?? '0') ?? 0.0)
        : (paidAmount * refundPercentage / 100);
    final nonRefundableAmount = _previewData != null
        ? (double.tryParse(_previewData!['nonRefundableAmount']?.toString() ?? '0') ?? 0.0)
        : (paidAmount - refundAmount);
    final refundMethod = _previewData?['refundMethod'] ?? (refundAmount > 1500 ? 'UPI / Bank Transfer' : 'Lunara Wallet');
    final canCancel = _previewData != null ? (_previewData!['canCancel'] ?? true) : (_errorMessage == null);
    final cancellationReason = _previewData?['cancellationReason'];

    return Container(
      padding: EdgeInsets.only(
        top: 24,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Header Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.cancel_outlined,
                      color: Colors.redAccent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cancel Booking?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Please review the refund details below',
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_isLoading) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
                  ),
                ),
              ] else if (_errorMessage != null && !canCancel) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.redAccent, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _loadCancellationPreview,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: LunaraTheme.electricViolet,
                          side: const BorderSide(color: LunaraTheme.electricViolet),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text(
                          'RETRY',
                          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: LunaraTheme.electricViolet,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text(
                          'CLOSE',
                          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Booking Details Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF15151D) : const Color(0xFFF7F7FA),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow('Venue', venueName, textColor, isBold: true),
                      const Divider(height: 16),
                      _buildDetailRow('Date', eventDate, textColor),
                      if (eventTime.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _buildDetailRow('Time', eventTime, textColor),
                      ],
                      const Divider(height: 16),
                      _buildDetailRow('Amount Paid', '₹${NumberFormat('#,##,###').format(paidAmount.toInt())}', textColor, isBold: true),
                      const SizedBox(height: 6),
                      _buildDetailRow('Refund Policy', '$refundPercentage%', textColor),
                      const SizedBox(height: 6),
                      _buildDetailRow('Refund Amount', '₹${NumberFormat('#,##,###').format(refundAmount.toInt())}', Colors.green, isBold: true),
                      if (nonRefundableAmount > 0) ...[
                        const SizedBox(height: 6),
                        _buildDetailRow('Non-refundable Amount', '₹${NumberFormat('#,##,###').format(nonRefundableAmount.toInt())}', Colors.redAccent),
                      ],
                      const Divider(height: 16),
                      _buildDetailRow('Refund Method', refundMethod, LunaraTheme.electricViolet, isBold: true),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Payout Form or Wallet Notice based on refundAmount > 1500
                if (refundAmount > 1500 || (_previewData?['requiresPayoutDetails'] == true)) ...[
                  _buildPayoutDetailsForm(isDark, textColor, secondaryTextColor),
                  const SizedBox(height: 14),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined, color: Colors.green, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Refund of ₹${NumberFormat('#,##,###').format(refundAmount.toInt())} will be credited instantly to your Lunara Wallet.',
                            style: TextStyle(color: isDark ? Colors.greenAccent : Colors.green.shade800, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                if (cancellationReason != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      cancellationReason,
                      style: TextStyle(color: Colors.amber[700], fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                if (_errorMessage != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Action Buttons
                const SizedBox(height: 8),
                if (_isProcessing)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
                    ),
                  )
                else ...[
                  ElevatedButton(
                    onPressed: _confirmCancellation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text(
                      'CONFIRM CANCELLATION',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: textColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      'KEEP BOOKING',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPayoutDetailsForm(bool isDark, Color textColor, Color secondaryTextColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191924) : const Color(0xFFF3F3FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance, color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              Text(
                'Payout Method (Refund > ₹1,500)',
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Since refund exceeds ₹1,500, amount will be transferred directly to your bank account or UPI within 24-48 hours.',
            style: TextStyle(color: secondaryTextColor, fontSize: 11),
          ),
          const SizedBox(height: 14),

          // Payout Type Selector Tabs
          Row(
            children: [
              _buildPayoutTypeChip('UPI_ID', 'UPI ID', Icons.qr_code),
              const SizedBox(width: 8),
              _buildPayoutTypeChip('UPI_NUMBER', 'UPI Phone', Icons.phone_android),
              const SizedBox(width: 8),
              _buildPayoutTypeChip('BANK_ACCOUNT', 'Bank Details', Icons.account_balance),
            ],
          ),
          const SizedBox(height: 14),

          if (_payoutType == 'UPI_ID') ...[
            _buildTextField(
              controller: _upiIdController,
              label: 'UPI ID / VPA',
              hint: 'e.g. yourname@okhdfcbank',
              icon: Icons.alternate_email,
              keyboardType: TextInputType.text,
              isDark: isDark,
              textColor: textColor,
            ),
          ] else if (_payoutType == 'UPI_NUMBER') ...[
            _buildTextField(
              controller: _upiNumberController,
              label: 'UPI Registered Phone Number',
              hint: '10-digit mobile number',
              icon: Icons.phone,
              keyboardType: TextInputType.phone,
              isDark: isDark,
              textColor: textColor,
            ),
          ] else ...[
            _buildTextField(
              controller: _bankHolderController,
              label: 'Account Holder Name',
              hint: 'Full name as per bank records',
              icon: Icons.person_outline,
              keyboardType: TextInputType.name,
              isDark: isDark,
              textColor: textColor,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _bankAccountController,
              label: 'Bank Account Number',
              hint: 'Enter account number',
              icon: Icons.credit_card,
              keyboardType: TextInputType.number,
              isDark: isDark,
              textColor: textColor,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _bankIfscController,
              label: 'IFSC Code',
              hint: 'e.g. HDFC0001234',
              icon: Icons.domain,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.characters,
              isDark: isDark,
              textColor: textColor,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPayoutTypeChip(String type, String label, IconData icon) {
    final isSelected = _payoutType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _payoutType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? LunaraTheme.electricViolet
                : LunaraTheme.electricViolet.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : LunaraTheme.electricViolet,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? Colors.white : LunaraTheme.electricViolet,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required TextInputType keyboardType,
    required bool isDark,
    required Color textColor,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          style: TextStyle(color: textColor, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
            prefixIcon: Icon(icon, size: 16, color: LunaraTheme.electricViolet),
            filled: true,
            fillColor: isDark ? const Color(0xFF101017) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: LunaraTheme.electricViolet),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, Color valueColor, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
