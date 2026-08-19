import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../widgets/bumble_swipe_widget.dart';
import 'profile_detail_view.dart';
import '../../widgets/subscription_limit_dialog.dart';
import '../../services/subscription_provider.dart';

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
            _allProfiles = widget.allProfiles!;
            
            // Initialize local swipedActions map from backend state to ensure correct UI init
            for (var u in _allProfiles) {
              if (u.isSuperLiked) {
                _swipedActions[u.id] = 'superlike';
              } else if (u.isLiked) {
                _swipedActions[u.id] = 'like';
              }
            }

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
          resolvedUsers.add(u);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _allProfiles = resolvedUsers;
          
          // Initialize local swipedActions map from backend state to ensure correct UI init
          for (var u in _allProfiles) {
            if (u.isSuperLiked) {
              _swipedActions[u.id] = 'superlike';
            } else if (u.isLiked) {
              _swipedActions[u.id] = 'like';
            }
          }

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
    if (ApiService.authToken == null) {
      await ApiService.initAuthToken();
    }
    final String? myId = ApiService.currentUserId ?? ApiService.cachedCurrentUser?.id;

    if (widget.user != null) {
      final bool isSelf = myId != null &&
          myId.isNotEmpty &&
          (widget.user!.id == myId || widget.user!.id.isEmpty);

      setState(() {
        _displayUser = widget.user;
        _isMe = isSelf;
        if (widget.user!.isSuperLiked) {
          _swipedActions[widget.user!.id] = 'superlike';
        } else if (widget.user!.isLiked) {
          _swipedActions[widget.user!.id] = 'like';
        }
      });
      _updateCurrentProfileIndex();

      if (!isSelf && widget.user!.id.isNotEmpty) {
        _checkExistingSwipe(widget.user!.id);
      }

      final String fetchId = widget.user!.id.isNotEmpty ? widget.user!.id : (myId ?? '');
      final fullUser = await ApiService.fetchProfile(userId: fetchId.isNotEmpty ? fetchId : null);
      if (fullUser != null && mounted) {
        setState(() {
          _displayUser = fullUser;
          if (isSelf || (myId != null && fullUser.id == myId)) {
            _isMe = true;
          }
          if (fullUser.isSuperLiked) {
            _swipedActions[fullUser.id] = 'superlike';
          } else if (fullUser.isLiked) {
            _swipedActions[fullUser.id] = 'like';
          }
        });
        _updateCurrentProfileIndex();
        if (!_isMe) {
          _checkExistingSwipe(fullUser.id);
        }
      }
    } else {
      setState(() => _isLoading = true);
      final me = ApiService.cachedCurrentUser;
      if (me != null) {
        setState(() {
          _displayUser = me;
          _isMe = true;
          _isLoading = false;
        });
        _updateCurrentProfileIndex();
      }

      final fetchedMe = await ApiService.fetchProfile();
      if (mounted) {
        final finalUser = fetchedMe ?? me ?? ApiService.cachedCurrentUser;
        if (finalUser != null) {
          setState(() {
            _displayUser = finalUser;
            _isMe = true;
            _isLoading = false;
          });
          _updateCurrentProfileIndex();
        } else {
          // Robust fallback: fetch customers to resolve user profile if direct fetch is empty
          final customers = await ApiService.fetchCustomers();
          if (customers.isNotEmpty && mounted) {
            final String? currentId = ApiService.currentUserId;
            Map<String, dynamic>? userMap;
            if (currentId != null && currentId.isNotEmpty) {
              try {
                userMap = customers.firstWhere(
                  (c) => c['id'] == currentId || c['_id'] == currentId,
                );
              } catch (_) {}
            }
            userMap ??= customers.first;
            final fallbackUser = User.fromJson(userMap);
            ApiService.cachedCurrentUser = fallbackUser;
            setState(() {
              _displayUser = fallbackUser;
              _isMe = true;
              _isLoading = false;
            });
            _updateCurrentProfileIndex();
          } else if (mounted) {
            final fallback = me ?? ApiService.cachedCurrentUser;
            setState(() {
              _displayUser = fallback;
              _isLoading = false;
            });
          }
        }
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
  // Returns a Future so callers (e.g. ProfileDetailView's own button) can
  // await the real server-confirmed outcome instead of guessing/optimistically
  // marking themselves as liked before this resolves.
  Future<void> _handleLike() async {
    if (_displayUser == null) return;
    final targetUser = _displayUser!;
    final targetId = targetUser.id;
    final currentAction = _swipedActions[targetId];

    // If already liked, clicking "like" again retains the like
    if (currentAction == 'like') {
      _showAlreadyLikedSnack(targetUser.firstName, isSuperLike: false);
      return;
    }

    // Daily like limit guard (only if not downgrading from superlike)
    if (currentAction != 'superlike' && _dailyLikesUsed >= _dailyLikesLimit) {
      _showLimitReachedSnack();
      return;
    }

    // Fire API first — only apply optimistic UI once the server confirms
    // the like was actually accepted (previously this mutated state before
    // the call resolved, so a rejected like still showed as successful).
    final res = await ApiService.swipeUser(targetUserId: targetId, action: 'like');
    if (!mounted) return;

    if (res == null || res['limitReached'] == true) {
      _showLimitReachedSnack();
      return;
    }

    setState(() {
      _swipedActions[targetId] = 'like';
      if (currentAction == 'superlike') {
        // Return the superlike count
        if (_superlikesPerCycle > 0) _superlikesRemaining++;
      } else {
        _dailyLikesUsed++;
      }
    });

    // SubscriptionProvider (used by profile_hub_screen.dart and others to
    // display remaining likes/superlikes) is a process-lifetime singleton
    // with its own cache — nothing else in the swipe flow ever invalidated
    // it, so those displays could keep showing a stale count long after it
    // actually changed. Force a refetch so it stays accurate.
    unawaited(SubscriptionProvider.instance.refreshAfterPurchase());

    _showLikeNotification(targetUser.firstName, isSuperLike: false);

    if (res['matched'] == true) {
      _showMatchDialog(targetUser);
    }
  }

  // ── SUPERLIKE handler ─────────────────────────────────────────────────────────
  Future<void> _handleSuperLike() async {
    if (_displayUser == null) return;
    final targetUser = _displayUser!;
    final targetId = targetUser.id;
    final currentAction = _swipedActions[targetId];

    // If already superliked, clicking "superlike" again retains it
    if (currentAction == 'superlike') {
      _showAlreadyLikedSnack(targetUser.firstName, isSuperLike: true);
      return;
    }

    // Superlikes remaining guard (always validate against plan limit)
    if (_superlikesPerCycle > 0 && _superlikesRemaining <= 0) {
      _showSuperLikeLimitSnack();
      return;
    }

    // Fire API first — only apply optimistic UI once the server confirms
    // the superlike was actually accepted.
    final res = await ApiService.swipeUser(targetUserId: targetId, action: 'superlike');
    if (!mounted) return;

    if (res == null || res['limitReached'] == true) {
      _showSuperLikeLimitSnack();
      return;
    }

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

    unawaited(SubscriptionProvider.instance.refreshAfterPurchase());

    _showLikeNotification(targetUser.firstName, isSuperLike: true);

    if (res['matched'] == true) {
      _showMatchDialog(targetUser);
    }
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

    _swipeController.swipe(false);

    ApiService.swipeUser(targetUserId: targetUser.id, action: 'nope');
  }

  // Called by BumbleSwipeWidget when physical card swipe completes
  void _handleSwipe(bool liked) {
    if (_displayUser == null) return;
    final targetUser = _displayUser!;

    if (liked) {
      // Swiped right from gesture — navigate to next profile without auto-liking
      final targetId = targetUser.id;
      setState(() {
        _swipedActions[targetId] = 'passed';
        _swipeHistory.add(targetUser);
        _swipeDirections.add(true);
        _allProfiles.removeWhere((u) => u.id == targetUser.id);
      });
      _showNextProfile();
    } else {
      // Card swiped left → Nope: go next
      final targetId = targetUser.id;
      setState(() {
        _swipedActions[targetId] = 'noped';
        _swipeHistory.add(targetUser);
        _swipeDirections.add(false);
        _allProfiles.removeWhere((u) => u.id == targetUser.id);
      });
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
        elevation: 0,
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 90),
        duration: const Duration(seconds: 2),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            gradient: isSuperLike
                ? const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                  )
                : LunaraTheme.purpleGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: isSuperLike
                    ? const Color(0xFFFFD700).withValues(alpha: 0.4)
                    : LunaraTheme.electricViolet.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                isSuperLike ? Icons.star_rounded : Icons.favorite_rounded,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isSuperLike
                      ? 'You Super Liked $firstName! 🌟'
                      : 'You Liked $firstName! ❤️',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAlreadyLikedSnack(String firstName, {required bool isSuperLike}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            gradient: isSuperLike
                ? const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                  )
                : LunaraTheme.purpleGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: isSuperLike
                    ? const Color(0xFFFFD700).withValues(alpha: 0.4)
                    : LunaraTheme.electricViolet.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                isSuperLike ? Icons.star_rounded : Icons.favorite_rounded,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isSuperLike
                      ? 'You already Super Liked $firstName! 🌟'
                      : 'You already Liked $firstName! ❤️',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  void _showLimitReachedSnack() {
    if (!mounted) return;
    showSubscriptionLimitDialog(context, feature: SubLimitFeature.dailyLikes);
  }

  void _showSuperLikeLimitSnack() {
    if (!mounted) return;
    showSubscriptionLimitDialog(context, feature: SubLimitFeature.superLike);
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
    if (!mounted) return;
    showSubscriptionLimitDialog(context, feature: SubLimitFeature.backtrack).then((_) {
      _loadPlanLimits();
    });
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
          if (!_allProfiles.any((u) => u.id == prevUser.id)) {
            _allProfiles.insert(0, prevUser);
          }
          _outOfProfiles = false;
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
        if (!_allProfiles.any((u) => u.id == _backtrackedUser!.id)) {
          _allProfiles.insert(0, _backtrackedUser!);
        }
        _currentProfileIndex = _allProfiles.indexWhere(
          (u) => u.id == _backtrackedUser!.id,
        );
        if (_currentProfileIndex == -1) {
          _currentProfileIndex = 0;
        }
        _isMe = _backtrackedUser!.id == ApiService.currentUserId;
        _backtrackedUser = null;
        _outOfProfiles = false;
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
      final cached = ApiService.cachedCurrentUser;
      if (cached != null) {
        return ProfileDetailView(
          key: ValueKey(cached.id),
          user: cached,
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
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('PROFILE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
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
              const Icon(Icons.person_off_rounded, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Unable to load profile',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800]),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Please check your network connection and try again.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  setState(() => _isLoading = true);
                  await ApiService.initAuthToken();
                  await _initUser();
                  await _loadAllProfiles();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: LunaraTheme.electricViolet,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
        ),
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
