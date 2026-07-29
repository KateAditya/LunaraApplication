import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme.dart';
import '../../models/venue.dart';
import 'post_detail_screen.dart';
import '../../services/api_service.dart';


class AllPostsScreen extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final List<Venue> venues;

  const AllPostsScreen({super.key, required this.posts, required this.venues});

  @override
  State<AllPostsScreen> createState() => _AllPostsScreenState();
}

class _AllPostsScreenState extends State<AllPostsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late List<Map<String, dynamic>> _filteredPosts;

  @override
  void initState() {
    super.initState();
    _filteredPosts = widget.posts;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      if (_searchQuery.isEmpty) {
        _filteredPosts = widget.posts;
      } else {
        _filteredPosts = widget.posts.where((post) {
          final content = (post['content'] ?? '').toString().toLowerCase();
          final venue = (post['venue'] ?? '').toString().toLowerCase();
          final userName = (post['userName'] ?? '').toString().toLowerCase();
          final firstName = (post['firstName'] ?? '').toString().toLowerCase();
          final lastName = (post['lastName'] ?? '').toString().toLowerCase();
          final q = _searchQuery.toLowerCase();
          return content.contains(q) ||
              venue.contains(q) ||
              userName.contains(q) ||
              firstName.contains(q) ||
              lastName.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchHeader(context),
            Expanded(
              child: _filteredPosts.isEmpty
                  ? const Center(
                      child: Text(
                        'No posts found.',
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      itemCount: _filteredPosts.length,
                      itemBuilder: (context, index) {
                        return _buildPostCard(context, _filteredPosts[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: LunaraTheme.premiumCardShadow,
                border: Border.all(color: Colors.grey[100]!),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: 'Search posts, venues, users...',
                  hintStyle: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.black54),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : const Icon(
                          Icons.search,
                          color: LunaraTheme.electricViolet,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(BuildContext context, Map<String, dynamic> post) {
    // Resolve user avatar
    final String? avatarUrl = ApiService.formatImageUrl(
      post['profilePhotoUrl'] ??
      post['profileImageUrl'] ??
      post['photoUrl'] ??
      post['profilePhoto'] ??
      (post['user'] is Map ? post['user']['photoUrl'] : null) ??
      (post['user'] is Map ? post['user']['profilePhotoUrl'] : null) ??
      post['image'],
    );

    final String venueName = post['venue']?.toString() ?? '';

    final String targetVenueId = (post['venueId'] ?? (post['venue'] is Map ? post['venue']['id'] : null))?.toString() ?? '';

    // Look up venue to get cover image
    Venue? matchedVenueObj;
    if (targetVenueId.isNotEmpty) {
      try {
        matchedVenueObj = widget.venues.firstWhere((v) => v.id == targetVenueId);
      } catch (_) {}
    }
    if (matchedVenueObj == null && venueName.isNotEmpty) {
      final vNameLower = venueName.toLowerCase().trim();
      for (final v in widget.venues) {
        final nameLower = v.name.toLowerCase().trim();
        if (nameLower == vNameLower || nameLower.contains(vNameLower) || vNameLower.contains(nameLower)) {
          matchedVenueObj = v;
          break;
        }
      }
    }

    final Venue matchedVenue = matchedVenueObj ?? (widget.venues.isNotEmpty
        ? widget.venues.first
        : Venue(
            id: '0',
            name: venueName,
            city: 'Pune',
            addressLine1: 'Pune',
            averageRating: 0.0,
          ));

    // Resolve raw image path across all possible keys
    String? rawCover = post['coverImageUrl']?.toString().isNotEmpty == true
        ? post['coverImageUrl']
        : (post['venueImageUrl'] ?? post['venueImage'] ?? post['bannerUrl'] ?? post['bannerImage']);

    if ((rawCover == null || rawCover.toString().isEmpty) && post['venue'] is Map) {
      final vMap = post['venue'] as Map;
      if (vMap['images'] is List && (vMap['images'] as List).isNotEmpty) {
        final first = (vMap['images'] as List).first;
        rawCover = first is Map ? (first['url'] ?? first['imageUrl'] ?? first['filePath']) : (first is String ? first : null);
      }
      rawCover ??= (vMap['imageUrl'] ?? vMap['coverImage'] ?? vMap['photoUrl'] ?? vMap['image'])?.toString();
    }

    if (rawCover == null || rawCover.toString().isEmpty || rawCover.startsWith('Instance of')) {
      rawCover = matchedVenue.imageUrl;
      if ((rawCover == null || rawCover.isEmpty) && matchedVenue.images != null && matchedVenue.images!.isNotEmpty) {
        final firstImg = matchedVenue.images!.first;
        if (firstImg is Map) {
          rawCover = (firstImg['url'] ?? firstImg['imageUrl'] ?? firstImg['filePath'])?.toString();
        } else if (firstImg is String) {
          rawCover = firstImg;
        }
      }
    }

    if (rawCover != null && (rawCover.startsWith('Instance of') || rawCover.startsWith('{'))) {
      rawCover = null;
    }

    // Use venue cover image as background; fall back to user avatar
    final String? coverImageUrl = ApiService.formatImageUrl(rawCover) ?? avatarUrl;

    ImageProvider? bgImage;
    if (coverImageUrl != null && coverImageUrl.isNotEmpty) {
      if (coverImageUrl.startsWith('http')) {
        bgImage = CachedNetworkImageProvider(coverImageUrl);
      } else if (coverImageUrl.startsWith('assets/')) {
        bgImage = AssetImage(coverImageUrl);
      }
    }

    return Container(
      width: double.infinity,
      height: 280,
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image: bgImage != null
            ? DecorationImage(
                image: bgImage,
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.5),
                  BlendMode.darken,
                ),
                onError: (e, s) {},
              )
            : null,
        gradient: bgImage == null ? LunaraTheme.deepPurpleGradient : null,

        color: bgImage == null ? null : Colors.black,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),

      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  PostDetailScreen(post: post, venue: matchedVenue.toMap()),
            ),
          );
        },
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Bottom gradient for text readability
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.3),
                      Colors.black.withValues(alpha: 0.9),
                    ],
                    stops: const [0.4, 0.7, 1.0],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: LunaraTheme.electricViolet,
                        child: Text(
                          ((post['firstName'] ?? post['userName'] ?? 'U')[0])
                              .toString()
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          (post['firstName'] != null &&
                                  post['lastName'] != null)
                              ? '${post['firstName']} ${post['lastName']}'
                              : (post['userName'] ?? 'Lunara User'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: 0.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (post['type'] == 'strangers_meet')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                          child: const Text(
                            'STRANGER MEET',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      const Icon(
                        Icons.location_on_rounded,
                        color: Colors.white70,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        post['venue'].toString().toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    post['content'] ?? '',
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
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
}
