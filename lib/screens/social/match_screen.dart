import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/match_card.dart';
import 'match_settings_screen.dart';
import 'matched_profiles_screen.dart';
import 'people_who_liked_you_screen.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../services/subscription_provider.dart';
import '../../widgets/subscription_limit_dialog.dart';
import '../profile/vip_membership_screen.dart';

class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _profiles = [];
  final List<Map<String, dynamic>> _likedProfiles = [];
  final List<Map<String, dynamic>> _superLikedProfiles = [];
  final List<Map<String, dynamic>> _matchedProfiles = [];
  final List<Map<String, dynamic>> _swipedHistory = [];
  bool _isLoading = true;
  String _swipeAction = 'like';
  int _whoLikedCount = 0;
  int _whoLikedSuperCount = 0;
  bool _whoLikedLocked = true;

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
      if (ApiService.currentUserId == null) {
        await ApiService.fetchProfile();
      }
      final myId = ApiService.currentUserId;
      final selectedCity = ApiService.selectedCity;

      // Fetch customers, existing likes/matches, and who-liked summary in parallel
      final results = await Future.wait([
        ApiService.fetchCustomers(),
        ApiService.fetchMyLikesAndMatches(),
        ApiService.fetchWhoLikedSummary(),
      ]);

      final rawCustomers = results[0] as List<dynamic>;
      final mySwipes = results[1] as List<dynamic>;
      final whoLikedSummary = (results[2] as Map<String, dynamic>?) ?? {};
      final whoLikedTotal = whoLikedSummary['totalCount'] is int
          ? whoLikedSummary['totalCount'] as int
          : int.tryParse(whoLikedSummary['totalCount']?.toString() ?? '0') ?? 0;
      final whoLikedSuper = whoLikedSummary['superlikesCount'] is int
          ? whoLikedSummary['superlikesCount'] as int
          : int.tryParse(whoLikedSummary['superlikesCount']?.toString() ?? '0') ?? 0;
      final whoLikedIsLocked = whoLikedSummary['locked'] == true;

      final Set<String> swipedUserIds = {};
      final Map<String, dynamic> outgoingByTargetId = {};
      final Map<String, dynamic> incomingBySenderId = {};
      final List<Map<String, dynamic>> resolvedLiked = [];
      final List<Map<String, dynamic>> resolvedSuperLiked = [];
      final List<Map<String, dynamic>> resolvedMatched = [];

      // O(M) single-pass indexing into HashMaps
      for (var swipe in mySwipes) {
        final u1 = swipe['user1Id']?.toString();
        final u2 = swipe['user2Id']?.toString();
        if (u1 == myId && u2 != null) {
          swipedUserIds.add(u2);
          outgoingByTargetId[u2] = swipe;
        }
        if (u2 == myId && u1 != null) {
          incomingBySenderId[u1] = swipe;
        }
      }

      final List<Map<String, dynamic>> discoveryProfiles = [];

      for (var c in rawCustomers) {
        try {
          final u = User.fromJson(c);
          if (myId != null && u.id == myId) continue;

          // Filter by selected city
          if (selectedCity != null && selectedCity.isNotEmpty) {
            if (u.city == null ||
                u.city!.toLowerCase() != selectedCity.toLowerCase()) {
              continue;
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

          // O(1) instantaneous lookup via HashMap (eliminates O(N*M) nested scans)
          final outgoingSwipe = outgoingByTargetId[u.id];
          final incomingSwipe = incomingBySenderId[u.id];

          bool isLiked = false;
          bool isSuperLiked = false;
          bool isMatched = false;

          if (outgoingSwipe != null) {
            final status = outgoingSwipe['status']?.toString().toLowerCase();
            final reason = outgoingSwipe['matchReason']?.toString().toLowerCase();
            final isSuper = reason == 'superlike';

            if (status == 'pending') {
              if (isSuper) {
                isSuperLiked = true;
              } else {
                isLiked = true;
              }
            } else if (status == 'connected') {
              isLiked = true;
              isMatched = true;
              if (isSuper) {
                isSuperLiked = true;
              }
            }
          }

          if (incomingSwipe != null) {
            final status = incomingSwipe['status']?.toString().toLowerCase();
            final reason = incomingSwipe['matchReason']?.toString().toLowerCase();
            final isSuper = reason == 'superlike';
            if (status == 'connected') {
              isMatched = true;
              if (isSuper) {
                isSuperLiked = true;
              }
            }
          }

          if (isMatched) {
            resolvedMatched.add(profileMap);
          } else if (isSuperLiked) {
            resolvedSuperLiked.add(profileMap);
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
          _superLikedProfiles.clear();
          _superLikedProfiles.addAll(resolvedSuperLiked);
          _matchedProfiles.clear();
          _matchedProfiles.addAll(resolvedMatched);
          _whoLikedCount = whoLikedTotal;
          _whoLikedSuperCount = whoLikedSuper;
          _whoLikedLocked = whoLikedIsLocked;
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
    _swipedHistory.add(swiped);
    final swipedRight = _dragX > 0;
    final action = _swipeAction;

    // Reset default swipe action
    _swipeAction = 'like';

    setState(() {
      _isAnimating = false;
      _dragX = 0;
      _dragY = 0;
      _dragAngle = 0;
    });

    // Make backend swipe call
    ApiService.swipeUser(targetUserId: swiped['id'], action: action).then((
      res,
    ) {
      if (res != null) {
        if (res['limitReached'] == true) {
          final isElite = SubscriptionProvider.instance.isElite;
          final hasUnlimitedLikes = SubscriptionProvider.instance.hasUnlimitedLikes;

          // Suppress only if user truly has unlimited likes or superlikes configured
          if ((action == 'like' && hasUnlimitedLikes) || (action == 'superlike' && isElite)) {
            debugPrint('[MatchScreen] Suppressed limitReached for user with unlimited: action=$action');
          } else {
            // Revert optimistic consumption
            if (action == 'superlike') {
              SubscriptionProvider.instance.rollbackConsume(VipAction.superlike);
            } else if (action == 'like') {
              SubscriptionProvider.instance.rollbackConsume(VipAction.like);
            }
            if (_swipedHistory.isNotEmpty) _swipedHistory.removeLast();

            if (mounted) {
              setState(() {
                _profiles.insert(0, swiped);
              });
              showSubscriptionLimitDialog(
                context,
                feature: action == 'superlike' ? SubLimitFeature.superLike : SubLimitFeature.dailyLikes,
                customMessage: res['message'],
              );
            }
            return;
          }
        }

        final bool matched = res['matched'] == true;
        if (matched) {
          if (mounted) {
            setState(() {
              _matchedProfiles.add(swiped);
            });
          }
        } else if (swipedRight) {
          if (mounted) {
            setState(() {
              if (action == 'superlike') {
                _superLikedProfiles.add(swiped);
              } else {
                _likedProfiles.add(swiped);
              }
            });
          }
        }

        // 75% Limit Usage Warning notification & alert
        if (res['usageWarning'] != null && res['usageWarning']['triggered'] == true && mounted) {
          final isElite = SubscriptionProvider.instance.isElite;
          final isPaid = SubscriptionProvider.instance.isPaid;
          final feature = res['usageWarning']['feature']?.toString() ?? '';

          // Never show upgrade prompt to top tier (Elite) or for daily likes to VIP users
          if (!isElite && !(isPaid && feature == 'daily_likes')) {
            final warnMsg = res['usageWarning']['message']?.toString() ?? 'Limit warning';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Expanded(
                      child: Text(
                        warnMsg,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VIPMembershipScreen(initialTabIndex: isPaid ? 1 : 0),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isPaid ? 'TOP UP' : 'UPGRADE',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF7F00FF),
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        }

        // Sync actual quota counts from the server after every swipe
        // (background, no await — keeps UI snappy while keeping badges accurate)
        SubscriptionProvider.instance.refresh();
      }
    });
  }


  void _swipeCard(bool liked, {String? customAction}) {
    if (_profiles.isEmpty || _isAnimating) return;

    final action = customAction ?? (liked ? _swipeAction : 'nope');

    // ── Instant O(1) in-memory quota guard ──
    if (action == 'like') {
      final validation = SubscriptionProvider.instance.validateAction(VipAction.like);
      if (!validation.allowed) {
        setState(() {
          _dragX = 0;
          _dragY = 0;
          _dragAngle = 0;
          _isDragging = false;
        });
        showSubscriptionLimitDialog(
          context,
          feature: SubLimitFeature.dailyLikes,
          customMessage: validation.message,
        );
        return;
      }
      SubscriptionProvider.instance.optimisticConsume(VipAction.like);
    } else if (action == 'superlike') {
      final validation = SubscriptionProvider.instance.validateAction(VipAction.superlike);
      if (!validation.allowed) {
        setState(() {
          _dragX = 0;
          _dragY = 0;
          _dragAngle = 0;
          _isDragging = false;
        });
        showSubscriptionLimitDialog(
          context,
          feature: SubLimitFeature.superLike,
          customMessage: validation.message,
        );
        return;
      }
      SubscriptionProvider.instance.optimisticConsume(VipAction.superlike);
    }

    _swipeAction = action;

    setState(() {
      _isAnimating = true;
      _dragX = liked ? 600 : -600;
      _dragY = -30;
      _dragAngle = liked ? 0.25 : -0.25;
    });

    // Wait for card fly-out animation to complete before processing
    Future.delayed(const Duration(milliseconds: 300), () {
      _onSwipeComplete();
    });
  }

  Future<void> _rewindLastSwipe() async {
    if (_swipedHistory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No previous swipe to rewind'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final validation = SubscriptionProvider.instance.validateAction(VipAction.backtrack);
    if (!validation.allowed) {
      showSubscriptionLimitDialog(
        context,
        feature: SubLimitFeature.backtrack,
        customMessage: validation.message,
      );
      return;
    }

    final restored = _swipedHistory.removeLast();
    final targetUserId = (restored['id'] ?? restored['_id'])?.toString() ?? '';

    // Optimistically restore to UI
    setState(() {
      _profiles.insert(0, restored);
    });
    SubscriptionProvider.instance.optimisticConsume(VipAction.backtrack);

    if (targetUserId.isNotEmpty) {
      final res = await ApiService.backtrackSwipe(targetUserId);
      if (res != null && res['limitReached'] == true) {
        // Rollback
        SubscriptionProvider.instance.rollbackConsume(VipAction.backtrack);
        if (mounted) {
          setState(() {
            _profiles.remove(restored);
            _swipedHistory.add(restored);
          });
          showSubscriptionLimitDialog(
            context,
            feature: SubLimitFeature.backtrack,
            customMessage: res['message'],
          );
        }
        return;
      }
    }
    SubscriptionProvider.instance.refresh();
  }

  void _onBoostTap() {
    final provider = SubscriptionProvider.instance;
    final validation = provider.validateAction(VipAction.boost);
    if (!validation.allowed) {
      showSubscriptionLimitDialog(
        context,
        feature: SubLimitFeature.boost,
        customMessage: validation.message,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161622),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Text('⚡', style: TextStyle(fontSize: 24)),
            SizedBox(width: 8),
            Text('Activate Boost?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          provider.isElite
              ? 'As an Elite VIP, you have unlimited Profile Boosts! Boost your profile for 30 minutes?'
              : 'Boost puts your profile at the top of discover for 30 minutes! (${provider.boostsRemaining} remaining)',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB703),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              provider.optimisticConsume(VipAction.boost);
              final res = await ApiService.useBoost();
              if (res != null && res['success'] == true) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('⚡ Boost activated! Your profile is in the spotlight for 30 minutes!'),
                      backgroundColor: Color(0xFF7F00FF),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
                provider.refresh();
              } else {
                provider.rollbackConsume(VipAction.boost);
                if (mounted) {
                  showSubscriptionLimitDialog(
                    context,
                    feature: SubLimitFeature.boost,
                    customMessage: res?['message'],
                  );
                }
              }
            },
            child: const Text('ACTIVATE', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
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
            // Match stats & Who Liked Teaser
            _buildMatchStats(),
            const SizedBox(height: 10),
            _buildDailyLikesQuota(),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: LunaraTheme.accentVivid,
                      ),
                    )
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

  Widget _buildDailyLikesQuota() {
    return AnimatedBuilder(
      animation: SubscriptionProvider.instance,
      builder: (context, _) {
        final provider = SubscriptionProvider.instance;
        if (provider.hasUnlimitedLikes) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFFB703).withValues(alpha: 0.15),
                  const Color(0xFFFF8800).withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFB703).withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.all_inclusive, color: Color(0xFFFFB703), size: 13),
                SizedBox(width: 5),
                Text(
                  'UNLIMITED LIKES • VIP ACTIVE',
                  style: TextStyle(
                    color: Color(0xFFFFB703),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          );
        }

        final remaining = provider.likesRemaining;
        final limit = provider.status.dailyLikesLimitInt;
        final isOut = remaining <= 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isOut
                ? Colors.redAccent.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isOut
                  ? Colors.redAccent.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite,
                color: isOut ? Colors.redAccent : LunaraTheme.accentVivid,
                size: 12,
              ),
              const SizedBox(width: 6),
              Text(
                isOut
                    ? '0 / $limit likes remaining today • Resets at midnight'
                    : '$remaining / $limit likes remaining today',
                style: TextStyle(
                  color: isOut ? const Color(0xFFFF5252) : Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMatchStats() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Who Liked You Teaser Chip
          GestureDetector(
            onTap: () {
              if (_whoLikedLocked) {
                showSubscriptionLimitDialog(
                  context,
                  feature: SubLimitFeature.whoLikedMe,
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PeopleWhoLikedYouScreen(),
                  ),
                ).then((_) => _loadData());
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _whoLikedLocked
                      ? [
                          const Color(0xFF7F00FF).withValues(alpha: 0.25),
                          const Color(0xFFFF007F).withValues(alpha: 0.25),
                        ]
                      : [
                          const Color(0xFFFF007F).withValues(alpha: 0.35),
                          const Color(0xFFFF5252).withValues(alpha: 0.35),
                        ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _whoLikedLocked
                      ? const Color(0xFFFF007F).withValues(alpha: 0.6)
                      : const Color(0xFFFF5252),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF007F).withValues(alpha: 0.25),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite, color: Color(0xFFFF007F), size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '$_whoLikedCount Likes You${_whoLikedSuperCount > 0 ? " (★ $_whoLikedSuperCount)" : ""}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _whoLikedLocked ? Icons.lock : Icons.arrow_forward_ios,
                    color: _whoLikedLocked ? const Color(0xFFFFB703) : Colors.white70,
                    size: 11,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
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
          const SizedBox(width: 8),
          _statChip(
            icon: Icons.star,
            label: '${_superLikedProfiles.length} Super',
            color: LunaraTheme.primaryRich,
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
              );
            },
          ),
          const SizedBox(width: 8),
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
    return AnimatedBuilder(
      animation: SubscriptionProvider.instance,
      builder: (context, _) {
        final provider = SubscriptionProvider.instance;
        final superRemaining = provider.superlikesRemaining;
        final backtrackRemaining = provider.backtracksRemaining;
        final superIsUnlimited = provider.isElite || provider.status.isUnlimitedSuperlikes || superRemaining >= 9999;
        final backtrackIsUnlimited = provider.isElite || provider.status.hasUnlimitedBacktracks || backtrackRemaining >= 9999;
        final superLabel = superIsUnlimited ? '∞' : '$superRemaining';
        final backtrackLabel = backtrackIsUnlimited ? '∞' : '$backtrackRemaining';
        final superExhausted = !superIsUnlimited && superRemaining <= 0;
        final backtrackExhausted = !backtrackIsUnlimited && backtrackRemaining <= 0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _interactionButton(
                icon: Icons.replay,
                color: backtrackExhausted
                    ? const Color(0xFFFFB703).withValues(alpha: 0.4)
                    : const Color(0xFFFFB703),
                onTap: _rewindLastSwipe,
                label: 'REWIND',
                badgeText: backtrackLabel,
                badgeColor: backtrackExhausted ? Colors.grey : const Color(0xFFFFB703),
              ),
              _interactionButton(
                icon: Icons.close,
                color: LunaraTheme.primaryDeep,
                onTap: () {
                  _swipeCard(false, customAction: 'nope');
                },
                label: 'NOPE',
              ),
              _interactionButton(
                icon: Icons.favorite,
                color: LunaraTheme.accentVivid,
                onTap: () {
                  _swipeCard(true, customAction: 'like');
                },
                isLarge: true,
                label: 'LIKE',
              ),
              _interactionButton(
                icon: Icons.star,
                color: superExhausted
                    ? LunaraTheme.primaryRich.withValues(alpha: 0.4)
                    : LunaraTheme.primaryRich,
                onTap: () {
                  _swipeCard(true, customAction: 'superlike');
                },
                label: 'SUPER',
                badgeText: superLabel,
                badgeColor: superExhausted ? Colors.grey : LunaraTheme.primaryRich,
              ),
              _buildBoostButton(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _interactionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isLarge = false,
    required String label,
    String? badgeText,
    Color? badgeColor,
  }) {
    final double size = isLarge ? 74 : 54;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
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
                      color: color.withValues(alpha: 0.25),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(icon, color: color, size: isLarge ? 30 : 22),
              ),
            ),
            // Remaining count badge
            if (badgeText != null)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? color).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.8),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildBoostButton(SubscriptionProvider provider) {
    final boostsRemaining = provider.boostsRemaining;
    final boostIsUnlimited =
        provider.isElite || provider.status.isUnlimitedBoosts || boostsRemaining >= 9999;
    final boostLabel = boostIsUnlimited ? '∞' : '$boostsRemaining';
    final boostExhausted = !boostIsUnlimited && boostsRemaining <= 0;
    const boostColor = Color(0xFF00E5FF);

    return _interactionButton(
      icon: Icons.bolt,
      color: boostExhausted ? boostColor.withValues(alpha: 0.4) : boostColor,
      onTap: _onBoostTap,
      label: 'BOOST',
      badgeText: boostLabel,
      badgeColor: boostExhausted ? Colors.grey : boostColor,
    );
  }
}
