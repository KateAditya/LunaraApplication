import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:carousel_slider/carousel_slider.dart';
import '../../core/theme.dart';
import 'venue_detail_screen.dart';
import 'all_venues_screen.dart';
import 'upcoming_party_screen.dart';
import '../social/all_posts_screen.dart';
import '../../services/api_service.dart';
import '../../models/venue.dart';
import '../../models/user.dart';
import '../../widgets/lunara_profile_image.dart';
import 'all_users_screen.dart';
import '../social/post_detail_screen.dart';
import '../social/chat_screen.dart';
import '../profile/profile_screen.dart';
import '../../services/app_tour_service.dart';
import '../../widgets/vip_upgrade_button.dart';

class DiscoveryScreen extends StatefulWidget {
  final int? initialFilterIndex;

  const DiscoveryScreen({super.key, this.initialFilterIndex});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  List<Venue> _allVenues = [];
  bool _isLoading = true;
  User? _currentUser;
  Position? _currentPosition;
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _partyPlans = [];
  List<String> _availableCities = [];
  List<String> _availableAreas = [];
  String? _selectedArea;
  List<Map<String, dynamic>> _activeAds = [];
  int _currentAdIndex = 0;
  List<Map<String, dynamic>> _upcomingNights = [];

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadVenues();
    _determinePosition();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppTourService.showDiscoveryTour(context);
    });
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    try {
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  Future<void> _loadVenues() async {
    try {
      final results = await Future.wait([
        ApiService.fetchVenues(city: ApiService.selectedCity),
        ApiService.fetchProfile(),
        ApiService.fetchCustomers(),
        ApiService.fetchPartyPlans(status: 'active', page: 1, limit: 20),
        ApiService.fetchActiveAds(city: ApiService.selectedCity, type: 'Ads'),
        ApiService.fetchActiveAds(city: ApiService.selectedCity, type: 'Party'),
        ApiService.fetchStrangersMeetFeed(page: 1, limit: 20),
      ]);

      if (mounted) {
        setState(() {
          _allVenues = results[0] as List<Venue>;
          _currentUser = results[1] as User?;
          _allUsers = results[2] as List<Map<String, dynamic>>;
          _activeAds = results[4] as List<Map<String, dynamic>>;
          _currentAdIndex = 0;

          final dynamicPartyAds = results[5] as List<Map<String, dynamic>>;
          if (dynamicPartyAds.isNotEmpty) {
            _upcomingNights = dynamicPartyAds.map((ad) {
              final venue = ad['venue'] as Map<String, dynamic>? ?? {};
              final imageUrl = ad['imagePath'] != null
                  ? (ad['imagePath'].toString().startsWith('http')
                        ? ad['imagePath'].toString()
                        : '${ApiService.baseUrl}${ad['imagePath']}')
                  : '';

              String dateStr = ad['toDate'] ?? ad['fromDate'] ?? '';
              if (dateStr.isNotEmpty) {
                try {
                  final dt = DateTime.parse(dateStr);
                  dateStr = DateFormat('EEEE, MMM dd').format(dt);
                } catch (_) {}
              } else {
                dateStr = 'Upcoming';
              }

              return {
                'title': ad['title'] ?? ad['description'] ?? 'Special Event',
                'date': dateStr,
                'venue': venue['name'] ?? 'Unknown Venue',
                'image': imageUrl,
                'isAsset': false,
                'venueId': ad['venueId'],
                'venueMap': venue,
                'aboutEvent': ad['aboutEvent'],
              };
            }).toList();
          } else {
            _upcomingNights = [];
          }

          final rawPartyPlans = results[3] as List<Map<String, dynamic>>;
          final rawStrangersMeet = results[6] as List<Map<String, dynamic>>;

          List<Map<String, dynamic>> combinedPosts = [];

          if (rawPartyPlans.isNotEmpty) {
            combinedPosts.addAll(
              rawPartyPlans.map((plan) {
                final user = plan['user'] as Map<String, dynamic>? ?? {};
                final venue = plan['venue'] as Map<String, dynamic>? ?? {};

                String timeStr =
                    plan['planDateTime'] ?? plan['createdAt'] ?? '';
                if (timeStr.isNotEmpty) {
                  try {
                    final dt = DateTime.parse(timeStr);
                    timeStr = DateFormat('MMM dd, hh:mm a').format(dt);
                  } catch (_) {}
                }

                return {
                  'id': plan['id'],
                  'type': 'party_plan',
                  'firstName': user['firstName'] ?? 'User',
                  'lastName': user['lastName'] ?? '',
                  'profilePhotoUrl':
                      user['profilePhotoUrl'] ?? user['photoUrl'],
                  'profilePhoto': user['profilePhotoUrl'] ?? user['photoUrl'],
                  'city': venue['city'] ?? user['city'] ?? 'Unknown',
                  'bio': user['bio'] ?? '',
                  'gender': user['gender'] ?? 'Unknown',
                  'venue': venue['name'] ?? 'Unknown',
                  'content': plan['message'] ?? '',
                  'time': timeStr,
                  'coverImageUrl':
                      venue['coverImageUrl'] ?? venue['imageUrl'] ?? '',
                  'userId': user['id'],
                  'user': user,
                  'createdAt': plan['createdAt'],
                };
              }),
            );
          }

          if (rawStrangersMeet.isNotEmpty) {
            combinedPosts.addAll(
              rawStrangersMeet.map((meet) {
                final user = meet['user'] as Map<String, dynamic>? ?? {};
                final venue = meet['venue'] as Map<String, dynamic>? ?? {};

                String timeStr =
                    meet['eventDateTime'] ?? meet['createdAt'] ?? '';
                if (timeStr.isNotEmpty) {
                  try {
                    final dt = DateTime.parse(timeStr);
                    timeStr = DateFormat('MMM dd, hh:mm a').format(dt);
                  } catch (_) {}
                }

                return {
                  'id': meet['id'],
                  'type': 'strangers_meet',
                  'firstName': user['firstName'] ?? 'User',
                  'lastName': user['lastName'] ?? '',
                  'profilePhotoUrl':
                      user['photoUrl'] ?? user['profilePhotoUrl'],
                  'profilePhoto': user['photoUrl'] ?? user['profilePhotoUrl'],
                  'city': venue['city'] ?? user['city'] ?? 'Unknown',
                  'bio': user['bio'] ?? '',
                  'gender': user['gender'] ?? 'Unknown',
                  'venue': venue['name'] ?? 'Unknown',
                  'content': meet['tagline'] ?? meet['subject'] ?? '',
                  'time': timeStr,
                  'coverImageUrl':
                      venue['imageUrl'] ?? venue['coverImageUrl'] ?? '',
                  'userId': user['id'],
                  'user': user,
                  'createdAt': meet['createdAt'],
                };
              }),
            );
          }

          // Filter out user's own posts
          final myUserId = ApiService.currentUserId;
          if (myUserId != null) {
            combinedPosts.removeWhere((post) => post['userId'] == myUserId);
          }

          // Sort combined posts by time descending
          combinedPosts.sort((a, b) {
            final dateA =
                DateTime.tryParse(a['createdAt'] ?? '') ?? DateTime.now();
            final dateB =
                DateTime.tryParse(b['createdAt'] ?? '') ?? DateTime.now();
            return dateB.compareTo(dateA);
          });

          _partyPlans = combinedPosts;

          final fetchedCities = _allVenues.map((v) => v.city).toSet().toList();
          final fallbackCities = [
            'Pune',
            'Mumbai',
            'Delhi',
            'Bengaluru',
            'Goa',
          ];
          _availableCities = {...fetchedCities, ...fallbackCities}.toList();
          if (_availableCities.isNotEmpty) {
            _availableCities.sort();
            if (ApiService.selectedCity == null) {
              String defaultCity = _currentUser?.city ?? '';
              final match = _availableCities
                  .where((c) => c.toLowerCase() == defaultCity.toLowerCase())
                  .toList();
              ApiService.setSelectedCity(
                match.isNotEmpty ? match.first : _availableCities.first,
              );
            }
          } else if (ApiService.selectedCity == null) {
            ApiService.setSelectedCity(_currentUser?.city ?? 'Mumbai');
          }
          _availableAreas =
              _allVenues
                  .where(
                    (v) =>
                        ApiService.selectedCity == null ||
                        v.city.toLowerCase() ==
                            ApiService.selectedCity!.toLowerCase(),
                  )
                  .map((v) => (v.area ?? v.addressLine1).trim())
                  .where((a) => a.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
          _selectedArea = null;

          _isLoading = false;
        });
        //debugPrint('Loaded ${_allVenues.length} venues and ${_allUsers.length} users into state.');
      }
    } catch (e) {
      debugPrint('Error in _loadVenues: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Venue> get _filteredVenues {
    var liveVenues = _allVenues
        .where((v) => v.status?.toLowerCase() == 'live')
        .toList();

    // Filter by selected city
    if (ApiService.selectedCity != null) {
      liveVenues = liveVenues
          .where(
            (v) =>
                v.city.toLowerCase() == ApiService.selectedCity!.toLowerCase(),
          )
          .toList();
    }

    // Filter by selected area
    if (_selectedArea != null) {
      liveVenues = liveVenues
          .where(
            (v) =>
                (v.area ?? v.addressLine1).trim().toLowerCase() ==
                _selectedArea!.toLowerCase(),
          )
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      return liveVenues.where((v) {
        return v.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            v.city.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }
    return liveVenues;
  }

  List<Map<String, dynamic>> get _filteredPartyPlans {
    var plans = _partyPlans;
    // Hide the current user's own posts
    final myId = ApiService.currentUserId;
    if (myId != null) {
      plans = plans.where((p) {
        final planUserId =
            p['userId']?.toString() ??
            (p['user'] is Map ? p['user']['id']?.toString() : null) ??
            '';
        return planUserId != myId;
      }).toList();
    }
    if (ApiService.selectedCity != null) {
      plans = plans
          .where(
            (p) =>
                (p['city']?.toString() ?? '').toLowerCase() ==
                ApiService.selectedCity!.toLowerCase(),
          )
          .toList();
    }
    return plans;
  }

  List<Map<String, dynamic>> get _filteredUsers {
    var users = _allUsers;
    if (ApiService.selectedCity != null) {
      users = users.where((u) {
        final String? userCity =
            u['city'] ?? (u['profile'] is Map ? u['profile']['city'] : null);
        return (userCity?.toString() ?? '').toLowerCase() ==
            ApiService.selectedCity!.toLowerCase();
      }).toList();
    }
    return users;
  }

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    const double navbarHeight = 70.0;
    final double fixedTopPadding = statusBarHeight + navbarHeight;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Main Scrollable Content
          SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(top: fixedTopPadding + 10, bottom: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Ads Carousel
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildAdBanner(),
                ),
                const SizedBox(height: 24),

                // 2. Upcoming Nights
                if (_upcomingNights.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'UPCOMING NIGHTS',
                          style: TextStyle(
                            fontFamily: 'AllroundGothic',
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildUpcomingNights(),
                  const SizedBox(height: 24),
                ],

                // 3. Featured Venues
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'FEATURED VENUES',
                        style: TextStyle(
                          fontFamily: 'AllroundGothic',
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          fontSize: 15,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AllVenuesScreen(venues: _allVenues),
                          ),
                        ),
                        child: const Text(
                          'SEE ALL',
                          style: TextStyle(
                            fontFamily: 'AllroundGothic',
                            letterSpacing: 1,
                            fontWeight: FontWeight.bold,
                            color: LunaraTheme.electricViolet,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _buildSearchBox(),
                  ),
                ),
                const SizedBox(height: 16),
                // Area filter chips
                if (_availableAreas.isNotEmpty) ...[
                  _buildAreaFilter(),
                  const SizedBox(height: 12),
                ],
                _buildVenueList(),
                const SizedBox(height: 32),

                // 4. Recent Posts
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'RECENT POSTS',
                        style: TextStyle(
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          fontSize: 15,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          final displayFeeds = _filteredPartyPlans;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AllPostsScreen(
                                posts: displayFeeds,
                                venues: _allVenues,
                              ),
                            ),
                          );
                        },
                        child: const Text(
                          'SEE ALL',
                          style: TextStyle(
                            letterSpacing: 1,
                            fontWeight: FontWeight.bold,
                            color: LunaraTheme.electricViolet,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildRecentFeeds(),

                // 5. Top Profiles
                _buildTopProfiles(),
              ],
            ),
          ),

          // Fixed Header Layer
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Navbar
                  Container(
                    height: statusBarHeight + navbarHeight,
                    padding: EdgeInsets.fromLTRB(20, statusBarHeight, 20, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Image.asset(LunaraTheme.logoIcon, height: 28),
                        Expanded(
                          child: GestureDetector(
                            onTap: _showCitySelector,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.location_on_rounded,
                                  color: LunaraTheme.electricViolet,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    (ApiService.selectedCity ??
                                            _currentUser?.city ??
                                            'Locating...')
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      letterSpacing: 1,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: Colors.black54,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(right: 12),
                          child: VIPUpgradeButton(
                            key: AppTourService.vipUpgradeKey,
                            size: 36,
                          ),
                        ),
                        LunaraProfileImage(
                          user: _currentUser,
                          radius: 18,
                          showGradientBorder: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return TextField(
      key: AppTourService.searchBarKey,
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: InputDecoration(
        hintText: 'Search for clubs, lounges, events...',
        hintStyle: const TextStyle(
          color: Colors.black38,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: LunaraTheme.electricViolet,
        ),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.black54, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }

  Widget _buildAdBanner() {
    if (_activeAds.isEmpty) {
      return Container(
        margin: EdgeInsets.zero,
        height: 180,
        child: Stack(
          clipBehavior: Clip.antiAlias,
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LunaraTheme.purpleGradient,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: -20,
              right: -20,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
            Positioned(
              bottom: -30,
              left: 20,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 16.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Text(
                        'LIMITED OFFER',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'FIRST MONTH\nJOINING FREE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Join Lunara today and enjoy exclusive\ngroup booking perks with zero fees.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 180,
      margin: EdgeInsets.zero,
      child: Stack(
        children: [
          CarouselSlider.builder(
            itemCount: _activeAds.length,
            options: CarouselOptions(
              height: 180,
              viewportFraction: 1.0,
              enlargeCenterPage: false,
              autoPlay: _activeAds.length > 1,
              autoPlayInterval: const Duration(seconds: 4),
              autoPlayAnimationDuration: const Duration(milliseconds: 800),
              autoPlayCurve: Curves.fastOutSlowIn,
              onPageChanged: (index, reason) {
                if (mounted) {
                  setState(() {
                    _currentAdIndex = index;
                  });
                }
              },
            ),
            itemBuilder: (context, index, realIndex) {
              final ad = _activeAds[index];
              final imageUrl = ad['imagePath'] != null
                  ? (ad['imagePath'].toString().startsWith('http')
                        ? ad['imagePath'].toString()
                        : '${ApiService.baseUrl}${ad['imagePath']}')
                  : '';
              final venueName = ad['venue'] != null
                  ? ad['venue']['name']?.toString() ?? ''
                  : '';
              final venueArea = ad['venue'] != null
                  ? ad['venue']['area']?.toString() ??
                        ad['venue']['addressLine1']?.toString() ??
                        ''
                  : '';
              final venueCategory = ad['venue'] != null
                  ? ad['venue']['category']?.toString() ?? ''
                  : '';

              return GestureDetector(
                onTap: () {
                  Venue? matchingVenue;
                  try {
                    matchingVenue = _allVenues.firstWhere(
                      (v) => v.id == ad['venueId'],
                    );
                  } catch (_) {
                    matchingVenue = null;
                  }
                  if (matchingVenue != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            VenueDetailScreen(venue: matchingVenue!.toMap()),
                      ),
                    );
                  } else if (ad['venue'] != null) {
                    final Map<String, dynamic> minimalVenue = {
                      'id': ad['venueId'] ?? ad['venue']['id'] ?? '',
                      'name': ad['venue']['name'] ?? '',
                      'city':
                          ad['venue']['city'] ?? ApiService.selectedCity ?? '',
                      'area':
                          ad['venue']['area'] ??
                          ad['venue']['addressLine1'] ??
                          '',
                      'addressLine1': ad['venue']['addressLine1'] ?? '',
                      'category': ad['venue']['category'] ?? '',
                      'images': [imageUrl],
                      'tagline': ad['venue']['tagline'] ?? '',
                    };
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VenueDetailScreen(venue: minimalVenue),
                      ),
                    );
                  }
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LunaraTheme.purpleGradient,
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.white54,
                                    size: 40,
                                  ),
                                ),
                              ),
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: Colors.grey[900],
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        left: 20,
                        bottom: 20,
                        right: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (venueCategory.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: LunaraTheme.electricViolet.withValues(
                                    alpha: 0.85,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  venueCategory.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (venueName.isNotEmpty) ...[
                              Text(
                                venueName.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                            if (venueArea.isNotEmpty) ...[
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: Colors.white70,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    venueArea.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
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
                ),
              );
            },
          ),
          if (_activeAds.length > 1)
            Positioned(
              bottom: 20,
              right: 20,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: _activeAds.asMap().entries.map((entry) {
                  final isSelected = _currentAdIndex == entry.key;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: isSelected ? 16.0 : 6.0,
                    height: 6.0,
                    margin: const EdgeInsets.symmetric(horizontal: 3.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUpcomingNights() {
    return SizedBox(
      key: AppTourService.upcomingNightsKey,
      height: 250,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _upcomingNights.length,
        itemBuilder: (context, index) {
          final night = _upcomingNights[index];
          return RepaintBoundary(
            child: Container(
              width: 280,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: night['isAsset'] == true
                          ? Image.asset(night['image']!, fit: BoxFit.cover)
                          : Image.network(
                              night['image']!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: Colors.grey[900],
                                    child: const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.white54,
                                        size: 40,
                                      ),
                                    ),
                                  ),
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      color: Colors.grey[900],
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      ),
                                    );
                                  },
                            ),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.15),
                              Colors.black.withValues(alpha: 0.3),
                              Colors.black.withValues(alpha: 0.85),
                            ],
                            stops: const [0.2, 0.5, 1.0],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE100FF), Color(0xFF7F00FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFE100FF,
                              ).withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          night['date']!.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            night['title']!.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                color: LunaraTheme.cyberCyan,
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  night['venue']!.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
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
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            final venueId = night['venueId'];
                            final venueMap = night['venueMap'];

                            Venue? matchingVenue;
                            if (venueId != null) {
                              try {
                                matchingVenue = _allVenues.firstWhere(
                                  (v) => v.id == venueId,
                                );
                              } catch (_) {}
                            }

                            Map<String, dynamic>? passVenueMap;
                            if (matchingVenue != null) {
                              passVenueMap = matchingVenue.toMap();
                            } else if (venueMap is Map && venueMap.isNotEmpty) {
                              passVenueMap = Map<String, dynamic>.from(
                                venueMap,
                              );
                            }

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UpcomingPartyScreen(
                                  party: night,
                                  venueMap: passVenueMap,
                                ),
                              ),
                            );
                          },
                          splashColor: Colors.white.withValues(alpha: 0.1),
                          highlightColor: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVenueList() {
    if (_isLoading) return _buildVenueSkeleton();
    final venues = _filteredVenues;

    return SizedBox(
      height: 340,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        scrollDirection: Axis.horizontal,
        itemCount: venues.length,
        itemBuilder: (context, index) {
          final venue = venues[index];
          // RepaintBoundary isolates painting of each card
          String? distanceText;
          if (_currentPosition != null &&
              venue.latitude != null &&
              venue.longitude != null &&
              venue.latitude != 0.0 &&
              venue.longitude != 0.0) {
            double distanceInMeters = Geolocator.distanceBetween(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              venue.latitude!,
              venue.longitude!,
            );
            if (distanceInMeters < 1000) {
              distanceText = '${distanceInMeters.toStringAsFixed(0)} m';
            } else {
              distanceText =
                  '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
            }
          } else {
            // Fallback dummy distance for venues missing coordinates in the database or if location is unavailable
            double dummyDistance = 1.2 + (index * 0.7);
            distanceText = '${dummyDistance.toStringAsFixed(1)} km';
          }

          return RepaintBoundary(
            child: Container(
              width: 280,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                gradient: LunaraTheme.cardGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(
                  color: const Color(0xFF7F00FF).withValues(alpha: 0.08),
                  width: 1.2,
                ),
              ),
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VenueDetailScreen(venue: venue.toMap()),
                  ),
                ),
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Venue Image
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      child: Image.network(
                        venue.imageUrl ?? '',
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 180,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LunaraTheme.purpleGradient,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.business_rounded,
                              color: Colors.white54,
                              size: 48,
                            ),
                          ),
                        ),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 180,
                            color: Colors.grey[50],
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                      ),
                    ),
                    // Details
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  venue.name.toUpperCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    letterSpacing: 1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber[50],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      color: Colors.amber,
                                      size: 14,
                                    ),
                                    Text(
                                      ' ${venue.averageRating}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (venue.type ?? '').toUpperCase(),
                            style: TextStyle(
                              color: LunaraTheme.electricViolet,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                color: Colors.grey,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  venue.city,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(
                                Icons.directions_run_rounded,
                                color: Colors.grey,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                distanceText,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
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
          );
        },
      ),
    );
  }

  Widget _buildVenueSkeleton() {
    return SizedBox(
      height: 340,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        itemBuilder: (context, index) {
          return Container(
            width: 280,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF3EEFF),
                  Color(0xFFF8F4FF),
                  Color(0xFFEEE6FF),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Color(0x0A7F00FF),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
              border: Border.all(color: Color(0x1A7F00FF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 18,
                        width: 160,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        height: 12,
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        height: 14,
                        width: 120,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentFeeds() {
    final displayFeeds = _filteredPartyPlans;
    return SizedBox(
      height: 260,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: displayFeeds.length,
        itemBuilder: (context, index) {
          final feed = displayFeeds[index];

          // Handle nested user object or flat structure
          final userObj = feed['user'] is Map ? feed['user'] : feed;
          final String? profilePhoto =
              (userObj['profilePhotoUrl'] ??
                      userObj['profilePhoto'] ??
                      feed['image'])
                  ?.toString();
          String? imageUrl = profilePhoto;
          if (imageUrl != null && imageUrl.startsWith('/')) {
            imageUrl = '${ApiService.baseUrl}$imageUrl';
          }

          // Handle nested venue object or flat string
          String venueName = '';
          String? coverImageUrl;
          if (feed['venue'] is Map) {
            venueName = feed['venue']['name']?.toString() ?? '';
            coverImageUrl = feed['venue']['coverImageUrl']?.toString();
          } else {
            venueName = feed['venue']?.toString() ?? '';
            coverImageUrl = feed['coverImageUrl']?.toString();
            if (coverImageUrl != null && coverImageUrl.isEmpty) {
              coverImageUrl = null;
            }
          }

          if (coverImageUrl != null && coverImageUrl.startsWith('/')) {
            coverImageUrl = '${ApiService.baseUrl}$coverImageUrl';
          }

          return RepaintBoundary(
            child: Container(
              width: 240,
              height: 240,
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                gradient: coverImageUrl == null
                    ? LunaraTheme.cardGradient
                    : null,
                image: coverImageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(coverImageUrl),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                          Colors.black.withValues(alpha: 0.6),
                          BlendMode.darken,
                        ),
                      )
                    : null,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7F00FF).withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: const Color(0xFF7F00FF).withValues(alpha: 0.08),
                  width: 1.2,
                ),
              ),
              child: InkWell(
                onTap: () {
                  final venue = _allVenues.firstWhere(
                    (v) => v.name.toLowerCase() == venueName.toLowerCase(),
                    orElse: () => _allVenues.isNotEmpty
                        ? _allVenues.first
                        : Venue(
                            id: '0',
                            name: venueName,
                            city: 'Pune',
                            addressLine1: 'Pune',
                            averageRating: 0.0,
                          ),
                  );

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PostDetailScreen(post: feed, venue: venue.toMap()),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(
                                  0xFF7F00FF,
                                ).withValues(alpha: 0.15),
                                width: 1.5,
                              ),
                            ),
                            child: ClipOval(
                              child: (imageUrl != null && imageUrl.isNotEmpty)
                                  ? Image.network(
                                      imageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Image.asset(
                                                LunaraTheme.defaultAvatar,
                                                fit: BoxFit.cover,
                                              ),
                                    )
                                  : Image.asset(
                                      LunaraTheme.defaultAvatar,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  (userObj['firstName'] != null &&
                                          userObj['lastName'] != null)
                                      ? '${userObj['firstName']} ${userObj['lastName']}'
                                      : (userObj['userName'] ?? 'Lunara User'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: coverImageUrl != null
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  feed['time'] ?? '',
                                  style: TextStyle(
                                    color: coverImageUrl != null
                                        ? Colors.white70
                                        : Colors.grey,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Text(
                          feed['content'] ?? feed['message'] ?? '',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: coverImageUrl != null
                                ? Colors.white
                                : Colors.black87,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (feed['type'] == 'strangers_meet')
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'STRANGER MEET',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF7F00FF,
                                ).withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Color(0xFF7F00FF),
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      venueName.toUpperCase(),
                                      style: TextStyle(
                                        color: coverImageUrl != null
                                            ? Colors.white
                                            : const Color(0xFF7F00FF),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopProfiles() {
    // Robust null check and filter out the current user + apply gender filter
    final List<dynamic> users = _filteredUsers.where((u) {
      final isNotMe = u['id']?.toString() != _currentUser?.id;
      if (_currentUser?.gender == null) return isNotMe;

      final myGender = _currentUser!.gender!.toLowerCase();
      final uGender =
          (u['gender'] ??
                  (u['profile'] is Map ? u['profile']['gender'] : null) ??
                  '')
              .toString()
              .toLowerCase();

      if (myGender == 'male' || myGender == 'm') {
        if (uGender == 'male' || uGender == 'm') return false;
      } else if (myGender == 'female' || myGender == 'f') {
        if (uGender == 'female' || uGender == 'f') return false;
      }

      return isNotMe;
    }).toList();

    final displayUsers = users.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TOP PROFILES',
                style: TextStyle(
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  fontSize: 15,
                ),
              ),
              if (displayUsers.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AllUsersScreen(users: users),
                      ),
                    );
                  },
                  child: const Text(
                    'SEE ALL',
                    style: TextStyle(
                      letterSpacing: 1,
                      fontWeight: FontWeight.bold,
                      color: LunaraTheme.electricViolet,
                      fontSize: 15,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (displayUsers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Text(
              'No profiles available here at the moment.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          SizedBox(
            height: 104,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: displayUsers.length,
              itemBuilder: (context, index) {
                final user = displayUsers[index];
                final String name =
                    (user['firstName'] ??
                            user['fullName'] ??
                            user['name'] ??
                            'User')
                        .toString();
                final vibe = user['gender'] ?? user['vibe'] ?? 'Discovery';
                final matchPct = 65 + (index * 4) % 35;

                return GestureDetector(
                  onTap: () {
                    User? resolvedUser;
                    try {
                      resolvedUser = User.fromJson(
                        Map<String, dynamic>.from(user),
                      );
                    } catch (_) {}
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(user: resolvedUser),
                      ),
                    );
                  },
                  child: Container(
                    width: 280,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LunaraTheme.cardGradient,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF7F00FF).withValues(alpha: 0.08),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF7F00FF,
                          ).withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        LunaraProfileImage(
                          userData: user,
                          radius: 26,
                          showGradientBorder: false,
                          isInteractive: false,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '$name, ${22 + (index % 10)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.black,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.verified,
                                    color: LunaraTheme.cyberCyan,
                                    size: 14,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                vibe.toString(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: LunaraTheme.electricViolet,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${1 + index} km away',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: matchPct >= 80
                                    ? const Color(
                                        0xFF10B981,
                                      ).withValues(alpha: 0.12)
                                    : LunaraTheme.electricViolet.withValues(
                                        alpha: 0.1,
                                      ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$matchPct%',
                                style: TextStyle(
                                  color: matchPct >= 80
                                      ? const Color(0xFF10B981)
                                      : LunaraTheme.electricViolet,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () {
                                final id =
                                    user['id']?.toString() ??
                                    user['_id']?.toString() ??
                                    '';
                                if (id.isEmpty) return;
                                final String? profilePhoto =
                                    (user['profilePhotoUrl'] ??
                                            user['profilePhoto'] ??
                                            user['image'])
                                        ?.toString();
                                String avatarUrl = profilePhoto ?? '';
                                if (avatarUrl.startsWith('/')) {
                                  avatarUrl = '${ApiService.baseUrl}$avatarUrl';
                                }
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      user: {
                                        'id': id,
                                        'name': name,
                                        'image': avatarUrl,
                                        'isAsset': false,
                                        'online':
                                            user['isOnline'] == true ||
                                            user['online'] == true,
                                      },
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF7F00FF),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _showCitySelector() {
    if (_availableCities.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.5,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'SELECT CITY',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _availableCities.length,
                  itemBuilder: (context, index) {
                    final city = _availableCities[index];
                    final isSelected =
                        city.toLowerCase() ==
                        (ApiService.selectedCity ?? '').toLowerCase();

                    final navigator = Navigator.of(context);
                    return GestureDetector(
                      onTap: () {
                        ApiService.setSelectedCity(city).then((_) {
                          if (mounted) {
                            setState(() {
                              _isLoading = true;
                              _selectedArea = null;
                            });
                            _loadVenues();
                            navigator.pop();
                          }
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? LunaraTheme.electricViolet.withValues(
                                  alpha: 0.1,
                                )
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? LunaraTheme.electricViolet
                                : Colors.grey[200]!,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              city.toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isSelected
                                    ? LunaraTheme.electricViolet
                                    : Colors.black87,
                                letterSpacing: 1,
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: LunaraTheme.electricViolet,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAreaFilter() {
    if (_availableAreas.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _availableAreas.length + 1, // +1 for "All" chip
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final area = isAll ? null : _availableAreas[index - 1];
          final isSelected = isAll
              ? _selectedArea == null
              : _selectedArea == area;

          return GestureDetector(
            onTap: () => setState(() => _selectedArea = area),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [Color(0xFF3E0F6B), Color(0xFFB952EB)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : null,
                color: isSelected ? null : Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? Colors.transparent
                      : const Color(0x1A7F00FF),
                  width: 1.2,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: LunaraTheme.electricViolet.withValues(
                            alpha: 0.25,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [],
              ),
              child: Text(
                isAll ? 'All Areas' : (area ?? ''),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                  color: isSelected ? Colors.white : Colors.black54,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
