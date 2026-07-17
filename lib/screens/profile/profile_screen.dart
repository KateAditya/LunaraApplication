import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../widgets/bumble_swipe_widget.dart';
import 'profile_detail_view.dart';
import 'vip_membership_screen.dart';

class ProfileScreen extends StatefulWidget {
  final User? user;
  final List<User>? allProfiles;

  const ProfileScreen({super.key, this.user, this.allProfiles});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? _displayUser;
  User? _me;
  bool _isLoading = false;
  bool _isMe = false;

  List<User> _allProfiles = [];
  int _currentProfileIndex = -1;

  // History for Backtrack (Undo) functionality
  final List<User> _swipeHistory = [];
  final List<bool> _swipeDirections = []; // true for like, false for nope
  final BumbleSwipeController _swipeController = BumbleSwipeController();
  bool _outOfProfiles = false;
  bool _isProfilesLoading = true;
  User? _backtrackedUser;
  String _swipeAction = 'like';

  // ── Like / SuperLike state per profile ───────────────────────────────────────
  // Maps userId → action: 'like' | 'superlike' | 'noped'
  final Map<String, String> _swipedActions = {};

  // ── Plan limit state (loaded once per session) ────────────────────────────────
  int _dailyLikesLimit = 999999; // fallback: unlimited
  int _dailyLikesUsed = 0;
  int _superlikesRemaining = 999999;
  int _superlikesPerCycle = 0;
  int _dailyBacktracksLimit = 3;
  int _dailyBacktracksRemaining = 3;
  int _dailyBacktracksUsed = 0;
  bool _limitsLoaded = false;

  @override
  void initState() {
    super.initState();
    _initUser();
    _loadAllProfiles();
  }

  // ── Load subscription plan limits ────────────────────────────────────────────
  Future<void> _loadPlanLimits() async {
    try {
      final sub = await ApiService.fetchUserSubscription();
      if (!mounted) return;
      // Parse dailyLikes from the nested features map
      final features = sub['features'];
      final dailyLikes = features?['daily_likes']?['limit'] ?? 7;
      final dailyBacktracks = features?['daily_backtracks']?['limit'] ?? 3;
      final usageMap = sub['usage'] as Map? ?? {};
      final dailyLikesUsed = usageMap['daily_likes'] as int? ?? 0;
      final dailyBacktracksUsed = usageMap['daily_backtracks'] as int? ?? 0;

      // superlikesRemaining comes from the subscription object itself
      final subscriptionData = sub['subscription'];
      int superlikesRemaining = 999999;
      int superlikesPerCycle = 0;
      if (subscriptionData != null) {
        superlikesRemaining = (subscriptionData as Map)['superlikesRemaining'] as int? ?? 0;
        final innerPkg = subscriptionData['package'];
        superlikesPerCycle = innerPkg != null ? (innerPkg as Map)['superlikesPerCycle'] as int? ?? 0 : 0;
      }

      setState(() {
        _dailyLikesLimit = dailyLikes == -1 ? 999999 : (dailyLikes as int? ?? 999999);
        _dailyLikesUsed = dailyLikesUsed;
        _superlikesRemaining = superlikesPerCycle == 0 ? 999999 : superlikesRemaining;
        _superlikesPerCycle = superlikesPerCycle;
        _dailyBacktracksLimit = dailyBacktracks == -1 ? 999999 : (dailyBacktracks as int? ?? 3);
        _dailyBacktracksUsed = dailyBacktracksUsed;
        _dailyBacktracksRemaining = _dailyBacktracksLimit == 999999 ? 999999 : (_dailyBacktracksLimit - _dailyBacktracksUsed);
        _limitsLoaded = true;
      });
    } catch (e) {
      debugPrint('[ProfileScreen] Failed to load plan limits: $e');
      if (mounted) setState(() => _limitsLoaded = true);
    }
  }

  Future<void> _loadAllProfiles() async {
    try {
      final me = await ApiService.fetchProfile();
      if (mounted) {
        setState(() {
          _me = me;
        });
      }

      if (widget.allProfiles != null && widget.allProfiles!.isNotEmpty) {
        if (mounted) {
          setState(() {
            _allProfiles = List<User>.from(widget.allProfiles!);
            _isProfilesLoading = false;
            _updateCurrentProfileIndex();
          });
        }
        _loadPlanLimits();
        return;
      }

      final String? myGender = me?.gender?.toLowerCase();
      final String? myId = ApiService.currentUserId;

      final rawCustomers = await ApiService.fetchCustomers();
      final List<User> resolvedUsers = [];
      for (var c in rawCustomers) {
        try {
          final u = User.fromJson(c);
          if (myId != null && u.id == myId) continue;
          if (myGender != null && myGender.isNotEmpty) {
            final uGender = u.gender?.toLowerCase();
            if (uGender == null || uGender == myGender) continue;
          }
          resolvedUsers.add(u);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _allProfiles = resolvedUsers;
          _isProfilesLoading = false;
          _updateCurrentProfileIndex();
        });
      }
    } catch (e) {
      debugPrint('[ProfileScreen] Error loading all profiles: $e');
    }

    // Load plan limits after profiles are ready
    _loadPlanLimits();
  }

  void _updateCurrentProfileIndex() {
    if (_displayUser != null && _allProfiles.isNotEmpty) {
      _currentProfileIndex = _allProfiles.indexWhere(
        (u) => u.id == _displayUser!.id,
      );
      if (_currentProfileIndex == -1) {
        _allProfiles.insert(0, _displayUser!);
        _currentProfileIndex = 0;
      }
    }
  }

  Future<void> _initUser() async {
    if (widget.user != null) {
      setState(() {
        _displayUser = widget.user;
        _isMe = _displayUser!.id == ApiService.currentUserId;
      });
      _updateCurrentProfileIndex();

      final fullUser = await ApiService.fetchProfile(userId: widget.user!.id);
      if (fullUser != null && mounted) {
        setState(() {
          _displayUser = fullUser;
        });
        _updateCurrentProfileIndex();
        // Also check if already liked today
        _checkExistingSwipe(fullUser.id);
      }
    } else {
      setState(() => _isLoading = true);
      final me = await ApiService.fetchProfile();
      if (mounted) {
        setState(() {
          _displayUser = me;
          _isMe = true;
          _isLoading = false;
        });
        _updateCurrentProfileIndex();
      }
    }
  }

  // ── Check if already liked a specific profile today ──────────────────────────
  Future<void> _checkExistingSwipe(String targetUserId) async {
    try {
      final status = await ApiService.fetchSwipeStatus(targetUserId);
      if (!mounted) return;
      if (status['alreadySuperLiked'] == true) {
        setState(() => _swipedActions[targetUserId] = 'superlike');
      } else if (status['alreadyLiked'] == true) {
        setState(() => _swipedActions[targetUserId] = 'like');
      }
      // Also sync limits from this call
      if (!_limitsLoaded) {
        setState(() {
          _dailyLikesLimit = status['dailyLikesLimit'] ?? _dailyLikesLimit;
          _dailyLikesUsed = status['dailyLikesUsed'] ?? _dailyLikesUsed;
          _superlikesRemaining = status['superlikesRemaining'] ?? _superlikesRemaining;
          _superlikesPerCycle = status['superlikesPerCycle'] ?? _superlikesPerCycle;
          _dailyBacktracksLimit = status['dailyBacktracksLimit'] ?? _dailyBacktracksLimit;
          _dailyBacktracksRemaining = status['dailyBacktracksRemaining'] ?? _dailyBacktracksRemaining;
          _dailyBacktracksUsed = status['dailyBacktracksUsed'] ?? _dailyBacktracksUsed;
          _limitsLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('[ProfileScreen] checkExistingSwipe error: $e');
    }
  }

  void _navigateToProfile(int index) {
    if (index < 0 || index >= _allProfiles.length) return;
    final targetUser = _allProfiles[index];
    setState(() {
      _displayUser = targetUser;
      _currentProfileIndex = index;
      _isMe = targetUser.id == ApiService.currentUserId;
    });
    // Fetch full profile details in background
    ApiService.fetchProfile(userId: targetUser.id).then((fullUser) {
      if (fullUser != null && mounted && _displayUser?.id == targetUser.id) {
        setState(() {
          _displayUser = fullUser;
        });
        // Check swipe status for this profile
        _checkExistingSwipe(targetUser.id);
      }
    });
  }

  void _showNextProfile() {
    if (_allProfiles.isEmpty) {
      if (!_isProfilesLoading) {
        setState(() => _outOfProfiles = true);
      }
      return;
    }
    int nextIndex = _currentProfileIndex;
    if (nextIndex < 0 || nextIndex >= _allProfiles.length) nextIndex = 0;
    _navigateToProfile(nextIndex);
  }

  // ── LIKE handler — stay on same page, change button colour ───────────────────
  void _handleLike() {
    if (_displayUser == null) return;
    final targetUser = _displayUser!;
    final targetId = targetUser.id;
    final currentAction = _swipedActions[targetId];

    // If already liked, clicking "like" again removes it (unlike)
    if (currentAction == 'like') {
      setState(() {
        _swipedActions.remove(targetId);
        if (_dailyLikesUsed > 0) _dailyLikesUsed--;
      });
      // Fire API (backend will toggle/destroy)
      ApiService.swipeUser(targetUserId: targetId, action: 'like');
      return;
    }

    // Daily like limit guard (only if not downgrading from superlike)
    if (currentAction != 'superlike' && _dailyLikesUsed >= _dailyLikesLimit) {
      _showLimitReachedSnack();
      return;
    }

    // Optimistically update UI immediately
    setState(() {
      _swipedActions[targetId] = 'like';
      if (currentAction == 'superlike') {
        // Return the superlike count
        if (_superlikesPerCycle > 0) _superlikesRemaining++;
      } else {
        _dailyLikesUsed++;
      }
    });

    // Show in-app notification
    _showLikeNotification(targetUser.firstName, isSuperLike: false);

    // Fire API
    ApiService.swipeUser(targetUserId: targetId, action: 'like').then((res) {
      if (res != null && res['matched'] == true && mounted) {
        _showMatchDialog(targetUser);
      }
    });
  }

  // ── SUPERLIKE handler ─────────────────────────────────────────────────────────
  void _handleSuperLike() {
    if (_displayUser == null) return;
    final targetUser = _displayUser!;
    final targetId = targetUser.id;
    final currentAction = _swipedActions[targetId];

    // If already superliked, clicking "superlike" again removes it
    if (currentAction == 'superlike') {
      setState(() {
        _swipedActions.remove(targetId);
        if (_superlikesPerCycle > 0) _superlikesRemaining++;
        if (_dailyLikesUsed > 0) _dailyLikesUsed--;
      });
      // Fire API (backend will toggle/destroy)
      ApiService.swipeUser(targetUserId: targetId, action: 'superlike');
      return;
    }

    // Superlikes remaining guard (only if not upgrading from like)
    if (currentAction != 'like' && _superlikesPerCycle > 0 && _superlikesRemaining <= 0) {
      _showSuperLikeLimitSnack();
      return;
    }

    // Optimistically update UI immediately
    setState(() {
      _swipedActions[targetId] = 'superlike';
      if (currentAction == 'like') {
        // Upgrading: consume one superlike
        if (_superlikesPerCycle > 0) _superlikesRemaining--;
      } else {
        if (_superlikesPerCycle > 0) _superlikesRemaining--;
        _dailyLikesUsed++;
      }
    });

    // Show in-app notification
    _showLikeNotification(targetUser.firstName, isSuperLike: true);

    // Fire API
    ApiService.swipeUser(targetUserId: targetId, action: 'superlike').then((res) {
      if (res != null && res['matched'] == true && mounted) {
        _showMatchDialog(targetUser);
      }
    });
  }

  // ── NOPE handler — go to next profile ────────────────────────────────────────
  void _handleNope() {
    if (_displayUser == null) return;
    final targetUser = _displayUser!;

    // Mark optimistically
    setState(() {
      _swipedActions[targetUser.id] = 'noped';
      _swipeHistory.add(targetUser);
      _swipeDirections.add(false);
      _allProfiles.removeWhere((u) => u.id == targetUser.id);
    });

    // Fire swipe card animation (which will trigger _handleSwipeCardComplete)
    _swipeAction = 'nope';
    _swipeController.swipe(false);

    ApiService.swipeUser(targetUserId: targetUser.id, action: 'nope');
  }

  // Called by BumbleSwipeWidget when physical card swipe completes
  void _handleSwipe(bool liked) {
    if (_displayUser == null) return;
    final targetUser = _displayUser!;

    if (liked) {
      // Card swiped right from gesture — treat as Like
      final action = _swipeAction == 'superlike' ? 'superlike' : 'like';
      final alreadySwiped = _swipedActions.containsKey(targetUser.id);
      if (!alreadySwiped) {
        if (action == 'superlike') {
          _handleSuperLike();
        } else {
          _handleLike();
        }
      }
      // Don't remove profile from list — user stays on same card
    } else {
      // Card swiped left → Nope: go next
      final targetId = targetUser.id;
      setState(() {
        _swipedActions[targetId] = 'noped';
        _swipeHistory.add(targetUser);
        _swipeDirections.add(false);
        _allProfiles.removeWhere((u) => u.id == targetUser.id);
      });
      _swipeAction = 'like';
      ApiService.swipeUser(targetUserId: targetId, action: 'nope');
      _showNextProfile();
    }
  }

  // ── Snack / in-app notification helpers ──────────────────────────────────────

  void _showLikeNotification(String firstName, {required bool isSuperLike}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isSuperLike
            ? const Color(0xFF7F00FF)
            : const Color(0xFF00B5FF),
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            Icon(
              isSuperLike ? Icons.star : Icons.favorite,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isSuperLike
                    ? 'You Super Liked $firstName! 🌟'
                    : 'You Liked $firstName! ❤️',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAlreadyLikedSnack(String action) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.grey[800],
        duration: const Duration(seconds: 2),
        content: Text(
          action == 'superlike'
              ? 'You already Super Liked this profile today.'
              : 'You already Liked this profile today.',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  void _showLimitReachedSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.red[700],
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Icon(Icons.lock, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "You've reached your daily like limit ($_dailyLikesLimit). Upgrade your plan for more likes!",
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuperLikeLimitSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.purple[700],
        duration: const Duration(seconds: 3),
        content: const Row(
          children: [
            Icon(Icons.star_border, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "No Super Likes remaining. Upgrade your plan to get more!",
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMatchDialog(User matchUser) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1F1235),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: LunaraTheme.electricViolet, width: 2),
            boxShadow: [
              BoxShadow(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.5),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "IT'S A MATCH! 🎉",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "You and ${matchUser.firstName} liked each other.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 45,
                    backgroundColor: Colors.grey[800],
                    backgroundImage:
                        _me?.profilePhoto != null && _me!.profilePhoto!.isNotEmpty
                        ? NetworkImage(_me!.profilePhoto!)
                        : null,
                    child: _me?.profilePhoto == null || _me!.profilePhoto!.isEmpty
                        ? const Icon(Icons.person, color: Colors.white, size: 40)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.favorite, color: Colors.redAccent, size: 40),
                  const SizedBox(width: 16),
                  CircleAvatar(
                    radius: 45,
                    backgroundColor: Colors.grey[800],
                    backgroundImage:
                        matchUser.profilePhoto != null && matchUser.profilePhoto!.isNotEmpty
                        ? NetworkImage(matchUser.profilePhoto!)
                        : null,
                    child: matchUser.profilePhoto == null || matchUser.profilePhoto!.isEmpty
                        ? const Icon(Icons.person, color: Colors.white, size: 40)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: LunaraTheme.electricViolet,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 5,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "SAY HELLO",
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("KEEP SWIPING", style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBacktrackUpgradePrompt() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF140C26),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
          border: Border(
            top: BorderSide(color: Color(0xFF7F00FF), width: 1.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Icon(
              Icons.history,
              size: 70,
              color: Color(0xFF7F00FF),
            ),
            const SizedBox(height: 24),
            const Text(
              "Out of Backtracks! ⚡",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "You've reached your daily backtrack limit of 3. Upgrade your subscription to VIP to get unlimited backtracks and see previous profiles!",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F00FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const VIPMembershipScreen(),
                    ),
                  ).then((_) {
                    _loadPlanLimits();
                  });
                },
                child: const Text(
                  "GET VIP MEMBERSHIP",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Maybe Later",
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _undoLastSwipe() {
    if (_swipeHistory.isEmpty) return;

    if (_dailyBacktracksRemaining <= 0 && _dailyBacktracksLimit != 999999) {
      _showBacktrackUpgradePrompt();
      return;
    }

    final prevUser = _swipeHistory.last;

    ApiService.backtrackSwipe(prevUser.id).then((res) {
      if (res != null && res['limitReached'] == true) {
        _showBacktrackUpgradePrompt();
        return;
      }

      if (mounted) {
        setState(() {
          if (_dailyBacktracksLimit != 999999) {
            _dailyBacktracksRemaining = res?['remaining'] ?? (_dailyBacktracksRemaining - 1);
            _dailyBacktracksUsed = res?['used'] ?? (_dailyBacktracksUsed + 1);
          }

          _swipeHistory.removeLast();
          _swipeDirections.removeLast();
          _backtrackedUser = prevUser;
          _swipedActions.remove(prevUser.id);
        });

        final backtrackWidget = ProfileDetailView(
          key: ValueKey(prevUser.id),
          user: prevUser,
          isMe: prevUser.id == ApiService.currentUserId,
          swipedAction: _swipedActions[prevUser.id],
          isLikeDisabled: _dailyLikesUsed >= _dailyLikesLimit,
          isSuperLikeDisabled: _superlikesPerCycle > 0 && _superlikesRemaining <= 0,
          onNope: () => _handleNope(),
          onLike: () => _handleLike(),
          onSuper: () => _handleSuperLike(),
          onBacktrack: _undoLastSwipe,
          canBacktrack: _swipeHistory.isNotEmpty,
        );

        _swipeController.backtrack(false, backtrackWidget);
      }
    });
  }

  void _handleBacktrackComplete() {
    if (_backtrackedUser != null) {
      setState(() {
        _displayUser = _backtrackedUser;
        _currentProfileIndex = _allProfiles.indexWhere(
          (u) => u.id == _backtrackedUser!.id,
        );
        _isMe = _backtrackedUser!.id == ApiService.currentUserId;
        _backtrackedUser = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
        ),
      );
    }

    final emptyStateWidget = Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No more profiles to show.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );

    if (_outOfProfiles) return emptyStateWidget;

    if (_displayUser == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('PROFILE')),
        body: const Center(child: Text('User not found')),
      );
    }

    if (_isMe) {
      return ProfileDetailView(
        key: ValueKey(_displayUser!.id),
        user: _displayUser!,
        isMe: true,
        swipedAction: null,
        isLikeDisabled: false,
        isSuperLikeDisabled: false,
        onNope: null,
        onLike: null,
        onSuper: null,
        onBacktrack: null,
        canBacktrack: false,
      );
    }

    final currentUserId = _displayUser!.id;
    final currentSwipedAction = _swipedActions[currentUserId];
    final isLikeDisabled = _dailyLikesUsed >= _dailyLikesLimit;
    final isSuperLikeDisabled = _superlikesPerCycle > 0 && _superlikesRemaining <= 0;

    final currentProfileWidget = ProfileDetailView(
      key: ValueKey(_displayUser!.id),
      user: _displayUser!,
      isMe: _isMe,
      swipedAction: currentSwipedAction,
      isLikeDisabled: isLikeDisabled,
      isSuperLikeDisabled: isSuperLikeDisabled,
      onNope: () => _handleNope(),
      onLike: () => _handleLike(),
      onSuper: () => _handleSuperLike(),
      onBacktrack: _undoLastSwipe,
      canBacktrack: _swipeHistory.isNotEmpty,
    );

    // Next profile (shown behind current card) — only for unswipped profiles
    User? nextUser;
    if (_allProfiles.isNotEmpty) {
      if (_currentProfileIndex < 0 || _currentProfileIndex >= _allProfiles.length) {
        nextUser = _allProfiles[0];
      } else {
        final nextIdx = (_currentProfileIndex + 1) % _allProfiles.length;
        if (nextIdx != _currentProfileIndex) {
          nextUser = _allProfiles[nextIdx];
        }
      }
    }

    final Widget? nextProfileWidget = nextUser != null
        ? ProfileDetailView(
            key: ValueKey('next_${nextUser.id}'),
            user: nextUser,
            isMe: nextUser.id == ApiService.currentUserId,
            swipedAction: null,
            isLikeDisabled: false,
            isSuperLikeDisabled: false,
            onNope: null,
            onLike: null,
            onSuper: null,
            onBacktrack: null,
            canBacktrack: false,
          )
        : null;

    final Widget backgroundWidget = _isProfilesLoading
        ? const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
            ),
          )
        : emptyStateWidget;

    return Stack(
      children: [
        if (nextProfileWidget == null) backgroundWidget,
        BumbleSwipeWidget(
          controller: _swipeController,
          currentWidget: currentProfileWidget,
          nextWidget: nextProfileWidget,
          onSwipeLeft: () => _handleSwipe(false),
          onSwipeRight: () => _handleSwipe(true),
          onSwipePrev: _handleBacktrackComplete,
        ),
      ],
    );
  }
}
