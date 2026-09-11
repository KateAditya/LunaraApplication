import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../discovery/venue_detail_screen.dart';
import '../../services/api_service.dart';
import '../../models/venue.dart';
import '../../widgets/lunara_cached_image.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<Venue> _allVenues = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVenues();
  }

  Future<void> _loadVenues() async {
    try {
      final venues = await ApiService.fetchVenues();
      if (mounted) {
        setState(() {
          _allVenues = venues
              .where((v) => v.status?.toLowerCase() == 'live')
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('LUNARA', style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w900)),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: LunaraTheme.electricViolet))
          : RefreshIndicator(
              onRefresh: _loadVenues,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroSection(),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('LIVE NOW', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 16),
                    _buildLiveVenues(),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('EXPLORE VIBES', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 16),
                    _buildVibeCategories(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeroSection() {
    return Container(
      height: 200,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LunaraTheme.primaryGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          Positioned(
            bottom: 24,
            left: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('FEATURED TONIGHT', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 8),
                Text(_allVenues.isNotEmpty ? _allVenues.first.name : 'ELARA VELVET', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveVenues() {
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _allVenues.length,
        itemBuilder: (context, index) {
          final venue = _allVenues[index];
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VenueDetailScreen(venue: venue.toMap()))),
            child: Container(
              width: 160,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: venue.imageUrl != null
                        ? LunaraCachedImage(venue.imageUrl!, height: 120, width: double.infinity, fit: BoxFit.cover)
                        : Container(height: 120, color: Colors.grey[200]),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(venue.name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(venue.city, style: const TextStyle(fontSize: 12, color: Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 14),
                            Text(' ${venue.averageRating}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
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

  Widget _buildVibeCategories() {
    final vibes = ['TECHNO', 'LOUNGE', 'ROOFTOP', 'PUB', 'FINE DINING'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: vibes.map((vibe) => _vibeChip(vibe)).toList(),
      ),
    );
  }

  Widget _vibeChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
    );
  }
}
