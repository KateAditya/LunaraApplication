import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../widgets/smart_checkout_sheet.dart';
import 'chat_screen.dart';
import 'party_plan_ticket_screen.dart';

class PartyPlanDetailScreen extends StatefulWidget {
  final Map<String, dynamic> plan;

  const PartyPlanDetailScreen({super.key, required this.plan});

  @override
  State<PartyPlanDetailScreen> createState() => _PartyPlanDetailScreenState();
}

class _PartyPlanDetailScreenState extends State<PartyPlanDetailScreen> {
  bool _isJoining = false;
  bool _alreadyRequested = false;
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
    _alreadyRequested = widget.plan['hasRequested'] == true;
    _checkRequestStatus();
    _loadVenueDetailsIfNeeded();
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
        if (mounted && res != null) {
          setState(() {
            _currentUserId = uid;
            if (res['isWindowClosed'] == true) _isWindowClosed = true;
            _cancellationRequest = res['cancellationRequest'] is Map<String, dynamic>
                ? res['cancellationRequest']
                : null;
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
            Text('Request Cancellation?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will send a cancellation request to the other participant. The Party Plan will only be cancelled after both participants agree.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 14),
            Text('If approved:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            SizedBox(height: 6),
            Text('• Commitment Deposit (₹499) will be returned to both users\' Lunara Wallets.', style: TextStyle(color: Colors.white60, fontSize: 12)),
            SizedBox(height: 4),
            Text('• Chat will become read-only (archived after 24h).', style: TextStyle(color: Colors.white60, fontSize: 12)),
            SizedBox(height: 4),
            Text('• Reliability Score may decrease (-5 pts).', style: TextStyle(color: Colors.white60, fontSize: 12)),
            SizedBox(height: 4),
            Text('• Both users will receive notifications.', style: TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Plan', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold)),
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
            child: const Text('Send Cancellation Request', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
          content: Text(action == 'approve' ? 'Party Plan cancelled. ₹499 Commitment Deposit credited to your Lunara Wallet!' : 'Cancellation request declined.'),
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
              const Text('• Both Commitment Deposits (₹499) will be credited to each user\'s Lunara Wallet.', style: TextStyle(color: Colors.white54, fontSize: 11)),
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
                      child: const Text('Keep Booking', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoadingCancellation ? null : () => _respondToCancellation(reqId, 'approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Approve Cancellation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
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

    // Default: Show subtle red outline "Cancel Party Plan" button if participant
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
    final isConfirmed = widget.plan['hasConfirmedBooking'] == true;
    if (!isConfirmed) return const SizedBox.shrink();

    return Container(
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
                'ARRIVAL CONFIRMATION',
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
                    final planId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
                    final uid = await ApiService.getCurrentUserId();
                    if (planId.isNotEmpty && uid != null && uid.isNotEmpty) {
                      await ApiService.confirmArrival(planId: planId, userId: uid, hasArrived: true);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✅ Arrival confirmed (YES)!'), backgroundColor: Colors.green),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('YES — I\'M HERE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final planId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
                    final uid = await ApiService.getCurrentUserId();
                    if (planId.isNotEmpty && uid != null && uid.isNotEmpty) {
                      await ApiService.confirmArrival(planId: planId, userId: uid, hasArrived: false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Recorded: NOT YET'), backgroundColor: Colors.orange),
                        );
                      }
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
    return 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=1200&auto=format&fit=crop&q=80';
  }

  Future<void> _checkRequestStatus() async {
    try {
      final myRequests = await ApiService.fetchMyPartyPlanRequests();
      final targetPlanId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
      if (targetPlanId.isEmpty) return;
      
      bool requested = false;
      String? reqStatus;
      String? reqId;

      for (final req in myRequests) {
        final planId = req['partyPlanId']?.toString() ?? req['planId']?.toString() ?? req['plan']?['id']?.toString();
        if (planId == targetPlanId) {
          requested = true;
          reqId = req['id']?.toString();
          reqStatus = (req['status'] ?? req['joinerPaymentStatus'] ?? 'pending').toString().toLowerCase();
          break;
        }
      }
      if (mounted) {
        setState(() {
          _alreadyRequested = requested;
          _activeRequestId = reqId;
          _requestStatus = reqStatus;
        });
      }
    } catch (e) {
      debugPrint('Error checking request status in PartyPlanDetailScreen: $e');
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
      itemPrice: 499.0,
      onWalletPayment: () async {
        final res = await ApiService.payWithWallet(
          amount: 499.0,
          planId: widget.plan['id']?.toString(),
          paymentType: 'commitment_deposit',
        );
        if (res != null && res['success'] == true) {
          final transactionId = res['data']?['transactionId']?.toString() ?? 'wallet';
          final confirmRes = await ApiService.post('/api/mobile/party-plans/requests/$reqId/joiner-pay', body: {
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
        final res = await ApiService.post('/api/mobile/party-plans/requests/$reqId/joiner-pay', body: {
          'razorpay_order_id': 'order_mock_direct',
          'razorpay_payment_id': 'pay_direct_${DateTime.now().millisecondsSinceEpoch}',
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
      onHybridPayment: (shortfall) async {
        final res = await ApiService.post('/api/mobile/party-plans/requests/$reqId/joiner-pay', body: {
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
        setState(() => _alreadyRequested = true);
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

    final isMyPost =
        host['id']?.toString() == ApiService.currentUserId || plan['userId']?.toString() == ApiService.currentUserId;

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
                      errorBuilder: (_, _, _) => Image.network(
                        'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=1200&auto=format&fit=crop&q=80',
                        fit: BoxFit.cover,
                      ),
                    ),
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
                        icon: Icons.circle,
                        label: status,
                        color: status == 'ACTIVE' ? Colors.green : Colors.grey,
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
      bottomNavigationBar: isMyPost
          ? _myPlanBanner()
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: (_alreadyRequested && (_requestStatus == 'accepted' || _requestStatus == 'payment_pending'))
                    ? GestureDetector(
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
                                'PAY SAFETY DEPOSIT (₹499)',
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
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PartyPlanTicketScreen(
                                          request: {
                                            'id': _activeRequestId,
                                            'planId': widget.plan['id'],
                                            'plan': widget.plan,
                                          },
                                          plan: widget.plan,
                                          isHost: false,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: LunaraTheme.electricViolet,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.qr_code_rounded, color: Colors.white, size: 18),
                                        SizedBox(width: 6),
                                        Text(
                                          'VIEW TICKET',
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
                            ],
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
            ),
    );
  }

  Widget _myPlanBanner() {
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
