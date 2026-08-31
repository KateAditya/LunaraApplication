import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../services/api_service.dart';

class LargePartyCancellationDialog extends StatefulWidget {
  final String bookingId;
  final String partySubject;
  final String venueName;
  final String scheduledDate;
  final String scheduledTime;
  final double amountPaid;
  final VoidCallback? onSubmitted;

  const LargePartyCancellationDialog({
    super.key,
    required this.bookingId,
    required this.partySubject,
    required this.venueName,
    required this.scheduledDate,
    required this.scheduledTime,
    required this.amountPaid,
    this.onSubmitted,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String bookingId,
    required String partySubject,
    required String venueName,
    required String scheduledDate,
    required String scheduledTime,
    required double amountPaid,
    VoidCallback? onSubmitted,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => LargePartyCancellationDialog(
        bookingId: bookingId,
        partySubject: partySubject,
        venueName: venueName,
        scheduledDate: scheduledDate,
        scheduledTime: scheduledTime,
        amountPaid: amountPaid,
        onSubmitted: onSubmitted,
      ),
    );
  }

  @override
  State<LargePartyCancellationDialog> createState() =>
      _LargePartyCancellationDialogState();
}

class _LargePartyCancellationDialogState
    extends State<LargePartyCancellationDialog> {
  final List<String> _commonReasons = [
    'Medical / Family Emergency',
    'Travel / Transportation Issue',
    'Friends / Group Cannot Attend',
    'Event Rescheduled / Postponed',
    'Venue / Scheduling Conflict',
    'Other Reason',
  ];

  String? _selectedReason;
  final TextEditingController _reasonDetailsController =
      TextEditingController();
  final TextEditingController _upiController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _accountHolderController =
      TextEditingController();
  final TextEditingController _accountNumberController =
      TextEditingController();
  final TextEditingController _ifscController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reasonDetailsController.dispose();
    _upiController.dispose();
    _mobileController.dispose();
    _accountHolderController.dispose();
    _accountNumberController.dispose();
    _ifscController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_selectedReason == null) {
      setState(() {
        _errorMessage = 'Please select a reason for cancellation.';
      });
      return;
    }

    final reason = _selectedReason!;
    final reasonDetails = _reasonDetailsController.text.trim();
    final upiId = _upiController.text.trim();
    final mobileNumber = _mobileController.text.trim();
    final accountHolder = _accountHolderController.text.trim();
    final accountNumber = _accountNumberController.text.trim();
    final ifsc = _ifscController.text.trim();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.requestLargePartyCancellation(
        bookingId: widget.bookingId,
        reason: reason,
        reasonDetails: reasonDetails.isNotEmpty ? reasonDetails : null,
        upiId: upiId.isNotEmpty ? upiId : null,
        mobileNumber: mobileNumber.isNotEmpty ? mobileNumber : null,
        accountHolderName: accountHolder.isNotEmpty ? accountHolder : null,
        accountNumber: accountNumber.isNotEmpty ? accountNumber : null,
        ifscCode: ifsc.isNotEmpty ? ifsc : null,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        widget.onSubmitted?.call();
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['message'] ??
                  'Cancellation request submitted. Lunara Admin will review it shortly.',
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _errorMessage =
              res['message'] ?? 'Failed to submit cancellation request.';
          _isSubmitting = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Network error. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F1117),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF2A2E3D), width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.cancel_presentation_rounded,
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
                          'Cancel Large Party',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Host Cancellation Request',
                          style: GoogleFonts.outfit(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Party summary card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1D26),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A2E3D)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.celebration_rounded,
                          color: LunaraTheme.electricViolet,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.partySubject,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                widget.venueName,
                                style: GoogleFonts.outfit(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFF2A2E3D), height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date & Time',
                              style: GoogleFonts.outfit(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${widget.scheduledDate} • ${widget.scheduledTime}',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Amount Paid',
                              style: GoogleFonts.outfit(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '₹${widget.amountPaid.toInt()}',
                              style: GoogleFonts.outfit(
                                color: const Color(0xFF10B981),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Reason selection header
              Text(
                'Please provide a valid reason for cancellation:',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              // Reason options
              ..._commonReasons.map((reason) {
                final isSelected = _selectedReason == reason;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedReason = reason;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? LunaraTheme.electricViolet.withValues(alpha: 0.12)
                          : const Color(0xFF1A1D26),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? LunaraTheme.electricViolet
                            : const Color(0xFF2A2E3D),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: isSelected
                              ? LunaraTheme.electricViolet
                              : Colors.white38,
                          size: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            reason,
                            style: GoogleFonts.outfit(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 10),

              // Optional details text field
              Text(
                'Additional Details (Optional):',
                style: GoogleFonts.outfit(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonDetailsController,
                maxLines: 2,
                maxLength: 250,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Explain any additional details...',
                  hintStyle:
                      GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF1A1D26),
                  counterStyle: GoogleFonts.outfit(
                      color: Colors.white30, fontSize: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF2A2E3D)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF2A2E3D)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: LunaraTheme.electricViolet),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),

              const SizedBox(height: 14),

              // Refund payment details section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF141721),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A2E3D)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.account_balance_rounded,
                          color: Color(0xFF60A5FA),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Refund Payout Details',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Provide UPI ID or Bank details if manual settlement is required by Admin:',
                      style: GoogleFonts.outfit(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // UPI ID
                    _buildTextField(
                      label: 'UPI ID',
                      hint: 'username@bank',
                      controller: _upiController,
                    ),
                    const SizedBox(height: 8),

                    // Mobile Number
                    _buildTextField(
                      label: 'Mobile Number',
                      hint: '10-digit mobile number',
                      controller: _mobileController,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 8),

                    // Bank Account Holder
                    _buildTextField(
                      label: 'Bank Account Holder Name',
                      hint: 'Full name as in bank',
                      controller: _accountHolderController,
                    ),
                    const SizedBox(height: 8),

                    // Bank Account Number & IFSC
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildTextField(
                            label: 'Account Number',
                            hint: 'Account No.',
                            controller: _accountNumberController,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: _buildTextField(
                            label: 'IFSC Code',
                            hint: 'HDFC0001234',
                            controller: _ifscController,
                            textCapitalization: TextCapitalization.characters,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Admin Review Notice
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      color: Color(0xFFF59E0B),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This request will be reviewed by Lunara Admin. Once approved, the refund will be processed according to the Lunara refund policy.',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFFFDE68A),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFEF4444), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.outfit(
                              color: const Color(0xFFEF4444), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF2A2E3D)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Keep Party',
                        style: GoogleFonts.outfit(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _handleSubmit,
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
                              'Submit Request',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            color: Colors.white60,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.outfit(color: Colors.white24, fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF0F1117),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2A2E3D)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2A2E3D)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: LunaraTheme.electricViolet),
            ),
          ),
        ),
      ],
    );
  }
}
