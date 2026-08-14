import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../widgets/smart_checkout_sheet.dart';
import 'chat_screen.dart';
import 'party_plan_ticket_screen.dart';
import 'widgets/party_plan_arrival_dialog.dart';
import '../profile/lunara_wallet_screen.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

class _VenueImageFallback extends StatelessWidget {
  const _VenueImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2D0060), Color(0xFF0D001C)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.nightlife_rounded, color: Colors.white24, size: 72),
      ),
    );
  }
}

class PartyPlanDetailScreen extends StatefulWidget {
  final Map<String, dynamic> plan;

  const PartyPlanDetailScreen({super.key, required this.plan});

  @override
  State<PartyPlanDetailScreen> createState() => _PartyPlanDetailScreenState();
}

class _PartyPlanDetailScreenState extends State<PartyPlanDetailScreen> {
  bool _isJoining = false;
  bool _alreadyRequested = false;
  bool _isInvitedUser = false;
  bool _isAcceptingInvite = false;
  String? _requestStatus;
  String? _activeRequestId;
  String? _fetchedVenueImageUrl;
  Map<String, dynamic>? _cancellationRequest;
  bool _isWindowClosed = false;
  bool _isLoadingCancellation = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    final targetPlanId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    final syncRequested = ApiService.isPartyPlanRequestedSync(targetPlanId);
    final syncReqData = ApiService.getCachedPartyPlanRequestSync(targetPlanId);

    _alreadyRequested = widget.plan['hasRequested'] == true || syncRequested;
    if (syncReqData != null) {
      _activeRequestId = syncReqData['id']?.toString() ?? syncReqData['requestId']?.toString();
      _requestStatus = (syncReqData['status'] ?? syncReqData['joinerPaymentStatus'] ?? 'pending').toString().toLowerCase();
    }

    if (widget.plan['isInvite'] == true || widget.plan['isInvitedUser'] == true || widget.plan['type'] == 'party_plan_invitation' || widget.plan['eventType'] == 'party_plan_invitation') {
      _isInvitedUser = true;
    }
    if (widget.plan['requestId'] != null || widget.plan['activeRequestId'] != null) {
      _activeRequestId = (widget.plan['requestId'] ?? widget.plan['activeRequestId']).toString();
      _alreadyRequested = true;
    }
    _checkRequestStatus();
    _loadVenueDetailsIfNeeded();
    _refreshPlanDetails();
    _fetchCurrentUserAndCancellationState();
  }

  Future<void> _refreshPlanDetails() async {
    final planId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    if (planId.isEmpty) return;

    final plan = await ApiService.fetchPartyPlanDetail(planId);
    if (!mounted || plan == null) return;
    setState(() {
      // Preserve notification-only metadata (requestId, invitation state) while
      // replacing stale or partial card data with the server-authoritative plan.
      widget.plan.addAll(plan);
      widget.plan['planId'] = planId;
    });
    _checkRequestStatus();
    _fetchCurrentUserAndCancellationState();
  }

  Future<void> _fetchCurrentUserAndCancellationState() async {
    try {
      final uid = await ApiService.getCurrentUserId();
      final targetPlanId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
      
      final rawDateTime = widget.plan['planDateTime'] ?? widget.plan['planDate'];
      if (rawDateTime != null) {
        try {
          final eventTime = DateTime.parse(rawDateTime.toString()).toLocal();
          final diff = eventTime.difference(DateTime.now());
          if (diff.inHours < 3) {
            if (mounted) setState(() => _isWindowClosed = true);
          }
        } catch (_) {}
      }

      if (targetPlanId.isNotEmpty) {
        final res = await ApiService.getPartyPlanCancellationRequest(targetPlanId);
        if (mounted) {
          final cancelReq = res?['cancellationRequest'];
          setState(() {
            _currentUserId = uid;
            if (res?['isWindowClosed'] == true) _isWindowClosed = true;
            _cancellationRequest = cancelReq is Map<String, dynamic>
                ? cancelReq
                : (cancelReq is Map ? Map<String, dynamic>.from(cancelReq) : null);
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching cancellation state: $e');
    }
  }

  void _showCancellationStep1Dialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text('CANCEL THIS PLAN?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This action will notify the other participant. Both participants must confirm the cancellation before the Party Plan is cancelled.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              'Frequent cancellations may affect your Commitment Deposit / Reliability Score.',
              style: TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.w600, height: 1.3),
            ),
            SizedBox(height: 14),
            Text('If approved:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            SizedBox(height: 6),
            Text('• Commitment Deposit (₹99) will be returned to both users\' Lunara Wallets.', style: TextStyle(color: Colors.white60, fontSize: 12)),
            SizedBox(height: 4),
            Text('• Chat will become read-only (archived after 24h).', style: TextStyle(color: Colors.white60, fontSize: 12)),
            SizedBox(height: 4),
            Text('• Reliability Score may decrease for initiator (-5 pts).', style: TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('KEEP PLAN', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showCancellationStep2ReasonModal();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('REQUEST CANCELLATION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  void _showCancellationStep2ReasonModal() {
    String selectedReason = 'my_plans_changed';
    final TextEditingController otherController = TextEditingController();

    final Map<String, String> reasonOptions = {
      'my_plans_changed': 'My plans have changed',
      'not_available': 'I\'m not available anymore',
      'not_interested': 'Not interested anymore',
      'found_another_plan': 'Found another plan',
      'venue_changed': 'Venue changed',
      'personal_reasons': 'Personal reasons',
      'other': 'Other',
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                    ),
                    const SizedBox(height: 16),
                    const Text('Why are you cancelling?', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text('Select a reason for internal record. This is never displayed publicly.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 16),
                    ...reasonOptions.entries.map((entry) {
                      final isSelected = selectedReason == entry.key;
                      return InkWell(
                        onTap: () => setModalState(() => selectedReason = entry.key),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.redAccent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSelected ? Colors.redAccent : Colors.white10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: isSelected ? Colors.redAccent : Colors.white38,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(entry.value, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (selectedReason == 'other') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: otherController,
                        maxLength: 150,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Enter reason (max 150 characters)',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isLoadingCancellation
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _submitCancellationRequest(selectedReason, selectedReason == 'other' ? otherController.text.trim() : null);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('SUBMIT CANCELLATION REQUEST', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitCancellationRequest(String reason, String? otherText) async {
    final planId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    if (planId.isEmpty) return;

    setState(() => _isLoadingCancellation = true);
    final res = await ApiService.requestPartyPlanCancellation(
      planId: planId,
      reason: reason,
      otherReasonText: otherText,
    );
    if (!mounted) return;
    setState(() => _isLoadingCancellation = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cancellation request sent. Waiting for the other participant to approve.'), backgroundColor: Colors.orangeAccent),
      );
      _fetchCurrentUserAndCancellationState();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Failed to send cancellation request'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _respondToCancellation(String requestId, String action) async {
    final planId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    if (planId.isEmpty) return;

    setState(() => _isLoadingCancellation = true);
    final res = await ApiService.respondToPartyPlanCancellationRequest(
      planId: planId,
      requestId: requestId,
      action: action,
    );
    if (!mounted) return;
    setState(() => _isLoadingCancellation = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'approve' ? 'Party Plan cancelled. ₹99 Commitment Deposit credited to your Lunara Wallet!' : 'Cancellation request declined.'),
          backgroundColor: action == 'approve' ? Colors.green : Colors.grey.shade800,
        ),
      );
      _fetchCurrentUserAndCancellationState();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Action failed'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildCancellationSection() {
    final status = widget.plan['status']?.toString();
    final isCancelled = status == 'cancelled';

    // Before host acceptance, this user owns a request rather than a booking.
    // Its only cancellation action is the request-level action in the bottom CTA.
    if (_alreadyRequested && _requestStatus == 'pending' && !_isInvitedUser) {
      return const SizedBox.shrink();
    }

    if (_isExpired) {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.timer_off_rounded, color: Colors.grey, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'This Party Plan has expired. No further actions or join requests can be made.',
                style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    if (isCancelled) {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'This Party Plan has been cancelled. Commitment deposits have been credited to Lunara Wallets.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    if (_isWindowClosed) {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_rounded, color: Colors.amber, size: 18),
                SizedBox(width: 8),
                Text(
                  'BOOKING LOCKED',
                  style: TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ],
            ),
            SizedBox(height: 6),
            Text(
              'This Party Plan can no longer be cancelled because the cancellation window has closed (less than 3 hours before event start time).',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      );
    }

    if (_cancellationRequest != null && _cancellationRequest!['status'] == 'pending') {
      final reqId = _cancellationRequest!['id']?.toString() ?? '';
      final requestedById = _cancellationRequest!['requestedById']?.toString() ?? '';
      final isRecipient = _currentUserId != null && requestedById != _currentUserId;
      final requesterObj = _cancellationRequest!['requester'] as Map<String, dynamic>?;
      final requesterName = requesterObj?['firstName'] ?? 'The other participant';
      final reasonKey = _cancellationRequest!['reason']?.toString() ?? '';

      final Map<String, String> reasonLabels = {
        'my_plans_changed': 'My plans have changed',
        'not_available': 'I\'m not available anymore',
        'not_interested': 'Not interested anymore',
        'found_another_plan': 'Found another plan',
        'venue_changed': 'Venue changed',
        'personal_reasons': 'Personal reasons',
        'other': 'Other reasons',
      };
      final reasonText = reasonLabels[reasonKey] ?? reasonKey;

      if (isRecipient) {
        return Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1F1D2B),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cancellation Request Received',
                      style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$requesterName wants to cancel this Party Plan.',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'Reason: "$reasonText"',
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 12),
              const Text('If you approve:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              const Text('• Both Commitment Deposits (₹99) will be credited to each user\'s Lunara Wallet.', style: TextStyle(color: Colors.white54, fontSize: 11)),
              const Text('• Chat becomes read-only.', style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoadingCancellation ? null : () => _respondToCancellation(reqId, 'reject'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white30),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('KEEP PLAN', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoadingCancellation ? null : () => _respondToCancellation(reqId, 'approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('CONFIRM CANCELLATION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      } else {
        return Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.hourglass_top_rounded, color: Colors.orangeAccent, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cancellation Request Pending — Waiting for the other participant to approve.',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }
    }

    // Default: Show subtle red outline "Cancel Party Plan" button — HOST ONLY
    if (!_isHostPlan(widget.plan)) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: _isLoadingCancellation ? null : _showCancellationStep1Dialog,
        icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 18),
        label: const Text(
          'Cancel Party Plan',
          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.5),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5), width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: Colors.redAccent.withValues(alpha: 0.05),
        ),
      ),
    );
  }

  Widget _buildArrivalConfirmationCard() {
    final isConfirmed = widget.plan['hasConfirmedBooking'] == true ||
        widget.plan['lifecycleStatus'] == 'match_confirmed' ||
        widget.plan['lifecycleStatus'] == 'chat_enabled' ||
        widget.plan['lifecycleStatus'] == 'plan_completed';
    if (!isConfirmed) return const SizedBox.shrink();

    final planId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    final venue = (widget.plan['venue'] is Map) ? widget.plan['venue'] as Map<String, dynamic> : <String, dynamic>{};
    final venueName = venue['name']?.toString() ?? widget.plan['venueName']?.toString() ?? 'the venue';

    final hostReached = widget.plan['hostArrivalConfirmed'] == true;
    final guestReached = widget.plan['guestArrivalConfirmed'] == true;
    final bothReached = hostReached && guestReached;
    final isRefunded = widget.plan['hostPaymentStatus'] == 'refunded' ||
        widget.plan['joinerPaymentStatus'] == 'refunded' ||
        widget.plan['lifecycleStatus'] == 'plan_completed' ||
        widget.plan['paymentStatus']?.toString().toLowerCase().contains('refunded') == true;

    final bool isHost = _isHostPlan(widget.plan);
    final userReached = isHost ? hostReached : guestReached;
    final partnerReached = isHost ? guestReached : hostReached;

    if (bothReached || isRefunded) {
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.celebration_rounded, color: Color(0xFF10B981), size: 20),
                SizedBox(width: 8),
                Text(
                  '🎉 PARTY COMPLETED',
                  style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Both participants confirmed arrival! ₹99 Commitment Deposit has been refunded to your LUNARA Wallet.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LunaraWalletScreen()),
                ),
                icon: const Icon(Icons.account_balance_wallet_rounded, size: 16),
                label: const Text('VIEW WALLET', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (userReached && !partnerReached) {
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pin_drop_rounded, color: Color(0xFF6366F1), size: 20),
                SizedBox(width: 8),
                Text(
                  '📍 ARRIVAL CONFIRMED',
                  style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
                ),
              ],
            ),
            SizedBox(height: 6),
            Text(
              'You confirmed arrival (✓ Reached). Waiting for your partner\'s confirmation (⏳ Waiting) to process your ₹99 Commitment Deposit refund.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1B2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pin_drop_rounded, color: LunaraTheme.electricViolet, size: 20),
              SizedBox(width: 8),
              Text(
                '📍 ARE YOU AT THE VENUE?',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Have you reached the venue? Confirming arrival guarantees your Commitment Deposit refund.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    final uid = await ApiService.getCurrentUserId();
                    if (planId.isNotEmpty && uid != null && uid.isNotEmpty) {
                      final res = await ApiService.confirmArrival(planId: planId, userId: uid, hasArrived: true);
                      if (res['bothArrived'] == true && mounted) {
                        PartyPlanArrivalDialog.showBothArrivedSuccessDialog(
                          context,
                          venueName: venueName,
                          plan: widget.plan,
                        );
                      } else if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✓ Arrival confirmed! Waiting for your partner.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                      _refreshPlanDetails();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('YES — I\'M HERE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final uid = await ApiService.getCurrentUserId();
                    if (planId.isNotEmpty && uid != null && uid.isNotEmpty) {
                      await ApiService.confirmArrival(planId: planId, userId: uid, hasArrived: false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Recorded: NOT YET. Confirm when you reach.'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                      _refreshPlanDetails();
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white30),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('NOT YET', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _loadVenueDetailsIfNeeded() async {
    final initialUrl = _getVenueImageUrl();
    if (initialUrl != null && initialUrl.isNotEmpty) return;

    final venueId = widget.plan['venueId']?.toString() ??
        widget.plan['venue']?['id']?.toString() ??
        '';
    if (venueId.isEmpty) return;

    try {
      final response = await ApiService.get('/api/venues/$venueId');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['venue'] is Map) {
          final v = Map<String, dynamic>.from(data['venue']);
          final raw = v['imageUrl'] ??
              v['coverImageUrl'] ??
              v['coverImage'] ??
              v['image'] ??
              (v['gallery'] is List && (v['gallery'] as List).isNotEmpty
                  ? (v['gallery'] as List).first
                  : null) ??
              (v['images'] is List && (v['images'] as List).isNotEmpty
                  ? ((v['images'] as List).first is Map
                      ? ((v['images'] as List).first['filePath'] ??
                          (v['images'] as List).first['url'] ??
                          (v['images'] as List).first['imageUrl'])
                      : (v['images'] as List).first)
                  : null);
          if (raw != null) {
            final formatted = ApiService.formatImageUrl(raw);
            if (mounted && formatted != null && formatted.isNotEmpty) {
              setState(() {
                _fetchedVenueImageUrl = formatted;
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading venue details in PartyPlanDetailScreen: $e');
    }
  }

  String? _getVenueImageUrl() {
    if (_fetchedVenueImageUrl != null && _fetchedVenueImageUrl!.isNotEmpty) {
      return _fetchedVenueImageUrl;
    }
    final venue = widget.plan['venue'] as Map<String, dynamic>? ?? {};
    final plan = widget.plan;

    final raw = venue['imageUrl'] ??
        venue['coverImageUrl'] ??
        venue['cover_image_url'] ??
        venue['image'] ??
        venue['coverImage'] ??
        (venue['images'] is List && (venue['images'] as List).isNotEmpty
            ? ((venue['images'] as List).first is Map
                ? ((venue['images'] as List).first['filePath'] ??
                    (venue['images'] as List).first['url'] ??
                    (venue['images'] as List).first['imageUrl'])
                : (venue['images'] as List).first)
            : null) ??
        plan['venueImageUrl'] ??
        plan['venue_image_url'] ??
        plan['venueImage'] ??
        plan['imageUrl'] ??
        plan['image'];

    final formatted = ApiService.formatImageUrl(raw);
    if (formatted != null && formatted.isNotEmpty) {
      return formatted;
    }
    // Do not mask a missing venue image with a generic club photo. Returning
    // null lets the detail page load the selected venue and, only if it has no
    // image, render the branded gradient fallback.
    return null;
  }

  Future<void> _checkRequestStatus() async {
    try {
      // The host has no join request for their own plan. Avoid deriving the
      // host CTA from participant request cache/state.
      if (_isHostPlan(widget.plan)) return;
      final myRequests = await ApiService.fetchMyPartyPlanRequests();
      final targetPlanId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
      if (targetPlanId.isEmpty) return;
      
      bool requested = false;
      bool isInvited = _isInvitedUser;
      String? reqStatus;
      String? reqId;

      for (final req in myRequests) {
        final planId = req['partyPlanId']?.toString() ?? req['planId']?.toString() ?? req['plan']?['id']?.toString();
        if (planId == targetPlanId) {
          requested = true;
          reqId = req['id']?.toString();
          reqStatus = (req['status'] ?? req['joinerPaymentStatus'] ?? 'pending').toString().toLowerCase();

          final reqIsInvite = req['isPrivateInvite'] == true ||
              req['invitedBy'] != null ||
              req['type'] == 'invitation' ||
              (req['plan'] != null && (req['plan']['visibility'] == 'private' || req['plan']['visibility'] == 'both'));
          if (reqIsInvite) {
            isInvited = true;
          }
          break;
        }
      }

      final planData = widget.plan;
      final visibility = (planData['visibility'] ?? '').toString().toLowerCase();
      final currentUserId = ApiService.currentUserId;
      final hostId = (planData['userId'] ?? planData['hostId'] ?? '').toString();
      if ((visibility == 'private' || visibility == 'both') && currentUserId != null && currentUserId != hostId && requested) {
        isInvited = true;
      }

      if (mounted) {
        setState(() {
          _alreadyRequested = requested;
          _isInvitedUser = isInvited;
          _activeRequestId = reqId ?? _activeRequestId;
          _requestStatus = reqStatus;
        });
      }
    } catch (e) {
      debugPrint('Error checking request status in PartyPlanDetailScreen: $e');
    }
  }

  Future<void> _handleAcceptInvite() async {
    if (_activeRequestId == null || _activeRequestId!.isEmpty) return;
    setState(() => _isAcceptingInvite = true);
    try {
      final res = await ApiService.acceptPartyPlanInvite(_activeRequestId!);
      if (!mounted) return;
      setState(() => _isAcceptingInvite = false);

      if (res != null && res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Invite Accepted! Party Plan confirmed.'),
            backgroundColor: Colors.green,
          ),
        );
        _checkRequestStatus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res?['message'] ?? 'Failed to accept invite'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAcceptingInvite = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accepting invite: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmRequestExit({required bool withdraw}) async {
    if (_activeRequestId == null || _activeRequestId!.isEmpty) return;
    final label = withdraw ? 'Withdraw request' : 'Cancel request';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$label?'),
        content: Text(withdraw
            ? 'Your payment has not been completed. This closes your payment window.'
            : 'You can cancel this request before the host accepts it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('KEEP REQUEST')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(withdraw ? 'WITHDRAW' : 'CANCEL REQUEST'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoadingCancellation = true);
    final success = withdraw
        ? await ApiService.withdrawPartyPlanRequest(_activeRequestId!)
        : await ApiService.cancelPartyPlanRequest(_activeRequestId!);
    if (!mounted) return;
    setState(() {
      _isLoadingCancellation = false;
      if (success) _requestStatus = 'cancelled';
    });
    final action = withdraw ? 'withdrawn' : 'cancelled';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success ? 'Request $action' : 'Unable to update this request. Please refresh and try again.'),
      backgroundColor: success ? Colors.green : Colors.red,
    ));
  }

  void _startRazorpayDirectPayment(String reqId, String venueName, {String? orderId, double depositAmount = 99.0}) async {
    String currentOrderId = (orderId ?? '').trim();
    String razorpayKey = 'rzp_test_123';

    if (currentOrderId.isEmpty) {
      final initRes = await ApiService.initiateJoinerPayment(reqId);
      if (initRes != null && initRes['success'] == true) {
        currentOrderId = (initRes['razorpayOrderId'] ?? '').toString();
        if (initRes['razorpayKeyId'] != null && initRes['razorpayKeyId'].toString().isNotEmpty) {
          razorpayKey = initRes['razorpayKeyId'].toString();
        }
      }
    }

    late Razorpay razorpay;
    razorpay = Razorpay();

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) async {
      final confirmRes = await ApiService.post('/api/mobile/party-plans/requests/$reqId/joiner-pay', body: {
        'userId': ApiService.currentUserId ?? '',
        'razorpay_order_id': response.orderId ?? (currentOrderId.isNotEmpty ? currentOrderId : 'order_rzp_${DateTime.now().millisecondsSinceEpoch}'),
        'razorpay_payment_id': response.paymentId ?? 'pay_${DateTime.now().millisecondsSinceEpoch}',
        'razorpay_signature': response.signature ?? 'signature',
      });
      razorpay.clear();
      if (confirmRes.statusCode == 200 && mounted) {
        setState(() {
          _requestStatus = 'confirmed';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Safety Deposit Paid! Booking Confirmed!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        String msg = 'Payment Confirmation Failed';
        try {
          final b = jsonDecode(confirmRes.body);
          msg = b['message'] ?? b['error'] ?? msg;
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment Failed: $msg'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });

    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      razorpay.clear();
      if (mounted) {
        final errText = (response.message != null && response.message!.isNotEmpty && response.message != 'Payment Failed')
            ? response.message!
            : 'Payment process cancelled or failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment Failed: $errText'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });

    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {
      razorpay.clear();
    });

    final options = <String, dynamic>{
      'key': razorpayKey,
      'amount': (depositAmount * 100).round(),
      'name': 'Lunara Party Deposit',
      'description': 'Safety deposit for Party Plan at $venueName',
      if (currentOrderId.isNotEmpty) 'order_id': currentOrderId,
      'prefill': {
        'contact': '9999999999',
        'email': 'user@lunara.app',
      },
      'theme': {
        'color': '#7C3AED',
      }
    };

    try {
      razorpay.open(options);
    } catch (e) {
      debugPrint('Error opening Razorpay: $e');
    }
  }

  void _openDepositPaymentSheet() {
    final reqId = _activeRequestId;
    if (reqId == null || reqId.isEmpty) return;

    final venue = widget.plan['venue'] as Map<String, dynamic>? ?? {};
    final venueName = venue['name'] as String? ?? 'Venue';

    SmartCheckoutSheet.show(
      context: context,
      title: 'Party Plan Safety Deposit',
      subtitle: 'Safety commitment deposit for Party Plan at $venueName',
      itemPrice: 99.0,
      onWalletPayment: () async {
        final res = await ApiService.payWithWallet(
          amount: 99.0,
          planId: widget.plan['id']?.toString(),
          paymentType: 'commitment_deposit',
        );
        if (res != null && res['success'] == true) {
          final transactionId = res['data']?['transactionId']?.toString() ?? 'wallet';
          final confirmRes = await ApiService.post('/api/mobile/party-plans/requests/$reqId/joiner-pay', body: {
            'userId': ApiService.currentUserId ?? '',
            'razorpay_order_id': 'order_mock_wallet',
            'razorpay_payment_id': 'wallet_$transactionId',
            'razorpay_signature': 'mock_signature',
          });
          if (confirmRes.statusCode == 200 && mounted) {
            setState(() {
              _requestStatus = 'confirmed';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 Safety Deposit Paid! Booking Confirmed!'),
                backgroundColor: Colors.green,
              ),
            );
            return true;
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res?['message'] ?? 'Wallet payment failed'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return false;
      },
      onDirectPayment: () async {
        _startRazorpayDirectPayment(reqId, venueName);
      },
      onHybridPayment: (shortfall) async {
        final res = await ApiService.post('/api/mobile/party-plans/requests/$reqId/joiner-pay', body: {
          'userId': ApiService.currentUserId ?? '',
          'razorpay_order_id': 'order_mock_hybrid',
          'razorpay_payment_id': 'pay_hybrid_${DateTime.now().millisecondsSinceEpoch}',
          'razorpay_signature': 'mock_signature',
        });
        if (res.statusCode == 200 && mounted) {
          setState(() {
            _requestStatus = 'confirmed';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Safety Deposit Paid! Booking Confirmed!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      },
    );
  }

  void _openHostDepositPaymentSheet() {
    final cleanPlanId = widget.plan['id']?.toString() ?? '';
    final venue = widget.plan['venue'] as Map<String, dynamic>? ?? {};
    final venueName = venue['name'] as String? ?? 'Venue';

    SmartCheckoutSheet.show(
      context: context,
      title: 'Host Safety Deposit',
      subtitle: 'Publish & activate your Party Plan at $venueName',
      itemPrice: 99.0,
      onWalletPayment: () async {
        final res = await ApiService.payWithWallet(
          amount: 99.0,
          planId: cleanPlanId,
          paymentType: 'host_deposit',
        );
        if (res != null && res['success'] == true) {
          final transactionId = res['data']?['transactionId']?.toString() ?? 'wallet';
          final paymentConfirmed = await ApiService.verifyHostPayment(
            cleanPlanId,
            'order_mock_wallet',
            'wallet_$transactionId',
            'mock_signature',
          );
          if (paymentConfirmed && mounted) {
            setState(() {
              widget.plan['hostPaymentStatus'] = 'paid';
              widget.plan['isLive'] = true;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 Host Safety Deposit Paid via Smart Wallet! Plan Published.'),
                backgroundColor: Colors.green,
              ),
            );
            return true;
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res?['message'] ?? 'Wallet payment failed'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return false;
      },
      onDirectPayment: () async {
        await _launchHostRazorpay(cleanPlanId, venueName, 99.0);
      },
      onHybridPayment: (shortfall) async {
        await _launchHostRazorpay(cleanPlanId, venueName, shortfall > 0 ? shortfall : 99.0);
      },
    );
  }

  Future<void> _launchHostRazorpay(String cleanPlanId, String venueName, double depositAmount) async {
    final initRes = await ApiService.initiateHostPayment(cleanPlanId);
    String currentOrderId = '';
    String razorpayKey = 'rzp_test_123';
    if (initRes != null && initRes['success'] == true) {
      currentOrderId = (initRes['razorpayOrderId'] ?? '').toString();
      if (initRes['razorpayKeyId'] != null && initRes['razorpayKeyId'].toString().isNotEmpty) {
        razorpayKey = initRes['razorpayKeyId'].toString();
      }
    }

    if (currentOrderId.isEmpty) {
      currentOrderId = 'order_mock_${DateTime.now().millisecondsSinceEpoch}';
    }

    if (currentOrderId.startsWith('order_mock_') || razorpayKey == 'rzp_test_123' || currentOrderId.startsWith('mock_')) {
      final paymentConfirmed = await ApiService.verifyHostPayment(
        cleanPlanId,
        currentOrderId,
        'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
        'mock_signature',
      );
      if (paymentConfirmed && mounted) {
        setState(() {
          widget.plan['hostPaymentStatus'] = 'paid';
          widget.plan['isLive'] = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Host Safety Deposit Paid! Your plan is live.'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }
    }

    late Razorpay razorpay;
    razorpay = Razorpay();

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) async {
      final pId = response.paymentId ?? 'pay_mock_${DateTime.now().millisecondsSinceEpoch}';
      final oId = response.orderId ?? currentOrderId;
      final sig = response.signature ?? 'mock_signature';

      final paymentConfirmed = await ApiService.verifyHostPayment(
        cleanPlanId,
        oId,
        pId,
        sig,
      );

      razorpay.clear();
      if (paymentConfirmed && mounted) {
        setState(() {
          widget.plan['hostPaymentStatus'] = 'paid';
          widget.plan['isLive'] = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Host Safety Deposit Paid! Your plan is live.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });

    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      razorpay.clear();
    });

    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {
      razorpay.clear();
    });

    final options = <String, dynamic>{
      'key': razorpayKey,
      'amount': (depositAmount * 100).round(),
      'name': 'Lunara Host Deposit',
      'description': 'Host safety deposit for Party Plan at $venueName',
      'currency': 'INR',
      if (currentOrderId.isNotEmpty) 'order_id': currentOrderId,
      'prefill': {'contact': '9999999999', 'email': 'user@lunara.app'},
      'theme': {'color': '#7C3AED'},
    };

    try {
      razorpay.open(options);
    } catch (e) {
      debugPrint('Error opening Razorpay for Host Payment: $e');
    }
  }

  String _formatDateTime(dynamic raw) {
    if (raw == null) return 'TBD';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return DateFormat('EEE, dd MMM yyyy • hh:mm a').format(dt);
    } catch (_) {
      return raw.toString();
    }
  }

  Future<void> _sendJoinRequest() async {
    if (_isJoining || _alreadyRequested) return;

    final planId =
        widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    if (planId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid plan ID.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isJoining = true);
    try {
      final res = await ApiService.requestToJoinPartyPlanDetailed(planId);
      if (!mounted) return;
      if (res.alreadyRequested || res.success) {
        setState(() {
          _alreadyRequested = true;
          _isInvitedUser = false;
          _activeRequestId = res.requestId ?? _activeRequestId;
          _requestStatus = res.status ?? 'pending';
        });
        if (res.isNewRequest) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
              content: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LunaraTheme.purpleGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'JOIN REQUEST SENT! THE HOST WILL REVIEW IT.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  void _showHostDetails(BuildContext ctx, Map<String, dynamic> host) {
    final hostName = host['name'] as String? ?? 'Unknown';
    final hostAge = host['age'];
    final hostOccupation = host['occupation'] as String? ?? '';
    final hostBio = host['bio'] as String? ?? '';

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF1F003A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              LunaraProfileImage(
                userData: host,
                radius: 40,
                showGradientBorder: true,
                isInteractive: false,
              ),
              const SizedBox(height: 14),
              Text(
                hostAge != null ? '$hostName, $hostAge' : hostName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (hostOccupation.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  hostOccupation,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
              if (hostBio.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  hostBio,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Map<String, dynamic> _extractHost(Map<String, dynamic> plan) {
    if (plan['host'] is Map && (plan['host'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(plan['host']);
    }
    if (plan['user'] is Map && (plan['user'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(plan['user']);
    }
    if (plan['creator'] is Map && (plan['creator'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(plan['creator']);
    }
    final name = plan['hostName'] ?? plan['userName'] ?? (plan['hostFirstName'] != null ? '${plan['hostFirstName']} ${plan['hostLastName'] ?? ''}'.trim() : null);
    final photo = plan['hostProfilePhotoUrl'] ?? plan['hostPhotoUrl'] ?? plan['profileImageUrl'] ?? plan['userPhotoUrl'];
    return {
      'id': plan['userId'] ?? plan['hostId'],
      'name': name ?? 'Party Host',
      'firstName': plan['hostFirstName'] ?? name,
      'lastName': plan['hostLastName'],
      'profilePhotoUrl': photo,
      'profileImageUrl': photo,
      'bio': plan['hostBio'],
      'occupation': plan['hostOccupation'],
      'age': plan['hostAge'],
    };
  }

  bool _isHostPlan(Map<String, dynamic> plan) {
    final currentUid = ApiService.currentUserId ?? _currentUserId ?? '';
    if (currentUid.isEmpty) return false;

    final role = (plan['role'] ?? plan['viewerRole'] ?? '').toString().toLowerCase();
    if (role == 'host' || role == 'creator') return true;

    final host = _extractHost(plan);
    final creator = plan['creator'] is Map ? plan['creator'] as Map : const <String, dynamic>{};
    final user = plan['user'] is Map ? plan['user'] as Map : const <String, dynamic>{};
    return [
      host['id'],
      plan['userId'],
      plan['hostId'],
      creator['id'],
      user['id'],
    ].any((id) => id?.toString() == currentUid);
  }

  String _extractHostName(Map<String, dynamic> host, Map<String, dynamic> plan) {
    final name = host['name'] ?? host['fullName'];
    if (name != null && name.toString().trim().isNotEmpty && name.toString().trim() != 'Unknown') {
      return name.toString().trim();
    }
    final fn = host['firstName'] ?? plan['hostFirstName'];
    final ln = host['lastName'] ?? plan['hostLastName'];
    if (fn != null && fn.toString().trim().isNotEmpty) {
      return '$fn ${ln ?? ''}'.trim();
    }
    if (plan['hostName'] != null && plan['hostName'].toString().isNotEmpty && plan['hostName'].toString() != 'Unknown') {
      return plan['hostName'].toString();
    }
    return 'Party Host';
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final host = _extractHost(plan);
    final venue = plan['venue'] as Map<String, dynamic>? ?? {};

    // `requesterId` is deliberately not treated as host ownership. It belongs
    // to a participant request and previously made role inference ambiguous.
    final isMyPost = _isHostPlan(plan);

    final hostName = _extractHostName(host, plan);
    final hostAge = host['age'] ?? plan['hostAge'];
    final hostOccupation = host['occupation'] as String? ?? plan['hostOccupation'] as String? ?? '';
    final hostBio = host['bio'] as String? ?? plan['hostBio'] as String? ?? '';

    final venueName = venue['name'] as String? ?? 'Venue';
    final venueAddress =
        [venue['addressLine1'], venue['area'], venue['city']]
            .where((e) => e != null && e.toString().isNotEmpty)
            .join(', ');

    final description = plan['description'] as String? ?? '';
    final planDateRaw = plan['planDateTime'] ?? plan['planDate'];
    final formattedDate = _formatDateTime(planDateRaw);
    final visibility = (plan['visibility'] as String? ?? 'public').toUpperCase();
    final status = (plan['status'] as String? ?? 'active').toUpperCase();

    final venueImageUrl = _getVenueImageUrl();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0014),
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: const Color(0xFF1F003A),
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: CircleAvatar(
                backgroundColor: Colors.black45,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: CircleAvatar(
                  backgroundColor: Colors.black45,
                  child: IconButton(
                    icon: const Icon(Icons.person_rounded, color: Colors.white),
                    onPressed: () => _showHostDetails(context, host),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Gradient background
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2D0060), Color(0xFF0D001C)],
                      ),
                    ),
                  ),
                  // Venue Image if available
                  if (venueImageUrl != null && venueImageUrl.isNotEmpty)
                    Image.network(
                      venueImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _VenueImageFallback(),
                    )
                  else
                    const _VenueImageFallback(),
                  // Dark overlay gradient for contrast
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.4),
                          Colors.black.withValues(alpha: 0.88),
                        ],
                      ),
                    ),
                  ),
                  // Host info overlay
                  Positioned(
                    bottom: 24,
                    left: 24,
                    right: 24,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _showHostDetails(context, host),
                          child: LunaraProfileImage(
                            userData: host,
                            radius: 34,
                            showGradientBorder: true,
                            isInteractive: false,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      hostAge != null
                                          ? '$hostName, $hostAge'
                                          : hostName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (hostOccupation.isNotEmpty)
                                Text(
                                  hostOccupation,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Party Plan badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: LunaraTheme.primaryDeep,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'PARTY PLAN',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Body Content ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Row
                  Row(
                    children: [
                      _chip(
                        icon: _isExpired ? Icons.timer_off_rounded : Icons.circle,
                        label: _isExpired ? 'EXPIRED' : status,
                        color: _isExpired ? Colors.grey : (status == 'ACTIVE' ? Colors.green : Colors.grey),
                      ),
                      const SizedBox(width: 8),
                      _chip(
                        icon: Icons.lock_open_rounded,
                        label: visibility,
                        color: visibility == 'PUBLIC'
                            ? LunaraTheme.accentVivid
                            : Colors.orange,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Description
                  if (description.isNotEmpty) ...[
                    const Text(
                      'ABOUT THIS PLAN',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Host Bio
                  if (hostBio.isNotEmpty) ...[
                    const Text(
                      'HOST BIO',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hostBio,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Date / Time Card
                  _infoCard(
                    icon: Icons.calendar_today_rounded,
                    title: 'DATE & TIME',
                    value: formattedDate,
                    iconColor: LunaraTheme.accentVivid,
                  ),
                  const SizedBox(height: 12),

                  // Preferences Card
                  _infoCard(
                    icon: Icons.restaurant_menu_rounded,
                    title: 'FOOD & DRINK PREFERENCES',
                    value: 'Food: ${plan['foodPreference'] ?? 'Both'}',
                    subtitle: 'Drink: ${plan['drinkPreference'] ?? 'Both'}',
                    iconColor: Colors.amber,
                  ),
                  const SizedBox(height: 12),

                  // Venue Card with Privacy Masking (Step 3)
                  _infoCard(
                    icon: (plan['showVenueDetails'] == false && !isMyPost && plan['hasConfirmedBooking'] != true)
                        ? Icons.visibility_off_rounded
                        : Icons.location_on_rounded,
                    title: 'VENUE',
                    value: (plan['showVenueDetails'] == false && !isMyPost && plan['hasConfirmedBooking'] != true)
                        ? '${venue['area'] ?? venue['city'] ?? 'Near Area'} (Exact venue hidden until booking)'
                        : venueName,
                    subtitle: (plan['showVenueDetails'] == false && !isMyPost && plan['hasConfirmedBooking'] != true)
                        ? 'Locality: ${venue['area'] ?? venue['city'] ?? 'Local Area'}'
                        : venueAddress,
                    iconColor: (plan['showVenueDetails'] == false && !isMyPost && plan['hasConfirmedBooking'] != true)
                        ? Colors.amber
                        : LunaraTheme.electricViolet,
                  ),

                  // Arrival Confirmation Card (30m Window)
                  _buildArrivalConfirmationCard(),
                  const SizedBox(height: 12),

                  // Mutual Cancellation Section
                  _buildCancellationSection(),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Bottom CTA ───────────────────────────────────────────────────────
      bottomNavigationBar: _buildBottomCTA(isMyPost),
    );
  }

  Widget? _buildBottomCTA(bool isMyPost) {
    if (_isExpired) {
      return _expiredBanner();
    }
    if (isMyPost) {
      return _myPlanBanner();
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: (_alreadyRequested && _requestStatus == 'pending' && !_isInvitedUser)
            ? SizedBox(
                height: 58,
                child: OutlinedButton.icon(
                  onPressed: _isLoadingCancellation ? null : () => _confirmRequestExit(withdraw: false),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('CANCEL REQUEST', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                ),
              )
            : (_alreadyRequested && (_requestStatus == 'accepted' || _requestStatus == 'payment_pending'))
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _openDepositPaymentSheet,
                    child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00C853), Color(0xFF69F0AE)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00C853).withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.payment_rounded, color: Colors.white, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'PAY SAFETY DEPOSIT (₹99)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                    ),
                  ),
                  TextButton(
                    onPressed: _isLoadingCancellation ? null : () => _confirmRequestExit(withdraw: true),
                    child: const Text('WITHDRAW REQUEST', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            : (_alreadyRequested && (_requestStatus == 'confirmed' || _requestStatus == 'paid'))
                ? Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            final host = _extractHost(widget.plan);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(user: {
                                  ...host,
                                  'contextType': 'party_plan',
                                  'planId': widget.plan['id']?.toString(),
                                }),
                              ),
                            );
                          },
                          child: Container(
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: LunaraTheme.purpleGradient,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'OPEN CHAT',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _isLoadingCancellation ? null : _showCancellationStep1Dialog,
                          child: Container(
                            height: 54,
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'CANCEL PLAN',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
            : (_alreadyRequested && _isInvitedUser && (_requestStatus == 'pending' || _requestStatus == 'invited'))
                    ? GestureDetector(
                        onTap: _isAcceptingInvite ? null : _handleAcceptInvite,
                        child: Container(
                          height: 58,
                          decoration: BoxDecoration(
                            gradient: _isAcceptingInvite ? null : LunaraTheme.purpleGradient,
                            color: _isAcceptingInvite ? Colors.grey.withValues(alpha: 0.3) : null,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: _isAcceptingInvite
                                ? null
                                : [
                                    BoxShadow(
                                      color: LunaraTheme.electricViolet.withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isAcceptingInvite)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              else
                                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                              const SizedBox(width: 10),
                              Text(
                                _isAcceptingInvite ? 'ACCEPTING INVITE...' : 'ACCEPT INVITE',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                : (_alreadyRequested && _requestStatus == 'cancelled')
                    ? Container(
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cancel_rounded, color: Colors.grey),
                            SizedBox(width: 10),
                            Text(
                              'REQUEST CANCELLED',
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      )
                : _alreadyRequested
                    ? Container(
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.4),
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Colors.green),
                                const SizedBox(width: 10),
                                const Text(
                                  'REQUEST SENT — AWAITING HOST APPROVAL',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: (_isJoining || _alreadyRequested) ? null : _sendJoinRequest,
                        child: Container(
                          height: 58,
                          decoration: BoxDecoration(
                            gradient: _isJoining ? null : LunaraTheme.purpleGradient,
                            color: _isJoining ? Colors.grey.withValues(alpha: 0.3) : null,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: _isJoining
                                ? null
                                : [
                                    BoxShadow(
                                      color: LunaraTheme.electricViolet.withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isJoining)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              else
                                const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                              const SizedBox(width: 10),
                              Text(
                                _isJoining ? 'SENDING REQUEST...' : 'REQUEST TO JOIN THE VIBE',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
      ),
    );
  }

  Widget _myPlanBanner() {
    final plan = widget.plan;
    final lifecycleStatus = plan['lifecycleStatus']?.toString() ?? plan['lifecycle_status']?.toString() ?? '';
    final planStatus = plan['status']?.toString() ?? '';
    final hostPaymentStatus = plan['hostPaymentStatus']?.toString() ?? plan['host_payment_status']?.toString() ?? '';
    final chatEnabled = plan['chatEnabled'] == true || plan['chat_enabled'] == true;

    // Determine if the plan is fully confirmed (match locked)
    final isConfirmed = chatEnabled ||
        lifecycleStatus == 'match_confirmed' ||
        lifecycleStatus == 'chat_enabled' ||
        lifecycleStatus == 'event_reminder' ||
        lifecycleStatus == 'arrival_confirmation' ||
        (planStatus == 'inactive' && hostPaymentStatus == 'paid');

    if (isConfirmed) {
      // Host sees: Ticket + Chat + Cancel after plan is matched
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(
            children: [
              // View Ticket
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PartyPlanTicketScreen(
                          request: const {},
                          plan: plan,
                          isHost: true,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LunaraTheme.purpleGradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: LunaraTheme.electricViolet.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'TICKET',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Open Chat
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    // Find partner from plan data
                    final partnerData = plan['matchedPartner'] ?? plan['partner'] ?? plan['guest'] ?? {};
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(user: {
                          ...(partnerData is Map ? Map<String, dynamic>.from(partnerData) : {}),
                          'contextType': 'party_plan',
                          'planId': plan['id']?.toString(),
                        }),
                      ),
                    );
                  },
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6D28D9), Color(0xFF9333EA)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'CHAT',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Cancel
              GestureDetector(
                onTap: _isLoadingCancellation ? null : _showCancellationStep1Dialog,
                child: Container(
                  height: 54,
                  width: 54,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  child: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 22),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Unpaid Host Deposit
    if (hostPaymentStatus != 'paid' && hostPaymentStatus != 'completed') {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: GestureDetector(
            onTap: _openHostDepositPaymentSheet,
            child: Container(
              height: 58,
              decoration: BoxDecoration(
                gradient: LunaraTheme.purpleGradient,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payment_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'PAY SAFETY DEPOSIT (₹99)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Host Paid — show static host label
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: LunaraTheme.primaryDeep.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: LunaraTheme.primaryDeep.withValues(alpha: 0.5),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.star_rounded, color: LunaraTheme.electricViolet),
              SizedBox(width: 10),
              Text(
                'YOUR PARTY PLAN',
                style: TextStyle(
                  color: LunaraTheme.electricViolet,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _isExpired {
    final plan = widget.plan;
    final status = (plan['status'] ?? '').toString().toLowerCase();
    final lifecycleStatus = (plan['lifecycleStatus'] ?? plan['lifecycle_status'] ?? '').toString().toLowerCase();

    if (status == 'expired' || lifecycleStatus == 'expired') return true;

    final rawDateTime = plan['planDateTime'] ??
        plan['eventDateTime'] ??
        plan['planDate'] ??
        plan['partyDate'] ??
        plan['bookingDate'];

    if (rawDateTime != null) {
      try {
        final planTime = DateTime.parse(rawDateTime.toString()).toLocal();
        if (planTime.isBefore(DateTime.now())) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Widget _expiredBanner() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer_off_rounded, color: Colors.grey, size: 20),
              SizedBox(width: 10),
              Text(
                'THIS EVENT HAS EXPIRED',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
