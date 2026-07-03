import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../widgets/bumble_swipe_widget.dart';
import 'profile_detail_view.dart';

class ProfileScreen extends StatefulWidget {
  final User? user;

  const ProfileScreen({super.key, this.user});

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
  User? _backtrackedUser;
  String _swipeAction = 'like';

  @override
  void initState() {
    super.initState();
    _initUser();
    _loadAllProfiles();
  }

  Future<void> _loadAllProfiles() async {
    try {
      final me = await ApiService.fetchProfile();
      final String? myGender = me?.gender?.toLowerCase();
      final String? selectedCity = ApiService.selectedCity;
      final String? myId = ApiService.currentUserId;

      final rawCustomers = await ApiService.fetchCustomers();
      final List<User> resolvedUsers = [];
      for (var c in rawCustomers) {
        try {
          final u = User.fromJson(c);
          
          // Exclude logged-in user
          if (myId != null && u.id == myId) {
            continue;
          }

          // Filter by selected city (case-insensitive)
          if (selectedCity != null && selectedCity.isNotEmpty) {
            if (u.city == null || u.city!.toLowerCase() != selectedCity.toLowerCase()) {
              continue;
            }
          }

          // Filter by opposite gender (case-insensitive)
          if (myGender != null && myGender.isNotEmpty) {
            final uGender = (u.gender ?? '').toLowerCase();
            if (myGender == 'male' || myGender == 'm') {
              if (uGender == 'male' || uGender == 'm') continue;
            } else if (myGender == 'female' || myGender == 'f') {
              if (uGender == 'female' || uGender == 'f') continue;
            }
          }

          resolvedUsers.add(u);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _me = me;
          _allProfiles = resolvedUsers;
          _updateCurrentProfileIndex();
        });
      }
    } catch (e) {
      debugPrint('[ProfileScreen] Error loading all profiles: $e');
    }
  }

  void _updateCurrentProfileIndex() {
    if (_displayUser != null && _allProfiles.isNotEmpty) {
      _currentProfileIndex = _allProfiles.indexWhere((u) => u.id == _displayUser!.id);
    }
  }

  Future<void> _initUser() async {
    if (widget.user != null) {
      setState(() {
        _displayUser = widget.user;
        _isMe = _displayUser!.id == ApiService.currentUserId;
      });
      _updateCurrentProfileIndex();
      // Fetch full user profile to retrieve the photos list and details
      debugPrint('[ProfileScreen] Fetching profile for user: ${widget.user!.id}');
      final fullUser = await ApiService.fetchProfile(userId: widget.user!.id);
      if (fullUser != null && mounted) {
        debugPrint('[ProfileScreen] Profile loaded successfully with ${fullUser.photos.length} photos.');
        setState(() {
          _displayUser = fullUser;
        });
        _updateCurrentProfileIndex();
      } else {
        debugPrint('[ProfileScreen] Profile fetch returned null.');
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
      }
    });
  }

  void _showNextProfile() {
    if (_allProfiles.isEmpty) return;
    int nextIndex = _currentProfileIndex;
    if (nextIndex == -1) {
      nextIndex = 0;
    } else {
      nextIndex = (nextIndex + 1) % _allProfiles.length;
    }
    _navigateToProfile(nextIndex);
  }

  void _handleSwipe(bool liked) {
    if (_displayUser == null) return;

    final targetUser = _displayUser!;
    final action = liked ? _swipeAction : 'nope';

    // Reset default swipe action
    _swipeAction = 'like';

    // Trigger backend API call to register the swipe
    ApiService.swipeUser(targetUserId: targetUser.id, action: action).then((res) {
      if (res != null && res['matched'] == true && mounted) {
        _showMatchDialog(targetUser);
      }
    });

    setState(() {
      _swipeHistory.add(targetUser);
      _swipeDirections.add(liked);
    });

    _showNextProfile();
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
            color: const Color(0xFF1F1235), // Slick premium dark violet
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
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Current user avatar
                  CircleAvatar(
                    radius: 45,
                    backgroundColor: Colors.grey[800],
                    backgroundImage: _me?.profilePhoto != null && _me!.profilePhoto!.isNotEmpty
                        ? NetworkImage(_me!.profilePhoto!)
                        : null,
                    child: _me?.profilePhoto == null || _me!.profilePhoto!.isEmpty
                        ? const Icon(Icons.person, color: Colors.white, size: 40)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.favorite, color: Colors.redAccent, size: 40),
                  const SizedBox(width: 16),
                  // Matched user avatar
                  CircleAvatar(
                    radius: 45,
                    backgroundColor: Colors.grey[800],
                    backgroundImage: matchUser.profilePhoto != null && matchUser.profilePhoto!.isNotEmpty
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 5,
                ),
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                },
                child: const Text(
                  "SAY HELLO",
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "KEEP SWIPING",
                  style: TextStyle(color: Colors.white54),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void _undoLastSwipe() {
    if (_swipeHistory.isEmpty) return;

    final prevUser = _swipeHistory.removeLast();
    final wasLiked = _swipeDirections.removeLast();
    _backtrackedUser = prevUser;

    final backtrackWidget = ProfileDetailView(
      key: ValueKey(prevUser.id),
      user: prevUser,
      isMe: prevUser.id == ApiService.currentUserId,
      onNope: () {
        _swipeAction = 'nope';
        _swipeController.swipe(false);
      },
      onLike: () {
        _swipeAction = 'like';
        _swipeController.swipe(true);
      },
      onSuper: () {
        _swipeAction = 'superlike';
        _swipeController.swipe(true);
      },
      onBacktrack: _undoLastSwipe,
      canBacktrack: _swipeHistory.isNotEmpty,
    );

    _swipeController.backtrack(wasLiked, backtrackWidget);
  }

  void _handleBacktrackComplete() {
    if (_backtrackedUser != null) {
      setState(() {
        _displayUser = _backtrackedUser;
        _currentProfileIndex = _allProfiles.indexWhere((u) => u.id == _backtrackedUser!.id);
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
        body: Center(child: CircularProgressIndicator(color: LunaraTheme.electricViolet)),
      );
    }

    if (_displayUser == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('PROFILE')),
        body: const Center(child: Text('User not found')),
      );
    }

    // When viewing own profile, don't wrap in swipe widget
    if (_isMe) {
      return ProfileDetailView(
        key: ValueKey(_displayUser!.id),
        user: _displayUser!,
        isMe: true,
        onNope: null,
        onLike: null,
        onSuper: null,
        onBacktrack: null,
        canBacktrack: false,
      );
    }

    final currentProfileWidget = ProfileDetailView(
      key: ValueKey(_displayUser!.id),
      user: _displayUser!,
      isMe: _isMe,
      onNope: () {
        _swipeAction = 'nope';
        _swipeController.swipe(false);
      },
      onLike: () {
        _swipeAction = 'like';
        _swipeController.swipe(true);
      },
      onSuper: () {
        _swipeAction = 'superlike';
        _swipeController.swipe(true);
      },
      onBacktrack: _undoLastSwipe,
      canBacktrack: _swipeHistory.isNotEmpty,
    );

    User? nextUser;
    if (_allProfiles.isNotEmpty) {
      if (_currentProfileIndex == -1) {
        nextUser = _allProfiles[0];
      } else {
        final nextIdx = (_currentProfileIndex + 1) % _allProfiles.length;
        if (nextIdx != _currentProfileIndex) {
          nextUser = _allProfiles[nextIdx];
        }
      }
    }

    final nextProfileWidget = nextUser != null
        ? ProfileDetailView(
            key: ValueKey(nextUser.id),
            user: nextUser,
            isMe: nextUser.id == ApiService.currentUserId,
            onNope: null,
            onLike: null,
            onSuper: null,
            onBacktrack: null,
            canBacktrack: false,
          )
        : null;

    return BumbleSwipeWidget(
      controller: _swipeController,
      currentWidget: currentProfileWidget,
      nextWidget: nextProfileWidget,
      onSwipeLeft: () => _handleSwipe(false),
      onSwipeRight: () => _handleSwipe(true),
      onSwipePrev: _handleBacktrackComplete,
    );
  }
}
