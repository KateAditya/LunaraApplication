import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../models/strangers_meet_request.dart';
import 'strangers_meet_ticket_screen.dart';

class StrangersMeetPaymentScreen extends StatefulWidget {
  final StrangersMeetRequest request;
  final VoidCallback onPaymentSuccess;

  const StrangersMeetPaymentScreen({
    super.key,
    required this.request,
    required this.onPaymentSuccess,
  });

  @override
  State<StrangersMeetPaymentScreen> createState() => _StrangersMeetPaymentScreenState();
}

class _StrangersMeetPaymentScreenState extends State<StrangersMeetPaymentScreen> {
  bool _isProcessing = false;
  late Razorpay _razorpay;
  String? _lastOrderId;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleRazorpaySuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleRazorpayError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
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
    setState(() => _isProcessing = true);

    // Call checkout / initiate endpoint on backend
    final checkoutData = await ApiService.initiateStrangersMeetPayment(widget.request.id);

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
    final String razorpayKeyId = checkoutData['razorpayKeyId'] ?? 'rzp_test_123';
    final int amount = checkoutData['amount'];

    var options = {
      'key': razorpayKeyId,
      'amount': amount,
      'name': 'Lunara',
      'description': 'Strangers Meet - ${widget.request.subject}',
      'order_id': orderId,
      'prefill': {
        'contact': '8888888888',
        'email': 'test@razorpay.com'
      }
    };

    bool razorpayOpened = false;
    try {
      _razorpay.open(options);
      razorpayOpened = true;
    } catch (e) {
      debugPrint('Error opening Razorpay, falling back to simulated payment: $e');
    }

    if (!razorpayOpened) {
      // Fallback simulated payment
      Future.delayed(const Duration(seconds: 2), () {
        _confirmPayment(orderId, 'mock_payment', 'mock_signature');
      });
    }
  }

  Future<void> _confirmPayment(String orderId, String paymentId, String signature) async {
    if (!mounted) return;
    setState(() => _isProcessing = true);

    final result = await ApiService.payStrangersMeetRequest(
      widget.request.id,
      orderId,
      paymentId,
      signature,
    );
    
    if (!mounted) return;
    
    setState(() => _isProcessing = false);

    if (result != null) {
      widget.onPaymentSuccess();
      
      // Update the request with ticket info before passing
      final updatedReq = StrangersMeetRequest(
        id: widget.request.id,
        subject: widget.request.subject,
        tagline: widget.request.tagline,
        eventDateTime: widget.request.eventDateTime,
        numberOfPersons: widget.request.numberOfPersons,
        chargesPerHead: widget.request.chargesPerHead,
        slotsFilled: widget.request.slotsFilled,
        status: widget.request.status,
        paymentAmount: widget.request.paymentAmount,
        paymentStatus: 'paid',
        adminNotes: widget.request.adminNotes,
        ticketId: result['ticketId'],
        createdAt: widget.request.createdAt,
        user: widget.request.user,
        venue: widget.request.venue,
        joiners: widget.request.joiners,
      );

      // Replace current screen with Ticket Screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => StrangersMeetTicketScreen(request: updatedReq),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment verification failed. Please contact support.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final amount = req.paymentAmount ?? 0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Payment Confirmation', style: TextStyle(fontWeight: FontWeight.w900)),
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
                          _buildSummaryRow('Venue', req.venue?['name'] ?? 'Unknown'),
                          const SizedBox(height: 12),
                          _buildSummaryRow('Date & Time', DateFormat('MMM dd, yyyy • hh:mm a').format(req.eventDateTime)),
                          const SizedBox(height: 12),
                          _buildSummaryRow('Persons', '${req.numberOfPersons} pax'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Payment Breakdown
                    const Text(
                      'Payment Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildPaymentRow('Event Arrangement Fee', '₹${amount.toStringAsFixed(0)}'),
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
                          'Total Amount',
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
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
