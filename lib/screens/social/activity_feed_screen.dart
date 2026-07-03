import 'package:flutter/material.dart';
import '../../core/theme.dart';

class ActivityFeedScreen extends StatelessWidget {
  const ActivityFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(24.0),
                itemCount: 10,
                itemBuilder: (context, index) {
                  return _buildActivityItem(index);
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
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Text(
            'ACTIVITY PULSE',
            style: LunaraTheme.headingStyle.copyWith(
              fontSize: 20,
              letterSpacing: 4,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.tune, color: Color(0xFF1A1A1A), size: 20),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem(int index) {
    final types = ['match', 'guestlist', 'booking', 'vibe_check'];
    final type = types[index % types.length];

    switch (type) {
      case 'match':
        return _buildMatchActivity();
      case 'guestlist':
        return _buildGuestlistActivity();
      case 'booking':
        return _buildBookingActivity();
      case 'vibe_check':
        return _buildVibeCheckActivity();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMatchActivity() {
    return _baseActivityItem(
      icon: Icons.favorite,
      iconColor: LunaraTheme.primaryDeep,
      title: 'New Match Found!',
      subtitle: 'You and Sarah J. are a vibe match. Start a conversation now.',
      time: '2m ago',
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundImage: NetworkImage('https://i.pravatar.cc/150?u=s2'),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.bolt, color: LunaraTheme.accentVivid, size: 16),
          const SizedBox(width: 4),
          const CircleAvatar(
            radius: 20,
            backgroundImage: NetworkImage('https://i.pravatar.cc/150?u=me'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestlistActivity() {
    return _baseActivityItem(
      icon: Icons.list_alt,
      iconColor: Colors.amber,
      title: 'Friend on Guestlist',
      subtitle: 'Alex R. just joined the guestlist for Elara Velvet.',
      time: '15m ago',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LunaraTheme.purpleGradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, color: Colors.white, size: 14),
            const SizedBox(width: 8),
            const Text(
              'JOIN GUESTLIST TOO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingActivity() {
    return _baseActivityItem(
      icon: Icons.confirmation_number_outlined,
      iconColor: LunaraTheme.accentVivid,
      title: 'Table Confirmed',
      subtitle: 'Your VIP booking at Ultra Club for tonight is verified.',
      time: '1h ago',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LunaraTheme.cardGradient,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: LunaraTheme.lightBorder),
          boxShadow: LunaraTheme.premiumShadow,
        ),
        child: const Text(
          'VIEW TICKET',
          style: TextStyle(
            color: LunaraTheme.accentVivid,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildVibeCheckActivity() {
    return _baseActivityItem(
      icon: Icons.flash_on,
      iconColor: LunaraTheme.primaryRich,
      title: 'Vibe Check: High Energy',
      subtitle: 'Neon Pulse is reaching peak capacity. Music: Melodic House.',
      time: '30m ago',
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: LunaraTheme.primaryRich.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '🔥 PEPPERY',
              style: TextStyle(
                color: LunaraTheme.primaryRich,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _baseActivityItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String time,
    Widget? child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: const Color(0xFF1A1A1A).withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        time,
                        style: const TextStyle(
                          color: Colors.black38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  if (child != null) ...[const SizedBox(height: 12), child],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
