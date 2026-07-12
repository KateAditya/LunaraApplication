import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../discovery/payment_confirmation_screen.dart';
import 'party_plan_ticket_screen.dart';

class HostPartyPlanManagerScreen extends StatefulWidget {
  const HostPartyPlanManagerScreen({super.key});

  @override
  State<HostPartyPlanManagerScreen> createState() => _HostPartyPlanManagerScreenState();
}

class _HostPartyPlanManagerScreenState extends State<HostPartyPlanManagerScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _myPlans = [];
  Map<String, List<Map<String, dynamic>>> _planRequests = {};

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
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

  void _onHostPayDeposit(Map<String, dynamic> plan) {
    final venue = plan['venue'] ?? {};
    final planId = plan['id'];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentConfirmationScreen(
          venue: venue,
          date: plan['planDateTime'] != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse(plan['planDateTime']).toLocal()) : 'Tonight',
          package: 'Party Plan Safety Deposit',
          time: plan['planDateTime'] != null ? DateFormat('hh:mm a').format(DateTime.parse(plan['planDateTime']).toLocal()) : '21:00',
          table: 'Host Table',
          guests: '1 Head',
          totalPrice: '₹99',
          showSplitBill: false,
          razorpayOrderId: plan['hostRazorpayOrderId'],
          onRazorpayPaymentSuccess: (paymentId, signature) async {
            try {
              final orderId = plan['hostRazorpayOrderId'] ?? 'mock_order';
              final success = await ApiService.verifyHostPayment(planId, orderId, paymentId, signature);
              if (!mounted) return;
              if (success) {
                await _loadData();
                // After host pays, if there's an accepted request, open ticket
                final reqs = _planRequests[planId] ?? [];
                final confirmedReq = reqs.firstWhere(
                  (r) => r['status'] == 'accepted' || 
                         (r['joinerPaymentStatus'] == 'paid' && plan['hostPaymentStatus'] == 'paid'),
                  orElse: () => {},
                );
                if (confirmedReq.isNotEmpty && mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PartyPlanTicketScreen(
                        request: confirmedReq,
                        plan: plan,
                        isHost: true,
                      ),
                    ),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment Verification Failed.'), backgroundColor: Colors.red),
                );
              }
            } catch (e) {
              debugPrint('Payment verification error: $e');
            }
          },
          onPaymentSuccess: () async {
            try {
              final orderId = plan['hostRazorpayOrderId'] ?? 'mock_order';
              final success = await ApiService.verifyHostPayment(planId, orderId, 'mock_payment', 'mock_signature');
              if (!mounted) return;
              if (success) {
                await _loadData();
                final reqs = _planRequests[planId] ?? [];
                final confirmedReq = reqs.firstWhere(
                  (r) => r['status'] == 'accepted' ||
                         (r['joinerPaymentStatus'] == 'paid' && plan['hostPaymentStatus'] == 'paid'),
                  orElse: () => {},
                );
                if (confirmedReq.isNotEmpty && mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PartyPlanTicketScreen(
                        request: confirmedReq,
                        plan: plan,
                        isHost: true,
                      ),
                    ),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment Verification Failed.'), backgroundColor: Colors.red),
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final plans = await ApiService.fetchMyPartyPlans();
      final activePlans = plans.where((p) => p['status'] != 'cancelled').toList();
      
      final reqsMap = <String, List<Map<String, dynamic>>>{};
      for (final plan in activePlans) {
        final planId = plan['id'];
        final reqs = await ApiService.fetchPartyPlanRequests(planId);
        reqsMap[planId] = reqs;
      }
      
      if (mounted) {
        setState(() {
          _myPlans = activePlans;
          _planRequests = reqsMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading host data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onAcceptRequest(String reqId, Map<String, dynamic> plan) async {
    final result = await ApiService.acceptPartyPlanRequest(reqId);
    if (!mounted) return;
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request Accepted! Complete your deposit to lock match.')),
      );
      await _loadData();
      final hostOrderId = result['hostRazorpayOrderId']?.toString();
      if (hostOrderId != null) {
        final updatedPlan = _myPlans.firstWhere(
          (p) => p['id']?.toString() == plan['id']?.toString(),
          orElse: () => <String, dynamic>{},
        );
        if (updatedPlan.isNotEmpty) {
          final newPlan = Map<String, dynamic>.from(updatedPlan);
          newPlan['hostRazorpayOrderId'] = hostOrderId;
          _onHostPayDeposit(newPlan);
        } else {
          final newPlan = Map<String, dynamic>.from(plan);
          newPlan['hostRazorpayOrderId'] = hostOrderId;
          _onHostPayDeposit(newPlan);
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to accept request.'), backgroundColor: Colors.red),
      );
    }
  }

  void _onCancelPlan(String planId) async {
    final success = await ApiService.cancelPartyPlan(planId);
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan Cancelled successfully.')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to cancel plan.'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Manage My Plans', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: LunaraTheme.electricViolet))
          : _myPlans.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _myPlans.length,
                    itemBuilder: (context, index) {
                      final plan = _myPlans[index];
                      final planId = plan['id'];
                      final requests = _planRequests[planId] ?? [];
                      return _buildPlanCard(plan, requests);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'You have not posted any plans.',
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

  Widget _buildPlanCard(Map<String, dynamic> plan, List<Map<String, dynamic>> requests) {
    final venue = plan['venue'] ?? {};
    final venueName = venue['name'] ?? 'Unknown Venue';
    final message = plan['message'] ?? 'Let\'s party!';
    final planDateTime = plan['planDateTime'] != null ? DateTime.parse(plan['planDateTime']).toLocal() : DateTime.now();
    final isLive = plan['isLive'] ?? false;
    final paymentStatus = plan['hostPaymentStatus'] ?? 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.1), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isLive ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isLive ? 'LIVE' : 'LOCKED',
                        style: TextStyle(
                          color: isLive ? Colors.green : Colors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on_rounded, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(venueName, style: TextStyle(color: Colors.grey[800], fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(DateFormat('MMM dd, yyyy • hh:mm a').format(planDateTime), style: TextStyle(color: Colors.grey[800], fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Deposit: ${paymentStatus.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: (paymentStatus == 'paid' || paymentStatus == 'refunded') ? Colors.green : Colors.orange,
                          ),
                        ),
                        if (paymentStatus == 'unpaid' && requests.any((r) => r['status'] == 'payment_pending')) ...[
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _onHostPayDeposit(plan),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: const Size(0, 26),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              elevation: 0,
                            ),
                            child: const Text('PAY ₹99', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    TextButton(
                      onPressed: () => _onCancelPlan(plan['id']),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(50, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('CANCEL PLAN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Requests Section
          if (requests.isNotEmpty) ...[
            Container(color: Colors.grey[200], height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REQUESTS (${requests.length})',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600], letterSpacing: 1),
                  ),
                  const SizedBox(height: 12),
                  ...requests.map((req) {
                    final reqUser = req['requester'] ?? {};
                    final name = '${reqUser['firstName'] ?? ''} ${reqUser['lastName'] ?? ''}'.trim();
                    final status = req['status'] ?? 'pending';
                    final hostPaid = plan['hostPaymentStatus'] == 'paid' || plan['hostPaymentStatus'] == 'refunded';
                    final joinerPaid = req['joinerPaymentStatus'] == 'paid' || req['joinerPaymentStatus'] == 'refunded';
                    final timerText = _getTimeRemaining(req['paymentTimeoutAt']);
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.1), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: LunaraTheme.electricViolet,
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'U',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name.isNotEmpty ? name : 'Lunara User', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 4),
                                if (status.toString().toLowerCase() == 'pending')
                                  const Text('Wants to join', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600))
                                else if (status.toString().toLowerCase() == 'payment_pending' || status.toString().toLowerCase() == 'accepted') ...[
                                  if (!hostPaid)
                                    const Text('Please pay your ₹99 deposit to lock match.', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold))
                                  else if (hostPaid && !joinerPaid)
                                    Text('Waiting for joiner payment... ($timerText)', style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold))
                                  else if (hostPaid && joinerPaid) ...[
                                    const Text('Match Successful! Booking Confirmed 🎉', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 6),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => PartyPlanTicketScreen(
                                              request: req,
                                              plan: plan,
                                              isHost: true,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.qr_code_rounded, size: 14, color: Colors.white),
                                      label: const Text('VIEW TICKET', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: LunaraTheme.electricViolet,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        minimumSize: const Size(0, 32),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ]
                                ]
                                else if (status.toString().toLowerCase() == 'payment_failed')
                                  const Text('Payment timeout or failed', style: TextStyle(color: Colors.grey, fontSize: 11))
                                else if (status.toString().toLowerCase() == 'rejected')
                                  const Text('Rejected', style: TextStyle(color: Colors.grey, fontSize: 11))
                              ],
                            ),
                          ),
                          if (status.toString().toLowerCase() == 'pending')
                            ElevatedButton(
                              onPressed: () => _onAcceptRequest(req['id'], plan),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: LunaraTheme.electricViolet,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                minimumSize: const Size(0, 36),
                              ),
                              child: const Text('ACCEPT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          if ((status.toString().toLowerCase() == 'payment_pending' || status.toString().toLowerCase() == 'accepted') && !hostPaid)
                            ElevatedButton(
                              onPressed: () => _onHostPayDeposit(plan),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                minimumSize: const Size(0, 36),
                              ),
                              child: const Text('PAY ₹99', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

