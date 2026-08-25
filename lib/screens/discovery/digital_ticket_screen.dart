import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../services/google_places_service.dart';
import '../../widgets/action_button.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../services/api_service.dart';
import '../../services/lunara_ticket_capture_service.dart';
import '../../utils/lunara_date_formatter.dart';
import '../home/dashboard.dart';

class DigitalTicketScreen extends StatefulWidget {
  final Map<dynamic, dynamic>? venue;
  final String? date;
  final String? package;
  final String? time;
  final String? table;
  final String? guests;
  final String? totalPrice;
  final String? ticketId;
  final String? ticketUrl;
  final String? status;
  final Map<dynamic, dynamic>? booking;
  final String? bannerImageUrl;
  final String? eventTitle;
  final dynamic user;
  final bool? isUpcomingNight;

  const DigitalTicketScreen({
    super.key,
    this.venue,
    this.date,
    this.package,
    this.time,
    this.table,
    this.guests,
    this.totalPrice,
    this.ticketId,
    this.ticketUrl,
    this.status,
    this.booking,
    this.bannerImageUrl,
    this.eventTitle,
    this.user,
    this.isUpcomingNight,
  });

  @override
  State<DigitalTicketScreen> createState() => _DigitalTicketScreenState();
}

class _DigitalTicketScreenState extends State<DigitalTicketScreen> {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _countdownTimer;
  Duration _timeRemaining = Duration.zero;
  final bool _isGeneratingPdf = false;
  final GlobalKey _ticketKey = GlobalKey();
  User? _loadedBookerUser;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _startCountdown();
    _initBookerProfile();
  }

  Future<void> _initBookerProfile() async {
    // If the cached user already has a name + photo, nothing to fetch —
    // avoid the async round-trip and the resulting setState rebuild entirely.
    final cached = ApiService.cachedCurrentUser;
    if (cached != null &&
        cached.firstName.trim().isNotEmpty &&
        (cached.profilePhoto ?? '').trim().isNotEmpty) {
      return;
    }

    // Also skip if the widget data already has a complete user.
    final current = _resolveBookerUser();
    if (current != null &&
        current.firstName.trim().isNotEmpty &&
        (current.profilePhoto ?? '').trim().isNotEmpty) {
      return;
    }

    try {
      final profile = await ApiService.fetchProfile();
      if (mounted && profile != null) {
        // Only rebuild if the fetched data actually adds something new.
        final existing = _resolveBookerUser();
        if (existing?.profilePhoto != profile.profilePhoto ||
            existing?.firstName != profile.firstName) {
          setState(() {
            _loadedBookerUser = profile;
          });
        }
      }
    } catch (e) {
      debugPrint("Error auto-loading booker profile in DigitalTicketScreen: $e");
    }
  }

  DateTime? _getEventDateTime() {
    try {
      final rawDate = widget.date ??
          widget.booking?['bookingDate'] ??
          widget.booking?['partyDate'] ??
          widget.booking?['date'] ??
          widget.booking?['eventStartAt'];
      final rawTime = widget.time ??
          widget.booking?['startTime'] ??
          widget.booking?['time'] ??
          widget.booking?['partyTime'];
      return LunaraDateFormatter.parseToLocal(rawDate, explicitTime: rawTime?.toString());
    } catch (e) {
      debugPrint("Error parsing event datetime: $e");
    }
    return null;
  }

  bool _isTicketExpired() {
    final statusStr = (widget.status ?? widget.booking?['status'] ?? '').toString().toLowerCase();
    if (statusStr == 'expired' || statusStr == 'cancelled') return true;
    final eventDateTime = _getEventDateTime();
    if (eventDateTime != null) {
      final expirationTime = eventDateTime.add(const Duration(hours: 30));
      return DateTime.now().isAfter(expirationTime);
    }
    return false;
  }

  void _startCountdown() {
    final eventDateTime = _getEventDateTime();
    if (eventDateTime != null) {
      final now = DateTime.now();
      if (eventDateTime.isAfter(now)) {
        _timeRemaining = eventDateTime.difference(now);
      } else {
        _timeRemaining = Duration.zero;
      }
    } else {
      _timeRemaining = Duration.zero;
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          final target = _getEventDateTime();
          if (target != null) {
            final now = DateTime.now();
            if (target.isAfter(now)) {
              _timeRemaining = target.difference(now);
            } else {
              _timeRemaining = Duration.zero;
              timer.cancel();
            }
          } else {
            _timeRemaining = Duration.zero;
            timer.cancel();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _positionStreamSubscription?.cancel();
    super.dispose();
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
      debugPrint("Error in DigitalTicketScreen location initialization: $e");
    }
  }

  User? _resolveBookerUser() {
    if (widget.user is User) return widget.user as User;
    if (widget.user is Map) {
      try {
        final map = Map<String, dynamic>.from(widget.user as Map);
        return User.fromJson(map);
      } catch (_) {}
    }

    final bUser = widget.booking?['user'] ??
        widget.booking?['host'] ??
        widget.booking?['booker'] ??
        widget.booking?['creator'];
    if (bUser is User) return bUser;
    if (bUser is Map) {
      try {
        final map = Map<String, dynamic>.from(bUser);
        return User.fromJson(map);
      } catch (_) {}
    }

    // Prefer the immediately-available cached user over the async-loaded one
    // so the very first frame already has complete user data.
    if (ApiService.cachedCurrentUser != null) return ApiService.cachedCurrentUser;
    if (_loadedBookerUser != null) return _loadedBookerUser;

    return null;
  }

  String _resolveHostUsername(User? hostUser) {
    if (hostUser == null) return '@guest';
    if (hostUser.displayName != null &&
        hostUser.displayName!.trim().isNotEmpty &&
        hostUser.displayName!.startsWith('@')) {
      return hostUser.displayName!.trim().toLowerCase();
    }
    final fn = hostUser.firstName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final ln = hostUser.lastName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (fn.isNotEmpty && ln.isNotEmpty) {
      return '@$fn.$ln';
    } else if (fn.isNotEmpty) {
      return '@$fn';
    } else if (hostUser.email.isNotEmpty) {
      final emailPrefix = hostUser.email.split('@')[0].toLowerCase();
      return '@$emailPrefix';
    }
    return '@guest';
  }

  bool get _isSoloBooking {
    if (widget.booking != null) {
      final b = widget.booking!;
      if (b['isSolo'] == true ||
          b['goingMode'] == 'solo' ||
          b['bookingType'] == 'solo' ||
          b['category'] == 'solo') {
        return true;
      }
    }
    final pkg = (widget.package ?? '').toLowerCase();
    final table = (widget.table ?? '').toLowerCase();
    if (pkg.contains('solo') || table.contains('solo')) return true;

    if (!_isEventBooking) {
      final g = (widget.guests ?? '').toLowerCase().trim();
      if (g == '1' || g == '1 guest' || g == '1 guests') return true;
      if (widget.booking?['numberOfGuests'] == 1) return true;
    }
    return false;
  }

  bool get _isEventBooking {
    if (widget.isUpcomingNight == true) return true;
    final b = widget.booking;
    if (b != null) {
      if (b['isUpcomingNight'] == true ||
          b['isEventBooking'] == true ||
          b['category'] == 'event_booking') {
        return true;
      }
      if (b['partyEventId'] != null || b['partyEvent'] != null) return true;
    }
    final pkg = (widget.package ?? '').toLowerCase();
    if (pkg.contains('party ticket') ||
        pkg.contains('event entry') ||
        pkg.contains('upcoming night') ||
        pkg.contains('event pass')) {
      return true;
    }
    if (widget.bannerImageUrl != null && widget.bannerImageUrl!.isNotEmpty) {
      return true;
    }
    return false;
  }

  String? get _resolvedEventTitle {
    if (widget.eventTitle != null && widget.eventTitle!.trim().isNotEmpty) {
      return widget.eventTitle!.trim();
    }
    final b = widget.booking;
    if (b != null) {
      final t = b['eventTitle'] ??
          b['partySubject'] ??
          b['title'] ??
          (b['partyEvent'] is Map ? b['partyEvent']['title'] : null);
      if (t != null && t.toString().trim().isNotEmpty) {
        return t.toString().trim();
      }
    }
    if (_isEventBooking &&
        widget.package != null &&
        widget.package!.trim().isNotEmpty &&
        widget.package != 'Confirmation Charges' &&
        widget.package != 'Standard' &&
        widget.package != 'Party Ticket') {
      return widget.package!.trim();
    }
    return null;
  }

  Map<dynamic, dynamic>? get _resolvedVenueMap {
    if (widget.venue != null && widget.venue!.isNotEmpty) return widget.venue;
    if (widget.booking?['venue'] is Map) return widget.booking!['venue'] as Map;
    return null;
  }

  String _getTicketBannerImageUrl() {
    String normalize(String path) {
      final clean = path.replaceAll('\\', '/');
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return clean;
      }
      return '${ApiService.baseUrl}/${clean.startsWith('/') ? clean.substring(1) : clean}';
    }

    // 1. Explicit bannerImageUrl parameter
    if (widget.bannerImageUrl != null && widget.bannerImageUrl!.trim().isNotEmpty) {
      final val = widget.bannerImageUrl!.trim();
      return val.startsWith('assets/') ? val : normalize(val);
    }

    // 2. From booking metadata
    final b = widget.booking;
    if (b != null) {
      for (final key in [
        'bannerImageUrl',
        'eventPoster',
        'bannerUrl',
        'imagePath',
        'posterUrl',
        'imageUrl',
        'image'
      ]) {
        final val = b[key]?.toString().trim();
        if (val != null && val.isNotEmpty) {
          return val.startsWith('assets/') ? val : normalize(val);
        }
      }
      if (b['partyEvent'] is Map) {
        final pe = b['partyEvent'] as Map;
        final val = (pe['bannerImageUrl'] ?? pe['imagePath'] ?? pe['image'])?.toString().trim();
        if (val != null && val.isNotEmpty) {
          return val.startsWith('assets/') ? val : normalize(val);
        }
      }
      if (b['rawRequest'] is Map) {
        final raw = b['rawRequest'] as Map;
        final val = (raw['bannerImageUrl'] ?? raw['eventPoster'] ?? raw['imagePath'])?.toString().trim();
        if (val != null && val.isNotEmpty) {
          return val.startsWith('assets/') ? val : normalize(val);
        }
      }
    }

    // 3. From venue dictionary
    final venue = _resolvedVenueMap;
    if (venue != null) {
      for (final key in [
        'coverImageUrl',
        'profilePhotoUrl',
        'bannerImageUrl',
        'eventPoster',
        'photoUrl',
        'filePath',
        'imageUrl',
        'image'
      ]) {
        final val = venue[key]?.toString().trim();
        if (val != null && val.isNotEmpty && !val.toLowerCase().contains('menu')) {
          return val.startsWith('assets/') ? val : normalize(val);
        }
      }
      if (venue['coverImage'] is Map) {
        final path = venue['coverImage']['url'] ?? venue['coverImage']['filePath'];
        if (path != null && path.toString().isNotEmpty) {
          return normalize(path.toString());
        }
      }
      final images = venue['images'];
      if (images is List && images.isNotEmpty) {
        final nonMenuImages = images.where((img) {
          if (img is Map) {
            final type = (img['imageType'] ?? img['type'] ?? img['category'] ?? '').toString().toLowerCase();
            return !type.contains('menu') && !type.contains('package');
          }
          return true;
        }).toList();

        final listToUse = nonMenuImages.isNotEmpty ? nonMenuImages : images;
        final img = listToUse[0];
        if (img is Map) {
          final path = img['filePath'] ?? img['url'];
          if (path != null && path.toString().isNotEmpty) {
            return normalize(path.toString());
          }
        } else if (img is String && img.isNotEmpty) {
          return normalize(img);
        }
      }
    }

    final idHash = (venue?['name']?.toString() ?? 'event').hashCode.abs() % 20;
    return 'https://picsum.photos/seed/$idHash/600/400';
  }

  Widget _buildBannerImageWidget(String imageUrl) {
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          decoration: const BoxDecoration(
            gradient: LunaraTheme.deepPurpleGradient,
          ),
          child: const Center(
            child: Icon(Icons.nightlife_rounded, color: Colors.white70, size: 56),
          ),
        ),
      );
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        decoration: const BoxDecoration(
          gradient: LunaraTheme.deepPurpleGradient,
        ),
        child: const Center(
          child: Icon(Icons.nightlife_rounded, color: Colors.white70, size: 56),
        ),
      ),
    );
  }


  void _shareTicket(BuildContext context) {
    final venueName = widget.venue?['name'] ?? widget.booking?['venueName'] ?? 'Unknown Venue';
    final dateStr = widget.date ?? 'SAT, OCT 24';
    final timeStr = widget.time ?? '10:30 PM';
    final ticketIdStr = (widget.ticketId ?? 'TICKET').toUpperCase();
    final tableStr = widget.table ?? 'VIP V1';
    final guestsStr = widget.guests ?? '1';

    String cleanDateStr = dateStr;
    String cleanTimeStr = timeStr;
    if (dateStr.contains('•')) {
      final parts = dateStr.split('•');
      cleanDateStr = parts[0].trim();
      cleanTimeStr = parts.length > 1 ? parts[1].trim() : cleanTimeStr;
    }

    final hostUser = _resolveBookerUser();
    final cleanHostName = hostUser != null ? '${hostUser.firstName} ${hostUser.lastName}'.trim() : 'Guest User';
    final eventName = _resolvedEventTitle ?? venueName;

    LunaraTicketCaptureService.shareTicket(
      context: context,
      ticketKey: _ticketKey,
      ticketCode: ticketIdStr,
      venueName: eventName,
      eventDateTime: '$cleanDateStr • $cleanTimeStr',
      eventType: _isEventBooking ? 'Upcoming Night Event Pass' : 'Venue Booking Pass',
      hostName: cleanHostName,
      guestCount: '$guestsStr Guests',
      extraDetails: _isEventBooking ? 'Venue: $venueName' : 'Table $tableStr',
    );
  }

  String _formatCountdownText() {
    if (_timeRemaining.inSeconds <= 0) {
      return "EVENT STARTED";
    }
    final days = _timeRemaining.inDays;
    final hours = _timeRemaining.inHours;
    final mins = _timeRemaining.inMinutes % 60;
    final secs = _timeRemaining.inSeconds % 60;
    
    if (days > 0) {
      return '${days}d ${(_timeRemaining.inHours % 24).toString().padLeft(2, '0')}h ${mins.toString().padLeft(2, '0')}m';
    }
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? LunaraTheme.midnightBlack : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _buildGlowingTicket(context),
                    ),
                  ),
                ),
              ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black87;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.close, color: color),
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const Dashboard()),
              (route) => false,
            ),
          ),
          Text(
            'DIGITAL TICKET',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: color,
            ),
          ),
          IconButton(
            icon: Icon(Icons.share_outlined, color: color, size: 20),
            onPressed: () => _shareTicket(context),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowingTicket(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final venueMap = _resolvedVenueMap;
    final String venueName = venueMap?['name']?.toString() ??
        venueMap?['venueName']?.toString() ??
        widget.booking?['venueName']?.toString() ??
        'LUNARA VENUE';
    final String venueCity = venueMap?['city']?.toString() ??
        widget.booking?['venueCity']?.toString() ??
        '';
    final String venueArea = venueMap?['area']?.toString() ??
        widget.booking?['venueArea']?.toString() ??
        '';
    final String rawAddress = venueMap?['address']?.toString() ??
        venueMap?['addressLine1']?.toString() ??
        widget.booking?['venueAddress']?.toString() ??
        '';
    final String venueAddress = rawAddress.isNotEmpty
        ? rawAddress
        : (venueArea.isNotEmpty ? '$venueArea, $venueCity' : venueCity);

    final String cleanBannerImage = _getTicketBannerImageUrl();

    final String? resolvedEventTitle = _resolvedEventTitle;
    final bool isEvent = _isEventBooking || resolvedEventTitle != null;
    final bool isSolo = _isSoloBooking;

    // Date & Time formatting
    final eventDt = _getEventDateTime();
    final String displayDate = eventDt != null
        ? LunaraDateFormatter.formatEventDate(eventDt, pattern: 'EEE, d MMM yyyy').toUpperCase()
        : (widget.date ?? widget.booking?['bookingDate']?.toString() ?? 'SAT, OCT 24').trim();
    final String displayTime = eventDt != null
        ? LunaraDateFormatter.formatEventTime(eventDt)
        : LunaraDateFormatter.normalizeTimeTo12Hour(widget.time ?? widget.booking?['startTime']?.toString());
    final String displayDateTime = '$displayDate • $displayTime';

    // Table / Package display
    String displayTable;
    if (isEvent) {
      displayTable = resolvedEventTitle ?? widget.package ?? 'EVENT PASS';
    } else if (isSolo) {
      if (widget.table != null &&
          widget.table!.trim().isNotEmpty &&
          widget.table != 'VIP V1' &&
          widget.table != 'Confirmation Charges') {
        displayTable = widget.table!.trim().toUpperCase();
      } else if (widget.package != null &&
          widget.package!.trim().isNotEmpty &&
          widget.package != 'Confirmation Charges' &&
          widget.package != 'Standard') {
        displayTable = widget.package!.trim().toUpperCase();
      } else {
        displayTable = 'SOLO ENTRY';
      }
    } else {
      if (widget.table != null && widget.table!.trim().isNotEmpty) {
        displayTable = widget.table!.trim().toUpperCase();
      } else if (widget.package != null && widget.package!.trim().isNotEmpty) {
        displayTable = widget.package!.trim().toUpperCase();
      } else {
        displayTable = 'STANDARD TABLE';
      }
    }

    // Guests display
    String displayGuests;
    if (isSolo) {
      displayGuests = '1 GUEST (SOLO)';
    } else {
      final rawG = widget.guests ?? widget.booking?['numberOfGuests']?.toString();
      if (rawG != null && rawG.trim().isNotEmpty) {
        final cleanG = rawG.trim().toUpperCase().replaceAll('GUESTS', '').replaceAll('GUEST', '').trim();
        final count = int.tryParse(cleanG) ?? 1;
        displayGuests = count == 1 ? '1 GUEST' : '$count GUESTS';
      } else {
        displayGuests = '1 GUEST';
      }
    }

    final String rawStatus = widget.status ??
        widget.booking?['status']?.toString() ??
        'CONFIRMED';
    final String displayStatus = rawStatus.toUpperCase();

    final String finalTicketId = (widget.ticketId ??
        widget.booking?['ticketCode'] ??
        widget.booking?['ticketId'] ??
        (widget.booking?['id'] != null
            ? widget.booking!['id'].toString().substring(0, 8).toUpperCase()
            : 'TICKET')).toString().toUpperCase();

    final hostUser = _resolveBookerUser();
    final cleanHostName = hostUser != null && hostUser.fullName.trim().isNotEmpty
        ? hostUser.fullName.trim()
        : (hostUser != null && hostUser.firstName.trim().isNotEmpty
            ? '${hostUser.firstName} ${hostUser.lastName}'.trim()
            : 'Guest User');
    final hostUsername = _resolveHostUsername(hostUser);

    final double amountPaid = double.tryParse((widget.totalPrice ??
            widget.booking?['totalAmount']?.toString() ??
            widget.booking?['paymentAmount']?.toString() ??
            '').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    final bool isFreeTicket = amountPaid <= 0;

    // Payment method resolution
    String paymentMethodText;
    if (isFreeTicket) {
      paymentMethodText = 'Complimentary';
    } else {
      final pMethod = (widget.booking?['paymentMethod'] ??
              widget.booking?['method'] ??
              widget.booking?['paymentType'] ??
              '').toString().toLowerCase();
      if (pMethod.contains('wallet')) {
        paymentMethodText = 'Lunara Wallet';
      } else if (pMethod.contains('upi')) {
        paymentMethodText = 'UPI Payment';
      } else if (pMethod.contains('card')) {
        paymentMethodText = 'Credit / Debit Card';
      } else {
        paymentMethodText = 'UPI / Net Banking';
      }
    }

    // Latitude & Longitude for distance and navigation
    final latVal = venueMap?['latitude'] ?? widget.booking?['latitude'];
    final lngVal = venueMap?['longitude'] ?? widget.booking?['longitude'];
    double? lat;
    double? lng;
    if (latVal != null) {
      lat = double.tryParse(latVal.toString());
    }
    if (lngVal != null) {
      lng = double.tryParse(lngVal.toString());
    }

    String distanceText = '';
    if (_currentPosition != null && lat != null && lng != null && lat != 0.0 && lng != 0.0) {
      distanceText = GooglePlacesService.formatRoadDistance(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        lat,
        lng,
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final ticketWidth = screenWidth > 500 ? 420.0 : double.infinity;

    return RepaintBoundary(
      key: _ticketKey,
      child: Container(
        width: ticketWidth,
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E1E28), Color(0xFF15151D)],
                )
              : LunaraTheme.cardGradient,
          borderRadius: BorderRadius.circular(32),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  )
                ]
              : LunaraTheme.premiumCardShadow,
          border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: isDark ? 0.3 : 0.15)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Event / Venue Banner Section with Background Image
            Container(
              height: (MediaQuery.of(context).size.height * 0.24).clamp(145.0, 205.0),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _buildBannerImageWidget(cleanBannerImage),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.2),
                              Colors.black.withValues(alpha: 0.5),
                              Colors.black.withValues(alpha: 0.92),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Dynamic Header Pill: Upcoming Night / Solo Booking / Venue Reservation
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: isEvent
                              ? LunaraTheme.primaryGradient
                              : (isSolo
                                  ? const LinearGradient(
                                      colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                                    )
                                  : const LinearGradient(
                                      colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                                    )),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: (isEvent
                                      ? LunaraTheme.electricViolet
                                      : (isSolo ? const Color(0xFF8B5CF6) : const Color(0xFF3B82F6)))
                                  .withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isEvent
                                  ? Icons.nightlife_rounded
                                  : (isSolo ? Icons.person_rounded : Icons.local_bar_rounded),
                              color: Colors.white,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isEvent
                                  ? 'UPCOMING NIGHT'
                                  : (isSolo ? 'SOLO BOOKING' : 'VENUE RESERVATION'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 20,
                      right: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (resolvedEventTitle != null) ...[
                            Text(
                              resolvedEventTitle.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.8,
                                height: 1.15,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded, color: LunaraTheme.cyberCyan, size: 12),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '@ ${venueName.toUpperCase()} • ${displayDateTime.toUpperCase()}',
                                    style: const TextStyle(
                                      color: LunaraTheme.cyberCyan,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            Text(
                              venueName.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              displayDateTime.toUpperCase(),
                              style: const TextStyle(
                                color: LunaraTheme.cyberCyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_isTicketExpired())
                      Positioned(
                        top: 16,
                        right: 16,
                        child: _buildExpiredWatermark(),
                      ),
                  ],
                ),
              ),
            ),

            // Dashed Divider line
            Row(
              children: [
                Container(
                  width: 12,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isDark ? LunaraTheme.midnightBlack : Colors.white,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Flex(
                        direction: Axis.horizontal,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.max,
                        children: List.generate(
                          (constraints.constrainWidth() / 10).floor(),
                          (index) => SizedBox(
                            width: 5,
                            height: 2,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: LunaraTheme.electricViolet.withValues(alpha: isDark ? 0.4 : 0.2),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  width: 12,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isDark ? LunaraTheme.midnightBlack : Colors.white,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(12),
                    ),
                  ),
                ),
              ],
            ),

            // Dynamic Info & Profiles Section
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Live Countdown / Expired Status Banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: _isTicketExpired()
                          ? Colors.red.withValues(alpha: 0.12)
                          : LunaraTheme.electricViolet.withValues(alpha: isDark ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isTicketExpired()
                            ? Colors.red.shade400
                            : LunaraTheme.electricViolet.withValues(alpha: isDark ? 0.4 : 0.25),
                      ),
                    ),
                    child: Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Icon(
                            _isTicketExpired() ? Icons.error_outline_rounded : Icons.timer_outlined,
                            color: _isTicketExpired() ? Colors.red.shade600 : LunaraTheme.electricViolet,
                            size: 18,
                          ),
                          Text(
                            _isTicketExpired() ? 'TICKET STATUS: ' : 'EXPIRATION COUNTDOWN: ',
                            style: TextStyle(
                              color: _isTicketExpired()
                                  ? Colors.red.shade700
                                  : (isDark ? Colors.white70 : Colors.black87),
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            _isTicketExpired() ? 'EXPIRED' : _formatCountdownText(),
                            style: TextStyle(
                              color: _isTicketExpired() ? Colors.red.shade700 : LunaraTheme.electricViolet,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Ticket Holder Profile Section
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF24242E) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[200]!),
                    ),
                    child: Row(
                      children: [
                        if (hostUser != null)
                          LunaraProfileImage(
                            user: hostUser,
                            radius: 26,
                            showGradientBorder: true,
                            isInteractive: true,
                          )
                        else
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                            child: Icon(Icons.person, color: isDark ? Colors.grey[400] : Colors.grey[500], size: 24),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cleanHostName,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                hostUsername,
                                style: TextStyle(
                                  color: isDark ? Colors.white70 : Colors.black54,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.2), width: 1),
                          ),
                          child: Text(
                            isSolo ? 'SOLO HOLDER' : 'HOLDER',
                            style: const TextStyle(
                              color: LunaraTheme.electricViolet,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Payment details card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF24242E) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[200]!,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.account_balance_wallet_rounded,
                                color: LunaraTheme.electricViolet,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PAYMENT METHOD',
                                  style: TextStyle(
                                    color: isDark ? Colors.white54 : Colors.black54,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  paymentMethodText,
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'AMOUNT PAID',
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black54,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  isFreeTicket ? 'FREE' : '₹${amountPaid.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    color: isDark ? Colors.green[400] : const Color(0xFF2E7D32),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: (isFreeTicket ? Colors.blue[50] : Colors.green[50])
                                        ?.withValues(alpha: isDark ? 0.15 : 1.0),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isFreeTicket ? 'FREE' : 'PAID',
                                    style: TextStyle(
                                      color: isDark
                                          ? (isFreeTicket ? Colors.blue[300] : Colors.green[300])
                                          : (isFreeTicket ? Colors.blue[700] : Colors.green[700]),
                                      fontSize: 7,
                                      fontWeight: FontWeight.bold,
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

                  // Venue Details Card with map navigation and distance tag
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF24242E) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[200]!,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                image: DecorationImage(
                                  image: NetworkImage(cleanBannerImage),
                                  fit: BoxFit.cover,
                                ),
                                border: Border.all(color: isDark ? Colors.white10 : Colors.grey[300]!),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          venueName.toUpperCase(),
                                          style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black87,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (distanceText.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Text(
                                            distanceText,
                                            style: const TextStyle(
                                              color: LunaraTheme.electricViolet,
                                              fontSize: 8,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    venueAddress,
                                    style: TextStyle(
                                      color: isDark ? Colors.white70 : Colors.black54,
                                      fontSize: 10,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.black12, height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 32,
                          child: TextButton.icon(
                            onPressed: () async {
                              final queryStr = (lat != null && lng != null && lat != 0.0 && lng != 0.0)
                                  ? '$lat,$lng'
                                  : '$venueName, $venueAddress';
                              final mapUrl = Uri.parse(
                                'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(queryStr)}',
                              );
                              if (await canLaunchUrl(mapUrl)) {
                                await launchUrl(mapUrl, mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: const Icon(
                              Icons.map_rounded,
                              color: LunaraTheme.electricViolet,
                              size: 14,
                            ),
                            label: const Text(
                              'VIEW MAP DIRECTIONS',
                              style: TextStyle(
                                color: LunaraTheme.electricViolet,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              backgroundColor: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Bottom Ticket Info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: _ticketLabelValue(isEvent ? 'ENTRY / PASS' : (isSolo ? 'PLAN / ENTRY' : 'TABLE'), displayTable, isDark)),
                      Expanded(child: _ticketLabelValue('GUESTS', displayGuests, isDark)),
                      Expanded(child: _ticketLabelValue('STATUS', displayStatus, isDark)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${isSolo ? 'SOLO GUEST ENTRY' : 'ADMIT GUESTS'} • TICKET ID: $finalTicketId',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.grey[600],
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ticketLabelValue(String label, String value, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.white54 : Colors.grey[600],
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _downloadLocalTicket(BuildContext context) async {
    final venueName = widget.venue?['name']?.toString() ?? 'Venue';
    final displayDate = widget.date ?? 'Event Date';
    final ticketCode = (widget.ticketId ?? 'BKG-PASS').toUpperCase();

    await LunaraTicketCaptureService.downloadTicket(
      context: context,
      ticketKey: _ticketKey,
      ticketCode: ticketCode,
      eventType: 'Venue_Booking',
      venueName: venueName,
      eventDateTime: displayDate,
    );
  }

  Widget _buildFooter(BuildContext context) {
    final hasPdf = widget.ticketUrl != null && widget.ticketUrl!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _isGeneratingPdf 
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
                )
              : LunaraActionButton(
                  text: 'DOWNLOAD TICKET',
                  onPressed: () => _downloadLocalTicket(context),
                ),
          const SizedBox(height: 12),
          if (hasPdf) ...[
            LunaraActionButton(
              text: 'VIEW TICKET LINK',
              onPressed: () async {
                final pdfUri = Uri.parse(widget.ticketUrl!);
                if (await canLaunchUrl(pdfUri)) {
                  await launchUrl(pdfUri, mode: LaunchMode.externalApplication);
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not open the PDF URL.')),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
          ],
          LunaraActionButton(
            text: 'GO TO DASHBOARD',
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const Dashboard()),
              (route) => false,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.red.shade600,
              width: 3.0,
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
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 4.0,
            ),
          ),
        ),
      ),
    );
  }
}
