// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class PartnerReachConfirmationDialog extends StatefulWidget {
  final String planId;
  final String stage; // e.g. 'thirty_min_reach', 'first_check', or 'final_check'
  final String partnerName;
  final String? partnerPhoto;
  final bool isHost;
  final String? hostName;
  final String? hostPhoto;
  final String planTitle;
  final String venueName;
  final DateTime eventDateTime;
  final String eventKey;
  final VoidCallback? onCompleted;

  const PartnerReachConfirmationDialog({
    super.key,
    required this.planId,
    this.stage = 'thirty_min_reach',
    required this.partnerName,
    this.partnerPhoto,
    this.isHost = false,
    this.hostName,
    this.hostPhoto,
    required this.planTitle,
    required this.venueName,
    required this.eventDateTime,
    required this.eventKey,
    this.onCompleted,
  });

  // Track responded event keys and open dialogs to ensure deduplication across popup and notifications
  static final Set<String> _respondedEventKeys = {};
  static final Set<String> _currentlyOpenPlanIds = {};

  static Future<bool?> show(
    BuildContext context, {
    required String planId,
    String stage = 'thirty_min_reach',
    required String partnerName,
    String? partnerPhoto,
    bool isHost = false,
    String? hostName,
    String? hostPhoto,
    required String planTitle,
    required String venueName,
    required DateTime eventDateTime,
    String? eventKey,
    VoidCallback? onCompleted,
  }) {
    final key = eventKey ?? 'PARTY_PLAN_VENUE_REACH_CONFIRMATION_$planId';

    // Deduplication check: do not open popup if already responded or already open
    if (_respondedEventKeys.contains(key) || _currentlyOpenPlanIds.contains(planId)) {
      debugPrint('📍 Reach confirmation dialog suppressed for $key (already responded or currently open)');
      return Future.value(null);
    }

    _currentlyOpenPlanIds.add(planId);

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PartnerReachConfirmationDialog(
        planId: planId,
        stage: stage,
        partnerName: partnerName,
        partnerPhoto: partnerPhoto,
        isHost: isHost,
        hostName: hostName,
        hostPhoto: hostPhoto,
        planTitle: planTitle,
        venueName: venueName,
        eventDateTime: eventDateTime,
        eventKey: key,
        onCompleted: onCompleted,
      ),
    ).whenComplete(() {
      _currentlyOpenPlanIds.remove(planId);
    });
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
      final cleanPlanId = widget.planId.replaceFirst(
        RegExp(r'^(pp_|party_plan_|party_plan_timeline_)', caseSensitive: false),
        '',
      );
      final res = await ApiService.confirmArrival(
        planId: cleanPlanId,
        userId: currentUid,
        hasArrived: hasReached,
        stage: widget.stage,
        source: 'POPUP',
        notificationId: widget.eventKey,
      );

      if (res['success'] == true || res['alreadyConfirmed'] == true) {
        // Mark as responded so the popup is never reshown for this plan
        PartnerReachConfirmationDialog._respondedEventKeys.add(widget.eventKey);

        if (mounted) {
          Navigator.of(context).pop(true);
          widget.onCompleted?.call();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                res['message'] ?? (hasReached
                    ? '✓ Venue arrival confirmed! Waiting for partner.'
                    : 'Recorded: Not reached yet.'),
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              backgroundColor: hasReached ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
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
        _errorMessage = 'Connection error. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm a').format(widget.eventDateTime);
    final dateStr = DateFormat('EEE, d MMM').format(widget.eventDateTime);

    final resolvedHostName = widget.hostName?.trim().isNotEmpty == true
        ? widget.hostName!.trim()
        : (widget.isHost ? 'You (Host)' : 'Host');
    final resolvedPartnerName = widget.partnerName.trim().isNotEmpty
        ? widget.partnerName.trim()
        : (widget.isHost ? 'Partner' : 'You (Partner)');

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
                  color: const Color(0xFF8B5CF6).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Color(0xFF8B5CF6),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isHost
                          ? '📍 Venue Arrival Confirmation'
                          : '📍 Party Plan Venue Confirmation',
                      style: GoogleFonts.outfit(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '30-Minute Venue Reach Check',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFFA78BFA),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFF2A273F), height: 1),
          const SizedBox(height: 14),

          // Participants Summary Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1F1B2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A273F)),
            ),
            child: Column(
              children: [
                // Host row
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF3B3654),
                      backgroundImage: widget.hostPhoto != null && widget.hostPhoto!.isNotEmpty
                          ? NetworkImage(widget.hostPhoto!)
                          : null,
                      child: widget.hostPhoto == null || widget.hostPhoto!.isEmpty
                          ? Text(
                              resolvedHostName.isNotEmpty ? resolvedHostName[0].toUpperCase() : 'H',
                              style: GoogleFonts.outfit(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Host: $resolvedHostName',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            widget.isHost ? 'You are hosting this plan' : 'Party Plan Host',
                            style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: Color(0xFF2A273F), height: 1),
                ),
                // Partner row
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF3B3654),
                      backgroundImage: widget.partnerPhoto != null && widget.partnerPhoto!.isNotEmpty
                          ? NetworkImage(widget.partnerPhoto!)
                          : null,
                      child: widget.partnerPhoto == null || widget.partnerPhoto!.isEmpty
                          ? Text(
                              resolvedPartnerName.isNotEmpty ? resolvedPartnerName[0].toUpperCase() : 'P',
                              style: GoogleFonts.outfit(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Partner: $resolvedPartnerName',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            widget.isHost ? 'You are meeting with partner' : 'You are joining this plan',
                            style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Venue and Time Details Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1728),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: Color(0xFF9D8EFF), size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.venueName,
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded, color: Colors.white54, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '$dateStr • $timeStr',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Central Question
          Center(
            child: Text(
              'Have you reached the venue?',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Confirm your arrival. Once both participants confirm, ₹99 deposit is refunded to your wallet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: Colors.white60,
                height: 1.3,
              ),
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                _errorMessage!,
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFFF4D4D), fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 18),

          // Action Buttons: YES, I HAVE REACHED / NO, NOT YET
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : () => _handleResponse(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    'NO, NOT YET',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : () => _handleResponse(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
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
                          'YES, I HAVE REACHED',
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
