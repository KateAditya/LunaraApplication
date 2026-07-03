import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../core/theme.dart';
import '../services/google_places_service.dart';
import '../screens/discovery/venue_detail_screen.dart';

class LightMapView extends StatefulWidget {
  final List<Map<String, dynamic>> venues;
  final Map<String, dynamic>? directionToVenue;
  final Position? userPosition;

  const LightMapView({
    super.key,
    required this.venues,
    this.directionToVenue,
    this.userPosition,
  });

  @override
  State<LightMapView> createState() => _LightMapViewState();
}

class _LightMapViewState extends State<LightMapView> {
  late GoogleMapController _controller;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  static const String _lightMapStyle = ''; // Default light style

  @override
  void initState() {
    super.initState();
    _initMarkers();
  }

  @override
  void didUpdateWidget(LightMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.venues != oldWidget.venues ||
        widget.directionToVenue != oldWidget.directionToVenue ||
        widget.userPosition != oldWidget.userPosition) {
      _markers.clear();
      _polylines.clear();
      _initMarkers();
      if (_controller != null) {
        _animateCameraToFitFallback();
      }
    }
  }

  Future<void> _initMarkers() async {
    final Set<Marker> newMarkers = {};

    for (int i = 0; i < widget.venues.length; i++) {
      final venue = widget.venues[i];
      final double lat = (venue['latitude'] as num?)?.toDouble() ?? (18.535 + i * 0.005);
      final double lng = (venue['longitude'] as num?)?.toDouble() ?? (73.834 + i * 0.005);

      newMarkers.add(
        Marker(
          markerId: MarkerId(venue['id']?.toString() ?? i.toString()),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(
            title: venue['name']?.toString() ?? 'Venue',
            snippet: venue['city']?.toString() ?? '',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VenueDetailScreen(venue: venue),
                ),
              );
            },
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(270.0), // 270.0 is Violet
        ),
      );
    }

    if (widget.directionToVenue != null && widget.userPosition != null) {
      final venue = widget.directionToVenue!;
      final double? targetLat = (venue['latitude'] as num?)?.toDouble();
      final double? targetLng = (venue['longitude'] as num?)?.toDouble();

      if (targetLat != null && targetLng != null) {
        final double originLat = widget.userPosition!.latitude;
        final double originLng = widget.userPosition!.longitude;

        GooglePlacesService.fetchDirections(
          originLat,
          originLng,
          targetLat,
          targetLng,
        ).then((points) {
          if (mounted) {
            final routePoints = points.isNotEmpty
                ? points
                : [LatLng(originLat, originLng), LatLng(targetLat, targetLng)];

            setState(() {
              _polylines.clear();
              _polylines.add(
                Polyline(
                  polylineId: const PolylineId('route_directions'),
                  points: routePoints,
                  color: LunaraTheme.electricViolet,
                  width: 5,
                  geodesic: true,
                ),
              );
            });

            if (_controller != null) {
              _animateCameraToFitPolyline(routePoints);
            }
          }
        });
      }
    }

    if (mounted) {
      setState(() {
        _markers.addAll(newMarkers);
      });
    }
  }

  void _animateCameraToFitPolyline(List<LatLng> points) {
    if (points.isEmpty) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    });
  }

  void _animateCameraToFitFallback() {
    if (widget.directionToVenue != null && widget.userPosition != null) {
      final venue = widget.directionToVenue!;
      final double? targetLat = (venue['latitude'] as num?)?.toDouble();
      final double? targetLng = (venue['longitude'] as num?)?.toDouble();

      if (targetLat != null && targetLng != null) {
        final LatLng venueLatLng = LatLng(targetLat, targetLng);
        final LatLng userLatLng = LatLng(widget.userPosition!.latitude, widget.userPosition!.longitude);
        _animateCameraToFitPolyline([userLatLng, venueLatLng]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: const CameraPosition(
        target: LatLng(18.535, 73.834), // Default to Pune center
        zoom: 13,
      ),
      onMapCreated: (controller) {
        _controller = controller;
        if (_lightMapStyle.isNotEmpty) {
          _controller.setMapStyle(_lightMapStyle);
        }
        _animateCameraToFitFallback();
      },
      cloudMapId: 'LUNARA_LIGHT_MAP_ID', // Required for Advanced Markers on Web
      markers: _markers,
      polylines: _polylines,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }
}
