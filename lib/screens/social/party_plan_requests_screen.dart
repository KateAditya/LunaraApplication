import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../services/realtime_sync_manager.dart';
import '../../services/optimistic_action_guard.dart';
import '../discovery/payment_confirmation_screen.dart';
import 'chat_screen.dart';

class PartyPlanRequestsScreen extends StatefulWidget {
  const PartyPlanRequestsScreen({super.key});

  @override
  State<PartyPlanRequestsScreen> createState() =>
      _PartyPlanRequestsScreenState();
}

class _PartyPlanRequestsScreenState extends State<PartyPlanRequestsScreen> {
  String _selectedFilter = 'pending'; // 'pending', 'accepted', 'rejected'
  bool _isLoading = true;
  List<Map<String, dynamic>> _requests = [];
  Timer? _timer;
  final Set<String> _activeActionReqIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _initRealtimeListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  void _initRealtimeListeners() {
    RealtimeSyncManager.instance.partyPlanNotifier.addListener(_onRealtimeUpdate);
    RealtimeSyncManager.instance.liveFeedNotifier.addListener(_onRealtimeUpdate);
    RealtimeSyncManager.instance.globalSyncTick.addListener(_onRealtimeUpdate);

    ApiService.addSocketListener('party_plan_request_accepted', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_request_rejected', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_request_cancelled', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_joiner_paid', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_host_paid', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_match_success', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_relisted', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_updated', _onSocketUpdate);
    ApiService.addSocketListener('live_feed_update', _onSocketUpdate);
  }

  void _disposeRealtimeListeners() {
    RealtimeSyncManager.instance.partyPlanNotifier.removeListener(_onRealtimeUpdate);
    RealtimeSyncManager.instance.liveFeedNotifier.removeListener(_onRealtimeUpdate);
    RealtimeSyncManager.instance.globalSyncTick.removeListener(_onRealtimeUpdate);

    ApiService.removeSocketListener('party_plan_request_accepted', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_request_rejected', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_request_cancelled', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_joiner_paid', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_host_paid', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_match_success', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_relisted', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_updated', _onSocketUpdate);
    ApiService.removeSocketListener('live_feed_update', _onSocketUpdate);
  }

  void _onRealtimeUpdate() {
    if (!mounted) return;
    _loadRequests(showLoader: false);
  }

  void _onSocketUpdate(dynamic data) {
    if (!mounted) return;
    _loadRequests(showLoader: false);
  }

  @override
  void dispose() {
    _disposeRealtimeListeners();
    _timer?.cancel();
    super.dispose();
  }

  String _getTimeRemaining(String? timeoutStr) {
    if (timeoutStr == null) return '';
    try {
      final timeout = DateTime.parse(timeoutStr).toLocal();
      final diff = timeout.difference(DateTime.now());
      if (diff.isNegative) return 'Expired';
      final mins = diff.inMinutes;
      final secs = diff.inSeconds % 60;
      return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} left';
    } catch (_) {
      return '';
    }
  }

  Future<void> _loadRequests({bool showLoader = true}) async {
    if (showLoader) setState(() => _isLoading = true);
    final allRequests = await ApiService.fetchMyPartyPlanRequests();

    if (mounted) {
      setState(() {
        _requests = allRequests.where((req) {
          final status = (req['status'] ?? '').toString().toLowerCase();
          if (_selectedFilter == 'accepted') {
            return status == 'accepted' || status == 'payment_pending';
          }
          if (_selectedFilter == 'rejected') {
            return status == 'rejected' || status == 'payment_failed';
          }
          return status == 'pending';
        }).toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelRequest(String reqId) async {
    final guardKey = 'cancel_req_$reqId';
    if (!OptimisticActionGuard.start(guardKey)) return;

    setState(() => _activeActionReqIds.add(reqId));
    try {
      final success = await ApiService.cancelPartyPlanRequest(reqId);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request cancelled successfully'),
            backgroundColor: Colors.black87,
          ),
        );
        await _loadRequests(showLoader: false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to cancel request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      OptimisticActionGuard.end(guardKey);
      if (mounted) {
        setState(() => _activeActionReqIds.remove(reqId));
      }
    }
  }

  Future<void> _acceptInvite(Map<String, dynamic> req) async {
    final reqId = req['id']?.toString() ?? '';
    if (reqId.isEmpty) return;
    final guardKey = 'accept_invite_$reqId';
    if (!OptimisticActionGuard.start(guardKey)) return;

    setState(() => _activeActionReqIds.add(reqId));
    try {
      final res = await ApiService.acceptPartyPlanInvite(reqId);
      if (!mounted) return;
      if (res != null && res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Invite accepted! Complete your deposit payment.'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadRequests(showLoader: false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res?['message'] ?? 'Failed to accept invite'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      OptimisticActionGuard.end(guardKey);
      if (mounted) {
        setState(() => _activeActionReqIds.remove(reqId));
      }
    }
  }

  Future<void> _declineInvite(String reqId) async {
    final guardKey = 'decline_invite_$reqId';
    if (!OptimisticActionGuard.start(guardKey)) return;

    setState(() => _activeActionReqIds.add(reqId));
    try {
      final success = await ApiService.rejectPartyPlanRequest(reqId);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invite declined'),
            backgroundColor: Colors.black87,
          ),
        );
        await _loadRequests(showLoader: false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to decline invite'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      OptimisticActionGuard.end(guardKey);
      if (mounted) {
        setState(() => _activeActionReqIds.remove(reqId));
      }
    }
  }

  void _onProceedToPayment(Map<String, dynamic> req) {
    final plan = req['plan'] ?? {};
    final venue = plan['venue'] ?? {};
    final reqId = req['id'];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentConfirmationScreen(
          venue: venue,
          date: plan['planDateTime'] != null
              ? DateFormat(
                  'dd/MM/yyyy',
                ).format(DateTime.parse(plan['planDateTime']).toLocal())
              : 'Tonight',
          package: 'Party Plan Safety Deposit',
          time: plan['planDateTime'] != null
              ? DateFormat(
                  'hh:mm a',
                ).format(DateTime.parse(plan['planDateTime']).toLocal())
              : '21:00',
          table: 'Strangers Table',
          guests: '1 Head',
          totalPrice: '₹99',
          showSplitBill: false,
          razorpayOrderId: req['joinerRazorpayOrderId'],
          onRazorpayPaymentSuccess: (paymentId, signature) async {
            try {
              final orderId = req['joinerRazorpayOrderId'] ?? 'mock_order';
              final success = await ApiService.verifyJoinerPayment(
                reqId,
                orderId,
                paymentId,
                signature,
              );
              if (!mounted) return;
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Payment Successful!'),
                    backgroundColor: Colors.green,
                  ),
                );
                _loadRequests();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Payment Verification Failed.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            } catch (e) {
              debugPrint('Payment verification error: $e');
            }
          },
          onPaymentSuccess: () async {
            try {
              // Joiner Razorpay Order ID
              final orderId = req['joinerRazorpayOrderId'] ?? 'mock_order';
              final success = await ApiService.verifyJoinerPayment(
                reqId,
                orderId,
                'mock_payment',
                'mock_signature',
              );
              if (!mounted) return;
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Payment Successful!'),
                    backgroundColor: Colors.green,
                  ),
                );
                _loadRequests();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Payment Verification Failed.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            } catch (e) {
              debugPrint('Payment verification error: $e');
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'My Party Plan Requests',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          // Filters
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildFilterChip('Pending', 'pending'),
                _buildFilterChip('Accepted', 'accepted'),
                _buildFilterChip('Rejected', 'rejected'),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: LunaraTheme.electricViolet,
                    ),
                  )
                : _requests.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadRequests,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: _requests.length,
                      itemBuilder: (context, index) {
                        return _buildRequestCard(_requests[index]);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () {
        if (_selectedFilter != value) {
          setState(() {
            _selectedFilter = value;
            _isLoading = true;
          });
          _loadRequests();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? LunaraTheme.electricViolet : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[600],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No $_selectedFilter requests',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final status = req['status'] ?? 'pending';
    final paymentStatus = req['joinerPaymentStatus'] ?? 'unpaid';
    final plan = req['plan'] ?? {};
    final venue = plan['venue'] ?? {};
    final host = plan['user'] ?? {};

    final venueName = venue['name'] ?? 'Unknown Venue';
    final message = plan['message'] ?? 'Let\'s party!';
    final planDateTime = plan['planDateTime'] != null
        ? DateTime.parse(plan['planDateTime']).toLocal()
        : DateTime.now();
    final hostName = '${host['firstName'] ?? ''} ${host['lastName'] ?? ''}'
        .trim();

    final isSelfPay = plan['paymentType'] == 'self_pay';
    final joinerPaid =
        paymentStatus.toString().toLowerCase() == 'paid' ||
        paymentStatus.toString().toLowerCase() == 'refunded' ||
        isSelfPay;
    final hostPaid =
        plan['hostPaymentStatus']?.toString().toLowerCase() == 'paid' ||
        plan['hostPaymentStatus']?.toString().toLowerCase() == 'refunded';

    final String lowerStatus = status.toString().toLowerCase();
    final bool isBookingConfirmed =
        (lowerStatus == 'accepted' || lowerStatus == 'payment_pending') &&
        hostPaid &&
        joinerPaid;
    final bool isAwaitingHost =
        (lowerStatus == 'accepted' || lowerStatus == 'payment_pending') &&
        !hostPaid &&
        !joinerPaid;
    final bool isAwaitingJoinerPayment =
        (lowerStatus == 'accepted' || lowerStatus == 'payment_pending') &&
        hostPaid &&
        !joinerPaid;
    final bool isJoinerPaidAwaitingHost =
        (lowerStatus == 'accepted' || lowerStatus == 'payment_pending') &&
        !hostPaid &&
        joinerPaid;

    final timerText = _getTimeRemaining(req['paymentTimeoutAt']);

    final bool isInvite = req['isInvite'] == true ||
        req['requestType'] == 'private_invite' ||
        req['type'] == 'party_plan_invitation';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildStatusBadge(
                  status,
                  paymentStatus,
                  plan['hostPaymentStatus']?.toString(),
                  paymentType: plan['paymentType']?.toString(),
                  isInvite: isInvite,
                ),
              ],
            ),
            const SizedBox(height: 8),

            Text(
              'Host: ${hostName.isNotEmpty ? hostName : 'Lunara User'}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            // Details
            _buildDetailRow(Icons.location_on_rounded, venueName),
            const SizedBox(height: 8),
            _buildDetailRow(
              Icons.calendar_today_rounded,
              DateFormat('MMM dd, yyyy • hh:mm a').format(planDateTime),
            ),

            // Actions
            if (isAwaitingHost) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.hourglass_empty_rounded,
                      color: Colors.orange,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'AWAITING HOST DEPOSIT PAYMENT',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (isAwaitingJoinerPayment) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deposit Required ($timerText)',
                        style: TextStyle(
                          color: Colors.red[400],
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        '₹99',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: () => _onProceedToPayment(req),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LunaraTheme.electricViolet,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'PAY DEPOSIT',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            if (isJoinerPaidAwaitingHost) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'WAITING FOR HOST DEPOSIT ($timerText)',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (isBookingConfirmed) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'BOOKING CONFIRMED',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (host.isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  user: {
                                    ...host,
                                    'contextType': 'party_plan',
                                    'planId': plan['id']?.toString(),
                                  },
                                ),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'CHAT',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: LunaraTheme.hotPink,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (lowerStatus == 'pending' && isInvite) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.mail_outline_rounded,
                        color: LunaraTheme.electricViolet,
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Private Invite',
                        style: TextStyle(
                          color: LunaraTheme.electricViolet,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: _activeActionReqIds.contains(req['id']?.toString())
                            ? null
                            : () => _declineInvite(req['id'].toString()),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red[600],
                          side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                        child: _activeActionReqIds.contains(req['id']?.toString())
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.red,
                                ),
                              )
                            : Text(
                                'Decline',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: Colors.red[600],
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _activeActionReqIds.contains(req['id']?.toString())
                            ? null
                            : () => _acceptInvite(req),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: LunaraTheme.electricViolet,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        child: _activeActionReqIds.contains(req['id']?.toString())
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Accept',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ] else if (lowerStatus == 'pending') ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Awaiting Host Decision',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  OutlinedButton(
                    onPressed: _activeActionReqIds.contains(req['id']?.toString())
                        ? null
                        : () => _cancelRequest(req['id'].toString()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red[600],
                      side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: _activeActionReqIds.contains(req['id']?.toString())
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.red,
                            ),
                          )
                        : const Text(
                            'Cancel Request',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(
    String status,
    String paymentStatus,
    String? hostPaymentStatus, {
    String? paymentType,
    bool isInvite = false,
  }) {
    Color bg;
    Color text;
    final String lowerStatus = status.toString().toLowerCase();
    String label = status.toUpperCase();

    final bool isSelfPay = paymentType == 'self_pay';
    final bool hostPaid =
        hostPaymentStatus?.toLowerCase() == 'paid' ||
        hostPaymentStatus?.toLowerCase() == 'refunded';
    final bool joinerPaid =
        paymentStatus.toLowerCase() == 'paid' ||
        paymentStatus.toLowerCase() == 'refunded' ||
        isSelfPay;

    if (lowerStatus == 'closed' || lowerStatus == 'cancelled') {
      bg = Colors.grey.withValues(alpha: 0.15);
      text = Colors.grey[700]!;
      label = lowerStatus == 'closed' ? 'CLOSED' : 'CANCELLED';
    } else if (lowerStatus == 'pending') {
      if (isInvite) {
        bg = LunaraTheme.electricViolet.withValues(alpha: 0.12);
        text = LunaraTheme.electricViolet;
        label = 'INVITE';
      } else {
        bg = Colors.orange.withValues(alpha: 0.1);
        text = Colors.orange;
      }
    } else if (lowerStatus == 'rejected' || lowerStatus == 'payment_failed') {
      bg = Colors.red.withValues(alpha: 0.1);
      text = Colors.red;
      label = lowerStatus == 'payment_failed' ? 'FAILED' : 'REJECTED';
    } else if (lowerStatus == 'accepted' || lowerStatus == 'payment_pending') {
      if (joinerPaid && hostPaid) {
        bg = Colors.green.withValues(alpha: 0.1);
        text = Colors.green;
        label = 'CONFIRMED';
      } else if (!hostPaid) {
        bg = Colors.orange.withValues(alpha: 0.1);
        text = Colors.orange;
        label = 'AWAITING HOST';
      } else if (hostPaid && !joinerPaid) {
        bg = LunaraTheme.electricViolet.withValues(alpha: 0.1);
        text = LunaraTheme.electricViolet;
        label = 'PAY DEPOSIT';
      } else {
        bg = Colors.blue.withValues(alpha: 0.1);
        text = Colors.blue;
        label = 'WAITING HOST';
      }
    } else {
      bg = Colors.green.withValues(alpha: 0.1);
      text = Colors.green;
      label = 'CONFIRMED';
    }


    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
        ),
      ],
    );
  }
}
