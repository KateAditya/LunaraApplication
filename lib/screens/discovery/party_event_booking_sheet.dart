import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/action_button.dart';
import '../../widgets/smart_checkout_sheet.dart';
import 'digital_ticket_screen.dart';

class PartyEventBookingSheet extends StatefulWidget {
  final Map<String, dynamic> event;

  const PartyEventBookingSheet({super.key, required this.event});

  @override
  State<PartyEventBookingSheet> createState() => _PartyEventBookingSheetState();
}

class _PartyEventBookingSheetState extends State<PartyEventBookingSheet> {
  int _quantity = 1;
  bool _isProcessing = false;

  late Razorpay _razorpay;
  String? _pendingBookingId;
  double? _pendingTotalPrice;
  bool _isHybridFlow = false;

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

  void _handleRazorpaySuccess(PaymentSuccessResponse response) async {
    if (_isHybridFlow) {
      _isHybridFlow = false;
      // Hybrid shortfall recharge completed, now execute wallet payment
      if (_pendingBookingId != null && _pendingTotalPrice != null) {
        final walletRes = await ApiService.payWithWallet(
          amount: _pendingTotalPrice!,
          bookingId: _pendingBookingId!,
          paymentType: 'party_event_booking',
        );
        if (walletRes != null && walletRes['success'] == true) {
          final txId = walletRes['data']?['transactionId']?.toString() ?? 'wallet';
          final confirmRes = await ApiService.payNowBooking(
            _pendingBookingId!,
            paymentMethod: 'WALLET',
            transactionId: txId,
          );
          if (confirmRes != null && mounted) {
            _navigateToTicket(confirmRes['ticketCode'] ?? '', _pendingTotalPrice!);
            return;
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recharge succeeded. Please complete booking with wallet.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return;
    }

    if (_pendingBookingId == null) return;
    try {
      final payRes = await ApiService.payNowBooking(
        _pendingBookingId!,
        paymentMethod: 'CARD',
        razorpayOrderId: response.orderId,
        razorpayPaymentId: response.paymentId,
        razorpaySignature: response.signature,
      );

      if (mounted) {
        if (payRes != null) {
          _navigateToTicket(
            payRes['ticketCode'] ?? '',
            _pendingTotalPrice ?? 0.0,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment verification failed. Please check your bookings.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error confirming booking: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _handleRazorpayError(PaymentFailureResponse response) {
    _isHybridFlow = false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment Failed: ${response.message ?? "Transaction Cancelled"}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('External Wallet: ${response.walletName}'),
          backgroundColor: Colors.blueAccent,
        ),
      );
    }
  }

  void _navigateToTicket(String ticketCode, double totalPrice) {
    if (!mounted) return;
    Navigator.pop(context); // Close bottom sheet

    final venueMap = widget.event['venueMap'] ?? widget.event['venue'];
    final eventTitle = widget.event['title']?.toString().trim().isNotEmpty == true
        ? widget.event['title'].toString()
        : widget.event['subject']?.toString().trim().isNotEmpty == true
            ? widget.event['subject'].toString()
            : null;
    final bannerUrl = widget.event['bannerImageUrl']?.toString().trim().isNotEmpty == true
        ? widget.event['bannerImageUrl'].toString()
        : widget.event['imagePath']?.toString().trim().isNotEmpty == true
            ? widget.event['imagePath'].toString()
            : widget.event['image']?.toString().trim().isNotEmpty == true
                ? widget.event['image'].toString()
                : null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DigitalTicketScreen(
          venue: venueMap,
          date: widget.event['date'],
          package: 'Party Ticket',
          time: widget.event['time'] ?? '8:00 PM',
          guests: '$_quantity GUESTS',
          totalPrice: totalPrice == 0 ? '0' : totalPrice.toStringAsFixed(2),
          ticketId: ticketCode,
          status: 'CONFIRMED',
          booking: widget.event,
          bannerImageUrl: bannerUrl,
          eventTitle: eventTitle,
          isUpcomingNight: true,
        ),
      ),
    );
  }

  void _processBooking() async {
    final eventId = widget.event['eventId'] ?? widget.event['id'];
    final rawPrice = widget.event['entryPrice'];
    final double entryPrice = rawPrice is num
        ? rawPrice.toDouble()
        : (double.tryParse(rawPrice?.toString() ?? '0') ?? 0.0);
    final double totalPrice = entryPrice * _quantity;

    if (entryPrice == 0) {
      // Free Event Direct Flow
      setState(() => _isProcessing = true);
      final bookingRes = await ApiService.createPartyBooking(
        partyEventId: eventId,
        quantity: _quantity,
      );
      setState(() => _isProcessing = false);

      if (bookingRes != null && bookingRes['success'] == true) {
        final ticketCode = bookingRes['data']?['ticketCode'] ?? 
            bookingRes['ticket']?['ticketCode'] ?? 
            '';
        _navigateToTicket(ticketCode, 0.0);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(bookingRes?['message'] ?? 'Failed to book event.')),
          );
        }
      }
      return;
    }

    // Paid Event Flow: Open Smart Checkout Sheet (Wallet / Razorpay / Hybrid)
    final parentContext = context;
    final eventTitle = widget.event['title'] ?? 'Party Event';

    SmartCheckoutSheet.show(
      context: parentContext,
      title: eventTitle,
      subtitle: '$_quantity x Ticket (${widget.event['venue'] ?? 'Event'})',
      itemPrice: totalPrice,
      onWalletPayment: () async {
        final bookingRes = await ApiService.createPartyBooking(
          partyEventId: eventId,
          quantity: _quantity,
        );

        if (bookingRes == null || bookingRes['success'] != true) {
          if (parentContext.mounted) {
            ScaffoldMessenger.of(parentContext).showSnackBar(
              SnackBar(
                content: Text(bookingRes?['message'] ?? 'Failed to initialize booking order.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return false;
        }

        final bookingId = bookingRes['data']?['id'] ?? bookingRes['id'];
        _pendingBookingId = bookingId;
        _pendingTotalPrice = totalPrice;

        final walletRes = await ApiService.payWithWallet(
          amount: totalPrice,
          bookingId: bookingId,
          paymentType: 'party_event_booking',
        );

        if (walletRes != null && walletRes['success'] == true) {
          final transactionId = walletRes['data']?['transactionId']?.toString() ?? 'wallet';
          final confirmRes = await ApiService.payNowBooking(
            bookingId,
            paymentMethod: 'WALLET',
            transactionId: transactionId,
          );

          if (confirmRes != null && parentContext.mounted) {
            ScaffoldMessenger.of(parentContext).showSnackBar(
              const SnackBar(
                content: Text('Payment Successful via Smart Wallet! 🎫'),
                backgroundColor: Color(0xFF10B981),
              ),
            );
            _navigateToTicket(confirmRes['ticketCode'] ?? '', totalPrice);
            return true;
          }
        }

        if (parentContext.mounted) {
          ScaffoldMessenger.of(parentContext).showSnackBar(
            SnackBar(
              content: Text(walletRes?['message'] ?? 'Wallet payment failed'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return false;
      },
      onDirectPayment: () async {
        final bookingRes = await ApiService.createPartyBooking(
          partyEventId: eventId,
          quantity: _quantity,
        );

        if (bookingRes == null || bookingRes['success'] != true) {
          if (parentContext.mounted) {
            ScaffoldMessenger.of(parentContext).showSnackBar(
              SnackBar(
                content: Text(bookingRes?['message'] ?? 'Failed to initialize booking.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }

        final bookingId = bookingRes['data']?['id'] ?? bookingRes['id'];
        final razorpayOrderId = bookingRes['razorpayOrderId'] ?? '';
        final razorpayKeyId = bookingRes['razorpayKeyId'] ?? 'rzp_test_123';

        _pendingBookingId = bookingId;
        _pendingTotalPrice = totalPrice;
        _isHybridFlow = false;

        final options = {
          'key': razorpayKeyId,
          'amount': (totalPrice * 100).toInt(),
          'name': 'Lunara',
          'description': 'Booking for $eventTitle ($_quantity Tickets)',
          'order_id': razorpayOrderId.isNotEmpty ? razorpayOrderId : null,
          'timeout': 300,
          'theme': {'color': '#7c3aed'},
        };

        try {
          _razorpay.open(options);
        } catch (rzpErr) {
          debugPrint('Razorpay open error: $rzpErr');
        }
      },
      onHybridPayment: (shortfallAmount) async {
        final bookingRes = await ApiService.createPartyBooking(
          partyEventId: eventId,
          quantity: _quantity,
        );

        if (bookingRes == null || bookingRes['success'] != true) {
          if (parentContext.mounted) {
            ScaffoldMessenger.of(parentContext).showSnackBar(
              SnackBar(
                content: Text(bookingRes?['message'] ?? 'Failed to initialize booking.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }

        final bookingId = bookingRes['data']?['id'] ?? bookingRes['id'];
        _pendingBookingId = bookingId;
        _pendingTotalPrice = totalPrice;
        _isHybridFlow = true;

        final orderData = await ApiService.createWalletRechargeOrder(shortfallAmount);
        if (orderData != null) {
          final String orderId = orderData['orderId'] ?? orderData['id'] ?? '';
          final options = {
            'key': orderData['keyId'] ?? 'rzp_test_123',
            'amount': (shortfallAmount * 100).toInt(),
            'name': 'Lunara Wallet Recharge',
            'description': 'Shortfall ₹${shortfallAmount.toStringAsFixed(0)} for $eventTitle',
            'order_id': orderId.isNotEmpty ? orderId : null,
            'timeout': 300,
            'theme': {'color': '#7c3aed'},
          };
          try {
            _razorpay.open(options);
          } catch (e) {
            debugPrint('Hybrid Razorpay error: $e');
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.event['title'] ?? 'Party Event';
    final rawPrice = widget.event['entryPrice'];
    final double entryPrice = rawPrice is num
        ? rawPrice.toDouble()
        : (double.tryParse(rawPrice?.toString() ?? '0') ?? 0.0);
    final rawSeats = widget.event['remainingSeats'];
    final int remainingSeats = rawSeats is num
        ? rawSeats.toInt()
        : (int.tryParse(rawSeats?.toString() ?? '') ?? 999999);
    final isUnlimited = widget.event['isUnlimited'] == true;

    final maxSeats = isUnlimited ? 10 : (remainingSeats > 10 ? 10 : remainingSeats);

    return Container(
      decoration: BoxDecoration(
        color: LunaraTheme.darkBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Book $title',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Number of Tickets',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  if (!isUnlimited && remainingSeats < 999999)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        remainingSeats <= 0 
                            ? 'Sold Out' 
                            : '($remainingSeats ${remainingSeats == 1 ? "seat" : "seats"} left)',
                        style: TextStyle(
                          color: remainingSeats <= 3 ? Colors.amber : Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.remove_circle_outline, 
                      color: _quantity > 1 ? Colors.white : Colors.white24,
                    ),
                    onPressed: _quantity > 1
                        ? () => setState(() => _quantity--)
                        : null,
                  ),
                  Text(
                    '$_quantity',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.add_circle_outline, 
                      color: _quantity < maxSeats ? Colors.white : Colors.white24,
                    ),
                    onPressed: () {
                      if (_quantity < maxSeats) {
                        setState(() => _quantity++);
                      } else {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isUnlimited 
                                  ? 'Maximum 10 tickets per booking.' 
                                  : 'Only $maxSeats tickets available for this event.',
                            ),
                            duration: const Duration(seconds: 2),
                            backgroundColor: Colors.amber[900],
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Amount',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                entryPrice == 0 ? 'FREE' : '₹${(entryPrice * _quantity).toStringAsFixed(2)}',
                style: const TextStyle(color: LunaraTheme.electricViolet, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 32),
          LunaraActionButton(
            text: _isProcessing 
                ? 'PROCESSING...' 
                : (entryPrice == 0 ? 'CONFIRM BOOKING' : 'PROCEED TO PAY'),
            onPressed: _isProcessing ? () {} : _processBooking,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
