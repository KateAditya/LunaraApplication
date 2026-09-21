import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import 'venue_detail_screen.dart';
import 'party_event_booking_sheet.dart';
import '../../widgets/night_partner_selector_sheet.dart';
import '../../widgets/upcoming_night_post_partner_sheet.dart';
import '../../utils/lunara_date_formatter.dart';
import '../../widgets/lunara_cached_image.dart';

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
  bool _isInterestLoading = true;
  // Re-enabled: the event-linked plan flow behind this button now resolves the
  // event's real ticket price server-side, holds seats against the event's
  // capacity, and refunds through the existing cancellation path.
  final bool _showPostPartnerButton = true;
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

  String _formatDateIso(dynamic raw) {
    if (raw == null) return '';
    final clean = raw.toString().trim();
    if (clean.isEmpty) return '';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(clean)) {
      return clean;
    }
    try {
      final parsed = DateTime.parse(clean);
      final yyyy = parsed.year;
      final mm = parsed.month.toString().padLeft(2, '0');
      final dd = parsed.day.toString().padLeft(2, '0');
      return '$yyyy-$mm-$dd';
    } catch (_) {}

    final dt = LunaraDateFormatter.parseToLocal(raw);
    if (dt != null) {
      final yyyy = dt.year;
      final mm = dt.month.toString().padLeft(2, '0');
      final dd = dt.day.toString().padLeft(2, '0');
      return '$yyyy-$mm-$dd';
    }

    final patterns = [
      'yyyy-MM-dd',
      'yyyy/MM/dd',
      'dd-MM-yyyy',
      'dd/MM/yyyy',
      'MMM dd, yyyy',
      'MMMM dd, yyyy',
      'dd MMM yyyy',
      'dd MMMM yyyy',
      'EEEE, MMM dd, yyyy',
      'EEEE, MMM dd',
      'EEE, MMM dd',
      'MMM dd',
    ];
    for (final p in patterns) {
      try {
        final parsed = DateFormat(p).parse(clean);
        int year = parsed.year;
        if (year == 1970) {
          year = DateTime.now().year;
        }
        final yyyy = year;
        final mm = parsed.month.toString().padLeft(2, '0');
        final dd = parsed.day.toString().padLeft(2, '0');
        return '$yyyy-$mm-$dd';
      } catch (_) {}
    }

    return clean;
  }

  String _getEffectiveEventDate() {
    final raw = widget.party['eventDate'] ??
        widget.party['rawDate'] ??
        widget.party['fromDate'] ??
        widget.party['toDate'] ??
        widget.party['bannerFromDate'] ??
        widget.party['date'] ??
        '';
    return _formatDateIso(raw);
  }

  Future<void> _checkInitialInterest() async {
    final venueId =
        widget.venueMap?['id']?.toString() ??
        widget.party['venueId']?.toString() ??
        '';
    final date = _getEffectiveEventDate();
    if (venueId.isNotEmpty) {
      final isInt = await ApiService.checkNightInterest(
        venueId: venueId,
        date: date,
      );
      if (mounted) {
        setState(() {
          _isInterested = isInt;
          _isInterestLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isInterestLoading = false;
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
    final date = _getEffectiveEventDate();

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
                    LunaraCachedImage(
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

                  const SizedBox(height: 28),

                  // Post to Find Partner Button (Disabled for now as requested; logic preserved)
                  if (_showPostPartnerButton) ...[
                    InkWell(
                      onTap: () {
                        final venueId = widget.venueMap?['id']?.toString() ?? widget.party['venueId']?.toString() ?? '';
                        final vName = venueName;
                        final eventDate = _getEffectiveEventDate();
                        final eventTime = LunaraDateFormatter.normalizeTimeTo12Hour(widget.party['time']?.toString() ?? '8:00 PM');
                        final flyer = widget.party['image'] ?? widget.party['coverImageUrl'] ?? widget.party['imagePath'];
                        final title = widget.party['title'] ?? widget.party['name'] ?? vName;

                        UpcomingNightPostPartnerSheet.show(
                          context,
                          party: widget.party,
                          venueId: venueId,
                          venueName: vName,
                          date: eventDate,
                          time: eventTime,
                          bannerImage: flyer?.toString(),
                          eventTitle: title?.toString(),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF7C3AED),
                              Color(0xFFEC4899),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.campaign_rounded, color: Colors.white, size: 19),
                              SizedBox(width: 8),
                              Text(
                                'POST TO FIND PARTNER',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12.5,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              SizedBox(width: 5),
                              Text('✨', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Action Row: Interested + Invite Partner + Book Now
                  Row(
                    children: [
                      // Interested Button
                      Expanded(
                        flex: 4,
                        child: InkWell(
                          onTap: (_isToggling || _isInterestLoading) ? null : _toggleInterest,
                          borderRadius: BorderRadius.circular(16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 54,
                            decoration: BoxDecoration(
                              color: _isInterested
                                  ? LunaraTheme.electricViolet.withValues(alpha: 0.12)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: LunaraTheme.electricViolet,
                                width: 2.0,
                              ),
                              boxShadow: _isInterested
                                  ? [
                                      BoxShadow(
                                        color: LunaraTheme.electricViolet.withValues(alpha: 0.25),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.03),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: (_isToggling || _isInterestLoading)
                                  ? const Center(
                                      key: ValueKey('interest_loading'),
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
                                      key: ValueKey('interest_loaded_$_isInterested'),
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
                                              size: 18,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _isInterested ? 'INTERESTED ✓' : 'INTERESTED',
                                              style: const TextStyle(
                                                color: LunaraTheme.electricViolet,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 12,
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
                      ),
                      const SizedBox(width: 8),

                      // Invite Partner Button
                      Expanded(
                        flex: 4,
                        child: InkWell(
                          onTap: () {
                            final flyer = widget.party['image'] ?? widget.party['coverImageUrl'] ?? widget.party['imagePath'];
                            final title = widget.party['title'] ?? widget.party['name'] ?? venueName;
                            NightPartnerSelectorSheet.show(
                              context,
                              party: {
                                ...widget.party,
                                if (currentVenue != null) 'venueMap': currentVenue,
                              },
                              venueId: widget.venueMap?['id']?.toString() ?? widget.party['venueId']?.toString() ?? '',
                              venueName: venueName,
                              date: _getEffectiveEventDate(),
                              time: widget.party['time']?.toString() ?? '20:00',
                              bannerImage: flyer?.toString(),
                              eventTitle: title?.toString(),
                            );
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            height: 54,
                            decoration: BoxDecoration(
                              color: LunaraTheme.electricViolet,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.person_add_rounded, color: Colors.white, size: 18),
                                      SizedBox(width: 6),
                                      Text(
                                        'INVITE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Book Now Button
                      Expanded(
                        flex: 4,
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
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: LunaraTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
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
                                      fontSize: 12,
                                      letterSpacing: 1.0,
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
