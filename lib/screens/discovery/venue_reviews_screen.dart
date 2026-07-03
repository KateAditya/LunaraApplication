import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass_card.dart';

class VenueReviewsScreen extends StatelessWidget {
  final Map<String, dynamic> venue;

  const VenueReviewsScreen({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: LunaraTheme.midnightBlack),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              _buildOverallRating(),
              _buildReviewSummary(),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: 8,
                  itemBuilder: (context, index) => _buildReviewCard(index),
                ),
              ),
            ],
          ),
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
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            'REVIEWS',
            style: LunaraTheme.headingStyle.copyWith(
              fontSize: 18,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(width: 48), // Spacer
        ],
      ),
    );
  }

  Widget _buildOverallRating() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GlassCard(
        padding: const EdgeInsets.all(24),
        borderRadius: BorderRadius.circular(24),
        child: Row(
          children: [
            Column(
              children: [
                const Text(
                  '4.8',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: List.generate(
                    5,
                    (index) =>
                        const Icon(Icons.star, color: Colors.amber, size: 14),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Based on 1.2k reviews',
                  style: TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(width: 32),
            Expanded(
              child: Column(
                children: [
                  _ratingBar('Energy', 0.9, LunaraTheme.accentVivid),
                  const SizedBox(height: 8),
                  _ratingBar('Safety', 0.85, LunaraTheme.primaryRich),
                  const SizedBox(height: 8),
                  _ratingBar('Crowd', 0.75, LunaraTheme.primaryDeep),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ratingBar(String label, double value, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewSummary() {
    final summary =
        venue['review_summary'] ??
        'This venue is highly praised for its exceptional sound system and elite atmosphere. Guests consistently mention the attentive staff and the overall sense of safety. Perfect for techno lovers seeking a premium underground experience.';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(16),
        borderColor: LunaraTheme.accentVivid.withValues(alpha: 0.2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: LunaraTheme.accentVivid,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'AI SUMMARY',
                  style: LunaraTheme.headingStyle.copyWith(
                    fontSize: 10,
                    color: LunaraTheme.accentVivid,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              summary,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewCard(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: NetworkImage(
                    'https://i.pravatar.cc/150?u=rev$index',
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ALEX R.',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '2 nights ago',
                        style: TextStyle(color: Colors.white24, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: List.generate(
                    5,
                    (i) => Icon(
                      Icons.star,
                      color: i < 5 ? Colors.amber : Colors.white10,
                      size: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'The sound system is incredible. Definately one of the best techno spots in Gotham. The staff was very attentive and safety felt top-notch.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _vibeTag('High Energy'),
                const SizedBox(width: 8),
                _vibeTag('Elite Crowd'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _vibeTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: LunaraTheme.accentVivid.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LunaraTheme.accentVivid.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: LunaraTheme.accentVivid,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
