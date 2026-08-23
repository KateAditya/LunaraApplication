// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../models/strangers_meet_request.dart';
import '../../widgets/smart_checkout_sheet.dart';
import 'strangers_meet_ticket_screen.dart';

class StrangersMeetPaymentScreen extends StatefulWidget {
  final StrangersMeetRequest request;
  final VoidCallback onPaymentSuccess;
  final bool isJoinPayment;

  const StrangersMeetPaymentScreen({
    super.key,
    required this.request,
    required this.onPaymentSuccess,
    this.isJoinPayment = false,
  });

  @override
  State<StrangersMeetPaymentScreen> createState() =>
      _StrangersMeetPaymentScreenState();
}

class _StrangersMeetPaymentScreenState
    extends State<StrangersMeetPaymentScreen> {
  bool _isProcessing = false;
  late Razorpay _razorpay;
  String? _lastOrderId;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      try {
        _razorpay = Razorpay();
        _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleRazorpaySuccess);
        _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleRazorpayError);
        _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
      } catch (e) {
        debugPrint('Razorpay init error: $e');
      }
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      try {
        _razorpay.clear();
      } catch (e) {
        debugPrint('Razorpay clear error: $e');
      }
    }
    super.dispose();
  }

  void _handleRazorpaySuccess(PaymentSuccessResponse response) {
    _confirmPayment(
      response.orderId ?? _lastOrderId ?? 'mock_order',
      response.paymentId ?? 'mock_payment',
      response.signature ?? 'mock_signature',
    );
  }

  void _handleRazorpayError(PaymentFailureResponse response) {
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('External Wallet: ${response.walletName}')),
    );
  }

  Future<void> _handlePayment() async {
    // The card may have been opened before the event expired. Always refresh
    // the authoritative event time before opening a checkout flow.
    final latestRequest = await ApiService.fetchStrangersMeetRequestById(
      widget.request.id,
    );
    if (!mounted) return;
    if (latestRequest == null || latestRequest.eventDateTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This Stranger Meet has expired and can no longer be paid for.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final double amount = widget.isJoinPayment
        ? latestRequest.chargesPerHead
        : (latestRequest.paymentAmount ?? 99.0);

    SmartCheckoutSheet.show(
      context: context,
      title: 'Strangers Meet - ${widget.request.subject}',
      subtitle: widget.isJoinPayment
          ? 'Joiner Fee Payment'
          : 'Host Platform Deposit',
      itemPrice: amount,
      onWalletPayment: () async {
        final res = await ApiService.payWithWallet(
          amount: amount,
          planId: widget.request.id,
          paymentType: widget.isJoinPayment
              ? 'strangers_meet_join'
              : 'strangers_meet_deposit',
        );
        if (res != null && res['success'] == true) {
          final transactionId = res['data']?['transactionId']?.toString() ?? 'wallet';
          final confirmRes = widget.isJoinPayment
              ? await ApiService.payStrangersMeetJoin(
                  widget.request.id,
                  'order_mock_wallet',
                  'wallet_$transactionId',
                  'mock_signature',
                )
              : await ApiService.payStrangersMeetRequest(
                  widget.request.id,
                  'order_mock_wallet',
                  'wallet_$transactionId',
                  'mock_signature',
                );

          if (confirmRes != null && confirmRes['success'] == true) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Payment Successful via Smart Wallet! 🎫'),
                  backgroundColor: Color(0xFF10B981),
                ),
              );
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => StrangersMeetTicketScreen(
                    request: widget.request,
                  ),
                ),
              );
            }
            return true;
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(confirmRes?['message'] ?? 'Wallet confirmation failed'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
            return false;
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(res?['message'] ?? 'Wallet payment failed'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return false;
        }
      },
      onDirectPayment: () async {
        await _executeDirectRazorpay();
      },
      onHybridPayment: (shortfallAmount) async {
        final orderData = await ApiService.createWalletRechargeOrder(
          shortfallAmount,
        );
        if (orderData != null) {
          final String orderId = orderData['orderId'] ?? orderData['id'] ?? '';
          final options = {
            'key': orderData['keyId'] ?? 'rzp_test_key',
            'amount': (shortfallAmount * 100).toInt(),
            'name': 'Lunara Shortfall',
            'description':
                'Recharge ₹${shortfallAmount.toStringAsFixed(0)} for Strangers Meet',
            'order_id': orderId,
            'theme': {'color': '#7F00FF'},
          };

          _razorpay.open(options);
        }
      },
    );
  }

  Future<void> _executeDirectRazorpay() async {
    setState(() => _isProcessing = true);

    Map<String, dynamic>? checkoutData;
    try {
      checkoutData = widget.isJoinPayment
          ? await ApiService.initiateStrangersMeetJoinPayment(widget.request.id)
          : await ApiService.initiateStrangersMeetPayment(widget.request.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      final errorStr = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorStr), backgroundColor: Colors.red),
      );
      return;
    }

    if (checkoutData == null) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to initiate payment. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final String orderId = checkoutData['razorpayOrderId'];
    _lastOrderId = orderId;
    final String razorpayKeyId =
        checkoutData['razorpayKeyId'] ?? 'rzp_test_123';
    final int amount = checkoutData['amount'];

    var options = {
      'key': razorpayKeyId,
      'amount': amount,
      'name': 'Lunara',
      'description': 'Strangers Meet - ${widget.request.subject}',
      'order_id': orderId,
      'prefill': {'contact': '8888888888', 'email': 'test@razorpay.com'},
    };

    if (kIsWeb || orderId.startsWith('order_mock_') || razorpayKeyId == 'rzp_test_123') {
      _confirmPayment(orderId, 'mock_payment', 'mock_signature');
      return;
    }

    bool razorpayOpened = false;
    try {
      _razorpay.open(options);
      razorpayOpened = true;
    } catch (e) {
      debugPrint(
        'Error opening Razorpay, falling back to simulated payment: $e',
      );
    }

    if (!razorpayOpened) {
      Future.delayed(const Duration(seconds: 2), () {
        _confirmPayment(orderId, 'mock_payment', 'mock_signature');
      });
    }
  }

  Future<void> _confirmPayment(
    String orderId,
    String paymentId,
    String signature,
  ) async {
    if (!mounted) return;
    setState(() => _isProcessing = true);

    Map<String, dynamic>? result;
    try {
      result = widget.isJoinPayment
          ? await ApiService.payStrangersMeetJoin(
              widget.request.id,
              orderId,
              paymentId,
              signature,
            )
          : await ApiService.payStrangersMeetRequest(
              widget.request.id,
              orderId,
              paymentId,
              signature,
            );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      final errorStr = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorStr), backgroundColor: Colors.red),
      );
      return;
    }

    if (!mounted) return;

    setState(() => _isProcessing = false);

    if (result != null) {
      widget.onPaymentSuccess();
      if (widget.isJoinPayment) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Payment confirmed! You have successfully joined the meet. 🎉',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        _promptChargesPerHead(result);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment verification failed. Please contact support.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _promptChargesPerHead(Map<String, dynamic> result) async {
    final TextEditingController chargesController = TextEditingController(
      text: '199',
    );
    double selectedCharges = 199.0;
    bool isSaving = false;

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle indicator
                      Center(
                        child: Container(
                          width: 48,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '💵 Decide Entry Price',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Set your per-seat charge. Participants will pay this to join. Set ₹0 to make it free.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Live Profit Preview
                      Builder(
                        builder: (ctx) {
                          final totalSeats = widget.request.numberOfPersons;
                          final platformTotal =
                              widget.request.paymentAmount ?? 0;
                          final platformPerSeat =
                              widget.request.platformChargePerSeat ??
                              (platformTotal / totalSeats);
                          // Estimated: assume half seats filled for preview
                          final estimatedFilled = totalSeats;
                          final hostRevenue = selectedCharges * estimatedFilled;
                          final netProfit = hostRevenue - platformTotal;
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: netProfit >= 0
                                  ? Colors.green.withValues(alpha: 0.06)
                                  : Colors.orange.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: netProfit >= 0
                                    ? Colors.green.withValues(alpha: 0.3)
                                    : Colors.orange.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PROFIT ESTIMATE (if all $totalSeats seats filled)',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Platform fee paid',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    Text(
                                      '- ₹${platformTotal.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.red,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Your revenue ($totalSeats × ₹${selectedCharges.toStringAsFixed(0)})',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const SizedBox(width: 8),
                                    Text(
                                      '+ ₹${hostRevenue.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.green,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Your net profit',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '₹${netProfit.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: netProfit >= 0
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Platform charge/seat: ₹${platformPerSeat.toStringAsFixed(0)} · Unfilled seats refunded by platform',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // Custom Input Field
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: TextField(
                          controller: chargesController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Enter charges per head',
                            prefixText: '₹ ',
                            border: InputBorder.none,
                          ),
                          onChanged: (val) {
                            setModalState(() {
                              selectedCharges = double.tryParse(val) ?? 0.0;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Quick Selection Chips
                      const Text(
                        'QUICK SELECTIONS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildQuickChip('Free', 0.0, selectedCharges, (val) {
                            setModalState(() {
                              selectedCharges = val;
                              chargesController.text = val.toStringAsFixed(0);
                            });
                          }),
                          _buildQuickChip('₹99', 99.0, selectedCharges, (val) {
                            setModalState(() {
                              selectedCharges = val;
                              chargesController.text = val.toStringAsFixed(0);
                            });
                          }),
                          _buildQuickChip('₹199', 199.0, selectedCharges, (
                            val,
                          ) {
                            setModalState(() {
                              selectedCharges = val;
                              chargesController.text = val.toStringAsFixed(0);
                            });
                          }),
                          _buildQuickChip('₹499', 499.0, selectedCharges, (
                            val,
                          ) {
                            setModalState(() {
                              selectedCharges = val;
                              chargesController.text = val.toStringAsFixed(0);
                            });
                          }),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Confirm and Publish Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  if (selectedCharges < 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Charges cannot be negative',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  setModalState(() {
                                    isSaving = true;
                                  });

                                  final success =
                                      await ApiService.updateStrangersMeetCharges(
                                        widget.request.id,
                                        selectedCharges,
                                      );

                                  if (success) {
                                    Navigator.pop(
                                      context,
                                    ); // Close bottom sheet

                                    // Update the local request
                                    final updatedReq = StrangersMeetRequest(
                                      id: widget.request.id,
                                      subject: widget.request.subject,
                                      tagline: widget.request.tagline,
                                      eventDateTime:
                                          widget.request.eventDateTime,
                                      numberOfPersons:
                                          widget.request.numberOfPersons,
                                      chargesPerHead: selectedCharges,
                                      slotsFilled: widget.request.slotsFilled,
                                      status: widget.request.status,
                                      paymentAmount:
                                          widget.request.paymentAmount,
                                      paymentStatus: 'paid',
                                      adminNotes: widget.request.adminNotes,
                                      ticketId: result['ticketId'],
                                      createdAt: widget.request.createdAt,
                                      mobileNumber: widget.request.mobileNumber,
                                      alternateMobileNumber:
                                          widget.request.alternateMobileNumber,
                                      bankName: widget.request.bankName,
                                      accountNumber:
                                          widget.request.accountNumber,
                                      accountHolderName:
                                          widget.request.accountHolderName,
                                      ifscCode: widget.request.ifscCode,
                                      upiId: widget.request.upiId,
                                      platformChargePerSeat:
                                          widget.request.platformChargePerSeat,
                                      settlementStatus:
                                          widget.request.settlementStatus,
                                      bankDetails: widget.request.bankDetails,
                                      settlementTransactionId: widget
                                          .request
                                          .settlementTransactionId,
                                      settlementAmount:
                                          widget.request.settlementAmount,
                                      settlementDate:
                                          widget.request.settlementDate,
                                      settlementMethod:
                                          widget.request.settlementMethod,
                                      user: widget.request.user,
                                      venue: widget.request.venue,
                                      joiners: widget.request.joiners,
                                    );

                                    // Push to Ticket Screen
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            '🎉 Payment Successful! Your Stranger Meet is LIVE! 🚀',
                                          ),
                                          backgroundColor: Colors.green,
                                          duration: Duration(seconds: 4),
                                        ),
                                      );
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              StrangersMeetTicketScreen(
                                                request: updatedReq,
                                              ),
                                        ),
                                      );
                                    }
                                  } else {
                                    setModalState(() {
                                      isSaving = false;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Failed to update charges per head. Please try again.',
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: LunaraTheme.electricViolet,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: isSaving
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  'PUBLISH MEETUP',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickChip(
    String label,
    double value,
    double currentValue,
    ValueChanged<double> onTap,
  ) {
    final isSelected = value == currentValue;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? LunaraTheme.electricViolet : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? LunaraTheme.electricViolet : Colors.grey[200]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[800],
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final amount = widget.isJoinPayment
        ? req.chargesPerHead
        : (req.paymentAmount ?? 0);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Payment Confirmation',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'EVENT SUMMARY',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            req.subject,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildSummaryRow(
                            'Venue',
                            req.venue?['name'] ?? 'Unknown',
                          ),
                          const SizedBox(height: 12),
                          _buildSummaryRow(
                            'Date & Time',
                            DateFormat(
                              'MMM dd, yyyy • hh:mm a',
                            ).format(req.eventDateTime),
                          ),
                          const SizedBox(height: 12),
                          _buildSummaryRow(
                            'Persons',
                            widget.isJoinPayment
                                ? '1 pax'
                                : '${req.numberOfPersons} pax',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Platform Fee Breakdown
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            LunaraTheme.electricViolet.withValues(alpha: 0.05),
                            Colors.purple.withValues(alpha: 0.02),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: LunaraTheme.electricViolet.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PAYMENT BREAKDOWN',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildPaymentRow(
                            'Total Seats Booked',
                            widget.isJoinPayment
                                ? '1 seat'
                                : '${req.numberOfPersons} seats',
                          ),
                          const SizedBox(height: 8),
                          if (!widget.isJoinPayment &&
                              req.platformChargePerSeat != null) ...[
                            _buildPaymentRow(
                              'Platform Charge / Seat',
                              '₹${req.platformChargePerSeat!.toStringAsFixed(0)}',
                            ),
                            const SizedBox(height: 8),
                          ],
                          _buildPaymentRow(
                            widget.isJoinPayment
                                ? 'Entry Ticket Fee'
                                : 'Event Arrangement Fee',
                            '₹${amount.toStringAsFixed(0)}',
                          ),
                          const SizedBox(height: 8),
                          _buildPaymentRow('Taxes & Fees', 'Included'),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Divider(),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total Amount to Pay',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '₹${amount.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: LunaraTheme.electricViolet,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // How earnings work
                    if (!widget.isJoinPayment)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: Colors.green,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'How Your Earnings Work',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '1. You pay the arrangement fee of ₹${amount.toStringAsFixed(0)} to secure ${req.numberOfPersons} seats.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '2. After payment, you decide your per-head charge for participants.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '3. After the meet, admin will settle: your participant earnings + refund for unfilled seats.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Pay Button
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _handlePayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LunaraTheme.electricViolet,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isProcessing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          'PAY ₹${amount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
