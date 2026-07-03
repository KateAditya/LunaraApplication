import 'package:flutter/material.dart';
import '../../core/theme.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<String> _recentSearches = [
    'NEON JUNGLE',
    'ELARA',
    'TECHNO HOUSE',
    'VIP BOOTH',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('RECENT SEARCHES'),
                    const SizedBox(height: 16),
                    _buildRecentSearches(),
                    const SizedBox(height: 40),
                    _buildSectionHeader('FIND BY CATEGORY'),
                    const SizedBox(height: 16),
                    _buildCategories(),
                    const SizedBox(height: 40),
                    _buildSectionHeader('TRENDING TONIGHT'),
                    const SizedBox(height: 16),
                    _buildTrendingList(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
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
                autofocus: true,
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'Search venues, people, or vibes...',
                  hintStyle: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  suffixIcon: const Icon(
                    Icons.search,
                    color: LunaraTheme.electricViolet,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.grey[400],
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildRecentSearches() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _recentSearches
          .map((search) => _buildSearchChip(search))
          .toList(),
    );
  }

  Widget _buildSearchChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.close, color: Colors.grey[300], size: 14),
        ],
      ),
    );
  }

  Widget _buildCategories() {
    final categories = [
      {
        'name': 'ROOFTOP',
        'icon': Icons.layers_outlined,
        'color': LunaraTheme.electricViolet,
      },
      {
        'name': 'UNDERGROUND',
        'icon': Icons.unarchive_outlined,
        'color': LunaraTheme.electricViolet,
      },
      {
        'name': 'LOUNGE',
        'icon': Icons.weekend_outlined,
        'color': LunaraTheme.electricViolet,
      },
      {
        'name': 'LIVE MUSIC',
        'icon': Icons.mic_external_on_outlined,
        'color': LunaraTheme.electricViolet,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 2.2,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final cat = categories[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: LunaraTheme.cardGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: LunaraTheme.premiumCardShadow,
            border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              Icon(
                cat['icon'] as IconData,
                color: cat['color'] as Color,
                size: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  cat['name'] as String,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTrendingList() {
    final trending = [
      {'name': 'NEON JUNGLE', 'type': 'CLUB', 'matches': '42 Matches Active'},
      {'name': 'OBSIDIAN', 'type': 'LOUNGE', 'matches': '18 Matches Active'},
      {
        'name': 'THE VAULT',
        'type': 'UNDERGROUND',
        'matches': '29 Matches Active',
      },
    ];

    return Column(
      children: trending
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LunaraTheme.cardGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: LunaraTheme.premiumCardShadow,
                  border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.05)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: LunaraTheme.electricViolet.withValues(
                          alpha: 0.05,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.trending_up_rounded,
                        color: LunaraTheme.electricViolet,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name']!,
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item['type']!,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      item['matches']!,
                      style: const TextStyle(
                        color: LunaraTheme.electricViolet,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
