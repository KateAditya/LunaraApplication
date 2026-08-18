import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import 'venue_detail_screen.dart';
import 'party_event_booking_sheet.dart';

class UpcomingPartyScreen extends StatefulWidget {
  final Map<String, dynamic> party;
  final Map<String, dynamic>? venueMap;

  const UpcomingPartyScreen({super.key, required this.party, this.venueMap});

  @override
  State<UpcomingPartyScreen> createState() => _UpcomingPartyScreenState();
}

class _UpcomingPartyScreenState extends State<UpcomingPartyScreen> {
  bool _isInterested = false;
  bool _isToggling = false;
  Map<String, dynamic>? _venueData;
  Map<String, dynamic>? get currentVenue => _venueData ?? widget.venueMap;

  @override
  void initState() {
    super.initState();
    _checkInitialInterest();
    _loadFullVenueDetails();
  }

  Future<void> _loadFullVenueDetails() async {
    final venueId = widget.venueMap?['id']?.toString() ?? widget.party['venueId']?.toString() ?? '';
    if (venueId.isEmpty) return;
    try {
      final res = await ApiService.get('/api/venues/$venueId');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        if (data != null && data['venue'] is Map) {
          setState(() {
            _venueData = Map<String, dynamic>.from(data['venue']);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading full venue details in UpcomingPartyScreen: $e');
    }
  }

  String _formatDateIso(String raw) {
    final clean = raw.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(clean)) {
      return clean;
    }
    try {
      final parsed = DateTime.parse(clean);
      final yyyy = parsed.year;
      final mm = parsed.month.toString().padLeft(2, '0');
      final dd = parsed.day.toString().padLeft(2, '0');
      return '$yyyy-$mm-$dd';
    } catch (_) {
      final now = DateTime.now();
      final yyyy = now.year;
      final mm = now.month.toString().padLeft(2, '0');
      final dd = now.day.toString().padLeft(2, '0');
      return '$yyyy-$mm-$dd';
    }
  }

  Future<void> _checkInitialInterest() async {
    final venueId =
        widget.venueMap?['id']?.toString() ??
        widget.party['venueId']?.toString() ??
        '';
    final rawDate =
        widget.party['rawDate']?.toString() ??
        widget.party['date']?.toString() ??
        '';
    final date = _formatDateIso(rawDate);
    if (venueId.isNotEmpty) {
      final isInt = await ApiService.checkNightInterest(
        venueId: venueId,
        date: date,
      );
      if (mounted) {
        setState(() {
          _isInterested = isInt;
        });
      }
    }
  }

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Future<void> _toggleInterest() async {
    final venueId =
        widget.venueMap?['id']?.toString() ??
        widget.party['venueId']?.toString() ??
        '';
    final rawDate =
        widget.party['rawDate']?.toString() ??
        widget.party['date']?.toString() ??
        '';
    final date = _formatDateIso(rawDate);

    if (venueId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Venue missing for marking interest.'),
          backgroundColor: LunaraTheme.electricViolet,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final bool previousState = _isInterested;

    // 1. Optimistic Instant UI Update
    setState(() {
      _isInterested = !previousState;
      _isToggling = true;
    });

    if (previousState) {
      // Reverting interest (removing)
      final success = await ApiService.removeNightInterest(
        venueId: venueId,
        date: date,
      );
      if (mounted) {
        setState(() => _isToggling = false);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Interest removed.'),
              backgroundColor: Colors.black87,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          // Revert state on failure
          setState(() => _isInterested = previousState);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not update interest. Please try again.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } else {
      // Adding interest
      final success = await ApiService.markNightInterested(
        venueId: venueId,
        date: date,
      );
      if (mounted) {
        setState(() => _isToggling = false);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Marked as Interested! 🎉 Host can view your profile.',
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          // Revert state on failure
          setState(() => _isInterested = previousState);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not update interest. Please try again.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final String title = widget.party['title']?.toString() ?? 'Special Event';
    final String dateStr = widget.party['date']?.toString() ?? 'Upcoming';
    final resolvedVenue = currentVenue;
    final String venueName = (resolvedVenue?['name'] ?? widget.party['venue'] ?? 'Venue').toString();
    final String imageUrl = widget.party['image']?.toString() ?? '';
    final String aboutEventText =
        (widget.party['aboutEvent'] != null &&
            widget.party['aboutEvent'].toString().trim().isNotEmpty)
        ? widget.party['aboutEvent'].toString().trim()
        : 'Join us for an unforgettable night at $venueName. Get ready for amazing music, great vibes, and an incredible atmosphere. Book your tickets now before they sell out!';

    String venueImageUrl = '';
    if (resolvedVenue != null) {
      if (resolvedVenue['coverImage'] != null) {
        if (resolvedVenue['coverImage'] is Map) {
          venueImageUrl = (resolvedVenue['coverImage']['url'] ?? resolvedVenue['coverImage']['filePath'] ?? '').toString();
        } else {
          venueImageUrl = resolvedVenue['coverImage'].toString();
        }
      } else if (resolvedVenue['image'] != null) {
        venueImageUrl = resolvedVenue['image'].toString();
      } else if (resolvedVenue['imageUrl'] != null) {
        venueImageUrl = resolvedVenue['imageUrl'].toString();
      } else if (resolvedVenue['primaryPhoto'] != null) {
        venueImageUrl = resolvedVenue['primaryPhoto'].toString();
      }
      if (venueImageUrl.isNotEmpty && !venueImageUrl.startsWith('http')) {
        final clean = venueImageUrl.replaceAll(r'\', '/');
        final formatted = clean.startsWith('/') ? clean : '/$clean';
        venueImageUrl = '${ApiService.baseUrl}$formatted';
      }
    }

    final String cityRaw = (resolvedVenue?['city'] ?? '').toString().trim();
    final String areaRaw = (resolvedVenue?['area'] ?? resolvedVenue?['addressLine1'] ?? '').toString().trim();
    final String cleanCity = (cityRaw.isNotEmpty && cityRaw.toLowerCase() != 'null') ? cityRaw : '';
    final String cleanArea = (areaRaw.isNotEmpty && areaRaw.toLowerCase() != 'null') ? areaRaw : '';
    String venueLocationText = '';
    if (cleanCity.isNotEmpty && cleanArea.isNotEmpty) {
      venueLocationText = '$cleanCity • $cleanArea';
    } else if (cleanCity.isNotEmpty) {
      venueLocationText = cleanCity;
    } else if (cleanArea.isNotEmpty) {
      venueLocationText = cleanArea;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: screenWidth * 1.35,
            pinned: true,
            stretch: true,
            backgroundColor: Colors.white,
            automaticallyImplyLeading: false,
            leadingWidth: 0,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl.isNotEmpty)
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[200],
                        child: const Icon(
                          Icons.broken_image,
                          size: 50,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  else
                    Container(
                      color: Colors.grey[200],
                      child: const Icon(
                        Icons.event,
                        size: 50,
                        color: Colors.grey,
                      ),
                    ),

                  // Gradient Overlay for Text Legibility
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.4),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.85),
                          ],
                          stops: const [0.0, 0.2, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Top Buttons (Back)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 10,
                    left: 20,
                    right: 20,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _circleButton(
                          icon: Icons.arrow_back_ios_new,
                          onTap: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Info Overlay
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: LunaraTheme.cyberCyan.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: LunaraTheme.cyberCyan.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          child: Text(
                            dateStr.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          title.toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'AllroundGothic',
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.5,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              color: LunaraTheme.cyberCyan,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                venueName.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ABOUT THIS EVENT',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: 1,
                      fontFamily: 'AllroundGothic',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Text(
                      aboutEventText,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.6,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  if (currentVenue != null && currentVenue!.isNotEmpty) ...[
                    const Text(
                      'HOSTED AT',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: 1,
                        fontFamily: 'AllroundGothic',
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VenueDetailScreen(
                              venue: currentVenue!,
                              initialPartyEvent: widget.party['rawAd'] is Map
                                  ? widget.party['rawAd']
                                  : widget.party,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LunaraTheme.cardGradient,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: LunaraTheme.electricViolet.withValues(
                                alpha: 0.08,
                              ),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                          border: Border.all(
                            color: const Color(0x147F00FF),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.grey[200],
                                image: venueImageUrl.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(venueImageUrl),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: venueImageUrl.isEmpty
                                  ? const Icon(Icons.store, color: Colors.grey)
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    venueName.toUpperCase(),
                                    style: const TextStyle(
                                      fontFamily: 'AllroundGothic',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (venueLocationText.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      venueLocationText.toUpperCase(),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: LunaraTheme.electricViolet,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Action Row: Interested + Book Now
                  Row(
                    children: [
                      // Interested Button
                      Expanded(
                        flex: 5,
                        child: InkWell(
                          onTap: _toggleInterest,
                          borderRadius: BorderRadius.circular(16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 56,
                            decoration: BoxDecoration(
                              color: _isInterested
                                  ? LunaraTheme.electricViolet.withValues(
                                      alpha: 0.12,
                                    )
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: LunaraTheme.electricViolet,
                                width: 2.0,
                              ),
                              boxShadow: _isInterested
                                  ? [
                                      BoxShadow(
                                        color: LunaraTheme.electricViolet
                                            .withValues(alpha: 0.25),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.03,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                            ),
                            child: _isToggling
                                ? const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: LunaraTheme.electricViolet,
                                      ),
                                    ),
                                  )
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _isInterested
                                                ? Icons.favorite_rounded
                                                : Icons.favorite_border_rounded,
                                            color: LunaraTheme.electricViolet,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 6),
                                    Text(
                                      _isInterested ? 'INTERESTED ✓' : 'INTERESTED',
                                      style: const TextStyle(
                                        color: LunaraTheme.electricViolet,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Book Now Button
                      Expanded(
                        flex: 6,
                        child: InkWell(
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => Padding(
                                padding: EdgeInsets.only(
                                  bottom: MediaQuery.of(context).viewInsets.bottom,
                                ),
                                child: PartyEventBookingSheet(event: widget.party),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: LunaraTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: LunaraTheme.electricViolet.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6.0),
                                  child: Text(
                                    'BOOK NOW',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
