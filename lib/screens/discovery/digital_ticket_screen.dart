import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../services/api_service.dart';

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
  });

  @override
  State<DigitalTicketScreen> createState() => _DigitalTicketScreenState();
}

class _DigitalTicketScreenState extends State<DigitalTicketScreen> {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _countdownTimer;
  Duration _timeRemaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _startCountdown();
  }

  DateTime? _getEventDateTime() {
    try {
      String dateStr = widget.date ?? '';
      String timeStr = widget.time ?? '';
      if (dateStr.contains('•')) {
        final parts = dateStr.split('•');
        dateStr = parts[0].trim();
        if (parts.length > 1 && timeStr.isEmpty) {
          timeStr = parts[1].trim();
        }
      }
      if (dateStr.isEmpty) return null;

      // Parse time parts
      int hour = 20; // default 8 PM
      int minute = 0;
      if (timeStr.isNotEmpty) {
        final cleanTime = timeStr.toUpperCase();
        // Check if AM/PM format
        if (cleanTime.contains('AM') || cleanTime.contains('PM')) {
          final isPm = cleanTime.contains('PM');
          final timeOnly = cleanTime.replaceAll('AM', '').replaceAll('PM', '').trim();
          final parts = timeOnly.split(':');
          if (parts.isNotEmpty) {
            int h = int.tryParse(parts[0]) ?? 12;
            int m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
            if (isPm && h < 12) h += 12;
            if (!isPm && h == 12) h = 0;
            hour = h;
            minute = m;
          }
        } else {
          // 24 hour format e.g. "20:00"
          final parts = timeStr.split(':');
          if (parts.isNotEmpty) {
            hour = int.tryParse(parts[0]) ?? 20;
            minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
          }
        }
      }

      // Parse date parts
      // Format 1: YYYY-MM-DD
      final ymdRegex = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})');
      var match = ymdRegex.firstMatch(dateStr);
      if (match != null) {
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        return DateTime(year, month, day, hour, minute);
      }

      // Format 2: DD-MM-YYYY or DD/MM/YYYY
      final dmyRegex = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})');
      match = dmyRegex.firstMatch(dateStr);
      if (match != null) {
        final day = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final year = int.parse(match.group(3)!);
        return DateTime(year, month, day, hour, minute);
      }

      // Format 3: EEE, MMM d or MMM d (e.g. "Mon, Jul 21" or "Jul 21" or "SAT, OCT 24")
      // Since year is not present, default to current year
      final monthsList = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
      final cleanDate = dateStr.toUpperCase();
      int? foundMonth;
      for (int i = 0; i < monthsList.length; i++) {
        if (cleanDate.contains(monthsList[i])) {
          foundMonth = i + 1;
          break;
        }
      }

      if (foundMonth != null) {
        final dayRegex = RegExp(r'\b(\d{1,2})\b');
        final dayMatch = dayRegex.firstMatch(cleanDate);
        if (dayMatch != null) {
          final day = int.parse(dayMatch.group(1)!);
          final yearRegex = RegExp(r'\b(20\d{2})\b');
          final yearMatch = yearRegex.firstMatch(cleanDate);
          final year = yearMatch != null ? int.parse(yearMatch.group(1)!) : DateTime.now().year;
          return DateTime(year, foundMonth, day, hour, minute);
        }
      }
    } catch (e) {
      debugPrint("Error parsing event datetime: $e");
    }
    return null;
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
      _timeRemaining = const Duration(hours: 4, minutes: 30, seconds: 0);
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
            if (_timeRemaining.inSeconds > 0) {
              _timeRemaining = _timeRemaining - const Duration(seconds: 1);
            } else {
              timer.cancel();
            }
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

  String _getVenueImageUrl() {
    final venue = widget.venue;
    if (venue == null) return 'https://picsum.photos/seed/venue/600/400';
    
    if (venue['imageUrl'] != null && venue['imageUrl'].toString().isNotEmpty) {
      final path = venue['imageUrl'].toString().replaceAll('\\', '/');
      return path.startsWith('http') ? path : '${ApiService.baseUrl}/${path.startsWith('/') ? path.substring(1) : path}';
    }
    
    final images = venue['images'];
    if (images is List && images.isNotEmpty) {
      final img = images[0];
      if (img is Map) {
        final path = (img['filePath'] ?? img['url'] ?? '').toString().replaceAll('\\', '/');
        if (path.isNotEmpty) {
          return path.startsWith('http') ? path : '${ApiService.baseUrl}/${path.startsWith('/') ? path.substring(1) : path}';
        }
      } else if (img is String) {
        final path = img.replaceAll('\\', '/');
        return path.startsWith('http') ? path : '${ApiService.baseUrl}/${path.startsWith('/') ? path.substring(1) : path}';
      }
    }
    
    final idHash = (venue['name']?.toString() ?? 'venue').hashCode.abs() % 20;
    return 'https://picsum.photos/seed/$idHash/600/400';
  }

  void _shareTicket(BuildContext context) {
    final venueName = widget.venue?['name'] ?? 'Unknown Venue';
    final dateStr = widget.date ?? 'SAT, OCT 24';
    final timeStr = widget.time ?? '10:30 PM';
    final ticketIdStr = widget.ticketId ?? 'TICKET';
    final tableStr = widget.table ?? 'VIP V1';
    final guestsStr = widget.guests ?? '1';

    String cleanDateStr = dateStr;
    String cleanTimeStr = timeStr;
    if (dateStr.contains('•')) {
      final parts = dateStr.split('•');
      cleanDateStr = parts[0].trim();
      cleanTimeStr = parts[1].trim();
    }

    final shareText = 'My Digital Ticket on Lunara is Confirmed! 🥳\n\n'
        'Venue: $venueName\n'
        'Date: $cleanDateStr • $cleanTimeStr\n'
        'Table: $tableStr\n'
        'Guests: $guestsStr\n'
        'Ticket ID: $ticketIdStr\n\n'
        'Let\'s vibe together! 💜';

    final box = context.findRenderObject() as RenderBox?;
    Share.share(
      shareText,
      subject: 'My Lunara Ticket',
      sharePositionOrigin: box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black87),
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
          const Text(
            'DIGITAL TICKET',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black87,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.black87, size: 20),
            onPressed: () => _shareTicket(context),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowingTicket(BuildContext context) {
    final String venueName = widget.venue?['name']?.toString() ?? 'ELARA VELVET';
    final String venueCity = widget.venue?['city']?.toString() ?? 'Unknown City';
    final String venueArea = widget.venue?['area']?.toString() ?? '';
    final String venueAddress = widget.venue?['address']?.toString() ?? '${venueArea.isNotEmpty ? "$venueArea, " : ""}$venueCity';
    final String cleanVenueImage = _getVenueImageUrl();

    String displayDate = widget.date ?? 'SAT, OCT 24';
    String displayTime = widget.time ?? '10:30 PM';
    String displayDateTime;
    if (displayDate.contains('•')) {
      displayDateTime = displayDate;
      final parts = displayDate.split('•');
      displayDate = parts[0].trim();
      displayTime = parts[1].trim();
    } else {
      displayDateTime = '$displayDate • $displayTime';
    }

    final String displayTable = widget.table ?? 'VIP V1';
    final String displayGuests = widget.guests != null ? '${widget.guests} GUESTS' : '6 GUESTS';
    final String displayStatus = 'VERIFIED';
    final String finalTicketId = (widget.ticketId ?? 'TICKET').toUpperCase();

    final hostUser = ApiService.cachedCurrentUser;
    final cleanHostName = hostUser != null ? '${hostUser.firstName} ${hostUser.lastName}'.trim() : 'Guest User';
    final hostUsername = hostUser != null ? '@${hostUser.firstName.toLowerCase()}.${hostUser.lastName.toLowerCase()}' : '@guest';

    final double amountPaid = double.tryParse((widget.totalPrice ?? '0').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 199.0;

    final latVal = widget.venue?['latitude'];
    final lngVal = widget.venue?['longitude'];
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
      double distanceInMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        lat,
        lng,
      );
      if (distanceInMeters < 1000) {
        distanceText = '${distanceInMeters.toStringAsFixed(0)} m';
      } else {
        distanceText = '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
      }
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final ticketWidth = screenWidth > 500 ? 420.0 : double.infinity;

    return Container(
      width: ticketWidth,
      decoration: BoxDecoration(
        gradient: LunaraTheme.cardGradient,
        borderRadius: BorderRadius.circular(32),
        boxShadow: LunaraTheme.premiumCardShadow,
        border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Event Banner Section with Venue Image Background
          Container(
            height: 180,
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
                    child: Image.network(
                      cleanVenueImage,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        decoration: const BoxDecoration(
                          gradient: LunaraTheme.deepPurpleGradient,
                        ),
                        child: const Center(
                          child: Icon(Icons.location_city, color: Colors.white38, size: 56),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.2),
                            Colors.black.withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 24,
                    right: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          venueName.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 24,
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
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
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
          ),

          // Dashed Divider line
          Row(
            children: [
              Container(
                width: 12,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.horizontal(
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
                              color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
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
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(12),
                  ),
                ),
              ),
            ],
          ),

          // Dynamic Info & Profiles Section
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Live Countdown Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timer_outlined, color: LunaraTheme.electricViolet, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'EXPIRATION COUNTDOWN: ',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        _formatCountdownText(),
                        style: const TextStyle(
                          color: LunaraTheme.electricViolet,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Ticket Holder Profile Section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      if (hostUser != null)
                        LunaraProfileImage(
                          user: hostUser,
                          radius: 30,
                          showGradientBorder: true,
                          isInteractive: true,
                        )
                      else
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.grey[200],
                          child: Icon(Icons.person, color: Colors.grey[500], size: 28),
                        ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cleanHostName,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              hostUsername,
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.2), width: 1),
                        ),
                        child: const Text(
                          'TICKET HOLDER',
                          style: TextStyle(
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
                const SizedBox(height: 16),

                // Payment details card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.grey[200]!,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet_rounded,
                              color: LunaraTheme.electricViolet,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PAYMENT METHOD',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'UPI / Net Banking',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 12,
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
                          const Text(
                            'AMOUNT PAID',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                '₹${amountPaid.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Color(0xFF2E7D32),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'PAID',
                                  style: TextStyle(
                                    color: Colors.green[700],
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
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.grey[200]!,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              image: DecorationImage(
                                image: NetworkImage(cleanVenueImage),
                                fit: BoxFit.cover,
                              ),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                          ),
                          const SizedBox(width: 10),
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
                                          color: Colors.black87,
                                          fontSize: 13,
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
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Text(
                                          distanceText,
                                          style: const TextStyle(
                                            color: LunaraTheme.electricViolet,
                                            fontSize: 9,
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
                                  style: const TextStyle(
                                    color: Colors.black54,
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
                            final mapUrl = Uri.parse(
                              'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent("$venueName, $venueAddress")}',
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
                const SizedBox(height: 20),

                // Bottom Ticket Info
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: _ticketLabelValue('TABLE', displayTable)),
                    Expanded(child: _ticketLabelValue('GUESTS', displayGuests)),
                    Expanded(child: _ticketLabelValue('STATUS', displayStatus)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'ADMIT ONE + FRIENDS • TICKET ID: $finalTicketId',
                  style: TextStyle(
                    color: Colors.grey[600],
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
    );
  }

  Widget _ticketLabelValue(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final hasPdf = widget.ticketUrl != null && widget.ticketUrl!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPdf) ...[
            LunaraActionButton(
              text: 'DOWNLOAD PDF TICKET',
              onPressed: () async {
                final pdfUri = Uri.parse(widget.ticketUrl!);
                if (await canLaunchUrl(pdfUri)) {
                  await launchUrl(pdfUri, mode: LaunchMode.externalApplication);
                } else {
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
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
    );
  }
}
