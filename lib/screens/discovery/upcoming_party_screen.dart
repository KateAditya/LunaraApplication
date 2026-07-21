import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'venue_detail_screen.dart';
import 'booking_process_screen.dart';

class UpcomingPartyScreen extends StatelessWidget {
  final Map<String, dynamic> party;
  final Map<String, dynamic>? venueMap;

  const UpcomingPartyScreen({super.key, required this.party, this.venueMap});

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

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final String title = party['title']?.toString() ?? 'Special Event';
    final String dateStr = party['date']?.toString() ?? 'Upcoming';
    final String venueName = party['venue']?.toString() ?? 'Unknown Venue';
    final String imageUrl = party['image']?.toString() ?? '';
    final String aboutEventText = (party['aboutEvent'] != null && party['aboutEvent'].toString().trim().isNotEmpty)
        ? party['aboutEvent'].toString().trim()
        : 'Join us for an unforgettable night at $venueName. Get ready for amazing music, great vibes, and an incredible atmosphere. Book your tickets now before they sell out!';

    String? venueImageUrl;
    if (venueMap != null) {
      final images = venueMap!['images'];
      if (images is List && images.isNotEmpty) {
        final firstImg = images[0];
        if (firstImg is Map) {
          venueImageUrl = firstImg['url']?.toString();
        } else if (firstImg is String) {
          venueImageUrl = firstImg;
        }
      }
      if (venueImageUrl == null && venueMap!['imageUrl'] != null) {
        venueImageUrl = venueMap!['imageUrl'].toString();
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
                  
                  // Top Buttons (Back & Favorite)
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
                        // _circleButton(
                        //   icon: Icons.favorite_border_rounded,
                        //   onTap: () {},
                        // ),
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
                  
                  if (venueMap != null && venueMap!.isNotEmpty) ...[
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
                            builder: (_) => VenueDetailScreen(venue: venueMap!),
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
                                    '${venueMap!['city']} • ${venueMap!['area'] ?? venueMap!['addressLine1']}'.toUpperCase(),
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
                  
                  InkWell(
                    onTap: () {
                      if (venueMap != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BookingProcessScreen(
                              venue: venueMap!,
                              isUpcomingNight: true,
                              upcomingNightDate: party['rawDate'] ?? party['date'],
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
                      width: double.infinity,
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
