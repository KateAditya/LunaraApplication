import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../core/theme.dart';
import 'strangers_meet_host_cancellation_dialog.dart';

class StrangersMeetCancellationDialog extends StatefulWidget {
  final String meetId;
  final String subject;
  final String venueName;
  final double paidAmount;
  final VoidCallback? onCancelled;

  const StrangersMeetCancellationDialog({
    super.key,
    required this.meetId,
    required this.subject,
    required this.venueName,
    required this.paidAmount,
    this.onCancelled,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String meetId,
    required String subject,
    required String venueName,
    required double paidAmount,
    VoidCallback? onCancelled,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StrangersMeetCancellationDialog(
        meetId: meetId,
        subject: subject,
        venueName: venueName,
        paidAmount: paidAmount,
        onCancelled: onCancelled,
      ),
    );
  }

  @override
  State<StrangersMeetCancellationDialog> createState() =>
      _StrangersMeetCancellationDialogState();
}

class _StrangersMeetCancellationDialogState
    extends State<StrangersMeetCancellationDialog> {
  String _selectedReason = 'Schedule conflict / Plans changed';
  final TextEditingController _otherReasonController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  final List<String> _reasons = [
    'Schedule conflict / Plans changed',
    'Emergency / Personal reasons',
    'Travel / Location unavailable',
    'Other reason',
  ];

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

  Future<void> _submitCancellationRequest() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final reasonText = _selectedReason == 'Other reason'
        ? (_otherReasonController.text.trim().isNotEmpty
            ? _otherReasonController.text.trim()
            : 'Other reason')
        : _selectedReason;

    final otherDetails = _selectedReason == 'Other reason'
        ? _otherReasonController.text.trim()
        : null;

    final result = await ApiService.requestStrangersMeetCancellation(
      widget.meetId,
      reason: reasonText,
      otherReasonText: otherDetails,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message'] ??
                'Cancellation request sent to host for approval.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onCancelled?.call();
    } else {
      final msg = result['message']?.toString() ?? '';
      if (msg.toLowerCase().contains('not a participant')) {
        Navigator.pop(context, false);
        StrangersMeetHostCancellationDialog.show(
          context,
          meetId: widget.meetId,
          subject: widget.subject,
          venueName: widget.venueName,
          joinedCount: 0,
          collectedAmount: 0.0,
          onCancelled: widget.onCancelled,
        );
        return;
      }
      setState(() {
        _isSubmitting = false;
        _errorMessage =
            msg.isNotEmpty ? msg : 'Failed to submit cancellation request.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF13131A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFF2A2A3C), width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.cancel_rounded,
                      color: Color(0xFFEF4444),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cancel Stranger Meet?',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Paid Amount & Refund summary card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E2E48)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Your Paid Amount:',
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '₹${widget.paidAmount.toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Refund Policy:',
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Subject to Host Approval',
                            style: GoogleFonts.inter(
                              color: const Color(0xFFF59E0B),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'If approved by the host, ₹${widget.paidAmount.toStringAsFixed(0)} will be credited directly to your Lunara Smart Wallet.',
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Reason dropdown / selection
              Text(
                'Reason for Cancellation',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E2E48)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedReason,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E1E2E),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    items: _reasons.map((r) {
                      return DropdownMenuItem<String>(
                        value: r,
                        child: Text(
                          r,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedReason = val);
                      }
                    },
                  ),
                ),
              ),

              if (_selectedReason == 'Other reason') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _otherReasonController,
                  maxLines: 2,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Please specify the reason...',
                    hintStyle: GoogleFonts.inter(
                        color: Colors.white30, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF1E1E2E),
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2E2E48)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2E2E48)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: LunaraTheme.electricViolet),
                    ),
                  ),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.inter(
                              color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF3B3B52)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Keep Stranger Meet',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          _isSubmitting ? null : _submitCancellationRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Request Cancellation',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
