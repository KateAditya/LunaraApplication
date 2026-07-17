import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../services/api_service.dart';

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

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
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
      debugPrint("Error in PartyPlanTicketScreen location initialization: $e");
    }
  }

  void _shareTicket(BuildContext context) {
    final venue = widget.plan['venue'] ?? {};
    final venueName = venue['name'] ?? 'Unknown Venue';
    final planDateTime = widget.plan['planDateTime'] != null
        ? DateTime.tryParse(widget.plan['planDateTime'].toString())?.toLocal() ?? DateTime.now()
        : DateTime.now();
    final dateStr = DateFormat('MMM dd, yyyy').format(planDateTime);
    final timeStr = DateFormat('hh:mm a').format(planDateTime);
    final description = widget.plan['message'] ?? widget.plan['description'] ?? 'Party Plan Vibe';
    final ticketId = (widget.request['id']?.toString() ?? 'TICKET').toUpperCase();

    final hostUser = widget.plan['user'] ?? widget.plan['host'] ?? {};
    final hostName = '${hostUser['firstName'] ?? ''} ${hostUser['lastName'] ?? ''}'.trim();
    final cleanHostName = hostName.isNotEmpty ? hostName : 'Host';

    final joinerUser = widget.request['requester'] ?? {};
    final joinerName = '${joinerUser['firstName'] ?? ''} ${joinerUser['lastName'] ?? ''}'.trim();
    final cleanJoinerName = joinerName.isNotEmpty ? joinerName : 'Joiner';

    final shareText = 'My Party Plan Booking on Lunara is Confirmed! 🥳\n\n'
        'Event: $description\n'
        'Venue: $venueName\n'
        'Date: $dateStr • $timeStr\n'
        'Host: $cleanHostName\n'
        'Joiner: $cleanJoinerName\n'
        'Ticket ID: $ticketId\n\n'
        'See you there! 💜';

    final box = context.findRenderObject() as RenderBox?;
    Share.share(
      shareText,
      subject: 'My Lunara Ticket',
      sharePositionOrigin: box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final venue = widget.plan['venue'] ?? {};
    final venueName = venue['name'] ?? 'Unknown Venue';
    final venueCity = venue['city'] ?? 'Unknown City';
    final venueArea = venue['area'] ?? '';
    final venueAddress = venue['address'] ?? '${venueArea.isNotEmpty ? "$venueArea, " : ""}$venueCity';
    final venueImageUrl = venue['imageUrl'] ?? (venue['images'] != null && (venue['images'] as List).isNotEmpty ? venue['images'][0]['filePath'] : null) ?? '';
    final cleanVenueImageUrl = venueImageUrl.startsWith('/') ? '${ApiService.baseUrl}$venueImageUrl' : venueImageUrl;

    final planDateTime = widget.plan['planDateTime'] != null
        ? DateTime.tryParse(widget.plan['planDateTime'].toString())?.toLocal() ??
              DateTime.now()
        : DateTime.now();

    final hostUser = widget.plan['user'] ?? widget.plan['host'] ?? {};
    final hostName =
        '${hostUser['firstName'] ?? ''} ${hostUser['lastName'] ?? ''}'.trim();
    final cleanHostName = hostName.isNotEmpty ? hostName : 'Host';
    final hostUsername = '@${hostUser['username'] ?? hostUser['firstName']?.toString().toLowerCase() ?? 'host'}';

    final joinerUser = widget.request['requester'] ?? {};
    final joinerName =
        '${joinerUser['firstName'] ?? ''} ${joinerUser['lastName'] ?? ''}'
            .trim();
    final cleanJoinerName = joinerName.isNotEmpty ? joinerName : 'Joiner';
    final joinerUsername = '@${joinerUser['username'] ?? joinerUser['firstName']?.toString().toLowerCase() ?? 'joiner'}';

    final ticketId = (widget.request['id']?.toString() ?? 'TICKET').toUpperCase();
    final description =
        widget.plan['message'] ?? widget.plan['description'] ?? 'Party Plan Vibe';

    final rawAmount = widget.request['paymentAmount'] ?? widget.plan['depositAmount'] ?? widget.request['amountPaid'] ?? widget.plan['amountPaid'] ?? (widget.plan['paymentType'] == 'self_pay' ? 198.0 : 99.0);
    final double amountPaid = double.tryParse(rawAmount.toString()) ?? 99.0;

    final latVal = venue['latitude'];
    final lngVal = venue['longitude'];
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

    return Scaffold(
      backgroundColor: LunaraTheme.midnightBlack,
      appBar: AppBar(
        title: const Text(
          'PARTY PLAN TICKET',
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
              // Success Indicator
              const Icon(
                Icons.stars_rounded,
                color: Colors.greenAccent,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'Booking Confirmed!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Both deposits are paid. Show this at the venue.',
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // The Ticket Card
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [LunaraTheme.electricViolet, Color(0xFF4C1D95)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Top Info Section
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'LUNARA VIBE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              Text(
                                ticketId.length > 12
                                    ? ticketId.substring(0, 12)
                                    : ticketId,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            description,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Details Grid
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
                                  DateFormat('hh:mm a').format(planDateTime),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Dashed Divider line
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: LunaraTheme.midnightBlack,
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                mainAxisSize: MainAxisSize.max,
                                children: List.generate(
                                  (constraints.constrainWidth() / 10).floor(),
                                  (index) => const SizedBox(
                                    width: 5,
                                    height: 2,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.white54,
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
                            color: LunaraTheme.midnightBlack,
                            borderRadius: BorderRadius.horizontal(
                              left: Radius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Dynamic Info & Profiles Section (Replacing QR)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: Column(
                        children: [
                          // Dual Profile Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Host Column
                              Expanded(
                                child: Column(
                                  children: [
                                    LunaraProfileImage(
                                      userData: hostUser,
                                      radius: 32,
                                      showGradientBorder: true,
                                      isInteractive: true,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      cleanHostName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                    Text(
                                      hostUsername,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.5), width: 1),
                                      ),
                                      child: const Text(
                                        'HOST',
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
                              // Heart connector icon
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.favorite_rounded,
                                  color: LunaraTheme.hotPink,
                                  size: 18,
                                ),
                              ),
                              // Joiner/Partner Column
                              Expanded(
                                child: Column(
                                  children: [
                                    LunaraProfileImage(
                                      userData: joinerUser,
                                      radius: 32,
                                      showGradientBorder: true,
                                      isInteractive: true,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      cleanJoinerName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                    Text(
                                      joinerUsername,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: LunaraTheme.cyberCyan.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: LunaraTheme.cyberCyan.withValues(alpha: 0.4), width: 1),
                                      ),
                                      child: const Text(
                                        'PARTNER',
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
                          const SizedBox(height: 20),

                          // Payment details card
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
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
                                          'DEPOSIT STATUS',
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
                                      'AMOUNT PAID',
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
                                          '₹${amountPaid.toStringAsFixed(0)}',
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

                          // Venue Details Card with map navigation
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
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
                                          image: NetworkImage(
                                            cleanVenueImageUrl.isNotEmpty
                                                ? cleanVenueImageUrl
                                                : 'https://picsum.photos/seed/venue/100/100',
                                          ),
                                          fit: BoxFit.cover,
                                        ),
                                        border: Border.all(color: Colors.white24),
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
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w900,
                                                  ),
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
                                                    color: LunaraTheme.cyberCyan.withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: LunaraTheme.cyberCyan.withValues(alpha: 0.4),
                                                      width: 0.5,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    distanceText,
                                                    style: const TextStyle(
                                                      color: LunaraTheme.cyberCyan,
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
                                              color: Colors.white70,
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
                                const Divider(color: Colors.white12, height: 16),
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
                                      color: LunaraTheme.cyberCyan,
                                      size: 14,
                                    ),
                                    label: const Text(
                                      'VIEW MAP DIRECTIONS',
                                      style: TextStyle(
                                        color: LunaraTheme.cyberCyan,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      backgroundColor: LunaraTheme.cyberCyan.withValues(alpha: 0.08),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
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
              ),

              const SizedBox(height: 40),

              // Action Buttons
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () => _shareTicket(context),
                  icon: const Icon(Icons.share_rounded, color: Colors.white),
                  label: const Text(
                    'SHARE TICKET',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'CLOSE',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
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
            fontSize: 10,
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
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
