import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass_card.dart';
import 'chat_screen.dart';
import '../../widgets/profile_share_sheet.dart';
import '../../widgets/lunara_cached_image.dart';

/// Screen showing matched or liked profiles. Accessible by tapping match/like count.
class MatchedProfilesScreen extends StatelessWidget {
  final List<Map<String, dynamic>> matchedProfiles;
  final String title;
  final String subtitle;

  const MatchedProfilesScreen({
    super.key,
    required this.matchedProfiles,
    this.title = 'YOUR MATCHES',
    this.subtitle = 'people matched with you',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          color: Theme.of(context).colorScheme.onSurface,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: LunaraTheme.headingStyle.copyWith(
                            fontSize: 22,
                          ),
                        ),
                        Text(
                          '${matchedProfiles.length} $subtitle',
                          style: LunaraTheme.bodyStyle.copyWith(
                            fontSize: 12,
                            color: LunaraTheme.accentVivid,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Matches Grid
              Expanded(
                child: matchedProfiles.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: matchedProfiles.length,
                        itemBuilder: (context, index) {
                          return _buildMatchTile(
                            context,
                            matchedProfiles[index],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_border,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.24),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'No matches yet',
            style: LunaraTheme.headingStyle.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Keep swiping to find your match!',
            style: LunaraTheme.bodyStyle.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.54),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchTile(BuildContext context, Map<String, dynamic> profile) {
    final matchChance =
        ((profile['matchChance'] as num?)?.toDouble() ?? 0.5) * 100;

    return GestureDetector(
      onTap: () {
        // Navigate to profile detail
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => _MatchedProfileDetailScreen(profile: profile),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: LunaraTheme.accentVivid.withValues(alpha: 0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: LunaraTheme.accentVivid.withValues(alpha: 0.15),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 30,
                backgroundImage: profile['isAsset'] == true
                    ? AssetImage(profile['image'] ?? '') as ImageProvider
                    : NetworkImage(profile['image'] ?? ''),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        profile['name'] ?? 'Unknown',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (LunaraTheme.getPlanBadgeColor(profile) != null) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.verified,
                          color: LunaraTheme.getPlanBadgeColor(profile),
                          size: 16,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile['vibe'] ?? '',
                    style: TextStyle(
                      color: LunaraTheme.accentVivid.withValues(alpha: 0.7),
                      fontSize: 11,
                      letterSpacing: 1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile['distance'] ?? '',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            // Match percentage
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: matchChance >= 70
                    ? Color(0xFF10B981).withValues(alpha: 0.15)
                    : matchChance >= 40
                    ? Color(0xFFFFD700).withValues(alpha: 0.15)
                    : Color(0xFFFF6B6B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: matchChance >= 70
                      ? Color(0xFF10B981).withValues(alpha: 0.3)
                      : matchChance >= 40
                      ? Color(0xFFFFD700).withValues(alpha: 0.3)
                      : Color(0xFFFF6B6B).withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                '${matchChance.toInt()}%',
                style: TextStyle(
                  color: matchChance >= 70
                      ? const Color(0xFF10B981)
                      : matchChance >= 40
                      ? const Color(0xFFFFD700)
                      : const Color(0xFFFF6B6B),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.24),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen profile detail for a matched user.
class _MatchedProfileDetailScreen extends StatelessWidget {
  final Map<String, dynamic> profile;

  const _MatchedProfileDetailScreen({required this.profile});

  @override
  Widget build(BuildContext context) {
    final matchChance =
        ((profile['matchChance'] as num?)?.toDouble() ?? 0.5) * 100;

    return Scaffold(
      body: Stack(
        children: [
          // Full-screen profile image
          Positioned.fill(
            child: profile['isAsset'] == true
                ? Image.asset(
                    profile['image'] ?? '',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: Colors.grey[900],
                      child: const Center(
                        child: Icon(
                          Icons.person,
                          color: Colors.white54,
                          size: 64,
                        ),
                      ),
                    ),
                  )
                : LunaraCachedImage(profile['image'] ?? '', fit: BoxFit.cover),
          ),

          // Gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.4, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.95),
                  ],
                ),
              ),
            ),
          ),

          // Back button
          Positioned(
            top: 50,
            left: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),

          // Match badge (top-right)
          Positioned(
            top: 50,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: matchChance >= 70
                      ? [const Color(0xFF10B981), const Color(0xFF059669)]
                      : [const Color(0xFFFFD700), const Color(0xFFFF8C00)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite, color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${matchChance.toInt()}% MATCH',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Profile Info at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Name & Age
                  Row(
                    children: [
                      Text(
                        '${profile['name']}, ${profile['age']}',
                        style: LunaraTheme.headingStyle.copyWith(fontSize: 32),
                      ),
                      if (LunaraTheme.getPlanBadgeColor(profile) != null) ...[
                        const SizedBox(width: 10),
                        Icon(
                          Icons.verified,
                          color: LunaraTheme.getPlanBadgeColor(profile),
                          size: 28,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Vibe
                  Text(
                    profile['vibe'] ?? '',
                    style: LunaraTheme.bodyStyle.copyWith(
                      color: LunaraTheme.accentVivid,
                      letterSpacing: 2,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Distance
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.white54,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        profile['distance'] ?? '',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Interests
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: (profile['interests'] as List<String>? ?? [])
                        .map(
                          (interest) => GlassCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            opacity: 0.2,
                            child: Text(
                              interest,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _actionBtn(
                        icon: Icons.chat_bubble_outline,
                        label: 'MESSAGE',
                        color: LunaraTheme.accentVivid,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                user: {
                                  'name': profile['name'] ?? 'User',
                                  'image': profile['image'] ?? '',
                                  'isAsset': profile['isAsset'] ?? false,
                                  'online': true,
                                },
                              ),
                            ),
                          );
                        },
                      ),
                      _actionBtn(
                        icon: Icons.person_add_alt_1,
                        label: 'ADD FRIEND',
                        color: LunaraTheme.primaryRich,
                        onTap: () {},
                      ),
                      _actionBtn(
                        icon: Icons.share,
                        label: 'SHARE',
                        color: LunaraTheme.primaryDeep,
                        onTap: () {
                          ProfileShareSheet.show(
                            context,
                            profileId: profile['id']?.toString() ?? '',
                            name: profile['name'] ?? 'User',
                            age: profile['age']?.toString(),
                            city: profile['city'] ?? profile['distance'],
                            profilePhotoUrl: profile['image'],
                            isAsset: profile['isAsset'] == true,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
