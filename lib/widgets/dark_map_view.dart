import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/theme.dart';
import '../screens/discovery/venue_detail_screen.dart';

/// Google Maps with dark night-mode styling and custom venue markers.
class DarkMapView extends StatefulWidget {
  final List<Map<String, dynamic>> venues;

  const DarkMapView({super.key, required this.venues});

  @override
  State<DarkMapView> createState() => _DarkMapViewState();
}

class _DarkMapViewState extends State<DarkMapView> {
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _initMarkers();
  }

  @override
  void didUpdateWidget(DarkMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.venues != oldWidget.venues) {
      _initMarkers();
    }
  }

  // Pune center
  static const LatLng _puneCenter = LatLng(18.5350, 73.8800);

  // Beautiful dark map style JSON (Aubergine/Night theme)
  static const String _darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0d0d1a"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#6b6b8d"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0d0d1a"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#1a1a2e"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#8b5cf6"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#6b6b8d"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#0f1a0f"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#10b981"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#1a1a3e"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#5c5c7a"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#1e1e40"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2a1a4e"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#3d2370"}]},
  {"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#3d1a6e"}]},
  {"featureType":"road.local","elementType":"geometry","stylers":[{"color":"#16162a"}]},
  {"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#5c5c7a"}]},
  {"featureType":"transit.line","elementType":"geometry","stylers":[{"color":"#1a1a3e"}]},
  {"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#1a1a30"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#060612"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d3d6b"}]}
]
''';

  Future<void> _initMarkers() async {
    final Set<Marker> newMarkers = {};

    for (int i = 0; i < widget.venues.length; i++) {
      final venue = widget.venues[i];
      final double lat =
          (venue['latitude'] as num?)?.toDouble() ?? (18.535 + i * 0.005);
      final double lng =
          (venue['longitude'] as num?)?.toDouble() ?? (73.870 + i * 0.008);
      final type = venue['type'] ?? venue['category'];

      // Generate custom marker bitmap
      final iconBytes = await _createCustomMarkerBitmap(
        color: _categoryColor(type),
        iconData: _categoryIcon(type),
      );

      final markerId = MarkerId('venue_$i');

      newMarkers.add(
        Marker(
          markerId: markerId,
          position: LatLng(lat, lng),
          icon: BitmapDescriptor.bytes(iconBytes),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VenueDetailScreen(venue: venue),
              ),
            );
          },
        ),
      );
    }

    if (mounted) {
      setState(() {
        _markers.clear();
        _markers.addAll(newMarkers);
      });
    }
  }

  Future<Uint8List> _createCustomMarkerBitmap({
    required Color color,
    required IconData iconData,
  }) async {
    final int shadowSize = 90; // Canvas size
    final double markerRadius = 26.0; // Slightly smaller, elegant size
    final Offset center = Offset(shadowSize / 2, shadowSize / 2);

    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    // 1. Sleek Colored Outer Glow
    final shadowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(center, markerRadius, shadowPaint);

    // 2. Deep Dark Background (matching map theme)
    final bgPaint = Paint()
      ..color = const Color(0xFF0D0D1A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, markerRadius, bgPaint);

    // 3. Tinted Inner Fill (like the legend)
    final tintPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, markerRadius - 1, tintPaint);

    // 4. Thin Elegant Border
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, markerRadius, borderPaint);

    // 5. The Icon (Colored to match the theme)
    TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(iconData.codePoint),
      style: TextStyle(
        fontSize: markerRadius * 1.15,
        fontFamily: iconData.fontFamily,
        package: iconData.fontPackage,
        color: color,
      ),
    );
    textPainter.layout();

    // Center the icon visually
    final double xCenter = (shadowSize - textPainter.width) / 2;
    final double yCenter = (shadowSize - textPainter.height) / 2;
    textPainter.paint(canvas, Offset(xCenter, yCenter));

    final ui.Image img = await pictureRecorder.endRecording().toImage(
      shadowSize,
      shadowSize,
    );
    final ByteData? byteData = await img.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return byteData!.buffer.asUint8List();
  }

  IconData _categoryIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'rooftop':
        return Icons.roofing;
      case 'bars':
        return Icons.local_bar;
      case 'pubs':
        return Icons.sports_bar;
      case 'club':
        return Icons.nightlife;
      case 'lounge':
        return Icons.weekend;
      case 'fine_dining':
      case 'fine dining':
        return Icons.restaurant;
      default:
        return Icons.location_on;
    }
  }

  Color _categoryColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'rooftop':
        return const Color(0xFFFF6B9D);
      case 'bars':
        return const Color(0xFF00D4FF);
      case 'pubs':
        return const Color(0xFFFFD700);
      case 'club':
        return const Color(0xFF8B5CF6);
      case 'lounge':
        return const Color(0xFF10B981);
      case 'fine_dining':
      case 'fine dining':
        return const Color(0xFFFF8C00);
      default:
        return LunaraTheme.primaryRich;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Google Map with dark style
        GoogleMap(
          initialCameraPosition: const CameraPosition(
            target: _puneCenter,
            zoom: 13.0,
          ),
          markers: _markers,
          onMapCreated: (controller) {
            controller.setMapStyle(_darkMapStyle);
          },
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
        ),

        // Top overlay — "PUNE" location label
        Positioned(
          top: 70,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: LunaraTheme.primaryRich.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_on,
                    color: LunaraTheme.accentVivid,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'PUNE, MAHARASHTRA',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Category legend (bottom-left)
        Positioned(
          bottom: 100,
          left: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'VENUES',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                _legendItem('Rooftop', const Color(0xFFFF6B9D), Icons.roofing),
                _legendItem('Bars', const Color(0xFF00D4FF), Icons.local_bar),
                _legendItem('Pubs', const Color(0xFFFFD700), Icons.sports_bar),
                _legendItem('Club', const Color(0xFF8B5CF6), Icons.nightlife),
                _legendItem('Lounge', const Color(0xFF10B981), Icons.weekend),
                _legendItem(
                  'Dining',
                  const Color(0xFFFF8C00),
                  Icons.restaurant,
                ),
              ],
            ),
          ),
        ),

        // Venue count badge (top-right)
        Positioned(
          top: 70,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: LunaraTheme.accentVivid.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              '${widget.venues.length} venues',
              style: TextStyle(
                color: LunaraTheme.accentVivid,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendItem(String label, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, color: color, size: 10),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
