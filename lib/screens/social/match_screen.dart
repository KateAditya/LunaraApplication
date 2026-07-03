import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/match_card.dart';
import 'match_success_dialog.dart';
import 'match_settings_screen.dart';
import 'matched_profiles_screen.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';

class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _profiles = [];
  final List<Map<String, dynamic>> _likedProfiles = [];
  final List<Map<String, dynamic>> _matchedProfiles = [];
  bool _isLoading = true;
  String _swipeAction = 'like';

  // Swipe animation
  double _dragX = 0;
  double _dragY = 0;
  double _dragAngle = 0;
  bool _isDragging = false;
  late AnimationController _swipeAnimController;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _swipeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _swipeAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onSwipeComplete();
      }
    });
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final me = await ApiService.fetchProfile();
      final myId = ApiService.currentUserId;
      final myGender = me?.gender?.toLowerCase();
      final selectedCity = ApiService.selectedCity;

      // 1. Fetch all raw customers
      final rawCustomers = await ApiService.fetchCustomers();
      
      // 2. Fetch all likes and matches
      final mySwipes = await ApiService.fetchMyLikesAndMatches();

      final Set<String> swipedUserIds = {};
      final List<Map<String, dynamic>> resolvedLiked = [];
      final List<Map<String, dynamic>> resolvedMatched = [];

      for (var swipe in mySwipes) {
        final u1 = swipe['user1Id']?.toString();
        final u2 = swipe['user2Id']?.toString();
        if (u1 == myId) {
          if (u2 != null) {
            swipedUserIds.add(u2);
          }
        }
      }

      final List<Map<String, dynamic>> discoveryProfiles = [];

      for (var c in rawCustomers) {
        try {
          final u = User.fromJson(c);
          if (myId != null && u.id == myId) continue;

          // Filter by selected city
          if (selectedCity != null && selectedCity.isNotEmpty) {
            if (u.city == null || u.city!.toLowerCase() != selectedCity.toLowerCase()) {
              continue;
            }
          }

          // Filter by opposite gender
          if (myGender != null && myGender.isNotEmpty) {
            final uGender = (u.gender ?? '').toLowerCase();
            if (myGender == 'male' || myGender == 'm') {
              if (uGender == 'male' || uGender == 'm') continue;
            } else if (myGender == 'female' || myGender == 'f') {
              if (uGender == 'female' || uGender == 'f') continue;
            }
          }

          // Calculate match percentage dynamically
          final matchPct = ApiService.calculateMatchPercentage(u);

          final profileMap = {
            'id': u.id,
            'name': u.fullName.toUpperCase(),
            'age': u.age ?? 25,
            'vibe': (u.occupation ?? 'Night Owl').toUpperCase(),
            'verified': u.isVerified,
            'distance': '1.2 km away',
            'image': u.profilePhoto ?? 'https://picsum.photos/400/600',
            'isAsset': false,
            'interests': u.interests,
            'matchChance': matchPct / 100.0,
          };

          // Find swipes
          final outgoingSwipes = mySwipes.where(
            (s) => s['user1Id']?.toString() == myId && s['user2Id']?.toString() == u.id,
          ).toList();
          final outgoingSwipe = outgoingSwipes.isNotEmpty ? outgoingSwipes.first : null;

          final incomingSwipes = mySwipes.where(
            (s) => s['user2Id']?.toString() == myId && s['user1Id']?.toString() == u.id,
          ).toList();
          final incomingSwipe = incomingSwipes.isNotEmpty ? incomingSwipes.first : null;

          bool isLiked = false;
          bool isMatched = false;

          if (outgoingSwipe != null) {
            final status = outgoingSwipe['status']?.toString().toLowerCase();
            if (status == 'pending') {
              isLiked = true;
            } else if (status == 'connected') {
              isLiked = true;
              isMatched = true;
            }
          }

          if (incomingSwipe != null) {
            final status = incomingSwipe['status']?.toString().toLowerCase();
            if (status == 'connected') {
              isMatched = true;
            }
          }

          if (isMatched) {
            resolvedMatched.add(profileMap);
          } else if (isLiked) {
            resolvedLiked.add(profileMap);
          }

          if (!swipedUserIds.contains(u.id)) {
            discoveryProfiles.add(profileMap);
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _profiles = discoveryProfiles;
          _likedProfiles.clear();
          _likedProfiles.addAll(resolvedLiked);
          _matchedProfiles.clear();
          _matchedProfiles.addAll(resolvedMatched);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading Discovery data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _swipeAnimController.dispose();
    super.dispose();
  }

  void _onSwipeComplete() {
    if (_profiles.isEmpty) return;

    final swiped = _profiles.removeAt(0);
    final swipedRight = _dragX > 0;
    final action = swipedRight ? _swipeAction : 'nope';

    // Reset default swipe action
    _swipeAction = 'like';

    setState(() {
      _isAnimating = false;
      _dragX = 0;
      _dragY = 0;
      _dragAngle = 0;
    });

    // Make backend swipe call
    ApiService.swipeUser(
      targetUserId: swiped['id'],
      action: action,
    ).then((res) {
      if (res != null) {
        final bool matched = res['matched'] == true;
        if (matched) {
          if (mounted) {
            setState(() {
              _matchedProfiles.add(swiped);
            });
            _showMatchDialog(swiped);
          }
        } else if (swipedRight) {
          if (mounted) {
            setState(() {
              _likedProfiles.add(swiped);
            });
          }
        }
      }
    });
  }

  void _swipeCard(bool liked) {
    if (_profiles.isEmpty || _isAnimating) return;

    setState(() {
      _isAnimating = true;
      _dragX = liked ? 600 : -600;
      _dragY = -30;
      _dragAngle = liked ? 0.25 : -0.25;
    });

    // Wait for card fly-out animation to complete before processing
    Future.delayed(const Duration(milliseconds: 400), () {
      _onSwipeComplete();
    });
  }

  void _showMatchDialog(Map<String, dynamic> matchedUser) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Match',
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.8,
              end: 1.0,
            ).animate(CurvedAnimation(parent: anim1, curve: Curves.elasticOut)),
            child: child,
          ),
        );
      },
      pageBuilder: (context, anim1, anim2) {
        return MatchSuccessDialog(matchedUser: matchedUser);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.only(top: 60, bottom: 120),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 10),
            // Match stats
            _buildMatchStats(),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: LunaraTheme.accentVivid))
                  : _profiles.isEmpty
                      ? _buildEmptyState()
                      : _buildSwipeableCards(),
            ),
            const SizedBox(height: 20),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _statChip(
            icon: Icons.favorite,
            label: '${_likedProfiles.length} Liked',
            color: LunaraTheme.primaryDeep,
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
              );
            },
          ),
          const SizedBox(width: 12),
          _statChip(
            icon: Icons.bolt,
            label: '${_matchedProfiles.length} Matches',
            color: LunaraTheme.accentVivid,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      MatchedProfilesScreen(matchedProfiles: _matchedProfiles),
                ),
              );
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
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwipeableCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background cards (stack effect)
          if (_profiles.length > 2)
            Positioned.fill(
              child: Transform.scale(
                scale: 0.9,
                child: Transform.translate(
                  offset: const Offset(0, 20),
                  child: Opacity(
                    opacity: 0.3,
                    child: MatchCard(profile: _profiles[2]),
                  ),
                ),
              ),
            ),
          if (_profiles.length > 1)
            Positioned.fill(
              child: Transform.scale(
                scale: 0.95,
                child: Transform.translate(
                  offset: const Offset(0, 10),
                  child: Opacity(
                    opacity: 0.6,
                    child: MatchCard(profile: _profiles[1]),
                  ),
                ),
              ),
            ),

          // Top card (swipeable)
          if (_profiles.isNotEmpty)
            Positioned.fill(
              child: GestureDetector(
                onPanStart: (_) {
                  setState(() => _isDragging = true);
                },
                onPanUpdate: (details) {
                  if (_isAnimating) return;
                  setState(() {
                    _dragX += details.delta.dx;
                    _dragY += details.delta.dy;
                    _dragAngle = _dragX * 0.001;
                  });
                },
                onPanEnd: (details) {
                  if (_isAnimating) return;
                  setState(() => _isDragging = false);

                  if (_dragX.abs() > 100) {
                    // Threshold reached — complete the swipe
                    _swipeCard(_dragX > 0);
                  } else {
                    // Snap back
                    setState(() {
                      _dragX = 0;
                      _dragY = 0;
                      _dragAngle = 0;
                    });
                  }
                },
                child: AnimatedContainer(
                  duration: _isDragging
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  transform: Matrix4.translationValues(_dragX, _dragY, 0.0)
                    ..rotateZ(_dragAngle),
                  child: Stack(
                    children: [
                      MatchCard(profile: _profiles.first),
                      // LIKE / NOPE overlay
                      if (_dragX > 30)
                        Positioned(
                          top: 40,
                          left: 20,
                          child: Transform.rotate(
                            angle: -0.3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: LunaraTheme.accentVivid,
                                  width: 3,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'LIKE',
                                style: TextStyle(
                                  color: LunaraTheme.accentVivid,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_dragX < -30)
                        Positioned(
                          top: 40,
                          right: 20,
                          child: Transform.rotate(
                            angle: 0.3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: LunaraTheme.primaryDeep,
                                  width: 3,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'NOPE',
                                style: TextStyle(
                                  color: LunaraTheme.primaryDeep,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, color: Colors.white24, size: 80),
          const SizedBox(height: 16),
          Text(
            'No more profiles nearby',
            style: LunaraTheme.headingStyle.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Loading more...',
            style: LunaraTheme.bodyStyle.copyWith(
              color: LunaraTheme.accentVivid,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DISCOVER',
                style: LunaraTheme.bodyStyle.copyWith(
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
              Text(
                'NIGHT MATCH',
                style: LunaraTheme.headingStyle.copyWith(fontSize: 24),
              ),
            ],
          ),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const MatchSettingsScreen(),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.tune, color: LunaraTheme.accentVivid),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _interactionButton(
            icon: Icons.close,
            color: LunaraTheme.primaryDeep,
            onTap: () {
              _swipeAction = 'nope';
              _swipeCard(false);
            },
            label: 'NOPE',
          ),
          _interactionButton(
            icon: Icons.favorite,
            color: LunaraTheme.accentVivid,
            onTap: () {
              _swipeAction = 'like';
              _swipeCard(true);
            },
            isLarge: true,
            label: 'LIKE',
          ),
          _interactionButton(
            icon: Icons.star,
            color: LunaraTheme.primaryRich,
            onTap: () {
              _swipeAction = 'superlike';
              _swipeCard(true);
            },
            label: 'SUPER',
          ),
        ],
      ),
    );
  }

  Widget _interactionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isLarge = false,
    required String label,
  }) {
    final double size = isLarge ? 80 : 60;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: color, size: isLarge ? 32 : 24),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.7),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
