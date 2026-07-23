import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import 'venue_detail_screen.dart';
import 'booking_process_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _checkInitialInterest();
  }

  Future<void> _checkInitialInterest() async {
    final venueId = widget.venueMap?['id']?.toString() ?? widget.party['venueId']?.toString() ?? '';
    final date = widget.party['rawDate']?.toString() ?? widget.party['date']?.toString() ?? '';
    if (venueId.isNotEmpty && date.isNotEmpty) {
      final isInt = await ApiService.checkNightInterest(venueId: venueId, date: date);
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
    final venueId = widget.venueMap?['id']?.toString() ?? widget.party['venueId']?.toString() ?? '';
    final date = widget.party['rawDate']?.toString() ?? widget.party['date']?.toString() ?? '';

    if (venueId.isEmpty || date.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Venue or date missing for marking interest.'),
          backgroundColor: LunaraTheme.electricViolet,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isToggling = true);

    if (_isInterested) {
      final success = await ApiService.removeNightInterest(venueId: venueId, date: date);
      if (mounted) {
        if (success) {
          setState(() {
            _isInterested = false;
            _isToggling = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Interest removed.'),
              backgroundColor: Colors.black87,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          setState(() => _isToggling = false);
        }
      }
    } else {
      final success = await ApiService.markNightInterested(venueId: venueId, date: date);
      if (mounted) {
        if (success) {
          setState(() {
            _isInterested = true;
            _isToggling = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Marked as Interested! 🎉 Host will be able to see you in Interested Partners.'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          setState(() => _isToggling = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final String title = widget.party['title']?.toString() ?? 'Special Event';
    final String dateStr = widget.party['date']?.toString() ?? 'Upcoming';
    final String venueName = widget.party['venue']?.toString() ?? 'Unknown Venue';
    final String imageUrl = widget.party['image']?.toString() ?? '';
    final String aboutEventText = (widget.party['aboutEvent'] != null && widget.party['aboutEvent'].toString().trim().isNotEmpty)
        ? widget.party['aboutEvent'].toString().trim()
        : 'Join us for an unforgettable night at $venueName. Get ready for amazing music, great vibes, and an incredible atmosphere. Book your tickets now before they sell out!';

    String? venueImageUrl;
    if (widget.venueMap != null) {
      final images = widget.venueMap!['images'];
      if (images is List && images.isNotEmpty) {
        final firstImg = images[0];
        if (firstImg is Map) {
          venueImageUrl = firstImg['url']?.toString();
        } else if (firstImg is String) {
          venueImageUrl = firstImg;
        }
      }
      if (venueImageUrl == null && widget.venueMap!['imageUrl'] != null) {
        venueImageUrl = widget.venueMap!['imageUrl'].toString();
      }
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
                        child: const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                      ),
                    )
                  else
                    Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.event, size: 50, color: Colors.grey),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: LunaraTheme.cyberCyan.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: LunaraTheme.cyberCyan.withValues(alpha: 0.5)),
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
                            const Icon(Icons.location_on_rounded, color: LunaraTheme.cyberCyan, size: 16),
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
                  
                  if (widget.venueMap != null && widget.venueMap!.isNotEmpty) ...[
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
                            builder: (_) => VenueDetailScreen(venue: widget.venueMap!),
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
                              color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                          border: Border.all(
                            color: const Color(0xFF7F00FF).withValues(alpha: 0.08),
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
                                image: venueImageUrl != null && venueImageUrl.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(venueImageUrl),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: venueImageUrl == null || venueImageUrl.isEmpty
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
                                  const SizedBox(height: 4),
                                  Text(
                                    '${widget.venueMap!['city']} • ${widget.venueMap!['area'] ?? widget.venueMap!['addressLine1']}'.toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios, size: 16, color: LunaraTheme.electricViolet),
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
                          onTap: _isToggling ? null : _toggleInterest,
                          borderRadius: BorderRadius.circular(16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: _isInterested ? LunaraTheme.primaryGradient : null,
                              color: _isInterested ? null : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _isInterested
                                    ? Colors.transparent
                                    : LunaraTheme.electricViolet,
                                width: 1.8,
                              ),
                              boxShadow: _isInterested
                                  ? [
                                      BoxShadow(
                                        color: LunaraTheme.electricViolet.withValues(alpha: 0.35),
                                        blurRadius: 14,
                                        offset: const Offset(0, 6),
                                      ),
                                    ]
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.03),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _isToggling
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _isInterested ? Colors.white : LunaraTheme.electricViolet,
                                        ),
                                      )
                                    : Icon(
                                        _isInterested ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                        color: _isInterested ? Colors.white : LunaraTheme.electricViolet,
                                        size: 20,
                                      ),
                                const SizedBox(width: 8),
                                Text(
                                  _isInterested ? 'INTERESTED ✓' : 'INTERESTED',
                                  style: TextStyle(
                                    color: _isInterested ? Colors.white : LunaraTheme.electricViolet,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
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
                            if (widget.venueMap != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BookingProcessScreen(
                                    venue: widget.venueMap!,
                                    isUpcomingNight: true,
                                    upcomingNightDate: widget.party['rawDate'] ?? widget.party['date'],
                                    upcomingNightTime: '20:00',
                                  ),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Venue details not available for booking.'),
                                  backgroundColor: LunaraTheme.electricViolet,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: LunaraTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'BOOK NOW',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  letterSpacing: 1.5,
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
