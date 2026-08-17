import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/google_places_service.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../widgets/lunara_ticket_widget.dart';
import '../../services/api_service.dart';

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

  @override
  void initState() {
    super.initState();
    _initLocation();
    _initCountdown();
    _fetchTicketData();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
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
    final gpId = (widget.booking['id'] ?? widget.booking['partyId'] ?? widget.booking['groupPartyId'] ?? widget.booking['bookingId'])?.toString();
    if (gpId == null) return;
    try {
      final response = await ApiService.get('/api/mobile/group-parties/$gpId/ticket');
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

  void _shareTicket(BuildContext context) {
    final gpId = (widget.booking['id'] ?? widget.booking['partyId'] ?? widget.booking['groupPartyId'] ?? widget.booking['bookingId'])?.toString() ?? '';
    final ticketId = (_canonicalTicketCode ?? widget.booking['ticketCode'] ?? widget.booking['id'] ?? 'TICKET').toString().toUpperCase();

    String? rawUrl = _ticketUrl ?? widget.booking['ticketUrl'] ?? widget.booking['ticket_url'];
    String shareLink = '';

    if (rawUrl != null && rawUrl.toString().trim().isNotEmpty) {
      final str = rawUrl.toString().trim();
      if (str.startsWith('http://') || str.startsWith('https://')) {
        shareLink = str;
      } else {
        shareLink = '${ApiService.baseUrl}${str.startsWith('/') ? '' : '/'}$str';
      }
    } else {
      shareLink = '${ApiService.baseUrl}/api/mobile/group-parties/$gpId/ticket';
    }

    final box = context.findRenderObject() as RenderBox?;
    Share.share(
      shareLink,
      subject: 'Lunara Group Party Ticket ($ticketId)',
      sharePositionOrigin: box != null ? box.localToGlobal(Offset.zero) & box.size : null,
    );
  }

  Widget _buildCountdownBadge() {
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
    final paymentMethodLabel = isFreeParty
        ? 'FREE (Complimentary)'
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
              LunaraTicketWidget(
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
                                const Text(
                                  'TOTAL PAID',
                                  style: TextStyle(
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
                                      isFreeParty ? 'FREE' : '₹${totalAmount.toStringAsFixed(totalAmount.truncateToDouble() == totalAmount ? 0 : 2)}',
                                      style: TextStyle(
                                        color: isFreeParty ? const Color(0xFF1D4ED8) : const Color(0xFF15803D),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isFreeParty ? const Color(0xFFDEEBFF) : const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isFreeParty ? 'FREE' : 'PAID',
                                        style: TextStyle(
                                          color: isFreeParty ? const Color(0xFF1D4ED8) : const Color(0xFF15803D),
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

              const SizedBox(height: 28),

              // ── ACTION BUTTONS BELOW TICKET ────────────────────────────────
              if ((_ticketUrl ?? widget.booking['ticketUrl']) != null &&
                  (_ticketUrl ?? widget.booking['ticketUrl']).toString().isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final url = (_ticketUrl ?? widget.booking['ticketUrl']).toString();
                      final pdfUri = Uri.parse(url);
                      if (await canLaunchUrl(pdfUri)) {
                        await launchUrl(pdfUri, mode: LaunchMode.externalApplication);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Could not open the PDF URL.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                    label: const Text(
                      'DOWNLOAD PDF TICKET',
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
              ],
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
