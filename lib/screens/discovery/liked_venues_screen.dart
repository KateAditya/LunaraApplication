import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'venue_detail_screen.dart';

/// Static in-memory store for liked venues (will be replaced with server persistence later)
class LikedVenuesStore {
  static final List<Map<String, dynamic>> _likedVenues = [];

  static List<Map<String, dynamic>> get venues =>
      List.unmodifiable(_likedVenues);

  static bool isLiked(Map<String, dynamic> venue) {
    return _likedVenues.any((v) => v['name'] == venue['name']);
  }

  static void toggle(Map<String, dynamic> venue) {
    if (isLiked(venue)) {
      _likedVenues.removeWhere((v) => v['name'] == venue['name']);
    } else {
      _likedVenues.add(Map<String, dynamic>.from(venue));
    }
  }
}

class LikedVenuesScreen extends StatefulWidget {
  const LikedVenuesScreen({super.key});

  @override
  State<LikedVenuesScreen> createState() => _LikedVenuesScreenState();
}

class _LikedVenuesScreenState extends State<LikedVenuesScreen> {
  @override
  Widget build(BuildContext context) {
    final venues = LikedVenuesStore.venues;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: venues.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            color: Colors.grey[100],
                            size: 80,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'No liked venues yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tap the heart icon on any venue to save it here',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      itemCount: venues.length,
                      itemBuilder: (context, index) {
                        return _buildVenueCard(venues[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Text(
            'LIKED VENUES',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
          const Spacer(),
          const Icon(Icons.favorite_rounded, color: LunaraTheme.electricViolet, size: 24),
        ],
      ),
    );
  }

  Widget _buildVenueCard(Map<String, dynamic> venue) {
    final String name = venue['name'] ?? 'Unknown Venue';
    final num rating = venue['averageRating'] ?? 4.5;
    final String type = venue['type'] ?? venue['category'] ?? 'Venue';
    final String address = venue['addressLine1'] ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VenueDetailScreen(venue: venue),
            ),
          );
          // Refresh in case user unliked the venue
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LunaraTheme.cardGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: LunaraTheme.premiumCardShadow,
            border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          rating.toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          type.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        address,
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.favorite_rounded, color: LunaraTheme.electricViolet),
                onPressed: () {
                  setState(() {
                    LikedVenuesStore.toggle(venue);
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
