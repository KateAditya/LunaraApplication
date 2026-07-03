import 'package:flutter/material.dart';
import '../../core/theme.dart';

class VenueInvitePickerScreen extends StatelessWidget {
  const VenueInvitePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final venues = [
      {'name': 'ELARA VELVET', 'type': 'Rooftop Lounge', 'dist': '0.8km'},
      {'name': 'OBSIDIAN', 'type': 'Techno Club', 'dist': '1.2km'},
      {'name': 'NEON GARDEN', 'type': 'Botanical Bar', 'dist': '0.5km'},
      {'name': 'ULTRA CLUB', 'type': 'VIP Lounge', 'dist': '2.1km'},
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildSearch(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: venues.length,
                itemBuilder: (context, index) {
                  final venue = venues[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, venue),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LunaraTheme.cardGradient,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: LunaraTheme.premiumCardShadow,
                          border: Border.all(
                            color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey[100]!),
                              ),
                              child: const Icon(
                                Icons.nightlife,
                                color: LunaraTheme.electricViolet,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    venue['name']!,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${venue['type']} • ${venue['dist']}',
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.add_circle_outline,
                              color: LunaraTheme.electricViolet,
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'SEND INVITATION',
            style: TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[100]!),
        ),
        child: TextField(
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'Search venues...',
            hintStyle: const TextStyle(color: Colors.black),
            border: InputBorder.none,
            icon: Icon(Icons.search, color: Colors.grey[400], size: 20),
          ),
        ),
      ),
    );
  }
}
