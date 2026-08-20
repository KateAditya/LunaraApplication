import 'dart:async';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:geolocator/geolocator.dart';
import '../../services/google_places_service.dart';
import 'package:carousel_slider/carousel_slider.dart';
import '../../core/theme.dart';
import 'venue_detail_screen.dart';
import 'all_venues_screen.dart';
import 'upcoming_party_screen.dart';
import 'booking_process_screen.dart';
import '../social/all_posts_screen.dart';
import '../../services/api_service.dart';
import '../../models/venue.dart';
import '../../models/user.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../widgets/lunara_network_image.dart';
import 'all_users_screen.dart';
import '../social/post_detail_screen.dart';
import '../profile/profile_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../profile/lunara_wallet_screen.dart';
import '../../services/app_tour_service.dart';
import '../../widgets/vip_upgrade_button.dart';
import '../../widgets/ad_announcement_dialog.dart';
import '../../widgets/lunara_pulsing_logo_button.dart';
import '../../main.dart';

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
  StreamSubscription<Position>? _positionStreamSubscription;
  final Map<String, Map<String, dynamic>> _googleRatings = {};
  int _currentAdIndex = 0;
  List<Map<String, dynamic>> _upcomingNights = [];
  bool _sortByDistance = false;
  bool _isProfileCardDismissed = false;
  bool _hasShownAdPopup = false;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    GooglePlacesService.addListener(_onDistanceUpdated);
    _loadVenues();
    _determinePosition(requestIfNeeded: true);
  }

  void _onDistanceUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    GooglePlacesService.removeListener(_onDistanceUpdated);
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

  Future<void> _determinePosition({
    bool requestIfNeeded = false,
    bool showLoader = false,
  }) async {
    if (showLoader && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: LunaraTheme.cyberCyan),
        ),
      );
    }

    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (requestIfNeeded) {
        AppLockWrapper.ignoreNextPause = true;
        await Geolocator.openLocationSettings();
      }
      if (showLoader && mounted) Navigator.pop(context);
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      if (requestIfNeeded) {
        AppLockWrapper.ignoreNextPause = true;
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (showLoader && mounted) Navigator.pop(context);
          return;
        }
      } else {
        if (showLoader && mounted) Navigator.pop(context);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (requestIfNeeded) {
        AppLockWrapper.ignoreNextPause = true;
        if (!kIsWeb) {
          try {
            await Geolocator.openAppSettings();
          } catch (e) {
            debugPrint("openAppSettings error: $e");
          }
        }
      }
      if (showLoader && mounted) Navigator.pop(context);
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
        _prefetchRoadDistances(_allVenues);
      }
      _startLocationUpdates();
      if (showLoader && mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint("Error getting location: $e");
      if (showLoader && mounted) Navigator.pop(context);
    }
  }

  void _prefetchRoadDistances(List<Venue> venues) {
    if (_currentPosition == null || venues.isEmpty) return;
    final dests = venues
        .where((v) => v.latitude != null && v.longitude != null && v.latitude != 0.0 && v.longitude != 0.0)
        .map((v) => {'lat': v.latitude!, 'lng': v.longitude!})
        .toList();
    if (dests.isNotEmpty) {
      GooglePlacesService.prefetchDistances(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        dests,
      );
    }
  }

  void _startLocationUpdates() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen(
          (Position position) {
            if (mounted) {
              setState(() {
                _currentPosition = position;
              });
              _prefetchRoadDistances(_allVenues);
            }
          },
          onError: (e) {
            debugPrint("Error in location stream: $e");
          },
        );
  }

  void _fetchGoogleRatingsForVenues(List<Venue> venues) async {
    if (kIsWeb || venues.isEmpty) return;
    final Map<String, Map<String, dynamic>> newRatings = {};
    for (final venue in venues.take(10)) {
      if (venue.name.isNotEmpty && !_googleRatings.containsKey(venue.id)) {
        try {
          final result = await GooglePlacesService.fetchGoogleRating(venue.name, venue.city);
          if (result != null) {
            newRatings[venue.id] = result;
          }
        } catch (_) {}
      }
    }
    if (newRatings.isNotEmpty && mounted) {
      setState(() {
        _googleRatings.addAll(newRatings);
      });
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

              String dateStr = ad['eventDate'] ?? ad['toDate'] ?? ad['fromDate'] ?? '';
              if (dateStr.isNotEmpty) {
                try {
                  final dt = DateTime.parse(dateStr).toLocal();
                  dateStr = DateFormat('EEEE, MMM dd').format(dt);
                } catch (_) {}
              } else {
                dateStr = 'Upcoming';
              }

              final bool isUnlimited = ad['isUnlimited'] == true;
              final int seatLimit = ad['seatLimit'] is num ? (ad['seatLimit'] as num).toInt() : (int.tryParse(ad['seatLimit']?.toString() ?? '0') ?? 0);
              final int filledSeats = ad['filledSeats'] is num ? (ad['filledSeats'] as num).toInt() : (int.tryParse(ad['filledSeats']?.toString() ?? '0') ?? 0);
              final int remainingSeats = isUnlimited ? 999999 : (seatLimit - filledSeats);
              final double entryPrice = ad['entryPrice'] is num ? (ad['entryPrice'] as num).toDouble() : (double.tryParse(ad['entryPrice']?.toString() ?? '0') ?? 0.0);

              return {
                'eventId': ad['id'],
                'title': ad['title'] ?? ad['description'] ?? 'Special Event',
                'date': dateStr,
                'rawDate': ad['eventDate'] ?? ad['toDate'] ?? ad['fromDate'],
                'venue': venue['name'] ?? 'Unknown Venue',
                'image': imageUrl,
                'isAsset': false,
                'venueId': ad['venueId'],
                'venueMap': venue,
                'aboutEvent': ad['aboutEvent'],
                'entryPrice': entryPrice,
                'isUnlimited': isUnlimited,
                'seatLimit': seatLimit,
                'filledSeats': filledSeats,
                'remainingSeats': remainingSeats > 0 ? remainingSeats : 0,
              };
            })
            .where((night) {
               // Filter out expired events
               if (night['rawDate'] != null) {
                 try {
                   final dt = DateTime.parse(night['rawDate']).toLocal();
                   // Keep if the event date is in the future or today
                   if (dt.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
                     return false;
                   }
                 } catch (_) {}
               }
               return true;
            })
            .toList();
          } else {
            _upcomingNights = [];
          }

          if (!_hasShownAdPopup) {
            _hasShownAdPopup = true;
            final popupAds = [...dynamicPartyAds];
            if (popupAds.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  AdAnnouncementDialog.showList(context, popupAds);
                }
              });
            }
          }

          final rawPartyPlans = results[3] as List<Map<String, dynamic>>;
          final rawStrangersMeet = results[6] as List<Map<String, dynamic>>;

          List<Map<String, dynamic>> combinedPosts = [];

          if (rawPartyPlans.isNotEmpty) {
            combinedPosts.addAll(
              rawPartyPlans.map((plan) {
                final user =
                    (plan['user'] ?? plan['creator'] ?? plan['host'])
                        as Map<String, dynamic>? ??
                    {};
                final venue =
                    (plan['venue'] ?? plan['venueMap'])
                        as Map<String, dynamic>? ??
                    {};

                String timeStr =
                    plan['planDateTime'] ?? plan['createdAt'] ?? '';
                if (timeStr.isNotEmpty) {
                  try {
                    final dt = DateTime.parse(timeStr).toLocal();
                    timeStr = DateFormat('MMM dd, hh:mm a').format(dt);
                  } catch (_) {}
                }

                final targetVenueId =
                    (plan['venueId'] ?? venue['id'])?.toString() ?? '';
                final bool isSecretVenuePost = venue['isSecret'] == true;

                // Resolve venue cover image from multiple possible fields
                dynamic rawImg =
                    venue['coverImageUrl'] ??
                    venue['imageUrl'] ??
                    venue['image'] ??
                    (venue['coverImage'] is Map
                        ? venue['coverImage']['url'] ??
                              venue['coverImage']['filePath']
                        : null) ??
                    (venue['images'] is List &&
                            (venue['images'] as List).isNotEmpty
                        ? ((venue['images'] as List).first is Map
                              ? (venue['images'] as List).first['url'] ??
                                    (venue['images'] as List).first['filePath']
                              : (venue['images'] as List).first)
                        : null);

                // A secret-venue post still carries the venue's real id (the
                // backend needs it for e.g. distance/city grouping) even
                // though name/image are masked — never use that id to look
                // up the real cover photo from the full venue directory, or
                // the masking is trivially bypassed.
                if ((rawImg == null ||
                        rawImg.toString().isEmpty ||
                        rawImg.toString().startsWith('Instance of')) &&
                    targetVenueId.isNotEmpty &&
                    !isSecretVenuePost) {
                  try {
                    final matchedV = _allVenues.firstWhere(
                      (v) => v.id == targetVenueId,
                    );
                    rawImg = matchedV.imageUrl;
                  } catch (_) {}
                }

                final String? photoUrl =
                    (user['profilePhotoUrl'] ??
                            user['photoUrl'] ??
                            user['profilePhoto'] ??
                            user['image'])
                        ?.toString();

                return {
                  'id': plan['id'],
                  'type': 'party_plan',
                  'firstName': user['firstName'] ?? 'User',
                  'lastName': user['lastName'] ?? '',
                  'profilePhotoUrl': photoUrl,
                  'profilePhoto': photoUrl,
                  'city': venue['city'] ?? user['city'] ?? 'Unknown',
                  'bio': user['bio'] ?? '',
                  'gender': user['gender'] ?? 'Unknown',
                  'venue': venue['name'] ?? 'Venue',
                  'venueId': targetVenueId,
                  'content': plan['message'] ?? '',
                  'time': timeStr,
                  'coverImageUrl':
                      (rawImg != null &&
                          !rawImg.toString().startsWith('Instance of'))
                      ? rawImg.toString()
                      : '',
                  'userId': user['id'] ?? plan['userId'],
                  'user': user,
                  'venueMap': venue,
                  'createdAt': plan['createdAt'],
                };
              }),
            );
          }

          if (rawStrangersMeet.isNotEmpty) {
            final now = DateTime.now();
            final activeStrangersMeets = rawStrangersMeet.where((meet) {
              final status = meet['status']?.toString().toLowerCase();
              final payStatus = (meet['paymentStatus'] ?? meet['payment_status'])?.toString().toLowerCase();

              // Require approved status AND paid host deposit
              if (status != 'approved') return false;
              if (payStatus != 'paid') return false;

              final dtStr = (meet['eventDateTime'] ?? meet['event_date_time'])?.toString();
              if (dtStr != null && dtStr.isNotEmpty) {
                final dt = DateTime.tryParse(dtStr)?.toLocal();
                if (dt != null) {
                  final eventEndTime = dt.add(const Duration(hours: 6));
                  if (eventEndTime.isBefore(now)) {
                    return false;
                  }
                }
              }
              return true;
            }).toList();

            combinedPosts.addAll(
              activeStrangersMeets.map((meet) {
                final user =
                    (meet['user'] ?? meet['host']) as Map<String, dynamic>? ??
                    {};
                final venue =
                    (meet['venue'] ?? meet['venueMap'])
                        as Map<String, dynamic>? ??
                    {};

                String timeStr =
                    meet['eventDateTime'] ?? meet['createdAt'] ?? '';
                if (timeStr.isNotEmpty) {
                  try {
                    final dt = DateTime.parse(timeStr).toLocal();
                    timeStr = DateFormat('MMM dd, hh:mm a').format(dt);
                  } catch (_) {}
                }

                final String extractedVenueId =
                    (meet['venueId'] ??
                            venue['id'] ??
                            (meet['venue'] is Map
                                ? meet['venue']['id']
                                : null) ??
                            (meet['venue'] is String ? meet['venue'] : ''))
                        ?.toString() ??
                    '';

                // Resolve venue cover image from multiple possible fields
                dynamic rawImg =
                    venue['coverImageUrl'] ??
                    venue['imageUrl'] ??
                    venue['image'] ??
                    meet['coverImageUrl'] ??
                    meet['venueImageUrl'] ??
                    meet['venueImage'] ??
                    meet['bannerUrl'] ??
                    meet['bannerImage'] ??
                    (venue['coverImage'] is Map
                        ? venue['coverImage']['url'] ??
                              venue['coverImage']['filePath']
                        : null) ??
                    (venue['images'] is List &&
                            (venue['images'] as List).isNotEmpty
                        ? ((venue['images'] as List).first is Map
                              ? (venue['images'] as List).first['url'] ??
                                    (venue['images'] as List).first['filePath']
                              : (venue['images'] as List).first)
                        : null);

                if ((rawImg == null ||
                        rawImg.toString().isEmpty ||
                        rawImg.toString().startsWith('Instance of')) &&
                    extractedVenueId.isNotEmpty) {
                  try {
                    final matchedV = _allVenues.firstWhere(
                      (v) => v.id == extractedVenueId,
                    );
                    rawImg = matchedV.imageUrl;
                  } catch (_) {}
                }

                final String? photoUrl =
                    (user['photoUrl'] ??
                            user['profilePhotoUrl'] ??
                            user['profilePhoto'] ??
                            user['image'])
                        ?.toString();

                return {
                  'id': meet['id'],
                  'type': 'strangers_meet',
                  'firstName': user['firstName'] ?? 'User',
                  'lastName': user['lastName'] ?? '',
                  'profilePhotoUrl': photoUrl,
                  'profilePhoto': photoUrl,
                  'city': venue['city'] ?? user['city'] ?? 'Unknown',
                  'bio': user['bio'] ?? '',
                  'gender': user['gender'] ?? 'Unknown',
                  'venue':
                      venue['name'] ??
                      meet['venueName'] ??
                      (meet['venue'] is String ? meet['venue'] : null) ??
                      'Venue',
                  'venueId': extractedVenueId,
                  'venueMap': venue,
                  'content': meet['tagline'] ?? meet['subject'] ?? '',
                  'time': timeStr,
                  'coverImageUrl':
                      (rawImg != null &&
                          !rawImg.toString().startsWith('Instance of'))
                      ? rawImg.toString()
                      : '',
                  'userId': user['id'] ?? meet['userId'],
                  'user': user,
                  'createdAt': meet['createdAt'],
                };
              }),
            );
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
          final fallbackCities = ['Pune'];
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
            ApiService.setSelectedCity(_currentUser?.city ?? 'Pune');
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
        _fetchGoogleRatingsForVenues(_allVenues);
        _prefetchRoadDistances(_allVenues);
      }
    } catch (e) {
      debugPrint('Error in _loadVenues: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await _loadVenues();
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
      liveVenues = liveVenues.where((v) {
        return v.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            v.city.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // Sort by distance if enabled and position is available
    if (_sortByDistance && _currentPosition != null) {
      liveVenues.sort((a, b) {
        if (a.latitude == null || a.longitude == null) return 1;
        if (b.latitude == null || b.longitude == null) return -1;
        double distA = GooglePlacesService.calculateRoadDistanceInMeters(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          a.latitude!,
          a.longitude!,
        );
        double distB = GooglePlacesService.calculateRoadDistanceInMeters(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          b.latitude!,
          b.longitude!,
        );
        return distA.compareTo(distB);
      });
    }

    return liveVenues;
  }

  List<Map<String, dynamic>> get _filteredPartyPlans {
    var plans = _partyPlans;
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
      final String targetCity = ApiService.selectedCity!.toLowerCase().trim();
      users = users.where((u) {
        final String? rawCity =
            u['city']?.toString() ??
            (u['profile'] is Map ? u['profile']['city']?.toString() : null);
        // Include users with no city set (they may just not have filled it in)
        if (rawCity == null || rawCity.isEmpty) return true;
        final String userCity = rawCity.toLowerCase().trim();
        return userCity.contains(targetCity) || targetCity.contains(userCity);
      }).toList();
    }
    return users;
  }

  int _calculateProfileCompletion() {
    if (_currentUser == null) return 0;
    return _currentUser!.profileCompletionPercentage;
  }

  Widget _buildProfileCompletionCard() {
    if (_isProfileCardDismissed || _currentUser == null) {
      return const SizedBox.shrink();
    }

    final int percentage = _calculateProfileCompletion();

    // If 100% complete, auto-disappear
    if (percentage >= 100) {
      return const SizedBox.shrink();
    }

    final missingFields = _currentUser!.incompleteFields;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            LunaraTheme.electricViolet.withValues(alpha: 0.12),
            LunaraTheme.cyberCyan.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      color: LunaraTheme.electricViolet,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Profile Completion',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        '$percentage% Completed',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: LunaraTheme.electricViolet,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                onPressed: () {
                  setState(() {
                    _isProfileCardDismissed = true;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percentage / 100.0,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(
                LunaraTheme.electricViolet,
              ),
            ),
          ),
          if (missingFields.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Details to fill:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: missingFields.map((field) {
                return GestureDetector(
                  onTap: () {
                    if (_currentUser != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              EditProfileScreen(user: _currentUser!),
                        ),
                      ).then((_) => _loadVenues());
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: LunaraTheme.electricViolet.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.add_circle_outline_rounded,
                          size: 13,
                          color: LunaraTheme.electricViolet,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          field,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: LunaraTheme.electricViolet,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: () {
                if (_currentUser != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          EditProfileScreen(user: _currentUser!),
                    ),
                  ).then((_) => _loadVenues());
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfileScreen(),
                    ),
                  ).then((_) => _loadVenues());
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'COMPLETE PROFILE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
          RefreshIndicator(
            color: LunaraTheme.electricViolet,
            backgroundColor: Colors.white,
            edgeOffset: fixedTopPadding,
            onRefresh: () async {
              await _loadVenues();
            },
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.only(top: fixedTopPadding + 10, bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 0. Profile Completion Banner
                  _buildProfileCompletionCard(),
                  const SizedBox(height: 12),

                  // 1. Ads Carousel
                  Builder(
                    builder: (context) {
                      final double screenWidth = MediaQuery.of(context).size.width;
                      final double horizontalPadding = screenWidth >= 600 ? 10.0 : 20.0;
                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                        child: _buildAdBanner(),
                      );
                    },
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
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
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
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () async {
                                  if (_currentPosition == null) {
                                    await _determinePosition(
                                      requestIfNeeded: true,
                                      showLoader: true,
                                    );
                                    if (_currentPosition != null) {
                                      setState(() {
                                        _sortByDistance = true;
                                      });
                                    }
                                  } else {
                                    setState(() {
                                      _sortByDistance = !_sortByDistance;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _sortByDistance
                                        ? LunaraTheme.electricViolet
                                        : LunaraTheme.electricViolet.withValues(
                                            alpha: 0.1,
                                          ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _sortByDistance
                                          ? LunaraTheme.electricViolet
                                          : LunaraTheme.electricViolet
                                                .withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.my_location_rounded,
                                        color: _sortByDistance
                                            ? Colors.white
                                            : LunaraTheme.electricViolet,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'NEAR ME',
                                        style: TextStyle(
                                          color: _sortByDistance
                                              ? Colors.white
                                              : LunaraTheme.electricViolet,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    AllVenuesScreen(venues: _allVenues),
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
                  if (_filteredPartyPlans.any(
                    (p) => p['type'] == 'party_plan',
                  )) ...[
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
                              final displayFeeds = _filteredPartyPlans
                                  .where((p) => p['type'] == 'party_plan')
                                  .toList();
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
                    _buildFeedsList(
                      _filteredPartyPlans
                          .where((p) => p['type'] == 'party_plan')
                          .toList(),
                    ),
                  ],

                  if (_filteredPartyPlans.any(
                        (p) => p['type'] == 'party_plan',
                      ) &&
                      _filteredPartyPlans.any(
                        (p) => p['type'] == 'strangers_meet',
                      ))
                    const SizedBox(height: 32),

                  // 4b. Strangers Meet
                  if (_filteredPartyPlans.any(
                    (p) => p['type'] == 'strangers_meet',
                  )) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'STRANGERS MEET',
                            style: TextStyle(
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              fontSize: 15,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              final displayFeeds = _filteredPartyPlans
                                  .where((p) => p['type'] == 'strangers_meet')
                                  .toList();
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
                    _buildFeedsList(
                      _filteredPartyPlans
                          .where((p) => p['type'] == 'strangers_meet')
                          .toList(),
                    ),
                  ],

                  // 5. Top Profiles
                  _buildTopProfiles(),
                ],
              ),
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
                        LunaraPulsingLogoButton(
                          size: 34,
                          iconPadding: 4,
                          borderWidth: 1.5,
                          onTap: _refreshData,
                        ),
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
                            tier: _currentUser?.subscriptionTier,
                            onUpdated: () => _loadVenues(),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LunaraWalletScreen(),
                              ),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            height: 36,
                            width: 36,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.account_balance_wallet_rounded,
                              color: LunaraTheme.electricViolet,
                              size: 22,
                            ),
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
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isTablet = screenWidth >= 600;
    final double bannerHeight = isTablet ? 230.0 : 180.0;

    if (_activeAds.isEmpty) {
      return Container(
        margin: EdgeInsets.zero,
        height: bannerHeight,
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
      height: bannerHeight,
      margin: EdgeInsets.zero,
      child: Stack(
        children: [
          CarouselSlider.builder(
            itemCount: _activeAds.length,
            options: CarouselOptions(
              height: bannerHeight,
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
                    final venueMap = matchingVenue.toMap();
                    if (_googleRatings.containsKey(matchingVenue.id)) {
                      venueMap['googleRating'] =
                          _googleRatings[matchingVenue.id]?['rating'];
                      venueMap['googleRatingCount'] =
                          _googleRatings[matchingVenue
                              .id]?['user_ratings_total'];
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VenueDetailScreen(venue: venueMap),
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
                    final venueId = ad['venueId'] ?? ad['venue']['id'] ?? '';
                    if (_googleRatings.containsKey(venueId)) {
                      minimalVenue['googleRating'] =
                          _googleRatings[venueId]?['rating'];
                      minimalVenue['googleRatingCount'] =
                          _googleRatings[venueId]?['user_ratings_total'];
                    }
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
                          ? Image.asset(
                              night['image']!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.purple.shade900,
                                child: const Center(
                                  child: Icon(Icons.nightlife, color: Colors.white),
                                ),
                              ),
                            )
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
      height: 385,
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
            distanceText = GooglePlacesService.formatRoadDistance(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              venue.latitude!,
              venue.longitude!,
            );
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
                onTap: () {
                  final venueMap = venue.toMap();
                  if (_googleRatings.containsKey(venue.id)) {
                    venueMap['googleRating'] =
                        _googleRatings[venue.id]?['rating'];
                    venueMap['googleRatingCount'] =
                        _googleRatings[venue.id]?['user_ratings_total'];
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VenueDetailScreen(venue: venueMap),
                    ),
                  );
                },
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
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      color: Colors.amber,
                                      size: 14,
                                    ),
                                    Builder(
                                      builder: (context) {
                                        final googleRatingData =
                                            _googleRatings[venue.id];
                                        final double displayRating =
                                            googleRatingData != null
                                            ? (googleRatingData['rating']
                                                          as num?)
                                                      ?.toDouble() ??
                                                  venue.averageRating
                                            : venue.averageRating;
                                        final displayRatingStr =
                                            displayRating > 0.0
                                            ? displayRating.toStringAsFixed(1)
                                            : '4.5';
                                        return Text(
                                          ' $displayRatingStr',
                                          style: const TextStyle(
                                            color: Colors.black87,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    Image.asset(
                                      'assets/images/google_logo.png',
                                      height: 10,
                                      errorBuilder: (_, _, _) => const Text(
                                        'G',
                                        style: TextStyle(
                                          color: Colors.amber,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
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
                              if (distanceText != null) ...[
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
                              ] else ...[
                                InkWell(
                                  onTap: () async {
                                    await _determinePosition(
                                      requestIfNeeded: true,
                                      showLoader: true,
                                    );
                                    if (_currentPosition != null) {
                                      setState(() {
                                        _sortByDistance = true;
                                      });
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: LunaraTheme.electricViolet
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.my_location_rounded,
                                          color: LunaraTheme.electricViolet,
                                          size: 11,
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'DISTANCE',
                                          style: TextStyle(
                                            color: LunaraTheme.electricViolet,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => BookingProcessScreen(
                                        venue: venue.toMap(),
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LunaraTheme.purpleGradient,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: LunaraTheme.electricViolet
                                            .withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Text(
                                    'BOOK NOW',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
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
      height: 385,
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
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: 28,
                            width: 90,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ],
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

  Widget _buildFeedsList(List<Map<String, dynamic>> displayFeeds) {
    return SizedBox(
      height: 260,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: displayFeeds.length,
        itemBuilder: (context, index) {
          final feed = displayFeeds[index];

          // Handle nested user object or flat structure
          final userObj = feed['user'] is Map ? feed['user'] as Map : feed;
          final String? userPhotoRaw =
              (userObj['profilePhotoUrl'] ??
                      userObj['photoUrl'] ??
                      userObj['profilePhoto'] ??
                      feed['profilePhotoUrl'] ??
                      feed['profilePhoto'])
                  ?.toString();
          final String? avatarUrl = ApiService.formatImageUrl(userPhotoRaw);

          // Resolve venue name & ID
          String venueName = '';
          if (feed['venue'] is Map) {
            venueName = (feed['venue'] as Map)['name']?.toString() ?? '';
          } else {
            venueName = feed['venue']?.toString() ?? '';
          }
          final String targetVenueId =
              (feed['venueId'] ??
                      (feed['venue'] is Map ? feed['venue']['id'] : null))
                  ?.toString() ??
              '';

          // Try to get cover image from all possible fields and venue lookup
          String? rawCover =
              feed['coverImageUrl']?.toString().isNotEmpty == true
              ? feed['coverImageUrl']
              : (feed['venueImageUrl'] ??
                    feed['venueImage'] ??
                    feed['bannerUrl'] ??
                    feed['bannerImage']);

          if ((rawCover == null || rawCover.toString().isEmpty) &&
              feed['venue'] is Map) {
            final vMap = feed['venue'] as Map;
            if (vMap['images'] is List && (vMap['images'] as List).isNotEmpty) {
              final first = (vMap['images'] as List).first;
              rawCover = first is Map
                  ? (first['url'] ?? first['imageUrl'] ?? first['filePath'])
                  : first?.toString();
            }
            rawCover ??=
                (vMap['imageUrl'] ??
                        vMap['coverImage'] ??
                        vMap['photoUrl'] ??
                        vMap['image'])
                    ?.toString();
          }

          // Search in _allVenues by ID first, then by Name
          if (rawCover == null || rawCover.toString().isEmpty) {
            Venue? matchedVenue;
            if (targetVenueId.isNotEmpty) {
              try {
                matchedVenue = _allVenues.firstWhere(
                  (v) => v.id == targetVenueId,
                );
              } catch (_) {}
            }
            if (matchedVenue == null && venueName.isNotEmpty) {
              final vNameLower = venueName.toLowerCase().trim();
              for (final v in _allVenues) {
                final nameLower = v.name.toLowerCase().trim();
                if (nameLower == vNameLower ||
                    nameLower.contains(vNameLower) ||
                    vNameLower.contains(nameLower)) {
                  matchedVenue = v;
                  break;
                }
              }
            }

            if (matchedVenue != null) {
              rawCover = matchedVenue.imageUrl;
              if ((rawCover == null || rawCover.isEmpty) &&
                  matchedVenue.images != null &&
                  matchedVenue.images!.isNotEmpty) {
                final firstImg = matchedVenue.images!.first;
                if (firstImg is Map) {
                  rawCover =
                      (firstImg['url'] ??
                              firstImg['imageUrl'] ??
                              firstImg['filePath'])
                          ?.toString();
                } else if (firstImg != null) {
                  try {
                    rawCover =
                        ((firstImg as dynamic).url ??
                                (firstImg as dynamic).filePath ??
                                firstImg.toString())
                            ?.toString();
                  } catch (_) {
                    rawCover = firstImg.toString();
                  }
                }
              }
            }
          }

          // Fall back to host/user avatar URL if venue image not found
          if (rawCover == null || rawCover.toString().isEmpty) {
            rawCover = userPhotoRaw;
          }

          // Fall back to first available venue image in _allVenues if still empty
          if (rawCover == null || rawCover.toString().isEmpty) {
            for (final v in _allVenues) {
              if (v.imageUrl != null && v.imageUrl!.isNotEmpty) {
                rawCover = v.imageUrl;
                break;
              }
            }
          }

          if (rawCover != null && rawCover.startsWith('Instance of')) {
            rawCover = null;
          }

          final String? coverImageUrl =
              ApiService.formatImageUrl(rawCover?.toString()) ?? avatarUrl;

          final bool isSecretVenue = feed['venueMap'] is Map &&
              (feed['venueMap'] as Map)['isSecret'] == true;

          return RepaintBoundary(
            child: Container(
              width: 240,
              height: 240,
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7F00FF).withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1.2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: isSecretVenue
                          ? Image.asset(
                              'assets/images/secretimag.png',
                              fit: BoxFit.cover,
                              colorBlendMode: BlendMode.darken,
                              color: Colors.black.withValues(alpha: 0.6),
                            )
                          : LunaraNetworkImage(
                              imageUrl: coverImageUrl,
                              fit: BoxFit.cover,
                              colorFilter: ColorFilter.mode(
                                Colors.black.withValues(alpha: 0.6),
                                BlendMode.darken,
                              ),
                            ),
                    ),
                    Positioned.fill(
                      child: InkWell(
                        onTap: () {
                          final venue = _allVenues.firstWhere(
                            (v) =>
                                v.name.toLowerCase() == venueName.toLowerCase(),
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
                              builder: (_) => PostDetailScreen(
                                post: feed,
                                venue: venue.toMap(),
                              ),
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
                                  LunaraProfileImage(
                                    userData: userObj,
                                    radius: 18,
                                  ),

                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          (userObj['firstName'] != null &&
                                                  userObj['lastName'] != null)
                                              ? '${userObj['firstName']} ${userObj['lastName']}'
                                              : (userObj['userName'] ??
                                                    'Lunara User'),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          feed['time'] ?? '',
                                          style: const TextStyle(
                                            color: Colors.white70,
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
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.4,
                                    color: Colors.white,
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
                                        color: Colors.amber.withValues(
                                          alpha: 0.25,
                                        ),
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
                                        color: Colors.black.withValues(
                                          alpha: 0.35,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.2,
                                          ),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isSecretVenue ? Icons.lock_rounded : Icons.star_rounded,
                                            color: isSecretVenue ? Colors.white70 : Colors.amber,
                                            size: 12,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              venueName.toUpperCase(),
                                              style: const TextStyle(
                                                color: Colors.white,
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
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileMetricChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 9.5),
          const SizedBox(width: 2.5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProfiles() {
    // Robust null check and filter out the current user + apply gender filter
    final List<dynamic> users = _filteredUsers.where((u) {
      final isNotMe = u['id']?.toString() != _currentUser?.id;
      return isNotMe;
    }).toList();

    // Sort by rankScore (Boost + Superlikes + Likes + Points)
    users.sort((a, b) {
      final scoreA = (a['rankScore'] is num
          ? a['rankScore']
          : double.tryParse(a['rankScore']?.toString() ?? '0') ?? 0);
      final scoreB = (b['rankScore'] is num
          ? b['rankScore']
          : double.tryParse(b['rankScore']?.toString() ?? '0') ?? 0);
      return scoreB.compareTo(scoreA);
    });

    final List<dynamic> allUsers = _filteredUsers.where((u) {
      return u['id']?.toString() != _currentUser?.id;
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
                        builder: (_) => AllUsersScreen(users: allUsers),
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
            height: 122,
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

                final int likes =
                    (user['likesCount'] is num
                            ? user['likesCount']
                            : int.tryParse(
                                    user['likesCount']?.toString() ?? '0',
                                  ) ??
                                  0)
                        .toInt();
                final int superLikes =
                    (user['superLikesCount'] is num
                            ? user['superLikesCount']
                            : int.tryParse(
                                    user['superLikesCount']?.toString() ?? '0',
                                  ) ??
                                  0)
                        .toInt();

                final dynamic bRaw =
                    user['boostCount'] ?? user['boostsRemaining'];
                final int boosts =
                    (bRaw is num
                            ? bRaw
                            : int.tryParse(bRaw?.toString() ?? '0') ?? 0)
                        .toInt();
                final bool isBoosted = user['isBoosted'] == true || boosts > 0;

                return GestureDetector(
                  onTap: () {
                    User? resolvedUser;
                    try {
                      resolvedUser = User.fromJson(
                        Map<String, dynamic>.from(user),
                      );
                    } catch (_) {}
                    final List<User> resolvedAllProfiles = [];
                    for (var u in users) {
                      try {
                        resolvedAllProfiles.add(
                          User.fromJson(Map<String, dynamic>.from(u)),
                        );
                      } catch (_) {}
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(
                          user: resolvedUser,
                          allProfiles: resolvedAllProfiles,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 175,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LunaraTheme.cardGradient,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isBoosted
                            ? Colors.amber.withValues(alpha: 0.6)
                            : const Color(0xFF7F00FF).withValues(alpha: 0.08),
                        width: isBoosted ? 1.8 : 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isBoosted
                              ? Colors.amber.withValues(alpha: 0.15)
                              : const Color(0xFF7F00FF).withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            LunaraProfileImage(
                              userData: user,
                              radius: 20,
                              showGradientBorder: isBoosted,
                              isInteractive: false,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          '$name, ${22 + (index % 10)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.black,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (LunaraTheme.getPlanBadgeColor(user) != null) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.verified,
                                          color: LunaraTheme.getPlanBadgeColor(user),
                                          size: 14,
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    vibe.toString(),
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: LunaraTheme.electricViolet,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // Row of Metrics: Superlikes, Likes
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            _buildProfileMetricChip(
                              Icons.star_rounded,
                              '$superLikes Super',
                              const Color(0xFF9333EA),
                            ),
                            const SizedBox(width: 8),
                            _buildProfileMetricChip(
                              Icons.favorite_rounded,
                              '$likes Likes',
                              const Color(0xFFEC4899),
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
