import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../services/subscription_provider.dart';
import '../../widgets/subscription_limit_dialog.dart';
import '../profile/profile_detail_view.dart';
import '../profile/vip_membership_screen.dart';
import '../../widgets/lunara_cached_image.dart';

class PeopleWhoLikedYouScreen extends StatefulWidget {
  const PeopleWhoLikedYouScreen({super.key});

  @override
  State<PeopleWhoLikedYouScreen> createState() => _PeopleWhoLikedYouScreenState();
}

class _PeopleWhoLikedYouScreenState extends State<PeopleWhoLikedYouScreen> {
  final List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _page = 1;
  int _totalCount = 0;
  bool _hasMore = false;
  bool _isVipLocked = false;
  final Set<String> _processingIds = {};
  final Set<String> _matchedIds = {};

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadLikes();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _loadMoreLikes();
      }
    }
  }

  Future<void> _loadLikes() async {
    setState(() {
      _isLoading = true;
      _page = 1;
      _isVipLocked = false;
    });

    try {
      final res = await ApiService.fetchPeopleWhoLikedMe(page: 1, limit: 20);
      if (!mounted) return;

      if (res['locked'] == true) {
        final pagination = res['pagination'] as Map<String, dynamic>?;
        final total = pagination?['total'] ?? 0;
        setState(() {
          _isVipLocked = true;
          _totalCount = total is int ? total : int.tryParse(total.toString()) ?? 0;
          _isLoading = false;
        });
        return;
      }

      final List<dynamic> usersRaw = res['users'] ?? res['data'] ?? [];
      final List<Map<String, dynamic>> loaded = [];
      for (var u in usersRaw) {
        if (u is Map<String, dynamic>) {
          loaded.add(u);
        }
      }

      final pagination = res['pagination'] as Map<String, dynamic>?;
      final total = pagination?['total'] ?? loaded.length;
      final totalPages = pagination?['totalPages'] ?? 1;

      setState(() {
        _profiles.clear();
        _profiles.addAll(loaded);
        _totalCount = total is int ? total : int.tryParse(total.toString()) ?? loaded.length;
        _hasMore = _page < (totalPages is int ? totalPages : 1);
        _isVipLocked = false;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[PeopleWhoLikedYouScreen] Error loading likes: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreLikes() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _page + 1;
      final res = await ApiService.fetchPeopleWhoLikedMe(page: nextPage, limit: 20);
      if (!mounted) return;

      final List<dynamic> usersRaw = res['users'] ?? res['data'] ?? [];
      final List<Map<String, dynamic>> loaded = [];
      for (var u in usersRaw) {
        if (u is Map<String, dynamic>) {
          loaded.add(u);
        }
      }

      final pagination = res['pagination'] as Map<String, dynamic>?;
      final totalPages = pagination?['totalPages'] ?? nextPage;

      setState(() {
        _page = nextPage;
        _profiles.addAll(loaded);
        _hasMore = _page < (totalPages is int ? totalPages : nextPage);
        _isLoadingMore = false;
      });
    } catch (e) {
      debugPrint('[PeopleWhoLikedYouScreen] Error loading more likes: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _onLikeBack(Map<String, dynamic> item) async {
    final targetUserId = item['id']?.toString() ?? '';
    if (targetUserId.isEmpty || _processingIds.contains(targetUserId)) return;

    setState(() => _processingIds.add(targetUserId));

    try {
      final res = await ApiService.swipeUser(targetUserId: targetUserId, action: 'like');
      if (!mounted) return;

      if (res != null && res['limitReached'] == true) {
        showSubscriptionLimitDialog(
          context,
          feature: SubLimitFeature.dailyLikes,
          customMessage: res['message'],
        );
        setState(() => _processingIds.remove(targetUserId));
        return;
      }

      final isMatch = res != null && res['matched'] == true;
      if (isMatch) {
        setState(() {
          _matchedIds.add(targetUserId);
        });
        _showMatchDialog(item);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You liked ${item['fullName'] ?? 'them'} back! ❤️'),
            backgroundColor: LunaraTheme.electricViolet,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {
          _profiles.removeWhere((p) => p['id']?.toString() == targetUserId);
          if (_totalCount > 0) _totalCount--;
        });
      }
    } catch (e) {
      debugPrint('Error liking back: $e');
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(targetUserId));
      }
    }
  }

  void _onPass(Map<String, dynamic> item) {
    final targetUserId = item['id']?.toString() ?? '';
    setState(() {
      _profiles.removeWhere((p) => p['id']?.toString() == targetUserId);
      if (_totalCount > 0) _totalCount--;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Passed on ${item['fullName'] ?? 'profile'}'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showMatchDialog(Map<String, dynamic> item) {
    final photoUrl = item['profilePhoto']?.toString() ?? item['image']?.toString() ?? '';
    final formattedPhoto = ApiService.formatImageUrl(photoUrl) ?? photoUrl;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E1035), Color(0xFF0F0826)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: LunaraTheme.accentVivid.withValues(alpha: 0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: LunaraTheme.accentVivid.withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎉', style: TextStyle(fontSize: 44)),
                const SizedBox(height: 12),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFFF007F), Color(0xFF00F5FF)],
                  ).createShader(bounds),
                  child: const Text(
                    "IT'S A MATCH!",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You and ${item['fullName'] ?? 'they'} liked each other!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 24),
                // Profile Avatar
                CircleAvatar(
                  radius: 46,
                  backgroundImage: formattedPhoto.isNotEmpty
                      ? NetworkImage(formattedPhoto)
                      : const NetworkImage('https://picsum.photos/200'),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _profiles.removeWhere((p) => p['id']?.toString() == item['id']?.toString());
                      if (_totalCount > 0) _totalCount--;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LunaraTheme.accentVivid,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'KEEP BROWSING',
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090414),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0826),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PEOPLE WHO LIKED YOU',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: Colors.white,
              ),
            ),
            if (!_isLoading && !_isVipLocked)
              Text(
                '$_totalCount ${_totalCount == 1 ? "person" : "people"} interested in you',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 22),
            tooltip: 'Refresh',
            onPressed: () {
              SubscriptionProvider.instance.refresh();
              _loadLikes();
            },
          ),
          if (!_isVipLocked)
            Container(
              margin: const EdgeInsets.only(right: 14, top: 12, bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFB703), Color(0xFFFF8800)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium, color: Colors.black, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'VIP',
                    style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: LunaraTheme.accentVivid),
            SizedBox(height: 16),
            Text(
              'Loading who liked you...',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_isVipLocked) {
      return _buildVipLockBanner();
    }

    if (_profiles.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      color: LunaraTheme.accentVivid,
      backgroundColor: const Color(0xFF161622),
      onRefresh: () async {
        await SubscriptionProvider.instance.refresh();
        await _loadLikes();
      },
      child: GridView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.68,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        itemCount: _profiles.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _profiles.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(color: LunaraTheme.accentVivid),
              ),
            );
          }
          final item = _profiles[index];
          return _buildProfileCard(item);
        },
      ),
    );
  }

  Widget _buildProfileCard(Map<String, dynamic> item) {
    final isSuperLike = item['isSuperLike'] == true || item['matchReason'] == 'superlike' || item['actionType'] == 'superlike';
    final rawPhoto = item['profilePhoto']?.toString() ?? item['image']?.toString() ?? '';
    final photoUrl = ApiService.formatImageUrl(rawPhoto) ?? rawPhoto;
    final name = (item['fullName']?.toString() ?? item['name'] ?? 'LUNARA USER').toUpperCase();
    final age = item['age'] != null ? ', ${item['age']}' : '';
    final city = item['city']?.toString() ?? '';
    final targetUserId = item['id']?.toString() ?? '';
    final isProcessing = _processingIds.contains(targetUserId);
    final isMatched = _matchedIds.contains(targetUserId) || item['isMutualMatch'] == true;

    return GestureDetector(
      onTap: () {
        try {
          final List<dynamic> rawInterests = item['interests'] is List ? item['interests'] : [];
          final List<String> interestsList = rawInterests.map((e) => e.toString()).toList();

          final userObj = User(
            id: targetUserId,
            firstName: (item['firstName'] ?? item['name'] ?? item['fullName'] ?? 'User').toString(),
            lastName: (item['lastName'] ?? '').toString(),
            email: '',
            phone: '',
            profilePhoto: photoUrl,
            photos: photoUrl.isNotEmpty ? [photoUrl] : [],
            photoDetails: photoUrl.isNotEmpty ? [{'url': photoUrl}] : [],
            age: item['age'] is int ? item['age'] : int.tryParse(item['age']?.toString() ?? ''),
            city: item['city']?.toString(),
            occupation: item['occupation']?.toString() ?? item['vibe']?.toString(),
            bio: item['bio']?.toString(),
            interests: interestsList,
            isSuperLiked: isSuperLike,
          );

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileDetailView(
                user: userObj,
                isMe: false,
                onLike: () async {
                  await _onLikeBack(item);
                },
              ),
            ),
          );
        } catch (e) {
          debugPrint('Error opening profile: $e');
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSuperLike
                ? const Color(0xFF00E5FF)
                : Colors.white.withValues(alpha: 0.12),
            width: isSuperLike ? 2.0 : 1.0,
          ),
          boxShadow: isSuperLike
              ? [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo
              if (photoUrl.isNotEmpty)
                LunaraCachedImage(
                  photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: const Color(0xFF1E1035),
                    child: const Icon(Icons.person, color: Colors.white24, size: 50),
                  ),
                )
              else
                Container(
                  color: const Color(0xFF1E1035),
                  child: const Icon(Icons.person, color: Colors.white24, size: 50),
                ),

              // Top Superlike badge
              if (isSuperLike)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF7F00FF)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'SUPER LIKE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Bottom Gradient Overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 140,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.95),
                        Colors.black.withValues(alpha: 0.5),
                        Colors.transparent,
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ),
              ),

              // User details & Quick Actions
              Positioned(
                bottom: 10,
                left: 10,
                right: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$name$age',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (city.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on, color: LunaraTheme.accentVivid, size: 11),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                city.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    // Actions (Pass / Like Back)
                    if (isMatched)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF10B981)),
                        ),
                        child: const Center(
                          child: Text(
                            'MATCHED ✓',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _onPass(item),
                              child: Container(
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: const Icon(Icons.close, color: Colors.white70, size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: isProcessing ? null : () => _onLikeBack(item),
                              child: Container(
                                height: 36,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFF007F), Color(0xFFFF5252)],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF007F).withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: isProcessing
                                    ? const Center(
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : const Icon(Icons.favorite, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: LunaraTheme.accentVivid.withValues(alpha: 0.1),
                border: Border.all(color: LunaraTheme.accentVivid.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.favorite_border, color: LunaraTheme.accentVivid, size: 44),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Likes Yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'When someone likes your profile, they will show up here immediately.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                final provider = SubscriptionProvider.instance;
                if (provider.canBoost) {
                  ApiService.useBoost().then((res) {
                    if (res['success'] == true && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('⚡ Boost active! Your profile is in the spotlight!'),
                          backgroundColor: Color(0xFF7F00FF),
                        ),
                      );
                      provider.refresh();
                    }
                  });
                } else {
                  showSubscriptionLimitDialog(context, feature: SubLimitFeature.boost);
                }
              },
              icon: const Icon(Icons.bolt, color: Colors.black, size: 18),
              label: const Text(
                'BOOST PROFILE',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVipLockBanner() {
    final countText = _totalCount > 0
        ? '$_totalCount ${_totalCount == 1 ? "person has" : "people have"} liked your profile!'
        : 'People are waiting to connect with you!';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF7F00FF), Color(0xFFFF007F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF007F).withValues(alpha: 0.35),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 46),
            ),
            const SizedBox(height: 22),
            const Text(
              'SEE WHO LIKES YOU',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              countText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Unlock VIP Membership to instantly see unblurred photos, full profiles, and match without waiting!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 24),
            // Benefits container
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const Column(
                children: [
                  _VipBenefitRow(icon: Icons.visibility_rounded, text: 'See all likers and their full photos'),
                  SizedBox(height: 10),
                  _VipBenefitRow(icon: Icons.favorite_rounded, text: 'Match & chat immediately'),
                  SizedBox(height: 10),
                  _VipBenefitRow(icon: Icons.all_inclusive_rounded, text: 'Unlimited likes & daily super likes'),
                ],
              ),
            ),
            const SizedBox(height: 26),
            ElevatedButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VIPMembershipScreen()),
                );
                if (mounted) {
                  await SubscriptionProvider.instance.refresh();
                  _loadLikes();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.accentVivid,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 6,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.workspace_premium_rounded, size: 20, color: Colors.black),
                  SizedBox(width: 8),
                  Text(
                    'UNLOCK WITH VIP',
                    style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VipBenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _VipBenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: LunaraTheme.accentVivid.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: LunaraTheme.accentVivid, size: 14),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
