// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../services/google_places_service.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../widgets/lunara_ticket_widget.dart';
import '../../widgets/smart_checkout_sheet.dart';
import '../../services/api_service.dart';
import '../../services/lunara_ticket_capture_service.dart';

enum _LargePartyPaymentState { loading, paid, awaitingPayment, expired }

class LargePartyTicketScreen extends StatefulWidget {
  final Map<dynamic, dynamic> booking;
  final Map<dynamic, dynamic> venue;

  const LargePartyTicketScreen({
    super.key,
    required this.booking,
    required this.venue,
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
  String? _ticketUrl;
  int? _freshTotalParticipants;
  int? _freshMemberCount;
  double? _freshTotalAmount;
  String? _freshPaymentStatus;
  String? _freshPaymentMethod;
  Map<String, dynamic>? _freshVenue;
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
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
    _initLocation();
    _initCountdown();
    _fetchTicketData();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _countdownTimer?.cancel();
    _razorpay?.clear();
    super.dispose();
  }

  /// Best-effort guess from whatever the caller passed in, shown only until the
  /// authoritative server fetch in [_fetchTicketData] resolves and overwrites it.
  _LargePartyPaymentState _computeInitialStateFromLocalMap() {
    final amount = double.tryParse((widget.booking['totalAmount'] ?? widget.booking['depositAmount'] ?? widget.booking['approvedAmount'] ?? widget.booking['charges'] ?? 0).toString()) ?? 0.0;
    if (amount <= 0) return _LargePartyPaymentState.paid;
    final localStatus = (widget.booking['adminApprovalStatus'] ?? widget.booking['status'])?.toString().toLowerCase();
    if (localStatus == 'expired') return _LargePartyPaymentState.expired;
    if (localStatus == 'paid' || localStatus == 'payment_done' || localStatus == 'confirmed') {
      return _LargePartyPaymentState.paid;
    }
    // Any other/unknown status (approved, payment_sent, pending, null, ...):
    // never assume paid for a nonzero amount — wait for the server fetch to
    // confirm, and require Pay Now in the meantime.
    return _LargePartyPaymentState.awaitingPayment;
  }

  void _initCountdown() {
    final bookingDateStr = widget.booking['bookingDate']?.toString() ?? widget.booking['partyDate']?.toString();
    if (bookingDateStr == null) return;

    DateTime? targetDate = DateTime.tryParse(bookingDateStr)?.toLocal();
    if (targetDate == null) return;

    final startTimeStr = widget.booking['startTime']?.toString() ?? '20:00';
    try {
      final timeParts = startTimeStr.split(':');
      if (timeParts.length >= 2) {
        final hours = int.parse(timeParts[0]);
        final minutes = int.parse(timeParts[1]);
        targetDate = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          hours,
          minutes,
        );
      }
    } catch (_) {}

    void update() {
      if (!mounted) return;
      final remaining = targetDate!.difference(DateTime.now());
      setState(() {
        _timeRemaining = remaining.isNegative ? Duration.zero : remaining;
      });
    }

    update();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => update());
  }

  Future<void> _fetchTicketData() async {
    final id = (widget.booking['id'] ?? widget.booking['partyId'] ?? widget.booking['groupPartyId'] ?? widget.booking['bookingId'])?.toString();
    if (id == null) return;
    _bookingId = id;

    // Try the large-party Booking record first (ungated — works pre-payment too).
    try {
      final response = await ApiService.get('/api/mobile/bookings/$id');
      if (response.statusCode == 200 && mounted) {
        final mapData = jsonDecode(response.body);
        final booking = mapData is Map ? mapData['data'] : null;
        if (booking is Map) {
          setState(() {
            if (booking['venue'] is Map) {
              _freshVenue = Map<String, dynamic>.from(booking['venue']);
            }
            final adminAmount = double.tryParse((booking['adminPaymentAmount'] ?? '').toString());
            final totalAmount = double.tryParse((booking['totalAmount'] ?? '').toString());
            _freshTotalAmount = (adminAmount != null && adminAmount > 0) ? adminAmount : totalAmount;
            _freshPaymentStatus = booking['paymentStatus']?.toString();
            _canonicalTicketCode = booking['ticketCode']?.toString();
            _ticketUrl = booking['ticketUrl']?.toString();
            _amountDue = _freshTotalAmount;

            final guestsRaw = booking['numberOfGuests'];
            if (guestsRaw != null) {
              _freshTotalParticipants = int.tryParse(guestsRaw.toString());
              if (_freshTotalParticipants != null) {
                _freshMemberCount = _freshTotalParticipants! > 1 ? _freshTotalParticipants! - 1 : 1;
              }
            }

            final adminApprovalStatus = booking['adminApprovalStatus']?.toString();
            final bookingStatus = booking['status']?.toString();
            final isPaid = (_freshTotalAmount ?? 0) <= 0 || _freshPaymentStatus == 'paid';
            final isExpired = adminApprovalStatus == 'expired' || bookingStatus == 'expired';

            if (isPaid) {
              _paymentState = _LargePartyPaymentState.paid;
            } else if (isExpired) {
              _paymentState = _LargePartyPaymentState.expired;
            } else {
              // Covers isAwaitingPayment as well as any unrecognized status —
              // a nonzero-amount booking must never default to "paid".
              _paymentState = _LargePartyPaymentState.awaitingPayment;
            }
          });
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
              _freshPaymentStatus = groupParty['paymentStatus']?.toString();
              _freshPaymentMethod = groupParty['paymentMethod']?.toString();
              _amountDue = _freshTotalAmount;

              final gpStatus = groupParty['status']?.toString();
              final isPaid = (_freshTotalAmount ?? 0) <= 0 || _freshPaymentStatus == 'paid' || gpStatus == 'confirmed';
              final isExpired = gpStatus == 'expired';

              if (isPaid) {
                _paymentState = _LargePartyPaymentState.paid;
              } else if (isExpired) {
                _paymentState = _LargePartyPaymentState.expired;
              } else {
                // Covers 'approved' as well as any unrecognized status — a
                // nonzero-amount party must never default to "paid".
                _paymentState = _LargePartyPaymentState.awaitingPayment;
              }
            }
            _canonicalTicketCode = ticketObj['ticketCode']?.toString();
            _ticketUrl = ticketObj['ticketUrl']?.toString();
          });
        }
      }
    } catch (e) {
      debugPrint('_fetchTicketData error for GroupParty: $e');
    }
  }

  Future<void> _initiatePayment() async {
    final id = _bookingId;
    if (id == null || _isPaying) return;
    final venueMap = _freshVenue ?? (widget.venue.isNotEmpty ? Map<String, dynamic>.from(widget.venue) : <String, dynamic>{});
    final venueName = venueMap['name']?.toString() ?? 'Venue';
    final amount = _amountDue ?? 0.0;
    if (amount <= 0) return;

    SmartCheckoutSheet.show(
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
          if (confirmed && mounted) {
            await _fetchTicketData();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('🎉 Paid via Smart Credit Wallet! Your ticket is ready.'), backgroundColor: Colors.green),
            );
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

          if (orderId.startsWith('order_mock_')) {
            final success = await ApiService.verifyLargePartyPayment(
              id,
              razorpayOrderId: orderId,
              razorpayPaymentId: 'mock_payment',
              razorpaySignature: 'mock_signature',
            );
            if (mounted) setState(() => _isPaying = false);
            if (success) await _fetchTicketData();
            return;
          }

          _razorpay?.open({
            'key': razorpayKey,
            'order_id': orderId,
            'amount': orderData['amount'],
            'name': 'Lunara – Group Party',
            'description': 'Group Party at $venueName',
            'prefill': {'contact': widget.booking['mobileNumber']?.toString() ?? ''},
            'theme': {'color': '#7C3AED'},
          });
        } else if (mounted) {
          setState(() => _isPaying = false);
        }
      },
      onHybridPayment: (shortfall) async {
        setState(() => _isPaying = true);
        final result = await ApiService.initiateLargePartyPayment(id);
        if (result != null && result['success'] == true) {
          final orderData = result['order'] ?? result['data'] ?? result;
          final razorpayKey = result['razorpayKeyId']?.toString() ?? orderData['key']?.toString() ?? '';
          _razorpay?.open({
            'key': razorpayKey,
            'order_id': orderData['razorpayOrderId']?.toString() ?? orderData['id']?.toString(),
            'amount': (shortfall * 100).toInt(),
            'name': 'Lunara – Group Party Shortfall',
            'description': 'Group Party Shortfall at $venueName',
            'prefill': {'contact': widget.booking['mobileNumber']?.toString() ?? ''},
            'theme': {'color': '#7C3AED'},
          });
        } else if (mounted) {
          setState(() => _isPaying = false);
        }
      },
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: ${response.message ?? 'Please try again'}'), backgroundColor: Colors.red),
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
    if (_paymentState == _LargePartyPaymentState.expired) {
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

  Map<String, dynamic> _resolveHostUser() {
    if (_freshHostUser != null && _freshHostUser!.isNotEmpty) {
      return _freshHostUser!;
    }
    if (widget.booking['host'] is Map) return Map<String, dynamic>.from(widget.booking['host']);
    if (widget.booking['user'] is Map) return Map<String, dynamic>.from(widget.booking['user']);
    if (widget.booking['customer'] is Map) return Map<String, dynamic>.from(widget.booking['customer']);
    return <String, dynamic>{};
  }

  void _shareTicket(BuildContext context) {
    final venueMap = _freshVenue ?? (widget.venue.isNotEmpty ? Map<String, dynamic>.from(widget.venue) : (widget.booking['venue'] is Map ? Map<String, dynamic>.from(widget.booking['venue']) : <String, dynamic>{}));
    final venueName = venueMap['name']?.toString() ?? widget.venue['name']?.toString() ?? 'Venue';
    final rawDate = widget.booking['bookingDate'] ?? widget.booking['partyDate'];
    DateTime planDateTime = DateTime.now();
    if (rawDate != null) {
      try {
        planDateTime = DateTime.parse(rawDate.toString()).toLocal();
      } catch (_) {}
    }
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

    final rawDate = widget.booking['bookingDate'] ?? widget.booking['partyDate'];
    DateTime planDateTime = DateTime.now();
    if (rawDate != null) {
      try {
        planDateTime = DateTime.parse(rawDate.toString()).toLocal();
      } catch (_) {}
    }

    final ticketId = (_canonicalTicketCode ?? widget.booking['ticketCode'] ?? widget.booking['id'] ?? 'GP-TICKET').toString().toUpperCase();
    final double totalAmount = _freshTotalAmount ??
        double.tryParse((widget.booking['totalAmount'] ?? widget.booking['depositAmount'] ?? widget.booking['approvedAmount'] ?? widget.booking['charges'] ?? 0).toString()) ??
        0.0;

    // Standardized Participant Calculation:
    // If total is 14: Host = 1, Members = 13, Total = 14
    final rawGuestsCount = _freshTotalParticipants ?? widget.booking['totalParticipants'] ?? widget.booking['numberOfFriends'] ?? widget.booking['numberOfGuests'] ?? widget.booking['numberOfPersons'] ?? 5;
    final int totalParticipants = rawGuestsCount is int ? rawGuestsCount : (int.tryParse(rawGuestsCount.toString()) ?? 5);
    final int memberCount = _freshMemberCount ?? (totalParticipants > 1 ? totalParticipants - 1 : 1);

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

    final bool isFreeParty = totalAmount <= 0;
    final bool isAwaitingPayment = _paymentState == _LargePartyPaymentState.awaitingPayment;
    final bool isExpired = _paymentState == _LargePartyPaymentState.expired;
    final double amountDue = _amountDue ?? totalAmount;
    final paymentMethodLabel = isFreeParty
        ? 'FREE (Complimentary)'
        : isAwaitingPayment
            ? 'Awaiting Payment'
            : isExpired
                ? 'Expired — Not Paid'
                : (_freshPaymentMethod ??
                    (widget.booking['paymentId']?.toString().startsWith('wallet_') == true ? 'LUNARA Wallet' : 'Lunara Secure Pay'));

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
        title: const Text(
          'GROUP PARTY TICKET',
          style: TextStyle(
            color: darkTextColor,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            fontSize: 16,
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
                topSection: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Pill & Ticket Code
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0EBFF),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('🎉 ', style: TextStyle(fontSize: 10)),
                                Text(
                                  'VIP GROUP PARTY',
                                  style: TextStyle(
                                    color: Color(0xFF6D28D9),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          RichText(
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
                      const Text(
                        'Get ready for an epic night with your crew.',
                        style: TextStyle(
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
                                value: DateFormat('MMM dd, yyyy').format(planDateTime),
                                subtext: DateFormat('EEEE').format(planDateTime),
                              ),
                            ),
                            Container(height: 36, width: 1, color: const Color(0xFFE2E8F0)),
                            // TIME
                            Expanded(
                              child: _buildLightDetailBox(
                                icon: Icons.access_time_rounded,
                                label: 'TIME',
                                value: DateFormat('hh:mm a').format(planDateTime),
                                subtext: 'Onwards',
                              ),
                            ),
                            Container(height: 36, width: 1, color: const Color(0xFFE2E8F0)),
                            // PARTICIPANTS (1 Host + 13 Members = 14 Total)
                            Expanded(
                              child: _buildLightDetailBox(
                                icon: Icons.groups_rounded,
                                label: 'PARTICIPANTS',
                                value: '$totalParticipants Members',
                                subtext: '1 Host + $memberCount Friends',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
                                    '$totalParticipants Participants',
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
                                    '1 Host + $memberCount Members',
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
                                        const Text(
                                          'BOOKING STATUS',
                                          style: TextStyle(
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
                                  isAwaitingPayment || isExpired ? 'AMOUNT DUE' : 'TOTAL PAID',
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

              if (isExpired) ...[
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
