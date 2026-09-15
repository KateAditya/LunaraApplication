import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class GooglePlacesService {
  static const String _apiKey = 'AIzaSyDfse8V1Zd7nNKDb6Gkr3HoU2VXuZkc114';

  // In-memory cache for exact road distances: key -> meters
  static final Map<String, double> _roadDistanceCache = {};
  static final Map<String, String> _roadDistanceTextCache = {};
  static final Map<String, Future<double>> _inFlightRequests = {};
  static final List<VoidCallback> _listeners = [];

  static void addListener(VoidCallback listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static Timer? _notifyTimer;

  /// Coalesces listener notifications.
  ///
  /// Distances resolve one venue at a time, and each listener is a `setState`
  /// on a large screen, so a screen of venues used to trigger one full rebuild
  /// *per resolved venue*. Scheduling a single notification for the whole burst
  /// collapses that into one rebuild. This is a throttle with a trailing edge,
  /// not a debounce: the timer is never rescheduled while pending, so a steady
  /// trickle of resolutions can't starve the update.
  static void _notifyListeners() {
    if (_notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 100), () {
      _notifyTimer = null;
      for (final listener in List<VoidCallback>.from(_listeners)) {
        try {
          listener();
        } catch (e) {
          debugPrint('GooglePlacesService listener error: $e');
        }
      }
    });
  }

  /// Cache resolution for the two endpoints.
  ///
  /// The destination is a fixed venue and keeps ~11 m resolution (4 dp), which
  /// is what keeps neighbouring venues distinct.
  ///
  /// The origin is the user's own position, and the location stream reports it
  /// every 10 m (`distanceFilter: 10`). At 4 dp the key's own resolution was
  /// ~11 m — just *above* the stream's step — so virtually every GPS update
  /// produced a fresh key, missing the cache for every venue on screen and
  /// re-issuing a Directions request for each one. Rounding the origin to ~110 m
  /// (3 dp) is still far finer than any "2.4 km away" label needs, and lets
  /// ordinary walking reuse the distance already resolved.
  static String _cacheKey(double startLat, double startLng, double endLat, double endLng) {
    return '${startLat.toStringAsFixed(3)},${startLng.toStringAsFixed(3)}->${endLat.toStringAsFixed(4)},${endLng.toStringAsFixed(4)}';
  }

  /// Upper bound on cached distances. Both maps are static and previously grew
  /// without limit for the life of the process; every new origin added another
  /// entry per venue.
  static const int _maxCacheEntries = 2000;

  /// Writes a resolved distance into both caches, evicting the oldest entries
  /// once the ceiling is reached. Dart maps preserve insertion order, so the
  /// first keys are the least recently added.
  static void _storeDistance(String key, double meters, String text) {
    if (!_roadDistanceCache.containsKey(key) &&
        _roadDistanceCache.length >= _maxCacheEntries) {
      final excess = _roadDistanceCache.length - _maxCacheEntries + 1;
      for (final stale in _roadDistanceCache.keys.take(excess).toList()) {
        _roadDistanceCache.remove(stale);
        _roadDistanceTextCache.remove(stale);
      }
    }
    _roadDistanceCache[key] = meters;
    _roadDistanceTextCache[key] = text;
  }

  /// Calculates road driving distance in meters.
  /// Checks cache first, otherwise falls back to geodesic with urban circuity factor (1.30x)
  /// while triggering async road distance resolution in the background.
  static double calculateRoadDistanceInMeters(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    final key = _cacheKey(startLat, startLng, endLat, endLng);
    if (_roadDistanceCache.containsKey(key)) {
      return _roadDistanceCache[key]!;
    }

    // High-performance geodesic distance calculation with regional urban road multiplier (1.30x)
    final straightMeters = Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
    final estimatedMeters = straightMeters * 1.30;
    _storeDistance(key, estimatedMeters, formatDistanceDirect(estimatedMeters));
    return estimatedMeters;
  }

  /// Formats road driving distance for UI display (e.g. "450 m" or "24.0 km").
  /// Returns exact road distance if cached, or triggers background fetch and returns initial estimate.
  static String formatRoadDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    final key = _cacheKey(startLat, startLng, endLat, endLng);
    if (_roadDistanceTextCache.containsKey(key)) {
      return _roadDistanceTextCache[key]!;
    }

    final meters = calculateRoadDistanceInMeters(startLat, startLng, endLat, endLng);
    return formatDistanceDirect(meters);
  }

  /// Helper to format raw meters into a clean display string
  static String formatDistanceDirect(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      final km = meters / 1000.0;
      if (km < 10) {
        return '${km.toStringAsFixed(1)} km';
      } else {
        return '${km.toStringAsFixed(1)} km';
      }
    }
  }

  /// Asynchronously fetches exact driving road distance in meters via:
  /// 1. Google Maps Directions API (Exact road distance matching Google Maps navigation)
  /// 2. OSRM Driving Routing API (Real road network distance)
  /// 3. Geodesic distance * 1.30x fallback if offline
  static Future<double> fetchRoadDistanceMeters(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    final key = _cacheKey(startLat, startLng, endLat, endLng);
    if (_roadDistanceCache.containsKey(key)) {
      return _roadDistanceCache[key]!;
    }

    if (_inFlightRequests.containsKey(key)) {
      return _inFlightRequests[key]!;
    }

    final future = _executeFetchRoadDistance(startLat, startLng, endLat, endLng, key);
    _inFlightRequests[key] = future;
    return future;
  }

  static Future<double> _executeFetchRoadDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
    String key,
  ) async {
    double? exactMeters;
    String? exactText;

    // 1. Try Google Maps Directions API (if not Web or CORS-supported)
    if (!kIsWeb) {
      try {
        final url = 'https://maps.googleapis.com/maps/api/directions/json?origin=$startLat,$startLng&destination=$endLat,$endLng&mode=driving&key=$_apiKey';
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'OK' &&
              data['routes'] != null &&
              (data['routes'] as List).isNotEmpty) {
            final route = data['routes'][0];
            final legs = route['legs'] as List?;
            if (legs != null && legs.isNotEmpty) {
              final distVal = legs[0]['distance']?['value'];
              if (distVal != null && (distVal as num) > 0) {
                exactMeters = (distVal).toDouble();
                exactText = legs[0]['distance']?['text']?.toString();
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Google Directions distance query error: $e');
      }
    }

    // 2. Try OSRM Driving Routing Engine (Free, street-accurate road network distance)
    if (exactMeters == null || exactMeters <= 0) {
      try {
        final url = 'https://router.project-osrm.org/route/v1/driving/$startLng,$startLat;$endLng,$endLat?overview=false';
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['code'] == 'Ok' &&
              data['routes'] != null &&
              (data['routes'] as List).isNotEmpty) {
            final double distance = (data['routes'][0]['distance'] as num).toDouble();
            if (distance > 0) {
              exactMeters = distance;
            }
          }
        }
      } catch (e) {
        debugPrint('OSRM distance fetch error: $e');
      }
    }

    // 3. Fallback to geodesic distance * 1.30 if network failed
    if (exactMeters == null || exactMeters <= 0) {
      final straightMeters = Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
      exactMeters = straightMeters * 1.30;
    }

    // Cache the resolved values
    _storeDistance(key, exactMeters, exactText ?? formatDistanceDirect(exactMeters));
    _inFlightRequests.remove(key);

    // Notify listeners so UI updates automatically with exact driving distance
    _notifyListeners();

    return exactMeters;
  }

  /// Batch prefetches exact driving road distances for a list of destinations
  static Future<void> prefetchDistances(
    double startLat,
    double startLng,
    List<Map<String, double>> destinations,
  ) async {
    for (final dest in destinations) {
      final endLat = dest['lat'];
      final endLng = dest['lng'];
      if (endLat != null && endLng != null && endLat != 0.0 && endLng != 0.0) {
        fetchRoadDistanceMeters(startLat, startLng, endLat, endLng);
      }
    }
  }

  static Future<Map<String, dynamic>?> fetchGoogleRating(String venueName, String city) async {
    // Direct REST API calls to maps.googleapis.com are blocked by browser CORS policies on Web
    if (kIsWeb) return null;

    try {
      final query = Uri.encodeComponent('$venueName $city');
      final url = 'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=$query&inputtype=textquery&fields=rating,user_ratings_total,place_id&key=$_apiKey';

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['candidates'] != null && (data['candidates'] as List).isNotEmpty) {
          return data['candidates'][0] as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<List<LatLng>> fetchDirections(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    // 1. Try OSRM API (Free, actual street routing, supports CORS)
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/$originLng,$originLat;$destLng,$destLat?overview=full&geometries=geojson';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' &&
            data['routes'] != null &&
            (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];
          if (geometry != null && geometry['coordinates'] != null) {
            final List<dynamic> coords = geometry['coordinates'];
            return coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
          }
        }
      }
    } catch (e) {
      debugPrint('OSRM routing failed: $e');
    }

    // 2. Fallback to Google Directions API (mobile only, blocked by browser CORS on Web)
    if (kIsWeb) return [];

    try {
      final url = 'https://maps.googleapis.com/maps/api/directions/json?origin=$originLat,$originLng&destination=$destLat,$destLng&mode=driving&key=$_apiKey';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' &&
            data['routes'] != null &&
            (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final polylinePoints = route['overview_polyline']?['points'] as String?;
          if (polylinePoints != null && polylinePoints.isNotEmpty) {
            return decodePolyline(polylinePoints);
          }
        }
      }
      return [];
    } catch (e) {
      debugPrint('Google Directions API failed: $e');
      return [];
    }
  }

  static List<LatLng> decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }
}
