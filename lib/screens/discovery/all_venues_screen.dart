import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/google_places_service.dart';
import '../../core/theme.dart';
import '../../models/venue.dart';
import 'venue_detail_screen.dart';
import 'booking_process_screen.dart';
import '../../widgets/light_map_view.dart';
import '../../services/api_service.dart';
import 'advanced_filters_screen.dart';

class AllVenuesScreen extends StatefulWidget {
  final List<Venue> venues;

  const AllVenuesScreen({super.key, required this.venues});

  @override
  State<AllVenuesScreen> createState() => _AllVenuesScreenState();
}

class _AllVenuesScreenState extends State<AllVenuesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late List<Venue> _filteredVenues;
  bool _isMapView = false;
  Position? _currentPosition;

  // Filter criteria
  Set<String> _selectedVibes = {};
  double _priceLevel = 4.0;
  double _radius = 50.0;
  String? _selectedCrowdDensity;
  String _selectedCategory = 'ALL';
  late List<String> _categories;

  @override
  void initState() {
    super.initState();
    // Initialize filtered venues with all venues
    _filteredVenues = widget.venues;
    // Apply city filter if a city is selected in ApiService
    if (ApiService.selectedCity != null) {
      _filteredVenues = _filteredVenues
          .where(
            (v) =>
                v.city.toLowerCase() ==
                    ApiService.selectedCity!.toLowerCase() &&
                (v.status?.toLowerCase() == "live"),
          )
          .toList();
    }
    final types = widget.venues
        .map((v) => (v.type ?? '').toUpperCase())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    _categories = ['ALL', ...types];
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
        _applyFilters();
      }
    } catch (e) {
      debugPrint("Error getting location in AllVenuesScreen: $e");
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    setState(() {
      _filteredVenues = widget.venues.where((v) {
        final matchesSearch =
            (_searchQuery.isEmpty ||
                v.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                v.city.toLowerCase().contains(_searchQuery.toLowerCase())) &&
            (v.status?.toLowerCase() == 'live');

        final venueType = (v.type ?? '').toUpperCase();
        final matchesVibe =
            _selectedVibes.isEmpty || _selectedVibes.contains(venueType);

        final matchesCity =
            ApiService.selectedCity == null ||
            v.city.toLowerCase() == ApiService.selectedCity!.toLowerCase();

        // Price level matching
        final venuePrice = v.tableBookingCharges ?? 0.0;
        int venuePriceLevel = 0;
        if (venuePrice <= 500) {
          venuePriceLevel = 0;
        } else if (venuePrice <= 1500) {
          venuePriceLevel = 1;
        } else if (venuePrice <= 3000) {
          venuePriceLevel = 2;
        } else if (venuePrice <= 5000) {
          venuePriceLevel = 3;
        } else {
          venuePriceLevel = 4;
        }
        final matchesPrice = venuePriceLevel <= _priceLevel;

        // Radius matching
        bool matchesRadius = true;
        if (_currentPosition != null && v.latitude != null && v.longitude != null) {
          final distance = GooglePlacesService.calculateRoadDistanceInMeters(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            v.latitude!,
            v.longitude!,
          );
          final distanceKm = distance / 1000.0;
          matchesRadius = distanceKm <= _radius;
        }

        // Crowd density matching
        bool matchesCrowd = true;
        if (_selectedCrowdDensity != null) {
          final cap = v.capacity ?? 100;
          if (_selectedCrowdDensity == 'CHILL') {
            matchesCrowd = cap <= 150;
          } else if (_selectedCrowdDensity == 'LIVELY') {
            matchesCrowd = cap > 150 && cap <= 350;
          } else if (_selectedCrowdDensity == 'PACKED') {
            matchesCrowd = cap > 350;
          }
        }

        return matchesSearch && matchesVibe && matchesCity && matchesPrice && matchesRadius && matchesCrowd;
      }).toList();
    });
  }

  void _onSearchChanged(String query) {
    _searchQuery = query;
    _applyFilters();
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
              child: _isMapView
                  ? LightMapView(
                      venues: _filteredVenues.map((v) => v.toMap()).toList(),
                    )
                  : _filteredVenues.isEmpty
                  ? const Center(
                      child: Text(
                        'No venues found.',
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _filteredVenues.length,
                      itemBuilder: (context, index) {
                        return _buildVenueCard(context, _filteredVenues[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: GestureDetector(
        onTap: () {
          setState(() {
            _isMapView = !_isMapView;
          });
        },
        child: Container(
          height: 43,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LunaraTheme.purpleGradient,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3e0f6b).withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isMapView ? Icons.list : Icons.map,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                _isMapView ? 'LIST VIEW' : 'MAP VIEW',
                style: const TextStyle(
                  fontFamily: 'AllroundGothic',
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
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
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: _isMapView ? LunaraTheme.premiumCardShadow : null,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 8),
          // Search box
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
                  hintText: 'Search venues, cities...',
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
          const SizedBox(width: 12),
          // Filter button
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.black),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdvancedFiltersScreen(
                    initialVibes: _selectedVibes,
                    initialPriceLevel: _priceLevel,
                    initialRadius: _radius,
                    initialCrowdDensity: _selectedCrowdDensity,
                  ),
                ),
              );
              if (result != null) {
                // Update filters from AdvancedFiltersScreen
                setState(() {
                  _selectedVibes = Set<String>.from(result['vibes'] ?? []);
                  _priceLevel =
                      (result['priceLevel'] as num?)?.toDouble() ?? 2.0;
                  _radius = (result['radius'] as num?)?.toDouble() ?? 5.0;
                  _selectedCrowdDensity = result['crowdDensity'];
                });
                _applyFilters();
              }
            },
          ),
          if (_isMapView) const SizedBox(width: 12),
          if (_isMapView)
            Expanded(
              child: SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    final isSelected = _selectedCategory == category;
                    return GestureDetector(
                      onTap: () {
                        _selectedCategory = category;
                        _applyFilters();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? LunaraTheme.electricViolet
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: LunaraTheme.premiumCardShadow,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          category,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVenueCard(BuildContext context, Venue venue) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF3EEFF), Color(0xFFF8F4FF), Color(0xFFEEE6FF)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D7F00FF),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
          BoxShadow(
            color: Color(0x0A7F00FF),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0x1A7F00FF), width: 1.2),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VenueDetailScreen(venue: venue.toMap()),
          ),
        ),
        borderRadius: BorderRadius.circular(32),
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
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 200,
                  color: Colors.grey[100],
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.grey,
                  ),
                ),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 200,
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
                            fontFamily: 'AllroundGothic',
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            letterSpacing: 1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                              size: 16,
                            ),
                            Text(
                              ' ${venue.averageRating}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    (venue.type ?? '').toUpperCase(),
                    style: const TextStyle(
                      color: LunaraTheme.electricViolet,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            color: Colors.grey,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            venue.city,
                            style: const TextStyle(
                              fontFamily: 'AllroundGothic',
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BookingProcessScreen(venue: venue.toMap()),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LunaraTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
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
    );
  }
}
