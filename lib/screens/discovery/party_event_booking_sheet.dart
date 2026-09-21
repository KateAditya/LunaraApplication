import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/action_button.dart';
import '../../widgets/smart_checkout_sheet.dart';
import '../../widgets/dialogs/time_lock_blocked_dialog.dart';
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
  bool _isDetailsLoading = true;
  late Map<String, dynamic> _liveEvent;
  String? _inlineWarning;

  late Razorpay _razorpay;
  String? _pendingBookingId;
  double? _pendingTotalPrice;
  bool _isHybridFlow = false;

  @override
  void initState() {
    super.initState();
    _liveEvent = Map<String, dynamic>.from(widget.event);
    _fetchFreshEventDetails();
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

  Future<void> _fetchFreshEventDetails() async {
    final eventId = widget.event['eventId'] ?? widget.event['id'];
    if (eventId == null) {
      if (mounted) setState(() => _isDetailsLoading = false);
      return;
    }
    try {
      final res = await ApiService.get('/api/ads/active?type=Party');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        if (data is Map && data['data'] is List) {
          final List ads = data['data'];
          final matching = ads.firstWhere(
            (a) => a['id']?.toString() == eventId.toString(),
            orElse: () => null,
          );
          if (matching != null && mounted) {
            final isUnlimited = matching['isUnlimited'] == true;
            final int seatLimit = matching['seatLimit'] is num
                ? (matching['seatLimit'] as num).toInt()
                : (int.tryParse(matching['seatLimit']?.toString() ?? '0') ?? 0);
            final int filledSeats = matching['filledSeats'] is num
                ? (matching['filledSeats'] as num).toInt()
                : (int.tryParse(matching['filledSeats']?.toString() ?? '0') ?? 0);
            final dynamic rawRem = matching['remainingSeats'];
            final int rem = rawRem is num
                ? rawRem.toInt()
                : (isUnlimited ? 999999 : (seatLimit - filledSeats));

            setState(() {
              _liveEvent = {
                ..._liveEvent,
                ...Map<String, dynamic>.from(matching),
                'remainingSeats': rem > 0 ? rem : 0,
                'entryPrice': matching['entryPrice'],
                'isUnlimited': isUnlimited,
                'seatLimit': seatLimit,
                'filledSeats': filledSeats,
              };
              _isDetailsLoading = false;
            });
            return;
          }
        }
      }
      if (mounted) setState(() => _isDetailsLoading = false);
    } catch (e) {
      debugPrint('Error fetching fresh event details in booking sheet: $e');
      if (mounted) setState(() => _isDetailsLoading = false);
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
    ApiService.clearBookingCache();
    ApiService.notifyFeedNeedsRefresh();
    ApiService.planPostedNotifier.value++;
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

  String? get _eventDate {
    final raw = _liveEvent['eventDate'] ??
        widget.event['eventDate'] ??
        _liveEvent['date'] ??
        widget.event['date'] ??
        _liveEvent['rawDate'] ??
        widget.event['rawDate'] ??
        _liveEvent['fromDate'] ??
        widget.event['fromDate'];
    if (raw == null) return null;
    final clean = raw.toString().trim();
    if (clean.isEmpty) return null;
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(clean);
    if (match != null) return match.group(1);
    try {
      final parsed = DateTime.parse(clean);
      return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    } catch (_) {}
    return clean;
  }

  String? get _eventTime {
    final raw = _liveEvent['time'] ??
        widget.event['time'] ??
        _liveEvent['startTime'] ??
        widget.event['startTime'];
    if (raw == null) return null;
    return raw.toString().trim();
  }

  void _processBooking() async {
    final eventId = _liveEvent['eventId'] ?? widget.event['eventId'] ?? _liveEvent['id'] ?? widget.event['id'];
    final rawPrice = _liveEvent['entryPrice'] ?? widget.event['entryPrice'];
    final double entryPrice = rawPrice is num
        ? rawPrice.toDouble()
        : (double.tryParse(rawPrice?.toString() ?? '0') ?? 0.0);
    final double totalPrice = entryPrice * _quantity;

    if (entryPrice == 0) {
      // Free Event Direct Flow
      setState(() {
        _isProcessing = true;
        _inlineWarning = null;
      });
      final bookingRes = await ApiService.createPartyBooking(
        partyEventId: eventId.toString(),
        quantity: _quantity,
        eventDate: _eventDate,
        time: _eventTime,
      );
      setState(() => _isProcessing = false);

      if (bookingRes != null && bookingRes['success'] == true) {
        final ticketCode = bookingRes['data']?['ticketCode'] ?? 
            bookingRes['ticket']?['ticketCode'] ?? 
            '';
        _navigateToTicket(ticketCode, 0.0);
      } else {
        if (mounted) {
          final msg = bookingRes?['message']?.toString() ?? 'Failed to book event.';
          final isTimeLock = TimeLockBlockedDialog.isConflictError(msg) ||
              bookingRes?['timeLock'] != null ||
              bookingRes?['reason'] == 'FOUR_HOUR_TIME_LOCK' ||
              bookingRes?['code'] == 'FOUR_HOUR_TIME_LOCK' ||
              bookingRes?['code'] == 'USER_ALREADY_BOOKED' ||
              bookingRes?['code'] == 'USER_ALREADY_HAS_PLAN';

          if (isTimeLock) {
            TimeLockBlockedDialog.show(
              context,
              errorData: bookingRes ?? {'message': msg},
            );
          } else {
            setState(() {
              _inlineWarning = msg;
            });
          }
        }
      }
      return;
    }

    final parentContext = context;
    final eventTitle = _liveEvent['title'] ?? widget.event['title'] ?? 'Party Event';
    
    String venueName = 'Favela | ONYX, Pune';
    final rawVenue = _liveEvent['venue'] ?? widget.event['venue'];
    if (rawVenue is Map) {
      venueName = (rawVenue['name'] ?? rawVenue['title'] ?? rawVenue['venueName'] ?? 'Event').toString();
    } else if (rawVenue != null) {
      final str = rawVenue.toString();
      if (!str.startsWith('{')) {
        venueName = str;
      } else {
        venueName = (_liveEvent['venueName'] ?? widget.event['venueName'] ?? 'Favela | ONYX, Pune').toString();
      }
    }
    String? createdTicketCode;

    final bool? sheetSuccess = await SmartCheckoutSheet.show(
      context: parentContext,
      title: eventTitle,
      subtitle: '$_quantity x Ticket ($venueName)',
      itemPrice: totalPrice,
      onWalletPayment: () async {
        final bookingRes = await ApiService.createPartyBooking(
          partyEventId: eventId.toString(),
          quantity: _quantity,
          eventDate: _eventDate,
          time: _eventTime,
        );

        if (bookingRes == null || bookingRes['success'] != true) {
          if (parentContext.mounted) {
            final msg = bookingRes?['message']?.toString() ?? 'Failed to initialize booking order.';
            final isTimeLock = TimeLockBlockedDialog.isConflictError(msg) ||
                bookingRes?['timeLock'] != null ||
                bookingRes?['reason'] == 'FOUR_HOUR_TIME_LOCK' ||
                bookingRes?['code'] == 'FOUR_HOUR_TIME_LOCK' ||
                bookingRes?['code'] == 'USER_ALREADY_BOOKED' ||
                bookingRes?['code'] == 'USER_ALREADY_HAS_PLAN';

            if (isTimeLock) {
              TimeLockBlockedDialog.show(
                parentContext,
                errorData: bookingRes ?? {'message': msg},
              );
            } else {
              ScaffoldMessenger.of(parentContext).showSnackBar(
                SnackBar(
                  content: Text(msg),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }
          return false;
        }

        final bookingId = (bookingRes['data']?['id'] ?? bookingRes['id'])?.toString();
        if (bookingId == null || bookingId.isEmpty) {
          return false;
        }
        _pendingBookingId = bookingId;
        _pendingTotalPrice = totalPrice;

        final walletRes = await ApiService.payWithWallet(
          amount: totalPrice,
          bookingId: bookingId,
          paymentType: 'party_event_booking',
        );

        if (walletRes != null && walletRes['success'] == true) {
          final transactionId = walletRes['data']?['transactionId']?.toString() ??
              walletRes['data']?['txnId']?.toString() ??
              'wallet_${DateTime.now().millisecondsSinceEpoch}';
          final confirmRes = await ApiService.payNowBooking(
            bookingId,
            paymentMethod: 'WALLET',
            transactionId: transactionId,
          );

          if (confirmRes != null) {
            createdTicketCode = confirmRes['ticketCode']?.toString() ??
                confirmRes['data']?['ticketCode']?.toString() ??
                confirmRes['ticket']?['ticketCode']?.toString() ??
                confirmRes['id']?.toString() ??
                '';
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
          partyEventId: eventId.toString(),
          quantity: _quantity,
          eventDate: _eventDate,
          time: _eventTime,
        );

        if (bookingRes == null || bookingRes['success'] != true) {
          if (parentContext.mounted) {
            final msg = bookingRes?['message']?.toString() ?? 'Failed to initialize booking.';
            final isTimeLock = TimeLockBlockedDialog.isConflictError(msg) ||
                bookingRes?['timeLock'] != null ||
                bookingRes?['reason'] == 'FOUR_HOUR_TIME_LOCK' ||
                bookingRes?['code'] == 'FOUR_HOUR_TIME_LOCK' ||
                bookingRes?['code'] == 'USER_ALREADY_BOOKED' ||
                bookingRes?['code'] == 'USER_ALREADY_HAS_PLAN';

            if (isTimeLock) {
              TimeLockBlockedDialog.show(
                parentContext,
                errorData: bookingRes ?? {'message': msg},
              );
            } else {
              ScaffoldMessenger.of(parentContext).showSnackBar(
                SnackBar(
                  content: Text(msg),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }
          return false;
        }

        final bookingId = (bookingRes['data']?['id'] ?? bookingRes['id'])?.toString();
        if (bookingId == null || bookingId.isEmpty) {
          return false;
        }
        final razorpayOrderId = (bookingRes['razorpayOrderId'] ?? '').toString();
        final razorpayKeyId = (bookingRes['razorpayKeyId'] ?? 'rzp_test_123').toString();

        _pendingBookingId = bookingId;
        _pendingTotalPrice = totalPrice;
        _isHybridFlow = false;

        final isMock = kIsWeb ||
            razorpayOrderId.isEmpty ||
            razorpayOrderId.startsWith('dummy_order_') ||
            razorpayOrderId.startsWith('order_mock_') ||
            razorpayKeyId == 'rzp_test_123';

        if (isMock) {
          final payRes = await ApiService.payNowBooking(
            bookingId,
            paymentMethod: 'CARD',
            razorpayOrderId: razorpayOrderId.isNotEmpty ? razorpayOrderId : 'dummy_order_$bookingId',
            razorpayPaymentId: 'pay_${DateTime.now().millisecondsSinceEpoch}',
            razorpaySignature: 'mock_signature',
          );
          if (payRes != null && payRes['success'] == true) {
            createdTicketCode = payRes['ticketCode']?.toString() ??
                payRes['data']?['ticketCode']?.toString() ??
                payRes['ticket']?['ticketCode']?.toString() ??
                payRes['id']?.toString() ??
                '';
            return true;
          }
          return false;
        }

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
          return 'gateway_launched';
        } catch (rzpErr) {
          debugPrint('Razorpay open error: $rzpErr');
          final payRes = await ApiService.payNowBooking(
            bookingId,
            paymentMethod: 'CARD',
            razorpayOrderId: razorpayOrderId.isNotEmpty ? razorpayOrderId : 'dummy_order_$bookingId',
            razorpayPaymentId: 'pay_${DateTime.now().millisecondsSinceEpoch}',
            razorpaySignature: 'mock_signature',
          );
          if (payRes != null && payRes['success'] == true) {
            createdTicketCode = payRes['ticketCode']?.toString() ??
                payRes['data']?['ticketCode']?.toString() ??
                payRes['ticket']?['ticketCode']?.toString() ??
                payRes['id']?.toString() ??
                '';
            return true;
          }
          return false;
        }
      },
      onHybridPayment: (shortfallAmount) async {
        final bookingRes = await ApiService.createPartyBooking(
          partyEventId: eventId.toString(),
          quantity: _quantity,
          eventDate: _eventDate,
          time: _eventTime,
        );

        if (bookingRes == null || bookingRes['success'] != true) {
          if (parentContext.mounted) {
            final msg = bookingRes?['message']?.toString() ?? 'Failed to initialize booking.';
            final isTimeLock = TimeLockBlockedDialog.isConflictError(msg) ||
                bookingRes?['timeLock'] != null ||
                bookingRes?['reason'] == 'FOUR_HOUR_TIME_LOCK' ||
                bookingRes?['code'] == 'FOUR_HOUR_TIME_LOCK' ||
                bookingRes?['code'] == 'USER_ALREADY_BOOKED' ||
                bookingRes?['code'] == 'USER_ALREADY_HAS_PLAN';

            if (isTimeLock) {
              TimeLockBlockedDialog.show(
                parentContext,
                errorData: bookingRes ?? {'message': msg},
              );
            } else {
              ScaffoldMessenger.of(parentContext).showSnackBar(
                SnackBar(
                  content: Text(msg),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }
          return false;
        }

        final bookingId = (bookingRes['data']?['id'] ?? bookingRes['id'])?.toString();
        if (bookingId == null || bookingId.isEmpty) {
          return false;
        }
        _pendingBookingId = bookingId;
        _pendingTotalPrice = totalPrice;
        _isHybridFlow = true;

        final isMock = kIsWeb;
        if (isMock) {
          // Recharge mock shortfall and confirm wallet booking
          await ApiService.verifyWalletRecharge(
            amount: shortfallAmount,
            razorpayPaymentId: 'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
            razorpayOrderId: 'order_mock_${DateTime.now().millisecondsSinceEpoch}',
            razorpaySignature: 'mock_signature',
          );
          final walletRes = await ApiService.payWithWallet(
            amount: totalPrice,
            bookingId: bookingId,
            paymentType: 'party_event_booking',
          );
          if (walletRes != null && walletRes['success'] == true) {
            final txId = walletRes['data']?['transactionId']?.toString() ?? 'wallet';
            final confirmRes = await ApiService.payNowBooking(
              bookingId,
              paymentMethod: 'WALLET',
              transactionId: txId,
            );
            if (confirmRes != null) {
              createdTicketCode = confirmRes['ticketCode']?.toString() ?? '';
              return true;
            }
          }
          return false;
        }

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
            return 'gateway_launched';
          } catch (e) {
            debugPrint('Hybrid Razorpay error: $e');
            return false;
          }
        }
        return false;
      },
    );

    if (sheetSuccess == true && parentContext.mounted) {
      ScaffoldMessenger.of(parentContext).showSnackBar(
        const SnackBar(
          content: Text('Payment Successful! 🎫'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      _navigateToTicket(createdTicketCode ?? '', totalPrice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _liveEvent['title'] ?? widget.event['title'] ?? 'Party Event';
    final rawPrice = _liveEvent['entryPrice'] ?? widget.event['entryPrice'];
    final double entryPrice = rawPrice is num
        ? rawPrice.toDouble()
        : (double.tryParse(rawPrice?.toString() ?? '0') ?? 0.0);
    final rawSeats = _liveEvent['remainingSeats'] ?? widget.event['remainingSeats'];
    final int remainingSeats = rawSeats is num
        ? rawSeats.toInt()
        : (int.tryParse(rawSeats?.toString() ?? '') ?? 999999);
    final isUnlimited = (_liveEvent['isUnlimited'] ?? widget.event['isUnlimited']) == true;

    final int maxSeats = isUnlimited ? 100 : (remainingSeats > 0 ? remainingSeats : 0);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Color(0xFF0F172A)),
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
                    style: TextStyle(color: Color(0xFF475569), fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (!isUnlimited && remainingSeats < 999999)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        remainingSeats <= 0 
                            ? 'Sold Out' 
                            : '($remainingSeats ${remainingSeats == 1 ? "seat" : "seats"} left)',
                        style: TextStyle(
                          color: remainingSeats <= 3 ? Colors.amber[800] : const Color(0xFF64748B),
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
                      color: _quantity > 1 ? const Color(0xFF0F172A) : Colors.black26,
                    ),
                    onPressed: _quantity > 1
                        ? () {
                            setState(() {
                              _quantity--;
                              _inlineWarning = null;
                            });
                          }
                        : null,
                  ),
                  Text(
                    '$_quantity',
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.add_circle_outline, 
                      color: (maxSeats > 0 && _quantity < maxSeats) ? const Color(0xFF0F172A) : Colors.black26,
                    ),
                    onPressed: maxSeats <= 0
                        ? null
                        : () {
                            if (_quantity < maxSeats) {
                              setState(() {
                                _quantity++;
                                _inlineWarning = null;
                              });
                            } else {
                              setState(() {
                                _inlineWarning = isUnlimited
                                    ? 'Maximum 100 tickets per transaction.'
                                    : 'All $remainingSeats available seats selected.';
                              });
                            }
                          },
                  ),
                ],
              ),
            ],
          ),
          if (_inlineWarning != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _inlineWarning!,
                      style: TextStyle(
                        color: Colors.amber[900],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Amount',
                style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                entryPrice == 0 ? 'FREE' : '₹${(entryPrice * _quantity).toStringAsFixed(2)}',
                style: const TextStyle(color: LunaraTheme.electricViolet, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 32),
          LunaraActionButton(
            text: _isDetailsLoading
                ? 'CHECKING AVAILABILITY...'
                : (_isProcessing 
                    ? 'PROCESSING...' 
                    : (!isUnlimited && remainingSeats <= 0)
                        ? 'SOLD OUT'
                        : (entryPrice == 0 ? 'CONFIRM BOOKING' : 'PROCEED TO PAY')),
            isLoading: _isDetailsLoading || _isProcessing,
            onPressed: (_isDetailsLoading || _isProcessing || (!isUnlimited && remainingSeats <= 0))
                ? () {} 
                : _processBooking,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
