import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:lunara_app/core/theme.dart';
import 'package:lunara_app/models/user.dart';
import 'settings_screen.dart';
import 'edit_profile_screen.dart';
import '../../services/block_service.dart';
import '../../services/api_service.dart';
import '../../services/optimistic_action_guard.dart';
import '../../services/subscription_provider.dart';
import 'package:intl/intl.dart';
import '../../widgets/profile_share_sheet.dart';
import '../../widgets/subscription_limit_dialog.dart';
import 'vip_membership_screen.dart';
import '../social/post_detail_screen.dart';
import '../../models/strangers_meet_request.dart';
import '../../widgets/dialogs/time_lock_blocked_dialog.dart';

class ProfileDetailView extends StatefulWidget {
  final User user;
  final bool isMe;
  final VoidCallback? onNope;
  // Returns a Future so this widget can wait for the real server-confirmed
  // outcome before showing the liked/superliked state, instead of guessing.
  final Future<dynamic> Function()? onLike;
  final Future<dynamic> Function()? onSuper;
  final VoidCallback? onBacktrack;
  final bool canBacktrack;

  /// 'like' | 'superlike' | 'noped' | null (not yet acted on)
  final String? swipedAction;

  /// True when the user has hit their daily like quota
  final bool isLikeDisabled;

  /// True when the user has no superlike credits remaining
  final bool isSuperLikeDisabled;

  const ProfileDetailView({
    super.key,
    required this.user,
    required this.isMe,
    this.onNope,
    this.onLike,
    this.onSuper,
    this.onBacktrack,
    this.canBacktrack = false,
    this.swipedAction,
    this.isLikeDisabled = false,
    this.isSuperLikeDisabled = false,
  });

  @override
  State<ProfileDetailView> createState() => _ProfileDetailViewState();
}

class _ProfileDetailViewState extends State<ProfileDetailView> {
  int _currentPhotoIndex = 0;
  bool _isBlocked = false;
  late User _currentUser;
  bool _isLiked = false;
  bool _isSuperLiked = false;
  bool _isLoadingSwipeStatus = false;
  bool _isSuperLiking = false;

  @override
  void initState() {
    super.initState();
    ApiService.profileUpdateNotifier.addListener(_refreshProfile);
    _currentUser = widget.user;
    _isLiked = widget.user.isLiked || widget.swipedAction == 'like';
    _isSuperLiked = widget.user.isSuperLiked || widget.swipedAction == 'superlike';
    if (!widget.isMe) {
      _checkBlockStatus();
      _isLoadingSwipeStatus = true;
      _fetchLiveSwipeStatus().then((_) {
        if (mounted) setState(() => _isLoadingSwipeStatus = false);
      });
    }
  }

  @override
  void dispose() {
    ApiService.profileUpdateNotifier.removeListener(_refreshProfile);
    super.dispose();
  }

  @override
  void didUpdateWidget(ProfileDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final userChanged = widget.user.id != oldWidget.user.id;
    if (userChanged) {
      _currentUser = widget.user;
      _isLiked = widget.user.isLiked || widget.swipedAction == 'like';
      _isSuperLiked = widget.user.isSuperLiked || widget.swipedAction == 'superlike';
      if (!widget.isMe) {
        _isLoadingSwipeStatus = true;
        _fetchLiveSwipeStatus().then((_) {
          if (mounted) setState(() => _isLoadingSwipeStatus = false);
        });
      }
    } else {
      _currentUser = widget.user;
      if (widget.swipedAction == 'like' || widget.user.isLiked) {
        _isLiked = true;
      } else if (widget.swipedAction == 'superlike' || widget.user.isSuperLiked) {
        _isSuperLiked = true;
      } else if (widget.swipedAction == null && oldWidget.swipedAction != null) {
        _isLiked = false;
        _isSuperLiked = false;
      }
    }
  }

  Future<void> _fetchLiveSwipeStatus() async {
    try {
      final status = await ApiService.fetchSwipeStatus(_currentUser.id);
      if (mounted && status.isNotEmpty) {
        setState(() {
          if (status['alreadyLiked'] == true) {
            _isLiked = true;
            _currentUser = _currentUser.copyWith(isLiked: true);
          }
          if (status['alreadySuperLiked'] == true) {
            _isSuperLiked = true;
            _currentUser = _currentUser.copyWith(isSuperLiked: true);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _refreshProfile() async {
    final updatedUser = await ApiService.fetchProfile(userId: _currentUser.id, forceRefresh: true);
    if (updatedUser != null && mounted) {
      setState(() {
        _currentUser = updatedUser;
        _isLiked = updatedUser.isLiked;
        _isSuperLiked = updatedUser.isSuperLiked;
      });
    }
  }

  Future<void> _checkBlockStatus() async {
    final isBlocked = await BlockService.isUserBlocked(_currentUser.id);
    if (mounted) {
      setState(() {
        _isBlocked = isBlocked;
      });
    }
  }

  Future<void> _toggleBlock() async {
    if (_isBlocked) {
      await BlockService.unblockUser(_currentUser.id);
    } else {
      await BlockService.blockUser(_currentUser.id);
    }
    _checkBlockStatus();
  }

  void _reportUser() {
    final TextEditingController reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report User'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to report and block this user?'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: "What's wrong?",
                hintText: 'Please provide a reason',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Please provide a reason to report this user.',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              await BlockService.reportUser(_currentUser.id, reason);
              _checkBlockStatus();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('User reported and blocked')),
                );
              }
            },
            child: const Text('Report', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  List<String> get _userPhotos {
    if (_currentUser.photos.isNotEmpty) {
      return _currentUser.photos;
    }
    if (_currentUser.profilePhoto != null &&
        _currentUser.profilePhoto!.isNotEmpty) {
      return [_currentUser.profilePhoto!];
    }
    return [];
  }

  void _showPreviousPhoto() {
    final photos = _userPhotos;
    if (photos.length <= 1) return;
    setState(() {
      _currentPhotoIndex =
          (_currentPhotoIndex - 1 + photos.length) % photos.length;
    });
  }

  void _showNextPhoto() {
    final photos = _userPhotos;
    if (photos.length <= 1) return;
    setState(() {
      _currentPhotoIndex = (_currentPhotoIndex + 1) % photos.length;
    });
  }

  List<Widget> _buildDynamicInfoSections() {
    final List<Widget> sections = [];

    // Section 1: Bio
    if (_currentUser.bio != null && _currentUser.bio!.isNotEmpty) {
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            _currentUser.bio!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    // Section 2: Work & Education
    final List<Widget> workEduRows = [];
    if (_currentUser.occupation != null &&
        _currentUser.occupation!.isNotEmpty) {
      String occ = _currentUser.occupation!;
      if (_currentUser.company != null && _currentUser.company!.isNotEmpty) {
        occ += ' at ${_currentUser.company}';
      }
      workEduRows.add(_buildInfoRow(Icons.work_outline_rounded, occ));
    } else if (_currentUser.company != null &&
        _currentUser.company!.isNotEmpty) {
      workEduRows.add(
        _buildInfoRow(Icons.business_outlined, _currentUser.company!),
      );
    }
    if (_currentUser.education != null && _currentUser.education!.isNotEmpty) {
      workEduRows.add(
        _buildInfoRow(Icons.school_outlined, _currentUser.education!),
      );
    }

    if (workEduRows.isNotEmpty) {
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: workEduRows,
          ),
        ),
      );
    }

    // Section 3: Music Preferences
    if (_currentUser.musicPreference.isNotEmpty) {
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.music_note_rounded,
                    size: 14,
                    color: LunaraTheme.cyberCyan,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'MY MUSIC',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _currentUser.musicPreference.take(3).map((genre) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Text(
                      genre.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    }

    // Section 4: Preferences (Looking For, Smoking, Budget)
    final List<Widget> prefRows = [];
    if (_currentUser.lookingFor.isNotEmpty) {
      prefRows.add(
        _buildInfoRow(
          Icons.search_rounded,
          'Looking for: ${_currentUser.lookingFor.join(", ")}',
        ),
      );
    }
    if (_currentUser.smokingPreference != null &&
        _currentUser.smokingPreference!.isNotEmpty) {
      final smokeVal = _currentUser.smokingPreference!.toUpperCase();
      final isNonSmoker =
          smokeVal.contains('NON') || smokeVal == 'NEVER' || smokeVal == 'NO';
      final IconData smokeIcon = isNonSmoker
          ? Icons.smoke_free_rounded
          : Icons.smoking_rooms_rounded;

      prefRows.add(_buildInfoRow(smokeIcon, _currentUser.smokingPreference!));
    }
    if (_currentUser.drinkPreference.isNotEmpty) {
      final drinkVal = _currentUser.drinkPreference.join(', ').toUpperCase();
      final isNonDrinker =
          drinkVal.contains('NEVER') ||
          drinkVal == 'NO' ||
          drinkVal.contains('NON');
      final IconData drinkIcon = isNonDrinker
          ? Icons.no_drinks_rounded
          : Icons.local_bar_rounded;

      prefRows.add(
        _buildInfoRow(
          drinkIcon,
          'Drinking: ${_currentUser.drinkPreference.join(", ")}',
        ),
      );
    }
    if (_currentUser.budgetRange != null &&
        _currentUser.budgetRange!.isNotEmpty) {
      prefRows.add(
        _buildInfoRow(
          Icons.currency_rupee_rounded,
          'Budget: ${_currentUser.budgetRange}',
        ),
      );
    }

    if (prefRows.isNotEmpty) {
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: prefRows,
          ),
        ),
      );
    }

    // Fallback if no sections are available at all
    if (sections.isEmpty) {
      sections.add(const SizedBox.shrink());
    }

    return sections;
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isBlocked) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black),
              onSelected: (value) {
                if (value == 'block') _toggleBlock();
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'block',
                  child: Text('Unblock User'),
                ),
              ],
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text(
                'User Blocked',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'You blocked this profile.',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _toggleBlock,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Unblock',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final double originalTopPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(originalTopPadding),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  _buildActionButtons(),
                  if (!widget.isMe) ...[
                    const SizedBox(height: 24),
                    _buildViewPlansButton(),
                  ],
                  _buildDetailsSection(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Wraps [child] in a 44×44 frosted-glass circular container used for
  /// both the back button and the 3-dots menu button.
  Widget _buildNavBtn({required Widget child}) {
    return SizedBox(
      width: 44,
      height: 44,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.38),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1.4,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(double topPadding) {
    final photos = _userPhotos;
    final photo = photos.isNotEmpty && _currentPhotoIndex < photos.length
        ? photos[_currentPhotoIndex]
        : _currentUser.profilePhoto;

    final infoSections = _buildDynamicInfoSections();
    final int sectionIndex = infoSections.isNotEmpty
        ? _currentPhotoIndex % infoSections.length
        : 0;
    final Widget activeSection = infoSections.isNotEmpty
        ? infoSections[sectionIndex]
        : const SizedBox.shrink();

    return SliverAppBar(
      expandedHeight: MediaQuery.of(context).size.height,
      toolbarHeight: 0,
      collapsedHeight: 0,
      pinned: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final double width = MediaQuery.of(context).size.width;
            final double tapX = details.localPosition.dx;
            if (tapX < width / 2) {
              _showPreviousPhoto();
            } else {
              _showNextPhoto();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background Gradient/Image
              if (photo != null && photo.isNotEmpty)
                SizedBox.expand(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                    child: SizedBox.expand(
                      key: ValueKey<String>(photo),
                      child: Image.network(
                        photo,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          key: const ValueKey<String>('error_placeholder'),
                          decoration: const BoxDecoration(
                            gradient: LunaraTheme.deepPurpleGradient,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  key: const ValueKey<String>('empty_placeholder'),
                  decoration: const BoxDecoration(
                    gradient: LunaraTheme.deepPurpleGradient,
                  ),
                ),

              // Beautiful Top and Bottom Gradients for Text Readability
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 140,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 300,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // ── Nav buttons (back + menu) ──────────────────────────────────
              // Using Positioned so they always sit just below the status bar,
              // regardless of whether the device has system navigation buttons
              // or gesture navigation enabled.
              Positioned(
                top: topPadding + 12,
                left: 12,
                child: _buildNavBtn(
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              Positioned(
                top: topPadding + 12,
                right: 12,
                child: _buildNavBtn(
                  child: widget.isMe
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.settings_outlined,
                            color: Colors.white,
                            size: 22,
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ),
                        )
                      : PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                            size: 22,
                          ),
                          color: Colors.white,
                          onSelected: (value) async {
                            if (value == 'block') {
                              await _toggleBlock();
                            } else if (value == 'report') {
                              _reportUser();
                            }
                          },
                          itemBuilder: (BuildContext context) =>
                              <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  value: 'block',
                                  child: Text(
                                    _isBlocked ? 'Unblock User' : 'Block User',
                                  ),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'report',
                                  child: Text(
                                    'Report User',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                        ),
                ),
              ),

              // Segmented Indicators at the top of the photo
              if (photos.length > 1)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 60,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: List.generate(
                      photos.length,
                      (index) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 4,
                          decoration: BoxDecoration(
                            color: _currentPhotoIndex == index
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Profile Info Overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              _currentUser.fullName.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                fontFamily: 'AllroundGothic',
                                shadows: [
                                  Shadow(
                                    color: Colors.black45,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_currentUser.age != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              ', ${_currentUser.age}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                shadows: [
                                  Shadow(
                                    color: Colors.black45,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (_currentUser.isVerified) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.verified_rounded,
                              color: LunaraTheme.cyberCyan,
                              size: 24,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  (_currentUser.city ?? 'UNKNOWN CITY')
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_currentUser.gender != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: LunaraTheme.electricViolet.withValues(
                                  alpha: 0.25,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: LunaraTheme.electricViolet.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ),
                              child: Text(
                                _currentUser.gender!.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.0, 0.1),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                        child: SizedBox(
                          key: ValueKey<int>(sectionIndex),
                          width: double.infinity,
                          child: activeSection,
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
    );
  }

  Widget _buildActionButtons() {
    if (widget.isMe) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Expanded(
              child: _actionButton(
                'EDIT PROFILE',
                Colors.black,
                Colors.white,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditProfileScreen(user: _currentUser),
                    ),
                  ).then((_) {
                    _refreshProfile();
                  });
                },
                isOutlined: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                'SHARE PROFILE',
                LunaraTheme.electricViolet,
                Colors.white,
                () {
                  ProfileShareSheet.show(
                    context,
                    profileId: _currentUser.id,
                    name: _currentUser.fullName,
                    age: _currentUser.age?.toString(),
                    city: _currentUser.city,
                    profilePhotoUrl: _currentUser.profilePhoto,
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoadingSwipeStatus) {
      return const SizedBox(
        height: 100, // Approximate height of the action buttons
        child: Center(
          child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
        ),
      );
    }

    return ListenableBuilder(
      listenable: SubscriptionProvider.instance,
      builder: (_, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final isSuperLiked = _isSuperLiked;
        final isLiked = _isLiked;

        final subProvider = SubscriptionProvider.instance;
        final bool hasUnlimitedLikes = subProvider.hasUnlimitedLikes;
        final bool canLike = hasUnlimitedLikes || subProvider.canLike;
        // Disabled (grey) only if user has no likes left and not unlimited, AND not already liked
        final likeDisabled = !isLiked && !hasUnlimitedLikes && !canLike;

        final bool isUnlimitedSuper = subProvider.isElite || subProvider.status.isUnlimitedSuperlikes;
        final bool canSuperLike = isUnlimitedSuper || subProvider.canSuperLike;
        // Disabled (grey) only when user has no superlikes and not unlimited, AND not already superliked
        final superLikeDisabled = !isSuperLiked && !isUnlimitedSuper && !canSuperLike;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Backtrack button ──────────────────────────────────────────────────
            Opacity(
              opacity: widget.canBacktrack ? 1.0 : 0.4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LunaraTheme.amberGlow,
                      boxShadow: [
                        if (widget.canBacktrack) ...[
                          BoxShadow(
                            color: const Color(0xFFFFB703).withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ] else
                          BoxShadow(
                            color: Colors.amber.withValues(
                              alpha: isDark ? 0.25 : 0.1,
                            ),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.undo_rounded, color: Colors.white),
                      onPressed: widget.canBacktrack ? widget.onBacktrack : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Backtrack',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // ── Nope button ───────────────────────────────────────────────────────
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF2A6D), Color(0xFFFF6597)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFFFF2A6D,
                        ).withValues(alpha: isDark ? 0.35 : 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: widget.onNope,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Nope',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),

            // ── Like button ───────────────────────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: isLiked ? 60 : 52,
                    height: isLiked ? 60 : 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Green when liked, disabled grey when limit reached, default cyan
                      gradient: isLiked
                          ? const LinearGradient(
                              colors: [Color(0xFF00C853), Color(0xFF69F0AE)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : likeDisabled
                          ? LinearGradient(
                              colors: [Colors.grey.shade400, Colors.grey.shade500],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFF00B5FF), Color(0xFF00E5FF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      boxShadow: [
                        if (isLiked) ...[
                          BoxShadow(
                            color: const Color(0xFF00C853).withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ] else
                          BoxShadow(
                            color: const Color(
                              0xFF00B5FF,
                            ).withValues(alpha: isDark ? 0.3 : 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                      ],
                    ),
                    child: IconButton(
                      disabledColor: Colors.white,
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: Colors.white,
                      ),
                      onPressed: () async {
                        final currentlyLiked = _isLiked;
                        if (!currentlyLiked) {
                          // Quota check / Grey button tap validation
                          if (likeDisabled || (!hasUnlimitedLikes && !subProvider.canLike)) {
                            final validation = subProvider.validateAction(VipAction.like);
                            showSubscriptionLimitDialog(
                              context,
                              feature: SubLimitFeature.dailyLikes,
                              customMessage: validation.message,
                            );
                            return;
                          }

                          if (!hasUnlimitedLikes) {
                            final validation = subProvider.validateAction(VipAction.like);
                            if (!validation.allowed) {
                              showSubscriptionLimitDialog(
                                context,
                                feature: SubLimitFeature.dailyLikes,
                                customMessage: validation.message,
                              );
                              return;
                            }
                          }
                        }

                        // Instant 0ms optimistic UI toggle
                        final nextState = !currentlyLiked;
                        setState(() {
                          _isLiked = nextState;
                          _currentUser = _currentUser.copyWith(isLiked: nextState);
                        });

                        if (widget.onLike != null) {
                          widget.onLike!.call().then((success) {
                            if (mounted && success != nextState) {
                              setState(() {
                                _isLiked = success == true;
                                _currentUser = _currentUser.copyWith(isLiked: success == true);
                              });
                            }
                          });
                        } else {
                          if (currentlyLiked) {
                            ApiService.unlikeUser(targetUserId: _currentUser.id).then((ok) {
                              if (!ok && mounted) {
                                setState(() {
                                  _isLiked = true;
                                  _currentUser = _currentUser.copyWith(isLiked: true);
                                });
                              }
                            });
                          } else {
                            subProvider.optimisticConsume(VipAction.like);
                            ApiService.swipeUser(targetUserId: _currentUser.id, action: 'like').then((res) {
                              if (!mounted) return;
                              if (res == null || res['limitReached'] == true) {
                                subProvider.rollbackConsume(VipAction.like);
                                setState(() {
                                  _isLiked = false;
                                  _currentUser = _currentUser.copyWith(isLiked: false);
                                });
                                showSubscriptionLimitDialog(
                                  context,
                                  feature: SubLimitFeature.dailyLikes,
                                  customMessage: res?['message'],
                                );
                              } else {
                                _checkUsageWarning(res);
                                subProvider.refresh();
                              }
                            });
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      isLiked ? 'LIKED ✓' : 'Like',
                      key: ValueKey(isLiked),
                      style: TextStyle(
                        fontSize: 11,
                        color: isLiked
                            ? const Color(0xFF00C853)
                            : (isDark ? Colors.white60 : Colors.black54),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // ── Super Like button ─────────────────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: isSuperLiked ? 52 : 48,
                    height: isSuperLiked ? 52 : 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Gold when superliked, disabled grey when no credits, default purple
                      gradient: isSuperLiked
                          ? const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : superLikeDisabled
                          ? LinearGradient(
                              colors: [Colors.grey.shade400, Colors.grey.shade500],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFF7F00FF), Color(0xFFB952EB)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      boxShadow: [
                        if (isSuperLiked) ...[
                          BoxShadow(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ] else
                          BoxShadow(
                            color: const Color(
                              0xFF7F00FF,
                            ).withValues(alpha: isDark ? 0.35 : 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                      ],
                    ),
                    child: IconButton(
                      disabledColor: Colors.white,
                      icon: _isSuperLiking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(
                              isSuperLiked ? Icons.star : Icons.star_border,
                              color: Colors.white,
                            ),
                      onPressed: (OptimisticActionGuard.isLocked('SWIPE_SUPER:${_currentUser.id}') || _isSuperLiking)
                          ? null
                          : () async {
                              if (_isSuperLiked) {
                                ScaffoldMessenger.of(context).clearSnackBars();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('You already Super Liked ${_currentUser.firstName}! 🌟'),
                                    duration: const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                return;
                              }

                              // Quota check / Grey button tap validation
                              if (superLikeDisabled || (!isUnlimitedSuper && !subProvider.canSuperLike)) {
                                final validation = subProvider.validateAction(VipAction.superlike);
                                showSubscriptionLimitDialog(
                                  context,
                                  feature: SubLimitFeature.superLike,
                                  customMessage: validation.message,
                                );
                                return;
                              }

                              // In-memory quota check
                              final validation = subProvider.validateAction(VipAction.superlike);
                              if (!validation.allowed) {
                                showSubscriptionLimitDialog(
                                  context,
                                  feature: SubLimitFeature.superLike,
                                  customMessage: validation.message,
                                );
                                return;
                              }

                              if (!OptimisticActionGuard.start('SWIPE_SUPER:${_currentUser.id}')) return;

                              setState(() {
                                _isSuperLiking = true;
                              });

                              try {
                                bool success = false;
                                if (widget.onSuper != null) {
                                  final res = await widget.onSuper!.call();
                                  success = res == true;
                                } else {
                                  final res = await ApiService.swipeUser(targetUserId: _currentUser.id, action: 'superlike');
                                  if (!mounted) return;
                                  if (res == null || res['limitReached'] == true) {
                                    showSubscriptionLimitDialog(
                                      context,
                                      feature: SubLimitFeature.superLike,
                                      customMessage: res?['message'],
                                    );
                                    success = false;
                                  } else {
                                    success = true;
                                    subProvider.optimisticConsume(VipAction.superlike);
                                    if (res['matched'] == true) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('🎉 It\'s a Match with ${_currentUser.firstName}!'),
                                          backgroundColor: const Color(0xFF10B981),
                                        ),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('You Super Liked ${_currentUser.firstName}! 🌟'),
                                          backgroundColor: const Color(0xFFFF8C00),
                                          behavior: SnackBarBehavior.floating,
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                    _checkUsageWarning(res);
                                  }
                                }

                                if (mounted) {
                                  setState(() {
                                    _isSuperLiked = success;
                                    if (success) {
                                      _currentUser = _currentUser.copyWith(isSuperLiked: true);
                                    }
                                  });
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() => _isSuperLiked = false);
                                }
                              } finally {
                                if (mounted) setState(() => _isSuperLiking = false);
                                OptimisticActionGuard.end('SWIPE_SUPER:${_currentUser.id}');
                                // Background-sync quota counts with backend
                                subProvider.refresh();
                              }
                            },
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      _isSuperLiking ? 'Superliking...' : (isSuperLiked ? 'SUPER LIKED' : 'Super Like'),
                      key: ValueKey('${isSuperLiked}_$_isSuperLiking'),
                      style: TextStyle(
                        fontSize: 11,
                        color: isSuperLiked
                            ? const Color(0xFFFFD700)
                            : (isDark ? Colors.white60 : Colors.black54),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
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

  Widget _actionButton(
    String label,
    Color bgColor,
    Color textColor,
    VoidCallback onTap, {
    bool isOutlined = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isOutlined ? Colors.transparent : bgColor,
          borderRadius: BorderRadius.circular(16),
          border: isOutlined ? Border.all(color: Colors.grey[200]!) : null,
          gradient: !isOutlined && bgColor == LunaraTheme.electricViolet
              ? LunaraTheme.purpleGradient
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isOutlined ? Colors.black : textColor,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }


  Widget _buildDetailsSection() {
    final user = _currentUser;
    final List<Map<String, dynamic>> details = [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (user.occupation != null && user.occupation!.isNotEmpty) {
      String occ = user.occupation!;
      if (user.company != null && user.company!.isNotEmpty) {
        occ += ' at ${user.company}';
      }
      details.add({'icon': Icons.work_outline_rounded, 'label': occ});
    } else if (user.company != null && user.company!.isNotEmpty) {
      details.add({'icon': Icons.business_outlined, 'label': user.company});
    }

    if (user.education != null && user.education!.isNotEmpty) {
      details.add({'icon': Icons.school_outlined, 'label': user.education});
    }

    if (user.smokingPreference != null && user.smokingPreference!.isNotEmpty) {
      details.add({
        'icon': Icons.smoke_free_rounded,
        'label': user.smokingPreference,
      });
    }

    if (user.budgetRange != null && user.budgetRange!.isNotEmpty) {
      details.add({
        'icon': Icons.currency_rupee_rounded,
        'label': 'Budget: ${user.budgetRange}',
      });
    }

    if (details.isEmpty &&
        user.musicPreference.isEmpty &&
        user.lookingFor.isEmpty &&
        user.interests.isEmpty &&
        user.nightlifePreference.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  gradient: LunaraTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ABOUT ME',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: 1,
                  fontFamily: 'AllroundGothic',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (details.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: details.map((d) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.purple.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: LunaraTheme.electricViolet.withValues(
                        alpha: isDark ? 0.35 : 0.15,
                      ),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        d['icon'] as IconData,
                        size: 16,
                        color: LunaraTheme.electricViolet,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          (d['label'] as String).toUpperCase(),
                          style: TextStyle(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.9)
                                : Colors.black87,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),

          if (user.nightlifePreference.isNotEmpty) ...[
            if (details.isNotEmpty) const SizedBox(height: 24),
            _buildTagsList(
              'NIGHTLIFE PREFERENCE',
              user.nightlifePreference,
              isDark,
            ),
          ],

          if (user.interests.isNotEmpty) ...[
            if (details.isNotEmpty || user.nightlifePreference.isNotEmpty)
              const SizedBox(height: 24),
            _buildTagsList('INTERESTS', user.interests, isDark),
          ],

          if (user.musicPreference.isNotEmpty) ...[
            if (details.isNotEmpty ||
                user.nightlifePreference.isNotEmpty ||
                user.interests.isNotEmpty)
              const SizedBox(height: 24),
            _buildTagsList('MUSIC PREFERENCES', user.musicPreference, isDark),
          ],

          if (user.lookingFor.isNotEmpty) ...[
            if (details.isNotEmpty ||
                user.nightlifePreference.isNotEmpty ||
                user.interests.isNotEmpty ||
                user.musicPreference.isNotEmpty)
              const SizedBox(height: 24),
            _buildTagsList('LOOKING FOR', user.lookingFor, isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildTagsList(String title, List<String> items, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            LunaraTheme.electricViolet.withValues(alpha: isDark ? 0.1 : 0.05),
            LunaraTheme.cyberCyan.withValues(alpha: isDark ? 0.1 : 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(
            alpha: isDark ? 0.3 : 0.15,
          ),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: LunaraTheme.electricViolet.withValues(
              alpha: isDark ? 0.1 : 0.05,
            ),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  gradient: LunaraTheme.secondaryGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white70 : Colors.black87,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((item) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: LunaraTheme.cyberCyan.withValues(
                      alpha: isDark ? 0.35 : 0.18,
                    ),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  item.toUpperCase(),
                  style: TextStyle(
                    color: isDark
                        ? LunaraTheme.cyberCyan
                        : LunaraTheme.electricViolet,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }


  Widget _buildViewPlansButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: _showActivePlansPopup,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: LunaraTheme.purpleGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.calendar_month_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'VIEW PLANS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActivePlansPopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return _ActivePlansBottomSheet(
          targetUserId: _currentUser.id,
          targetUserName: _currentUser.fullName,
        );
      },
    );
  }
}

class _ActivePlansBottomSheet extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;

  const _ActivePlansBottomSheet({
    required this.targetUserId,
    required this.targetUserName,
  });

  @override
  State<_ActivePlansBottomSheet> createState() =>
      _ActivePlansBottomSheetState();
}

class _ActivePlansBottomSheetState extends State<_ActivePlansBottomSheet> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _plans = [];
  Set<String> _requestedPlanIds = {};
  final Set<String> _joiningPlanIds = {};

  @override
  void initState() {
    super.initState();
    _loadPlans();
    _initListeners();
  }

  @override
  void dispose() {
    _disposeListeners();
    super.dispose();
  }

  void _initListeners() {
    ApiService.planPostedNotifier.addListener(_onAutoRefresh);
    ApiService.addSocketListener('party_plan_created', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_deleted', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_request_updated', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_request_accepted', _onSocketUpdate);
    ApiService.addSocketListener('strangers_meet_updated', _onSocketUpdate);
  }

  void _disposeListeners() {
    ApiService.planPostedNotifier.removeListener(_onAutoRefresh);
    ApiService.removeSocketListener('party_plan_created', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_deleted', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_request_updated', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_request_accepted', _onSocketUpdate);
    ApiService.removeSocketListener('strangers_meet_updated', _onSocketUpdate);
  }

  void _onAutoRefresh() {
    if (!mounted) return;
    _loadPlans();
  }

  void _onSocketUpdate(dynamic data) {
    if (!mounted) return;
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        ApiService.fetchUserPartyPlans(widget.targetUserId),
        ApiService.fetchUserStrangersMeets(widget.targetUserId),
        ApiService.fetchMyPartyPlanRequests(),
        ApiService.fetchJoinedStrangersMeets(),
      ]);

      final List<Map<String, dynamic>> partyPlans =
          (results[0] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final List<Map<String, dynamic>> strangersMeets =
          (results[1] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final List<Map<String, dynamic>> myPartyRequests =
          (results[2] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final List<StrangersMeetRequest> myJoinedMeets =
          (results[3] as List?)?.cast<StrangersMeetRequest>() ?? [];

      final now = DateTime.now();

      // Filter and tag Party Plans
      final activePartyPlans = partyPlans.where((plan) {
        final status = (plan['status'] ?? 'active').toString().toLowerCase();
        if (status != 'active') return false;
        final rawDateTime = plan['actualPlanDateTime'] ?? plan['planDateTime'];
        if (rawDateTime != null) {
          final planDateTime = DateTime.tryParse(rawDateTime.toString());
          if (planDateTime != null && planDateTime.isBefore(now)) return false;
        }
        return true;
      }).map((p) => {...p, 'planType': 'party_plan'}).toList();

      // Filter and tag Strangers Meets
      final activeStrangersMeets = strangersMeets.where((meet) {
        final status = (meet['status'] ?? '').toString().toLowerCase();
        if (status == 'rejected' || status == 'cancelled' || status == 'not_started') return false;
        final rawDateTime = meet['eventDateTime'];
        if (rawDateTime != null) {
          final meetDateTime = DateTime.tryParse(rawDateTime.toString());
          if (meetDateTime != null &&
              meetDateTime.isBefore(now.subtract(const Duration(hours: 6)))) {
            return false;
          }
        }
        return true;
      }).map((m) => {...m, 'planType': 'strangers_meet'}).toList();

      // Merge and sort all plans chronologically
      final allActivePlans = [...activePartyPlans, ...activeStrangersMeets];
      allActivePlans.sort((a, b) {
        final dtA = DateTime.tryParse(
              (a['planDateTime'] ?? a['eventDateTime'] ?? '').toString(),
            ) ??
            now;
        final dtB = DateTime.tryParse(
              (b['planDateTime'] ?? b['eventDateTime'] ?? '').toString(),
            ) ??
            now;
        return dtA.compareTo(dtB);
      });

      // Collect plan IDs that current user has already requested to join
      final requestedIds = ApiService.getRequestedPlanIdsSync();
      for (final req in myPartyRequests) {
        final planId =
            req['partyPlanId']?.toString() ?? req['planId']?.toString();
        if (planId != null) {
          requestedIds.add(planId);
        }
      }
      for (final joined in myJoinedMeets) {
        requestedIds.add(joined.id);
      }

      if (mounted) {
        setState(() {
          _plans = allActivePlans;
          _requestedPlanIds = requestedIds;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading plans in bottom sheet: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatDateTime(dynamic raw) {
    if (raw == null) return 'TBD';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return DateFormat('EEE, dd MMM yyyy • hh:mm a').format(dt);
    } catch (_) {
      return raw.toString();
    }
  }

  Future<void> _sendJoinRequest(String planId) async {
    if (_requestedPlanIds.contains(planId)) return;
    if (!OptimisticActionGuard.start('PROFILE_JOIN_PLAN:$planId')) return;

    try {
      final res = await ApiService.requestToJoinPartyPlanDetailed(planId);
      if (!mounted) return;

      if (res.alreadyRequested || res.success) {
        setState(() {
          _requestedPlanIds.add(planId);
        });
        ApiService.planPostedNotifier.value++;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            behavior: SnackBarBehavior.floating,
            content: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                gradient: LunaraTheme.purpleGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'JOIN REQUEST SENT! THE HOST WILL REVIEW IT.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        if (TimeLockBlockedDialog.isConflictError(res.message) ||
            (res.rawData != null && res.rawData!['allowed'] == false)) {
          TimeLockBlockedDialog.show(
            context,
            errorData: res.rawData ?? {'message': res.message},
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TimeLockBlockedDialog.cleanErrorMessage(res.message)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        if (TimeLockBlockedDialog.isConflictError(e)) {
          TimeLockBlockedDialog.showWithMessage(context, e.toString());
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TimeLockBlockedDialog.cleanErrorMessage(e)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      OptimisticActionGuard.end('PROFILE_JOIN_PLAN:$planId');
    }
  }

  Future<void> _sendStrangersMeetJoin(Map<String, dynamic> meet) async {
    final meetId = meet['id']?.toString() ?? '';
    if (meetId.isEmpty || _joiningPlanIds.contains(meetId) || _requestedPlanIds.contains(meetId)) return;

    final String subject = meet['subject']?.toString() ?? 'Strangers Meetup';
    String selectedFood = 'Any';
    String selectedDrink = 'Any';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.fromLTRB(
                24,
                20,
                24,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF140727) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'JOIN STRANGERS MEET',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: 1,
                      fontFamily: 'AllroundGothic',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subject,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? LunaraTheme.cyberCyan
                          : LunaraTheme.electricViolet,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'FOOD PREFERENCE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white60 : Colors.black54,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: ['Veg', 'Non-Veg', 'Any'].map((pref) {
                      final isSelected = selectedFood == pref;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setModalState(() => selectedFood = pref),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? LunaraTheme.electricViolet.withValues(alpha: 0.2)
                                  : (isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.grey[100]),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? LunaraTheme.electricViolet
                                    : (isDark ? Colors.white12 : Colors.black12),
                              ),
                            ),
                            child: Text(
                              pref,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w900
                                    : FontWeight.w600,
                                color: isSelected
                                    ? (isDark
                                        ? Colors.white
                                        : LunaraTheme.electricViolet)
                                    : (isDark ? Colors.white70 : Colors.black87),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'DRINK PREFERENCE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white60 : Colors.black54,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: ['Alcoholic', 'Non-Alcoholic', 'Any'].map((pref) {
                      final isSelected = selectedDrink == pref;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setModalState(() => selectedDrink = pref),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? LunaraTheme.cyberCyan.withValues(alpha: 0.2)
                                  : (isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.grey[100]),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? LunaraTheme.cyberCyan
                                    : (isDark ? Colors.white12 : Colors.black12),
                              ),
                            ),
                            child: Text(
                              pref,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w900
                                    : FontWeight.w600,
                                color: isSelected
                                    ? (isDark
                                        ? LunaraTheme.cyberCyan
                                        : Colors.teal[800])
                                    : (isDark ? Colors.white70 : Colors.black87),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LunaraTheme.electricViolet,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text(
                        'SUBMIT JOIN REQUEST',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    if (!OptimisticActionGuard.start('PROFILE_SM_JOIN:$meetId')) return;

    try {
      final success = await ApiService.sendStrangersMeetJoinRequest(
        meetId,
        foodPreference: selectedFood,
        drinkPreference: selectedDrink,
      );
      if (!mounted) return;

      if (success) {
        setState(() => _requestedPlanIds.add(meetId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text(
              'Join request sent for "$subject"! The host will review it. 🎉',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('Failed to send join request. Please try again.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (TimeLockBlockedDialog.isConflictError(e)) {
          TimeLockBlockedDialog.showWithMessage(context, e.toString());
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TimeLockBlockedDialog.cleanErrorMessage(e)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      OptimisticActionGuard.end('PROFILE_SM_JOIN:$meetId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F001E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Drag Indicator
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 16),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ACTIVE PLANS',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : Colors.black,
                              letterSpacing: 1.5,
                              fontFamily: 'AllroundGothic',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'PLANS BY ${widget.targetUserName.toUpperCase()}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: isDark
                                  ? LunaraTheme.cyberCyan
                                  : LunaraTheme.electricViolet,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Divider(color: isDark ? Colors.white10 : Colors.black12),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: LunaraTheme.electricViolet,
                        ),
                      )
                    : _plans.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 64,
                              color: isDark ? Colors.white24 : Colors.black26,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'NO ACTIVE PLANS CURRENTLY',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white54 : Colors.black54,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                        itemCount: _plans.length,
                        itemBuilder: (context, index) {
                          final plan = _plans[index];
                          final isStrangersMeet =
                              plan['planType'] == 'strangers_meet';
                          final planId = plan['id']?.toString() ??
                              plan['planId']?.toString() ??
                              '';
                          final venue =
                              plan['venue'] as Map<String, dynamic>? ?? {};
                          final venueName =
                              venue['name'] as String? ?? 'Venue';
                          final formattedDate = _formatDateTime(
                            plan['eventDateTime'] ??
                                plan['planDateTime'] ??
                                plan['planDate'],
                          );
                          final hasRequested = _requestedPlanIds.contains(
                            planId,
                          );
                          final isJoining = _joiningPlanIds.contains(planId);

                          if (isStrangersMeet) {
                            final subject =
                                plan['subject'] as String? ?? 'Strangers Meetup';
                            final tagline = plan['tagline'] as String? ?? '';
                            final numberOfPersons =
                                plan['numberOfPersons'] ?? 20;
                            final slotsFilled = plan['slotsFilled'] ??
                                plan['joinedCount'] ??
                                0;
                            final chargesPerHead =
                                NumberFormat('#,##0').format(
                                  plan['chargesPerHead'] ?? 0,
                                );
                            final dynamicStatus =
                                plan['dynamicStatus'] as String? ?? 'NEW';

                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PostDetailScreen(
                                      post: plan,
                                      venue: venue,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.04)
                                      : Colors.grey[50],
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isDark
                                        ? LunaraTheme.cyberCyan.withValues(alpha: 0.25)
                                        : Colors.teal.withValues(alpha: 0.2),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: isDark ? 0.25 : 0.04,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: LunaraTheme.cyberCyan
                                                .withValues(alpha: 0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.groups_rounded,
                                            color: LunaraTheme.cyberCyan,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: LunaraTheme.cyberCyan
                                                          .withValues(alpha: 0.15),
                                                      borderRadius:
                                                          BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: LunaraTheme.cyberCyan
                                                            .withValues(alpha: 0.3),
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      '🤝 STRANGERS MEETUP',
                                                      style: TextStyle(
                                                        color: LunaraTheme.cyberCyan,
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.amberAccent
                                                          .withValues(alpha: 0.15),
                                                      borderRadius:
                                                          BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      dynamicStatus,
                                                      style: const TextStyle(
                                                        color: Colors.amberAccent,
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                subject,
                                                style: TextStyle(
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                              if (tagline.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  tagline,
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.white70
                                                        : Colors.black87,
                                                    fontSize: 12,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.black.withValues(alpha: 0.25)
                                            : Colors.grey[100],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.location_on_rounded,
                                                size: 14,
                                                color: LunaraTheme.cyberCyan,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  venueName,
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.white
                                                        : Colors.black87,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.calendar_today_rounded,
                                                size: 13,
                                                color: Colors.grey,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  formattedDate,
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.white70
                                                        : Colors.black54,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.person_outline_rounded,
                                                size: 14,
                                                color: Colors.amber,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '$slotsFilled / $numberOfPersons SPOTS',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.amber,
                                                ),
                                              ),
                                              const Spacer(),
                                              Text(
                                                '₹$chargesPerHead / person',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w900,
                                                  color: Colors.green,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 46,
                                      child: hasRequested
                                          ? Container(
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: Colors.green.withValues(
                                                  alpha: 0.15,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                border: Border.all(
                                                  color: Colors.green.withValues(
                                                    alpha: 0.4,
                                                  ),
                                                ),
                                              ),
                                              child: const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.check_circle_rounded,
                                                    color: Colors.green,
                                                    size: 18,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'REQUEST SENT / JOINED',
                                                    style: TextStyle(
                                                      color: Colors.green,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                      letterSpacing: 1,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    LunaraTheme.cyberCyan,
                                                foregroundColor: Colors.black,
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                              ),
                                              onPressed: isJoining
                                                  ? null
                                                  : () => _sendStrangersMeetJoin(
                                                        plan,
                                                      ),
                                              icon: isJoining
                                                  ? const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.black,
                                                      ),
                                                    )
                                                  : const Icon(
                                                      Icons.group_add_rounded,
                                                      size: 18,
                                                    ),
                                              label: Text(
                                                isJoining
                                                    ? 'SENDING...'
                                                    : 'JOIN STRANGERS MEET',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 12,
                                                  letterSpacing: 1,
                                                ),
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          // Party Plan Card
                          final description =
                              plan['description'] as String? ?? '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.grey[50],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.05),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: isDark ? 0.2 : 0.02,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: LunaraTheme.electricViolet
                                            .withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.nightlife_rounded,
                                        color: LunaraTheme.electricViolet,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: LunaraTheme.electricViolet
                                                      .withValues(alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: LunaraTheme.electricViolet
                                                        .withValues(alpha: 0.3),
                                                  ),
                                                ),
                                                child: const Text(
                                                  '🎉 PARTY PLAN',
                                                  style: TextStyle(
                                                    color: LunaraTheme.electricViolet,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w900,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            venueName.toUpperCase(),
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            formattedDate,
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.white60
                                                  : Colors.black54,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (description.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    description,
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 16),
                                // Button
                                SizedBox(
                                  width: double.infinity,
                                  height: 46,
                                  child: hasRequested
                                      ? Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: Colors.green.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                              color: Colors.green.withValues(
                                                alpha: 0.4,
                                              ),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.check_circle_rounded,
                                                color: Colors.green,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'REQUEST SENT',
                                                style: TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  letterSpacing: 1,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                LunaraTheme.electricViolet,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                          onPressed: isJoining
                                              ? null
                                              : () => _sendJoinRequest(planId),
                                          icon: isJoining
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons
                                                      .add_circle_outline_rounded,
                                                  size: 18,
                                                ),
                                          label: Text(
                                            isJoining
                                                ? 'SENDING...'
                                                : 'REQUEST TO JOIN',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
