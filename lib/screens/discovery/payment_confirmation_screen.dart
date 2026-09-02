// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import 'split_payment_screen.dart';
import 'digital_ticket_screen.dart';
import '../../services/api_service.dart';
import '../../widgets/top_notification_banner.dart';
import '../../widgets/smart_checkout_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

class PaymentConfirmationScreen extends StatefulWidget {
  final String? bookingId;
  final Map<dynamic, dynamic> venue;
  final String date;
  final String package;
  final String? time;
  final String? table;
  final String? guests;
  final String? totalPrice;
  final bool showSplitBill;
  final Future<void> Function()? onPaymentSuccess;
  final Future<void> Function(String paymentId, String signature)?
  onRazorpayPaymentSuccess;
  final String? razorpayOrderId;
  final int? razorpayAmount;
  final String? razorpayKeyId;
  final String? mobileNumber;
  final String? optionalMobileNumber;
  final Future<bool> Function()? onCustomWalletPayment;
  final Future<void> Function()? onCustomDirectPayment;
  final Future<void> Function(double shortfallAmount)? onCustomHybridPayment;
  final Future<void> Function()? onPaymentCancelled;
  final Widget Function(BuildContext)? ticketScreenBuilder;
  // When true, the wallet/gateway checkout sheet opens automatically as soon
  // as this screen renders, instead of requiring an extra tap on this
  // screen's own 'PAY NOW' button first. Defaults to false so every existing
  // caller keeps its current two-step behavior unchanged; opt in per call
  // site where the summary shown here would otherwise duplicate a price
  // screen the user already confirmed just before navigating here.
  final bool autoOpenPayment;

  const PaymentConfirmationScreen({
    super.key,
    this.bookingId,
    required this.venue,
    required this.date,
    required this.package,
    this.time,
    this.table,
    this.guests,
    this.totalPrice,
    this.showSplitBill = true,
    this.onPaymentSuccess,
    this.onRazorpayPaymentSuccess,
    this.razorpayOrderId,
    this.razorpayAmount,
    this.razorpayKeyId,
    this.mobileNumber,
    this.optionalMobileNumber,
    this.onCustomWalletPayment,
    this.onCustomDirectPayment,
    this.onCustomHybridPayment,
    this.onPaymentCancelled,
    this.ticketScreenBuilder,
    this.autoOpenPayment = false,
  });

  @override
  State<PaymentConfirmationScreen> createState() =>
      _PaymentConfirmationScreenState();
}

class _PaymentConfirmationScreenState extends State<PaymentConfirmationScreen> {
  late Razorpay _razorpay;
  // Track whether the processing loading dialog is currently shown
  bool _isProcessingDialogOpen = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      try {
        _razorpay = Razorpay();
        _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
        _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
        _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
      } catch (e) {
        debugPrint('Razorpay init error: $e');
      }
    }
    if (widget.autoOpenPayment) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handlePayment(context);
      });
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

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    // Only pop the processing dialog if one is actually open.
    // DO NOT pop the screen itself here — Razorpay closes its own UI.
    // Prematurely popping here was causing the PaymentConfirmationScreen to
    // close before the onPaymentSuccess callbacks ran, breaking navigation.
    if (_isProcessingDialogOpen && mounted) {
      _isProcessingDialogOpen = false;
      Navigator.pop(context); // Close the processing dialog only
    }

    if (widget.bookingId != null && widget.bookingId!.isNotEmpty) {
      await ApiService.payNowBooking(
        widget.bookingId!,
        paymentMethod: 'CARD',
        razorpayPaymentId: response.paymentId,
        razorpaySignature: response.signature,
        razorpayOrderId: response.orderId ?? widget.razorpayOrderId,
      );
    }

    if (widget.onRazorpayPaymentSuccess != null) {
      await widget.onRazorpayPaymentSuccess!(
        response.paymentId ?? 'rzp_test_T1rwVokR7tFger',
        response.signature ?? 'mock_signature',
      );
    } else if (widget.onPaymentSuccess != null) {
      await widget.onPaymentSuccess!();
    }

    if (!mounted) return;

    TopNotificationBanner.show(
      title: 'Booking Confirmed! 🎉',
      body: 'Your payment at ${widget.venue['name'] ?? 'Venue'} is confirmed. Digital ticket generated!',
      data: {'bookingId': widget.bookingId},
    );
    if (widget.package == 'Party Plan Safety Deposit') {
      // Pop the PaymentConfirmationScreen back to live feed
      Navigator.pop(context);
    } else if (widget.ticketScreenBuilder != null) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: widget.ticketScreenBuilder!),
        (route) => route.isFirst,
      );
    } else {
      final isSolo = (widget.guests?.trim() == '1' ||
          widget.guests?.trim() == '1 Guest' ||
          widget.package.toLowerCase().contains('solo'));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DigitalTicketScreen(
            venue: widget.venue,
            date: widget.date,
            package: widget.package,
            time: widget.time,
            table: widget.table ?? (isSolo ? 'Solo Entry' : null),
            guests: isSolo ? '1' : widget.guests,
            totalPrice: widget.totalPrice,
            ticketId: widget.bookingId ?? widget.razorpayOrderId ?? 'TICKET',
            user: ApiService.cachedCurrentUser,
            booking: {
              'id': widget.bookingId,
              'bookingId': widget.bookingId,
              'venue': widget.venue,
              'venueId': widget.venue['id'],
              'isSolo': isSolo,
              'goingMode': isSolo ? 'solo' : 'venue_booking',
              'bookingType': isSolo ? 'solo' : 'venue_booking',
              'category': isSolo ? 'solo' : 'venue_booking',
              'totalAmount': widget.totalPrice,
              'paymentStatus': 'paid',
              'paymentMethod': 'UPI / Net Banking',
              'status': 'CONFIRMED',
              'tablePackage': widget.table ?? widget.package,
              'numberOfGuests': isSolo ? 1 : widget.guests,
              'bookingDate': widget.date,
              'startTime': widget.time,
              'user': ApiService.cachedCurrentUser,
            },
          ),
        ),
      );
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) async {
    if (_isProcessingDialogOpen && mounted) {
      _isProcessingDialogOpen = false;
      Navigator.pop(context); // Close the processing dialog
    }
    if (widget.bookingId != null && widget.bookingId!.isNotEmpty) {
      await ApiService.cancelPendingBooking(widget.bookingId!);
    }
    if (widget.onPaymentCancelled != null) {
      widget.onPaymentCancelled!();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment cancelled / failed: ${response.message}')),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (_isProcessingDialogOpen && mounted) {
      _isProcessingDialogOpen = false;
      Navigator.pop(context); // Close the processing dialog
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('External Wallet selected: ${response.walletName}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          if (widget.bookingId != null && widget.bookingId!.isNotEmpty) {
            await ApiService.cancelPendingBooking(widget.bookingId!);
          }
          if (widget.onPaymentCancelled != null) {
            widget.onPaymentCancelled!();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      _buildSummaryCard(),
                      const SizedBox(height: 32),
                      _buildWarningSection(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () async {
              if (widget.bookingId != null && widget.bookingId!.isNotEmpty) {
                await ApiService.cancelPendingBooking(widget.bookingId!);
              }
              if (widget.onPaymentCancelled != null) {
                widget.onPaymentCancelled!();
              }
              if (context.mounted) Navigator.pop(context);
            },
          ),
          const Expanded(
            child: Center(
              child: Text(
                'PAYMENT',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48), // To balance the back button
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LunaraTheme.cardGradient,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
            blurRadius: 40,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.venue['name']?.toString().toUpperCase() ?? 'VENUE',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        color: Colors.black,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.package.toUpperCase(),
                      style: TextStyle(
                        color: LunaraTheme.electricViolet,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.totalPrice != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'TOTAL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.grey,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      widget.totalPrice!,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 28),
          Divider(color: Colors.grey[100], height: 1),
          const SizedBox(height: 28),
          _summaryRow('DATE', widget.date),
          if (widget.table != null) ...[
            const SizedBox(height: 16),
            _summaryRow('TABLE', widget.table!),
          ],
          if (widget.time != null) ...[
            const SizedBox(height: 16),
            _summaryRow('TIME', widget.time!),
          ],
          if (widget.guests != null) ...[
            const SizedBox(height: 16),
            _summaryRow('GUESTS', widget.guests!),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildWarningSection() {
    final bool isSafetyDeposit = widget.package == 'Party Plan Safety Deposit';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isSafetyDeposit
            ? LunaraTheme.electricViolet.withValues(alpha: 0.05)
            : Colors.amber.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSafetyDeposit
              ? LunaraTheme.electricViolet.withValues(alpha: 0.15)
              : Colors.amber.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isSafetyDeposit
                ? Icons.verified_user_outlined
                : Icons.info_outline_rounded,
            color: isSafetyDeposit
                ? LunaraTheme.electricViolet
                : Colors.amber[700],
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              isSafetyDeposit
                  ? 'This safety deposit of ₹99 per head is refundable. Both parties must pay within 30 minutes. Refund will execute 3 hours after party time once both check in successfully (geolocation match). 2 no-show violations will restrict your profile for life.'
                  : 'Booking charges are non-refundable. Please review all details before confirming payment.',
              style: TextStyle(
                color: isSafetyDeposit
                    ? LunaraTheme.electricViolet
                    : Colors.amber[900],
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: Row(
        children: [
          if (widget.showSplitBill) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SplitPaymentScreen(),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  side: BorderSide(color: Colors.grey[200]!),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'SPLIT BILL',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: LunaraActionButton(
              text: (widget.totalPrice?.toLowerCase().contains('free') == true ||
                      widget.totalPrice == '₹0' ||
                      widget.totalPrice == '0')
                  ? 'CONFIRM FREE BOOKING'
                  : 'PAY NOW',
              onPressed: () => _handlePayment(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePayment(BuildContext context) async {
    int amountInPaise = 0;
    if (widget.totalPrice != null) {
      final cleanPrice = widget.totalPrice!.replaceAll(RegExp(r'[^\d]'), '');
      final parsed = int.tryParse(cleanPrice);
      if (parsed != null) {
        amountInPaise = parsed * 100;
      }
    }
    if (amountInPaise == 0 && widget.razorpayAmount != null && widget.razorpayAmount! > 0) {
      amountInPaise = widget.razorpayAmount!;
    }

    bool isFree = amountInPaise == 0 ||
        (widget.totalPrice != null &&
            (widget.totalPrice!.toLowerCase().contains('free') ||
                widget.totalPrice!.replaceAll(RegExp(r'[^\d]'), '') == '0'));

    if (isFree) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: LunaraTheme.premiumShadow,
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: LunaraTheme.electricViolet,
                  strokeWidth: 3,
                ),
                SizedBox(height: 24),
                Text(
                  'PROCESSING',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      Future.delayed(const Duration(milliseconds: 500), () async {
        if (!context.mounted) return;
        if (widget.bookingId != null && widget.bookingId!.isNotEmpty) {
          await ApiService.payNowBooking(widget.bookingId!);
        }
        if (widget.onRazorpayPaymentSuccess != null) {
          await widget.onRazorpayPaymentSuccess!('free_booking', 'free_signature');
        } else if (widget.onPaymentSuccess != null) {
          await widget.onPaymentSuccess!();
        }
        if (!context.mounted) return;
        Navigator.pop(context); // Close processing dialog
        final isSolo = (widget.guests?.trim() == '1' ||
            widget.guests?.trim() == '1 Guest' ||
            widget.package.toLowerCase().contains('solo'));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DigitalTicketScreen(
              venue: widget.venue,
              date: widget.date,
              package: widget.package,
              time: widget.time,
              table: widget.table ?? (isSolo ? 'Solo Entry' : null),
              guests: isSolo ? '1' : widget.guests,
              totalPrice: 'FREE (₹0)',
              ticketId: widget.bookingId ?? 'FREE_TICKET',
              user: ApiService.cachedCurrentUser,
              booking: {
                'id': widget.bookingId,
                'bookingId': widget.bookingId,
                'venue': widget.venue,
                'venueId': widget.venue['id'],
                'isSolo': isSolo,
                'goingMode': isSolo ? 'solo' : 'venue_booking',
                'bookingType': isSolo ? 'solo' : 'venue_booking',
                'category': isSolo ? 'solo' : 'venue_booking',
                'totalAmount': 0,
                'paymentStatus': 'paid',
                'paymentMethod': 'Complimentary',
                'status': 'CONFIRMED',
                'tablePackage': widget.table ?? widget.package,
                'numberOfGuests': isSolo ? 1 : widget.guests,
                'bookingDate': widget.date,
                'startTime': widget.time,
                'user': ApiService.cachedCurrentUser,
              },
            ),
          ),
        );
      });
      return;
    }

    final double itemPrice = amountInPaise / 100.0;

    final bool? sheetSuccess = await SmartCheckoutSheet.show(
      context: context,
      title: widget.venue['name']?.toString() ?? 'Lunara Booking',
      subtitle: widget.package,
      itemPrice: itemPrice,
      onWalletPayment: () async {
        if (widget.onCustomWalletPayment != null) {
          final success = await widget.onCustomWalletPayment!();
          return success;
        }

        final isSolo = (widget.guests?.trim() == '1' ||
            widget.guests?.trim() == '1 Guest' ||
            widget.package.toLowerCase().contains('solo'));
        final res = await ApiService.payWithWallet(
          amount: itemPrice,
          bookingId: widget.bookingId,
          planId: widget.bookingId,
          paymentType: isSolo ? 'solo_booking' : 'venue_booking',
        );
        if (res != null && res['success'] == true) {
          final transactionId = res['data']?['transactionId']?.toString() ?? 'wallet';
          if (widget.bookingId != null && widget.bookingId!.isNotEmpty) {
            await ApiService.payNowBooking(
              widget.bookingId!,
              paymentMethod: 'WALLET',
              transactionId: transactionId,
              razorpayPaymentId: 'wallet_$transactionId',
            );
          }
          if (widget.onRazorpayPaymentSuccess != null) {
            await widget.onRazorpayPaymentSuccess!(
              'wallet_$transactionId',
              'mock_signature',
            );
          } else if (widget.onPaymentSuccess != null) {
            await widget.onPaymentSuccess!();
          }
          return true;
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
        if (widget.onCustomDirectPayment != null) {
          await widget.onCustomDirectPayment!();
          return;
        }
        _executeDirectRazorpay(amountInPaise);
      },
      onHybridPayment: (shortfallAmount) async {
        if (widget.onCustomHybridPayment != null) {
          await widget.onCustomHybridPayment!(shortfallAmount);
          return;
        }
        final orderData = await ApiService.createWalletRechargeOrder(shortfallAmount);
        if (orderData != null) {
          final String orderId = orderData['orderId'] ?? orderData['id'] ?? '';
          final options = {
            'key': orderData['keyId'] ?? widget.razorpayKeyId ?? 'rzp_test_T1rwVokR7tFger',
            'amount': (shortfallAmount * 100).toInt(),
            'name': 'Lunara Shortfall',
            'description': 'Recharge ₹${shortfallAmount.toStringAsFixed(0)} for ${widget.package}',
            'order_id': orderId,
            'theme': {'color': '#7F00FF'},
          };
          _razorpay.open(options);
        }
      },
    );

    if (sheetSuccess == true && mounted) {
      TopNotificationBanner.show(
        title: 'Booking Confirmed! 🎉',
        body: 'Your payment via Smart Wallet at ${widget.venue['name'] ?? 'Venue'} is confirmed. Digital ticket generated!',
        data: {'bookingId': widget.bookingId},
      );
      if (widget.package == 'Party Plan Safety Deposit') {
        Navigator.pop(context);
      } else if (widget.ticketScreenBuilder != null) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: widget.ticketScreenBuilder!),
          (route) => route.isFirst,
        );
      } else {
        final isSolo = (widget.guests?.trim() == '1' ||
            widget.guests?.trim() == '1 Guest' ||
            widget.package.toLowerCase().contains('solo'));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DigitalTicketScreen(
              venue: widget.venue,
              date: widget.date,
              package: widget.package,
              time: widget.time,
              table: widget.table ?? (isSolo ? 'Solo Entry' : null),
              guests: isSolo ? '1' : widget.guests,
              totalPrice: widget.totalPrice,
              ticketId: widget.bookingId ?? widget.razorpayOrderId ?? 'TICKET',
              user: ApiService.cachedCurrentUser,
              booking: {
                'id': widget.bookingId,
                'bookingId': widget.bookingId,
                'venue': widget.venue,
                'venueId': widget.venue['id'],
                'isSolo': isSolo,
                'goingMode': isSolo ? 'solo' : 'venue_booking',
                'bookingType': isSolo ? 'solo' : 'venue_booking',
                'category': isSolo ? 'solo' : 'venue_booking',
                'totalAmount': widget.totalPrice,
                'paymentStatus': 'paid',
                'paymentMethod': 'Lunara Wallet',
                'status': 'CONFIRMED',
                'tablePackage': widget.table ?? widget.package,
                'numberOfGuests': isSolo ? 1 : widget.guests,
                'bookingDate': widget.date,
                'startTime': widget.time,
                'user': ApiService.cachedCurrentUser,
              },
            ),
          ),
        );
      }
    }
  }

  void _executeDirectRazorpay(int amountInPaise) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: LunaraTheme.premiumShadow,
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: LunaraTheme.electricViolet,
                strokeWidth: 3,
              ),
              SizedBox(height: 24),
              Text(
                'PROCESSING',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    var options = {
      'key': widget.razorpayKeyId ?? 'rzp_test_T1rwVokR7tFger',
      'amount': amountInPaise,
      'name': 'Lunara',
      'description': widget.package,
      'prefill': {
        'contact': widget.mobileNumber ?? '8888888888',
        'email': 'test@razorpay.com'
      },
      'theme': {'color': '#7F00FF'},
    };

    if (widget.razorpayOrderId != null &&
        widget.razorpayOrderId!.isNotEmpty &&
        !widget.razorpayOrderId!.startsWith('mock_') &&
        !widget.razorpayOrderId!.startsWith('order_mock_') &&
        !widget.razorpayOrderId!.contains('mock')) {
      options['order_id'] = widget.razorpayOrderId!;
    }

    bool razorpayOpened = false;
    try {
      _razorpay.open(options);
      razorpayOpened = true;
      _isProcessingDialogOpen = true;
    } catch (e) {
      debugPrint(
        'Error opening Razorpay, falling back to simulated payment: $e',
      );
    }

    if (!razorpayOpened) {
      // Simulated payment for fallback
      Future.delayed(const Duration(seconds: 2), () async {
        if (!context.mounted) return;

        if (widget.bookingId != null && widget.bookingId!.isNotEmpty) {
          await ApiService.payNowBooking(
            widget.bookingId!,
            paymentMethod: 'CARD',
            razorpayPaymentId: 'mock_payment_${DateTime.now().millisecondsSinceEpoch}',
            razorpaySignature: 'mock_signature',
          );
        }

        if (widget.onRazorpayPaymentSuccess != null) {
          await widget.onRazorpayPaymentSuccess!(
            'mock_payment',
            'mock_signature',
          );
        } else if (widget.onPaymentSuccess != null) {
          await widget.onPaymentSuccess!();
        }

        if (!context.mounted) return;
        Navigator.pop(context); // Close dialog
        if (widget.package == 'Party Plan Safety Deposit') {
          Navigator.pop(context);
        } else if (widget.ticketScreenBuilder != null) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: widget.ticketScreenBuilder!),
            (route) => route.isFirst,
          );
        } else {
          final isSolo = (widget.guests?.trim() == '1' ||
              widget.guests?.trim() == '1 Guest' ||
              widget.package.toLowerCase().contains('solo'));
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => DigitalTicketScreen(
                venue: widget.venue,
                date: widget.date,
                package: widget.package,
                time: widget.time,
                table: widget.table ?? (isSolo ? 'Solo Entry' : null),
                guests: isSolo ? '1' : widget.guests,
                totalPrice: widget.totalPrice,
                ticketId: widget.bookingId ?? widget.razorpayOrderId ?? 'TICKET',
                user: ApiService.cachedCurrentUser,
                booking: {
                  'id': widget.bookingId,
                  'bookingId': widget.bookingId,
                  'venue': widget.venue,
                  'venueId': widget.venue['id'],
                  'isSolo': isSolo,
                  'goingMode': isSolo ? 'solo' : 'venue_booking',
                  'bookingType': isSolo ? 'solo' : 'venue_booking',
                  'category': isSolo ? 'solo' : 'venue_booking',
                  'totalAmount': widget.totalPrice,
                  'paymentStatus': 'paid',
                  'paymentMethod': 'UPI / Net Banking',
                  'status': 'CONFIRMED',
                  'tablePackage': widget.table ?? widget.package,
                  'numberOfGuests': isSolo ? 1 : widget.guests,
                  'bookingDate': widget.date,
                  'startTime': widget.time,
                  'user': ApiService.cachedCurrentUser,
                },
              ),
            ),
          );
        }
      });
    }
  }
}
