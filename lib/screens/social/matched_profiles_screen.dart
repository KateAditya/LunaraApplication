import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../widgets/lunara_cached_image.dart';
import '../profile/profile_screen.dart';

/// Screen showing matched, liked, or super-liked profiles. Accessible by tapping match/like stats.
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

  static User mapToUser(Map<String, dynamic> profile) {
    final rawInterests = profile['interests'];
    List<String> parsedInterests = [];
    if (rawInterests is List) {
      parsedInterests = rawInterests.map((e) => e.toString()).toList();
    }

    final rawName = profile['name']?.toString() ??
        profile['fullName']?.toString() ??
        'LUNARA MEMBER';
    final parts = rawName.split(' ');
    final firstName = profile['firstName']?.toString() ??
        (parts.isNotEmpty ? parts.first : 'User');
    final lastName = profile['lastName']?.toString() ??
        (parts.length > 1 ? parts.sublist(1).join(' ') : '');
    final rawPhoto = profile['image']?.toString() ??
        profile['profilePhoto']?.toString() ??
        profile['profileImageUrl']?.toString();
    final photo = rawPhoto != null && rawPhoto.isNotEmpty
        ? ApiService.formatImageUrl(rawPhoto)
        : null;

    return User(
      id: (profile['id'] ?? profile['_id'] ?? '').toString(),
      firstName: firstName,
      lastName: lastName,
      email: profile['email']?.toString() ?? '',
      phone: profile['phone']?.toString() ?? '',
      profilePhoto: photo,
      photos: photo != null ? [photo] : [],
      city: profile['city']?.toString() ?? profile['distance']?.toString() ?? '',
      occupation: profile['occupation']?.toString() ?? profile['vibe']?.toString(),
      bio: profile['bio']?.toString() ?? '',
      interests: parsedInterests,
      isVerified: profile['verified'] == true || profile['isVerified'] == true,
      age: profile['age'] is int
          ? profile['age'] as int
          : int.tryParse(profile['age']?.toString() ?? '') ?? 25,
      isLiked: profile['isLiked'] == true,
      isSuperLiked: profile['isSuperLiked'] == true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Responsive Light Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Color(0xFF0F172A),
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${matchedProfiles.length} $subtitle',
                          style: const TextStyle(
                            fontSize: 12,
                            color: LunaraTheme.electricViolet,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Matches List
            Expanded(
              child: matchedProfiles.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
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
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isSuper = title.contains('SUPER');
    final isLiked = title.contains('LIKED');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: (isSuper
                        ? const Color(0xFFFEF3C7)
                        : isLiked
                            ? const Color(0xFFFCE7F3)
                            : const Color(0xFFEDE9FE)),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                isSuper
                    ? Icons.star_rounded
                    : isLiked
                        ? Icons.favorite_rounded
                        : Icons.bolt_rounded,
                color: isSuper
                    ? const Color(0xFFD97706)
                    : isLiked
                        ? const Color(0xFFE100FF)
                        : const Color(0xFF7F00FF),
                size: 52,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isSuper
                  ? 'No Super Liked Profiles Yet'
                  : isLiked
                      ? 'No Liked Profiles Yet'
                      : 'No Matches Yet',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isSuper
                  ? 'Send a Super Like to standout and get noticed instantly!'
                  : isLiked
                      ? 'Profiles you like will appear here for easy viewing.'
                      : 'When you and another member like each other, they will appear here!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchTile(BuildContext context, Map<String, dynamic> profile) {
    final isSuper = profile['isSuperLiked'] == true || title.contains('SUPER');
    final isMatch = profile['isMatched'] == true;
    final userObj = mapToUser(profile);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileScreen(user: userObj),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSuper
                ? const Color(0xFFFDE68A)
                : isMatch
                    ? const Color(0xFFDDD6FE)
                    : const Color(0xFFE2E8F0),
            width: isSuper || isMatch ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar with Gradient Ring
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: isSuper
                      ? [const Color(0xFFFFD700), const Color(0xFFFF8C00)]
                      : isMatch
                          ? [const Color(0xFF7C3AED), const Color(0xFF9333EA)]
                          : [LunaraTheme.electricViolet, LunaraTheme.hotPink],
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: profile['isAsset'] == true
                      ? Image.asset(
                          profile['image'] ?? 'assets/images/placeholder.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: const Color(0xFFF1F5F9),
                            child: const Icon(Icons.person, color: Color(0xFF94A3B8), size: 28),
                          ),
                        )
                      : LunaraCachedImage(
                          profile['image'] ?? 'https://picsum.photos/400/600',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: const Color(0xFFF1F5F9),
                            child: const Icon(Icons.person, color: Color(0xFF94A3B8), size: 28),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Info Section
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile['name'] ?? 'Lunara Member',
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (LunaraTheme.getPlanBadgeColor(profile) != null) ...[
                        const SizedBox(width: 5),
                        Icon(
                          Icons.verified,
                          color: LunaraTheme.getPlanBadgeColor(profile),
                          size: 15,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    profile['vibe'] ?? profile['occupation'] ?? 'NIGHT OWL',
                    style: TextStyle(
                      color: isSuper
                          ? const Color(0xFFD97706)
                          : LunaraTheme.electricViolet,
                      fontSize: 11,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile['distance'] ?? profile['city'] ?? 'Nearby',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // View Profile Button
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(user: userObj),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7F00FF), Color(0xFF9333EA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7F00FF).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'VIEW',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
