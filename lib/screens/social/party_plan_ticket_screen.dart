import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/google_places_service.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../widgets/lunara_ticket_widget.dart';
import '../../services/api_service.dart';
import '../../services/lunara_ticket_capture_service.dart';
import '../../utils/lunara_date_formatter.dart';

class PartyPlanTicketScreen extends StatefulWidget {
  final Map<dynamic, dynamic> request;
  final Map<dynamic, dynamic> plan;
  final bool isHost;

  const PartyPlanTicketScreen({
    super.key,
    required this.request,
    required this.plan,
    required this.isHost,
  });

  @override
  State<PartyPlanTicketScreen> createState() => _PartyPlanTicketScreenState();
}

class _PartyPlanTicketScreenState extends State<PartyPlanTicketScreen> {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;

  // ── Countdown to party ─────────────────────────────────────────────────────
  Timer? _countdownTimer;
  Duration _timeRemaining = Duration.zero;

  // ── Backend-refreshed ticket data ─────────────────────────────────────────
  Map<String, dynamic>? _freshHostUser;
  Map<String, dynamic>? _freshJoinerUser;
  String? _canonicalTicketCode;
  final GlobalKey _ticketKey = GlobalKey();

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

  // ── Countdown logic ────────────────────────────────────────────────────────
  void _initCountdown() {
    final rawDate = widget.plan['planDateTime'] ??
        widget.plan['eventStartAt'] ??
        widget.plan['bookingDate'] ??
        widget.request['planDateTime'] ??
        widget.request['eventStartAt'] ??
        widget.request['bookingDate'];
    final rawTime = widget.plan['startTime'] ??
        widget.plan['time'] ??
        widget.request['startTime'] ??
        widget.request['time'];
    final planDateTime = LunaraDateFormatter.parseToLocal(rawDate, explicitTime: rawTime?.toString());
    if (planDateTime == null) return;

    final expirationTime = planDateTime.add(const Duration(hours: 2));

    void update() {
      if (!mounted) return;
      final remaining = expirationTime.difference(DateTime.now());
      setState(() {
        _timeRemaining = remaining.isNegative ? Duration.zero : remaining;
      });
    }

    update();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => update());
  }

  // ── Fetch fresh profile photos + ticketCode from backend ───────────────────
  Future<void> _fetchTicketData() async {
    final rawId = widget.request['ticketCode']?.toString() ??
        widget.plan['ticketCode']?.toString() ??
        widget.request['ticketId']?.toString() ??
        widget.plan['ticketId']?.toString() ??
        widget.request['bookingId']?.toString() ??
        widget.plan['bookingId']?.toString() ??
        widget.plan['matchedRequestId']?.toString() ??
        widget.request['id']?.toString() ??
        widget.request['reqId']?.toString() ??
        widget.request['planId']?.toString() ??
        widget.plan['planId']?.toString() ??
        widget.plan['id']?.toString();
    if (rawId == null) return;
    if (!mounted) return;
    try {
      final cleanId = rawId.replaceFirst('party_plan_host_', '').replaceFirst('party_plan_joiner_', '').trim();
      final data = await ApiService.fetchPartyPlanTicket(cleanId);
      if (data != null && mounted) {
        setState(() {
          final planData = data['plan'];
          final requestData = data['request'];

          final hostObj = data['host'] ??
              data['creator'] ??
              (planData is Map
                  ? (planData['host'] ?? planData['creator'] ?? planData['user'])
                  : null);
          if (hostObj is Map) {
            _freshHostUser = Map<String, dynamic>.from(hostObj);
          }

          final joinerObj = data['joiner'] ??
              data['partner'] ??
              data['requester'] ??
              data['matchedJoiner'] ??
              (requestData is Map
                  ? (requestData['requester'] ?? requestData['joiner'] ?? requestData['partner'] ?? requestData['user'])
                  : null) ??
              (planData is Map
                  ? (planData['matchedJoiner'] ?? planData['partner'] ?? planData['joiner'])
                  : null);
          if (joinerObj is Map) {
            _freshJoinerUser = Map<String, dynamic>.from(joinerObj);
          }

          _canonicalTicketCode = data['ticketCode']?.toString() ?? data['ticketId']?.toString();
        });
      }
    } catch (e) {
      debugPrint('_fetchTicketData error: $e');
    }
  }

  // ── Countdown display badge (Light Mode) ──────────────────────────────────
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

    final d = _timeRemaining.inDays;
    final h = _timeRemaining.inHours.remainder(24);
    final m = _timeRemaining.inMinutes.remainder(60);
    final s = _timeRemaining.inSeconds.remainder(60);

    final String label = d > 0
        ? '${d}d ${h}h ${m}m'
        : h > 0
            ? '${h}h ${m}m ${s}s'
            : '${m}m ${s}s';

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
      debugPrint("Error in PartyPlanTicketScreen location initialization: $e");
    }
  }

  void _shareTicket(BuildContext context) {
    final venue = widget.plan['venue'] ?? {};
    final venueName = venue['name'] ?? 'Venue';
    final planDateTime = widget.plan['planDateTime'] != null
        ? DateFormat('MMM dd, yyyy • hh:mm a').format(
            DateTime.tryParse(widget.plan['planDateTime'].toString())?.toLocal() ?? DateTime.now(),
          )
        : '';
    final ticketId = (_canonicalTicketCode ?? widget.request['id']?.toString() ?? 'PP-PASS').toUpperCase();
    final hostUser = _resolveHostUser();
    final hostName = '${hostUser['firstName'] ?? ''} ${hostUser['lastName'] ?? ''}'.trim();

    LunaraTicketCaptureService.shareTicket(
      context: context,
      ticketKey: _ticketKey,
      ticketCode: ticketId,
      venueName: venueName,
      eventDateTime: planDateTime,
      eventType: 'Party Plan',
      hostName: hostName.isNotEmpty ? hostName : 'Party Host',
      guestCount: '2 Guests (Confirmed)',
    );
  }

  // ── Helper to resolve Host User object robustly ────────────────────────────
  Map<String, dynamic> _resolveHostUser() {
    if (_freshHostUser != null && _freshHostUser!.isNotEmpty) {
      return _freshHostUser!;
    }
    if (widget.plan['host'] is Map && (widget.plan['host'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(widget.plan['host']);
    }
    if (widget.plan['creator'] is Map && (widget.plan['creator'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(widget.plan['creator']);
    }
    if (widget.request['host'] is Map && (widget.request['host'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(widget.request['host']);
    }
    if (widget.request['creator'] is Map && (widget.request['creator'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(widget.request['creator']);
    }
    if (widget.request['plan'] is Map) {
      final p = widget.request['plan'];
      if (p['host'] is Map && (p['host'] as Map).isNotEmpty) return Map<String, dynamic>.from(p['host']);
      if (p['creator'] is Map && (p['creator'] as Map).isNotEmpty) return Map<String, dynamic>.from(p['creator']);
      if (p['user'] is Map && (p['user'] as Map).isNotEmpty) return Map<String, dynamic>.from(p['user']);
    }
    if (widget.plan['user'] is Map && widget.isHost && (widget.plan['user'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(widget.plan['user']);
    }

    final myUser = ApiService.cachedCurrentUser;
    final planUserId = widget.plan['userId']?.toString() ??
        widget.plan['creatorId']?.toString() ??
        widget.request['plan']?['userId']?.toString() ??
        widget.request['plan']?['creatorId']?.toString() ??
        widget.request['userId']?.toString();

    final isMe = widget.isHost || (myUser != null && planUserId != null && planUserId == myUser.id);
    if (isMe && myUser != null) {
      return <String, dynamic>{
        'id': myUser.id,
        'firstName': myUser.firstName,
        'lastName': myUser.lastName,
        'username': myUser.displayName ?? myUser.firstName.toLowerCase(),
        'profilePhotoUrl': myUser.profilePhoto,
        'profileImageUrl': myUser.profilePhoto,
        'image': myUser.profilePhoto,
        'bio': myUser.bio,
      };
    }

    if (widget.plan['user'] is Map && (widget.plan['user'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(widget.plan['user']);
    }

    return <String, dynamic>{};
  }

  // ── Helper to resolve Joiner/Partner User object robustly ──────────────────
  Map<String, dynamic> _resolveJoinerUser(Map<String, dynamic> hostUser) {
    if (_freshJoinerUser != null && _freshJoinerUser!.isNotEmpty) {
      return _freshJoinerUser!;
    }
    if (widget.request['requester'] is Map && (widget.request['requester'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(widget.request['requester']);
    }
    if (widget.request['joiner'] is Map && (widget.request['joiner'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(widget.request['joiner']);
    }
    if (widget.request['partner'] is Map && (widget.request['partner'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(widget.request['partner']);
    }
    if (widget.plan['partner'] is Map && (widget.plan['partner'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(widget.plan['partner']);
    }
    if (widget.plan['matchedJoiner'] is Map && (widget.plan['matchedJoiner'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(widget.plan['matchedJoiner']);
    }
    if (widget.plan['joiner'] is Map && (widget.plan['joiner'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(widget.plan['joiner']);
    }
    if (widget.request['matchedJoiner'] is Map && (widget.request['matchedJoiner'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(widget.request['matchedJoiner']);
    }
    if (widget.request['user'] is Map && (widget.request['user'] as Map).isNotEmpty) {
      final cand = Map<String, dynamic>.from(widget.request['user']);
      final hostId = hostUser['id']?.toString();
      final candId = cand['id']?.toString();
      if (hostId == null || candId == null || hostId != candId) {
        return cand;
      }
    }
    if (widget.plan['user'] is Map && (widget.plan['user'] as Map).isNotEmpty) {
      final cand = Map<String, dynamic>.from(widget.plan['user']);
      final hostId = hostUser['id']?.toString();
      final candId = cand['id']?.toString();
      if (hostId == null || candId == null || hostId != candId) {
        return cand;
      }
    }

    final myUser = ApiService.cachedCurrentUser;
    if (!widget.isHost && myUser != null) {
      return <String, dynamic>{
        'id': myUser.id,
        'firstName': myUser.firstName,
        'lastName': myUser.lastName,
        'username': myUser.displayName ?? myUser.firstName.toLowerCase(),
        'profilePhotoUrl': myUser.profilePhoto,
        'profileImageUrl': myUser.profilePhoto,
        'image': myUser.profilePhoto,
        'bio': myUser.bio,
      };
    }

    return <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final venue = (widget.plan['venue'] is Map ? widget.plan['venue'] : null) ??
        (widget.request['venue'] is Map ? widget.request['venue'] : null) ??
        {};
    final venueName = venue['name'] ?? 'Lunara Venue';
    final venueCity = venue['city'] ?? 'Pune';
    final venueArea = venue['area'] ?? '';
    final venueAddress = venue['address'] ??
        venue['addressLine1'] ??
        '${venueArea.isNotEmpty ? "$venueArea, " : ""}$venueCity, Maharashtra 411057';

    final rawDate = widget.plan['planDateTime'] ??
        widget.plan['eventStartAt'] ??
        widget.plan['bookingDate'] ??
        widget.plan['partyDate'] ??
        widget.request['planDateTime'] ??
        widget.request['eventStartAt'] ??
        widget.request['bookingDate'] ??
        widget.request['partyDate'];
    final rawTime = widget.plan['startTime'] ??
        widget.plan['time'] ??
        widget.plan['partyTime'] ??
        widget.request['startTime'] ??
        widget.request['time'] ??
        widget.request['partyTime'];

    final DateTime planDateTime = LunaraDateFormatter.parseToLocal(rawDate, explicitTime: rawTime?.toString()) ?? DateTime.now();

    final hostUser = _resolveHostUser();
    final hostFirstName = hostUser['firstName']?.toString() ?? '';
    final hostLastName = hostUser['lastName']?.toString() ?? '';
    final hostNameRaw = '$hostFirstName $hostLastName'.trim();
    final cleanHostName = hostNameRaw.isNotEmpty
        ? hostNameRaw
        : (hostUser['name']?.toString() ??
            (widget.isHost && ApiService.cachedCurrentUser != null
                ? '${ApiService.cachedCurrentUser!.firstName} ${ApiService.cachedCurrentUser!.lastName}'.trim()
                : 'Host User'));
    final hostUsernameRaw = hostUser['username']?.toString() ??
        hostUser['displayName']?.toString() ??
        (hostFirstName.isNotEmpty ? hostFirstName.toLowerCase() : null);
    final hostUsername = hostUsernameRaw != null && hostUsernameRaw.isNotEmpty
        ? (hostUsernameRaw.startsWith('@') ? hostUsernameRaw : '@$hostUsernameRaw')
        : (widget.isHost && ApiService.cachedCurrentUser != null
            ? '@${(ApiService.cachedCurrentUser!.displayName ?? ApiService.cachedCurrentUser!.firstName).toLowerCase()}'
            : '@host');

    final joinerUser = _resolveJoinerUser(hostUser);
    final joinerFirstName = joinerUser['firstName']?.toString() ?? '';
    final joinerLastName = joinerUser['lastName']?.toString() ?? '';
    final joinerNameRaw = '$joinerFirstName $joinerLastName'.trim();
    final cleanJoinerName = joinerNameRaw.isNotEmpty
        ? joinerNameRaw
        : (joinerUser['name']?.toString() ??
            (!widget.isHost && ApiService.cachedCurrentUser != null
                ? '${ApiService.cachedCurrentUser!.firstName} ${ApiService.cachedCurrentUser!.lastName}'.trim()
                : 'Partner Guest'));
    final joinerUsernameRaw = joinerUser['username']?.toString() ??
        joinerUser['displayName']?.toString() ??
        (joinerFirstName.isNotEmpty ? joinerFirstName.toLowerCase() : null);
    final joinerUsername = joinerUsernameRaw != null && joinerUsernameRaw.isNotEmpty
        ? (joinerUsernameRaw.startsWith('@') ? joinerUsernameRaw : '@$joinerUsernameRaw')
        : (!widget.isHost && ApiService.cachedCurrentUser != null
            ? '@${(ApiService.cachedCurrentUser!.displayName ?? ApiService.cachedCurrentUser!.firstName).toLowerCase()}'
            : '@guest');

    final ticketId = (_canonicalTicketCode ??
        widget.request['ticketCode']?.toString() ??
        widget.plan['ticketCode']?.toString() ??
        widget.request['ticketId']?.toString() ??
        widget.plan['ticketId']?.toString() ??
        widget.request['bookingId']?.toString() ??
        widget.plan['bookingId']?.toString() ??
        widget.request['id']?.toString() ??
        'LUN-PARTY-PLAN').toUpperCase();
    final headlineText = "Let's party at $venueName!";

    final rawAmount = widget.request['paymentAmount'] ??
        widget.request['totalAmount'] ??
        widget.plan['depositAmount'] ??
        widget.plan['totalAmount'] ??
        widget.plan['paymentAmount'] ??
        widget.request['amountPaid'] ??
        widget.plan['amountPaid'] ??
        99.0;
    final rawPaymentType = (widget.plan['paymentType'] ??
            widget.plan['plan']?['paymentType'] ??
            widget.request['paymentType'] ??
            widget.request['plan']?['paymentType'] ??
            'split')
        .toString()
        .toLowerCase()
        .trim();
    final bool isSelfPay = rawPaymentType == 'self_pay' || rawPaymentType == 'self' || rawPaymentType == 'host_pay';

    final double amountPaid = double.tryParse(rawAmount.toString()) ?? 99.0;

    final bookingCreatedDate = widget.request['createdAt'] != null
        ? DateTime.tryParse(widget.request['createdAt'].toString())?.toLocal() ?? planDateTime
        : planDateTime;

    final latVal = venue['latitude'];
    final lngVal = venue['longitude'];
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
          'PARTY PLAN TICKET',
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
              // ── THE TICKET CARD (LIGHT THEME) ──────────────────────────────
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
                                      'LUNARA VIBE',
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
                                      text: ticketId.length > 12
                                          ? ticketId.substring(0, 12)
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

                      // Party Headline
                      Text(
                        '🎉 $headlineText',
                        style: const TextStyle(
                          color: darkTextColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Get ready for a night full of vibes and memories.',
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
                                value: rawTime != null && rawTime.toString().trim().isNotEmpty
                                    ? LunaraDateFormatter.normalizeTimeTo12Hour(rawTime.toString())
                                    : LunaraDateFormatter.formatEventTime(planDateTime),
                                subtext: 'Onwards',
                              ),
                            ),
                            Container(height: 36, width: 1, color: const Color(0xFFE2E8F0)),
                            // GUESTS
                            Expanded(
                              child: _buildLightDetailBox(
                                icon: Icons.group_rounded,
                                label: 'GUESTS',
                                value: '2 Going',
                                subtext: 'Confirmed',
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
                      // ── DUAL PROFILES SECTION (HOST & PARTNER) ─────────────
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
                                      'HOST',
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

                            // Middle Heart Connector
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF3E8FF),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.favorite_rounded,
                                color: Color(0xFF8B5CF6),
                                size: 16,
                              ),
                            ),

                            // Partner Column (Right)
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
                                      'PARTNER',
                                      style: TextStyle(
                                        color: Color(0xFF00838F),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  LunaraProfileImage(
                                    userData: joinerUser,
                                    radius: 30,
                                    showGradientBorder: true,
                                    borderWidth: 2,
                                    isInteractive: true,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    cleanJoinerName,
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
                                    joinerUsername,
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

                      // ── DEPOSIT STATUS CARD (GREEN TINT) ───────────────────
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
                                      children: const [
                                        Text(
                                          'DEPOSIT STATUS',
                                          style: TextStyle(
                                            color: grayTextColor,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Lunara Secure Pay',
                                          style: TextStyle(
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
                                  'AMOUNT PAID',
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
                                      '₹${amountPaid.toStringAsFixed(amountPaid.truncateToDouble() == amountPaid ? 0 : 2)}',
                                      style: const TextStyle(
                                        color: Color(0xFF15803D),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'PAID',
                                        style: TextStyle(
                                          color: Color(0xFF15803D),
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

                      // ── PARTY EXPENSES NOTE (SPLIT / SELF PAY) ─────────────
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelfPay ? const Color(0xFFFAF5FF) : const Color(0xFFF0F9FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelfPay ? const Color(0xFFE9D5FF) : const Color(0xFFBAE6FD),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelfPay ? const Color(0xFFF3E8FF) : const Color(0xFFE0F2FE),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isSelfPay ? Icons.volunteer_activism_rounded : Icons.call_split_rounded,
                                color: isSelfPay ? const Color(0xFF9333EA) : const Color(0xFF0284C7),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isSelfPay ? 'SELF PAY (HOST PAYS)' : 'SPLIT EXPENSES (50-50)',
                                    style: TextStyle(
                                      color: isSelfPay ? const Color(0xFF7E22CE) : const Color(0xFF0369A1),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isSelfPay
                                        ? 'The total expenses of this party will be paid by the host.'
                                        : 'The total expenses of this party will be split equally between both participants.',
                                    style: const TextStyle(
                                      color: darkTextColor,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ),
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
                                  final mapUrl = Uri.parse(
                                      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent("$venueName, $venueAddress")}');
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
                                        'Party Plan Entry',
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
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
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

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final venue = widget.plan['venue'] ?? {};
                      final venueName = venue['name'] ?? 'Venue';
                      final planDateTime = widget.plan['planDateTime'] != null
                          ? DateFormat('MMM dd, yyyy • hh:mm a').format(
                              DateTime.tryParse(widget.plan['planDateTime'].toString())?.toLocal() ?? DateTime.now(),
                            )
                          : '';
                      final ticketId = (_canonicalTicketCode ?? widget.request['id']?.toString() ?? 'PP-PASS').toUpperCase();
                      LunaraTicketCaptureService.downloadTicket(
                        context: context,
                        ticketKey: _ticketKey,
                        ticketCode: ticketId,
                        eventType: 'Party_Plan',
                        venueName: venueName,
                        eventDateTime: planDateTime,
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
