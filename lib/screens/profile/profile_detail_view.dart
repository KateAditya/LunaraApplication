import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:lunara_app/core/theme.dart';
import 'package:lunara_app/models/user.dart';
import 'settings_screen.dart';
import 'edit_profile_screen.dart';
import '../../services/block_service.dart';
import '../../services/api_service.dart';
import 'package:intl/intl.dart';

class ProfileDetailView extends StatefulWidget {
  final User user;
  final bool isMe;
  final VoidCallback? onNope;
  final VoidCallback? onLike;
  final VoidCallback? onSuper;
  final VoidCallback? onBacktrack;
  final bool canBacktrack;

  const ProfileDetailView({
    super.key,
    required this.user,
    required this.isMe,
    this.onNope,
    this.onLike,
    this.onSuper,
    this.onBacktrack,
    this.canBacktrack = false,
  });

  @override
  State<ProfileDetailView> createState() => _ProfileDetailViewState();
}

class _ProfileDetailViewState extends State<ProfileDetailView> {
  int _currentPhotoIndex = 0;
  bool _isBlocked = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isMe) {
      _checkBlockStatus();
    }
  }

  Future<void> _checkBlockStatus() async {
    final isBlocked = await BlockService.isUserBlocked(widget.user.id);
    if (mounted) {
      setState(() {
        _isBlocked = isBlocked;
      });
    }
  }

  Future<void> _toggleBlock() async {
    if (_isBlocked) {
      await BlockService.unblockUser(widget.user.id);
    } else {
      await BlockService.blockUser(widget.user.id);
    }
    _checkBlockStatus();
  }

  void _reportUser() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report User'),
        content: const Text(
          'Are you sure you want to report and block this user?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await BlockService.reportUser(
                widget.user.id,
                'Inappropriate profile content',
              );
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
    if (widget.user.photos.isNotEmpty) {
      return widget.user.photos;
    }
    if (widget.user.profilePhoto != null &&
        widget.user.profilePhoto!.isNotEmpty) {
      return [widget.user.profilePhoto!];
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
    if (widget.user.bio != null && widget.user.bio!.isNotEmpty) {
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            widget.user.bio!,
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
    if (widget.user.occupation != null && widget.user.occupation!.isNotEmpty) {
      String occ = widget.user.occupation!;
      if (widget.user.company != null && widget.user.company!.isNotEmpty) {
        occ += ' at ${widget.user.company}';
      }
      workEduRows.add(_buildInfoRow(Icons.work_outline_rounded, occ));
    } else if (widget.user.company != null && widget.user.company!.isNotEmpty) {
      workEduRows.add(
        _buildInfoRow(Icons.business_outlined, widget.user.company!),
      );
    }
    if (widget.user.education != null && widget.user.education!.isNotEmpty) {
      workEduRows.add(
        _buildInfoRow(Icons.school_outlined, widget.user.education!),
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
    if (widget.user.musicPreference.isNotEmpty) {
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
                children: widget.user.musicPreference.take(3).map((genre) {
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
    if (widget.user.lookingFor.isNotEmpty) {
      prefRows.add(
        _buildInfoRow(
          Icons.search_rounded,
          'Looking for: ${widget.user.lookingFor.join(", ")}',
        ),
      );
    }
    if (widget.user.smokingPreference != null &&
        widget.user.smokingPreference!.isNotEmpty) {
      prefRows.add(
        _buildInfoRow(Icons.smoke_free_rounded, widget.user.smokingPreference!),
      );
    }
    if (widget.user.budgetRange != null &&
        widget.user.budgetRange!.isNotEmpty) {
      prefRows.add(
        _buildInfoRow(
          Icons.currency_rupee_rounded,
          'Budget: ${widget.user.budgetRange}',
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

    return Scaffold(
      backgroundColor: Colors.white,
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
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
                  const SizedBox(height: 32),
                  _buildPhotoGridLabel(),
                  _buildPhotoGrid(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    final photos = _userPhotos;
    final photo = photos.isNotEmpty && _currentPhotoIndex < photos.length
        ? photos[_currentPhotoIndex]
        : widget.user.profilePhoto;

    final infoSections = _buildDynamicInfoSections();
    final int sectionIndex = infoSections.isNotEmpty
        ? _currentPhotoIndex % infoSections.length
        : 0;
    final Widget activeSection = infoSections.isNotEmpty
        ? infoSections[sectionIndex]
        : const SizedBox.shrink();

    return SliverAppBar(
      expandedHeight: MediaQuery.of(context).size.height,
      pinned: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.35),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (widget.isMe)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ClipOval(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.35),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white,
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ClipOval(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.35),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
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
            ),
          ),
      ],
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
                              widget.user.fullName.toUpperCase(),
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
                          if (widget.user.age != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              ', ${widget.user.age}',
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
                          if (widget.user.isVerified) ...[
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
                                  (widget.user.city ?? 'UNKNOWN CITY')
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
                          if (widget.user.gender != null)
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
                                widget.user.gender!.toUpperCase(),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                      builder: (_) => EditProfileScreen(user: widget.user),
                    ),
                  );
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
                () {},
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
                    BoxShadow(
                      color: Colors.amber.withValues(
                        alpha: isDark ? 0.35 : 0.15,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
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
        // Nope button with label
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
                    blurRadius: 10,
                    offset: const Offset(0, 4),
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
        // Like button (larger) with label
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF00B5FF), Color(0xFF00E5FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFF00B5FF,
                    ).withValues(alpha: isDark ? 0.4 : 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.favorite, color: Colors.white),
                iconSize: 32,
                onPressed: widget.onLike,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Like',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.black54,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        // Super button with label
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF7F00FF), Color(0xFFB952EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFF7F00FF,
                    ).withValues(alpha: isDark ? 0.35 : 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.star, color: Colors.white),
                onPressed: widget.onSuper,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Super',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.black54,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
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

  Widget _buildPhotoGridLabel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
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
            'MOMENTS',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: 1,
              fontFamily: 'AllroundGothic',
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {},
            child: const Text(
              'VIEW ALL',
              style: TextStyle(
                color: LunaraTheme.electricViolet,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection() {
    final user = widget.user;
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

  Widget _buildPhotoGrid() {
    final photos = widget.user.photos;
    final int count = photos.isEmpty ? 0 : photos.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (count == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.grey[50],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey[200]!,
            ),
          ),
          child: const Center(
            child: Text(
              'No moments uploaded yet.',
              style: TextStyle(
                color: Colors.black38,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            final allPhotos = _userPhotos;
            final targetPhoto = photos[index];
            final targetIdx = allPhotos.indexOf(targetPhoto);
            if (targetIdx != -1) {
              setState(() {
                _currentPhotoIndex = targetIdx;
              });
            }
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.network(
              photos[index],
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.grey[50],
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
        );
      },
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
            gradient: const LinearGradient(
              colors: [LunaraTheme.electricViolet, LunaraTheme.cyberCyan],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
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
          targetUserId: widget.user.id,
          targetUserName: widget.user.fullName,
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
  }

  Future<void> _loadPlans() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        ApiService.fetchUserPartyPlans(widget.targetUserId),
        ApiService.fetchMyPartyPlanRequests(),
      ]);

      final List<Map<String, dynamic>> allPlans = results[0];
      final List<Map<String, dynamic>> myRequests = results[1];

      // Filter only active plans
      final activePlans = allPlans.where((plan) {
        final status = (plan['status'] ?? 'active').toString().toLowerCase();
        return status == 'active';
      }).toList();

      // Collect plan IDs that current user has already requested to join
      final requestedIds = <String>{};
      for (final req in myRequests) {
        final planId =
            req['partyPlanId']?.toString() ?? req['planId']?.toString();
        if (planId != null) {
          requestedIds.add(planId);
        }
      }

      if (mounted) {
        setState(() {
          _plans = activePlans;
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
    if (_joiningPlanIds.contains(planId)) return;

    setState(() {
      _joiningPlanIds.add(planId);
    });

    try {
      final success = await ApiService.requestToJoinPartyPlan(planId);
      if (success) {
        setState(() {
          _requestedPlanIds.add(planId);
        });
        if (mounted) {
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
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Failed to send request. You may have already requested.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _joiningPlanIds.remove(planId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
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
                          final planId =
                              plan['id']?.toString() ??
                              plan['planId']?.toString() ??
                              '';
                          final venue =
                              plan['venue'] as Map<String, dynamic>? ?? {};
                          final venueName = venue['name'] as String? ?? 'Venue';
                          final description =
                              plan['description'] as String? ?? '';
                          final formattedDate = _formatDateTime(
                            plan['planDate'] ?? plan['planDateTime'],
                          );
                          final hasRequested = _requestedPlanIds.contains(
                            planId,
                          );
                          final isJoining = _joiningPlanIds.contains(planId);

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
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
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
