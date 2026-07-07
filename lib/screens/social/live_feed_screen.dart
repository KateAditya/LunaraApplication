import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../widgets/lunara_profile_image.dart';
import '../discovery/payment_confirmation_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    _pollingTimer?.cancel();
    _pulseController.dispose();
    _tabController.dispose();
    super.dispose();
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
                    isLabelVisible: _feedItems.any(
                      (i) =>
                          i['type'] == 'incoming_request' &&
                          (i['requestType'] == 'table_plan' ||
                              i['requestType'] == 'stranger_meet') &&
                          i['status'] == 'pending',
                    ),
                    smallSize: 8,
                    child: const Text('Stranger Meet'),
                  ),
                ),
                Tab(
                  child: Badge(
                    isLabelVisible: _feedItems.any(
                      (i) =>
                          i['type'] == 'incoming_request' &&
                          i['requestType'] == 'party_plan' &&
                          i['status'] == 'pending',
                    ),
                    smallSize: 8,
                    child: const Text('Party Plan'),
                  ),
                ),
                Tab(
                  child: Badge(
                    isLabelVisible: _notifications.any(
                      (n) => n['isRead'] != true,
                    ),
                    smallSize: 8,
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
    final partyItems = _feedItems.where((item) {
      final type = item['type'];
      final reqType = item['requestType'];
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
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notif = _notifications[index];
                return _buildNotificationCard(notif);
              },
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
          color: Theme.of(context).cardTheme.color ?? Colors.white,
          borderRadius: BorderRadius.circular(18),
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
                        ),
                      ),
                      Text(
                        '${host['occupation'] ?? 'Guest'}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  timeAgo,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${venue['name'] ?? 'Venue'} • $formattedDate at $planTime',
              style: const TextStyle(fontSize: 12),
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
                    onTap: () {}, // Navigate to details
                  ),
                ),
                if (!isMyPost) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _actionButton(
                      icon: Icons.bolt,
                      label: 'JOIN',
                      color: LunaraTheme.primaryDeep,
                      outline: false,
                      onTap: () async {
                        final success = await ApiService.requestToJoinPartyPlan(
                          post['id']?.toString() ??
                              post['planId']?.toString() ??
                              '',
                        );
                        if (success) _loadFeed(showLoader: false);
                      },
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
                    onTap: () {},
                  ),
                ),
                if (!isMyPost) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _actionButton(
                      icon: Icons.bolt,
                      label: 'JOIN',
                      color: LunaraTheme.primaryDeep,
                      outline: false,
                      onTap: () async {
                        final planId =
                            plan['planId']?.toString() ??
                            plan['id']?.toString() ??
                            '';
                        final success = await ApiService.requestToJoinPartyPlan(
                          planId,
                        );
                        if (success) _loadFeed(showLoader: false);
                      },
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
                        ),
                      ),
                      Text(
                        'Your ${req['requestType'] == 'table_plan' ? 'Table Plan' : 'Party Plan'}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        timeAgo,
                        style: const TextStyle(
                          color: Colors.black38,
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
            ] else if (currentStatus == 'accepted') ...[
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
    final plan = req['plan'] ?? {};
    final venue = plan['venue'] ?? {};
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
                        ),
                      ),
                      Text(
                        '${plan['type'] == 'table_plan' ? 'Table Plan' : 'Party Plan'} at ${venue['name'] ?? 'Venue'}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        timeAgo,
                        style: const TextStyle(
                          color: Colors.black38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (currentStatus == 'accepted') ...[
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
                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            icon: Icons.payment,
                            label: 'PROCEED TO PAY',
                            color: Colors.green,
                            outline: false,
                            onTap: () async {
                              // Initiate payment
                              final data =
                                  await ApiService.initiateJoinerPayment(reqId);
                              if (data != null && mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PaymentConfirmationScreen(
                                      venue: venue,
                                      date: plan['planDate'] ?? '',
                                      time: plan['startTime'] ?? '',
                                      package: 'Join Party',
                                      totalPrice:
                                          data['amount']?.toString() ?? '99',
                                      showSplitBill: false,
                                    ),
                                  ),
                                );
                              }
                            },
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
                    ),
                  ],
                ),
              ),
            ] else if (currentStatus == 'paid') ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
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

  Widget _buildNotificationCard(Map<String, dynamic> notif) {
    final title = notif['title'] ?? 'Notification';
    final body = notif['body'] ?? '';
    final timeAgo = _formatTimeAgo(notif['createdAt']);

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
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(color: Colors.black87, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              timeAgo,
              style: const TextStyle(color: Colors.black54, fontSize: 10),
            ),
          ],
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
