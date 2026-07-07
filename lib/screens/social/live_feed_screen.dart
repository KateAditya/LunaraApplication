import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../widgets/lunara_profile_image.dart';
import 'party_plan_detail_screen.dart';
import '../discovery/payment_confirmation_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'party_plan_ticket_screen.dart';

class LiveFeedScreen extends StatefulWidget {
  final bool isTab;
  const LiveFeedScreen({super.key, this.isTab = false});

  @override
  State<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends State<LiveFeedScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  List<Map<String, dynamic>> _feedItems = [];
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  Timer? _pollingTimer;

  // Track optimistic state changes for buttons
  final Map<String, String> _optimisticStates = {};
  final Set<String> _readRequestIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadFeed();

    // Fast polling every 15 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadFeed(showLoader: false);
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _pollingTimer?.cancel();
    _pulseController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    _markCurrentTabItemsAsRead();
  }

  void _markCurrentTabItemsAsRead() {
    final index = _tabController.index;
    if (index == 0) {
      // Mark all Stranger Meet incoming requests as read
      final List<String> toMark = [];
      setState(() {
        for (var item in _feedItems) {
          if (item['type'] == 'incoming_request' &&
              (item['requestType'] == 'table_plan' ||
                  item['requestType'] == 'stranger_meet')) {
            final reqId = item['id']?.toString() ?? '';
            if (reqId.isNotEmpty && !_readRequestIds.contains(reqId)) {
              _readRequestIds.add(reqId);
              toMark.add(reqId);
            }
          }
        }
      });
      for (final rId in toMark) {
        ApiService.markRequestRead(rId);
      }
    } else if (index == 1) {
      // Mark all Party Plan incoming requests as read
      final List<String> toMark = [];
      setState(() {
        for (var item in _feedItems) {
          if (item['type'] == 'incoming_request' &&
              item['requestType'] == 'party_plan') {
            final reqId = item['id']?.toString() ?? '';
            if (reqId.isNotEmpty && !_readRequestIds.contains(reqId)) {
              _readRequestIds.add(reqId);
              toMark.add(reqId);
            }
          }
        }
      });
      for (final rId in toMark) {
        ApiService.markRequestRead(rId);
      }
    } else if (index == 2) {
      // Mark all other notifications as read
      _markAllNotificationsAsRead();
    }
  }

  Future<void> _markAllNotificationsAsRead() async {
    List<String> unreadIds = [];
    for (var n in _notifications) {
      final nId = n['id']?.toString() ?? '';
      final isRead = n['isRead'] == true || n['read'] == true;
      if (!isRead && nId.isNotEmpty) {
        unreadIds.add(nId);
      }
    }
    if (unreadIds.isEmpty) return;

    // Optimistically mark all notifications as read
    setState(() {
      for (var n in _notifications) {
        final nId = n['id']?.toString() ?? '';
        if (unreadIds.contains(nId)) {
          n['read'] = true;
          n['isRead'] = true;
        }
      }
    });

    for (var nId in unreadIds) {
      await ApiService.markNotificationRead(nId);
    }
  }

  Future<void> _markNotificationAsRead(Map<String, dynamic> notif) async {
    final isRead = notif['isRead'] == true || notif['read'] == true;
    if (isRead) return;

    final nId = notif['id']?.toString() ?? '';
    if (nId.isEmpty) return;

    setState(() {
      notif['read'] = true;
      notif['isRead'] = true;
    });

    await ApiService.markNotificationRead(nId);
  }

  Future<void> _clearAllNotifications() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LunaraTheme.darkSurface,
        title: const Text('Clear All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to clear all notifications?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CLEAR', style: TextStyle(color: LunaraTheme.accentVivid, fontWeight: FontWeight.bold)),
          ),
        ],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
    );

    if (confirm == true) {
      setState(() {
        _notifications.clear();
      });
      final success = await ApiService.clearAllNotifications();
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to clear notifications on server.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      _loadFeed(showLoader: false);
    }
  }

  Future<void> _loadFeed({bool showLoader = true}) async {
    if (showLoader) setState(() => _isLoading = true);
    try {
      final data = await ApiService.fetchLiveFeedData();
      final notifs = await ApiService.fetchNotifications();

      List<Map<String, dynamic>> combined = [
        ...List<Map<String, dynamic>>.from(data['feed'] ?? []),
        ...List<Map<String, dynamic>>.from(data['myRequests'] ?? []),
        ...List<Map<String, dynamic>>.from(data['incomingRequests'] ?? []),
      ];

      combined.sort((a, b) {
        final dateA =
            DateTime.tryParse(
              a['postedAt']?.toString() ?? a['createdAt']?.toString() ?? '',
            ) ??
            DateTime.now();
        final dateB =
            DateTime.tryParse(
              b['postedAt']?.toString() ?? b['createdAt']?.toString() ?? '',
            ) ??
            DateTime.now();
        return dateB.compareTo(dateA);
      });

      if (mounted) {
        setState(() {
          _feedItems = combined;
          _notifications = notifs;
          _isLoading = false;
        });
        _markCurrentTabItemsAsRead();
      }
    } catch (e) {
      debugPrint('Error loading live feed: $e');
      if (mounted) setState(() => _isLoading = false);
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

  String _formatPlanDate(dynamic planDate) {
    if (planDate == null) return 'Tonight';
    try {
      final parsedDate = DateTime.parse(planDate.toString()).toLocal();
      final now = DateTime.now();
      if (parsedDate.year == now.year &&
          parsedDate.month == now.month &&
          parsedDate.day == now.day) {
        return 'Tonight';
      }
      final tomorrow = now.add(const Duration(days: 1));
      if (parsedDate.year == tomorrow.year &&
          parsedDate.month == tomorrow.month &&
          parsedDate.day == tomorrow.day) {
        return 'Tomorrow';
      }
      return DateFormat('E, dd MMM').format(parsedDate);
    } catch (_) {
      return planDate.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strangerMeetUnreadCount = _feedItems.where((i) =>
        i['type'] == 'incoming_request' &&
        (i['requestType'] == 'table_plan' || i['requestType'] == 'stranger_meet') &&
        i['status'] == 'pending' &&
        !_readRequestIds.contains(i['id']?.toString() ?? '')).length;

    final partyPlanUnreadCount = _feedItems.where((i) =>
        i['type'] == 'incoming_request' &&
        i['requestType'] == 'party_plan' &&
        i['status'] == 'pending' &&
        !_readRequestIds.contains(i['id']?.toString() ?? '')).length;

    final otherUnreadCount = _notifications.where((n) =>
        n['isRead'] != true && n['read'] != true).length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            TabBar(
              controller: _tabController,
              labelColor: LunaraTheme.accentVivid,
              unselectedLabelColor: Colors.grey,
              indicatorColor: LunaraTheme.accentVivid,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              tabs: [
                Tab(
                  child: Badge(
                    label: Text(
                      '$strangerMeetUnreadCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    isLabelVisible: strangerMeetUnreadCount > 0,
                    backgroundColor: LunaraTheme.accentVivid,
                    child: const Text('Stranger Meet'),
                  ),
                ),
                Tab(
                  child: Badge(
                    label: Text(
                      '$partyPlanUnreadCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    isLabelVisible: partyPlanUnreadCount > 0,
                    backgroundColor: LunaraTheme.accentVivid,
                    child: const Text('Party Plan'),
                  ),
                ),
                Tab(
                  child: Badge(
                    label: Text(
                      '$otherUnreadCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    isLabelVisible: otherUnreadCount > 0,
                    backgroundColor: LunaraTheme.accentVivid,
                    child: const Text('Other'),
                  ),
                ),
              ],
            ),
            Expanded(
              child: _isLoading && _feedItems.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildStrangerMeetFeed(),
                        _buildPartyPlanFeed(),
                        _buildNotificationsFeed(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (!widget.isTab)
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () => Navigator.pop(context),
            )
          else
            const SizedBox(
              width: 48,
            ), // Maintain spacing for the Row's MainAxisAlignment.spaceBetween
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(
                        alpha: _pulseAnimation.value,
                      ),
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
          IconButton(
            icon: const Icon(Icons.refresh, color: LunaraTheme.accentVivid),
            onPressed: () => _loadFeed(showLoader: true),
            tooltip: 'Refresh Feed',
          ),
        ],
      ),
    );
  }

  Widget _buildStrangerMeetFeed() {
    final strangerItems = _feedItems.where((item) {
      final type = item['type'];
      final reqType = item['requestType'];
      return type == 'table_plan' ||
          ((type == 'incoming_request' || type == 'my_request') &&
              (reqType == 'table_plan' || reqType == 'stranger_meet'));
    }).toList();

    return RefreshIndicator(
      onRefresh: () => _loadFeed(showLoader: false),
      child: strangerItems.isEmpty
          ? _buildEmptyState('No Stranger Meets active right now.')
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: strangerItems.length,
              itemBuilder: (context, index) {
                final item = strangerItems[index];
                if (item['type'] == 'incoming_request') {
                  return _buildIncomingRequestCard(item);
                }
                if (item['type'] == 'my_request') {
                  return _buildMyRequestCard(item);
                }
                return _buildPlanCard(item); // default fallback
              },
            ),
    );
  }

  Widget _buildPartyPlanFeed() {
    // Collect plan IDs that are already fully confirmed (both paid) so we
    // can suppress the duplicate public-feed card for the same plan.
    final confirmedPlanIds = <String>{};
    for (final item in _feedItems) {
      if ((item['type'] == 'my_request' || item['type'] == 'incoming_request') &&
          item['requestType'] == 'party_plan') {
        final status = item['status']?.toString().toLowerCase() ?? '';
        if (status == 'accepted' || status == 'paid') {
          final planId = (item['plan']?['id'] ?? item['plan']?['planId'] ?? '').toString();
          if (planId.isNotEmpty) confirmedPlanIds.add(planId);
        }
      }
    }

    final partyItems = _feedItems.where((item) {
      final type = item['type'];
      final reqType = item['requestType'];
      // Suppress the public plan card when it is already confirmed
      if (type == 'party_plan') {
        final planId = (item['planId'] ?? item['id'] ?? '').toString();
        if (confirmedPlanIds.contains(planId)) return false;
      }
      return type == 'party_plan' ||
          ((type == 'incoming_request' || type == 'my_request') &&
              reqType == 'party_plan');
    }).toList();

    return RefreshIndicator(
      onRefresh: () => _loadFeed(showLoader: false),
      child: partyItems.isEmpty
          ? _buildEmptyState('No Party Plans active right now.')
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: partyItems.length,
              itemBuilder: (context, index) {
                final item = partyItems[index];
                if (item['type'] == 'party_plan') {
                  return _buildPartyPlanCard(item);
                }
                if (item['type'] == 'incoming_request') {
                  return _buildIncomingRequestCard(item);
                }
                if (item['type'] == 'my_request') {
                  return _buildMyRequestCard(item);
                }
                return const SizedBox.shrink();
              },
            ),
    );
  }

  Widget _buildNotificationsFeed() {
    return RefreshIndicator(
      onRefresh: () => _loadFeed(showLoader: false),
      child: _notifications.isEmpty
          ? _buildEmptyState('No recent activity.')
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 12.0, bottom: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: _clearAllNotifications,
                        icon: const Icon(Icons.clear_all, color: LunaraTheme.accentVivid, size: 20),
                        label: const Text(
                          'CLEAR ALL',
                          style: TextStyle(
                            color: LunaraTheme.accentVivid,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.1,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          backgroundColor: LunaraTheme.accentVivid.withValues(alpha: 0.1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notif = _notifications[index];
                      return _buildNotificationCard(notif);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(String text) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Center(
          child: Text(text, style: const TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> post) {
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
          color: LunaraTheme.darkSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
          ),
          boxShadow: LunaraTheme.premiumShadow,
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
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${host['name'] ?? 'Unknown'}, ${host['age'] ?? '25'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${host['occupation'] ?? 'Guest'}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  timeAgo,
                  style: const TextStyle(fontSize: 10, color: Colors.white38),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${venue['name'] ?? 'Venue'} • $formattedDate at $planTime',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    icon: Icons.info_outline,
                    label: 'DETAILS',
                    color: LunaraTheme.accentVivid,
                    outline: true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PartyPlanDetailScreen(plan: post),
                        ),
                      );
                    },
                  ),
                ),
                if (!isMyPost) ...[
                  const SizedBox(width: 10),
                  Builder(
                    builder: (context) {
                      final planId = post['planId']?.toString() ?? post['id']?.toString() ?? '';
                      // Find if I have requested this plan
                      final myReq = _feedItems.firstWhere(
                        (item) =>
                            item['type'] == 'my_request' &&
                            item['requestType'] == 'table_plan' &&
                            item['plan'] != null &&
                            (item['plan']['id']?.toString() == planId ||
                                item['plan']['planId']?.toString() == planId),
                        orElse: () => {},
                      );

                      if (myReq.isNotEmpty) {
                        final reqId = myReq['id']?.toString() ?? '';
                        final reqStatus = _optimisticStates[reqId] ??
                            myReq['status']?.toString().toLowerCase() ??
                            'pending';

                        if (reqStatus == 'pending') {
                          return Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey.withValues(alpha: 0.5),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.hourglass_empty_rounded,
                                    color: Colors.grey,
                                    size: 15,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'PENDING',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        } else if (reqStatus == 'accepted' ||
                            reqStatus == 'payment_pending') {
                          return Expanded(
                            child: CountdownPayButton(
                              myReq: myReq,
                              venue: venue,
                              plan: post,
                              onPaymentSuccess: () =>
                                  _loadFeed(showLoader: false),
                            ),
                          );
                        } else if (reqStatus == 'paid') {
                          return Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.blue.withValues(alpha: 0.5),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    color: Colors.blue,
                                    size: 15,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'JOINED',
                                    style: TextStyle(
                                      color: Colors.blue,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        } else if (reqStatus == 'rejected') {
                          return Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.5),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.cancel_outlined,
                                    color: Colors.red,
                                    size: 15,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'REJECTED',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                      }

                      return Expanded(
                        child: _actionButton(
                          icon: Icons.bolt,
                          label: 'JOIN',
                          color: LunaraTheme.primaryDeep,
                          outline: false,
                          onTap: () async {
                            final planId = post['planId']?.toString() ??
                                post['id']?.toString() ??
                                '';
                            if (planId.isEmpty) return;
                            final success =
                                await ApiService.requestToJoinPartyPlan(planId);
                            if (!mounted) return;
                            if (success) {
                              _loadFeed(showLoader: false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Join request sent! Host will review it.',
                                  ),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Request failed. You may have already requested to join.',
                                  ),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartyPlanCard(Map<String, dynamic> plan) {
    final host = plan['host'] ?? {};
    final venue = plan['venue'] ?? {};
    final isMyPost = host['id']?.toString() == ApiService.currentUserId;
    final formattedDate = _formatPlanDate(plan['planDate']);
    final timeAgo = _formatTimeAgo(plan['postedAt']);
    final planTime = plan['startTime'] ?? '21:00';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1F003A), Color(0xFF0D001C)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: LunaraTheme.primaryDeep,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'PARTY PLAN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  timeAgo,
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
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
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${host['name'] ?? 'Unknown'}, ${host['age'] ?? '25'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${host['occupation'] ?? 'Guest'}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (plan['description'] != null &&
                plan['description'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  plan['description'],
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            Text(
              '${venue['name'] ?? 'Venue'} • $formattedDate at $planTime',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    icon: Icons.info_outline,
                    label: 'DETAILS',
                    color: LunaraTheme.cyberCyan,
                    outline: true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PartyPlanDetailScreen(plan: plan),
                        ),
                      ).then((_) => _loadFeed(showLoader: false));
                    },
                  ),
                ),
                if (!isMyPost) ...[
                  const SizedBox(width: 10),
                  Builder(
                    builder: (context) {
                      final planId = plan['planId']?.toString() ?? plan['id']?.toString() ?? '';
                      // Find if I have requested this plan
                      final myReq = _feedItems.firstWhere(
                        (item) =>
                            item['type'] == 'my_request' &&
                            item['requestType'] == 'party_plan' &&
                            item['plan'] != null &&
                            (item['plan']['id']?.toString() == planId ||
                                item['plan']['planId']?.toString() == planId),
                        orElse: () => {},
                      );

                      if (myReq.isNotEmpty) {
                        final reqId = myReq['id']?.toString() ?? '';
                        final reqStatus = _optimisticStates[reqId] ??
                            myReq['status']?.toString().toLowerCase() ??
                            'pending';

                        if (reqStatus == 'pending') {
                          return Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey.withValues(alpha: 0.5),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.hourglass_empty_rounded,
                                    color: Colors.grey,
                                    size: 15,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'PENDING',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        } else if (reqStatus == 'accepted' ||
                            reqStatus == 'payment_pending') {
                          final hostPaid = myReq['plan']?['hostPaymentStatus'] == 'paid' ||
                              myReq['plan']?['hostPaymentStatus'] == 'refunded';
                          if (!hostPaid) {
                            return Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.hourglass_empty_rounded, color: Colors.orange, size: 15),
                                    SizedBox(width: 6),
                                    Text(
                                      'AWAITING HOST PAYMENT',
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return Expanded(
                            child: CountdownPayButton(
                              myReq: myReq,
                              venue: venue,
                              plan: plan,
                              onPaymentSuccess: () =>
                                  _loadFeed(showLoader: false),
                            ),
                          );
                        } else if (reqStatus == 'paid' || reqStatus == 'accepted') {
                          return Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PartyPlanTicketScreen(
                                      request: myReq,
                                      plan: myReq['plan'] ?? plan,
                                      isHost: false,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.qr_code_rounded, size: 14, color: Colors.white),
                              label: const Text('VIEW TICKET', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: LunaraTheme.electricViolet,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          );
                        } else if (reqStatus == 'rejected') {
                          return Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.5),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.cancel_outlined,
                                    color: Colors.red,
                                    size: 15,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'REJECTED',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                      }

                      return Expanded(
                        child: _actionButton(
                          icon: Icons.bolt,
                          label: 'JOIN',
                          color: LunaraTheme.primaryDeep,
                          outline: false,
                          onTap: () async {
                            final planId = plan['planId']?.toString() ??
                                plan['id']?.toString() ??
                                '';
                            if (planId.isEmpty) return;
                            final success =
                                await ApiService.requestToJoinPartyPlan(planId);
                            if (!mounted) return;
                            if (success) {
                              _loadFeed(showLoader: false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Join request sent! Host will review it.',
                                  ),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Request failed. You may have already requested to join.',
                                  ),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Incoming Request = Host seeing someone asking to join
  Widget _buildIncomingRequestCard(Map<String, dynamic> req) {
    final requester = req['requester'] ?? {};
    final reqId = req['id']?.toString() ?? '';
    final timeAgo = _formatTimeAgo(req['createdAt']);
    final currentStatus =
        _optimisticStates[reqId] ??
        req['status']?.toString().toLowerCase() ??
        'pending';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LunaraTheme.primaryDeep.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: LunaraTheme.primaryDeep.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                LunaraProfileImage(
                  userData: requester,
                  radius: 20,
                  isInteractive: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${requester['firstName'] ?? 'User'} wants to join',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Your ${req['requestType'] == 'table_plan' ? 'Table Plan' : 'Party Plan'}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        timeAgo,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (currentStatus == 'pending') ...[
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      icon: Icons.check,
                      label: 'ACCEPT',
                      color: Colors.green,
                      outline: false,
                      onTap: () async {
                        setState(() => _optimisticStates[reqId] = 'accepted');
                        await ApiService.acceptPartyPlanRequest(reqId);
                        _loadFeed(showLoader: false);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _actionButton(
                      icon: Icons.close,
                      label: 'REJECT',
                      color: Colors.red,
                      outline: true,
                      onTap: () async {
                        setState(() => _optimisticStates[reqId] = 'rejected');
                        await ApiService.rejectPartyPlanRequest(reqId);
                        _loadFeed(showLoader: false);
                      },
                    ),
                  ),
                ],
              ),
            ] else if (currentStatus == 'accepted' || currentStatus == 'paid') ...[
              // Both payments confirmed — show VIEW TICKET for the host
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'BOOKING CONFIRMED 🎉',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final plan = req['plan'] ?? {};
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PartyPlanTicketScreen(
                                request: req,
                                plan: plan,
                                isHost: true,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.qr_code_rounded, size: 16, color: Colors.white),
                        label: const Text(
                          'VIEW TICKET',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: LunaraTheme.electricViolet,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (currentStatus == 'payment_pending') ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'WAITING FOR PAYMENT',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: Text(
                    currentStatus.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // My Request = Current user requested to join someone else's plan
  Widget _buildMyRequestCard(Map<String, dynamic> req) {
    final requestType = req['requestType']?.toString() ?? 'table_plan';
    final isLargeParty = requestType == 'large_party_request';

    final booking = isLargeParty ? (req['booking'] ?? {}) : {};
    final plan = isLargeParty ? {} : (req['plan'] ?? {});
    final venue = isLargeParty ? (booking['venue'] ?? {}) : (plan['venue'] ?? {});

    final timeAgo = _formatTimeAgo(req['createdAt']);
    final reqId = req['id']?.toString() ?? '';
    final currentStatus =
        _optimisticStates[reqId] ??
        req['status']?.toString().toLowerCase() ??
        'pending';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LunaraTheme.accentVivid.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: LunaraTheme.accentVivid.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: LunaraTheme.accentVivid.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.send,
                    color: LunaraTheme.accentVivid,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'You requested to join',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        isLargeParty
                            ? 'Group Booking at ${venue['name'] ?? 'Venue'}'
                            : '${plan['type'] == 'table_plan' ? 'Table Plan' : 'Party Plan'} at ${venue['name'] ?? 'Venue'}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        timeAgo,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isLargeParty) ...[
              if (currentStatus == 'pending') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.yellow.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.yellow.withValues(alpha: 0.3)),
                  ),
                  child: const Center(
                    child: Text(
                      'PENDING ADMIN APPROVAL',
                      style: TextStyle(
                        color: Colors.yellow,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ] else if (currentStatus == 'approved') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: const Center(
                    child: Text(
                      'APPROVED! AWAITING PAYMENT LINK FROM ADMIN',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ] else if (currentStatus == 'payment_sent') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'PAYMENT REQUIRED: ₹${booking['adminPaymentAmount'] ?? booking['totalAmount'] ?? '0'}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _actionButton(
                              icon: Icons.payment,
                              label: 'PAY NOW',
                              color: Colors.green,
                              outline: false,
                              onTap: () async {
                                final urlStr = booking['adminPaymentLink'] ?? '';
                                if (urlStr.isNotEmpty) {
                                  final url = Uri.parse(urlStr);
                                  if (await canLaunchUrl(url)) {
                                    await launchUrl(url, mode: LaunchMode.externalApplication);
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else if (currentStatus == 'payment_done') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.blue, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'PAYMENT CONFIRMED & BOOKED',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: Center(
                    child: Text(
                      currentStatus.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ] else ...[
              if (currentStatus == 'accepted' || currentStatus == 'payment_pending') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'YOUR REQUEST WAS ACCEPTED!',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Builder(
                        builder: (context) {
                          final hostPaid = req['plan']?['hostPaymentStatus'] == 'paid' ||
                              req['plan']?['hostPaymentStatus'] == 'refunded';
                          if (!hostPaid) {
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.hourglass_empty_rounded, color: Colors.orange, size: 15),
                                  SizedBox(width: 6),
                                  Text(
                                    'AWAITING HOST PAYMENT',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return Row(
                            children: [
                              Expanded(
                                child: CountdownPayButton(
                                  myReq: req,
                                  venue: venue,
                                  plan: plan,
                                  onPaymentSuccess: () =>
                                      _loadFeed(showLoader: false),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _actionButton(
                                  icon: Icons.cancel,
                                  label: 'CANCEL',
                                  color: Colors.red,
                                  outline: true,
                                  onTap: () async {
                                    setState(
                                      () => _optimisticStates[reqId] = 'cancelled',
                                    );
                                    await ApiService.rejectPartyPlanRequest(reqId);
                                    _loadFeed(showLoader: false);
                                  },
                                ),
                              ),
                            ],
                          );
                        }
                      ),
                    ],
                  ),
                ),
              ] else if (currentStatus == 'paid' || currentStatus == 'accepted') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, color: Colors.blue, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'PAYMENT CONFIRMED',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PartyPlanTicketScreen(
                                  request: req,
                                  plan: req['plan'] ?? plan,
                                  isHost: false,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.qr_code_rounded, size: 16, color: Colors.white),
                          label: const Text(
                            'VIEW TICKET',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: LunaraTheme.electricViolet,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  child: Center(
                    child: Text(
                      currentStatus.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notif) {
    final title = notif['title'] ?? 'Notification';
    final body = notif['body'] ?? '';
    final timeAgo = _formatTimeAgo(notif['createdAt']);
    final isRead = notif['isRead'] == true || notif['read'] == true;

    IconData icon = Icons.notifications;
    Color color = Colors.grey;
    if (title.toLowerCase().contains('like')) {
      icon = Icons.favorite;
      color = Colors.red;
    } else if (title.toLowerCase().contains('payment')) {
      icon = Icons.payment;
      color = Colors.green;
    } else if (title.toLowerCase().contains('visit') ||
        title.toLowerCase().contains('view')) {
      icon = Icons.visibility;
      color = Colors.blue;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _markNotificationAsRead(notif),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isRead ? 0.05 : 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isRead ? Colors.transparent : color.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: isRead ? color.withValues(alpha: 0.6) : color, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isRead ? Colors.white70 : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        color: isRead ? Colors.white54 : Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isRead)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: LunaraTheme.accentVivid,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Text(
                    timeAgo,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
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
          color: outline ? color.withValues(alpha: 0.1) : color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: outline ? color.withValues(alpha: 0.5) : Colors.transparent,
          ),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CountdownPayButton extends StatefulWidget {
  final Map<String, dynamic> myReq;
  final Map<String, dynamic> venue;
  final Map<String, dynamic> plan;
  final VoidCallback onPaymentSuccess;

  const CountdownPayButton({
    super.key,
    required this.myReq,
    required this.venue,
    required this.plan,
    required this.onPaymentSuccess,
  });

  @override
  State<CountdownPayButton> createState() => _CountdownPayButtonState();
}

class _CountdownPayButtonState extends State<CountdownPayButton> {
  Timer? _timer;
  int _secondsLeft = -1; // -1 means no timeout

  @override
  void initState() {
    super.initState();
    _calculateTimeLeft();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _calculateTimeLeft();
      }
    });
  }

  void _calculateTimeLeft() {
    final timeoutStr = widget.myReq['paymentTimeoutAt'];
    if (timeoutStr == null) {
      if (_secondsLeft != -1) {
        setState(() => _secondsLeft = -1);
      }
      return;
    }
    final parsed = DateTime.tryParse(timeoutStr.toString())?.toLocal();
    if (parsed == null) {
      if (_secondsLeft != -1) {
        setState(() => _secondsLeft = -1);
      }
      return;
    }
    final diff = parsed.difference(DateTime.now()).inSeconds;
    setState(() {
      _secondsLeft = diff > 0 ? diff : 0;
    });
    if (_secondsLeft == 0) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_secondsLeft == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: const Center(
          child: Text(
            'PAYMENT TIMED OUT',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      );
    }

    final planDate = widget.plan['planDateTime'] != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(widget.plan['planDateTime'].toString()))
        : 'Tonight';
    final planTime = widget.plan['planDateTime'] != null
        ? DateFormat('hh:mm a').format(DateTime.parse(widget.plan['planDateTime'].toString()))
        : '21:00';
    final reqId = widget.myReq['id']?.toString() ?? '';
    final label = _secondsLeft > 0
        ? 'PAY NOW (${_formatDuration(_secondsLeft)})'
        : 'PAY NOW';

    return GestureDetector(
      onTap: () async {
        final data = await ApiService.initiateJoinerPayment(reqId);
        if (data != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentConfirmationScreen(
                venue: widget.venue,
                date: planDate,
                time: planTime,
                package: 'Party Plan Safety Deposit',
                totalPrice: data['amount']?.toString() ?? '99',
                showSplitBill: false,
                razorpayOrderId: widget.myReq['joinerRazorpayOrderId'],
                onRazorpayPaymentSuccess: (paymentId, signature) async {
                  try {
                    final orderId = widget.myReq['joinerRazorpayOrderId'] ?? 'mock_order';
                    final success = await ApiService.verifyJoinerPayment(reqId, orderId, paymentId, signature);
                    if (!mounted) return;
                    if (success) {
                      widget.onPaymentSuccess();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PartyPlanTicketScreen(
                            request: widget.myReq,
                            plan: widget.plan.isNotEmpty ? widget.plan : (widget.myReq['plan'] ?? {}),
                            isHost: false,
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Payment Verification Failed.'), backgroundColor: Colors.red),
                      );
                    }
                  } catch (e) {
                    debugPrint('Payment verification error: $e');
                  }
                },
                onPaymentSuccess: () async {
                  try {
                    final orderId = widget.myReq['joinerRazorpayOrderId'] ?? 'mock_order';
                    final success = await ApiService.verifyJoinerPayment(reqId, orderId, 'mock_payment', 'mock_signature');
                    if (!mounted) return;
                    if (success) {
                      widget.onPaymentSuccess();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PartyPlanTicketScreen(
                            request: widget.myReq,
                            plan: widget.plan.isNotEmpty ? widget.plan : (widget.myReq['plan'] ?? {}),
                            isHost: false,
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Payment Verification Failed.'), backgroundColor: Colors.red),
                      );
                    }
                  } catch (e) {
                    debugPrint('Payment verification error: $e');
                  }
                },
              ),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Colors.green, Color(0xFF008037)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.payment_rounded, color: Colors.white, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

