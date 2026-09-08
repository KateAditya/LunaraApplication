// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../services/google_places_service.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../widgets/lunara_ticket_widget.dart';
import '../../widgets/smart_checkout_sheet.dart';
import '../../widgets/top_notification_banner.dart';
import '../../services/api_service.dart';
import '../../services/lunara_ticket_capture_service.dart';
import '../../utils/lunara_date_formatter.dart';
import '../../dialogs/large_party_cancellation_dialog.dart';

enum _LargePartyPaymentState { loading, paid, awaitingPayment, expired }

class LargePartyTicketScreen extends StatefulWidget {
  final Map<dynamic, dynamic> booking;
  final Map<dynamic, dynamic> venue;
  final bool? isExpired;
  final bool? isCancelled;

  const LargePartyTicketScreen({
    super.key,
    required this.booking,
    required this.venue,
    this.isExpired,
    this.isCancelled,
  });

  @override
  State<LargePartyTicketScreen> createState() => _LargePartyTicketScreenState();
}

class _LargePartyTicketScreenState extends State<LargePartyTicketScreen> {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;

  // Countdown timer to party date
  Timer? _countdownTimer;
  Duration _timeRemaining = Duration.zero;

  // Fresh backend ticket data
  Map<String, dynamic>? _freshHostUser;
  String? _canonicalTicketCode;
  int? _freshTotalParticipants;
  int? _freshMemberCount;
  double? _freshTotalAmount;
  String? _freshPaymentStatus;
  String? _freshPaymentMethod;
  Map<String, dynamic>? _freshVenue;
  DateTime? _freshPartyDate;
  String? _freshStartTime;
  final GlobalKey _ticketKey = GlobalKey();

  // Server-verified payment/expiry state — the single source of truth for
  // whether this screen shows a Pay Now button, an Expired notice, or the ticket.
  _LargePartyPaymentState _paymentState = _LargePartyPaymentState.loading;
  double? _amountDue;
  String? _bookingId;

  Razorpay? _razorpay;
  bool _isPaying = false;

  @override
  void initState() {
    super.initState();
    _paymentState = _computeInitialStateFromLocalMap();
    if (!kIsWeb) {
      try {
        _razorpay = Razorpay();
        _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
        _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
        _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
      } catch (e) {
        debugPrint('Razorpay init error: $e');
      }
    }
    _initLocation();
    _initCountdown();
    // Pre-populate fresh fields from widget data synchronously so the first
    // frame is already complete — no waiting for the network round-trip.
    _prefillFromWidget();
    _fetchTicketData();

    ApiService.addSocketListener('group_party_payment_success', _onSocketUpdate);
    ApiService.addSocketListener('group_party_status_update', _onSocketUpdate);
    ApiService.addSocketListener('large_party_status_update', _onSocketUpdate);
    ApiService.addSocketListener('large_party_cancellation_approved', _onSocketUpdate);
    ApiService.addSocketListener('large_party_cancellation_rejected', _onSocketUpdate);
    ApiService.addSocketListener('large_party_refund_paid', _onSocketUpdate);
    ApiService.addSocketListener('group_party_cancelled', _onSocketUpdate);
  }

  void _onSocketUpdate(dynamic data) {
    if (!mounted) return;
    _fetchTicketData();
  }

  @override
  void dispose() {
    ApiService.removeSocketListener('group_party_payment_success', _onSocketUpdate);
    ApiService.removeSocketListener('group_party_status_update', _onSocketUpdate);
    ApiService.removeSocketListener('large_party_status_update', _onSocketUpdate);
    ApiService.removeSocketListener('large_party_cancellation_approved', _onSocketUpdate);
    ApiService.removeSocketListener('large_party_cancellation_rejected', _onSocketUpdate);
    ApiService.removeSocketListener('large_party_refund_paid', _onSocketUpdate);
    ApiService.removeSocketListener('group_party_cancelled', _onSocketUpdate);
    _positionStreamSubscription?.cancel();
    _countdownTimer?.cancel();
    if (!kIsWeb) {
      try {
        _razorpay?.clear();
      } catch (e) {
        debugPrint('Razorpay clear error: $e');
      }
    }
    super.dispose();
  }

  bool get _isTicketCancelled {
    if (widget.isCancelled == true) return true;
    final b = widget.booking;
    final status = (b['status'] ?? b['adminApprovalStatus'] ?? '').toString().toLowerCase();
    final paymentStatus = (_freshPaymentStatus ?? b['paymentStatus'] ?? '').toString().toLowerCase();
    return status == 'cancelled' || paymentStatus == 'cancelled' || paymentStatus == 'refunded';
  }

  bool get _isTicketExpired {
    if (_isTicketCancelled) return false;
    if (widget.isExpired == true) return true;
    if (_paymentState == _LargePartyPaymentState.expired) return true;
    final b = widget.booking;
    final status = (b['status'] ?? b['adminApprovalStatus'] ?? '').toString().toLowerCase();
    if (status == 'expired') return true;

    // Check if the event date/time has passed (+ 2 hours duration)
    final bookingDateStr = _freshPartyDate ?? b['bookingDate'] ?? b['partyDate'] ?? b['eventStartAt'];
    final startTimeStr = _freshStartTime ?? b['startTime'] ?? '12:00 AM';
    final DateTime eventStart = _parseEventDateTime(bookingDateStr, startTimeStr);
    final DateTime eventEnd = eventStart.add(const Duration(hours: 2));
    if (DateTime.now().isAfter(eventEnd)) {
      return true;
    }
    return false;
  }

  /// Best-effort guess from whatever the caller passed in, shown only until the
  /// authoritative server fetch in [_fetchTicketData] resolves and overwrites it.
  _LargePartyPaymentState _computeInitialStateFromLocalMap() {
    final localStatus = (widget.booking['adminApprovalStatus'] ?? widget.booking['status'])?.toString().toLowerCase();
    final paymentStatus = (widget.booking['paymentStatus'])?.toString().toLowerCase();
    final totalAmount = double.tryParse((widget.booking['totalAmount'] ?? widget.booking['paymentAmount'] ?? '0').toString()) ?? 0.0;
    if (widget.isExpired == true || localStatus == 'expired') return _LargePartyPaymentState.expired;
    if (paymentStatus == 'paid' ||
        localStatus == 'payment_done' ||
        localStatus == 'confirmed' ||
        localStatus == 'completed' ||
        totalAmount <= 0) {
      return _LargePartyPaymentState.paid;
    }
    // Any other/unknown status: never assume paid — wait for server fetch to confirm
    return _LargePartyPaymentState.awaitingPayment;
  }

  /// Synchronously copies widget.booking data into the "fresh" fields so that
  /// the very first build frame already renders complete data.  The actual
  /// [_fetchTicketData] call will overwrite these with server-verified values
  /// but will only trigger setState if something genuinely changed.
  void _prefillFromWidget() {
    final b = widget.booking;
    if (b['user'] is Map) {
      _freshHostUser = Map<String, dynamic>.from(b['user']);
    } else if (b['host'] is Map) {
      _freshHostUser = Map<String, dynamic>.from(b['host']);
    } else if (b['customer'] is Map) {
      _freshHostUser = Map<String, dynamic>.from(b['customer']);
    }
    if (b['venue'] is Map) {
      _freshVenue = Map<String, dynamic>.from(b['venue']);
    } else if (widget.venue.isNotEmpty) {
      _freshVenue = Map<String, dynamic>.from(widget.venue);
    }
    _freshTotalAmount ??= double.tryParse(
        (b['totalAmount'] ?? b['paymentAmount'] ?? b['depositAmount'] ?? '').toString());
    _freshPaymentStatus ??= b['paymentStatus']?.toString() ?? 'paid';
    _freshPaymentMethod ??= b['paymentMethod']?.toString();
    _canonicalTicketCode ??= b['ticketCode']?.toString() ?? b['ticketId']?.toString();
    _amountDue ??= _freshTotalAmount;

    final rawParticipants = b['totalParticipants'] ?? b['numberOfFriends'] ?? b['numberOfGuests'];
    if (rawParticipants != null && _freshTotalParticipants == null) {
      _freshTotalParticipants = int.tryParse(rawParticipants.toString());
      if (_freshTotalParticipants != null && _freshMemberCount == null) {
        _freshMemberCount = _freshTotalParticipants! > 1 ? _freshTotalParticipants! - 1 : 1;
      }
    }
    final rawDate = b['bookingDate'] ?? b['partyDate'] ?? b['eventStartAt'] ?? b['eventDate'];
    if (rawDate != null && _freshPartyDate == null) {
      _freshPartyDate = DateTime.tryParse(rawDate.toString())?.toLocal();
    }
    final rawTime = b['startTime'] ?? b['time'] ?? b['bookingTime'];
    if (rawTime != null && rawTime.toString().trim().isNotEmpty && _freshStartTime == null) {
      _freshStartTime = _normalizeTimeStr(rawTime.toString());
    }
    if (_freshStartTime == null) {
      if (_freshPartyDate != null && (_freshPartyDate!.hour != 0 || _freshPartyDate!.minute != 0)) {
        if (_freshPartyDate!.hour == 5 && _freshPartyDate!.minute == 30) {
          _freshStartTime = '12:00 AM';
        } else {
          _freshStartTime = DateFormat('hh:mm a').format(_freshPartyDate!);
        }
      } else if (_freshPartyDate != null) {
        _freshStartTime = '12:00 AM';
      }
    }
  }

  String _normalizeTimeStr(String? time) {
    return LunaraDateFormatter.normalizeTimeTo12Hour(time);
  }

  DateTime _parseEventDateTime(dynamic rawDate, dynamic rawTime) {
    return LunaraDateFormatter.parseToLocal(rawDate, explicitTime: rawTime?.toString()) ?? DateTime.now();
  }

  void _initCountdown() {
    final bookingDateStr = _freshPartyDate ?? widget.booking['bookingDate'] ?? widget.booking['partyDate'];
    final startTimeStr = _freshStartTime ?? widget.booking['startTime'] ?? '12:00 AM';
    final DateTime eventStart = _parseEventDateTime(bookingDateStr, startTimeStr);
    final DateTime targetDate = eventStart.add(const Duration(hours: 2));

    void update() {
      if (!mounted) return;
      final remaining = targetDate.difference(DateTime.now());
      setState(() {
        _timeRemaining = remaining.isNegative ? Duration.zero : remaining;
      });
    }

    _countdownTimer?.cancel();
    update();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => update());
  }

  Future<void> _fetchTicketData() async {
    final rawId = widget.booking['bookingId'] ??
        widget.booking['metadata']?['bookingId'] ??
        widget.booking['metadata']?['partyId'] ??
        widget.booking['entityId'] ??
        widget.booking['partyId'] ??
        widget.booking['groupPartyId'] ??
        widget.booking['data']?['partyId'] ??
        widget.booking['data']?['bookingId'] ??
        widget.booking['id'];
    final id = ApiService.cleanBookingId(rawId?.toString() ?? '');
    if (id.isEmpty) return;
    _bookingId = id;

    // Try the large-party Booking record first (ungated — works pre-payment too).
    try {
      final response = await ApiService.get('/api/mobile/bookings/$id');
      if (response.statusCode == 200 && mounted) {
        final mapData = jsonDecode(response.body);
        final booking = mapData is Map ? mapData['data'] : null;
        if (booking is Map) {
          // Compute new values first, then only setState if something changed.
          Map<String, dynamic>? newHostUser;
          if (booking['user'] is Map) {
            newHostUser = Map<String, dynamic>.from(booking['user']);
          } else if (booking['host'] is Map) {
            newHostUser = Map<String, dynamic>.from(booking['host']);
          }

          Map<String, dynamic>? newVenue;
          if (booking['venue'] is Map) newVenue = Map<String, dynamic>.from(booking['venue']);

          final adminAmount = double.tryParse((booking['adminPaymentAmount'] ?? '').toString());
          final totalAmount = double.tryParse((booking['totalAmount'] ?? '').toString());
          final newTotalAmount = (adminAmount != null && adminAmount > 0) ? adminAmount : totalAmount;
          final newPaymentStatus = booking['paymentStatus']?.toString();
          final newTicketCode = booking['ticketCode']?.toString();
          final newAmountDue = newTotalAmount;
          final guestsRaw = booking['numberOfGuests'];
          final newTotalParticipants = guestsRaw != null ? int.tryParse(guestsRaw.toString()) : null;
          final newMemberCount = newTotalParticipants != null && newTotalParticipants > 1 ? newTotalParticipants - 1 : null;

          final rawBookingDate = booking['bookingDate'] ?? booking['partyDate'] ?? booking['eventStartAt'];
          DateTime? newPartyDate;
          if (rawBookingDate != null) {
            newPartyDate = DateTime.tryParse(rawBookingDate.toString())?.toLocal();
          }
          final rawBookingTime = booking['startTime'] ?? booking['bookingTime'] ?? booking['time'];
          String? newStartTime;
          if (rawBookingTime != null && rawBookingTime.toString().trim().isNotEmpty) {
            newStartTime = _normalizeTimeStr(rawBookingTime.toString());
          }

          final adminApprovalStatus = booking['adminApprovalStatus']?.toString().toLowerCase();
          final bookingStatus = booking['status']?.toString().toLowerCase();
          final isFreeBooking = (newTotalAmount == null || newTotalAmount <= 0);
          final isExpired = widget.isExpired == true || adminApprovalStatus == 'expired' || bookingStatus == 'expired';
          final isPaid = !isExpired && (newPaymentStatus == 'paid' ||
                         adminApprovalStatus == 'payment_done' ||
                         (bookingStatus == 'confirmed' && isFreeBooking) ||
                         (bookingStatus == 'completed' && isFreeBooking));
          final newPaymentState = isPaid
              ? _LargePartyPaymentState.paid
              : isExpired
                  ? _LargePartyPaymentState.expired
                  : _LargePartyPaymentState.awaitingPayment;

          // Only rebuild if something actually changed.
          final didChange = newPaymentState != _paymentState ||
              newTicketCode != _canonicalTicketCode ||
              newPaymentStatus != _freshPaymentStatus ||
              newTotalAmount != _freshTotalAmount ||
              (newPartyDate != null && newPartyDate != _freshPartyDate) ||
              (newStartTime != null && newStartTime != _freshStartTime) ||
              (newHostUser != null && newHostUser.toString() != _freshHostUser?.toString()) ||
              (newVenue != null && newVenue.toString() != _freshVenue?.toString());

          if (mounted && didChange) {
            setState(() {
              if (newHostUser != null) _freshHostUser = newHostUser;
              if (newVenue != null) _freshVenue = newVenue;
              if (newPartyDate != null) _freshPartyDate = newPartyDate;
              if (newStartTime != null) _freshStartTime = newStartTime;
              _freshTotalAmount = newTotalAmount;
              _freshPaymentStatus = newPaymentStatus;
              _canonicalTicketCode = newTicketCode;
              _amountDue = newAmountDue;
              if (newTotalParticipants != null) _freshTotalParticipants = newTotalParticipants;
              if (newMemberCount != null) _freshMemberCount = newMemberCount;
              _paymentState = newPaymentState;
            });
            _initCountdown();
          }
          return;
        }
      }
      if (response.statusCode != 404) {
        debugPrint('_fetchTicketData: unexpected status ${response.statusCode} for booking $id');
      }
    } catch (e) {
      debugPrint('_fetchTicketData error for Booking: $e');
    }

    // Fall back to the small GroupParty ticket endpoint (already ungated, always
    // returns status/paymentStatus regardless of payment state).
    try {
      final response = await ApiService.get('/api/mobile/group-parties/$id/ticket');
      if (response.statusCode == 200 && mounted) {
        final mapData = jsonDecode(response.body);
        if (mapData != null && mapData['data'] != null) {
          final ticketObj = mapData['data'];
          final groupParty = ticketObj['groupParty'];
          setState(() {
            if (groupParty is Map) {
              if (groupParty['host'] is Map) {
                _freshHostUser = Map<String, dynamic>.from(groupParty['host']);
              } else if (groupParty['user'] is Map) {
                _freshHostUser = Map<String, dynamic>.from(groupParty['user']);
              }
              if (groupParty['venue'] is Map) {
                _freshVenue = Map<String, dynamic>.from(groupParty['venue']);
              }
              if (groupParty['totalParticipants'] != null) {
                _freshTotalParticipants = int.tryParse(groupParty['totalParticipants'].toString());
              } else if (groupParty['numberOfFriends'] != null) {
                _freshTotalParticipants = int.tryParse(groupParty['numberOfFriends'].toString());
              }
              if (groupParty['memberCount'] != null) {
                _freshMemberCount = int.tryParse(groupParty['memberCount'].toString());
              }
              if (groupParty['totalAmount'] != null) {
                _freshTotalAmount = double.tryParse(groupParty['totalAmount'].toString());
              }
              if (groupParty['partyDate'] != null) {
                _freshPartyDate = DateTime.tryParse(groupParty['partyDate'].toString())?.toLocal();
              }
              final rawStartTime = groupParty['startTime']?.toString();
              if (rawStartTime != null && rawStartTime.trim().isNotEmpty) {
                _freshStartTime = _normalizeTimeStr(rawStartTime);
              }
              _freshPaymentStatus = groupParty['paymentStatus']?.toString();
              _freshPaymentMethod = groupParty['paymentMethod']?.toString();
              _amountDue = _freshTotalAmount;

              final gpStatus = groupParty['status']?.toString().toLowerCase();
              final isFreeGp = (_freshTotalAmount == null || _freshTotalAmount! <= 0);
              final isExpired = widget.isExpired == true || gpStatus == 'expired';
              final isPaid = !isExpired && (_freshPaymentStatus == 'paid' || 
                             gpStatus == 'confirmed' ||
                             gpStatus == 'completed' ||
                             isFreeGp);

              if (isPaid) {
                _paymentState = _LargePartyPaymentState.paid;
              } else if (isExpired) {
                _paymentState = _LargePartyPaymentState.expired;
              } else {
                _paymentState = _LargePartyPaymentState.awaitingPayment;
              }
            }
            _canonicalTicketCode = ticketObj['ticketCode']?.toString();
          });
          _initCountdown();
          return;
        }
      }
    } catch (e) {
      debugPrint('_fetchTicketData error for GroupParty: $e');
    }

    // Fall back to /api/mobile/tickets/$id
    try {
      final response = await ApiService.get('/api/mobile/tickets/$id');
      if (response.statusCode == 200 && mounted) {
        final mapData = jsonDecode(response.body);
        if (mapData != null && mapData['data'] != null) {
          final ticketObj = mapData['data'];
          setState(() {
            if (ticketObj['user'] is Map) {
              _freshHostUser = Map<String, dynamic>.from(ticketObj['user']);
            }
            if (ticketObj['venue'] is Map) {
              _freshVenue = Map<String, dynamic>.from(ticketObj['venue']);
            }
            if (ticketObj['numberOfGuests'] != null) {
              _freshTotalParticipants = int.tryParse(ticketObj['numberOfGuests'].toString());
            }
            if (_freshTotalParticipants != null && _freshMemberCount == null) {
              _freshMemberCount = _freshTotalParticipants! > 1 ? _freshTotalParticipants! - 1 : 1;
            }
            if (ticketObj['totalAmount'] != null) {
              _freshTotalAmount = double.tryParse(ticketObj['totalAmount'].toString());
            }
            if (ticketObj['eventStartAt'] != null || ticketObj['bookingDate'] != null) {
              _freshPartyDate = DateTime.tryParse((ticketObj['eventStartAt'] ?? ticketObj['bookingDate']).toString())?.toLocal();
            }
            if (ticketObj['startTime'] != null && ticketObj['startTime'].toString().trim().isNotEmpty) {
              _freshStartTime = _normalizeTimeStr(ticketObj['startTime'].toString());
            }
            _canonicalTicketCode = ticketObj['ticketCode']?.toString() ?? ticketObj['ticketId']?.toString();
            _paymentState = _LargePartyPaymentState.paid;
          });
          _initCountdown();
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _initiatePayment() async {
    final id = _bookingId;
    if (id == null || _isPaying) return;
    final venueMap = _freshVenue ?? (widget.venue.isNotEmpty ? Map<String, dynamic>.from(widget.venue) : <String, dynamic>{});
    final venueName = venueMap['name']?.toString() ?? 'Venue';
    final amount = _amountDue ?? 0.0;
    if (amount <= 0) return;

    final bool? sheetSuccess = await SmartCheckoutSheet.show(
      context: context,
      title: 'Group Party Payment',
      subtitle: 'Complete payment for your party at $venueName',
      itemPrice: amount,
      onWalletPayment: () async {
        final res = await ApiService.payWithWallet(amount: amount, bookingId: id, paymentType: 'group_party');
        if (res != null && res['success'] == true) {
          final transactionId = res['data']?['transactionId']?.toString() ?? 'wallet';
          final confirmed = await ApiService.verifyLargePartyPayment(
            id,
            razorpayOrderId: 'order_mock_wallet',
            razorpayPaymentId: 'wallet_$transactionId',
            razorpaySignature: 'mock_signature',
          );
          if (confirmed) {
            return true;
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res?['message']?.toString() ?? 'Wallet payment failed'), backgroundColor: Colors.redAccent),
          );
        }
        return false;
      },
      onDirectPayment: () async {
        setState(() => _isPaying = true);
        final result = await ApiService.initiateLargePartyPayment(id);
        if (result != null && result['success'] == true) {
          final orderData = result['order'] ?? result['data'] ?? result;
          final razorpayKey = result['razorpayKeyId']?.toString() ?? orderData['key']?.toString() ?? '';
          final orderId = orderData['razorpayOrderId']?.toString() ?? orderData['id']?.toString() ?? '';
          final num amountInPaise = orderData['amount'] ?? ((amount * 100).toInt());

          if (kIsWeb || _razorpay == null) {
            final bool? shouldConfirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1E1035),
                title: const Text('Direct Payment Gateway', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                content: Text('Simulate Razorpay payment of ₹${amount.toInt()} for Group Party at $venueName?', style: const TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(backgroundColor: LunaraTheme.electricViolet),
                    child: const Text('Confirm Pay', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );

            if (shouldConfirm == true) {
              final success = await ApiService.verifyLargePartyPayment(
                id,
                razorpayOrderId: orderId.isNotEmpty ? orderId : 'order_mock_${DateTime.now().millisecondsSinceEpoch}',
                razorpayPaymentId: 'mock_payment_${DateTime.now().millisecondsSinceEpoch}',
                razorpaySignature: 'mock_signature',
              );
              if (mounted) setState(() => _isPaying = false);
              if (success) {
                await _fetchTicketData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('🎉 Payment verified successfully! Your ticket is confirmed.'), backgroundColor: Colors.green),
                  );
                }
                return true;
              }
              return false;
            } else {
              if (mounted) setState(() => _isPaying = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment cancelled.'), backgroundColor: Colors.black87),
                );
              }
              return false;
            }
          }

          final effectiveKey = (razorpayKey.isNotEmpty && razorpayKey != 'rzp_test_123') ? razorpayKey : 'rzp_test_T1rwVokR7tFger';
          final options = {
            'key': effectiveKey,
            if (orderId.isNotEmpty && !orderId.startsWith('order_mock_')) 'order_id': orderId,
            'amount': amountInPaise,
            'name': 'Lunara – Group Party',
            'description': 'Group Party at $venueName',
            'prefill': {
              'contact': widget.booking['mobileNumber']?.toString() ?? '9999999999',
              'email': 'user@lunara.app',
            },
            'theme': {'color': '#7C3AED'},
          };

          try {
            _razorpay?.open(options);
            return 'gateway_launched';
          } catch (e) {
            debugPrint('Razorpay open error: $e');
            if (mounted) {
              setState(() => _isPaying = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not open payment gateway: $e'), backgroundColor: Colors.redAccent),
              );
            }
            return false;
          }
        } else if (mounted) {
          setState(() => _isPaying = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result?['message']?.toString() ?? 'Failed to initiate payment gateway'),
              backgroundColor: Colors.redAccent,
            ),
          );
          return false;
        }
        return false;
      },
      onHybridPayment: (shortfall) async {
        setState(() => _isPaying = true);
        final result = await ApiService.initiateLargePartyPayment(id);
        if (result != null && result['success'] == true) {
          final orderData = result['order'] ?? result['data'] ?? result;
          final razorpayKey = result['razorpayKeyId']?.toString() ?? orderData['key']?.toString() ?? '';
          final orderId = orderData['razorpayOrderId']?.toString() ?? orderData['id']?.toString() ?? '';
          final shortfallPaise = (shortfall * 100).toInt();

          if (kIsWeb || _razorpay == null) {
            final bool? shouldConfirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1E1035),
                title: const Text('Smart Hybrid Payment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                content: Text('Pay shortfall of ₹${shortfall.toInt()} via Direct Gateway + remaining from wallet for Group Party at $venueName?', style: const TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(backgroundColor: LunaraTheme.electricViolet),
                    child: const Text('Confirm Pay', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );

            if (shouldConfirm == true) {
              await ApiService.payWithWallet(amount: amount, bookingId: id, paymentType: 'group_party');
              final success = await ApiService.verifyLargePartyPayment(
                id,
                razorpayOrderId: orderId.isNotEmpty ? orderId : 'order_mock_${DateTime.now().millisecondsSinceEpoch}',
                razorpayPaymentId: 'mock_payment_${DateTime.now().millisecondsSinceEpoch}',
                razorpaySignature: 'mock_signature',
              );
              if (mounted) setState(() => _isPaying = false);
              if (success) {
                await _fetchTicketData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('🎉 Payment verified successfully! Your ticket is confirmed.'), backgroundColor: Colors.green),
                  );
                }
                return true;
              }
              return false;
            } else {
              if (mounted) setState(() => _isPaying = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment cancelled.'), backgroundColor: Colors.black87),
                );
              }
              return false;
            }
          }

          final effectiveKey = (razorpayKey.isNotEmpty && razorpayKey != 'rzp_test_123') ? razorpayKey : 'rzp_test_T1rwVokR7tFger';
          final options = {
            'key': effectiveKey,
            if (orderId.isNotEmpty && !orderId.startsWith('order_mock_')) 'order_id': orderId,
            'amount': shortfallPaise,
            'name': 'Lunara – Group Party Shortfall',
            'description': 'Group Party Shortfall at $venueName',
            'prefill': {
              'contact': widget.booking['mobileNumber']?.toString() ?? '9999999999',
              'email': 'user@lunara.app',
            },
            'theme': {'color': '#7C3AED'},
          };

          try {
            _razorpay?.open(options);
            return 'gateway_launched';
          } catch (e) {
            debugPrint('Razorpay open error: $e');
            if (mounted) {
              setState(() => _isPaying = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not open payment gateway: $e'), backgroundColor: Colors.redAccent),
              );
            }
            return false;
          }
        } else if (mounted) {
          setState(() => _isPaying = false);
          return false;
        }
        return false;
      },
    );

    if (sheetSuccess == true && mounted) {
      TopNotificationBanner.show(
        title: 'Payment Successful! 🎉',
        body: 'Group party payment was verified via Smart Wallet. Ticket is active!',
      );
      ApiService.notifyFeedNeedsRefresh();
      await _fetchTicketData();
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    final id = _bookingId;
    if (id == null) return;
    try {
      final verified = await ApiService.verifyLargePartyPayment(
        id,
        razorpayOrderId: response.orderId ?? '',
        razorpayPaymentId: response.paymentId ?? '',
        razorpaySignature: response.signature ?? '',
      );
      if (mounted) {
        setState(() => _isPaying = false);
        if (verified) {
          await _fetchTicketData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('🎉 Payment successful! Your ticket is ready.'), backgroundColor: Colors.green),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('_onPaymentSuccess error: $e');
      if (mounted) setState(() => _isPaying = false);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (mounted) {
      setState(() => _isPaying = false);
      final isCancelled = response.code == Razorpay.PAYMENT_CANCELLED ||
          response.code == 2 ||
          (response.message != null &&
              (response.message!.toLowerCase().contains('cancel') ||
                  response.message!.toLowerCase().contains('back')));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCancelled
                ? 'Payment cancelled. You can complete your booking payment anytime.'
                : 'Payment failed: ${response.message ?? "Please try again"}',
          ),
          backgroundColor: isCancelled ? Colors.black87 : Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position pos) {
        if (mounted) {
          setState(() {
            _currentPosition = pos;
          });
        }
      });
    } catch (e) {
      debugPrint("Error in LargePartyTicketScreen location initialization: $e");
    }
  }

  Widget _buildCountdownBadge() {
    if (_isTicketCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel_outlined, color: Color(0xFFDC2626), size: 12),
            SizedBox(width: 4),
            Text(
              'CANCELLED',
              style: TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    if (_isTicketExpired || _paymentState == _LargePartyPaymentState.expired) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_off_rounded, color: Color(0xFFB91C1C), size: 12),
            SizedBox(width: 4),
            Text(
              'EXPIRED',
              style: TextStyle(
                color: Color(0xFFB91C1C),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    if (_timeRemaining == Duration.zero) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF86EFAC)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.celebration_rounded, color: Color(0xFF15803D), size: 12),
            SizedBox(width: 4),
            Text(
              'PARTY TIME!',
              style: TextStyle(
                color: Color(0xFF15803D),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    final days = _timeRemaining.inDays;
    final hours = _timeRemaining.inHours % 24;
    final minutes = _timeRemaining.inMinutes % 60;

    final label = days > 0 ? '${days}d ${hours}h left' : '${hours}h ${minutes}m left';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDD6FE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.access_time_rounded, color: Color(0xFF7C3AED), size: 12),
          const SizedBox(width: 4),
          Text(
            'Expires in $label',
            style: const TextStyle(
              color: Color(0xFF7C3AED),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiredWatermark() {
    return IgnorePointer(
      child: Transform.rotate(
        angle: -0.22,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.red.shade600,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            'EXPIRED',
            style: TextStyle(
              color: Colors.red.shade600,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 3.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCancelledWatermark() {
    return IgnorePointer(
      child: Transform.rotate(
        angle: -0.22,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFEF4444),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Text(
            'CANCELLED',
            style: TextStyle(
              color: Color(0xFFEF4444),
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 3.5,
            ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _resolveHostUser() {
    Map<String, dynamic> hostMap = {};
    if (_freshHostUser != null && _freshHostUser!.isNotEmpty) {
      hostMap = Map<String, dynamic>.from(_freshHostUser!);
    } else if (widget.booking['host'] is Map && (widget.booking['host'] as Map).isNotEmpty) {
      hostMap = Map<String, dynamic>.from(widget.booking['host']);
    } else if (widget.booking['user'] is Map && (widget.booking['user'] as Map).isNotEmpty) {
      hostMap = Map<String, dynamic>.from(widget.booking['user']);
    } else if (widget.booking['customer'] is Map && (widget.booking['customer'] as Map).isNotEmpty) {
      hostMap = Map<String, dynamic>.from(widget.booking['customer']);
    }

    final cached = ApiService.cachedCurrentUser;
    final cachedPhoto = cached?.profilePhoto;

    if (hostMap.isNotEmpty) {
      final existingPhoto = (hostMap['profilePhotoUrl'] ?? hostMap['profileImageUrl'] ?? hostMap['profilePhoto'] ?? hostMap['photo'])?.toString();
      if ((existingPhoto == null || existingPhoto.trim().isEmpty) && cachedPhoto != null && cachedPhoto.isNotEmpty) {
        hostMap['profilePhotoUrl'] = cachedPhoto;
        hostMap['profileImageUrl'] = cachedPhoto;
        hostMap['profilePhoto'] = cachedPhoto;
      }
      if ((hostMap['firstName'] == null || hostMap['firstName'].toString().trim().isEmpty) && cached != null) {
        hostMap['firstName'] = cached.firstName;
        hostMap['lastName'] = cached.lastName;
      }
      return hostMap;
    }

    if (cached != null) {
      return {
        'id': cached.id,
        'firstName': cached.firstName,
        'lastName': cached.lastName,
        'fullName': '${cached.firstName} ${cached.lastName}'.trim(),
        'name': '${cached.firstName} ${cached.lastName}'.trim(),
        'username': '${cached.firstName.toLowerCase()}.${cached.lastName.toLowerCase()}',
        'email': cached.email,
        'mobileNumber': cached.phone,
        'phone': cached.phone,
        'profilePhotoUrl': cached.profilePhoto,
        'profileImageUrl': cached.profilePhoto,
        'profilePhoto': cached.profilePhoto,
      };
    }
    return <String, dynamic>{};
  }

  void _shareTicket(BuildContext context) {
    final venueMap = _freshVenue ?? (widget.venue.isNotEmpty ? Map<String, dynamic>.from(widget.venue) : (widget.booking['venue'] is Map ? Map<String, dynamic>.from(widget.booking['venue']) : <String, dynamic>{}));
    final venueName = venueMap['name']?.toString() ?? widget.venue['name']?.toString() ?? 'Venue';
    final rawDate = _freshPartyDate ?? widget.booking['bookingDate'] ?? widget.booking['partyDate'];
    final rawTime = _freshStartTime ?? widget.booking['startTime'] ?? '12:00 AM';
    final DateTime planDateTime = _parseEventDateTime(rawDate, rawTime);
    final eventDateTime = DateFormat('MMM dd, yyyy • hh:mm a').format(planDateTime);
    final ticketId = (_canonicalTicketCode ?? widget.booking['ticketCode'] ?? widget.booking['id'] ?? 'LP-PASS').toString().toUpperCase();
    final hostUser = _resolveHostUser();
    final hostName = '${hostUser['firstName'] ?? ''} ${hostUser['lastName'] ?? ''}'.trim();
    final rawGuestsCount = _freshTotalParticipants ?? widget.booking['totalParticipants'] ?? widget.booking['numberOfFriends'] ?? widget.booking['numberOfGuests'] ?? widget.booking['numberOfPersons'] ?? 5;

    LunaraTicketCaptureService.shareTicket(
      context: context,
      ticketKey: _ticketKey,
      ticketCode: ticketId,
      venueName: venueName,
      eventDateTime: eventDateTime,
      eventType: 'Large Party VIP Pass',
      hostName: hostName.isNotEmpty ? hostName : 'Party Host',
      guestCount: '$rawGuestsCount VIP Guests',
    );
  }

  @override
  Widget build(BuildContext context) {
    final venueMap = _freshVenue ?? (widget.venue.isNotEmpty ? Map<String, dynamic>.from(widget.venue) : (widget.booking['venue'] is Map ? Map<String, dynamic>.from(widget.booking['venue']) : <String, dynamic>{}));
    final venueName = venueMap['name']?.toString() ?? widget.venue['name']?.toString() ?? 'Venue';
    final venueCity = venueMap['city']?.toString() ?? widget.venue['city']?.toString() ?? 'Pune';
    final venueArea = venueMap['area']?.toString() ?? widget.venue['area']?.toString() ?? '';
    final venueAddress = venueMap['address']?.toString() ??
        venueMap['addressLine1']?.toString() ??
        widget.venue['address']?.toString() ??
        widget.venue['addressLine1']?.toString() ??
        '${venueArea.isNotEmpty ? "$venueArea, " : ""}$venueCity';

    final rawDate = _freshPartyDate ?? widget.booking['bookingDate'] ?? widget.booking['partyDate'];
    final rawTime = _freshStartTime ?? widget.booking['startTime'] ?? '12:00 AM';
    final DateTime planDateTime = _parseEventDateTime(rawDate, rawTime);

    final ticketId = (_canonicalTicketCode ?? widget.booking['ticketCode'] ?? widget.booking['id'] ?? 'GP-TICKET').toString().toUpperCase();
    final double totalAmount = _freshTotalAmount ??
        double.tryParse((widget.booking['totalAmount'] ?? widget.booking['depositAmount'] ?? widget.booking['approvedAmount'] ?? widget.booking['charges'] ?? 0).toString()) ??
        0.0;

    // Standardized Participant Calculation:
    // If total is 14: Host = 1, Members = 13, Total = 14
    final rawGuestsCount = _freshTotalParticipants ?? widget.booking['totalParticipants'] ?? widget.booking['numberOfFriends'] ?? widget.booking['numberOfGuests'] ?? widget.booking['numberOfPersons'] ?? 5;
    final int totalParticipants = rawGuestsCount is int ? rawGuestsCount : (int.tryParse(rawGuestsCount.toString()) ?? 5);
    final bool isSoloBooking = totalParticipants <= 1 ||
        widget.booking['goingMode'] == 'solo' ||
        widget.booking['isSolo'] == true ||
        widget.booking['bookingType'] == 'solo' ||
        widget.booking['category'] == 'solo';
    final int memberCount = _freshMemberCount ?? (totalParticipants > 1 ? totalParticipants - 1 : 0);

    final bookingCreatedDate = widget.booking['createdAt'] != null
        ? DateTime.tryParse(widget.booking['createdAt'].toString())?.toLocal() ?? planDateTime
        : planDateTime;

    final hostUser = _resolveHostUser();
    final hostNameRaw = '${hostUser['firstName'] ?? ''} ${hostUser['lastName'] ?? ''}'.trim();
    final cleanHostName = hostNameRaw.isNotEmpty ? hostNameRaw : (hostUser['name']?.toString() ?? 'Party Host');
    final hostUsernameRaw = hostUser['username']?.toString() ?? hostUser['firstName']?.toString().toLowerCase();
    final hostUsername = hostUsernameRaw != null && hostUsernameRaw.isNotEmpty
        ? (hostUsernameRaw.startsWith('@') ? hostUsernameRaw : '@$hostUsernameRaw')
        : '@host';

    final latVal = venueMap['latitude'] ?? widget.venue['latitude'];
    final lngVal = venueMap['longitude'] ?? widget.venue['longitude'];
    double? lat = latVal != null ? double.tryParse(latVal.toString()) : null;
    double? lng = lngVal != null ? double.tryParse(lngVal.toString()) : null;

    String distanceText = '';
    if (_currentPosition != null && lat != null && lng != null && lat != 0.0 && lng != 0.0) {
      distanceText = GooglePlacesService.formatRoadDistance(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        lat,
        lng,
      );
    }

    final bool isAwaitingPayment = _paymentState == _LargePartyPaymentState.awaitingPayment;
    final bool isExpired = _paymentState == _LargePartyPaymentState.expired;
    final bool isFreeParty = totalAmount <= 0 && !isAwaitingPayment && !isExpired && _paymentState == _LargePartyPaymentState.paid;
    final double amountDue = _amountDue ?? totalAmount;
    final paymentMethodLabel = isFreeParty
        ? 'FREE (No Payment Required)'
        : isAwaitingPayment
            ? 'Awaiting Payment'
            : isExpired
                ? 'Expired — Not Paid'
                : (_freshPaymentMethod ??
                    (widget.booking['paymentId']?.toString().startsWith('wallet_') == true
                        ? 'LUNARA Wallet'
                        : (widget.booking['paymentId']?.toString().startsWith('free_') == true
                            ? 'FREE (No Payment Required)'
                            : 'Online Payment (Razorpay)')));

    const lightBgColor = Color(0xFFF6F7FB);
    const darkTextColor = Color(0xFF0F172A);
    const grayTextColor = Color(0xFF64748B);

    return Scaffold(
      backgroundColor: lightBgColor,
      appBar: AppBar(
        backgroundColor: lightBgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: darkTextColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'GROUP PARTY TICKET',
            style: TextStyle(
              color: darkTextColor,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              fontSize: 16,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: darkTextColor),
            onPressed: () => _shareTicket(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // ── THE TICKET CARD ───────────────────────────────────────────
              RepaintBoundary(
                key: _ticketKey,
                child: LunaraTicketWidget(
                  cardColor: Colors.white,
                  cutoutColor: lightBgColor,
                  dashColor: const Color(0xFFCBD5E1),
                  borderRadius: 24.0,
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                topSection: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Pill & Ticket Code
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0EBFF),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('🎉 ', style: TextStyle(fontSize: 10)),
                                      Flexible(
                                        child: Text(
                                          'VIP GROUP PARTY',
                                          style: TextStyle(
                                            color: Color(0xFF6D28D9),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: RichText(
                                    text: TextSpan(
                                      children: [
                                        const TextSpan(
                                          text: 'TICKET ID: ',
                                          style: TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        TextSpan(
                                          text: ticketId.length > 14
                                              ? ticketId.substring(0, 14)
                                              : ticketId,
                                          style: const TextStyle(
                                            color: Color(0xFF6D28D9),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Countdown badge
                          _buildCountdownBadge(),
                          const SizedBox(height: 16),

                          // Headline
                          Text(
                            '🎉 Party at $venueName!',
                            style: const TextStyle(
                              color: darkTextColor,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isTicketCancelled
                                ? 'This booking has been cancelled.'
                                : (_isTicketExpired
                                    ? 'This event has concluded.'
                                    : 'Get ready for an epic night with your crew.'),
                            style: const TextStyle(
                              color: grayTextColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 20),

                      // 3-Column Info Details Box
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAFAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            // DATE
                            Expanded(
                              child: _buildLightDetailBox(
                                icon: Icons.calendar_today_rounded,
                                label: 'DATE',
                                value: LunaraDateFormatter.formatEventDate(planDateTime, pattern: 'MMM dd, yyyy'),
                                subtext: LunaraDateFormatter.formatEventDate(planDateTime, pattern: 'EEEE'),
                              ),
                            ),
                            Container(height: 36, width: 1, color: const Color(0xFFE2E8F0)),
                            // TIME
                            Expanded(
                              child: _buildLightDetailBox(
                                icon: Icons.access_time_rounded,
                                label: 'TIME',
                                value: LunaraDateFormatter.formatEventTime(planDateTime),
                                subtext: 'Onwards',
                              ),
                            ),
                            Container(height: 36, width: 1, color: const Color(0xFFE2E8F0)),
                            // PARTICIPANTS (1 Host + 13 Members = 14 Total)
                            Expanded(
                              child: _buildLightDetailBox(
                                icon: Icons.groups_rounded,
                                label: 'PARTICIPANTS',
                                value: isSoloBooking ? '1 Guest' : '$totalParticipants Members',
                                subtext: isSoloBooking ? 'Solo Booking' : '1 Host + $memberCount Friends',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isTicketCancelled)
                  Positioned(
                    top: 24,
                    right: 16,
                    child: _buildCancelledWatermark(),
                  )
                else if (_isTicketExpired)
                  Positioned(
                    top: 24,
                    right: 16,
                    child: _buildExpiredWatermark(),
                  ),
              ],
            ),
            bottomSection: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    children: [
                      // ── SINGLE PROFILE SECTION (HOST + GROUP SIZE) ────────
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Host Column (Left)
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECE6FE),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'PARTY HOST',
                                      style: TextStyle(
                                        color: Color(0xFF7C3AED),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  LunaraProfileImage(
                                    userData: hostUser,
                                    radius: 30,
                                    showGradientBorder: true,
                                    borderWidth: 2,
                                    isInteractive: true,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    cleanHostName,
                                    style: const TextStyle(
                                      color: darkTextColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                  Text(
                                    hostUsername,
                                    style: const TextStyle(
                                      color: grayTextColor,
                                      fontSize: 10.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),

                            // Vertical Divider
                            Container(
                              width: 1,
                              height: 70,
                              color: const Color(0xFFE2E8F0),
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                            ),

                            // Group Size Column (Right)
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0F7FA),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'GROUP SIZE',
                                      style: TextStyle(
                                        color: Color(0xFF00838F),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE0F7FA),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.groups_rounded,
                                      color: Color(0xFF00838F),
                                      size: 32,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    isSoloBooking ? '1 Guest (Solo)' : '$totalParticipants Participants',
                                    style: const TextStyle(
                                      color: darkTextColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                  Text(
                                    isSoloBooking ? 'Solo Booking' : '1 Host + $memberCount Members',
                                    style: const TextStyle(
                                      color: grayTextColor,
                                      fontSize: 10.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── BOOKING STATUS CARD ────────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFDCFCE7)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFDCFCE7),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.verified_user_rounded,
                                      color: Color(0xFF16A34A),
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isFreeParty ? 'BOOKING TYPE' : (isAwaitingPayment ? 'PAYMENT STATUS' : 'PAYMENT METHOD'),
                                          style: const TextStyle(
                                            color: grayTextColor,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          paymentMethodLabel,
                                          style: const TextStyle(
                                            color: darkTextColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  isAwaitingPayment || isExpired ? 'AMOUNT DUE' : (isFreeParty ? 'BOOKING CHARGE' : 'TOTAL PAID'),
                                  style: const TextStyle(
                                    color: grayTextColor,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isFreeParty ? 'FREE' : '₹${amountDue.toStringAsFixed(amountDue.truncateToDouble() == amountDue ? 0 : 2)}',
                                      style: TextStyle(
                                        color: isFreeParty
                                            ? const Color(0xFF1D4ED8)
                                            : isAwaitingPayment
                                                ? const Color(0xFFB45309)
                                                : isExpired
                                                    ? const Color(0xFFB91C1C)
                                                    : const Color(0xFF15803D),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isFreeParty
                                            ? const Color(0xFFDEEBFF)
                                            : isAwaitingPayment
                                                ? const Color(0xFFFEF3C7)
                                                : isExpired
                                                    ? const Color(0xFFFEE2E2)
                                                    : const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isFreeParty
                                            ? 'FREE'
                                            : isAwaitingPayment
                                                ? 'PENDING'
                                                : isExpired
                                                    ? 'EXPIRED'
                                                    : 'PAID',
                                        style: TextStyle(
                                          color: isFreeParty
                                              ? const Color(0xFF1D4ED8)
                                              : isAwaitingPayment
                                                  ? const Color(0xFFB45309)
                                                  : isExpired
                                                      ? const Color(0xFFB91C1C)
                                                      : const Color(0xFF15803D),
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── VENUE LOCATION CARD ────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.location_on_rounded,
                                    color: Color(0xFF7C3AED),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              venueName.toUpperCase(),
                                              style: const TextStyle(
                                                color: darkTextColor,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w900,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (distanceText.isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEDE9FE),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                distanceText,
                                                style: const TextStyle(
                                                  color: Color(0xFF7C3AED),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        venueAddress,
                                        style: const TextStyle(
                                          color: grayTextColor,
                                          fontSize: 11,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 38,
                              child: TextButton(
                                onPressed: () async {
                                  Uri mapUrl;
                                  if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
                                    mapUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
                                  } else {
                                    mapUrl = Uri.parse(
                                      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent("$venueName, $venueAddress")}',
                                    );
                                  }
                                  if (await canLaunchUrl(mapUrl)) {
                                    await launchUrl(mapUrl, mode: LaunchMode.externalApplication);
                                  }
                                },
                                style: TextButton.styleFrom(
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.map_rounded, color: Color(0xFF7C3AED), size: 15),
                                    SizedBox(width: 6),
                                    Text(
                                      'VIEW MAP DIRECTIONS',
                                      style: TextStyle(
                                        color: Color(0xFF7C3AED),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(Icons.chevron_right_rounded, color: Color(0xFF7C3AED), size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: Color(0xFFE2E8F0), height: 1),
                      const SizedBox(height: 16),

                      // ── TICKET FOOTER ROW ──────────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF1F5F9),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.confirmation_number_rounded,
                                    color: Color(0xFF7C3AED),
                                    size: 15,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: const [
                                      Text(
                                        'TICKET TYPE',
                                        style: TextStyle(
                                          color: grayTextColor,
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      SizedBox(height: 1),
                                      Text(
                                        'Group Party Entry',
                                        style: TextStyle(
                                          color: darkTextColor,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF1F5F9),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.access_time_filled_rounded,
                                    color: Color(0xFF7C3AED),
                                    size: 15,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'BOOKED ON',
                                        style: TextStyle(
                                          color: grayTextColor,
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        '${DateFormat('MMM dd, yyyy').format(bookingCreatedDate)} • ${DateFormat('hh:mm a').format(bookingCreatedDate)}',
                                        style: const TextStyle(
                                          color: darkTextColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),

              if (_isTicketExpired) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.timer_off_rounded, color: Color(0xFFB91C1C), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This request expired because payment wasn\'t completed before the party started.',
                          style: TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ] else if (isAwaitingPayment) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isPaying ? null : _initiatePayment,
                    icon: _isPaying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.payment_rounded, color: Colors.white, size: 20),
                    label: Text(
                      _isPaying ? 'PROCESSING...' : 'PAY NOW ₹${amountDue.toStringAsFixed(amountDue.truncateToDouble() == amountDue ? 0 : 2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.8,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final venueMap = _freshVenue ?? (widget.venue.isNotEmpty ? Map<String, dynamic>.from(widget.venue) : (widget.booking['venue'] is Map ? Map<String, dynamic>.from(widget.booking['venue']) : <String, dynamic>{}));
                      final venueName = venueMap['name']?.toString() ?? widget.venue['name']?.toString() ?? 'Venue';
                      final rawDate = widget.booking['bookingDate'] ?? widget.booking['partyDate'];
                      DateTime planDateTime = DateTime.now();
                      if (rawDate != null) {
                        try {
                          planDateTime = DateTime.parse(rawDate.toString()).toLocal();
                        } catch (_) {}
                      }
                      if (_freshPartyDate != null) planDateTime = _freshPartyDate!;
                      if (_freshStartTime != null) {
                        final tp = _freshStartTime!.split(':');
                        if (tp.length >= 2) {
                          final h = int.tryParse(tp[0]);
                          final m = int.tryParse(tp[1]);
                          if (h != null && m != null) {
                            planDateTime = DateTime(planDateTime.year, planDateTime.month, planDateTime.day, h, m);
                          }
                        }
                      }
                      final eventDateTime = DateFormat('MMM dd, yyyy • hh:mm a').format(planDateTime);
                      final ticketId = (_canonicalTicketCode ?? widget.booking['ticketCode'] ?? widget.booking['id'] ?? 'LP-PASS').toString().toUpperCase();
                      LunaraTicketCaptureService.downloadTicket(
                        context: context,
                        ticketKey: _ticketKey,
                        ticketCode: ticketId,
                        eventType: 'Large_Party',
                        venueName: venueName,
                        eventDateTime: eventDateTime,
                      );
                    },
                    icon: const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                    label: const Text(
                      'DOWNLOAD TICKET PASS',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.8,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => _shareTicket(context),
                    icon: const Icon(Icons.share_rounded, color: darkTextColor, size: 18),
                    label: const Text(
                      'SHARE TICKET',
                      style: TextStyle(
                        color: darkTextColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.8,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (!_isTicketExpired && !_isTicketCancelled) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final venueMap = _freshVenue ?? (widget.venue.isNotEmpty ? Map<String, dynamic>.from(widget.venue) : (widget.booking['venue'] is Map ? Map<String, dynamic>.from(widget.booking['venue']) : <String, dynamic>{}));
                        final venueName = venueMap['name']?.toString() ?? widget.venue['name']?.toString() ?? 'Venue';
                        final bookingId = (_bookingId ?? widget.booking['id'] ?? widget.booking['bookingId'] ?? '').toString();
                        final partySubject = (widget.booking['partySubject'] ?? widget.booking['subject'] ?? '$venueName Large Party').toString();
                        final rawDate = widget.booking['bookingDate'] ?? widget.booking['partyDate'];
                        DateTime planDateTime = DateTime.now();
                        if (rawDate != null) {
                          try {
                            planDateTime = DateTime.parse(rawDate.toString()).toLocal();
                          } catch (_) {}
                        }
                        if (_freshPartyDate != null) planDateTime = _freshPartyDate!;
                        final scheduledDate = DateFormat('EEE, MMM dd, yyyy').format(planDateTime);
                        final scheduledTime = _freshStartTime ?? (widget.booking['startTime']?.toString() ?? '20:00');
                        final amountPaid = (_freshTotalAmount ?? (widget.booking['totalAmount'] as num?)?.toDouble() ?? 0.0).toDouble();

                        LargePartyCancellationDialog.show(
                          context,
                          bookingId: bookingId,
                          partySubject: partySubject,
                          venueName: venueName,
                          scheduledDate: scheduledDate,
                          scheduledTime: scheduledTime,
                          amountPaid: amountPaid,
                          onSubmitted: () {
                            Navigator.pop(context);
                          },
                        );
                      },
                      icon: const Icon(Icons.cancel_presentation_rounded, color: Color(0xFFEF4444), size: 18),
                      label: const Text(
                        'CANCEL LARGE PARTY',
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.8,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'CLOSE',
                    style: TextStyle(
                      color: grayTextColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLightDetailBox({
    required IconData icon,
    required String label,
    required String value,
    required String subtext,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(
            color: Color(0xFFEDE9FE),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFF7C3AED), size: 16),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          subtext,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
