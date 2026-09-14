import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/match_card.dart';
import 'matched_profiles_screen.dart';
import 'people_who_liked_you_screen.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../profile/profile_screen.dart';

/// Clean, responsive Light-Themed Mutual Matches Hub
class MatchScreen extends StatefulWidget {
  final bool isMatchesOnly;

  const MatchScreen({super.key, this.isMatchesOnly = false});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  final List<Map<String, dynamic>> _likedProfiles = [];
  final List<Map<String, dynamic>> _superLikedProfiles = [];
  final List<Map<String, dynamic>> _matchedProfiles = [];
  bool _isLoading = true;
  int _matchedDeckIndex = 0;
  int _whoLikedCount = 0;
  int _whoLikedSuperCount = 0;
  bool _whoLikedLocked = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  User _mapToUser(Map<String, dynamic> profile) {
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

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      if (ApiService.currentUserId == null) {
        await ApiService.fetchProfile();
      }
      final myId = ApiService.currentUserId;

      // Fetch existing likes/matches and who-liked summary in parallel
      final results = await Future.wait([
        ApiService.fetchMyLikesAndMatches(),
        ApiService.fetchWhoLikedSummary(),
      ]);

      final mySwipes = results[0] as List<dynamic>;
      final whoLikedSummary = (results[1] as Map<String, dynamic>?) ?? {};
      final whoLikedTotal = whoLikedSummary['totalCount'] is int
          ? whoLikedSummary['totalCount'] as int
          : int.tryParse(whoLikedSummary['totalCount']?.toString() ?? '0') ?? 0;
      final whoLikedSuper = whoLikedSummary['superlikesCount'] is int
          ? whoLikedSummary['superlikesCount'] as int
          : int.tryParse(whoLikedSummary['superlikesCount']?.toString() ?? '0') ?? 0;
      final whoLikedIsLocked = whoLikedSummary['locked'] == true;

      final List<Map<String, dynamic>> resolvedLiked = [];
      final List<Map<String, dynamic>> resolvedSuperLiked = [];
      final List<Map<String, dynamic>> resolvedMatched = [];

      // Helper to build a comprehensive profile Map from swipe user json
      Map<String, dynamic> buildProfileMapFromUser(
        dynamic userJson, {
        required String id,
        bool isLiked = false,
        bool isSuperLiked = false,
        bool isMatched = false,
      }) {
        final profile = (userJson is Map) ? userJson['profile'] : null;
        final firstName = userJson?['firstName']?.toString() ??
            userJson?['name']?.toString() ??
            'Member';
        final lastName = userJson?['lastName']?.toString() ?? '';
        final fullName = '$firstName $lastName'.trim();
        final rawPhoto = userJson?['profileImageUrl']?.toString() ??
            userJson?['profilePhoto']?.toString() ??
            profile?['profilePhoto']?.toString() ??
            (profile?['photos'] is List && (profile['photos'] as List).isNotEmpty
                ? profile['photos'][0]?.toString()
                : null);
        final photo = rawPhoto != null && rawPhoto.isNotEmpty
            ? ApiService.formatImageUrl(rawPhoto)
            : 'https://picsum.photos/400/600';
        final city = profile?['city']?.toString() ?? userJson?['city']?.toString() ?? '';
        final occupation = profile?['occupation']?.toString() ?? userJson?['occupation']?.toString() ?? 'Night Owl';
        final bio = profile?['bio']?.toString() ?? userJson?['bio']?.toString() ?? '';
        final rawInterests = profile?['interests'] ?? userJson?['interests'];
        List<String> interests = [];
        if (rawInterests is List) {
          interests = rawInterests.map((e) => e.toString()).toList();
        }

        int age = 25;
        if (profile?['dateOfBirth'] != null || userJson?['dateOfBirth'] != null) {
          try {
            final dob = DateTime.parse((profile?['dateOfBirth'] ?? userJson?['dateOfBirth']).toString());
            final now = DateTime.now();
            age = now.year - dob.year;
            if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
              age--;
            }
          } catch (_) {}
        } else if (profile?['age'] != null) {
          age = int.tryParse(profile['age'].toString()) ?? 25;
        } else if (userJson?['age'] != null) {
          age = int.tryParse(userJson['age'].toString()) ?? 25;
        }

        return {
          'id': id,
          'name': fullName.toUpperCase(),
          'firstName': firstName,
          'lastName': lastName,
          'age': age,
          'vibe': occupation.toUpperCase(),
          'occupation': occupation,
          'city': city.isNotEmpty ? city : 'Nearby',
          'bio': bio,
          'verified': userJson?['isVerified'] == true,
          'distance': city.isNotEmpty ? city : 'Nearby',
          'image': photo,
          'isAsset': false,
          'interests': interests,
          'matchChance': isMatched ? 0.95 : (isSuperLiked ? 0.90 : 0.85),
          'isLiked': isLiked,
          'isSuperLiked': isSuperLiked,
          'isMatched': isMatched,
        };
      }

      // O(M) single-pass indexing and direct resolution of all liked / superliked / matched users
      for (var swipe in mySwipes) {
        try {
          if (swipe is! Map) continue;
          final s = Map<String, dynamic>.from(swipe);
          final user1Id = (s['user1Id'] ?? s['user1_id'] ?? s['swiperId'] ?? s['swiper_id'])?.toString();
          final user2Id = (s['user2Id'] ?? s['user2_id'] ?? s['targetUserId'] ?? s['target_user_id'])?.toString();
          final status = (s['status'] ?? '').toString().toLowerCase();
          final matchReason = (s['matchReason'] ?? '').toString().toLowerCase();
          final isConnected = status == 'connected' || status == 'matched';
          final isSuper = matchReason == 'superlike' || s['isSuperLike'] == true;

          // Case A: Current user initiated (User 1)
          if (user1Id != null && user1Id == myId && user2Id != null && user2Id != myId) {
            final otherUserJson = s['user2'] ?? s['targetUser'];
            final otherUserId = user2Id;
            final pMap = buildProfileMapFromUser(
              otherUserJson,
              id: otherUserId,
              isLiked: !isSuper,
              isSuperLiked: isSuper,
              isMatched: isConnected,
            );
            if (isConnected) {
              if (!resolvedMatched.any((p) => p['id'] == otherUserId)) resolvedMatched.add(pMap);
            } else if (isSuper) {
              if (!resolvedSuperLiked.any((p) => p['id'] == otherUserId)) resolvedSuperLiked.add(pMap);
            } else {
              if (!resolvedLiked.any((p) => p['id'] == otherUserId)) resolvedLiked.add(pMap);
            }
          }
          // Case B: Current user received (User 2)
          else if (user2Id != null && user2Id == myId && user1Id != null && user1Id != myId) {
            final otherUserJson = s['user1'] ?? s['swiper'];
            final otherUserId = user1Id;
            if (isConnected) {
              final pMap = buildProfileMapFromUser(
                otherUserJson,
                id: otherUserId,
                isLiked: false,
                isSuperLiked: isSuper,
                isMatched: true,
              );
              if (!resolvedMatched.any((p) => p['id'] == otherUserId)) resolvedMatched.add(pMap);
            }
          }
          // Case C: Fallback when status is connected/matched
          else if (isConnected) {
            dynamic otherUserJson = s['user2'] ?? s['targetUser'];
            String otherUserId = user2Id ?? '';
            if (user2Id == myId || (otherUserJson is Map && otherUserJson['id']?.toString() == myId)) {
              otherUserJson = s['user1'] ?? s['swiper'];
              otherUserId = user1Id ?? (otherUserJson is Map ? otherUserJson['id']?.toString() ?? '' : '');
            }
            if (otherUserId.isNotEmpty && otherUserId != myId) {
              final pMap = buildProfileMapFromUser(
                otherUserJson,
                id: otherUserId,
                isLiked: false,
                isSuperLiked: isSuper,
                isMatched: true,
              );
              if (!resolvedMatched.any((p) => p['id'] == otherUserId)) resolvedMatched.add(pMap);
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _likedProfiles.clear();
          _likedProfiles.addAll(resolvedLiked);

          _superLikedProfiles.clear();
          _superLikedProfiles.addAll(resolvedSuperLiked);

          _matchedProfiles.clear();
          _matchedProfiles.addAll(resolvedMatched);

          _whoLikedCount = whoLikedTotal;
          _whoLikedSuperCount = whoLikedSuper;
          _whoLikedLocked = whoLikedIsLocked;

          if (_matchedDeckIndex >= _matchedProfiles.length) {
            _matchedDeckIndex = 0;
          }

          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: Stack(
        children: [
          // Ambient soft light theme glows
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    LunaraTheme.electricViolet.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    LunaraTheme.hotPink.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main Layout
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 6),
                _buildHeader(),
                const SizedBox(height: 12),
                _buildMatchStats(),
                const SizedBox(height: 12),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: LunaraTheme.electricViolet,
                          ),
                        )
                      : _matchedProfiles.isEmpty
                          ? _buildEmptyState()
                          : _buildSwipeableCards(),
                ),
                const SizedBox(height: 12),
                if (_matchedProfiles.isNotEmpty) ...[
                  _buildActionButtons(),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 🔙 Always Visible Glassmorphic Light Back Button
          GestureDetector(
            onTap: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
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
                child: Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 🏷️ Header Title (Clean, Never Truncated)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'MUTUAL',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                    color: LunaraTheme.electricViolet,
                  ),
                ),
                Text(
                  'Your Matches (${_matchedProfiles.length})',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // 🔄 Refresh Action Button
          GestureDetector(
            onTap: _isLoading ? null : _loadData,
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
              child: Center(
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: LunaraTheme.electricViolet,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, color: Color(0xFF0F172A), size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchStats() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Who Liked You Teaser Chip
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PeopleWhoLikedYouScreen(),
                ),
              ).then((_) => _loadData());
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _whoLikedLocked
                      ? [
                          const Color(0xFF7F00FF).withValues(alpha: 0.85),
                          const Color(0xFFFF007F).withValues(alpha: 0.85),
                        ]
                      : [
                          const Color(0xFFFF007F),
                          const Color(0xFFFF5252),
                        ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF007F).withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite, color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '$_whoLikedCount Likes You${_whoLikedSuperCount > 0 ? " (★ $_whoLikedSuperCount)" : ""}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _whoLikedLocked ? Icons.lock : Icons.arrow_forward_ios,
                    color: Colors.white70,
                    size: 11,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Liked Profiles
          _statChip(
            icon: Icons.favorite_rounded,
            label: '${_likedProfiles.length} Liked',
            color: const Color(0xFFE100FF),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MatchedProfilesScreen(
                    matchedProfiles: _likedProfiles,
                    title: 'LIKED PROFILES',
                    subtitle: 'people you liked',
                  ),
                ),
              ).then((_) => _loadData());
            },
          ),
          const SizedBox(width: 8),

          // Super Liked Profiles
          _statChip(
            icon: Icons.star_rounded,
            label: '${_superLikedProfiles.length} Super',
            color: const Color(0xFF7F00FF),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MatchedProfilesScreen(
                    matchedProfiles: _superLikedProfiles,
                    title: 'SUPER LIKED PROFILES',
                    subtitle: 'people you super liked',
                  ),
                ),
              ).then((_) => _loadData());
            },
          ),
          const SizedBox(width: 8),

          // Matches
          _statChip(
            icon: Icons.bolt_rounded,
            label: '${_matchedProfiles.length} Matches',
            color: const Color(0xFF7F00FF),
            isSelected: true,
            onTap: () {
              if (_matchedProfiles.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MatchedProfilesScreen(
                      matchedProfiles: _matchedProfiles,
                      title: 'MUTUAL MATCHES',
                      subtitle: 'people you matched with',
                    ),
                  ),
                ).then((_) => _loadData());
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required Color color,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEDE9FE) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF7F00FF) : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFF7F00FF).withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF7F00FF) : const Color(0xFF0F172A),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwipeableCards() {
    final total = _matchedProfiles.length;
    if (total == 0) return _buildEmptyState();

    final activeIndex = _matchedDeckIndex.clamp(0, total - 1);
    final currentMatched = _matchedProfiles[activeIndex];
    final nextMatched = total > 1 ? _matchedProfiles[(activeIndex + 1) % total] : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (nextMatched != null)
            Positioned.fill(
              child: Transform.scale(
                scale: 0.95,
                child: Transform.translate(
                  offset: const Offset(0, 10),
                  child: Opacity(
                    opacity: 0.6,
                    child: MatchCard(profile: nextMatched),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                final userObj = _mapToUser(currentMatched);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(user: userObj),
                  ),
                );
              },
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity != null && total > 1) {
                  if (details.primaryVelocity! < -100) {
                    // Swipe Left -> Next Match
                    setState(() {
                      _matchedDeckIndex = (_matchedDeckIndex + 1) % total;
                    });
                  } else if (details.primaryVelocity! > 100) {
                    // Swipe Right -> Prev Match
                    setState(() {
                      _matchedDeckIndex = (_matchedDeckIndex - 1 + total) % total;
                    });
                  }
                }
              },
              child: Stack(
                children: [
                  MatchCard(profile: currentMatched),
                  // Mutual match badge in top corner
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7F00FF), Color(0xFF9333EA)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7F00FF).withValues(alpha: 0.4),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'MUTUAL MATCH',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
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
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE9FE),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFC4B5FD),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7F00FF).withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: Color(0xFF7F00FF),
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Mutual Matches Yet',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'When you and another member both like each other, they will appear right here with full profile access and direct chat!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PeopleWhoLikedYouScreen(),
                  ),
                ).then((_) => _loadData());
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7F00FF), Color(0xFF9333EA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7F00FF).withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'SEE WHO LIKES YOU',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        fontSize: 12,
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

  Widget _buildActionButtons() {
    final total = _matchedProfiles.length;
    if (total == 0) return const SizedBox.shrink();

    final hasMultiple = total > 1;
    final activeIndex = _matchedDeckIndex.clamp(0, total - 1);
    final currentMatched = _matchedProfiles[activeIndex];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              if (hasMultiple) ...[
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_matchedDeckIndex > 0) {
                        _matchedDeckIndex--;
                      } else {
                        _matchedDeckIndex = total - 1;
                      }
                    });
                  },
                  child: Container(
                    width: 48,
                    height: 48,
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
                      child: Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],

              // 💜 VIEW FULL PROFILE (100% Responsive with FittedBox)
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    final userObj = _mapToUser(currentMatched);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(user: userObj),
                      ),
                    );
                  },
                  child: Container(
                    height: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7F00FF), Color(0xFF9333EA)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7F00FF).withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_rounded, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'VIEW FULL PROFILE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              if (hasMultiple) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_matchedDeckIndex < total - 1) {
                        _matchedDeckIndex++;
                      } else {
                        _matchedDeckIndex = 0;
                      }
                    });
                  },
                  child: Container(
                    width: 48,
                    height: 48,
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
                      child: Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF0F172A), size: 16),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Pagination dots if multiple matches
        if (hasMultiple) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(total, (index) {
              final isCur = index == activeIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isCur ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isCur ? const Color(0xFF7F00FF) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: isCur
                      ? [
                          BoxShadow(
                            color: const Color(0xFF7F00FF).withValues(alpha: 0.4),
                            blurRadius: 6,
                          )
                        ]
                      : null,
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          hasMultiple
              ? 'Match ${activeIndex + 1} of $total • Swipe card or tap arrows to browse'
              : 'Mutual match • Tap card or button to view full profile',
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
