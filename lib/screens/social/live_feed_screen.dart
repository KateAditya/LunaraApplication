import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme.dart';
import 'poster_profile_screen.dart';

import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../widgets/lunara_profile_image.dart';
import 'post_detail_screen.dart';
import '../discovery/payment_confirmation_screen.dart';
import '../../widgets/action_button.dart';

class LiveFeedScreen extends StatefulWidget {
  const LiveFeedScreen({super.key});

  @override
  State<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends State<LiveFeedScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  List<Map<String, dynamic>> _feedItems = [];
  bool _isLoading = true;
  Timer? _pollingTimer;

  Future<void> _loadFeed({bool showLoader = true}) async {
    if (showLoader) {
      setState(() => _isLoading = true);
    }
    try {
      final data = await ApiService.fetchLiveFeedData();
      
      List<Map<String, dynamic>> combined = [
        ...List<Map<String, dynamic>>.from(data['feed'] ?? []),
        ...List<Map<String, dynamic>>.from(data['myRequests'] ?? []),
        ...List<Map<String, dynamic>>.from(data['incomingRequests'] ?? []),
      ];

      combined.sort((a, b) {
        final dateA = DateTime.tryParse(a['postedAt']?.toString() ?? a['createdAt']?.toString() ?? '') ?? DateTime.now();
        final dateB = DateTime.tryParse(b['postedAt']?.toString() ?? b['createdAt']?.toString() ?? '') ?? DateTime.now();
        return dateB.compareTo(dateA);
      });

      if (mounted) {
        setState(() {
          _feedItems = combined;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading live feed: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatPlanDate(dynamic planDate) {
    if (planDate == null) return 'Tonight';
    try {
      final parsedDate = DateTime.parse(planDate.toString()).toLocal();
      final now = DateTime.now();
      if (parsedDate.year == now.year && parsedDate.month == now.month && parsedDate.day == now.day) {
        return 'Tonight';
      }
      final tomorrow = now.add(const Duration(days: 1));
      if (parsedDate.year == tomorrow.year && parsedDate.month == tomorrow.month && parsedDate.day == tomorrow.day) {
        return 'Tomorrow';
      }
      return DateFormat('E, dd MMM').format(parsedDate);
    } catch (_) {
      return planDate.toString();
    }
  }

  String _formatTimeAgo(dynamic postedAt) {
    if (postedAt == null) return '';
    try {
      final parsed = DateTime.parse(postedAt.toString()).toLocal();
      final diff = DateTime.now().difference(parsed);
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
      return 'Just now';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadFeed();
    
    // Automatically poll for updates every 30 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadFeed(showLoader: false);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _feedItems.length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildLiveIndicator(context, activeCount),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      color: LunaraTheme.accentVivid,
                      backgroundColor: Theme.of(context).cardTheme.color ?? Colors.white,
                      onRefresh: _loadFeed,
                      child: _feedItems.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                              children: [
                                _sectionLabel(context, 'PLANS NEAR YOU'),
                                const SizedBox(height: 40),
                                const Center(
                                  child: Text(
                                    'No active plans found near you.',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                              itemCount: _feedItems.length + 1,
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _sectionLabel(context, 'PLANS NEAR YOU'),
                                  );
                                }
                                final item = _feedItems[index - 1];
                                if (item['type'] == 'party_plan') {
                                  return _buildPartyPlanCard(context, item);
                                } else if (item['type'] == 'table_plan') {
                                  return _buildPlanCard(context, item);
                                } else if (item['type'] == 'my_request') {
                                  return _buildMyRequestCard(context, item);
                                } else if (item['type'] == 'incoming_request') {
                                  return _buildIncomingRequestCard(context, item);
                                } else {
                                  return const SizedBox.shrink();
                                }
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Row(
      children: [
        Text(
          label,
          style: LunaraTheme.headingStyle.copyWith(
            fontSize: 11,
            letterSpacing: 2,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5))),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            'LIVE FEED',
            style: LunaraTheme.headingStyle.copyWith(
              fontSize: 18,
              letterSpacing: 4,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          
        ],
      ),
    );
  }

  Widget _buildLiveIndicator(BuildContext context, int activeCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: _pulseAnimation.value),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(
                        alpha: _pulseAnimation.value * 0.5,
                      ),
                      blurRadius: 6,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Colors.red,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$activeCount plans active tonight',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context, Map<String, dynamic> post) {
    final matchPct = post['matchScore'] as int? ?? 80;
    final matchColor = matchPct >= 85
        ? LunaraTheme.primaryDeep
        : matchPct >= 70
        ? Colors.amber[800]!
        : LunaraTheme.accentVivid;

    final host = post['host'] ?? {};
    final venue = post['venue'] ?? {};
    final isMyPost = host['id']?.toString() == ApiService.currentUserId;
    final formattedDate = _formatPlanDate(post['planDate']);
    final timeAgo = _formatTimeAgo(post['postedAt']);
    final planTime = post['startTime'] ?? '21:00';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LunaraTheme.cardGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: LunaraTheme.premiumShadow,
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LunaraProfileImage(
                  userData: host,
                  radius: 22,
                  isInteractive: false,
                  showGradientBorder: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            host['name'] as String? ?? 'Unknown',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (host['age'] != null) ...[
                            Text(
                              ', ${host['age']}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.work_outline,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                            size: 11,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            host['occupation'] as String? ?? 'Guest',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: matchColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: matchColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$matchPct%',
                        style: TextStyle(color: matchColor, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'MATCH',
                        style: TextStyle(color: matchColor.withValues(alpha: 0.7), fontSize: 7, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: LunaraTheme.accentVivid, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${venue['name'] ?? 'Venue'} • $formattedDate at $planTime',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8), fontSize: 12),
                    ),
                  ),
                  Text(
                    timeAgo,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3), fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _planActionButton(
                    icon: Icons.person_search,
                    label: 'SEE DETAILS',
                    color: LunaraTheme.accentVivid,
                    outline: true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PosterProfileScreen(
                            poster: {
                              'name': host['name'] ?? 'Unknown',
                              'age': host['age'] ?? 25,
                              'avatar': LunaraTheme.defaultAvatar,
                              'profession': host['occupation'] ?? 'Guest',
                              'education': '',
                              'bio': host['bio'] ?? '',
                              'matchPct': matchPct,
                            },
                            feedItem: {
                              'venueName': venue['name'] ?? 'Venue',
                              'planTime': planTime,
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (!isMyPost) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _planActionButton(
                      icon: Icons.bolt,
                      label: 'JOIN',
                      color: LunaraTheme.primaryDeep,
                      outline: false,
                      onTap: () => _handleJoin(context, post),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartyPlanCard(BuildContext context, Map<String, dynamic> plan) {
    final host = plan['host'] ?? {};
    final venue = plan['venue'] ?? {};
    final isMyPost = host['id']?.toString() == ApiService.currentUserId;
    final matchPct = plan['matchScore'] as int? ?? 80;
    
    final matchColor = matchPct >= 85
        ? LunaraTheme.primaryDeep
        : matchPct >= 70
        ? Colors.amber[800]!
        : LunaraTheme.accentVivid;

    final formattedDate = _formatPlanDate(plan['planDate']);
    final timeAgo = _formatTimeAgo(plan['postedAt']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1F003A),
              Color(0xFF0D001C),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.15),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LunaraTheme.purpleGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.celebration, color: Colors.white, size: 10),
                      SizedBox(width: 4),
                      Text(
                        'PARTY PLAN',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  timeAgo,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                LunaraProfileImage(
                  userData: host,
                  radius: 22,
                  isInteractive: false,
                  showGradientBorder: true,
                  borderWidth: 1.5,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            host['name'] as String? ?? 'Unknown',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (host['age'] != null) ...[
                            Text(
                              ', ${host['age']}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.work_outline,
                            color: Colors.white.withValues(alpha: 0.4),
                            size: 11,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            host['occupation'] as String? ?? 'Guest',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: matchColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: matchColor.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$matchPct%',
                        style: TextStyle(color: matchColor, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'MATCH',
                        style: TextStyle(color: matchColor.withValues(alpha: 0.7), fontSize: 7, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (plan['description'] != null && plan['description'].toString().trim().isNotEmpty) ...[
              Text(
                plan['description'] as String,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: LunaraTheme.cyberCyan, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${venue['name'] ?? 'Venue'} • $formattedDate at ${plan['startTime'] ?? '21:00'}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _planActionButton(
                    icon: Icons.info_outline_rounded,
                    label: 'DETAILS',
                    color: LunaraTheme.cyberCyan,
                    outline: true,
                    onTap: () {
                      final hostName = host['name'] as String? ?? 'Host';
                      final first = hostName.split(' ').first;
                      final last = hostName.split(' ').skip(1).join(' ');
                      
                      final postMap = {
                        'id': plan['planId']?.toString() ?? '',
                        'userId': host['id']?.toString() ?? '',
                        'firstName': first,
                        'lastName': last.isNotEmpty ? last : 'User',
                        'venue': venue['name'] ?? 'Unknown Venue',
                        'content': plan['description'] ?? '',
                        'time': plan['planDate'] ?? '',
                        'profilePhotoUrl': null,
                        'user': host,
                      };

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PostDetailScreen(
                            post: postMap,
                            venue: venue,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (!isMyPost) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _planActionButton(
                      icon: Icons.bolt,
                      label: 'JOIN',
                      color: LunaraTheme.primaryDeep,
                      outline: false,
                      onTap: () => _handleJoinPartyPlan(context, plan),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleJoin(BuildContext context, Map<String, dynamic> post) async {
    final success = await ApiService.requestToJoinPartyPlan(post['id']?.toString() ?? post['planId']?.toString() ?? '');
    if (success) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            behavior: SnackBarBehavior.floating,
            content: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      'YOUR REQUEST TO JOIN THE VIBE HAS BEEN SENT!',
                      style: TextStyle(
                        fontFamily: 'AllroundGothic',
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send request. You may have already requested.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleJoinPartyPlan(BuildContext context, Map<String, dynamic> plan) async {
    final planId = plan['planId']?.toString() ?? plan['id']?.toString() ?? '';
    final success = await ApiService.requestToJoinPartyPlan(planId);
    if (success) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            behavior: SnackBarBehavior.floating,
            content: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      'YOUR REQUEST TO JOIN THE VIBE HAS BEEN SENT!',
                      style: TextStyle(
                        fontFamily: 'AllroundGothic',
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
        _loadFeed();
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send request. You may have already requested.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _planActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool outline,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: outline ? color.withValues(alpha: 0.1) : null,
          gradient: outline ? null : LunaraTheme.purpleGradient,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: outline ? color.withValues(alpha: 0.5) : Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: outline ? color : Colors.white, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: outline ? color : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyRequestCard(BuildContext context, Map<String, dynamic> req) {
    final plan = req['plan'] ?? {};
    final venue = plan['venue'] ?? {};
    final timeAgo = _formatTimeAgo(req['createdAt']);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LunaraTheme.accentVivid.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: LunaraTheme.accentVivid.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: LunaraTheme.accentVivid.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: LunaraTheme.accentVivid, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    req['requestType'] == 'large_party_request'
                      ? 'You requested a large party booking'
                      : 'You requested to join a ${req['requestType'] == 'table_plan' ? 'Table Plan' : 'Party Plan'}',
                    style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'at ${venue['name'] ?? 'Venue'}',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (req['status'] == 'accepted' || req['status'] == 'approved') ? Colors.green.withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          req['status']?.toString().toUpperCase() ?? 'PENDING',
                          style: TextStyle(
                            color: (req['status'] == 'accepted' || req['status'] == 'approved') ? Colors.green : Colors.amber,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(timeAgo, style: const TextStyle(color: Colors.black38, fontSize: 10)),
                    ],
                  ),
                  if (req['requestType'] == 'large_party_request' && req['status'] == 'approved' && req['booking'] != null) ...[
                    const SizedBox(height: 12),
                    if (req['booking']['paymentStatus'] == 'paid')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.check_circle, color: Colors.green, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Booking Confirmed!',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: LunaraActionButton(
                          text: 'PAY ₹${req['booking']['totalAmount']} NOW',
                          onPressed: () async {
                             await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PaymentConfirmationScreen(
                                  venue: venue,
                                  date: req['booking']['bookingDate']?.toString() ?? '',
                                  time: req['booking']['startTime']?.toString() ?? '',
                                  package: 'Large Party Booking',
                                  guests: req['booking']['numberOfGuests']?.toString(),
                                  totalPrice: req['booking']['totalAmount']?.toString() ?? '0',
                                  showSplitBill: false,
                                ),
                              ),
                            );
                            // Refresh feed after payment screen returns
                            _loadFeed(showLoader: false);
                          },
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingRequestCard(BuildContext context, Map<String, dynamic> req) {
    final requester = req['requester'] ?? {};
    final timeAgo = _formatTimeAgo(req['createdAt']);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LunaraTheme.primaryDeep.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: LunaraTheme.primaryDeep.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: LunaraTheme.primaryRich,
                  backgroundImage: (requester['profileImageUrl'] != null)
                      ? NetworkImage('${ApiService.baseUrl}${requester['profileImageUrl']}')
                      : null,
                  child: (requester['profileImageUrl'] == null)
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${requester['firstName'] ?? 'User'} ${requester['lastName'] ?? ''} wants to join',
                        style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your ${req['requestType'] == 'table_plan' ? 'Table Plan' : 'Party Plan'}',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(timeAgo, style: TextStyle(color: Colors.black38, fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (req['status'] == 'pending') ...[
                  Expanded(
                    child: _planActionButton(
                      icon: Icons.check,
                      label: 'ACCEPT',
                      color: Colors.green,
                      outline: false,
                      onTap: () async {
                        if (req['requestType'] == 'party_plan') {
                          final success = await ApiService.acceptPartyPlanRequest(req['id']);
                          if (success != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Accepted!')));
                            _loadFeed();
                          }
                        } else {
                          // For table plan, we can just show a toast for now if not implemented
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Table plan request accepted!')));
                        }
                      },
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: Center(
                      child: Text(
                        'Status: ${req['status']?.toString().toUpperCase()}',
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

