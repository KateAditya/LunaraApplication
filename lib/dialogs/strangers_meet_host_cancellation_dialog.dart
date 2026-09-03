// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../core/theme.dart';

class StrangersMeetHostCancellationDialog extends StatefulWidget {
  final String meetId;
  final String subject;
  final String venueName;
  final int joinedCount;
  final double collectedAmount;
  final String? date;
  final String? time;
  final int? totalCapacity;
  final int? paidCount;
  final double? hostDeposit;
  final VoidCallback? onCancelled;

  const StrangersMeetHostCancellationDialog({
    super.key,
    required this.meetId,
    required this.subject,
    required this.venueName,
    required this.joinedCount,
    required this.collectedAmount,
    this.date,
    this.time,
    this.totalCapacity,
    this.paidCount,
    this.hostDeposit,
    this.onCancelled,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String meetId,
    required String subject,
    required String venueName,
    required int joinedCount,
    required double collectedAmount,
    String? date,
    String? time,
    int? totalCapacity,
    int? paidCount,
    double? hostDeposit,
    VoidCallback? onCancelled,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StrangersMeetHostCancellationDialog(
        meetId: meetId,
        subject: subject,
        venueName: venueName,
        joinedCount: joinedCount,
        collectedAmount: collectedAmount,
        date: date,
        time: time,
        totalCapacity: totalCapacity,
        paidCount: paidCount,
        hostDeposit: hostDeposit,
        onCancelled: onCancelled,
      ),
    );
  }

  @override
  State<StrangersMeetHostCancellationDialog> createState() =>
      _StrangersMeetHostCancellationDialogState();
}

class _StrangersMeetHostCancellationDialogState
    extends State<StrangersMeetHostCancellationDialog> {
  String _selectedReason = 'Medical / Health Emergency';
  final TextEditingController _reasonTextController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  final List<String> _reasons = [
    'Medical / Health Emergency',
    'Scheduling / Unforeseen Conflict',
    'Venue / Location Issue',
    'Personal / Family Reasons',
    'Other Reason',
  ];

  @override
  void dispose() {
    _reasonTextController.dispose();
    super.dispose();
  }

  Future<void> _submitCancellationRequest() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.requestStrangersMeetHostCancellation(
        widget.meetId,
        reason: _selectedReason,
        reasonText: _reasonTextController.text.trim().isNotEmpty
            ? _reasonTextController.text.trim()
            : null,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        Navigator.pop(context, true);
        widget.onCancelled?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['message'] ??
                  'Cancellation request submitted for Admin Review.',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        setState(() {
          _errorMessage =
              res['message'] ?? 'Failed to submit cancellation request.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF13151B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFF262A36), width: 1.5),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.cancel_presentation_rounded,
                    color: Colors.amber,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cancel Stranger Meet',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Summary Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E222D),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2E3444)),
              ),
              child: Column(
                children: [
                  _buildSummaryRow('Meet:', widget.subject),
                  const SizedBox(height: 8),
                  _buildSummaryRow('Venue:', widget.venueName),
                  if (widget.date != null && widget.date!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildSummaryRow('Date:', widget.date!),
                  ],
                  if (widget.time != null && widget.time!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildSummaryRow('Time:', widget.time!),
                  ],
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'Joined participants:',
                    '${widget.joinedCount}${widget.totalCapacity != null ? ' / ${widget.totalCapacity}' : ''}',
                    valueColor: LunaraTheme.electricViolet,
                  ),
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'Paid participants:',
                    '${widget.paidCount ?? widget.joinedCount}',
                    valueColor: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'Amount collected from participants:',
                    '₹${widget.collectedAmount.toStringAsFixed(0)}',
                    valueColor: const Color(0xFF10B981),
                  ),
                  if (widget.hostDeposit != null && widget.hostDeposit! > 0) ...[
                    const SizedBox(height: 8),
                    _buildSummaryRow(
                      'Host confirmation/deposit:',
                      '₹${widget.hostDeposit!.toStringAsFixed(0)}',
                      valueColor: Colors.amber,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Notice Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF261D12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF78350F)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.joinedCount > 0
                          ? '${widget.joinedCount} participants have already paid for this meet. Cancelling the meet may require refunds to participating users. Are you sure you want to continue?'
                          : 'No participants have paid yet. Cancelling will close this meet immediately.',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFFFDE68A),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Reason Selector
            Text(
              'Please select a reason:',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),

            ..._reasons.map((reason) {
              final isSelected = _selectedReason == reason;
              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedReason = reason;
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? LunaraTheme.electricViolet.withOpacity(0.12)
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
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          reason,
                          style: GoogleFonts.outfit(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 13,
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

            // Optional note
            Text(
              'Additional Details (Optional):',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _reasonTextController,
              maxLines: 3,
              maxLength: 300,
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Explain the reason for cancellation...',
                hintStyle: GoogleFonts.outfit(
                  color: Colors.white38,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: const Color(0xFF1A1D26),
                counterStyle:
                    GoogleFonts.outfit(color: Colors.white30, fontSize: 11),
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
                  borderSide: const BorderSide(color: LunaraTheme.electricViolet),
                ),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.outfit(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Action Buttons (Section 3: CANCEL REQUEST / KEEP MEET)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFF383E50)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'KEEP MEET',
                      style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed:
                        _isSubmitting ? null : _submitCancellationRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'CANCEL REQUEST',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white60,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.outfit(
              color: valueColor ?? Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
