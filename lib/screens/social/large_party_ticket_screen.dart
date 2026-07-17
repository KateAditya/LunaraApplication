import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
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

  @override
  void initState() {
    super.initState();
    _initLocation();
    _initCountdown();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _initCountdown() {
    final bookingDateStr = widget.booking['bookingDate']?.toString();
    if (bookingDateStr == null) return;

    DateTime? targetDate = DateTime.tryParse(bookingDateStr)?.toLocal();
    if (targetDate == null) return;

    // Apply start time if available
    final startTimeStr = widget.booking['startTime']?.toString() ?? '21:00';
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
    final venueName = widget.venue['name'] ?? 'Unknown Venue';
    final rawDate = widget.booking['bookingDate'];
    final guests = widget.booking['numberOfGuests'] ?? '20+';
    final ticketId = (widget.booking['ticketCode'] ?? widget.booking['id'] ?? 'TICKET').toString().toUpperCase();

    String dateStr = 'Tonight';
    if (rawDate != null) {
      try {
        dateStr = DateFormat('MMM dd, yyyy').format(DateTime.parse(rawDate.toString()).toLocal());
      } catch (_) {}
    }

    final shareText = 'My VIP Large Party Booking on Lunara is Confirmed! 🎉🔥\n\n'
        'Venue: $venueName\n'
        'Date: $dateStr\n'
        'Guests: $guests Guests (Large Party)\n'
        'Ticket Code: $ticketId\n\n'
        'Ready to vibe with the crew! 💜';

    final box = context.findRenderObject() as RenderBox?;
    Share.share(
      shareText,
      subject: 'My Lunara VIP Group Ticket',
      sharePositionOrigin: box != null ? box.localToGlobal(Offset.zero) & box.size : null,
    );
  }

  Widget _buildCountdownBadge() {
    if (_timeRemaining == Duration.zero) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5), width: 1),
        ),
        child: const Text(
          'EVENT LIVE / PAST',
          style: TextStyle(
            color: Colors.greenAccent,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    final days = _timeRemaining.inDays;
    final hours = _timeRemaining.inHours % 24;
    final minutes = _timeRemaining.inMinutes % 60;
    final seconds = _timeRemaining.inSeconds % 60;

    String text;
    if (days > 0) {
      text = '$days d, $hours h left';
    } else {
      text = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} left';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        'COUNTDOWN: $text',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTicketDetail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final venueName = widget.venue['name'] ?? 'Unknown Venue';
    final venueCity = widget.venue['city'] ?? 'Unknown City';
    final venueArea = widget.venue['area'] ?? '';
    final venueAddress = widget.venue['address'] ?? widget.venue['addressLine1'] ?? '${venueArea.isNotEmpty ? "$venueArea, " : ""}$venueCity';
    final venueImageUrl = widget.venue['imageUrl'] ?? (widget.venue['images'] != null && (widget.venue['images'] as List).isNotEmpty ? widget.venue['images'][0]['filePath'] : null) ?? '';
    final cleanVenueImageUrl = venueImageUrl.startsWith('/') ? '${ApiService.baseUrl}$venueImageUrl' : venueImageUrl;

    final rawDate = widget.booking['bookingDate'];
    DateTime planDateTime = DateTime.now();
    if (rawDate != null) {
      try {
        planDateTime = DateTime.parse(rawDate.toString()).toLocal();
      } catch (_) {}
    }

    final ticketId = (widget.booking['ticketCode'] ?? widget.booking['id'] ?? 'TICKET').toString().toUpperCase();
    final totalAmount = widget.booking['totalAmount'] ?? widget.booking['adminPaymentAmount'] ?? 0;
    final guests = widget.booking['numberOfGuests'] ?? '20+';

    final latVal = widget.venue['latitude'];
    final lngVal = widget.venue['longitude'];
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

    // Host Profile Resolution
    final Map<String, dynamic> hostUser = widget.booking['customer'] is Map
        ? Map<String, dynamic>.from(widget.booking['customer'])
        : <String, dynamic>{};
    final hostName = '${hostUser['firstName'] ?? 'You'} ${hostUser['lastName'] ?? ''}'.trim();
    final hostUsername = '@${hostUser['username'] ?? hostUser['firstName']?.toString().toLowerCase() ?? 'host'}';

    return Scaffold(
      backgroundColor: LunaraTheme.midnightBlack,
      appBar: AppBar(
        title: const Text(
          'LARGE PARTY TICKET',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.white),
            onPressed: () => _shareTicket(context),
          ),
          const SizedBox(width: 8),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // VIP Star Badge Indicator
              const Icon(
                Icons.stars_rounded,
                color: LunaraTheme.cyberCyan,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'VIP Booking Confirmed!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Large Party reservation is fully paid. Show this at the venue.',
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Reusable Ticket Widget
              LunaraTicketWidget(
                topSection: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'VIP LARGE PARTY',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          Text(
                            ticketId.length > 12 ? ticketId.substring(0, 12) : ticketId,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildCountdownBadge(),
                      const SizedBox(height: 20),
                      Text(
                        venueName.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTicketDetail(
                              'DATE',
                              DateFormat('MMM dd, yyyy').format(planDateTime),
                            ),
                          ),
                          Expanded(
                            child: _buildTicketDetail(
                              'TIME',
                              widget.booking['startTime']?.toString() ?? '09:00 PM',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                bottomSection: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                LunaraProfileImage(
                                  userData: hostUser,
                                  radius: 36,
                                  showGradientBorder: true,
                                  isInteractive: true,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  hostName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  hostUsername,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.5), width: 1),
                                  ),
                                  child: const Text(
                                    'PARTY HOST',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 80,
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [LunaraTheme.cyberCyan, LunaraTheme.deepBlue],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: LunaraTheme.cyberCyan.withValues(alpha: 0.3),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.groups_rounded,
                                      color: Colors.white,
                                      size: 36,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$guests Guests',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  'Vibe Crew',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: LunaraTheme.cyberCyan.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: LunaraTheme.cyberCyan.withValues(alpha: 0.4), width: 1),
                                  ),
                                  child: const Text(
                                    'LARGE GROUP',
                                    style: TextStyle(
                                      color: LunaraTheme.cyberCyan,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Lunara Secure Pay detail
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: LunaraTheme.cyberCyan.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.account_balance_wallet_rounded,
                                    color: LunaraTheme.cyberCyan,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'BOOKING STATUS',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Lunara Secure Pay',
                                      style: TextStyle(
                                        color: Colors.white,
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
                                  'TOTAL PAID',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      '₹${double.tryParse(totalAmount.toString())?.toStringAsFixed(0) ?? totalAmount.toString()}',
                                      style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.greenAccent.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'PAID',
                                        style: TextStyle(
                                          color: Colors.greenAccent,
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

                      // Venue Address & Maps Deep Link
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (cleanVenueImageUrl.isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      cleanVenueImageUrl,
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 60,
                                        height: 60,
                                        color: Colors.white10,
                                        child: const Icon(Icons.location_on_rounded, color: Colors.white30),
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        venueName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        venueAddress,
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.6),
                                          fontSize: 11,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (distanceText.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.navigation_outlined, size: 10, color: LunaraTheme.cyberCyan),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$distanceText away',
                                              style: const TextStyle(
                                                color: LunaraTheme.cyberCyan,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                onPressed: () async {
                                  final url = Uri.parse(
                                    lat != null && lng != null && lat != 0.0 && lng != 0.0
                                        ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng'
                                        : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent("$venueName, $venueAddress")}',
                                  );
                                  if (await canLaunchUrl(url)) {
                                    await launchUrl(url, mode: LaunchMode.externalApplication);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Could not open map link')),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.map_outlined, size: 16, color: LunaraTheme.cyberCyan),
                                label: const Text(
                                  'VIEW MAP DIRECTIONS',
                                  style: TextStyle(
                                    color: LunaraTheme.cyberCyan,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  backgroundColor: LunaraTheme.cyberCyan.withValues(alpha: 0.1),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
