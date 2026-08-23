// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class PartyPlanCancellationDialog extends StatefulWidget {
  final String planId;
  final String requestId;
  final String requesterName;
  final String? requesterPhoto;
  final String planTitle;
  final String venueName;
  final DateTime eventDateTime;
  final String reason;
  final String? otherReasonText;
  final VoidCallback? onCompleted;

  const PartyPlanCancellationDialog({
    super.key,
    required this.planId,
    required this.requestId,
    required this.requesterName,
    this.requesterPhoto,
    required this.planTitle,
    required this.venueName,
    required this.eventDateTime,
    required this.reason,
    this.otherReasonText,
    this.onCompleted,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String planId,
    required String requestId,
    required String requesterName,
    String? requesterPhoto,
    required String planTitle,
    required String venueName,
    required DateTime eventDateTime,
    required String reason,
    String? otherReasonText,
    VoidCallback? onCompleted,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PartyPlanCancellationDialog(
        planId: planId,
        requestId: requestId,
        requesterName: requesterName,
        requesterPhoto: requesterPhoto,
        planTitle: planTitle,
        venueName: venueName,
        eventDateTime: eventDateTime,
        reason: reason,
        otherReasonText: otherReasonText,
        onCompleted: onCompleted,
      ),
    );
  }

  @override
  State<PartyPlanCancellationDialog> createState() =>
      _PartyPlanCancellationDialogState();
}

class _PartyPlanCancellationDialogState
    extends State<PartyPlanCancellationDialog> {
  bool _isSubmitting = false;
  String? _errorMessage;

  String _formatReason(String reasonKey, String? extraText) {
    switch (reasonKey.toLowerCase()) {
      case 'my_plans_changed':
        return 'My plans have changed';
      case 'not_available':
        return "I'm not available anymore";
      case 'not_interested':
        return 'Not interested anymore';
      case 'found_another_plan':
        return 'Found another plan';
      case 'venue_changed':
        return 'Venue changed';
      case 'personal_reasons':
        return 'Personal circumstances';
      case 'other':
        return extraText != null && extraText.isNotEmpty ? extraText : 'Other reason';
      default:
        return reasonKey.replaceAll('_', ' ');
    }
  }

  Future<void> _handleResponse(String action) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.respondToPartyPlanCancellationRequest(
        planId: widget.planId,
        requestId: widget.requestId,
        action: action,
      );

      if (res['success'] == true) {
        if (mounted) {
          Navigator.of(context).pop(true);
          widget.onCompleted?.call();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                action == 'approve'
                    ? 'Cancellation accepted. Commitment deposit credited to wallet.'
                    : 'Cancellation request declined. Party Plan remains confirmed.',
                style: GoogleFonts.inter(color: Colors.white),
              ),
              backgroundColor: action == 'approve' ? Colors.green : Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage = res['message'] ?? 'Failed to process request';
        });
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Connection error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEE, d MMM • h:mm a').format(widget.eventDateTime);
    final reasonDisplay = _formatReason(widget.reason, widget.otherReasonText);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF14121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0xFF2A273F), width: 1.5)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
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

          // Header Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4D4D).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFFF4D4D),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cancellation Request',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Action Required',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFFFF4D4D),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF2A273F), height: 1),
          const SizedBox(height: 16),

          // Requester Info Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1F1B2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A273F)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF3B3654),
                  backgroundImage: widget.requesterPhoto != null && widget.requesterPhoto!.isNotEmpty
                      ? NetworkImage(widget.requesterPhoto!)
                      : null,
                  child: widget.requesterPhoto == null || widget.requesterPhoto!.isEmpty
                      ? Text(
                          widget.requesterName.isNotEmpty ? widget.requesterName[0].toUpperCase() : 'U',
                          style: GoogleFonts.outfit(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.requesterName,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Requested to cancel this Party Plan',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Event & Reason Summary
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1728),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.event_outlined, color: Color(0xFF9D8EFF), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.planTitle.isNotEmpty ? widget.planTitle : 'Weekend Party Plan',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, color: Colors.white54, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      widget.venueName,
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.access_time_rounded, color: Colors.white54, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        dateStr,
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Color(0xFFFFB800), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reason: $reasonDisplay',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFFFD56B), fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Refund Notice
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF132A1D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF22543D)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF48BB78), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'If accepted, your ₹99 Commitment Deposit will be instantly credited to your Lunara Wallet.',
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9AE6B4)),
                  ),
                ),
              ],
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFFF4D4D)),
            ),
          ],
          const SizedBox(height: 20),

          // Action Buttons: Reject & Accept
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : () => _handleResponse('reject'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFFFF4D4D)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    'Reject',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFFF4D4D),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : () => _handleResponse('approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'Accept Cancellation',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
