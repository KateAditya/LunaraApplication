import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../discovery/group_party_booking_screen.dart';
import '../discovery/all_users_screen.dart';

import '../../models/venue.dart';
import '../../services/api_service.dart';
import '../../models/user.dart';
import 'package:intl/intl.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../services/app_tour_service.dart';
import 'package:lunara_app/screens/social/live_feed_screen.dart';
import 'swipe_intro_screen.dart';
import '../../widgets/venue_timing_error_dialog.dart';
import '../discovery/upcoming_party_screen.dart';


class PlanHubScreen extends StatefulWidget {
  final bool autoShowCreatePlan;
  final bool autoShowStrangersMeet;

  const PlanHubScreen({
    super.key,
    this.autoShowCreatePlan = false,
    this.autoShowStrangersMeet = false,
  });

  @override
  State<PlanHubScreen> createState() => _PlanHubScreenState();
}

class _PlanHubScreenState extends State<PlanHubScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _bannerController;
  late Animation<double> _pulseAnim;
  late Animation<double> _rotateAnim;
  List<Venue> _allVenues = [];
  bool _isLoadingVenues = true;
  User? _currentUser;

  List<Map<String, dynamic>> _customerList = [];
  List<Map<String, dynamic>> _partyPlans = [];
  List<Map<String, dynamic>> _upcomingNights = [];
  bool _isLoadingCustomers = true;

  @override
  void initState() {
    super.initState();
    _bannerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _bannerController, curve: Curves.easeInOut),
    );
    _rotateAnim = Tween<double>(begin: -0.04, end: 0.04).animate(
      CurvedAnimation(parent: _bannerController, curve: Curves.easeInOut),
    );
    _loadVenues();
    _loadProfile();
    _loadCustomers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.autoShowCreatePlan) {
        _showCreatePlanSheet(context);
      } else if (widget.autoShowStrangersMeet) {
        _showArrangeStrangersMeetSheet(context);
      }
    });
  }

  bool _isVenueOpenOnDate(Venue venue, DateTime date) {
    final daysOpen = venue.daysOpen;
    if (daysOpen == null || daysOpen.isEmpty) {
      return true; // default to open
    }
    final weekdaysMap = {
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
      7: 'Sunday',
    };
    final weekdayName = weekdaysMap[date.weekday];
    if (weekdayName == null) return false;
    
    return daysOpen.any((d) {
      final str = d.toString().trim().toLowerCase();
      final fullDay = weekdayName.toLowerCase();
      final shortDay = weekdayName.substring(0, 3).toLowerCase();
      return str.contains(fullDay) || str.contains(shortDay);
    });
  }

  bool _isTimeWithinVenueHours(
    TimeOfDay time,
    String? openingStr,
    String? closingStr,
  ) {
    if (openingStr == null ||
        openingStr.isEmpty ||
        closingStr == null ||
        closingStr.isEmpty) {
      return true; // no timing constraint
    }

    final openParts = openingStr.split(':');
    if (openParts.length < 2) return true;
    final openHour = int.tryParse(openParts[0]) ?? 0;
    final openMin = int.tryParse(openParts[1]) ?? 0;

    final closeParts = closingStr.split(':');
    if (closeParts.length < 2) return true;
    final closeHour = int.tryParse(closeParts[0]) ?? 0;
    final closeMin = int.tryParse(closeParts[1]) ?? 0;

    final selectedMinutes = time.hour * 60 + time.minute;
    final openMinutes = openHour * 60 + openMin;
    final closeMinutes = closeHour * 60 + closeMin;

    if (closeMinutes < openMinutes) {
      // Overlap past midnight, e.g. 12:00 PM to 01:30 AM next day
      return selectedMinutes >= openMinutes || selectedMinutes <= closeMinutes;
    } else {
      // Normal hours, e.g. 10:00 AM to 11:00 PM
      return selectedMinutes >= openMinutes && selectedMinutes <= closeMinutes;
    }
  }

  String _formatTimeOfBooking(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        final ampm = hour >= 12 ? 'PM' : 'AM';
        final formattedHour = hour % 12 == 0 ? 12 : hour % 12;
        final formattedMinute = minute.toString().padLeft(2, '0');
        return '$formattedHour:$formattedMinute $ampm';
      }
    } catch (_) {}
    return timeStr;
  }

  Future<void> _loadCustomers() async {
    try {
      final results = await Future.wait([
        ApiService.fetchCustomers(),
        ApiService.fetchPartyPlans(),
        ApiService.fetchActiveAds(city: ApiService.selectedCity, type: 'Party'),
      ]);
      final customers = results[0] as List<Map<String, dynamic>>;
      final plans = results[1] as List<Map<String, dynamic>>;
      final dynamicPartyAds = results[2] as List<Map<String, dynamic>>;

      List<Map<String, dynamic>> upcoming = [];
      if (dynamicPartyAds.isNotEmpty) {
        upcoming = dynamicPartyAds.map((ad) {
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
      }

      if (mounted) {
        setState(() {
          _customerList = customers;
          _partyPlans = plans;
          _upcomingNights = upcoming;
          _isLoadingCustomers = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading customers and plans: $e');
      if (mounted) setState(() => _isLoadingCustomers = false);
    }
  }

  Future<void> _loadProfile() async {
    try {
      final user = await ApiService.fetchProfile();
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _loadVenues() async {
    try {
      final venues = await ApiService.fetchVenues();
      if (mounted) {
        setState(() {
          _allVenues = venues
              .where((v) => v.status?.toLowerCase() == 'live')
              .toList();
          _isLoadingVenues = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading venues: $e');
      if (mounted) setState(() => _isLoadingVenues = false);
    }
  }

  @override
  void dispose() {
    _bannerController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppTourService.showPlanHubTour(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildAnimatedBanner()),
            SliverToBoxAdapter(child: _buildActionButtons(context)),
            SliverToBoxAdapter(child: _buildFeaturedSection()),
            SliverToBoxAdapter(child: _buildTopTenProfilesSection()),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PLAN HUB',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Colors.black,
                ),
              ),
              Text(
                _currentUser != null
                    ? 'Welcome back, ${_currentUser!.firstName}!'
                    : 'Create plans & connect',
                style: TextStyle(fontSize: 12, color: Colors.grey[50]),
              ),
            ],
          ),
          const Spacer(),

          _currentUser != null
              ? LunaraProfileImage(
                  user: _currentUser,
                  radius: 20,
                  showGradientBorder: true,
                )
              : Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    color: LunaraTheme.electricViolet,
                    size: 20,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: AnimatedBuilder(
        animation: _bannerController,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnim.value,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LunaraTheme.purpleGradient,
                boxShadow: [
                  BoxShadow(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.antiAlias,
                children: [
                  // Decorative orbs
                  Positioned(
                    top: -30,
                    right: -20,
                    child: Transform.rotate(
                      angle: _rotateAnim.value,
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -20,
                    left: 10,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                  ),
                  // Stars / sparkles
                  Positioned(
                    top: 18,
                    right: 60,
                    child: Icon(
                      Icons.star_rounded,
                      color: Colors.white.withValues(alpha: 0.3),
                      size: 14,
                    ),
                  ),
                  Positioned(
                    top: 40,
                    right: 40,
                    child: Icon(
                      Icons.star_rounded,
                      color: Colors.white.withValues(alpha: 0.15),
                      size: 8,
                    ),
                  ),
                  // Content
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: const Text(
                                  '✦ LUNARA PLANS',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'PLAN YOUR\nPERFECT NIGHT',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Invite friends, book venues\n& create unforgettable memories.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Animated logo icon
                        if (MediaQuery.of(context).size.width > 350)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Transform.rotate(
                              angle: _rotateAnim.value * 2,
                            child: Image.asset(
                              'assets/images/logo_icon.png',
                              width: 48,
                              height: 48,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WHAT\'S YOUR PLAN?',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  key: AppTourService.createPlanKey,
                  child: _actionCard(
                    icon: Icons.add_circle_outline_rounded,
                    label: 'Create\nPlan',
                    gradient: LunaraTheme.purpleGradient,
                    onTap: () => _showCreatePlanSheet(context),
                  ),
                ),
              ),

              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  key: AppTourService.groupPartyKey,
                  child: _actionCard(
                    icon: Icons.groups_rounded,
                    label: 'Group\nParty',
                    gradient: LunaraTheme.purpleGradient,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GroupPartyBookingScreen(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  key: AppTourService.strangersMeetKey,
                  child: _actionCard(
                    icon: Icons.handshake_rounded,
                    label: 'Arrange Strangers\nMeet',
                    gradient: LunaraTheme.purpleGradient,
                    onTap: () => _showArrangeStrangersMeetSheet(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildUpcomingNightsSection(),
        ],
      ),
    );
  }

  Widget _buildUpcomingNightsSection() {
    if (_upcomingNights.isEmpty) {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const LiveFeedScreen(),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF3E0F6B), Color(0xFF5E17A2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.celebration_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SUITABLE PLANS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Explore active party plans and join the fun around you!',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white70,
                size: 14,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'UPCOMING NIGHTS',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _upcomingNights.length,
            itemBuilder: (context, index) {
              final night = _upcomingNights[index];
              return Container(
                width: 280,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
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
                                Colors.black.withValues(alpha: 0.1),
                                Colors.black.withValues(alpha: 0.3),
                                Colors.black.withValues(alpha: 0.8),
                              ],
                              stops: const [0.2, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE100FF), Color(0xFF7F00FF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(10),
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
                        bottom: 12,
                        left: 12,
                        right: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              night['title']!.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_rounded,
                                  color: LunaraTheme.cyberCyan,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    night['venue']!.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
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
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String label,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturedSection() {
    List<Map<String, dynamic>> filteredList = _customerList;
    if (_currentUser?.gender != null) {
      final myGender = _currentUser!.gender!.toLowerCase();
      filteredList = _customerList.where((u) {
        final isNotMe = u['id']?.toString() != _currentUser?.id;
        final uGender =
            (u['gender'] ??
                    (u['profile'] is Map ? u['profile']['gender'] : null) ??
                    u['vibe'] ??
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
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'FEATURED TONIGHT',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: Colors.black,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AllUsersScreen(users: _customerList),
                    ),
                  );
                },
                child: const Text(
                  'SEE ALL',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: LunaraTheme.electricViolet,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 108,
          child: _isLoadingCustomers
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _currentUser != null
                      ? (filteredList.length + 1)
                      : filteredList.length,
                  itemBuilder: (context, index) {
                    final Map<String, dynamic> person;
                    final bool isMe;

                    if (_currentUser != null && index == 0) {
                      isMe = true;
                      person = {
                        'name': _currentUser!.firstName,
                        'profilePhotoUrl': _currentUser!.profilePhoto,
                        'gender': _currentUser!.gender ?? 'You',
                      };
                    } else {
                      isMe = false;
                      final adjustedIndex = _currentUser != null
                          ? index - 1
                          : index;
                      person = filteredList[adjustedIndex];
                    }

                    // Extract fields safely
                    final name =
                        person['name'] ??
                        person['firstName'] ??
                        person['first_name'] ??
                        'User';

                    final vibe = person['gender'] ?? person['vibe'] ?? 'Party';

                    return Container(
                      width: 80,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        children: [
                          LunaraProfileImage(
                            userData: person,
                            user: isMe ? _currentUser : null,
                            radius: 30,
                            showGradientBorder: true,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isMe ? 'Me' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            vibe,
                            style: TextStyle(
                              fontSize: 9,
                              color: isMe
                                  ? const Color(0xFFB952EB)
                                  : LunaraTheme.electricViolet.withValues(
                                      alpha: 0.8,
                                    ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTopTenProfilesSection() {
    List<Map<String, dynamic>> filteredList = _customerList;
    if (_currentUser?.gender != null) {
      final myGender = _currentUser!.gender!.toLowerCase();
      filteredList = _customerList.where((u) {
        final isNotMe = u['id']?.toString() != _currentUser?.id;
        final uGender =
            (u['gender'] ??
                    (u['profile'] is Map ? u['profile']['gender'] : null) ??
                    u['vibe'] ??
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
    }

    // Rank dynamically by active hosted plans (primary weight) and budget preferences/super likes
    final scoredList = filteredList.map((u) {
      final userId = u['id']?.toString() ?? '';

      // Count of active plans they created
      final planCount = _partyPlans.where((p) {
        final creatorId = (p['userId'] ?? p['user']?['id'])?.toString();
        return creatorId == userId;
      }).length;

      // Deterministic super likes count
      final superLikes = (userId.hashCode.abs() % 41) + 10;

      // Higher budget adds to their plan score
      final preferences = u['preferences'] ?? {};
      final budgetRange = (preferences['budgetRange'] ?? '')
          .toString()
          .toLowerCase();
      int budgetScore = 0;
      if (budgetRange.contains('5000') || budgetRange.contains('5k')) {
        budgetScore = 40;
      } else if (budgetRange.contains('2000') || budgetRange.contains('2k')) {
        budgetScore = 30;
      } else if (budgetRange.contains('1000') || budgetRange.contains('1k')) {
        budgetScore = 20;
      } else if (budgetRange.contains('500')) {
        budgetScore = 10;
      }

      // Total rank score
      final score = (planCount * 1000) + (budgetScore * 10) + superLikes;

      return {
        'user': u,
        'planCount': planCount,
        'superLikes': superLikes,
        'score': score,
      };
    }).toList();

    // Sort in descending order of score
    scoredList.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Text(
            'TOP 10 PROFILES',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              color: Colors.black,
            ),
          ),
        ),
        _isLoadingCustomers
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: scoredList.length > 10 ? 10 : scoredList.length,
                itemBuilder: (context, index) {
                  final item = scoredList[index];
                  final person = item['user'] as Map<String, dynamic>;
                  final planCount = item['planCount'] as int;
                  final superLikes = item['superLikes'] as int;

                  final name =
                      person['name'] ??
                      person['firstName'] ??
                      person['first_name'] ??
                      'User';
                  final age = person['age'] ?? (22 + (index % 10));
                  final vibe =
                      person['gender'] ?? person['vibe'] ?? 'Discovery';
                  final matchPct = ApiService.calculateMatchPercentage(person);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0x1A7F00FF),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x0D7F00FF),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        LunaraProfileImage(
                          userData: person,
                          radius: 26,
                          showGradientBorder: false,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '$name, $age',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.black,
                                    ),
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
                                vibe,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: LunaraTheme.electricViolet,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.event_note,
                                    color: Colors.amber[700],
                                    size: 12,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$planCount Plans',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Icon(
                                    Icons.star,
                                    color: Colors.amber[600],
                                    size: 12,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$superLikes Super Likes',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
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
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ],
    );
  }

  // Bottom Sheets

  void _showCreatePlanSheet(BuildContext context) {
    final descriptionCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final taglineCtrl = TextEditingController();
    final chargesCtrl = TextEditingController(text: '0'); // default to 0
    final mobileCtrl = TextEditingController();
    final altMobileCtrl = TextEditingController();
    Venue? selectedVenue;
    String searchQuery = '';
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    bool isPosting = false;
    String? sheetErrorMsg;
    String selectedPrivacy = 'Public';
    String userSearchQuery = '';
    final List<String> selectedUserIds = [];
    String selectedFoodPref = 'Both';
    String selectedDrinkPref = 'Both';
    String selectedPaymentType = 'split';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          AppTourService.showCreatePlanTour(context);
        });
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final tomorrow = today.add(const Duration(days: 1));

            bool isDateOpen(DateTime date) {
              if (selectedVenue == null) return true;
              
              // Check closed dates
              final closedDates = selectedVenue!.closedDates;
              if (closedDates != null) {
                final yyyy = date.year;
                final mm = date.month.toString().padLeft(2, '0');
                final dd = date.day.toString().padLeft(2, '0');
                final dateStr = '$yyyy-$mm-$dd';
                if (closedDates.contains(dateStr)) {
                  return false;
                }
              }

              // Check weekdays
              final weekdaysMap = {
                1: 'Monday',
                2: 'Tuesday',
                3: 'Wednesday',
                4: 'Thursday',
                5: 'Friday',
                6: 'Saturday',
                7: 'Sunday',
              };
              final weekdayName = weekdaysMap[date.weekday];
              if (selectedVenue!.daysOpen != null && selectedVenue!.daysOpen!.isNotEmpty) {
                final isOpenOnWeekday = weekdayName != null && selectedVenue!.daysOpen!.any((d) {
                  final str = d.toString().trim().toLowerCase();
                  final fullDay = weekdayName.toLowerCase();
                  final shortDay = weekdayName.substring(0, 3).toLowerCase();
                  return str.contains(fullDay) || str.contains(shortDay);
                });
                if (!isOpenOnWeekday) {
                  return false;
                }
              }
              return true;
            }

            bool isTimeSlotValid(TimeOfDay time, [DateTime? specificDate]) {
              final activeDate = specificDate ?? selectedDate;
              if (activeDate == null) return true;
              if (selectedVenue == null) return true;

              final invalidReason = selectedVenue!.getInvalidReason(activeDate, time);
              if (invalidReason != null) {
                return false;
              }

              final selectedDateTime = DateTime(
                activeDate.year,
                activeDate.month,
                activeDate.day,
                time.hour,
                time.minute,
              );
              final minAllowedDateTime = DateTime.now().add(const Duration(hours: 1));
              if (selectedDateTime.isBefore(minAllowedDateTime)) {
                return false;
              }
              return true;
            }
            final List<DateTime> dynamicDates = [];
            DateTime checkDate = today;
            while (dynamicDates.length < 6) {
              if (isDateOpen(checkDate)) {
                dynamicDates.add(checkDate);
              }
              checkDate = checkDate.add(const Duration(days: 1));
            }

            Future<void> handleDateSelection(DateTime date) async {
              if (selectedVenue == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please select a venue first.'),
                    backgroundColor: Colors.orangeAccent,
                  ),
                );
                return;
              }

              final yyyy = date.year;
              final mm = date.month.toString().padLeft(2, '0');
              final dd = date.day.toString().padLeft(2, '0');
              final dateStr = '$yyyy-$mm-$dd';
              if (selectedVenue!.closedDates != null && selectedVenue!.closedDates!.contains(dateStr)) {
                VenueTimingErrorDialog.show(
                  context,
                  venueName: selectedVenue!.name,
                  daysOpen: selectedVenue!.daysOpen,
                  openingTime: selectedVenue!.openingTime,
                  closingTime: selectedVenue!.closingTime,
                  closedDates: selectedVenue!.closedDates,
                );
                return;
              }

              final weekdaysMap = {
                1: 'Monday',
                2: 'Tuesday',
                3: 'Wednesday',
                4: 'Thursday',
                5: 'Friday',
                6: 'Saturday',
                7: 'Sunday',
              };
              final weekdayName = weekdaysMap[date.weekday];
              final isOpenOnWeekday = weekdayName != null && selectedVenue!.daysOpen != null && selectedVenue!.daysOpen!.any((d) {
                final str = d.toString().trim().toLowerCase();
                final fullDay = weekdayName.toLowerCase();
                final shortDay = weekdayName.substring(0, 3).toLowerCase();
                return str.contains(fullDay) || str.contains(shortDay);
              });
              if (!isOpenOnWeekday && selectedVenue!.daysOpen != null && selectedVenue!.daysOpen!.isNotEmpty) {
                VenueTimingErrorDialog.show(
                  context,
                  venueName: selectedVenue!.name,
                  daysOpen: selectedVenue!.daysOpen,
                  openingTime: selectedVenue!.openingTime,
                  closingTime: selectedVenue!.closingTime,
                  closedDates: selectedVenue!.closedDates,
                );
                return;
              }

              final time = await showTimePicker(
                context: context,
                initialTime: selectedTime ?? TimeOfDay.now(),
              );

              if (time != null) {
                final selectedDateTime = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
                if (selectedDateTime.isBefore(DateTime.now())) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Selected date and time cannot be in the past.'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }

                final invalidReason = selectedVenue!.getInvalidReason(date, time);
                if (invalidReason != null) {
                  VenueTimingErrorDialog.show(
                    context,
                    venueName: selectedVenue!.name,
                    daysOpen: selectedVenue!.daysOpen,
                    openingTime: selectedVenue!.openingTime,
                    closingTime: selectedVenue!.closingTime,
                    closedDates: selectedVenue!.closedDates,
                  );
                  return;
                }

                setSheetState(() {
                  selectedDate = date;
                  selectedTime = time;
                  final formattedTime = _formatTimeOfBooking(
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  );
                  dateCtrl.text =
                      "${DateFormat('MMM dd, yyyy').format(date)} at $formattedTime";
                });
              }
            }

            Future<void> handleCustomDateSelection() async {
              if (selectedVenue == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please select a venue first.'),
                    backgroundColor: Colors.orangeAccent,
                  ),
                );
                return;
              }

              final date = await showDatePicker(
                context: context,
                initialDate: selectedDate ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 30)),
              );

              if (date != null) {
                await handleDateSelection(date);
              }
            }

            Widget buildDateChip(String label, DateTime dateVal, bool isSelected) {
              return GestureDetector(
                onTap: () {
                  if (selectedVenue == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select a venue first.'),
                        backgroundColor: Colors.orangeAccent,
                      ),
                    );
                    return;
                  }
                  setSheetState(() {
                    selectedDate = dateVal;
                    if (selectedTime != null && !isTimeSlotValid(selectedTime!, dateVal)) {
                      selectedTime = null;
                    }
                    if (selectedDate != null && selectedTime != null) {
                      final formattedTime = _formatTimeOfBooking(
                        '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}',
                      );
                      dateCtrl.text =
                          "${DateFormat('MMM dd, yyyy').format(selectedDate!)} at $formattedTime";
                    } else if (selectedDate != null) {
                      dateCtrl.text =
                          "${DateFormat('MMM dd, yyyy').format(selectedDate!)}";
                    } else {
                      dateCtrl.text = '';
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? LunaraTheme.electricViolet : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? LunaraTheme.electricViolet : Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('MMM d').format(dateVal),
                        style: TextStyle(
                          color: isSelected ? Colors.white70 : Colors.black54,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget buildCustomChip(bool isSelected) {
              return GestureDetector(
                onTap: handleCustomDateSelection,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? LunaraTheme.electricViolet : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? LunaraTheme.electricViolet : Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 12,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Custom',
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selectedDate != null &&
                                !dynamicDates.any((d) =>
                                    d.year == selectedDate!.year &&
                                    d.month == selectedDate!.month &&
                                    d.day == selectedDate!.day)
                            ? DateFormat('MMM d').format(selectedDate!)
                            : 'Choose Date',
                        style: TextStyle(
                          color: isSelected ? Colors.white70 : Colors.black54,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final List<Venue> displayedVenues = searchQuery.isEmpty
                ? _allVenues.take(5).toList()
                : _allVenues
                      .where(
                        (v) =>
                            v.name.toLowerCase().contains(
                              searchQuery.toLowerCase(),
                            ) ||
                            v.city.toLowerCase().contains(
                              searchQuery.toLowerCase(),
                            ),
                      )
                      .toList();

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.90,
              ),
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  24,
                  16,
                  24,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'CREATE A PARTY PLAN',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Venue Search
                      Container(
                        key: AppTourService.createPlanVenueSearchKey,
                        child: _sheetField(
                          hint: 'Search venue...',
                          icon: Icons.search_rounded,
                          onChanged: (val) =>
                              setSheetState(() => searchQuery = val),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Horizontal Venue List
                      if (_isLoadingVenues)
                        const Center(child: CircularProgressIndicator())
                      else if (displayedVenues.isEmpty)
                        const Text(
                          'No venues found',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        )
                      else
                        SizedBox(
                          height: 100,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: displayedVenues.length,
                            itemBuilder: (context, index) {
                              final v = displayedVenues[index];
                              final isSelected = selectedVenue?.id == v.id;
                              return GestureDetector(
                                onTap: () {
                                  setSheetState(() {
                                    selectedVenue = v;
                                    descriptionCtrl.text =
                                        "Let's party at ${v.name}! 🚀";
                                    // Validate previously selected date & time
                                    if (selectedDate != null && selectedTime != null) {
                                      final invalidReason = v.getInvalidReason(selectedDate!, selectedTime!);
                                      if (invalidReason != null) {
                                        selectedDate = null;
                                        selectedTime = null;
                                        dateCtrl.clear();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Cleared date/time selection: $invalidReason'),
                                            backgroundColor: Colors.orangeAccent,
                                          ),
                                        );
                                      }
                                    } else if (selectedDate != null) {
                                      final yyyy = selectedDate!.year;
                                      final mm = selectedDate!.month.toString().padLeft(2, '0');
                                      final dd = selectedDate!.day.toString().padLeft(2, '0');
                                      final dateStr = '$yyyy-$mm-$dd';
                                      final weekdaysMap = {
                                        1: 'Monday',
                                        2: 'Tuesday',
                                        3: 'Wednesday',
                                        4: 'Thursday',
                                        5: 'Friday',
                                        6: 'Saturday',
                                        7: 'Sunday',
                                      };
                                      final weekdayName = weekdaysMap[selectedDate!.weekday];
                                      final isOpenOnWeekday = weekdayName != null && v.daysOpen != null && v.daysOpen!.any((d) {
                                        final str = d.toString().trim().toLowerCase();
                                        final fullDay = weekdayName.toLowerCase();
                                        final shortDay = weekdayName.substring(0, 3).toLowerCase();
                                        return str.contains(fullDay) || str.contains(shortDay);
                                      });
                                      final isHoliday = v.closedDates != null && v.closedDates!.contains(dateStr);
                                      if (isHoliday || (!isOpenOnWeekday && v.daysOpen != null && v.daysOpen!.isNotEmpty)) {
                                        selectedDate = null;
                                        dateCtrl.clear();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Cleared date selection because ${v.name} is closed on that day.'),
                                            backgroundColor: Colors.orangeAccent,
                                          ),
                                        );
                                      }
                                    }
                                  });
                                },
                                child: Container(
                                  width: 140,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? LunaraTheme.electricViolet
                                          : Colors.grey[200]!,
                                      width: 2,
                                    ),
                                    image: v.imageUrl != null
                                        ? DecorationImage(
                                            image: NetworkImage(v.imageUrl!),
                                            fit: BoxFit.cover,
                                            colorFilter: ColorFilter.mode(
                                              Colors.black.withValues(
                                                alpha: isSelected ? 0.2 : 0.4,
                                              ),
                                              BlendMode.darken,
                                            ),
                                          )
                                        : null,
                                    color: Colors.grey[100],
                                  ),
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        v.name.toUpperCase(),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                      const SizedBox(height: 12),

                      // Auto-filled Description
                      _sheetField(
                        controller: descriptionCtrl,
                        hint: 'Plan details...',
                        icon: Icons.info_outline_rounded,
                      ),
                      const SizedBox(height: 10),

                      // Date & Time Picker Options
                      const Text(
                        'SELECT DATE & TIME',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            ...dynamicDates.map((dateVal) {
                              String label = '';
                              if (dateVal.year == today.year &&
                                  dateVal.month == today.month &&
                                  dateVal.day == today.day) {
                                label = 'Today';
                              } else if (dateVal.year == tomorrow.year &&
                                  dateVal.month == tomorrow.month &&
                                  dateVal.day == tomorrow.day) {
                                label = 'Tomorrow';
                              } else {
                                label = DateFormat('E').format(dateVal);
                              }

                              final isSelected = selectedDate != null &&
                                  selectedDate!.year == dateVal.year &&
                                  selectedDate!.month == dateVal.month &&
                                  selectedDate!.day == dateVal.day;

                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: buildDateChip(label, dateVal, isSelected),
                              );
                            }),
                            buildCustomChip(
                              selectedDate != null &&
                              !dynamicDates.any((d) =>
                                  d.year == selectedDate!.year &&
                                  d.month == selectedDate!.month &&
                                  d.day == selectedDate!.day)
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'SELECT TIME SLOT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final predefinedTimes = [
                            const TimeOfDay(hour: 19, minute: 0), // 7 PM
                            const TimeOfDay(hour: 20, minute: 0), // 8 PM
                            const TimeOfDay(hour: 21, minute: 0), // 9 PM
                            const TimeOfDay(hour: 22, minute: 0), // 10 PM
                            const TimeOfDay(hour: 23, minute: 0), // 11 PM
                            const TimeOfDay(hour: 0, minute: 0),  // 12 AM
                          ];

                          final validTimes = predefinedTimes.where((t) => isTimeSlotValid(t)).toList();

                          String formatTimeOfDay(TimeOfDay tod) {
                            final hour = tod.hour == 0 ? 12 : (tod.hour > 12 ? tod.hour - 12 : tod.hour);
                            final ampm = tod.hour >= 12 ? 'PM' : 'AM';
                            return '$hour:00 $ampm';
                          }

                          Widget buildTimeChip(String label, TimeOfDay tod, bool isSelected) {
                            return GestureDetector(
                              onTap: () {
                                setSheetState(() {
                                  selectedTime = tod;
                                  if (selectedDate != null) {
                                    final formattedTime = _formatTimeOfBooking(
                                      '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}',
                                    );
                                    dateCtrl.text =
                                        "${DateFormat('MMM dd, yyyy').format(selectedDate!)} at $formattedTime";
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected ? LunaraTheme.electricViolet : Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? LunaraTheme.electricViolet : Colors.grey[300]!,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            );
                          }

                          // Determine if selected time is a custom time (not in validTimes)
                          bool isCustomSelected = false;
                          if (selectedTime != null) {
                            isCustomSelected = !validTimes.any((t) => t.hour == selectedTime!.hour && t.minute == selectedTime!.minute);
                          }

                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                ...validTimes.map((tod) {
                                  final label = formatTimeOfDay(tod);
                                  final isSelected = selectedTime != null &&
                                      selectedTime!.hour == tod.hour &&
                                      selectedTime!.minute == tod.minute;

                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: buildTimeChip(label, tod, isSelected),
                                  );
                                }),
                                GestureDetector(
                                  onTap: () async {
                                    final TimeOfDay? picked = await showTimePicker(
                                      context: context,
                                      initialTime: selectedTime ?? const TimeOfDay(hour: 22, minute: 0),
                                    );
                                    if (picked != null) {
                                      if (!isTimeSlotValid(picked)) {
                                        VenueTimingErrorDialog.show(
                                          context,
                                          venueName: selectedVenue!.name,
                                          daysOpen: selectedVenue!.daysOpen,
                                          openingTime: selectedVenue!.openingTime,
                                          closingTime: selectedVenue!.closingTime,
                                          closedDates: selectedVenue!.closedDates,
                                        );
                                        return;
                                      }
                                      setSheetState(() {
                                        selectedTime = picked;
                                        if (selectedDate != null) {
                                          final formattedTime = _formatTimeOfBooking(
                                            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
                                          );
                                          dateCtrl.text =
                                              "${DateFormat('MMM dd, yyyy').format(selectedDate!)} at $formattedTime";
                                        }
                                      });
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isCustomSelected ? LunaraTheme.electricViolet : Colors.grey[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isCustomSelected ? LunaraTheme.electricViolet : Colors.grey[300]!,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 12,
                                          color: isCustomSelected ? Colors.white : Colors.black87,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isCustomSelected
                                              ? _formatTimeOfBooking(
                                                  '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}')
                                              : 'Custom',
                                          style: TextStyle(
                                            color: isCustomSelected ? Colors.white : Colors.black87,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      _sheetField(
                        controller: dateCtrl,
                        hint: 'Selected Date & Time',
                        icon: Icons.calendar_today_rounded,
                        readOnly: true,
                        onTap: () {
                          if (selectedDate != null) {
                            handleDateSelection(selectedDate!);
                          } else {
                            handleCustomDateSelection();
                          }
                        },
                      ),

                      const SizedBox(height: 10),
                      const Text(
                        'SELECT PRIVACY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: ['Public', 'Private', 'Both'].map((type) {
                          final isSelected = selectedPrivacy == type;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setSheetState(() {
                                  selectedPrivacy = type;
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  gradient: isSelected
                                      ? LunaraTheme.purpleGradient
                                      : null,
                                  color: isSelected ? null : Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.transparent
                                        : Colors.grey[200]!,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    type.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black54,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'PAYMENT MODEL',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            selectedPaymentType == 'self_pay'
                                ? 'Host pays 2x Deposit: ₹198 (Refundable)'
                                : 'Split Deposit: ₹99 per head (Refundable)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: selectedPaymentType == 'self_pay'
                                  ? Colors.green[700]
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: ['Split', 'Self Pay'].map((mode) {
                          final isSelected = (mode == 'Split' && selectedPaymentType == 'split') ||
                                             (mode == 'Self Pay' && selectedPaymentType == 'self_pay');
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: GestureDetector(
                                onTap: () {
                                  setSheetState(() {
                                    selectedPaymentType = mode == 'Split' ? 'split' : 'self_pay';
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    gradient: isSelected ? LunaraTheme.purpleGradient : null,
                                    color: isSelected ? null : Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? Colors.transparent : Colors.grey[200]!,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      mode.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? Colors.white : Colors.black54,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 14),
                      const Text(
                        'FOOD & DRINK PREFERENCES',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Food Preference',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey[200]!),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButtonFormField<String>(
                                      value: selectedFoodPref,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        prefixIcon: Icon(Icons.restaurant, color: LunaraTheme.electricViolet, size: 14),
                                        prefixIconConstraints: BoxConstraints(minWidth: 22, minHeight: 14),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                                      ),
                                      items: const ['Veg', 'Non-Veg', 'Both'].map((String val) {
                                        return DropdownMenuItem<String>(
                                          value: val,
                                          child: Text(val, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setSheetState(() {
                                            selectedFoodPref = val;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Drink Preference',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey[200]!),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButtonFormField<String>(
                                      value: selectedDrinkPref,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        prefixIcon: Icon(Icons.local_bar, color: LunaraTheme.electricViolet, size: 14),
                                        prefixIconConstraints: BoxConstraints(minWidth: 22, minHeight: 14),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                                      ),
                                      items: const ['Alcoholic', 'Non-Alcoholic', 'Both'].map((String val) {
                                        return DropdownMenuItem<String>(
                                          value: val,
                                          child: Text(val, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setSheetState(() {
                                            selectedDrinkPref = val;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      if (selectedPrivacy == 'Private' || selectedPrivacy == 'Both') ...[
                        const SizedBox(height: 10),
                        _sheetField(
                          hint: 'Search profiles to invite...',
                          icon: Icons.person_search_rounded,
                          onChanged: (val) {
                            setSheetState(() {
                              userSearchQuery = val;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 90,
                          child: _customerList.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No profiles available',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _customerList.where((u) {
                                    final name =
                                        (u['name'] ??
                                                u['firstName'] ??
                                                u['first_name'] ??
                                                '')
                                            .toString()
                                            .toLowerCase();
                                    final searchVal = userSearchQuery
                                        .toLowerCase();
                                    final isNotMe =
                                        u['id']?.toString() !=
                                        ApiService.currentUserId;
                                    return name.contains(searchVal) && isNotMe;
                                  }).length,
                                  itemBuilder: (ctx, idx) {
                                    final filteredList = _customerList.where((
                                      u,
                                    ) {
                                      final name =
                                          (u['name'] ??
                                                  u['firstName'] ??
                                                  u['first_name'] ??
                                                  '')
                                              .toString()
                                              .toLowerCase();
                                      final searchVal = userSearchQuery
                                          .toLowerCase();
                                      final isNotMe =
                                          u['id']?.toString() !=
                                          ApiService.currentUserId;
                                      return name.contains(searchVal) &&
                                          isNotMe;
                                    }).toList();
                                    final p = filteredList[idx];
                                    final pId = p['id']?.toString() ?? '';
                                    final pName =
                                        p['name'] ??
                                        p['firstName'] ??
                                        p['first_name'] ??
                                        'User';
                                    final isSelected = selectedUserIds.contains(
                                      pId,
                                    );

                                    return GestureDetector(
                                      onTap: () {
                                        setSheetState(() {
                                          if (isSelected) {
                                            selectedUserIds.remove(pId);
                                          } else {
                                            if (selectedUserIds.length >= 50) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Maximum 50 invites allowed.',
                                                  ),
                                                  backgroundColor:
                                                      Colors.redAccent,
                                                ),
                                              );
                                              return;
                                            }
                                            selectedUserIds.add(pId);
                                          }
                                        });
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 14,
                                        ),
                                        child: Column(
                                          children: [
                                            Stack(
                                              children: [
                                                LunaraProfileImage(
                                                  userData: p,
                                                  radius: 24,
                                                  showGradientBorder:
                                                      isSelected,
                                                  isInteractive: false,
                                                ),
                                                if (isSelected)
                                                  Positioned(
                                                    right: 0,
                                                    bottom: 0,
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            2,
                                                          ),
                                                      decoration:
                                                          const BoxDecoration(
                                                            color: Colors.green,
                                                            shape:
                                                                BoxShape.circle,
                                                          ),
                                                      child: const Icon(
                                                        Icons.check,
                                                        color: Colors.white,
                                                        size: 10,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              pName,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: isSelected
                                                    ? LunaraTheme.electricViolet
                                                    : Colors.black87,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],

                      if (selectedUserIds.length > 20) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: Colors.orange.shade800,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'You have selected ${selectedUserIds.length} friends. Since it exceeds 20, this event will be created as a Strangers Meet request.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Event Subject
                        _sheetField(
                          controller: subjectCtrl,
                          hint: 'Enter Event Subject...',
                          icon: Icons.title_rounded,
                        ),
                        const SizedBox(height: 14),
                        // Tag line / other details
                        _sheetField(
                          controller: taglineCtrl,
                          hint: 'Requirement Details...',
                          icon: Icons.subtitles_rounded,
                          maxLines: 3,
                        ),
                        const SizedBox(height: 14),
                        // Mobile Number
                        _sheetField(
                          controller: mobileCtrl,
                          hint: 'Mobile Number *',
                          icon: Icons.phone_android_rounded,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Alternate Mobile Number
                        _sheetField(
                          controller: altMobileCtrl,
                          hint: 'Alternate Mobile Number (Optional)',
                          icon: Icons.phone_rounded,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                        ),
                      ],

                      const SizedBox(height: 16),

                      if (sheetErrorMsg != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  sheetErrorMsg!,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      Container(
                        key: AppTourService.createPlanPostButtonKey,
                        child: _sheetButton(
                          label: isPosting
                              ? 'PROCEEDING...'
                              : (selectedUserIds.length > 20
                                    ? 'SUBMIT STRANGERS MEET'
                                    : (selectedPaymentType == 'self_pay'
                                        ? 'POST PARTY PLAN (PAY ₹198)'
                                        : 'POST PARTY PLAN (PAY ₹99)')),
                          onTap: isPosting
                              ? () {}
                              : () async {
                                   setSheetState(() {
                                     sheetErrorMsg = null;
                                   });
                                   if (selectedVenue == null) {
                                     setSheetState(() => sheetErrorMsg = 'Please select a venue');
                                     return;
                                   }
                                   if (selectedDate == null || selectedTime == null) {
                                     setSheetState(() => sheetErrorMsg = 'Please select date and time');
                                     return;
                                   }

                                   final dt = DateTime(
                                     selectedDate!.year,
                                     selectedDate!.month,
                                     selectedDate!.day,
                                     selectedTime!.hour,
                                     selectedTime!.minute,
                                   );

                                   if (dt.isBefore(DateTime.now())) {
                                     setSheetState(() => sheetErrorMsg = 'Selected date and time cannot be in the past.');
                                     return;
                                   }

                                   final invalidReason = selectedVenue!.getInvalidReason(selectedDate!, selectedTime!);
                                   if (invalidReason != null) {
                                     setSheetState(() => sheetErrorMsg = invalidReason);
                                     return;
                                   }

                                  final userId = ApiService.currentUserId;
                                  if (userId == null) {
                                    setSheetState(() => sheetErrorMsg = 'Please login to post a plan');
                                    return;
                                  }

                                  if ((selectedPrivacy == 'Private' ||
                                          selectedPrivacy == 'Both') &&
                                      selectedUserIds.isEmpty) {
                                    setSheetState(() => sheetErrorMsg = 'Please select at least one profile to invite');
                                    return;
                                  }

                                  final isStrangersMeet =
                                      selectedUserIds.length > 20;

                                  if (isStrangersMeet) {
                                    if (subjectCtrl.text.trim().isEmpty) {
                                      setSheetState(() => sheetErrorMsg = 'Please enter an event subject');
                                      return;
                                    }
                                    if (taglineCtrl.text.trim().isEmpty) {
                                      setSheetState(() => sheetErrorMsg = 'Please enter requirement details');
                                      return;
                                    }
                                  }

                                  final mobileRegExp = RegExp(r'^[6-9]\d{9}$');
                                  if (isStrangersMeet) {
                                    if (mobileCtrl.text.trim().isEmpty) {
                                       setSheetState(() => sheetErrorMsg = 'Mobile number is required for Strangers Meet.');
                                       return;
                                     }
                                     if (!mobileRegExp.hasMatch(mobileCtrl.text.trim())) {
                                       setSheetState(() => sheetErrorMsg = 'Please enter a valid 10-digit mobile number.');
                                       return;
                                     }
                                     if (altMobileCtrl.text.trim().isNotEmpty && !mobileRegExp.hasMatch(altMobileCtrl.text.trim())) {
                                       setSheetState(() => sheetErrorMsg = 'Please enter a valid 10-digit alternate mobile number.');
                                       return;
                                     }
                                  }
                                  setSheetState(() => isPosting = true);

                                  if (isStrangersMeet) {
                                    try {
                                      final success =
                                          await ApiService.submitStrangersMeetRequest(
                                            venueId: selectedVenue!.id,
                                            subject: subjectCtrl.text.trim(),
                                            tagline: taglineCtrl.text.trim(),
                                            eventDateTime: dt
                                                .toUtc()
                                                .toIso8601String(),
                                            numberOfPersons:
                                                selectedUserIds.length,
                                            chargesPerHead: 0.0,
                                            mobileNumber: mobileCtrl.text.trim(),
                                            alternateMobileNumber: altMobileCtrl.text.trim(),
                                            foodPreference: selectedFoodPref,
                                            drinkPreference: selectedDrinkPref,
                                          );

                                      if (success) {
                                        if (!mounted) return;
                                        Navigator.pop(
                                          context,
                                        ); // Close bottom sheet
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Strangers Meet Request submitted successfully! Admin will review it.',
                                            ),
                                            backgroundColor: Colors.green,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      } else {
                                         if (!mounted) return;
                                         setSheetState(() {
                                           isPosting = false;
                                           sheetErrorMsg = 'Failed to submit Strangers Meet request.';
                                         });
                                       }
                                    } catch (e) {
                                       if (!mounted) return;
                                       setSheetState(() {
                                         isPosting = false;
                                         sheetErrorMsg = 'Error: ' + e.toString();
                                       });
                                     }
                                    return;
                                  }

                                  // Validate unique plan per day constraint
                                  try {
                                    final existingPlans =
                                        await ApiService.fetchMyPartyPlans();
                                    final targetDateStr = DateFormat(
                                      'yyyy-MM-dd',
                                    ).format(selectedDate!);
                                    final alreadyHasPlan = existingPlans.any((
                                      p,
                                    ) {
                                      final pStatus = p['status']
                                          ?.toString()
                                          .toLowerCase();
                                      if (pStatus == 'cancelled') return false;

                                      final pDtStr = p['planDateTime'];
                                      if (pDtStr == null) return false;
                                      try {
                                        final pDt = DateTime.parse(
                                          pDtStr,
                                        ).toLocal();
                                        final pDateStr = DateFormat(
                                          'yyyy-MM-dd',
                                        ).format(pDt);
                                        return pDateStr == targetDateStr;
                                      } catch (_) {
                                        return false;
                                      }
                                    });

                                    if (alreadyHasPlan) {
                                       if (!mounted) return;
                                       setSheetState(() {
                                         isPosting = false;
                                         sheetErrorMsg = 'You already have a party plan scheduled for this day. limit: 1 plan per day.';
                                       });
                                       return;
                                     }
                                  } catch (e) {
                                    debugPrint(
                                      'Error validating unique plan: $e',
                                    );
                                  }

                                  try {
                                    final response = await ApiService.post(
                                      '/api/mobile/party-plans',
                                      body: {
                                        'userId': userId,
                                        'venueId': selectedVenue!.id,
                                        'message': descriptionCtrl.text.isEmpty
                                            ? "Let's party at ${selectedVenue!.name}"
                                            : descriptionCtrl.text,
                                        'planDateTime': dt.toUtc().toIso8601String(),
                                        'privacyType': selectedPrivacy
                                            .toLowerCase(),
                                        'paymentStatus': 'pending',
                                        'paymentType': selectedPaymentType,
                                        'selectedUserIds': selectedUserIds,
                                        'mobileNumber': '',
                                        'optionalMobileNumber': '',
                                        'foodPreference': selectedFoodPref,
                                        'drinkPreference': selectedDrinkPref,
                                      },
                                    );

                                    if (response.statusCode == 200 ||
                                        response.statusCode == 201) {
                                      if (!mounted) return;
                                      Navigator.pop(
                                        context,
                                      ); // Close bottom sheet

                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Plan posted for ${selectedVenue!.name}!',
                                          ),
                                          backgroundColor:
                                              LunaraTheme.electricViolet,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );

                                      // Direct user to the Live Feed so they can see their post immediately
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const LiveFeedScreen(),
                                        ),
                                      );
                                    } else {
                                       if (!mounted) return;
                                       String errorMsg = 'Failed to save plan data.';
                                       try {
                                         final data = jsonDecode(response.body);
                                         errorMsg = data['message'] ?? data['error'] ?? errorMsg;
                                       } catch (_) {}
                                       setSheetState(() {
                                         isPosting = false;
                                         sheetErrorMsg = errorMsg;
                                       });
                                     }
                                  } catch (e) {
                                     if (!mounted) return;
                                     setSheetState(() {
                                       isPosting = false;
                                       sheetErrorMsg = 'Error: ' + e.toString();
                                     });
                                   }
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showArrangeStrangersMeetSheet(BuildContext context) {
    String searchQuery = '';
    Venue? selectedVenue;
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    int numberOfPersons = 21;
    bool useUPI = true; // Toggle between UPI and bank account
    String foodPreference = 'Both';
    String drinkPreference = 'Both';
    String? sheetErrorMsg;

    final subjectCtrl = TextEditingController();
    final taglineCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final altMobileCtrl = TextEditingController();
    final chargesCtrl = TextEditingController(text: '0');
    // Bank / UPI fields
    final upiCtrl = TextEditingController();
    final bankNameCtrl = TextEditingController();
    final accountNumberCtrl = TextEditingController();
    final accountHolderCtrl = TextEditingController();
    final ifscCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          AppTourService.showStrangersMeetTour(context);
        });
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final tomorrow = today.add(const Duration(days: 1));

            bool isDateOpen(DateTime date) {
              if (selectedVenue == null) return true;
              final closedDates = selectedVenue!.closedDates;
              if (closedDates != null) {
                final yyyy = date.year;
                final mm = date.month.toString().padLeft(2, '0');
                final dd = date.day.toString().padLeft(2, '0');
                final dateStr = '$yyyy-$mm-$dd';
                if (closedDates.contains(dateStr)) {
                  return false;
                }
              }
              final weekdaysMap = {
                1: 'Monday',
                2: 'Tuesday',
                3: 'Wednesday',
                4: 'Thursday',
                5: 'Friday',
                6: 'Saturday',
                7: 'Sunday',
              };
              final weekdayName = weekdaysMap[date.weekday];
              if (selectedVenue!.daysOpen != null && selectedVenue!.daysOpen!.isNotEmpty) {
                final isOpenOnWeekday = weekdayName != null && selectedVenue!.daysOpen!.any((d) {
                  final str = d.toString().trim().toLowerCase();
                  final fullDay = weekdayName.toLowerCase();
                  final shortDay = weekdayName.substring(0, 3).toLowerCase();
                  return str.contains(fullDay) || str.contains(shortDay);
                });
                if (!isOpenOnWeekday) {
                  return false;
                }
              }
              return true;
            }

            bool isTimeSlotValid(TimeOfDay time, [DateTime? specificDate]) {
              final activeDate = specificDate ?? selectedDate;
              if (activeDate == null) return true;
              if (selectedVenue == null) return true;

              final invalidReason = selectedVenue!.getInvalidReason(activeDate, time);
              if (invalidReason != null) {
                return false;
              }

              final selectedDateTime = DateTime(
                activeDate.year,
                activeDate.month,
                activeDate.day,
                time.hour,
                time.minute,
              );
              final minAllowedDateTime = DateTime.now().add(const Duration(hours: 1));
              if (selectedDateTime.isBefore(minAllowedDateTime)) {
                return false;
              }
              return true;
            }

            final List<DateTime> dynamicDates = [];
            DateTime checkDate = today;
            while (dynamicDates.length < 6) {
              if (isDateOpen(checkDate)) {
                dynamicDates.add(checkDate);
              }
              checkDate = checkDate.add(const Duration(days: 1));
            }

            Future<void> handleDateSelection(DateTime date) async {
              if (selectedVenue == null) {
                setSheetState(() => sheetErrorMsg = 'Please select a venue first.');
                return;
              }
              final yyyy = date.year;
              final mm = date.month.toString().padLeft(2, '0');
              final dd = date.day.toString().padLeft(2, '0');
              final dateStr = '$yyyy-$mm-$dd';
              if (selectedVenue!.closedDates != null && selectedVenue!.closedDates!.contains(dateStr)) {
                VenueTimingErrorDialog.show(
                  context,
                  venueName: selectedVenue!.name,
                  daysOpen: selectedVenue!.daysOpen,
                  openingTime: selectedVenue!.openingTime,
                  closingTime: selectedVenue!.closingTime,
                  closedDates: selectedVenue!.closedDates,
                );
                return;
              }
              final weekdaysMap = {
                1: 'Monday',
                2: 'Tuesday',
                3: 'Wednesday',
                4: 'Thursday',
                5: 'Friday',
                6: 'Saturday',
                7: 'Sunday',
              };
              final weekdayName = weekdaysMap[date.weekday];
              if (selectedVenue!.daysOpen != null && selectedVenue!.daysOpen!.isNotEmpty) {
                final isOpenOnWeekday = weekdayName != null && selectedVenue!.daysOpen!.any((d) {
                  final str = d.toString().trim().toLowerCase();
                  final fullDay = weekdayName.toLowerCase();
                  final shortDay = weekdayName.substring(0, 3).toLowerCase();
                  return str.contains(fullDay) || str.contains(shortDay);
                });
                if (!isOpenOnWeekday) {
                  VenueTimingErrorDialog.show(
                    context,
                    venueName: selectedVenue!.name,
                    daysOpen: selectedVenue!.daysOpen,
                    openingTime: selectedVenue!.openingTime,
                    closingTime: selectedVenue!.closingTime,
                    closedDates: selectedVenue!.closedDates,
                  );
                  return;
                }
              }

              final time = await showTimePicker(
                context: context,
                initialTime: selectedTime ?? const TimeOfDay(hour: 22, minute: 0),
              );

              if (time != null) {
                final selectedDateTime = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
                if (selectedDateTime.isBefore(DateTime.now())) {
                  setSheetState(() => sheetErrorMsg = 'Selected date and time cannot be in the past.');
                  return;
                }

                final invalidReason = selectedVenue!.getInvalidReason(date, time);
                if (invalidReason != null) {
                  VenueTimingErrorDialog.show(
                    context,
                    venueName: selectedVenue!.name,
                    daysOpen: selectedVenue!.daysOpen,
                    openingTime: selectedVenue!.openingTime,
                    closingTime: selectedVenue!.closingTime,
                    closedDates: selectedVenue!.closedDates,
                  );
                  return;
                }

                setSheetState(() {
                  selectedDate = date;
                  selectedTime = time;
                  final formattedTime = _formatTimeOfBooking(
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  );
                  dateCtrl.text =
                      "${DateFormat('MMM dd, yyyy').format(date)} at $formattedTime";
                });
              }
            }

            Future<void> handleCustomDateSelection() async {
              if (selectedVenue == null) {
                setSheetState(() => sheetErrorMsg = 'Please select a venue first.');
                return;
              }
              final date = await showDatePicker(
                context: context,
                initialDate: selectedDate ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (date != null) {
                await handleDateSelection(date);
              }
            }

            Widget buildDateChip(String label, DateTime dateVal, bool isSelected) {
              return GestureDetector(
                onTap: () {
                  if (selectedVenue == null) {
                    setSheetState(() => sheetErrorMsg = 'Please select a venue first.');
                    return;
                  }
                  setSheetState(() {
                    selectedDate = dateVal;
                    if (selectedTime != null && !isTimeSlotValid(selectedTime!, dateVal)) {
                      selectedTime = null;
                    }
                    if (selectedDate != null && selectedTime != null) {
                      final formattedTime = _formatTimeOfBooking(
                        '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}',
                      );
                      dateCtrl.text =
                          "${DateFormat('MMM dd, yyyy').format(selectedDate!)} at $formattedTime";
                    } else if (selectedDate != null) {
                      dateCtrl.text =
                          "${DateFormat('MMM dd, yyyy').format(selectedDate!)}";
                    } else {
                      dateCtrl.text = '';
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? LunaraTheme.electricViolet : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? LunaraTheme.electricViolet : Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('MMM d').format(dateVal),
                        style: TextStyle(
                          color: isSelected ? Colors.white70 : Colors.black54,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget buildCustomChip(bool isSelected) {
              return GestureDetector(
                onTap: handleCustomDateSelection,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? LunaraTheme.electricViolet : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? LunaraTheme.electricViolet : Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 12,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Custom',
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selectedDate != null &&
                                !dynamicDates.any((d) =>
                                    d.year == selectedDate!.year &&
                                    d.month == selectedDate!.month &&
                                    d.day == selectedDate!.day)
                            ? DateFormat('MMM d').format(selectedDate!)
                            : 'Choose Date',
                        style: TextStyle(
                          color: isSelected ? Colors.white70 : Colors.black54,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final List<Venue> displayedVenues = searchQuery.isEmpty
                ? _allVenues.take(5).toList()
                : _allVenues
                      .where(
                        (v) =>
                            v.name.toLowerCase().contains(
                              searchQuery.toLowerCase(),
                            ) ||
                            v.city.toLowerCase().contains(
                              searchQuery.toLowerCase(),
                            ),
                      )
                      .toList();

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.90,
              ),
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  24,
                  16,
                  24,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'ARRANGE STRANGERS MEET',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Venue Search
                      Container(
                        key: AppTourService.strangersMeetSearchKey,
                        child: _sheetField(
                          hint: 'Search venue...',
                          icon: Icons.search_rounded,
                          onChanged: (val) =>
                              setSheetState(() => searchQuery = val),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Horizontal Venue List
                      if (_isLoadingVenues)
                        const Center(child: CircularProgressIndicator())
                      else if (displayedVenues.isEmpty)
                        const Text(
                          'No venues found',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        )
                      else
                        SizedBox(
                          height: 100,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: displayedVenues.length,
                            itemBuilder: (context, index) {
                              final v = displayedVenues[index];
                              final isSelected = selectedVenue?.id == v.id;
                              return GestureDetector(
                                onTap: () {
                                  setSheetState(() {
                                    selectedVenue = v;
                                    // Validate previously selected date & time
                                    if (selectedDate != null &&
                                        !_isVenueOpenOnDate(v, selectedDate!)) {
                                      selectedDate = null;
                                      selectedTime = null;
                                      dateCtrl.clear();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Cleared date selection because ${v.name} is closed on that day.',
                                          ),
                                          backgroundColor: Colors.orangeAccent,
                                        ),
                                      );
                                    } else if (selectedTime != null &&
                                        !_isTimeWithinVenueHours(
                                          selectedTime!,
                                          v.openingTime,
                                          v.closingTime,
                                        )) {
                                      selectedTime = null;
                                      dateCtrl.clear();
                                      if (selectedDate != null) {
                                        dateCtrl.text = DateFormat(
                                          'MMM dd, yyyy',
                                        ).format(selectedDate!);
                                      }
                                      final openStr = _formatTimeOfBooking(
                                        v.openingTime,
                                      );
                                      final closeStr = _formatTimeOfBooking(
                                        v.closingTime,
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Cleared time selection because it is outside ${v.name}\'s working hours ($openStr - $closeStr).',
                                          ),
                                          backgroundColor: Colors.orangeAccent,
                                        ),
                                      );
                                    }
                                  });
                                },
                                child: Container(
                                  width: 140,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? LunaraTheme.electricViolet
                                          : Colors.grey[200]!,
                                      width: 2,
                                    ),
                                    image: v.imageUrl != null
                                        ? DecorationImage(
                                            image: NetworkImage(v.imageUrl!),
                                            fit: BoxFit.cover,
                                            colorFilter: ColorFilter.mode(
                                              Colors.black.withValues(
                                                alpha: isSelected ? 0.2 : 0.4,
                                              ),
                                              BlendMode.darken,
                                            ),
                                          )
                                        : null,
                                    color: Colors.grey[100],
                                  ),
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        v.name.toUpperCase(),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                      const SizedBox(height: 20),

                      // Event Subject
                      _sheetField(
                        controller: subjectCtrl,
                        hint: 'Enter Event Subject...',
                        icon: Icons.title_rounded,
                      ),
                      const SizedBox(height: 14),

                      // Tag line / other details
                      _sheetField(
                        controller: taglineCtrl,
                        hint: 'Enter Requirement Details...',
                        icon: Icons.subtitles_rounded,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 10),

                      // Date & Time Picker Options
                      const Text(
                        'SELECT DATE & TIME',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            ...dynamicDates.map((dateVal) {
                              String label = '';
                              if (dateVal.year == today.year &&
                                  dateVal.month == today.month &&
                                  dateVal.day == today.day) {
                                label = 'Today';
                              } else if (dateVal.year == tomorrow.year &&
                                  dateVal.month == tomorrow.month &&
                                  dateVal.day == tomorrow.day) {
                                label = 'Tomorrow';
                              } else {
                                label = DateFormat('E').format(dateVal);
                              }

                              final isSelected = selectedDate != null &&
                                  selectedDate!.year == dateVal.year &&
                                  selectedDate!.month == dateVal.month &&
                                  selectedDate!.day == dateVal.day;

                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: buildDateChip(label, dateVal, isSelected),
                              );
                            }),
                            buildCustomChip(
                              selectedDate != null &&
                              !dynamicDates.any((d) =>
                                  d.year == selectedDate!.year &&
                                  d.month == selectedDate!.month &&
                                  d.day == selectedDate!.day)
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'SELECT TIME SLOT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final predefinedTimes = [
                            const TimeOfDay(hour: 19, minute: 0), // 7 PM
                            const TimeOfDay(hour: 20, minute: 0), // 8 PM
                            const TimeOfDay(hour: 21, minute: 0), // 9 PM
                            const TimeOfDay(hour: 22, minute: 0), // 10 PM
                            const TimeOfDay(hour: 23, minute: 0), // 11 PM
                            const TimeOfDay(hour: 0, minute: 0),  // 12 AM
                          ];

                          final validTimes = predefinedTimes.where((t) => isTimeSlotValid(t)).toList();

                          String formatTimeOfDay(TimeOfDay tod) {
                            final hour = tod.hour == 0 ? 12 : (tod.hour > 12 ? tod.hour - 12 : tod.hour);
                            final ampm = tod.hour >= 12 ? 'PM' : 'AM';
                            return '$hour:00 $ampm';
                          }

                          Widget buildTimeChip(String label, TimeOfDay tod, bool isSelected) {
                            return GestureDetector(
                              onTap: () {
                                setSheetState(() {
                                  selectedTime = tod;
                                  if (selectedDate != null) {
                                    final formattedTime = _formatTimeOfBooking(
                                      '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}',
                                    );
                                    dateCtrl.text =
                                        "${DateFormat('MMM dd, yyyy').format(selectedDate!)} at $formattedTime";
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected ? LunaraTheme.electricViolet : Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? LunaraTheme.electricViolet : Colors.grey[300]!,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            );
                          }

                          // Determine if selected time is a custom time (not in validTimes)
                          bool isCustomSelected = false;
                          if (selectedTime != null) {
                            isCustomSelected = !validTimes.any((t) => t.hour == selectedTime!.hour && t.minute == selectedTime!.minute);
                          }

                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                ...validTimes.map((tod) {
                                  final label = formatTimeOfDay(tod);
                                  final isSelected = selectedTime != null &&
                                      selectedTime!.hour == tod.hour &&
                                      selectedTime!.minute == tod.minute;

                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: buildTimeChip(label, tod, isSelected),
                                  );
                                }),
                                GestureDetector(
                                  onTap: () async {
                                    final TimeOfDay? picked = await showTimePicker(
                                      context: context,
                                      initialTime: selectedTime ?? const TimeOfDay(hour: 22, minute: 0),
                                    );
                                    if (picked != null) {
                                      if (!isTimeSlotValid(picked)) {
                                        VenueTimingErrorDialog.show(
                                          context,
                                          venueName: selectedVenue!.name,
                                          daysOpen: selectedVenue!.daysOpen,
                                          openingTime: selectedVenue!.openingTime,
                                          closingTime: selectedVenue!.closingTime,
                                          closedDates: selectedVenue!.closedDates,
                                        );
                                        return;
                                      }
                                      setSheetState(() {
                                        selectedTime = picked;
                                        if (selectedDate != null) {
                                          final formattedTime = _formatTimeOfBooking(
                                            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
                                          );
                                          dateCtrl.text =
                                              "${DateFormat('MMM dd, yyyy').format(selectedDate!)} at $formattedTime";
                                        }
                                      });
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isCustomSelected ? LunaraTheme.electricViolet : Colors.grey[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isCustomSelected ? LunaraTheme.electricViolet : Colors.grey[300]!,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 12,
                                          color: isCustomSelected ? Colors.white : Colors.black87,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isCustomSelected
                                              ? _formatTimeOfBooking(
                                                  '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}')
                                              : 'Custom',
                                          style: TextStyle(
                                            color: isCustomSelected ? Colors.white : Colors.black87,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      _sheetField(
                        controller: dateCtrl,
                        hint: 'Selected Date & Time',
                        icon: Icons.calendar_today_rounded,
                        readOnly: true,
                        onTap: () {
                          if (selectedDate != null) {
                            handleDateSelection(selectedDate!);
                          } else {
                            handleCustomDateSelection();
                          }
                        },
                      ),

                      const SizedBox(height: 16),

                      // Mobile Number
                      _sheetField(
                        controller: mobileCtrl,
                        hint: 'Enter Mobile Number',
                        icon: Icons.phone_android_rounded,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Alternate Mobile Number
                      _sheetField(
                        controller: altMobileCtrl,
                        hint: 'Alternate Mobile Number (Optional)',
                        icon: Icons.phone_rounded,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'FOOD & DRINK PREFERENCE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Food Preference',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey[200]!),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButtonFormField<String>(
                                      value: foodPreference,
                                      decoration: const InputDecoration(
                                        prefixIcon: Icon(Icons.restaurant, color: Color(0xFF7C3AED), size: 16),
                                        prefixIconConstraints: BoxConstraints(minWidth: 24, minHeight: 16),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                                      ),
                                      items: const ['Veg', 'Non-Veg', 'Both'].map((String val) {
                                        return DropdownMenuItem<String>(
                                          value: val,
                                          child: Text(val, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setSheetState(() => foodPreference = val);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Drink Preference',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey[200]!),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButtonFormField<String>(
                                      value: drinkPreference,
                                      decoration: const InputDecoration(
                                        prefixIcon: Icon(Icons.local_bar, color: Color(0xFF7C3AED), size: 16),
                                        prefixIconConstraints: BoxConstraints(minWidth: 24, minHeight: 16),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                                      ),
                                      items: const ['Alcoholic', 'Non-Alcoholic', 'Both'].map((String val) {
                                        return DropdownMenuItem<String>(
                                          value: val,
                                          child: Text(val, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setSheetState(() => drinkPreference = val);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── PAYMENT DETAILS SECTION ──────────────────────
                      const Text(
                        'PAYMENT DETAILS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add your bank details so admin can settle your earnings after the meet.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 12),

                      // UPI / Bank toggle
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setSheetState(() => useUPI = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: useUPI ? const Color(0xFF7C3AED) : Colors.grey[100],
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(10),
                                    bottomLeft: Radius.circular(10),
                                  ),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: Center(
                                  child: Text(
                                    'UPI ID',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: useUPI ? Colors.white : Colors.black54,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setSheetState(() => useUPI = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: !useUPI ? const Color(0xFF7C3AED) : Colors.grey[100],
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(10),
                                    bottomRight: Radius.circular(10),
                                  ),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: Center(
                                  child: Text(
                                    'Bank Account',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: !useUPI ? Colors.white : Colors.black54,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (useUPI) ...[
                        _sheetField(
                          controller: upiCtrl,
                          hint: 'Enter UPI ID (e.g. name@upi)',
                          icon: Icons.qr_code_rounded,
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ] else ...[
                        _sheetField(
                          controller: bankNameCtrl,
                          hint: 'Bank Name',
                          icon: Icons.account_balance_rounded,
                        ),
                        const SizedBox(height: 10),
                        _sheetField(
                          controller: accountHolderCtrl,
                          hint: 'Account Holder Name',
                          icon: Icons.person_rounded,
                        ),
                        const SizedBox(height: 10),
                        _sheetField(
                          controller: accountNumberCtrl,
                          hint: 'Account Number',
                          icon: Icons.credit_card_rounded,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 10),
                        _sheetField(
                          controller: ifscCtrl,
                          hint: 'IFSC Code',
                          icon: Icons.code_rounded,
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Number of Persons
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.people_alt_rounded,
                              color: Color(0xFF7C3AED),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'No. of Persons',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            // Decrement
                            GestureDetector(
                              onTap: () {
                                if (numberOfPersons > 21) {
                                  setSheetState(() => numberOfPersons--);
                                }
                              },
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: numberOfPersons > 21
                                      ? const Color(0xFF7C3AED)
                                      : Colors.grey[300],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.remove,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 32,
                              child: Text(
                                '$numberOfPersons',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF7C3AED),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Increment
                            GestureDetector(
                              onTap: () {
                                if (numberOfPersons < 50) {
                                  setSheetState(() => numberOfPersons++);
                                }
                              },
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: numberOfPersons < 50
                                      ? const Color(0xFF7C3AED)
                                      : Colors.grey[300],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 4,
                          top: 4,
                          bottom: 4,
                        ),
                        child: Text(
                          'Min 21 · Max 50 persons',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),

                      if (sheetErrorMsg != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  sheetErrorMsg!,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      Container(
                        key: AppTourService.strangersMeetArrangeButtonKey,
                        child: _sheetButton(
                          label: 'SEND REQUEST',
                          onTap: () async {
                            setSheetState(() => sheetErrorMsg = null);
                            if (selectedVenue == null) {
                              setSheetState(() => sheetErrorMsg = 'Please select a venue');
                              return;
                            }
                            if (subjectCtrl.text.trim().isEmpty) {
                              setSheetState(() => sheetErrorMsg = 'Please enter an event subject');
                              return;
                            }
                            if (taglineCtrl.text.trim().isEmpty) {
                              setSheetState(() => sheetErrorMsg = 'Please enter requirement details');
                              return;
                            }
                            if (selectedDate == null || selectedTime == null) {
                              setSheetState(() => sheetErrorMsg = 'Please select date and time');
                              return;
                            }
                            if (numberOfPersons <= 20 || numberOfPersons > 50) {
                              setSheetState(() => sheetErrorMsg = 'Number of persons must be between 21 and 50');
                              return;
                            }
                            final mobileRegExp = RegExp(r'^[6-9]\d{9}$');
                            if (mobileCtrl.text.trim().isEmpty) {
                              setSheetState(() => sheetErrorMsg = 'Please enter mobile number');
                              return;
                            }
                            if (!mobileRegExp.hasMatch(mobileCtrl.text.trim())) {
                              setSheetState(() => sheetErrorMsg = 'Please enter a valid 10-digit mobile number.');
                              return;
                            }
                            if (altMobileCtrl.text.trim().isNotEmpty && !mobileRegExp.hasMatch(altMobileCtrl.text.trim())) {
                              setSheetState(() => sheetErrorMsg = 'Please enter a valid 10-digit alternate mobile number.');
                              return;
                            }

                            final userId = ApiService.currentUserId;
                            if (userId == null) {
                              setSheetState(() => sheetErrorMsg = 'Please login to continue');
                              return;
                            }

                            final dt = DateTime(
                              selectedDate!.year,
                              selectedDate!.month,
                              selectedDate!.day,
                              selectedTime!.hour,
                              selectedTime!.minute,
                            );

                            if (dt.isBefore(DateTime.now())) {
                              setSheetState(() => sheetErrorMsg = 'Please select a future time');
                              return;
                            }

                            // Show loading indicator
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );

                            final success =
                                 await ApiService.submitStrangersMeetRequest(
                                   venueId: selectedVenue!.id,
                                   subject: subjectCtrl.text.trim(),
                                   tagline: taglineCtrl.text.trim(),
                                   eventDateTime: dt.toUtc().toIso8601String(),
                                   numberOfPersons: numberOfPersons,
                                   chargesPerHead: 0.0,
                                   mobileNumber: mobileCtrl.text.trim(),
                                   alternateMobileNumber: altMobileCtrl.text.trim(),
                                   // Bank/UPI details
                                   upiId: useUPI ? upiCtrl.text.trim() : null,
                                   bankName: !useUPI ? bankNameCtrl.text.trim() : null,
                                   accountNumber: !useUPI ? accountNumberCtrl.text.trim() : null,
                                   accountHolderName: !useUPI ? accountHolderCtrl.text.trim() : null,
                                   ifscCode: !useUPI ? ifscCtrl.text.trim() : null,
                                   foodPreference: foodPreference,
                                   drinkPreference: drinkPreference,
                                 );

                            if (context.mounted) {
                              Navigator.pop(context); // Close loading dialog
                            }

                            if (success) {
                              if (context.mounted) {
                                Navigator.pop(context); // Close bottom sheet
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Request submitted successfully! Admin will review it.',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } else {
                              if (context.mounted) {
                                setSheetState(() {
                                  sheetErrorMsg = 'Failed to submit request. Please try again.';
                                });
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _sheetField({
    TextEditingController? controller,
    required String hint,
    required IconData icon,
    ValueChanged<String>? onChanged,
    TextInputType? keyboardType,
    int? maxLines = 1,
    bool readOnly = false,
    VoidCallback? onTap,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: keyboardType,
        maxLines: maxLines,
        readOnly: readOnly,
        onTap: onTap,
        inputFormatters: inputFormatters,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
          prefixIcon: Icon(icon, color: LunaraTheme.electricViolet, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _sheetButton({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LunaraTheme.purpleGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}

class PlanManagerSimulationScreen extends StatefulWidget {
  const PlanManagerSimulationScreen({super.key});

  @override
  State<PlanManagerSimulationScreen> createState() =>
      _PlanManagerSimulationScreenState();
}

class _PlanManagerSimulationScreenState
    extends State<PlanManagerSimulationScreen> {
  int _currentPhase =
      0; // 0: Live, 1: Requests, 2: Deposits, 3: Check-in, 4: Completed, 5: Restricted
  int _noShowStrikes = 0;
  bool _hostPaid = false;
  bool _guestPaid = false;
  int _secondsLeft = 1800; // 30 mins
  Timer? _countdownTimer;
  String? _acceptedGuest;
  String _simulationLog = "Welcome to Plan Simulation Center.";

  final List<Map<String, String>> _mockRequests = [
    {
      'name': 'Priya S.',
      'age': '24',
      'vibe': 'UX Designer',
      'avatar': 'assets/images/profiles/lyra.png',
    },
    {
      'name': 'Rahul M.',
      'age': '29',
      'vibe': 'Finance Analyst',
      'avatar': 'assets/images/profiles/elara.png',
    },
    {
      'name': 'Alex R.',
      'age': '27',
      'vibe': 'Software Engineer',
      'avatar': 'assets/images/profiles/zane.png',
    },
    {
      'name': 'Mia K.',
      'age': '25',
      'vibe': 'Marketing Lead',
      'avatar': 'assets/images/profiles/zane.png',
    },
  ];

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _secondsLeft = 1800;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        setState(() {
          _secondsLeft--;
        });
      } else {
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    _countdownTimer?.cancel();
    setState(() {
      if (!_hostPaid) {
        _simulationLog =
            "TIMEOUT: Host didn't pay in 30m. Guest is refunded. Suggested other plans.";
        _hostPaid = false;
        _guestPaid = false;
        _currentPhase = 0;
      } else if (!_guestPaid) {
        _simulationLog =
            "TIMEOUT: Guest didn't pay in 30m. Post relived again.";
        _hostPaid = false;
        _guestPaid = false;
        _currentPhase = 1; // back to requests
      }
    });
  }

  void _addLog(String msg) {
    setState(() {
      _simulationLog = msg;
    });
  }

  String _formatTimer() {
    final minutes = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsLeft % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'SIMULATION CENTER',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            fontSize: 16,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSimulationInfoCard(),
            const SizedBox(height: 24),
            _buildLogPanel(),
            const SizedBox(height: 24),
            const Text(
              'ACTIVE FLOW STAGE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            _buildStageContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulationInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.stars,
                color: LunaraTheme.electricViolet,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'PLAN DETAILS (MOCK)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.grey[800],
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _infoRow('Venue Name', 'MiAMi Club'),
          _infoRow('Date & Time', 'Tonight at 23:00'),
          _infoRow('Deposit Fee', '₹99 per head'),
          _infoRow('Strikes Active', '$_noShowStrikes / 2 (Lifetime ban on 2)'),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          Text(
            val,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SYSTEM LOG',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.black45,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _simulationLog,
            style: const TextStyle(
              fontFamily: 'Courier',
              fontSize: 12,
              color: LunaraTheme.electricViolet,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageContent() {
    switch (_currentPhase) {
      case 0:
        return _stageLive();
      case 1:
        return _stageRequests();
      case 2:
        return _stageDeposits();
      case 3:
        return _stageCheckIn();
      case 4:
        return _stageCompleted();
      case 5:
        return _stageRestricted();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _stageLive() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          const Icon(Icons.wifi, color: Colors.green, size: 48),
          const SizedBox(height: 16),
          const Text(
            'PLAN IS LIVE',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your party plan is broadcasted to matches. Awaiting join requests.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _currentPhase = 1;
                _addLog("4 match requests received from nearby users.");
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: LunaraTheme.electricViolet,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Simulate 4 Incoming Requests',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stageRequests() {
    return Column(
      children: [
        const Text(
          'Select 1 person to accept and match. Other 3 requests will be deleted.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        ..._mockRequests.map((req) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.purple[50],
                  child: Text(
                    req['name']![0],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: LunaraTheme.electricViolet,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${req['name']!}, ${req['age']!}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        req['vibe']!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _acceptedGuest = req['name'];
                      _currentPhase = 2;
                      _startTimer();
                      _addLog(
                        "Accepted ${_acceptedGuest!}. 3 other requests deleted. Starting 30m deposit timer.",
                      );
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LunaraTheme.electricViolet,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Accept',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _stageDeposits() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.timer_outlined,
                color: Colors.redAccent,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                _formatTimer(),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                  fontFamily: 'Courier',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'DEPOSIT STAGE (₹99 per head)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          _paymentStatusRow('Host (You)', _hostPaid),
          const SizedBox(height: 8),
          _paymentStatusRow(_acceptedGuest ?? 'Guest', _guestPaid),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _hostPaid
                      ? null
                      : () {
                          setState(() {
                            _hostPaid = true;
                            _addLog("Host paid safety deposit of ₹99.");
                            if (_hostPaid && _guestPaid) {
                              _countdownTimer?.cancel();
                              _currentPhase = 3;
                              _addLog(
                                "Both paid! Party confirmed. Geolocation check-in unlocked.",
                              );
                            }
                          });
                        },
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Pay Host ₹99',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _guestPaid
                      ? null
                      : () {
                          setState(() {
                            _guestPaid = true;
                            _addLog(
                              "Guest (${_acceptedGuest!}) paid safety deposit of ₹99.",
                            );
                            if (_hostPaid && _guestPaid) {
                              _countdownTimer?.cancel();
                              _currentPhase = 3;
                              _addLog(
                                "Both paid! Party confirmed. Geolocation check-in unlocked.",
                              );
                            }
                          });
                        },
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Guest Pay ₹99',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _handleTimeout,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber[800],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Force Timeout (Simulate 30 min expiration)',
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentStatusRow(String name, bool isPaid) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        Row(
          children: [
            Icon(
              isPaid ? Icons.check_circle : Icons.pending,
              color: isPaid ? Colors.green : Colors.amber,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              isPaid ? 'PAID' : 'PENDING',
              style: TextStyle(
                color: isPaid ? Colors.green : Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stageCheckIn() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.location_on,
            color: LunaraTheme.electricViolet,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            'GEOLOCATION CHECK-IN',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Simulate whether both parties checked in successfully at the venue coordinates.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _currentPhase = 4;
                      _addLog(
                        "MATCH SUCCESS: Geolocation checks pass. Deposit refund scheduled in 3 hours.",
                      );
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Match Geolocation',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _noShowStrikes++;
                      _addLog(
                        "NO-SHOW REPORTED: warning notice sent. Strike added.",
                      );
                      if (_noShowStrikes >= 2) {
                        _currentPhase = 5;
                        _addLog(
                          "RESTRICTED: User banned for life after 2 strikes.",
                        );
                      } else {
                        _hostPaid = false;
                        _guestPaid = false;
                        _currentPhase = 0;
                      }
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[800],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Report No-Show',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stageCompleted() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          const Icon(Icons.celebration, color: Colors.amber, size: 48),
          const SizedBox(height: 16),
          const Text(
            'PARTY ONGOING',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Refund of ₹99 deposit will execute automatically 3 hours after party time.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _addLog(
                  "REFUND COMPLETED: Safety deposit of ₹99 refunded to both parties.",
                );
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Refund of ₹99 processed successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: LunaraTheme.electricViolet,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Simulate 3 Hours Later (Refund)',
              style: TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              setState(() {
                _hostPaid = false;
                _guestPaid = false;
                _currentPhase = 0;
                _addLog("Reset simulation.");
              });
            },
            child: const Text('Reset Simulation'),
          ),
        ],
      ),
    );
  }

  Widget _stageRestricted() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.red[100]!),
      ),
      child: Column(
        children: [
          Icon(Icons.gavel_rounded, color: Colors.red[800], size: 48),
          const SizedBox(height: 16),
          Text(
            'PROFILE RESTRICTED',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.red[900],
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'User has been permanently restricted (Lifetime Ban) due to 2 consecutive no-show violations.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.red[900]),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _noShowStrikes = 0;
                _hostPaid = false;
                _guestPaid = false;
                _currentPhase = 0;
                _addLog("Profile restrictions cleared. Simulation reset.");
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[800],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Clear Ban & Reset',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
