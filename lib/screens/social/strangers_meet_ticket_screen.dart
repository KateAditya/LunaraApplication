import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/google_places_service.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/strangers_meet_request.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../widgets/lunara_ticket_widget.dart';
import '../../services/api_service.dart';
import '../../services/lunara_ticket_capture_service.dart';

class StrangersMeetTicketScreen extends StatefulWidget {
  final StrangersMeetRequest request;

  const StrangersMeetTicketScreen({super.key, required this.request});

  @override
  State<StrangersMeetTicketScreen> createState() => _StrangersMeetTicketScreenState();
}

class _StrangersMeetTicketScreenState extends State<StrangersMeetTicketScreen> {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;

  // Countdown timer
  Timer? _countdownTimer;
  Duration _timeRemaining = Duration.zero;

  // Fresh backend ticket data
  Map<String, dynamic>? _freshHostUser;
  Map<String, dynamic>? _freshVenue;
  DateTime? _freshEventDateTime;
  String? _freshStartTime;
  String? _canonicalTicketCode;
  int? _freshPersonsCount;
  String? _freshSubject;
  String? _freshTagline;
  double? _freshAmountPaid;
  String? _freshPaymentStatus;
  String? _freshStatus;
  int? _freshTargetCapacity;
  final GlobalKey _ticketKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _prefillFromWidget();
    _initLocation();
    _initCountdown();
    _fetchTicketData();
  }

  void _prefillFromWidget() {
    _freshSubject = widget.request.subject;
    _freshTagline = widget.request.tagline;
    _freshAmountPaid = (widget.request.paymentAmount ?? widget.request.chargesPerHead).toDouble();
    _freshPaymentStatus = widget.request.paymentStatus;
    _freshStatus = widget.request.status;
    _freshEventDateTime = widget.request.eventDateTime;
    _canonicalTicketCode = widget.request.ticketId;
    _freshTargetCapacity = widget.request.numberOfPersons;
    if (widget.request.venue != null) {
      _freshVenue = Map<String, dynamic>.from(widget.request.venue!);
    }
    if (widget.request.user != null) {
      _freshHostUser = Map<String, dynamic>.from(widget.request.user!);
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  DateTime _parseEventDateTime(dynamic rawDate, dynamic rawTime) {
    DateTime baseDate = DateTime.now();
    if (rawDate != null) {
      if (rawDate is DateTime) {
        baseDate = rawDate.toLocal();
      } else {
        try {
          baseDate = DateTime.parse(rawDate.toString()).toLocal();
        } catch (_) {}
      }
    }

    if (rawTime != null && rawTime.toString().trim().isNotEmpty) {
      final tStr = rawTime.toString().trim();
      final isPm = tStr.toUpperCase().contains('PM');
      final isAm = tStr.toUpperCase().contains('AM');
      final cleanTime = tStr.toUpperCase().replaceAll('AM', '').replaceAll('PM', '').trim();
      final parts = cleanTime.split(':');
      if (parts.isNotEmpty) {
        int? h = int.tryParse(parts[0].trim());
        int m = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 0) : 0;
        if (h != null) {
          if (isPm && h < 12) h += 12;
          if (isAm && h == 12) h = 0;
          return DateTime(baseDate.year, baseDate.month, baseDate.day, h, m);
        }
      }
    } else if (baseDate.hour == 0 && baseDate.minute == 0) {
      // Default to 8:00 PM evening start if date-only was parsed
      return DateTime(baseDate.year, baseDate.month, baseDate.day, 20, 0);
    }
    return baseDate;
  }

  void _initCountdown() {
    final eventDate = _parseEventDateTime(_freshEventDateTime ?? widget.request.eventDateTime, _freshStartTime);
    void update() {
      if (!mounted) return;
      final remaining = eventDate.difference(DateTime.now());
      setState(() {
        _timeRemaining = remaining.isNegative ? Duration.zero : remaining;
      });
    }

    _countdownTimer?.cancel();
    update();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => update());
  }

  Future<void> _fetchTicketData() async {
    final rawId = widget.request.id;
    if (rawId.isEmpty) return;
    try {
      final cleanId = rawId.replaceFirst('strangers_meet_', '').trim();
      final response = await ApiService.get('/api/mobile/strangers-meet/requests/$cleanId/ticket');
      if (response.statusCode == 200 && mounted) {
        final mapData = jsonDecode(response.body);
        if (mapData != null && mapData['data'] != null) {
          final ticketObj = mapData['data'];
          final reqObj = ticketObj['request'];
          setState(() {
            if (reqObj is Map && reqObj['host'] is Map) {
              _freshHostUser = Map<String, dynamic>.from(reqObj['host']);
            }
            if (reqObj is Map && reqObj['venue'] is Map) {
              _freshVenue = Map<String, dynamic>.from(reqObj['venue']);
            }
            _canonicalTicketCode = ticketObj['ticketCode']?.toString() ?? reqObj?['ticketCode']?.toString();
            if (reqObj is Map) {
              final rawDt = reqObj['eventDateTime'] ?? reqObj['event_date_time'];
              if (rawDt != null) {
                final parsed = DateTime.tryParse(rawDt.toString())?.toLocal();
                if (parsed != null) _freshEventDateTime = parsed;
              }
              final rawSt = reqObj['startTime'] ?? reqObj['partyTime'] ?? reqObj['time'];
              if (rawSt != null && rawSt.toString().trim().isNotEmpty) {
                _freshStartTime = rawSt.toString().trim();
              }
              final dynamicCount = ticketObj['actualParticipantsCount'] ??
                  ticketObj['joinedCount'] ??
                  ticketObj['numberOfPersons'] ??
                  reqObj['actualParticipantsCount'] ??
                  reqObj['joinedCount'] ??
                  reqObj['slotsFilled'] ??
                  reqObj['numberOfPersons'];
              if (dynamicCount != null) {
                _freshPersonsCount = int.tryParse(dynamicCount.toString());
              }
              final rawSubject = reqObj['subject']?.toString();
              if (rawSubject != null && rawSubject.trim().isNotEmpty) {
                _freshSubject = rawSubject.trim();
              }
              final rawTagline = reqObj['tagline']?.toString();
              if (rawTagline != null && rawTagline.trim().isNotEmpty) {
                _freshTagline = rawTagline.trim();
              }
              final rawAmt = reqObj['paymentAmount'] ?? reqObj['totalAmount'] ?? reqObj['chargesPerHead'] ?? ticketObj['paymentAmount'] ?? ticketObj['totalAmount'];
              if (rawAmt != null) {
                final parsedAmt = double.tryParse(rawAmt.toString());
                if (parsedAmt != null) {
                  _freshAmountPaid = parsedAmt;
                }
              }
              final rawPayStatus = reqObj['paymentStatus']?.toString() ?? ticketObj['paymentStatus']?.toString();
              if (rawPayStatus != null) _freshPaymentStatus = rawPayStatus;

              final rawStatus = reqObj['status']?.toString() ?? ticketObj['status']?.toString();
              if (rawStatus != null) _freshStatus = rawStatus;

              final rawTarget = reqObj['targetCapacity'] ?? reqObj['capacity'] ?? reqObj['numberOfPersons'] ?? ticketObj['targetCapacity'] ?? ticketObj['numberOfPersons'];
              if (rawTarget != null) {
                _freshTargetCapacity = int.tryParse(rawTarget.toString());
              }
            }
          });
          _initCountdown();
        }
      }
    } catch (e) {
      debugPrint('_fetchTicketData error for StrangersMeet: $e');
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
      debugPrint("Error in StrangersMeetTicketScreen location initialization: $e");
    }
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
              'MEETUP LIVE!',
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
    if (widget.request.user != null && widget.request.user!.isNotEmpty) {
      return Map<String, dynamic>.from(widget.request.user!);
    }
    final myUser = ApiService.cachedCurrentUser;
    if (myUser != null) {
      final fName = myUser.firstName;
      final lName = myUser.lastName;
      final fullN = '$fName $lName'.trim();
      return <String, dynamic>{
        'id': myUser.id,
        'firstName': fName,
        'lastName': lName,
        'fullName': fullN.isNotEmpty ? fullN : 'Meetup Host',
        'name': fullN.isNotEmpty ? fullN : 'Meetup Host',
        'username': myUser.displayName ?? (fName.isNotEmpty ? fName.toLowerCase() : 'user'),
        'profilePhotoUrl': myUser.profilePhoto,
        'profileImageUrl': myUser.profilePhoto,
        'profilePhoto': myUser.profilePhoto,
        'image': myUser.profilePhoto,
        'phone': myUser.phone,
        'mobileNumber': myUser.phone,
        'email': myUser.email,
        'bio': myUser.bio,
      };
    }
    return <String, dynamic>{};
  }

  void _shareTicket(BuildContext context) {
    final venueMap = _freshVenue ?? widget.request.venue ?? {};
    final venueName = venueMap['name'] ?? 'Venue';
    final eventDateTime = _parseEventDateTime(_freshEventDateTime ?? widget.request.eventDateTime, _freshStartTime);
    final eventDateTimeFormatted = DateFormat('MMM dd, yyyy • hh:mm a').format(eventDateTime);
    final ticketId = (_canonicalTicketCode ?? widget.request.ticketId ?? 'SM-PASS').toUpperCase();
    final hostUser = _resolveHostUser();
    final hostName = '${hostUser['firstName'] ?? ''} ${hostUser['lastName'] ?? ''}'.trim();
    final dynamicCount = _freshPersonsCount ?? widget.request.actualParticipantsCount;

    LunaraTicketCaptureService.shareTicket(
      context: context,
      ticketKey: _ticketKey,
      ticketCode: ticketId,
      venueName: venueName,
      eventDateTime: eventDateTimeFormatted,
      eventType: 'Strangers Meet',
      hostName: hostName.isNotEmpty ? hostName : 'Event Host',
      guestCount: '$dynamicCount Attendees',
    );
  }

  @override
  Widget build(BuildContext context) {
    final venueMap = _freshVenue ?? widget.request.venue ?? {};
    final venueName = venueMap['name'] ?? 'Unknown Venue';
    final venueCity = venueMap['city'] ?? 'Pune';
    final venueArea = venueMap['area'] ?? '';
    final venueAddress = venueMap['address'] ??
        venueMap['addressLine1'] ??
        '${venueArea.isNotEmpty ? "$venueArea, " : ""}$venueCity, Maharashtra 411001';

    final ticketId = (_canonicalTicketCode ?? widget.request.ticketId ?? 'SM-TICKET').toUpperCase();
    final double amountPaid = (_freshAmountPaid ?? (widget.request.paymentAmount ?? widget.request.chargesPerHead)).toDouble();
    final int targetCapacity = _freshTargetCapacity ?? widget.request.numberOfPersons;
    final int dynamicCount = _freshPersonsCount ?? widget.request.actualParticipantsCount;
    final String subjectText = (_freshSubject != null && _freshSubject!.isNotEmpty) ? _freshSubject! : widget.request.subject;
    final String taglineText = (_freshTagline != null && _freshTagline!.isNotEmpty) ? _freshTagline! : widget.request.tagline;
    final String memberLabel = '$dynamicCount ${dynamicCount == 1 ? "Person" : "Persons"}';
    final String memberSubtext = targetCapacity > dynamicCount ? '$dynamicCount Joined • Max $targetCapacity' : 'Confirmed';
    final DateTime eventDateTime = _parseEventDateTime(_freshEventDateTime ?? widget.request.eventDateTime, _freshStartTime);

    final hostUser = _resolveHostUser();
    final hostNameRaw = '${hostUser['firstName'] ?? ''} ${hostUser['lastName'] ?? ''}'.trim();
    final cleanHostName = hostNameRaw.isNotEmpty ? hostNameRaw : 'Event Host';
    final hostUsernameRaw = hostUser['username']?.toString() ?? hostUser['firstName']?.toString().toLowerCase();
    final hostUsername = hostUsernameRaw != null && hostUsernameRaw.isNotEmpty
        ? (hostUsernameRaw.startsWith('@') ? hostUsernameRaw : '@$hostUsernameRaw')
        : '@host';

    final latVal = widget.request.venue?['latitude'];
    final lngVal = widget.request.venue?['longitude'];
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
          'STRANGERS MEET TICKET',
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
                                      'STRANGERS MEET',
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

                      // Headline & Tagline
                      Text(
                        '🎉 $subjectText',
                        style: const TextStyle(
                          color: darkTextColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        taglineText.isNotEmpty
                            ? taglineText
                            : 'Meet amazing new people at $venueName.',
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
                                value: DateFormat('MMM dd, yyyy').format(eventDateTime),
                                subtext: DateFormat('EEEE').format(eventDateTime),
                              ),
                            ),
                            Container(height: 36, width: 1, color: const Color(0xFFE2E8F0)),
                            // TIME
                            Expanded(
                              child: _buildLightDetailBox(
                                icon: Icons.access_time_rounded,
                                label: 'TIME',
                                value: DateFormat('hh:mm a').format(eventDateTime),
                                subtext: 'Onwards',
                              ),
                            ),
                            Container(height: 36, width: 1, color: const Color(0xFFE2E8F0)),
                            // MEMBERS / PERSONS
                            Expanded(
                              child: _buildLightDetailBox(
                                icon: Icons.groups_rounded,
                                label: 'MEMBERS',
                                value: memberLabel,
                                subtext: memberSubtext,
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
                      // ── SINGLE PROFILE SECTION (EVENT HOST + MEET SIZE) ───
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Event Host Column (Left)
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
                                      'EVENT HOST',
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

                            // Meet Size Column (Right)
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
                                      'MEET SIZE',
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
                                    memberLabel,
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
                                    targetCapacity > dynamicCount ? '$dynamicCount of $targetCapacity Joined' : 'Strangers Meet',
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
                                          (_freshPaymentStatus != null && _freshPaymentStatus!.isNotEmpty && _freshPaymentStatus!.toLowerCase() == 'pending')
                                              ? 'Payment Pending'
                                              : (_freshStatus != null && _freshStatus!.toLowerCase() == 'cancelled'
                                                  ? 'Cancelled'
                                                  : 'Lunara Secure Pay'),
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
                                  amountPaid <= 0 ? 'ENTRY FEE' : 'TOTAL PAID',
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
                                      amountPaid <= 0
                                          ? 'FREE'
                                          : '₹${amountPaid.toStringAsFixed(amountPaid.truncateToDouble() == amountPaid ? 0 : 2)}',
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
                                      child: Text(
                                        amountPaid <= 0 ? 'FREE ENTRY' : 'PAID',
                                        style: const TextStyle(
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
                                      'Strangers Meet Entry',
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
                                      '${DateFormat('MMM dd, yyyy').format(eventDateTime)} • ${DateFormat('hh:mm a').format(eventDateTime)}',
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

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final venueName = widget.request.venue?['name'] ?? 'Venue';
                      final eventDateTime = DateFormat('MMM dd, yyyy • hh:mm a').format(widget.request.eventDateTime);
                      final ticketId = (_canonicalTicketCode ?? widget.request.ticketId ?? 'SM-PASS').toUpperCase();
                      LunaraTicketCaptureService.downloadTicket(
                        context: context,
                        ticketKey: _ticketKey,
                        ticketCode: ticketId,
                        eventType: 'Strangers_Meet',
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
