// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class PartnerReachConfirmationDialog extends StatefulWidget {
  final String planId;
  final String stage; // 'first_check' or 'final_check'
  final String partnerName;
  final String? partnerPhoto;
  final String planTitle;
  final String venueName;
  final DateTime eventDateTime;
  final VoidCallback? onCompleted;

  const PartnerReachConfirmationDialog({
    super.key,
    required this.planId,
    required this.stage,
    required this.partnerName,
    this.partnerPhoto,
    required this.planTitle,
    required this.venueName,
    required this.eventDateTime,
    this.onCompleted,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String planId,
    required String stage,
    required String partnerName,
    String? partnerPhoto,
    required String planTitle,
    required String venueName,
    required DateTime eventDateTime,
    VoidCallback? onCompleted,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PartnerReachConfirmationDialog(
        planId: planId,
        stage: stage,
        partnerName: partnerName,
        partnerPhoto: partnerPhoto,
        planTitle: planTitle,
        venueName: venueName,
        eventDateTime: eventDateTime,
        onCompleted: onCompleted,
      ),
    );
  }

  @override
  State<PartnerReachConfirmationDialog> createState() =>
      _PartnerReachConfirmationDialogState();
}

class _PartnerReachConfirmationDialogState
    extends State<PartnerReachConfirmationDialog> {
  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _handleResponse(bool hasReached) async {
    final currentUid = ApiService.currentUserId;
    if (currentUid == null) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.confirmArrival(
        planId: widget.planId,
        userId: currentUid,
        hasArrived: hasReached,
        stage: widget.stage,
      );

      if (res['success'] == true) {
        if (mounted) {
          Navigator.of(context).pop(true);
          widget.onCompleted?.call();

          final isFirst = widget.stage == 'first_check' || widget.stage == 'pre_event_check';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isFirst
                    ? 'First evidence recorded. Final confirmation will occur at party start time.'
                    : (hasReached
                        ? 'Final confirmation submitted. Presence verified.'
                        : 'Final confirmation submitted.'),
                style: GoogleFonts.inter(color: Colors.white),
              ),
              backgroundColor: const Color(0xFF8B5CF6),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage = res['message'] ?? 'Failed to submit response';
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
    final isFirstStage = widget.stage == 'first_check' || widget.stage == 'pre_event_check';
    final dateStr = DateFormat('EEE, d MMM • h:mm a').format(widget.eventDateTime);

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

          // Header Badge & Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isFirstStage
                      ? const Color(0xFF3B82F6).withOpacity(0.15)
                      : const Color(0xFF8B5CF6).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isFirstStage ? Icons.location_on_outlined : Icons.verified_user_outlined,
                  color: isFirstStage ? const Color(0xFF3B82F6) : const Color(0xFF8B5CF6),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFirstStage ? 'Pre-Event Reach Check' : 'FINAL CONFIRMATION',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      isFirstStage ? 'Stage 1 — First Evidence' : 'Stage 2 — Final Verification at Party Time',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isFirstStage ? const Color(0xFF60A5FA) : const Color(0xFFA78BFA),
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

          // Partner Card
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
                  backgroundImage: widget.partnerPhoto != null && widget.partnerPhoto!.isNotEmpty
                      ? NetworkImage(widget.partnerPhoto!)
                      : null,
                  child: widget.partnerPhoto == null || widget.partnerPhoto!.isEmpty
                      ? Text(
                          widget.partnerName.isNotEmpty ? widget.partnerName[0].toUpperCase() : 'P',
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
                        'Has ${widget.partnerName} reached?',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Confirm partner presence at venue',
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

          // Event Info Box
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
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Policy Info Notice
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isFirstStage ? const Color(0xFF1A2634) : const Color(0xFF1F1A33),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isFirstStage ? const Color(0xFF2B4C6F) : const Color(0xFF4A3B6B),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: isFirstStage ? const Color(0xFF60A5FA) : const Color(0xFFA78BFA),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isFirstStage
                        ? 'This is the first reach check evidence (30 min before event). It will be saved permanently. The final confirmation at party start time determines wallet refund eligibility.'
                        : 'This is the FINAL CONFIRMATION for your Party Plan. If both participants are confirmed present, ₹99 Commitment Deposit is refunded to your Lunara Wallet.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isFirstStage ? const Color(0xFF93C5FD) : const Color(0xFFC4B5FD),
                      height: 1.35,
                    ),
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

          // Action Buttons: YES / NO
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : () => _handleResponse(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFFFF4D4D)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    'No, Has Not Reached',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFFF4D4D),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : () => _handleResponse(true),
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
                          'Yes, Partner Has Reached',
                          style: GoogleFonts.inter(
                            fontSize: 13,
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
