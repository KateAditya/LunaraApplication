import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../widgets/bumble_swipe_widget.dart';
import 'profile_detail_view.dart';
import '../../widgets/subscription_limit_dialog.dart';
import '../../services/subscription_provider.dart';
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
    ApiService.profileUpdateNotifier.addListener(_onProfileUpdated);
    SubscriptionProvider.instance.addListener(_onSubUpdated);
    _initUser();
    _loadAllProfiles();
  }

  @override
  void dispose() {
    ApiService.profileUpdateNotifier.removeListener(_onProfileUpdated);
    SubscriptionProvider.instance.removeListener(_onSubUpdated);
    super.dispose();
  }

  void _onSubUpdated() {
    if (mounted) setState(() {});
  }

  void _onProfileUpdated() {
    ApiService.fetchProfile(forceRefresh: true).then((me) {
      if (mounted && me != null && _isMe) {
        setState(() {
          _displayUser = me;
        });
      }
    });
  }

  // ── Load subscription plan limits ────────────────────────────────────────────
  Future<void> _loadPlanLimits() async {
    try {
      final subProvider = SubscriptionProvider.instance;
      unawaited(subProvider.refresh());
      unawaited(subProvider.fetchEntitlementsSummary());

      setState(() {
        _limitsLoaded = true;
      });
    } catch (e) {
      debugPrint('[ProfileScreen] Failed to load plan limits: $e');
      if (mounted) setState(() => _limitsLoaded = true);
    }
  }

  Future<void> _loadAllProfiles() async {
    try {
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
  // ── LIKE handler — stay on same page, change button colour instantly ────────
  Future<bool> _handleLike({bool? desiredState}) async {
    if (_displayUser == null) return false;
    final targetUser = _displayUser!;
    final targetId = targetUser.id;
    final currentAction = _swipedActions[targetId];
    final isCurrentlyLiked = currentAction == 'like' || targetUser.isLiked;
    final bool shouldBeLiked = desiredState ?? !isCurrentlyLiked;

    // If currently liked and should not be liked -> unlike
    if (!shouldBeLiked) {
      setState(() {
        _swipedActions.remove(targetId);
        _displayUser = _displayUser?.copyWith(isLiked: false);
      });
      ApiService.unlikeUser(targetUserId: targetId).then((ok) {
        if (ok && mounted) {
          unawaited(SubscriptionProvider.instance.refresh());
        }
      });
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed like for ${targetUser.firstName}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }

    // Daily like limit guard (skip if user has unlimited likes)
    final subProvider = SubscriptionProvider.instance;
    if (!subProvider.hasUnlimitedLikes && !subProvider.canLike) {
      final validation = subProvider.validateAction(VipAction.like);
      showSubscriptionLimitDialog(
        context,
        feature: SubLimitFeature.dailyLikes,
        customMessage: validation.message,
      );
      return false;
    }

    subProvider.optimisticConsume(VipAction.like);

    // Instant optimistic UI update (0ms delay)
    setState(() {
      _swipedActions[targetId] = 'like';
      _dailyLikesUsed++;
      _displayUser = _displayUser?.copyWith(isLiked: true);
    });
    _showLikeNotification(targetUser.firstName, isSuperLike: false);

    // Asynchronously verify with backend
    try {
      final res = await ApiService.swipeUser(targetUserId: targetId, action: 'like');
      if (!mounted) return true;
      if (res == null || res['limitReached'] == true) {
        subProvider.rollbackConsume(VipAction.like);
        setState(() {
          _swipedActions.remove(targetId);
          _dailyLikesUsed = math.max(0, _dailyLikesUsed - 1);
          _displayUser = _displayUser?.copyWith(isLiked: false);
        });
        showSubscriptionLimitDialog(
          context,
          feature: SubLimitFeature.dailyLikes,
          customMessage: res?['message'],
        );
        return false;
      } else {
        _checkUsageWarning(res);
        unawaited(SubscriptionProvider.instance.refresh());
        return true;
      }
    } catch (_) {
      return true;
    }
  }

  void _checkUsageWarning(Map<String, dynamic>? res) {
    if (res != null && res['usageWarning'] != null && res['usageWarning']['triggered'] == true && mounted) {
      final warnMsg = res['usageWarning']['message']?.toString() ?? 'Usage warning';
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
                    MaterialPageRoute(builder: (_) => const VIPMembershipScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'UPGRADE',
                    style: TextStyle(
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

  // ── SUPERLIKE handler ─────────────────────────────────────────────────────────
  Future<bool> _handleSuperLike() async {
    if (_displayUser == null) return false;
    final targetUser = _displayUser!;
    final targetId = targetUser.id;
    final currentAction = _swipedActions[targetId];

    // If already superliked, clicking "superlike" again retains it
    if (currentAction == 'superlike' || targetUser.isSuperLiked) {
      _showAlreadyLikedSnack(targetUser.firstName, isSuperLike: true);
      return true;
    }

    // Superlikes remaining guard (always validate against SubscriptionProvider)
    final subProvider = SubscriptionProvider.instance;
    final bool isUnlimitedSuper = subProvider.isElite || subProvider.status.isUnlimitedSuperlikes;
    if (!isUnlimitedSuper && !subProvider.canSuperLike) {
      final validation = subProvider.validateAction(VipAction.superlike);
      showSubscriptionLimitDialog(
        context,
        feature: SubLimitFeature.superLike,
        customMessage: validation.message,
      );
      return false;
    }

    subProvider.optimisticConsume(VipAction.superlike);

    // Instant optimistic UI update (0ms delay)
    setState(() {
      _swipedActions[targetId] = 'superlike';
      _displayUser = _displayUser?.copyWith(isSuperLiked: true);
    });
    _showLikeNotification(targetUser.firstName, isSuperLike: true);

    // Asynchronously send to backend
    try {
      final res = await ApiService.swipeUser(targetUserId: targetId, action: 'superlike');
      if (!mounted) return true;
      if (res == null || res['limitReached'] == true) {
        subProvider.rollbackConsume(VipAction.superlike);
        setState(() {
          _swipedActions.remove(targetId);
          _displayUser = _displayUser?.copyWith(isSuperLiked: false);
        });
        showSubscriptionLimitDialog(
          context,
          feature: SubLimitFeature.superLike,
          customMessage: res?['message'],
        );
        return false;
      } else {
        _checkUsageWarning(res);
        unawaited(SubscriptionProvider.instance.refresh());
        return true;
      }
    } catch (_) {
      return true;
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
  void _handleSwipe(bool isRightSwipe) {
    if (_displayUser == null) return;
    final targetUser = _displayUser!;

    if (isRightSwipe) {
      // Swiping left-to-right -> BACKTRACK to previous profile (like Tinder/Bumble)
      _undoLastSwipe();
    } else {
      // Swiping right-to-left -> Next profile (Nope)
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
                      ? 'You Super Liked $firstName! 🌟${_superlikesPerCycle > 0 ? ' ($_superlikesRemaining left)' : ''}'
                      : 'You Liked $firstName! ❤️${_dailyLikesLimit != 999999 ? ' (${_dailyLikesLimit - _dailyLikesUsed} left today)' : ''}',
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

  void _showBacktrackUpgradePrompt() {
    if (!mounted) return;
    showSubscriptionLimitDialog(
      context,
      feature: SubLimitFeature.backtrack,
      customMessage: 'You have reached your backtrack limit. Upgrade to VIP or get a Backtrack add-on to rewind profiles anytime!',
    ).then((_) {
      _loadPlanLimits();
    });
  }

  void _undoLastSwipe() {
    if (_swipeHistory.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No previous profile to backtrack to'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final subProvider = SubscriptionProvider.instance;
    final validation = subProvider.validateAction(VipAction.backtrack);
    if (!validation.allowed) {
      _showBacktrackUpgradePrompt();
      return;
    }

    final prevUser = _swipeHistory.last;

    // Optimistically consume backtrack entitlement (from plan or add-on)
    subProvider.optimisticConsume(VipAction.backtrack);

    ApiService.backtrackSwipe(prevUser.id).then((res) {
      if (res != null && res['limitReached'] == true) {
        subProvider.rollbackConsume(VipAction.backtrack);
        _showBacktrackUpgradePrompt();
        return;
      }

      if (mounted) {
        setState(() {
          _swipeHistory.removeLast();
          if (_swipeDirections.isNotEmpty) _swipeDirections.removeLast();
          _backtrackedUser = prevUser;
          _swipedActions.remove(prevUser.id);
          if (!_allProfiles.any((u) => u.id == prevUser.id)) {
            _allProfiles.insert(0, prevUser);
          }
          _displayUser = prevUser;
          _currentProfileIndex = _allProfiles.indexWhere((u) => u.id == prevUser.id);
          if (_currentProfileIndex == -1) _currentProfileIndex = 0;
          _outOfProfiles = false;
        });

        unawaited(SubscriptionProvider.instance.refresh());
        unawaited(SubscriptionProvider.instance.fetchEntitlementsSummary());

        final backtrackWidget = ProfileDetailView(
          key: ValueKey(prevUser.id),
          user: prevUser,
          isMe: prevUser.id == ApiService.currentUserId,
          swipedAction: _swipedActions[prevUser.id],
          isLikeDisabled: !SubscriptionProvider.instance.canLike,
          isSuperLikeDisabled: !SubscriptionProvider.instance.canSuperLike,
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
    final isLikeDisabled = !SubscriptionProvider.instance.canLike;
    final isSuperLikeDisabled = !SubscriptionProvider.instance.canSuperLike;

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
          canSwipeRight: () => _swipeHistory.isNotEmpty && SubscriptionProvider.instance.canBacktrack,
          onSwipeLeft: () => _handleSwipe(false),
          onSwipeRight: () => _handleSwipe(true),
          onSwipePrev: _handleBacktrackComplete,
        ),
      ],
    );
  }
}
