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
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    final result = await ApiService.confirmBookingCancellation(
      widget.bookingId,
      isGroupParty: widget.isGroupParty,
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
          duration: const Duration(seconds: 4),
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
    final eventDate = _previewData?['eventDate'] ?? widget.initialDate ?? 'Event Date';
    final eventTime = _previewData?['eventTime'] ?? widget.initialTime ?? '';
    final paidAmount = double.tryParse(_previewData?['paidAmount']?.toString() ?? widget.initialAmountPaid?.toString() ?? '0') ?? 0.0;

    final policy = _previewData?['refundPolicy'];
    final refundPercentage = policy != null ? (policy['refundPercentage'] ?? 80) : 80;
    final refundAmount = double.tryParse(_previewData?['refundAmount']?.toString() ?? '0') ?? (paidAmount * refundPercentage / 100);
    final nonRefundableAmount = double.tryParse(_previewData?['nonRefundableAmount']?.toString() ?? '0') ?? (paidAmount - refundAmount);
    final refundMethod = _previewData?['refundMethod'] ?? 'Lunara Wallet';
    final canCancel = _previewData?['canCancel'] ?? true;
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
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: LunaraTheme.electricViolet,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  'CLOSE',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
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
