import 'dart:async';
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import 'booking_process_screen.dart';
import '../../widgets/venue_video_player.dart';
import '../../services/google_places_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/app_tour_service.dart';



class VenueDetailScreen extends StatefulWidget {
  final Map<String, dynamic> venue;

  const VenueDetailScreen({super.key, required this.venue});

  @override
  State<VenueDetailScreen> createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends State<VenueDetailScreen> with WidgetsBindingObserver {
  Map<String, dynamic> get venue => widget.venue;
  int _currentCarouselIndex = 0;
  double? _googleRating;
  int? _googleRatingCount;
  bool _isLoadingRating = true;
  Position? _currentPosition;

  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadGoogleRating();
    _checkLocationAndForce(requestIfNeeded: false);
    _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen((status) {
      _checkLocationAndForce(requestIfNeeded: false);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLocationAndForce(requestIfNeeded: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceStatusSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppTourService.showVenueDetailTour(context);
    });
  }

  Future<void> _checkLocationAndForce({bool requestIfNeeded = false, bool showLoader = false}) async {
    if (showLoader && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: LunaraTheme.cyberCyan),
        ),
      );
    }
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (requestIfNeeded) {
          await Geolocator.openLocationSettings();
        }
        if (showLoader && mounted) {
          Navigator.pop(context);
        }
        return;
      }

      LocationPermission permission;
      try {
        permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied && requestIfNeeded) {
          permission = await Geolocator.requestPermission();
        }
      } catch (e) {
        debugPrint('Permission check error: $e');
        permission = LocationPermission.denied;
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (showLoader && mounted) {
          Navigator.pop(context);
        }
        return;
      }

      // If location is enabled and permission is granted:
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
      if (showLoader && mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error in _checkLocationAndForce: $e');
      if (showLoader && mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _loadGoogleRating() async {
    final name = venue['name'] as String? ?? '';
    final city = venue['city'] as String? ?? '';
    if (name.isNotEmpty) {
      final result = await GooglePlacesService.fetchGoogleRating(name, city);
      if (mounted && result != null) {
        setState(() {
          _googleRating = (result['rating'] as num?)?.toDouble();
          _googleRatingCount = result['user_ratings_total'] as int?;
          _isLoadingRating = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingRating = false);
      }
    } else if (mounted) {
      setState(() => _isLoadingRating = false);
    }
  }

  Future<void> _openDirectionsMap() async {
    final double? lat = double.tryParse(venue['latitude']?.toString() ?? '');
    final double? lng = double.tryParse(venue['longitude']?.toString() ?? '');

    if (lat == null || lng == null || lat == 0.0 || lng == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venue location coordinates are not available.')),
      );
      return;
    }

    // Show a loading overlay/indicator dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: LunaraTheme.cyberCyan),
      ),
    );

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!serviceEnabled) {
        Navigator.pop(context); // Dismiss dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services to get directions.')),
        );
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        Navigator.pop(context); // Dismiss dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required for directions.')),
        );
        if (permission == LocationPermission.deniedForever) {
          await Geolocator.openAppSettings();
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      Navigator.pop(context); // Dismiss dialog

      final Uri googleMapsUrl = Uri.parse(
        "https://www.google.com/maps/dir/?api=1&origin=${position.latitude},${position.longitude}&destination=$lat,$lng&travelmode=driving"
      );

      final bool canLaunch = await canLaunchUrl(googleMapsUrl);
      if (!mounted) return;
      if (canLaunch) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch Google Maps.')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss dialog
        debugPrint('Error launching maps: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting directions: $e')),
        );
      }
    }
  }



  String _formatTime(String? timeStr) {
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
    } catch (e) {
      debugPrint('Error formatting time: $e');
    }
    return timeStr;
  }

  String _formatDaysOpen(dynamic days) {
    if (days == null) return '';
    if (days is List) {
      if (days.isEmpty) return '';
      if (days.length == 7) return 'EVERYDAY';
      return days.join(', ').toUpperCase();
    }
    return days.toString().toUpperCase();
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

  static Widget _sectionHeading(String title) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF5D00B8).withValues(alpha: 0.4),
                  Colors.transparent,
                ],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDiscountBadge(double discount) {
    final discountStr = discount % 1 == 0 ? discount.toStringAsFixed(0) : discount.toStringAsFixed(1);
    
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF5D00B8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10.5),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0xFFFFFFFF), Color(0xFFF3EBFF)],
                    center: Alignment.center,
                    radius: 0.8,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$discountStr%',
                    style: const TextStyle(
                      color: Color(0xFF5D00B8),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 3),
              color: const Color(0xFF5D00B8),
              child: const Center(
                child: Text(
                  'DISCOUNT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 7.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountBanner(double discount) {
    final discountStr = discount % 1 == 0 ? discount.toStringAsFixed(0) : discount.toStringAsFixed(1);
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LunaraTheme.purpleGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_offer_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$discountStr% OFF YOUR BOOKING',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Exclusive discount applied when you book now.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double? discountVal = double.tryParse(venue['discountPercentage']?.toString() ?? '');
    final bool hasDiscount = discountVal != null && discountVal > 0;

    final List<Map<String, dynamic>> images = [];
    if (venue['images'] != null) {
      for (var item in (venue['images'] as List)) {
        if (item is Map) {
          images.add(Map<String, dynamic>.from(item));
        } else if (item is String) {
          images.add({'url': item, 'type': 'interior'});
        }
      }
    }

    final interiorImages = images.where((img) => img['type'] == 'interior').map((img) => img['url'] as String).toList();
    final videoMedia = images.where((img) => img['type'] == 'video').map((img) => img['url'] as String).toList();
    final menuImages = images.where((img) => img['type'] == 'menu').map((img) => img['url'] as String).toList();
    final foodMenuImages = images.where((img) => img['type'] == 'foodMenu').map((img) => img['url'] as String).toList();
    final barMenuImages = images.where((img) => img['type'] == 'barMenu').map((img) => img['url'] as String).toList();
    final beverageMenuImages = images.where((img) => img['type'] == 'beverageMenu').map((img) => img['url'] as String).toList();
    final partyPackagesImages = images.where((img) => img['type'] == 'partyPackages').map((img) => img['url'] as String).toList();

    if (venue['videoUrl'] != null && (venue['videoUrl'] as String).trim().isNotEmpty) {
      final vUrl = venue['videoUrl'] as String;
      if (!videoMedia.contains(vUrl)) {
        videoMedia.insert(0, vUrl);
      }
    }

    final Map<String, List<String>> menus = {};
    if (foodMenuImages.isNotEmpty) menus['FOOD MENU'] = foodMenuImages;
    if (barMenuImages.isNotEmpty) menus['BAR MENU'] = barMenuImages;
    if (beverageMenuImages.isNotEmpty) menus['BEVERAGE MENU'] = beverageMenuImages;
    if (partyPackagesImages.isNotEmpty) menus['PARTY PACKAGES'] = partyPackagesImages;
    if (menuImages.isNotEmpty) menus['MENU GALLERY'] = menuImages;

    final latVal = venue['latitude'];
    final lngVal = venue['longitude'];
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
      backgroundColor: Colors.white,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: screenWidth * 0.9,
            pinned: true,
            stretch: true,
            backgroundColor: Colors.white,
            automaticallyImplyLeading: false,
            leadingWidth: 0,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildMediaCarousel(),
                    // Gradient Overlay for Text Legibility
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.3),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.1),
                              Colors.black.withValues(alpha: 0.95),
                            ],
                            stops: const [0.0, 0.2, 0.55, 1.0],
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
                          if (hasDiscount)
                            _buildDiscountBadge(discountVal),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      venue['name'].toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    if ((venue['tagline']).toString().trim().isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        (venue['tagline']).toString().toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.location_on_rounded, color: Colors.white, size: 14),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '${venue['city']} • ${venue['area'] ?? venue['addressLine1']}'.toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.5,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (venue['openingTime'] != null || venue['closingTime'] != null || venue['daysOpen'] != null) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 12,
                                        runSpacing: 6,
                                        children: [
                                          if (venue['openingTime'] != null || venue['closingTime'] != null)
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.access_time_rounded, color: Colors.white, size: 14),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    '${_formatTime(venue['openingTime'])} - ${_formatTime(venue['closingTime'])}'.toUpperCase(),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          if (venue['daysOpen'] != null)
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.calendar_today_rounded, color: Colors.white, size: 12),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    _formatDaysOpen(venue['daysOpen']),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ],
                                    if (distanceText.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.directions_run_rounded, color: Colors.white, size: 14),
                                          const SizedBox(width: 4),
                                          Text(
                                            distanceText.toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 6),
                                      GestureDetector(
                                        onTap: () => _checkLocationAndForce(requestIfNeeded: true, showLoader: true),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: Colors.white.withValues(alpha: 0.25),
                                              width: 1,
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.my_location_rounded, color: Colors.white, size: 12),
                                              SizedBox(width: 6),
                                              Text(
                                                'GET DISTANCE',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (venue['coverChargeMale'] != null || venue['coverChargeFemale'] != null) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 10,
                                        runSpacing: 6,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.man_rounded, color: Colors.white, size: 16),
                                              const SizedBox(width: 2),
                                              Text(
                                                '₹${venue['coverChargeMale'] ?? '-'}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.woman_rounded, color: Colors.white, size: 16),
                                              const SizedBox(width: 2),
                                              Text(
                                                '₹${venue['coverChargeFemale'] ?? '-'}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                        const SizedBox(width: 4),
                                        if (_isLoadingRating)
                                          const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        else ...[
                                          Text(
                                            '${_googleRating ?? venue['averageRating'] ?? '4.5'}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          if (_googleRatingCount != null) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              '($_googleRatingCount)',
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.7),
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ],
                                        const SizedBox(width: 4),
                                        Image.asset('assets/images/google_logo.png', height: 12, errorBuilder: (_, _, _) => const Text('G', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  InkWell(
                                    key: AppTourService.venueDirectionsKey,
                                    onTap: _openDirectionsMap,
                                    customBorder: const CircleBorder(),
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.5),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                      ),
                                      child: const Icon(
                                        Icons.directions_rounded,
                                        color: LunaraTheme.cyberCyan,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ],
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
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LunaraActionButton(
                    key: AppTourService.venueBookNowKey,
                    text: 'BOOK NOW',
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => BookingProcessScreen(venue: venue)));
                    },
                  ),
                  const SizedBox(height: 24),
                  if (hasDiscount) ...[
                    _buildDiscountBanner(discountVal),
                    const SizedBox(height: 24),
                  ],
                  if (interiorImages.isNotEmpty) ...[
                    _buildGallerySection('INTERIOR GALLERY', interiorImages),
                    const SizedBox(height: 32),
                  ],
                  if (menus.isNotEmpty) ...[
                    MenuGallerySection(menus: menus),
                    const SizedBox(height: 32),
                  ],
                  if (videoMedia.isNotEmpty) ...[
                    _buildGallerySection('VIDEO GALLERY', videoMedia),
                    const SizedBox(height: 32),
                  ],
                  _sectionHeading('ABOUT'),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey[200]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      venue['description'] ?? 'No description available',
                      style: const TextStyle(height: 1.6, color: Colors.black87, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _sectionHeading('AMENITIES'),
                  const SizedBox(height: 16),
                  _buildAmenities(),
                  const SizedBox(height: 40),
                  LunaraActionButton(
                    text: 'BOOK NOW',
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => BookingProcessScreen(venue: venue)));
                    },
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmenities() {
    final Map<String, dynamic>? amenitiesData = venue['amenities'];
    
    if (amenitiesData == null) {
      return const Text('Amenities data not available', style: TextStyle(color: Colors.grey));
    }

    final List<Map<String, dynamic>> allPossibleAmenities = [
      {'key': 'hasAC', 'label': 'AC', 'icon': Icons.ac_unit},
      {'key': 'hasDJ', 'label': 'Resident DJ', 'icon': Icons.album_rounded},
      {'key': 'hasPool', 'label': 'Pool', 'icon': Icons.pool_rounded},
      {'key': 'hasWifi', 'label': 'Free WiFi', 'icon': Icons.wifi_rounded},
      {'key': 'hasParking', 'label': 'Parking', 'icon': Icons.local_parking_rounded},
      {'key': 'hasRooftop', 'label': 'Rooftop', 'icon': Icons.layers_rounded},
      {'key': 'hasLiveMusic', 'label': 'Live Music', 'icon': Icons.music_note_rounded},
      {'key': 'hasDanceFloor', 'label': 'Dance Floor', 'icon': Icons.accessibility_new_rounded},
      {'key': 'hasHappyHours', 'label': 'Happy Hours', 'icon': Icons.celebration_rounded},
      {'key': 'hasVIPSection', 'label': 'VIP Section', 'icon': Icons.stars_rounded},
      {'key': 'hasSmokingZone', 'label': 'Smoking Zone', 'icon': Icons.smoking_rooms_rounded},
      {'key': 'hasValetParking', 'label': 'Valet Parking', 'icon': Icons.directions_car_rounded},
      {'key': 'hasBottleService', 'label': 'Bottle Service', 'icon': Icons.wine_bar_rounded},
      {'key': 'hasPrivateDining', 'label': 'Private Dining', 'icon': Icons.restaurant_rounded},
      {'key': 'hasOutdoorSeating', 'label': 'Outdoor Seating', 'icon': Icons.deck_rounded},
    ];

    final List<Map<String, dynamic>> availableAmenities = allPossibleAmenities
        .where((a) => amenitiesData[a['key']] == true)
        .toList();

    if (availableAmenities.isEmpty) {
      return const Text('No specific amenities listed', style: TextStyle(color: Colors.grey));
    }

    // Show max 16 amenities (4x4 grid)
    final displayAmenities = availableAmenities.take(16).toList();
    // Calculate rows needed (max 4 rows)
    final rowCount = ((displayAmenities.length + 3) ~/ 4).clamp(1, 4);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(rowCount, (rowIndex) {
          final startIndex = rowIndex * 4;
          final endIndex = (startIndex + 4).clamp(0, displayAmenities.length);
          final rowItems = displayAmenities.sublist(startIndex, endIndex);

          return Padding(
            padding: EdgeInsets.only(bottom: rowIndex < rowCount - 1 ? 12 : 0),
            child: Row(
              children: List.generate(4, (colIndex) {
                if (colIndex >= rowItems.length) {
                  return const Expanded(child: SizedBox());
                }
                final a = rowItems[colIndex];
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: LunaraTheme.electricViolet.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            a['icon'] as IconData,
                            color: LunaraTheme.electricViolet,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (a['label'] as String).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.4,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }

  bool _isVideo(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('.mp4') ||
        lowerUrl.contains('.mov') ||
        lowerUrl.contains('.avi') ||
        lowerUrl.contains('.wmv') ||
        lowerUrl.contains('.webm') ||
        lowerUrl.contains('.m3u8') ||
        lowerUrl.contains('video') ||
        lowerUrl.contains('stream');
  }



  Widget _buildGallerySection(String title, List<String> urls) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(title),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: urls.length,
          itemBuilder: (context, index) {
            final url = urls[index];
            final isVideo = _isVideo(url);
            return GestureDetector(
              onTap: () => _showFullScreenGallery(context, urls, index),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    isVideo 
                      ? Container(
                          color: Colors.black87,
                          child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 30),
                        )
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: Colors.grey[100],
                            child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
                          ),
                        ),
                    if (isVideo)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _showFullScreenGallery(BuildContext context, List<String> urls, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenGalleryViewer(
          urls: urls,
          initialIndex: initialIndex,
          isVideo: _isVideo,
        ),
      ),
    );
  }

  Widget _buildMediaCarousel() {
    final List<String> mediaUrls = [];
    // Always put the video FIRST so it is shown prominently
    // if (venue['videoUrl'] != null &&
    //     (venue['videoUrl'] as String).trim().isNotEmpty) {
    //   mediaUrls.add(venue['videoUrl'] as String);
    // }

    // Show only the single cover image
    if (venue['image'] != null && (venue['image'] as String).trim().isNotEmpty) {
      mediaUrls.add(venue['image'] as String);
    }

    if (mediaUrls.isEmpty) {
      return Container(color: Colors.grey[200]);
    }

    if (mediaUrls.length == 1) {
      return _buildMediaItem(mediaUrls.first);
    }

    // Disable autoPlay so the carousel doesn't skip past a playing video
    return Stack(
      children: [
        CarouselSlider(
          options: CarouselOptions(
            height: double.infinity,
            viewportFraction: 1.0,
            enableInfiniteScroll: false,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 4),
            autoPlayAnimationDuration: const Duration(milliseconds: 1000),
            autoPlayCurve: Curves.fastOutSlowIn,
            onPageChanged: (index, reason) {
              setState(() {
                _currentCarouselIndex = index;
              });
            },
          ),
          items: mediaUrls.map((url) {
            return Builder(
              builder: (BuildContext context) {
                return SizedBox(
                  width: MediaQuery.of(context).size.width,
                  child: _buildMediaItem(url),
                );
              },
            );
          }).toList(),
        ),
        Positioned(
          bottom: 10.0,
          left: 0.0,
          right: 0.0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: mediaUrls.asMap().entries.map((entry) {
              return Container(
                width: 8.0,
                height: 8.0,
                margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white
                      .withValues(alpha: _currentCarouselIndex == entry.key ? 0.9 : 0.4),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaItem(String url) {
    final isVideo = _isVideo(url);

    if (isVideo) {
      return VenueVideoPlayer(videoUrl: url);
    } else {
      return Image.network(
        url,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey[200],
          child: const Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 48),
          ),
        ),
      );
    }
  }
}

class _FullScreenGalleryViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  final bool Function(String) isVideo;

  const _FullScreenGalleryViewer({
    required this.urls,
    required this.initialIndex,
    required this.isVideo,
  });

  @override
  State<_FullScreenGalleryViewer> createState() => _FullScreenGalleryViewerState();
}

class _FullScreenGalleryViewerState extends State<_FullScreenGalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.urls.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / $total',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Swipeable image pages
          PageView.builder(
            controller: _pageController,
            itemCount: total,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (context, index) {
              final url = widget.urls[index];
              if (widget.isVideo(url)) {
                return Center(child: VenueVideoPlayer(videoUrl: url));
              }
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                          color: LunaraTheme.electricViolet,
                        ),
                      );
                    },
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white38,
                      size: 64,
                    ),
                  ),
                ),
              );
            },
          ),
          // Left arrow
          if (_currentIndex > 0)
            Positioned(
              left: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => _goTo(_currentIndex - 1),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
          // Right arrow
          if (_currentIndex < total - 1)
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => _goTo(_currentIndex + 1),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
          // Dot indicators at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(total, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _currentIndex ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _currentIndex
                        ? LunaraTheme.electricViolet
                        : Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class MenuGallerySection extends StatelessWidget {
  final Map<String, List<String>> menus;

  const MenuGallerySection({super.key, required this.menus});

  void _openViewer(BuildContext context, String tab) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenMenuViewer(
          menus: menus,
          initialTab: tab,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = menus.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _VenueDetailScreenState._sectionHeading('MENUS'),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: tabs.map((tab) {
              final images = menus[tab]!;
              final firstImage = images.first;
              final imageCount = images.length;

              return GestureDetector(
                onTap: () => _openViewer(context, tab),
                child: Container(
                  width: 160,
                  margin: const EdgeInsets.only(right: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 3 / 4,
                          child: Image.network(
                            firstImage,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: Colors.grey[100],
                              child: const Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Colors.grey,
                                  size: 32,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.7),
                                ],
                                stops: const [0.5, 1.0],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 10,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                tab,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 0.5,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.photo_library_rounded,
                                    color: Colors.white70,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$imageCount ${imageCount == 1 ? 'page' : 'pages'}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
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
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class FullScreenMenuViewer extends StatefulWidget {
  final Map<String, List<String>> menus;
  final String initialTab;

  const FullScreenMenuViewer({
    super.key,
    required this.menus,
    required this.initialTab,
  });

  @override
  State<FullScreenMenuViewer> createState() => _FullScreenMenuViewerState();
}

class _FullScreenMenuViewerState extends State<FullScreenMenuViewer> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<String> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = widget.menus.keys.toList();
    final initialIndex = _tabs.indexOf(widget.initialTab);
    _tabController = TabController(
      length: _tabs.length,
      initialIndex: initialIndex != -1 ? initialIndex : 0,
      vsync: this,
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.label,
          indicator: BoxDecoration(
            gradient: LunaraTheme.purpleGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: List.generate(_tabs.length, (index) {
            final tab = _tabs[index];
            final isSelected = _tabController.index == index;
            return Tab(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.transparent : Colors.white12,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Text(
                  tab,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            );
          }),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((tab) {
          final images = widget.menus[tab]!;
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: images.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _FullScreenImagePage(
                          imageUrl: images[index],
                          title: '$tab — Page ${index + 1}',
                        ),
                      ),
                    );
                  },
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Image.network(
                      images[index],
                      fit: BoxFit.fitWidth,
                      width: double.infinity,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return SizedBox(
                          height: 300,
                          child: Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                              color: LunaraTheme.electricViolet,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, _, _) => Container(
                        height: 200,
                        color: Colors.grey[900],
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 48),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}

class _FullScreenImagePage extends StatelessWidget {
  final String imageUrl;
  final String title;

  const _FullScreenImagePage({required this.imageUrl, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return SizedBox(
                height: 300,
                child: Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                    color: LunaraTheme.electricViolet,
                  ),
                ),
              );
            },
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white38,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}
