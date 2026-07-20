import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../models/strangers_meet_request.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../widgets/lunara_ticket_widget.dart';
import '../../services/api_service.dart';

class StrangersMeetTicketScreen extends StatefulWidget {
  final StrangersMeetRequest request;

  const StrangersMeetTicketScreen({super.key, required this.request});

  @override
  State<StrangersMeetTicketScreen> createState() => _StrangersMeetTicketScreenState();
}

class _StrangersMeetTicketScreenState extends State<StrangersMeetTicketScreen> {
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
      debugPrint("Error in StrangersMeetTicketScreen location initialization: $e");
    }
  }

  void _shareTicket(BuildContext context) {
    final venueName = widget.request.venue?['name'] ?? 'Unknown Venue';
    final dateStr = DateFormat('MMM dd, yyyy').format(widget.request.eventDateTime);
    final timeStr = DateFormat('hh:mm a').format(widget.request.eventDateTime);
    final ticketId = widget.request.ticketId ?? 'TICKET';

    final hostUser = widget.request.user ?? {};
    final hostName = '${hostUser['firstName'] ?? ''} ${hostUser['lastName'] ?? ''}'.trim();
    final cleanHostName = hostName.isNotEmpty ? hostName : 'Host';

    final joinerUser = _resolveJoinerUser();
    final joinerName = '${joinerUser['firstName'] ?? ''} ${joinerUser['lastName'] ?? ''}'.trim();
    final cleanJoinerName = joinerName.isNotEmpty ? joinerName : 'Joiner';

    final shareText = 'My Strangers Meet Booking on Lunara is Confirmed! 🥳\n\n'
        'Event: ${widget.request.subject}\n'
        'Tagline: ${widget.request.tagline}\n'
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

  Map<String, dynamic> _resolveJoinerUser() {
    Map<String, dynamic> joinerUser = {};
    if (widget.request.joiners != null && widget.request.joiners!.isNotEmpty) {
      final currentUid = ApiService.currentUserId;
      final match = widget.request.joiners!.firstWhere(
        (j) => (j['user']?['id'] ?? j['user']?['_id'] ?? '') == currentUid || (j['id'] ?? j['_id'] ?? '') == currentUid,
        orElse: () => widget.request.joiners![0],
      );
      if (match is Map) {
        joinerUser = Map<String, dynamic>.from(match['user'] ?? match);
      }
    }
    if (joinerUser.isEmpty && ApiService.cachedCurrentUser != null) {
      final cur = ApiService.cachedCurrentUser!;
      joinerUser = {
        'firstName': cur.firstName,
        'lastName': cur.lastName,
        'profilePhoto': cur.profilePhoto,
        'subscriptionTier': cur.subscriptionTier,
        'username': '${cur.firstName.toLowerCase()}.${cur.lastName.toLowerCase()}',
      };
    }
    return joinerUser;
  }

  @override
  Widget build(BuildContext context) {
    final venueName = widget.request.venue?['name'] ?? 'Unknown Venue';
    final venueCity = widget.request.venue?['city'] ?? 'Unknown City';
    final venueArea = widget.request.venue?['area'] ?? '';
    final venueAddress = widget.request.venue?['address'] ?? '${venueArea.isNotEmpty ? "$venueArea, " : ""}$venueCity';
    final images = widget.request.venue?['images'];
    final String venueImageUrl = widget.request.venue?['imageUrl'] ?? (images is List && images.isNotEmpty ? (images.first?['filePath']?.toString() ?? '') : '') ?? '';
    final cleanVenueImageUrl = venueImageUrl.startsWith('/') ? '${ApiService.baseUrl}$venueImageUrl' : venueImageUrl;

    final hostUser = widget.request.user ?? {};
    final hostName = '${hostUser['firstName'] ?? ''} ${hostUser['lastName'] ?? ''}'.trim();
    final cleanHostName = hostName.isNotEmpty ? hostName : 'Host';
    final hostUsername = '@${hostUser['username'] ?? hostUser['firstName']?.toString().toLowerCase() ?? 'host'}';

    final joinerUser = _resolveJoinerUser();
    final joinerName = '${joinerUser['firstName'] ?? ''} ${joinerUser['lastName'] ?? ''}'.trim();
    final cleanJoinerName = joinerName.isNotEmpty ? joinerName : 'Joiner';
    final joinerUsername = '@${joinerUser['username'] ?? joinerUser['firstName']?.toString().toLowerCase() ?? 'joiner'}';

    final ticketId = widget.request.ticketId ?? 'TICKET';
    final amountPaid = widget.request.paymentAmount ?? widget.request.chargesPerHead;

    final latVal = widget.request.venue?['latitude'];
    final lngVal = widget.request.venue?['longitude'];
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
          'Your Ticket',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 2,
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
              const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Payment Successful!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your strangers meet event is confirmed.',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 32),

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
                              'STRANGERS MEET',
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
                      const SizedBox(height: 20),
                      Text(
                        widget.request.subject.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.request.tagline,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTicketDetail('DATE', DateFormat('MMM dd, yyyy').format(widget.request.eventDateTime)),
                          ),
                          Expanded(
                            child: _buildTicketDetail('TIME', DateFormat('hh:mm a').format(widget.request.eventDateTime)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTicketDetail('PERSONS', '${widget.request.numberOfPersons} pax'),
                          ),
                          const Spacer(),
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
                                  radius: 32,
                                  showGradientBorder: true,
                                  isInteractive: true,
                                ),
                                const SizedBox(height: 8),
                                Text(cleanHostName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                                Text(hostUsername, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: LunaraTheme.electricViolet.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10), border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.5), width: 1)),
                                  child: const Text('HOST', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                ),
                              ],
                            ),
                          ),
                          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle), child: const Icon(Icons.favorite_rounded, color: LunaraTheme.hotPink, size: 18)),
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
                                Text(cleanJoinerName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                                Text(joinerUsername, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: LunaraTheme.cyberCyan.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10), border: Border.all(color: LunaraTheme.cyberCyan.withValues(alpha: 0.4), width: 1)),
                                  child: const Text('PARTNER', style: TextStyle(color: LunaraTheme.cyberCyan, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: LunaraTheme.cyberCyan.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.account_balance_wallet_rounded, color: LunaraTheme.cyberCyan, size: 18)),
                                const SizedBox(width: 10),
                                const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('DEPOSIT STATUS', style: TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                    SizedBox(height: 2),
                                    Text('Lunara Secure Pay', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('AMOUNT PAID', style: TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text('₹${amountPaid.toStringAsFixed(0)}', style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 4),
                                    Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)), child: const Text('PAID', style: TextStyle(color: Colors.greenAccent, fontSize: 7, fontWeight: FontWeight.bold))),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), image: DecorationImage(image: NetworkImage(cleanVenueImageUrl.isNotEmpty ? cleanVenueImageUrl : 'https://picsum.photos/seed/venue/100/100'), fit: BoxFit.cover), border: Border.all(color: Colors.white24)),
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
                                      Text(venueAddress, style: const TextStyle(color: Colors.white70, fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white12, height: 16),
                            SizedBox(
                              width: double.infinity, height: 32,
                              child: TextButton.icon(
                                onPressed: () async {
                                  final mapUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent("$venueName, $venueAddress")}');
                                  if (await canLaunchUrl(mapUrl)) { await launchUrl(mapUrl, mode: LaunchMode.externalApplication); }
                                },
                                icon: const Icon(Icons.map_rounded, color: LunaraTheme.cyberCyan, size: 14),
                                label: const Text('VIEW MAP DIRECTIONS', style: TextStyle(color: LunaraTheme.cyberCyan, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: LunaraTheme.cyberCyan.withValues(alpha: 0.08), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              if (widget.request.ticketUrl != null && widget.request.ticketUrl!.isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final pdfUri = Uri.parse(widget.request.ticketUrl!);
                      if (await canLaunchUrl(pdfUri)) {
                        await launchUrl(pdfUri, mode: LaunchMode.externalApplication);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Could not open the PDF URL.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.download_rounded, color: Colors.white),
                    label: const Text('DOWNLOAD PDF TICKET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LunaraTheme.electricViolet,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => _shareTicket(context),
                  icon: const Icon(Icons.share_rounded, color: Colors.white),
                  label: const Text('SHARE TICKET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('BACK TO REQUESTS', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
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
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
