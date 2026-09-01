import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import 'party_plan_ticket_screen.dart';
import 'chat_screen.dart';

class HostPartyPlanManagerScreen extends StatefulWidget {
  const HostPartyPlanManagerScreen({super.key});

  @override
  State<HostPartyPlanManagerScreen> createState() =>
      _HostPartyPlanManagerScreenState();
}

class _HostPartyPlanManagerScreenState
    extends State<HostPartyPlanManagerScreen> {
  bool _isLoading = true;
  bool _isProcessing = false;
  List<Map<String, dynamic>> _myPlans = [];
  Map<String, List<Map<String, dynamic>>> _planRequests = {};

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initSocketListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _disposeSocketListeners();
    _timer?.cancel();
    super.dispose();
  }

  void _initSocketListeners() {
    ApiService.addSocketListener('plan_unavailable', _onPlanUnavailable);
    ApiService.addSocketListener('party_plan_request_created', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_request_received', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_request_updated', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_request_cancelled', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_request_rejected', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_relisted', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_reposted', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_cancelled', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_deleted', _onSocketUpdate);
    ApiService.addSocketListener(
      'party_plan_request_accepted',
      _onSocketUpdate,
    );
    ApiService.addSocketListener('party_plan_match_success', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_host_paid', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_joiner_paid', _onSocketUpdate);
  }

  void _disposeSocketListeners() {
    ApiService.removeSocketListener('plan_unavailable', _onPlanUnavailable);
    ApiService.removeSocketListener('party_plan_request_created', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_request_received', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_request_updated', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_request_cancelled', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_request_rejected', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_relisted', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_reposted', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_cancelled', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_deleted', _onSocketUpdate);
    ApiService.removeSocketListener(
      'party_plan_request_accepted',
      _onSocketUpdate,
    );
    ApiService.removeSocketListener(
      'party_plan_match_success',
      _onSocketUpdate,
    );
    ApiService.removeSocketListener('party_plan_host_paid', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_joiner_paid', _onSocketUpdate);
  }

  void _onPlanUnavailable(dynamic data) {
    if (!mounted) return;
    try {
      final planId = data['planId']?.toString();
      final requestId = data['requestId']?.toString();
      if (planId != null && requestId != null) {
        setState(() {
          if (_planRequests.containsKey(planId)) {
            _planRequests[planId]!.removeWhere(
              (r) => r['id']?.toString() == requestId,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Error handling plan_unavailable socket: $e');
    }
  }

  void _onSocketUpdate(dynamic data) {
    if (!mounted) return;
    _loadData();
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
    final planId = plan['id']?.toString() ?? '';
    final venue = plan['venue'] as Map<String, dynamic>? ?? {};
    final venueName = venue['name'] as String? ?? 'Venue';
    final amount = (plan['depositAmount'] ?? 99.0).toDouble();
    final orderId = plan['hostRazorpayOrderId']?.toString().trim() ?? '';

    _startHostRazorpayDirectPaymentInManager(
      partyPlanId: planId,
      venueName: venueName,
      orderId: orderId,
      depositAmount: amount,
      onSuccess: () async {
        await _loadData();
      },
    );
  }

  Future<void> _startHostRazorpayDirectPaymentInManager({
    required String partyPlanId,
    required String venueName,
    required String orderId,
    required double depositAmount,
    required Future<void> Function() onSuccess,
  }) async {
    String cleanPlanId = partyPlanId;
    if (cleanPlanId.startsWith('party_plan_timeline_')) {
      cleanPlanId = cleanPlanId.replaceFirst('party_plan_timeline_', '');
    }
    if (cleanPlanId.startsWith('pp_')) {
      cleanPlanId = cleanPlanId.replaceFirst('pp_', '');
    }

    debugPrint(
      '[HOST_PAYMENT_START] Pay Deposit clicked (Host Manager): '
      'partyPlanId=$cleanPlanId, venueName=$venueName, orderId=$orderId, depositAmount=$depositAmount',
    );

    try {
      String currentOrderId = orderId.trim();
      String razorpayKey = 'rzp_test_123';

      if (currentOrderId.isEmpty ||
          (!currentOrderId.startsWith('order_mock_') &&
              !currentOrderId.startsWith('mock_') &&
              !currentOrderId.startsWith('pay_direct_') &&
              currentOrderId.length < 10)) {
        debugPrint(
          '[HOST_ORDER_CREATE] Creating Razorpay order via initiateHostPayment',
        );
        final initRes = await ApiService.initiateHostPayment(cleanPlanId);
        debugPrint(
          '[HOST_ORDER_RESPONSE] Order API response received: $initRes',
        );
        if (initRes != null && initRes['success'] == true) {
          currentOrderId = (initRes['razorpayOrderId'] ?? '').toString();
          if (initRes['razorpayKeyId'] != null &&
              initRes['razorpayKeyId'].toString().isNotEmpty) {
            razorpayKey = initRes['razorpayKeyId'].toString();
          }
        }
      }

      debugPrint(
        '[HOST_ORDER_RESPONSE] Razorpay order ID received: orderId=$currentOrderId, keyId=$razorpayKey',
      );

      late Razorpay razorpay;
      razorpay = Razorpay();

      razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (
        PaymentSuccessResponse response,
      ) async {
        final pId = response.paymentId ?? '';
        final oId = response.orderId ?? currentOrderId;
        final sig = response.signature ?? '';

        debugPrint(
          '[PAYMENT-06] Razorpay success callback: '
          'paymentId=$pId, orderId=$oId, signature=$sig',
        );

        debugPrint('[PAYMENT-08] Verifying payment with backend');
        final confirmRes = await ApiService.post(
          '/api/mobile/party-plans/$cleanPlanId/host-pay',
          body: {
            'userId': ApiService.currentUserId ?? '',
            'razorpay_order_id': oId,
            'razorpay_payment_id': pId,
            'razorpay_signature': sig,
          },
        );

        debugPrint(
          '[PAYMENT-09] Verification response: statusCode=${confirmRes.statusCode}, body=${confirmRes.body}',
        );

        razorpay.clear();
        if (confirmRes.statusCode == 200 && mounted) {
          debugPrint('[PAYMENT-10] Deposit status updated successfully');
          await onSuccess();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  '🎉 Host Safety Deposit Paid! Your plan is fully activated.',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else if (mounted) {
          String msg = 'Payment Confirmation Failed';
          try {
            final b = jsonDecode(confirmRes.body);
            msg = b['message'] ?? b['error'] ?? msg;
          } catch (_) {}
          if (msg == 'Payment Failed') {
            msg = 'Verification failed (Status ${confirmRes.statusCode})';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment Failed: $msg'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      });

      razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (
        PaymentFailureResponse response,
      ) {
        debugPrint(
          '[PAYMENT-07] Razorpay error callback: code=${response.code}, message=${response.message}',
        );
        razorpay.clear();
        if (mounted) {
          String errText =
              response.message ?? 'Payment process cancelled or failed';
          if (errText.isEmpty || errText == 'Payment Failed') {
            if (response.code == Razorpay.PAYMENT_CANCELLED) {
              errText = 'Payment cancelled by user';
            } else {
              errText = 'Payment error (code ${response.code})';
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment Failed: $errText'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      });

      razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (
        ExternalWalletResponse response,
      ) {
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

      debugPrint(
        '[PAYMENT-05] Opening Razorpay checkout: key=$razorpayKey, amount=${options['amount']}, orderId=$currentOrderId',
      );

      try {
        razorpay.open(options);
      } catch (e) {
        debugPrint('Error opening Razorpay for Host Payment: $e');
      }
    } catch (e) {
      debugPrint('Error initiating host deposit payment: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final plans = await ApiService.fetchMyPartyPlans();
      final activePlans = plans
          .where((p) => p['status'] != 'cancelled')
          .toList();

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
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final result = await ApiService.acceptPartyPlanRequest(reqId);
      if (!mounted) return;
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Request Accepted! Complete your deposit to lock match.',
            ),
          ),
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
          const SnackBar(
            content: Text('Failed to accept request.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _onCancelPlan(String planId) {
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                    const Text(
                      'Why are you cancelling?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Select a reason for internal record. This is never displayed publicly.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    ...reasonOptions.entries.map((entry) {
                      final isSelected = selectedReason == entry.key;
                      return InkWell(
                        onTap: () => setModalState(() => selectedReason = entry.key),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.redAccent.withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.redAccent
                                  : Colors.white10,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: isSelected
                                    ? Colors.redAccent
                                    : Colors.white38,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  entry.value,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter reason (max 150 characters)',
                          hintStyle: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showHostChoiceDialog(
                            planId,
                            selectedReason,
                            selectedReason == 'other'
                                ? otherController.text.trim()
                                : null,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'PROCEED WITH CANCELLATION',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 0.8,
                          ),
                        ),
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

  void _showHostChoiceDialog(String planId, String selectedReason, String? otherText) {
    Map<String, dynamic>? plan;
    try {
      plan = _myPlans.firstWhere((p) => p['id']?.toString() == planId || p['planId']?.toString() == planId);
    } catch (_) {}
    final vis = plan?['visibility']?.toString().toLowerCase() ?? 'public';
    final isPrivateOrBoth = vis == 'private' || vis == 'both';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF14141F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, color: LunaraTheme.electricViolet, size: 24),
            SizedBox(width: 10),
            Text(
              'CANCEL OR REPOST?',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose an option for your Party Plan:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Option A: Cancel & Refund',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• Party Plan permanently ends.\n• ₹99 Commitment Deposit refunded to your Lunara Wallet.\n• All pending requests are cancelled.',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                  ),
                ],
              ),
            ),
            if (isPrivateOrBoth) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.public_rounded, color: Colors.tealAccent, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Option B: Repost Publicly',
                          style: TextStyle(
                            color: Colors.tealAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      '• Makes your plan public in the Live Feed.\n• Anyone nearby can discover and join.\n• Your ₹99 deposit remains active.',
                      style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event_repeat_rounded, color: LunaraTheme.electricViolet, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        isPrivateOrBoth ? 'Option C: Reschedule' : 'Option B: Repost Plan',
                        style: const TextStyle(
                          color: LunaraTheme.electricViolet,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '• Reschedule for a new date & time.\n• Remains active & live in feed (no refund).\n• Prior requests cleared for new schedule.',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                  ),
                ],
              ),
            ),
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
              _handleHostCancelAndRefund(planId, selectedReason, otherText);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'CANCEL & REFUND',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
          if (isPrivateOrBoth)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _handleHostMakePublic(planId);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                'REPOST PUBLICLY',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleHostRepostFlow(planId, selectedReason, otherText);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: LunaraTheme.electricViolet,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              isPrivateOrBoth ? 'RESCHEDULE' : 'REPOST PLAN',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  void _handleHostMakePublic(String planId) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final res = await ApiService.makePartyPlanPublic(planId);
      if (!mounted) return;
      if (res?['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Plan is now Public in the Live Feed! Anyone can now discover and join.'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res?['message'] ?? 'Failed to make plan public.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _handleHostCancelAndRefund(String planId, String reason, String? otherText) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final res = await ApiService.cancelPartyPlanDetailed(
        planId,
        reason: reason == 'other' ? otherText : reason,
      );
      if (!mounted) return;
      if (res?['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res?['message'] ?? 'Plan cancelled and refund processed.'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res?['message'] ?? 'Failed to cancel plan.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _handleHostRepostFlow(String planId, String reason, String? otherText) async {
    final now = DateTime.now();
    final initialDate = now.add(const Duration(hours: 1));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: LunaraTheme.electricViolet,
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A24),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: LunaraTheme.electricViolet,
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A24),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedTime == null || !mounted) return;

    final newDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (newDateTime.difference(DateTime.now()).inMinutes < 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a time at least 30 minutes in the future.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final res = await ApiService.repostPartyPlan(
        planId,
        newDateTime: newDateTime,
        reason: reason == 'other' ? otherText : reason,
      );
      if (!mounted) return;
      if (res?['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Party Plan reposted for ${DateFormat('dd MMM, hh:mm a').format(newDateTime)}!'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res?['message'] ?? 'Failed to repost plan.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _onRevokeAcceptance(String reqId) async {
    if (_isProcessing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoke acceptance?'),
        content: const Text(
          'The participant has not completed payment. Revoking closes their payment window and reopens eligible requests.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('KEEP ACCEPTANCE'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('REVOKE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isProcessing = true);
    final success = await ApiService.revokePartyPlanAcceptance(reqId);
    if (!mounted) return;
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Acceptance revoked. Payment window closed.'
              : 'Unable to revoke acceptance. Refresh and try again.',
        ),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
    if (success) await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Manage My Plans',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: LunaraTheme.electricViolet,
              ),
            )
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

  Widget _buildPlanCard(
    Map<String, dynamic> plan,
    List<Map<String, dynamic>> requests,
  ) {
    final venue = plan['venue'] ?? {};
    final venueName = venue['name'] ?? 'Unknown Venue';
    final message = plan['message'] ?? 'Let\'s party!';
    final planDateTime = plan['planDateTime'] != null
        ? DateTime.parse(plan['planDateTime']).toLocal()
        : DateTime.now();
    final isLive = plan['isLive'] ?? false;
    final paymentStatus = (plan['hostPaymentStatus'] ?? 'pending')
        .toString()
        .toLowerCase();
    final bool isHostPaid =
        paymentStatus == 'paid' ||
        paymentStatus == 'refunded' ||
        paymentStatus == 'completed' ||
        paymentStatus == 'confirmed';

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
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
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isLive
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.orange.withValues(alpha: 0.1),
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
                    Icon(
                      Icons.location_on_rounded,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      venueName,
                      style: TextStyle(color: Colors.grey[800], fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MMM dd, yyyy • hh:mm a').format(planDateTime),
                      style: TextStyle(color: Colors.grey[800], fontSize: 13),
                    ),
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
                            color: isHostPaid ? Colors.green : Colors.orange,
                          ),
                        ),
                        if (!isHostPaid &&
                            requests.any(
                              (r) => r['status'] == 'payment_pending',
                            )) ...[
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _onHostPayDeposit(plan),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              minimumSize: const Size(0, 26),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'PAY ₹99',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                      child: const Text(
                        'CANCEL PLAN',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...requests.map<Widget>((req) {
                    final hasActiveReservation = requests.any(
                      (r) =>
                          r['status']?.toString().toLowerCase() ==
                              'payment_pending' ||
                          r['status']?.toString().toLowerCase() == 'accepted',
                    );
                    final reqUser = req['requester'] ?? {};
                    final name =
                        '${reqUser['firstName'] ?? ''} ${reqUser['lastName'] ?? ''}'
                            .trim();
                    final status = req['status'] ?? 'pending';
                    final isSelfPay = plan['paymentType'] == 'self_pay';
                    final hostPaid = isHostPaid;
                    final joinerPaid =
                        req['joinerPaymentStatus']?.toString().toLowerCase() ==
                            'paid' ||
                        req['joinerPaymentStatus']?.toString().toLowerCase() ==
                            'refunded' ||
                        isSelfPay;
                    final timerText = _getTimeRemaining(
                      req['paymentTimeoutAt'],
                    );

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: LunaraTheme.electricViolet.withValues(
                            alpha: 0.1,
                          ),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: LunaraTheme.electricViolet.withValues(
                              alpha: 0.05,
                            ),
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
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isNotEmpty ? name : 'Lunara User',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (status.toString().toLowerCase() ==
                                    'pending') ...[
                                  if (req['isInvite'] == true)
                                    const Text(
                                      'Invited (Awaiting User Acceptance)',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  else
                                    const Text(
                                      'Wants to join',
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ] else if (status.toString().toLowerCase() ==
                                        'payment_pending' ||
                                    status.toString().toLowerCase() ==
                                        'accepted') ...[
                                  if (!hostPaid)
                                    const Text(
                                      'Please pay your ₹99 deposit to lock match.',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  else if (hostPaid && !joinerPaid)
                                    Text(
                                      'Waiting for joiner payment... ($timerText)',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  else if (hostPaid && joinerPaid) ...[
                                    const Text(
                                      'Match Successful! Booking Confirmed 🎉',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      PartyPlanTicketScreen(
                                                        request: req,
                                                        plan: plan,
                                                        isHost: true,
                                                      ),
                                                ),
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.qr_code_rounded,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                            label: const Text(
                                              'VIEW TICKET',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  LunaraTheme.electricViolet,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 4,
                                                  ),
                                              minimumSize: const Size(0, 32),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (reqUser != null &&
                                            reqUser.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => ChatScreen(
                                                      user: {
                                                        ...reqUser,
                                                        'contextType':
                                                            'party_plan',
                                                        'planId': plan['id']
                                                            ?.toString(),
                                                      },
                                                    ),
                                                  ),
                                                );
                                              },
                                              icon: const Icon(
                                                Icons
                                                    .chat_bubble_outline_rounded,
                                                size: 14,
                                                color: Colors.white,
                                              ),
                                              label: const Text(
                                                'CHAT',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    LunaraTheme.hotPink,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 4,
                                                    ),
                                                minimumSize: const Size(0, 32),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ] else if (status.toString().toLowerCase() ==
                                    'payment_failed')
                                  const Text(
                                    'Payment timeout or failed',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                    ),
                                  )
                                else if (status.toString().toLowerCase() ==
                                    'rejected')
                                  const Text(
                                    'Rejected',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (status.toString().toLowerCase() == 'pending' &&
                              req['isInvite'] != true)
                            ElevatedButton(
                              onPressed: (_isProcessing || hasActiveReservation)
                                  ? null
                                  : () => _onAcceptRequest(req['id'], plan),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: hasActiveReservation
                                    ? Colors.grey
                                    : LunaraTheme.electricViolet,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.grey.withValues(
                                  alpha: 0.3,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                minimumSize: const Size(0, 36),
                              ),
                              child: _isProcessing
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      hasActiveReservation
                                          ? 'LOCKED (30M)'
                                          : 'ACCEPT',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          if ((status.toString().toLowerCase() ==
                                      'payment_pending' ||
                                  status.toString().toLowerCase() ==
                                      'accepted') &&
                              req['joinerRazorpayPaymentId'] == null)
                            TextButton(
                              onPressed: _isProcessing
                                  ? null
                                  : () => _onRevokeAcceptance(
                                      req['id'].toString(),
                                    ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                              ),
                              child: const Text(
                                'REVOKE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if ((status.toString().toLowerCase() ==
                                      'payment_pending' ||
                                  status.toString().toLowerCase() ==
                                      'accepted') &&
                              !hostPaid)
                            ElevatedButton(
                              onPressed: _isProcessing
                                  ? null
                                  : () => _onHostPayDeposit(plan),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.green
                                    .withValues(alpha: 0.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                minimumSize: const Size(0, 36),
                              ),
                              child: const Text(
                                'PAY ₹99',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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
