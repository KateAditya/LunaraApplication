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
import '../../models/user.dart';
import '../profile/profile_screen.dart';
import '../../models/strangers_meet_request.dart';
import 'strangers_meet_payment_screen.dart';
import 'strangers_meet_ticket_screen.dart';
import 'chat_screen.dart';

class LiveFeedScreen extends StatefulWidget {
  final bool isTab;
  final VoidCallback? onCountChanged;
  final int initialTabIndex;
  const LiveFeedScreen({super.key, this.isTab = false, this.onCountChanged, this.initialTabIndex = 0});

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
  final Set<String> _clearedFeedItemIds = {};

  List<Map<String, dynamic>> _getJoinRequestsForMeet(String meetId) {
    return _feedItems.where((i) =>
      i['type'] == 'incoming_request' &&
      i['requestType'] == 'stranger_meet' &&
      i['planId']?.toString() == meetId
    ).toList();
  }

  Set<String> get _readRequestIds => ApiService.localReadRequestIds;
  Set<String> get _localReadNotificationIds => ApiService.localReadNotificationIds;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTabIndex);
    _tabController.addListener(_handleTabChange);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadFeed();
    _initSocketListeners();

    // Fast polling every 15 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadFeed(showLoader: false);
    });
  }

  @override
  void dispose() {
    _disposeSocketListeners();
    _tabController.removeListener(_handleTabChange);
    _pollingTimer?.cancel();
    _pulseController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _initSocketListeners() {
    ApiService.addSocketListener('party_plan_created', _onPartyPlanCreated);
    ApiService.addSocketListener('party_plan_deleted', _onPartyPlanDeleted);
    ApiService.addSocketListener('party_plan_request_accepted', _onPartyPlanRequestAccepted);
    ApiService.addSocketListener('party_plan_match_success', _onPartyPlanMatchSuccess);
    ApiService.addSocketListener('party_plan_host_paid', _onPartyPlanHostPaid);
    ApiService.addSocketListener('party_plan_joiner_paid', _onPartyPlanJoinerPaid);
    ApiService.addSocketListener('plan_unavailable', _onPlanUnavailable);
  }

  void _disposeSocketListeners() {
    ApiService.removeSocketListener('party_plan_created', _onPartyPlanCreated);
    ApiService.removeSocketListener('party_plan_deleted', _onPartyPlanDeleted);
    ApiService.removeSocketListener('party_plan_request_accepted', _onPartyPlanRequestAccepted);
    ApiService.removeSocketListener('party_plan_match_success', _onPartyPlanMatchSuccess);
    ApiService.removeSocketListener('party_plan_host_paid', _onPartyPlanHostPaid);
    ApiService.removeSocketListener('party_plan_joiner_paid', _onPartyPlanJoinerPaid);
    ApiService.removeSocketListener('plan_unavailable', _onPlanUnavailable);
  }

  void _onPartyPlanCreated(dynamic data) {
    if (!mounted) return;
    try {
      final map = Map<String, dynamic>.from(data);
      setState(() {
        final exists = _feedItems.any((item) => item['id']?.toString() == map['id']?.toString());
        if (!exists) {
          _feedItems.insert(0, map);
        }
      });
    } catch (e) {
      debugPrint('Error handling party_plan_created: $e');
    }
  }

  void _onPartyPlanDeleted(dynamic data) {
    if (!mounted) return;
    try {
      final planId = data['planId']?.toString();
      if (planId != null) {
        setState(() {
          _feedItems.removeWhere((item) => 
            (item['planId']?.toString() == planId) || 
            (item['id']?.toString() == planId && item['type'] == 'party_plan') ||
            (item['plan'] != null && item['plan']['id']?.toString() == planId)
          );
        });
      }
    } catch (e) {
      debugPrint('Error handling party_plan_deleted: $e');
    }
  }

  void _onPartyPlanRequestAccepted(dynamic data) {
    if (!mounted) return;
    try {
      final reqId = data['requestId']?.toString();
      if (reqId != null) {
        setState(() {
          for (var item in _feedItems) {
            if (item['id']?.toString() == reqId) {
              item['status'] = 'accepted';
              item['razorpayOrderId'] = data['razorpayOrderId'];
              item['charges'] = data['charges'];
              item['safetyDeposit'] = data['safetyDeposit'];
              item['totalAmount'] = data['totalAmount'];
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error handling party_plan_request_accepted: $e');
    }
  }

  void _onPartyPlanMatchSuccess(dynamic data) {
    if (!mounted) return;
    try {
      final reqId = data['requestId']?.toString();
      final planId = data['planId']?.toString();
      setState(() {
        for (var item in _feedItems) {
          if (item['id']?.toString() == reqId || (item['plan'] != null && item['plan']['id']?.toString() == planId)) {
            item['status'] = 'paid';
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Party Match Confirmed! Both host and guest have paid.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      debugPrint('Error handling party_plan_match_success: $e');
    }
  }

  void _onPartyPlanHostPaid(dynamic data) {
    if (!mounted) return;
    try {
      final reqId = data['requestId']?.toString();
      if (reqId != null) {
        setState(() {
          for (var item in _feedItems) {
            if (item['id']?.toString() == reqId) {
              item['status'] = 'host_paid';
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error handling party_plan_host_paid: $e');
    }
  }

  void _onPartyPlanJoinerPaid(dynamic data) {
    if (!mounted) return;
    try {
      final reqId = data['requestId']?.toString();
      if (reqId != null) {
        setState(() {
          for (var item in _feedItems) {
            if (item['id']?.toString() == reqId) {
              item['status'] = 'joiner_paid';
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error handling party_plan_joiner_paid: $e');
    }
  }

  void _onPlanUnavailable(dynamic data) {
    if (!mounted) return;
    try {
      final planId = data['planId']?.toString();
      final requestId = data['requestId']?.toString();
      setState(() {
        // Remove the specific stale request card from the feed
        if (requestId != null) {
          _feedItems.removeWhere((item) => item['id']?.toString() == requestId);
        }
        // Also remove any lingering plan card for that planId
        if (planId != null) {
          _feedItems.removeWhere((item) =>
              (item['id']?.toString() == planId && item['type'] == 'party_plan') ||
              (item['plan'] != null && item['plan']['id']?.toString() == planId &&
               item['status'] != 'accepted' && item['status'] != 'paid'));
        }
      });
    } catch (e) {
      debugPrint('Error handling plan_unavailable: $e');
    }
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
      if (toMark.isNotEmpty) {
        widget.onCountChanged?.call();
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
      if (toMark.isNotEmpty) {
        widget.onCountChanged?.call();
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
      final isRead = n['isRead'] == true ||
          n['read'] == true ||
          _localReadNotificationIds.contains(nId);
      if (!isRead && nId.isNotEmpty) {
        unreadIds.add(nId);
      }
    }
    if (unreadIds.isEmpty) return;

    // Persist locally so future polls don't revert these to unread
    _localReadNotificationIds.addAll(unreadIds);

    // Optimistically mark all notifications as read in local state
    setState(() {
      for (var n in _notifications) {
        final nId = n['id']?.toString() ?? '';
        if (unreadIds.contains(nId)) {
          n['read'] = true;
          n['isRead'] = true;
        }
      }
    });

    widget.onCountChanged?.call();

    // Fire-and-forget: send to server; local state is already correct
    for (var nId in unreadIds) {
      ApiService.markNotificationRead(nId);
    }
  }

  Future<void> _markNotificationAsRead(Map<String, dynamic> notif) async {
    final nId = notif['id']?.toString() ?? '';
    final isRead = notif['isRead'] == true ||
        notif['read'] == true ||
        _localReadNotificationIds.contains(nId);
    if (isRead) return;

    if (nId.isEmpty) return;

    // Persist locally so future polls don't revert this
    _localReadNotificationIds.add(nId);

    setState(() {
      notif['read'] = true;
      notif['isRead'] = true;
    });

    widget.onCountChanged?.call();

    // Fire-and-forget: local state already updated
    ApiService.markNotificationRead(nId);
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
            child: const Text('CLEAR', style: TextStyle(color: LunaraTheme.electricViolet, fontWeight: FontWeight.bold)),
          ),
        ],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
    );

    if (confirm == true) {
      // Persist all current notification IDs locally so they don't reappear
      // on the next poll even if the server hasn't cleared them yet.
      for (final n in _notifications) {
        final nId = n['id']?.toString() ?? '';
        if (nId.isNotEmpty) _localReadNotificationIds.add(nId);
      }
      setState(() {
        _notifications.clear();
      });
      widget.onCountChanged?.call();
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
      await ApiService.loadLocalReadIds();
      final data = await ApiService.fetchLiveFeedData();
      final notifs = await ApiService.fetchNotifications();

      final currentUserId = ApiService.currentUserId;
      List<Map<String, dynamic>> combined = [
        ...List<Map<String, dynamic>>.from(data['feed'] ?? []).where((item) {
          final hostId = (item['host']?['id'] ?? item['userId'] ?? '').toString();
          return hostId != currentUserId;
        }),
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
          // Re-apply local read state so polling never reverts dismissed notifications
          _notifications = notifs.map((n) {
            final nId = n['id']?.toString() ?? '';
            if (_localReadNotificationIds.contains(nId)) {
              return {...n, 'read': true, 'isRead': true};
            }
            return n;
          }).toList();
          _isLoading = false;
        });
        _markCurrentTabItemsAsRead();
        widget.onCountChanged?.call();
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

  bool _isInvite(Map<String, dynamic> item) {
    if (item['type'] != 'my_request') return false;
    final plan = item['plan'] ?? {};
    final isLargeParty = item['requestType'] == 'large_party_request';
    final isStrangerMeet = item['requestType'] == 'stranger_meet';
    final isStrangerMeetJoin = item['requestType'] == 'stranger_meet_join';
    if (isLargeParty || isStrangerMeet || isStrangerMeetJoin) return false;

    return (plan['visibility'] == 'private' || plan['visibility'] == 'both') &&
        (plan['selectedUsers'] is List && (plan['selectedUsers'] as List).contains(ApiService.currentUserId));
  }

  @override
  Widget build(BuildContext context) {
    final strangerMeetUnreadCount = _feedItems.where((i) =>
        i['type'] == 'incoming_request' &&
        (i['requestType'] == 'table_plan' || i['requestType'] == 'stranger_meet' || i['requestType'] == 'stranger_meet_join') &&
        i['status'] == 'pending' &&
        !_readRequestIds.contains(i['id']?.toString() ?? '')).length;

    final partyPlanUnreadCount = _feedItems.where((i) {
      if (i['requestType'] != 'party_plan' || i['status'] != 'pending') return false;
      if (_readRequestIds.contains(i['id']?.toString() ?? '')) return false;
      return i['type'] == 'incoming_request' || _isInvite(i);
    }).length;

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
              labelColor: LunaraTheme.electricViolet,
              unselectedLabelColor: Colors.grey,
              indicatorColor: LunaraTheme.electricViolet,
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
                    backgroundColor: LunaraTheme.electricViolet,
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
                    backgroundColor: LunaraTheme.electricViolet,
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
                    backgroundColor: LunaraTheme.electricViolet,
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
            icon: const Icon(Icons.refresh, color: LunaraTheme.electricViolet),
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
      final id = item['id']?.toString() ?? '';
      if (_clearedFeedItemIds.contains(id)) return false;
      return type == 'table_plan' ||
          ((type == 'incoming_request' || type == 'my_request') &&
              (reqType == 'table_plan' || reqType == 'stranger_meet' || reqType == 'stranger_meet_join'));
    }).toList();

    return RefreshIndicator(
      onRefresh: () => _loadFeed(showLoader: false),
      child: strangerItems.isEmpty
          ? _buildEmptyState('No Stranger Meets active right now.')
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Stranger Meets',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                          letterSpacing: 0.5,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            for (var item in strangerItems) {
                              final id = item['id']?.toString() ?? '';
                              if (id.isNotEmpty) _clearedFeedItemIds.add(id);
                            }
                          });
                        },
                        icon: const Icon(Icons.clear_all_rounded, color: LunaraTheme.electricViolet, size: 18),
                        label: const Text(
                          'CLEAR ALL',
                          style: TextStyle(
                            color: LunaraTheme.electricViolet,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          backgroundColor: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                ),
              ],
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
        if (status != 'rejected' && status != 'cancelled') {
          final planId = (item['plan']?['id'] ?? item['plan']?['planId'] ?? '').toString();
          if (planId.isNotEmpty) confirmedPlanIds.add(planId);
        }
      }
    }

    final partyItems = _feedItems.where((item) {
      final type = item['type'];
      final reqType = item['requestType'];
      final id = item['id']?.toString() ?? '';
      if (_clearedFeedItemIds.contains(id)) return false;
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
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Party Plans',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                          letterSpacing: 0.5,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            for (var item in partyItems) {
                              final id = item['id']?.toString() ?? '';
                              if (id.isNotEmpty) _clearedFeedItemIds.add(id);
                            }
                          });
                        },
                        icon: const Icon(Icons.clear_all_rounded, color: LunaraTheme.electricViolet, size: 18),
                        label: const Text(
                          'CLEAR ALL',
                          style: TextStyle(
                            color: LunaraTheme.electricViolet,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          backgroundColor: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                ),
              ],
            ),
    );
  }

  Widget _buildNotificationsFeed() {
    return RefreshIndicator(
      onRefresh: () => _loadFeed(showLoader: false),
      child: _notifications.isEmpty
          ? _buildEmptyState('No recent activity.', icon: Icons.notifications_paused_rounded)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Activity',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                          letterSpacing: 0.5,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _clearAllNotifications,
                        icon: const Icon(Icons.clear_all_rounded, color: LunaraTheme.electricViolet, size: 18),
                        label: const Text(
                          'CLEAR ALL',
                          style: TextStyle(
                            color: LunaraTheme.electricViolet,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          backgroundColor: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
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

  Widget _buildEmptyState(String text, {IconData icon = Icons.notifications_none_rounded}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.22),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
                ),
                child: Icon(
                  icon,
                  size: 48,
                  color: LunaraTheme.electricViolet.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> post) {
    final host = post['host'] ?? {};
    final venue = post['venue'] ?? {};
    final isMyPost = host['id']?.toString() == ApiService.currentUserId;
    final formattedDate = _formatPlanDate(post['planDateTime'] ?? post['planDate']);
    final timeAgo = _formatTimeAgo(post['postedAt']);
    String planTime = '21:00';
    if (post['planDateTime'] != null) {
      try {
        final parsedDt = DateTime.parse(post['planDateTime'].toString()).toLocal();
        planTime = DateFormat('hh:mm a').format(parsedDt);
      } catch (_) {}
    } else if (post['startTime'] != null) {
      planTime = post['startTime'];
    }

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
                    color: LunaraTheme.electricViolet,
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
                        final joinerPaid = myReq['joinerPaymentStatus']?.toString().toLowerCase() == 'paid' ||
                                           myReq['joinerPaymentStatus']?.toString().toLowerCase() == 'confirmed';

                        if (reqStatus == 'pending') {
                          return Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.green.withValues(alpha: 0.5),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline_rounded,
                                    color: Colors.green,
                                    size: 15,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'REQUEST SENT',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        } else if ((reqStatus == 'accepted' ||
                            reqStatus == 'payment_pending') && !joinerPaid) {
                          return Expanded(
                            child: CountdownPayButton(
                              myReq: myReq,
                              venue: venue,
                              plan: post,
                              onPaymentSuccess: () =>
                                  _loadFeed(showLoader: false),
                            ),
                          );
                        } else if (reqStatus == 'paid' || joinerPaid) {
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
    final formattedDate = _formatPlanDate(plan['planDateTime'] ?? plan['planDate']);
    final timeAgo = _formatTimeAgo(plan['postedAt']);
    String planTime = '21:00';
    if (plan['planDateTime'] != null) {
      try {
        final parsedDt = DateTime.parse(plan['planDateTime'].toString()).toLocal();
        planTime = DateFormat('hh:mm a').format(parsedDt);
      } catch (_) {}
    } else if (plan['startTime'] != null) {
      planTime = plan['startTime'];
    }

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
                Row(
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
                    if (plan['paymentType'] == 'self_pay') ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                        ),
                        child: const Text(
                          'PAID BY HOST',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
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
            if (isMyPost && plan['hostPaymentStatus']?.toString().toLowerCase() != 'paid') ...([
              Builder(
                builder: (context) {
                  final planId = plan['id']?.toString() ?? '';
                  final isSelfPay = plan['paymentType'] == 'self_pay';
                  final depositAmount = plan['depositAmount'] != null 
                      ? double.tryParse(plan['depositAmount'].toString())?.toInt() ?? (isSelfPay ? 198 : 99)
                      : (isSelfPay ? 198 : 99);
                  // Only show Pay Now if the host hasn't paid yet
                  return SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: () => _startHostPayment(planId, plan),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [LunaraTheme.electricViolet, LunaraTheme.electricViolet],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: LunaraTheme.electricViolet.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            )
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.payment_rounded, color: Colors.white, size: 15),
                            const SizedBox(width: 8),
                            Text(
                              'PAY HOST DEPOSIT (₹$depositAmount)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ]),
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    icon: Icons.info_outline,
                    label: 'DETAILS',
                    color: LunaraTheme.electricViolet,
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
                        final joinerPaid = myReq['joinerPaymentStatus']?.toString().toLowerCase() == 'paid' ||
                                           myReq['joinerPaymentStatus']?.toString().toLowerCase() == 'confirmed';

                        if (reqStatus == 'pending') {
                          return Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.green.withValues(alpha: 0.5),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline_rounded,
                                    color: Colors.green,
                                    size: 15,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'REQUEST SENT',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        } else if ((reqStatus == 'accepted' || reqStatus == 'payment_pending') && !joinerPaid) {
                          final hostPaid = myReq['plan']?['hostPaymentStatus']?.toString().toLowerCase() == 'paid' ||
                              myReq['plan']?['hostPaymentStatus']?.toString().toLowerCase() == 'refunded';
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
                        } else if (reqStatus == 'paid' || reqStatus == 'accepted' || joinerPaid) {
                          return Expanded(
                            child: Row(
                              children: [
                                Expanded(
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
                                ),
                                if (myReq['plan']?['creator'] != null || plan['host'] != null) ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChatScreen(user: {
                                              ...(myReq['plan']?['creator'] ?? plan['host'] ?? {}),
                                              'contextType': 'party_plan',
                                              'planId': myReq['plan']?['id']?.toString() ?? plan['id']?.toString(),
                                            }),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Colors.white),
                                      label: const Text('CHAT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: LunaraTheme.hotPink,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 11),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
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

  void _onHostPayDeposit(
    Map<String, dynamic> plan,
    String? hostRazorpayOrderId, {
    String? razorpayKeyId,
    int? amount,
  }) {
    final venue = plan['venue'] ?? {};
    // Resolve planId from plan object
    final planId = plan['id']?.toString() ?? plan['planId']?.toString() ?? '';

    String dateStr = 'Tonight';
    String timeStr = '21:00';
    try {
      if (plan['planDateTime'] != null) {
        final dt = DateTime.parse(plan['planDateTime'].toString()).toLocal();
        dateStr = DateFormat('dd/MM/yyyy').format(dt);
        timeStr = DateFormat('hh:mm a').format(dt);
      }
    } catch (_) {}

    final isSelfPay = plan['paymentType'] == 'self_pay';
    final resolvedAmount = amount ?? (plan['depositAmount'] != null 
        ? double.tryParse(plan['depositAmount'].toString())?.toInt() ?? (isSelfPay ? 198 : 99)
        : (isSelfPay ? 198 : 99));

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentConfirmationScreen(
          venue: venue,
          date: dateStr,
          package: 'Party Plan Safety Deposit',
          time: timeStr,
          table: 'Host Table',
          guests: isSelfPay ? 'Host + Guest (Self-Pay)' : '1 Head',
          totalPrice: '₹$resolvedAmount',
          showSplitBill: false,
          razorpayOrderId: hostRazorpayOrderId ?? plan['hostRazorpayOrderId']?.toString(),
          razorpayKeyId: razorpayKeyId,
          razorpayAmount: resolvedAmount * 100,
          onRazorpayPaymentSuccess: (paymentId, signature) async {
            try {
              final orderId = hostRazorpayOrderId ?? plan['hostRazorpayOrderId']?.toString() ?? 'mock_order';
              final success = await ApiService.verifyHostPayment(planId, orderId, paymentId, signature);
              if (!mounted) return;
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Host deposit paid successfully! ✅'),
                    backgroundColor: Colors.green,
                  ),
                );
                _loadFeed(showLoader: false);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Payment verification failed. Please contact support.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            } catch (e) {
              debugPrint('Payment verification error: $e');
            }
          },
          onPaymentSuccess: () async {
            try {
              final orderId = hostRazorpayOrderId ?? plan['hostRazorpayOrderId']?.toString() ?? 'mock_order';
              final success = await ApiService.verifyHostPayment(planId, orderId, 'mock_payment', 'mock_signature');
              if (!mounted) return;
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Host deposit paid successfully! ✅'),
                    backgroundColor: Colors.green,
                  ),
                );
                _loadFeed(showLoader: false);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Payment verification failed. Please contact support.'),
                    backgroundColor: Colors.red,
                  ),
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

  void _startHostPayment(String planId, Map<String, dynamic> plan) async {
    if (planId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not identify plan. Please refresh and try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final data = await ApiService.initiateHostPayment(planId);
    if (mounted) Navigator.pop(context);

    if (data != null && mounted) {
      // Already paid case — no new orderId, just open confirmation with existing orderId
      if (data['alreadyPaid'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Host deposit already paid!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadFeed(showLoader: false);
        return;
      }
      final orderId = data['razorpayOrderId']?.toString();
      final razorpayKeyId = data['razorpayKeyId']?.toString();
      final amount = data['amount'] is int
          ? data['amount'] as int
          : (data['amount'] is double ? (data['amount'] as double).toInt() : 99);
      _onHostPayDeposit(plan, orderId, razorpayKeyId: razorpayKeyId, amount: amount);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to initiate payment. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hostPaid = req['plan']?['hostPaymentStatus']?.toString().toLowerCase() == 'paid' ||
                     req['plan']?['hostPaymentStatus']?.toString().toLowerCase() == 'refunded' ||
                     req['planDetails']?['hostPaymentStatus']?.toString().toLowerCase() == 'paid' ||
                     req['planDetails']?['hostPaymentStatus']?.toString().toLowerCase() == 'refunded';
    final joinerPaid = req['joinerPaymentStatus']?.toString().toLowerCase() == 'paid' ||
                       req['joinerPaymentStatus']?.toString().toLowerCase() == 'confirmed';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1428) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark 
                ? LunaraTheme.hotPink.withValues(alpha: 0.4) 
                : LunaraTheme.hotPink.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: LunaraTheme.hotPink.withValues(alpha: isDark ? 0.15 : 0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                LunaraProfileImage(
                  userData: requester,
                  radius: 20,
                  isInteractive: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () {
                          try {
                            final userObj = User.fromJson(requester);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProfileScreen(user: userObj),
                              ),
                            );
                          } catch (e) {
                            debugPrint('Error navigating to profile screen: $e');
                          }
                        },
                        child: Text(
                          '${requester['firstName'] ?? 'User'} wants to join',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your ${req['requestType'] == 'table_plan' ? 'Table Plan' : (req['requestType'] == 'stranger_meet' ? 'Stranger Meet' : 'Party Plan')}',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black54,
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
                        if (req['requestType'] == 'stranger_meet') {
                          final planId = req['planId']?.toString() ?? '';
                          final success = await ApiService.handleStrangersMeetJoinRequest(planId, reqId, 'accept');
                          if (success) {
                            _loadFeed(showLoader: false);
                          } else {
                            setState(() => _optimisticStates.remove(reqId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Failed to accept request')),
                            );
                          }
                        } else {
                          final result = await ApiService.acceptPartyPlanRequest(reqId);
                          if (result != null) {
                            final hostOrderId = result['hostRazorpayOrderId']?.toString();
                            if (hostOrderId != null) {
                              final plan = req['plan'] ?? {};
                              _onHostPayDeposit(plan, hostOrderId);
                            } else {
                              _loadFeed(showLoader: false);
                            }
                          } else {
                            _loadFeed(showLoader: false);
                          }
                        }
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
                        if (req['requestType'] == 'stranger_meet') {
                          final planId = req['planId']?.toString() ?? '';
                          final success = await ApiService.handleStrangersMeetJoinRequest(planId, reqId, 'reject');
                          if (success) {
                            _loadFeed(showLoader: false);
                          } else {
                            setState(() => _optimisticStates.remove(reqId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Failed to reject request')),
                            );
                          }
                        } else {
                          await ApiService.rejectPartyPlanRequest(reqId);
                          _loadFeed(showLoader: false);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ] else if (currentStatus == 'accepted' || currentStatus == 'paid' || currentStatus == 'payment_pending') ...[
              if (hostPaid && joinerPaid) ...[
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
                      Row(
                        children: [
                          Expanded(
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
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(user: {
                                      ...requester,
                                      'contextType': 'party_plan',
                                      'planId': req['plan']?['id']?.toString(),
                                    }),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: Colors.white),
                              label: const Text(
                                'CHAT',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: LunaraTheme.hotPink,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else if (!hostPaid) ...[
                Builder(
                  builder: (context) {
                    final plan = req['plan'] ?? {};
                    final isSelfPay = plan['paymentType'] == 'self_pay';
                    final depositAmount = plan['depositAmount'] != null 
                        ? double.tryParse(plan['depositAmount'].toString())?.toInt() ?? (isSelfPay ? 198 : 99)
                        : (isSelfPay ? 198 : 99);
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: LunaraTheme.accentVivid.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.warning_amber_rounded, color: LunaraTheme.accentVivid, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'HOST DEPOSIT UNPAID',
                                style: TextStyle(
                                  color: LunaraTheme.accentVivid,
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
                                final planId = (req['planId']?.toString()?.isNotEmpty == true
                                    ? req['planId'].toString()
                                    : plan['id']?.toString() ?? '');
                                _startHostPayment(planId, plan);
                              },
                              icon: const Icon(Icons.payment, size: 16, color: Colors.white),
                              label: Text(
                                'PAY NOW (₹$depositAmount)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: LunaraTheme.electricViolet,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'AWAITING PARTICIPANT PAYMENT',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
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
    final isStrangerMeet = requestType == 'stranger_meet';
    final isStrangerMeetJoin = requestType == 'stranger_meet_join';

    final booking = isLargeParty ? (req['booking'] ?? {}) : {};
    final plan = (isLargeParty || isStrangerMeet) ? {} : (req['plan'] ?? {});
    final venue = isLargeParty
        ? (booking['venue'] ?? {})
        : (isStrangerMeet
            ? (req['venue'] ?? {})
            : (isStrangerMeetJoin ? (req['plan']?['venue'] ?? {}) : (plan['venue'] ?? {})));

    final isInvite = _isInvite(req);

    final timeAgo = _formatTimeAgo(req['createdAt']);
    final reqId = req['id']?.toString() ?? '';
    final currentStatus =
        _optimisticStates[reqId] ??
        req['status']?.toString().toLowerCase() ??
        'pending';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF101E24) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark 
                ? LunaraTheme.electricViolet.withValues(alpha: 0.4) 
                : LunaraTheme.electricViolet.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: LunaraTheme.electricViolet.withValues(alpha: isDark ? 0.12 : 0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.send,
                    color: LunaraTheme.electricViolet,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isStrangerMeet
                            ? 'You created a Stranger Meet'
                            : 'You requested to join',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        isLargeParty
                            ? 'Group Booking at ${venue['name'] ?? 'Venue'}'
                            : isStrangerMeet
                                ? 'Stranger Meet: "${req['subject'] ?? 'Subject'}" at ${venue['name'] ?? 'Venue'}'
                                : isStrangerMeetJoin
                                    ? 'Stranger Meet: "${req['plan']?['subject'] ?? 'Subject'}" at ${venue['name'] ?? 'Venue'}'
                                    : '${plan['type'] == 'table_plan' ? 'Table Plan' : 'Party Plan'} at ${venue['name'] ?? 'Venue'}',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black54,
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
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'APPROVED! PAYMENT REQUIRED: ₹${booking['totalAmount'] ?? '0'}',
                        style: const TextStyle(
                          color: Colors.blue,
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
                              color: Colors.blue,
                              outline: false,
                              onTap: () async {
                                final bookingId = booking['id']?.toString() ?? '';
                                if (bookingId.isEmpty) return;

                                // Show loading spinner
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => const Center(
                                    child: CircularProgressIndicator(
                                      color: LunaraTheme.electricViolet,
                                    ),
                                  ),
                                );

                                final paymentInfo = await ApiService.initiateLargePartyPayment(bookingId);

                                if (!mounted) return;
                                Navigator.pop(context); // Close loading spinner

                                if (paymentInfo != null && paymentInfo['success'] == true) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PaymentConfirmationScreen(
                                        venue: venue,
                                        date: booking['bookingDate'] != null
                                            ? DateFormat('dd/MM/yyyy').format(DateTime.parse(booking['bookingDate']).toLocal())
                                            : 'Tonight',
                                        package: 'Large Party Booking Deposit',
                                        time: booking['startTime'] ?? '21:00',
                                        table: 'Large Party Table',
                                        guests: '${booking['numberOfGuests'] ?? 1} Guests',
                                        totalPrice: '₹${booking['totalAmount'] ?? '0'}',
                                        showSplitBill: false,
                                        razorpayOrderId: paymentInfo['razorpayOrderId'],
                                        razorpayKeyId: paymentInfo['razorpayKeyId'],
                                        razorpayAmount: paymentInfo['amount'],
                                        onRazorpayPaymentSuccess: (paymentId, signature) async {
                                          final success = await ApiService.verifyLargePartyPayment(
                                            bookingId,
                                            razorpayOrderId: paymentInfo['razorpayOrderId'],
                                            razorpayPaymentId: paymentId,
                                            razorpaySignature: signature,
                                          );
                                          if (!mounted) return;
                                          if (success) {
                                            setState(() {
                                              _optimisticStates[reqId] = 'payment_done';
                                            });
                                            _loadFeed(showLoader: false);
                                          } else {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Payment Verification Failed.'),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to initiate payment. Please try again.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
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
            ] else if (isStrangerMeet) ...[
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
              ] else if (currentStatus == 'rejected') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Center(
                    child: Text(
                      'REJECTED: ${req['adminNotes'] ?? 'No notes provided'}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ] else if (currentStatus == 'approved' && req['paymentStatus'] != 'paid') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'APPROVED! PLATFORM DEPOSIT REQUIRED: ₹${req['paymentAmount'] ?? '0'}',
                        style: const TextStyle(
                          color: LunaraTheme.electricViolet,
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
                              color: LunaraTheme.electricViolet,
                              outline: false,
                              onTap: () {
                                final meetReq = StrangersMeetRequest.fromJson(req);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StrangersMeetPaymentScreen(
                                      request: meetReq,
                                      onPaymentSuccess: () {
                                        setState(() {
                                          _optimisticStates[reqId] = 'paid';
                                        });
                                        _loadFeed(showLoader: false);
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.blue, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        currentStatus == 'completed' ? 'COMPLETED' : 'PAYMENT CONFIRMED & PUBLISHED',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (currentStatus == 'approved' || currentStatus == 'paid' || currentStatus == 'completed') ...[
                Builder(
                  builder: (context) {
                    final meetRequests = _getJoinRequestsForMeet(reqId);
                    if (meetRequests.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 8),
                        const Text(
                          'JOIN REQUESTS',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...meetRequests.map((joinReq) {
                          final joinReqId = joinReq['id']?.toString() ?? '';
                          final joiner = joinReq['requester'] ?? {};
                          final joinerStatus = _optimisticStates[joinReqId] ?? joinReq['status']?.toString().toLowerCase() ?? 'pending';
                          final joinerPayment = joinReq['joinerPaymentStatus']?.toString().toLowerCase() ?? 'pending';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: Row(
                              children: [
                                LunaraProfileImage(
                                  userData: joiner,
                                  radius: 16,
                                  isInteractive: false,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        joiner['firstName'] ?? 'User',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        joinerStatus == 'paid' || joinerPayment == 'paid'
                                            ? 'PAID & JOINED'
                                            : joinerStatus.toUpperCase(),
                                        style: TextStyle(
                                          color: joinerStatus == 'paid' || joinerPayment == 'paid'
                                              ? Colors.green
                                              : (joinerStatus == 'accepted' ? Colors.orange : Colors.grey),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (joinerStatus == 'pending') ...[
                                  IconButton(
                                    icon: const Icon(Icons.check_circle_outline, color: Colors.green, size: 22),
                                    onPressed: () async {
                                      setState(() => _optimisticStates[joinReqId] = 'accepted');
                                      final success = await ApiService.handleStrangersMeetJoinRequest(reqId, joinReqId, 'accept');
                                      if (success) {
                                        _loadFeed(showLoader: false);
                                      } else {
                                        setState(() => _optimisticStates.remove(joinReqId));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Failed to accept request')),
                                        );
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 22),
                                    onPressed: () async {
                                      setState(() => _optimisticStates[joinReqId] = 'rejected');
                                      final success = await ApiService.handleStrangersMeetJoinRequest(reqId, joinReqId, 'reject');
                                      if (success) {
                                        _loadFeed(showLoader: false);
                                      } else {
                                        setState(() => _optimisticStates.remove(joinReqId));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Failed to reject request')),
                                        );
                                      }
                                    },
                                  ),
                                ],
                                if (joinerStatus == 'paid' || joinerPayment == 'paid') ...[
                                  IconButton(
                                    icon: const Icon(Icons.chat_bubble_outline_rounded, color: LunaraTheme.hotPink, size: 22),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(user: {
                                            ...joiner,
                                            'contextType': 'stranger_meet',
                                            'planId': reqId,
                                          }),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    );
                  }
                ),
              ],
            ] else if (isStrangerMeetJoin) ...[
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
                      'PENDING HOST APPROVAL',
                      style: TextStyle(
                        color: Colors.yellow,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ] else if (currentStatus == 'rejected') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: const Center(
                    child: Text(
                      'REJECTED BY HOST',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ] else if (currentStatus == 'accepted' || currentStatus == 'payment_pending') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'ACCEPTED! CHARGES PER HEAD: ₹${req['chargesPerHead'] ?? '0'}',
                        style: const TextStyle(
                          color: LunaraTheme.electricViolet,
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
                              color: LunaraTheme.electricViolet,
                              outline: false,
                              onTap: () {
                                final meetPlan = StrangersMeetRequest.fromJson(req['plan'] ?? {});
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StrangersMeetPaymentScreen(
                                      request: meetPlan,
                                      isJoinPayment: true,
                                      onPaymentSuccess: () {
                                        setState(() {
                                          _optimisticStates[reqId] = 'paid';
                                        });
                                        _loadFeed(showLoader: false);
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
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
                      if (req['plan']?['ticketId'] != null) ...[
                        const SizedBox(height: 10),
                      Row(
                        children: [
                          if (req['plan']?['ticketId'] != null) ...[
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  final meetPlan = StrangersMeetRequest.fromJson(req['plan']);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => StrangersMeetTicketScreen(
                                        request: meetPlan,
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
                          if (req['plan']?['user'] != null) ...[
                            if (req['plan']?['ticketId'] != null) const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(user: {
                                        ...req['plan']?['user'],
                                        'contextType': 'stranger_meet',
                                        'planId': req['plan']?['id']?.toString(),
                                      }),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: Colors.white),
                                label: const Text(
                                  'CHAT',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: LunaraTheme.hotPink,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      ],
                    ],
                  ),
                ),
              ],
            ] else ...[
              if (currentStatus == 'pending') ...[
                if (isInvite) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'YOU WERE INVITED!',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _actionButton(
                                icon: Icons.check_circle,
                                label: 'ACCEPT',
                                color: Colors.green,
                                outline: false,
                                onTap: () async {
                                  setState(() => _optimisticStates[reqId] = 'accepted');
                                  final res = await ApiService.acceptPartyPlanInvite(reqId);
                                  if (res != null) {
                                    _loadFeed(showLoader: false);
                                  } else {
                                    setState(() => _optimisticStates.remove(reqId));
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Failed to accept invite')),
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _actionButton(
                                icon: Icons.cancel,
                                label: 'DECLINE',
                                color: Colors.red,
                                outline: true,
                                onTap: () async {
                                  setState(() => _optimisticStates[reqId] = 'cancelled');
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
                ] else ...[
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
                        'PENDING HOST APPROVAL',
                        style: TextStyle(
                          color: Colors.yellow,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ] else if ((currentStatus == 'accepted' || currentStatus == 'payment_pending') &&
                  req['joinerPaymentStatus']?.toString().toLowerCase() != 'confirmed' &&
                  req['joinerPaymentStatus']?.toString().toLowerCase() != 'paid') ...[
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
                          final hostPaid = req['plan']?['hostPaymentStatus']?.toString().toLowerCase() == 'paid' ||
                              req['plan']?['hostPaymentStatus']?.toString().toLowerCase() == 'refunded';
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
              ] else if (currentStatus == 'paid' || 
                         req['joinerPaymentStatus']?.toString().toLowerCase() == 'paid' ||
                         req['joinerPaymentStatus']?.toString().toLowerCase() == 'confirmed') ...[
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
                            'PARTY PLAN CONFIRMED 🎉',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
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
                          if (req['plan']?['creator'] != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(user: {
                                        ...req['plan']?['creator'],
                                        'contextType': 'party_plan',
                                        'planId': req['plan']?['id']?.toString(),
                                      }),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: Colors.white),
                                label: const Text(
                                  'CHAT',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: LunaraTheme.hotPink,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    IconData icon = Icons.notifications_rounded;
    Color color = LunaraTheme.electricViolet;
    if (title.toLowerCase().contains('super')) {
      icon = Icons.star_rounded;
      color = const Color(0xFFFFB800); // Gold/Amber for Super Like
    } else if (title.toLowerCase().contains('like')) {
      icon = Icons.favorite_rounded;
      color = LunaraTheme.hotPink; // Hot Pink for Like
    } else if (title.toLowerCase().contains('payment')) {
      icon = Icons.payment_rounded;
      color = const Color(0xFF00E676); // Beautiful emerald green
    } else if (title.toLowerCase().contains('visit') ||
        title.toLowerCase().contains('view')) {
      icon = Icons.visibility_rounded;
      color = LunaraTheme.electricViolet; // Purple matching theme color instead of blue
    }

    final sender = notif['sender'];
    final hasSender = sender != null && sender['id'] != null;

    final cardBg = isDark
        ? (isRead ? const Color(0xFF16161E) : const Color(0xFF221A30))
        : (isRead ? Colors.white : const Color(0xFFF9F5FF));
    final borderCol = isRead
        ? (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05))
        : LunaraTheme.electricViolet.withValues(alpha: 0.3);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _markNotificationAsRead(notif),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderCol,
              width: isRead ? 1.0 : 1.5,
            ),
            boxShadow: isRead 
                ? null 
                : [
                    BoxShadow(
                      color: LunaraTheme.electricViolet.withValues(alpha: isDark ? 0.15 : 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Section: Avatar or Icon Badge
              if (hasSender)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    LunaraProfileImage(
                      userData: sender,
                      radius: 20,
                      showGradientBorder: !isRead,
                      isInteractive: true,
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF16161E) : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? const Color(0xFF16161E) : Colors.white,
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          icon,
                          color: isRead ? color.withValues(alpha: 0.6) : color,
                          size: 10,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: 0.15),
                        color.withValues(alpha: 0.05),
                      ],
                    ),
                    border: Border.all(
                      color: color.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      color: isRead ? color.withValues(alpha: 0.6) : color,
                      size: 20,
                    ),
                  ),
                ),
              const SizedBox(width: 14),

              // Middle Section: Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark 
                            ? (isRead ? Colors.white70 : Colors.white)
                            : (isRead ? Colors.black87 : Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        color: isDark 
                            ? (isRead ? Colors.white54 : Colors.white70)
                            : (isRead ? Colors.black54 : Colors.black87),
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                    if (hasSender) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () {
                          try {
                            final userObj = User.fromJson(Map<String, dynamic>.from(sender));
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProfileScreen(user: userObj),
                              ),
                            );
                          } catch (e) {
                            debugPrint('Error navigating to profile: $e');
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [LunaraTheme.electricViolet, LunaraTheme.hotPink],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_outline_rounded, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'View Profile',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Right Section: Unread indicator & Time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isRead)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6, top: 4),
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: LunaraTheme.hotPink,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: LunaraTheme.hotPink,
                            blurRadius: 4,
                            spreadRadius: 1,
                          )
                        ],
                      ),
                    ),
                  Text(
                    timeAgo,
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 10,
                      fontWeight: isRead ? FontWeight.normal : FontWeight.w500,
                    ),
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
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(widget.plan['planDateTime'].toString()).toLocal())
        : 'Tonight';
    final planTime = widget.plan['planDateTime'] != null
        ? DateFormat('hh:mm a').format(DateTime.parse(widget.plan['planDateTime'].toString()).toLocal())
        : '21:00';
    final reqId = widget.myReq['id']?.toString() ?? '';
    final isSelfPay = widget.plan['paymentType'] == 'self_pay' || 
                      widget.myReq['plan']?['paymentType'] == 'self_pay';
    final label = isSelfPay
        ? 'CONFIRM JOIN 🎉'
        : (_secondsLeft > 0
            ? 'PAY NOW (${_formatDuration(_secondsLeft)})'
            : 'PAY NOW');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        if (reqId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid request ID.'), backgroundColor: Colors.red),
          );
          return;
        }

        if (isSelfPay) {
          // Confirm self paid join directly
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
            ),
          );
          try {
            final success = await ApiService.confirmSelfPaidJoin(reqId);
            if (!mounted) return;
            Navigator.pop(context); // Close spinner
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
                const SnackBar(content: Text('Failed to confirm join.'), backgroundColor: Colors.red),
              );
            }
          } catch (e) {
            if (mounted) Navigator.pop(context);
            debugPrint('Error confirming self paid join: $e');
          }
          return;
        }

        // Show loading spinner
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
          ),
        );

        Map<String, dynamic>? data;
        try {
          data = await ApiService.initiateJoinerPayment(reqId);
        } catch (e) {
          debugPrint('Error initiating joiner payment: $e');
        } finally {
          if (mounted) Navigator.pop(context); // Close loading spinner
        }

        if (data != null && mounted) {
          // Use the FRESH orderId returned by the server (it may differ from cached one)
          final freshOrderId = data['razorpayOrderId']?.toString() ?? '';
          final razorpayKeyId = data['razorpayKeyId']?.toString();
          final razorpayAmount = data['amount'] is int
              ? (data['amount'] as int) * 100
              : int.tryParse(data['amount']?.toString() ?? '') != null
                  ? (int.parse(data['amount'].toString())) * 100
                  : 9900;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentConfirmationScreen(
                venue: widget.venue,
                date: planDate,
                time: planTime,
                package: 'Party Plan Safety Deposit',
                totalPrice: '₹${data?['amount'] ?? 99}',
                showSplitBill: false,
                razorpayOrderId: freshOrderId,
                razorpayKeyId: razorpayKeyId,
                razorpayAmount: razorpayAmount,
                onRazorpayPaymentSuccess: (paymentId, signature) async {
                  try {
                    // Show loading spinner for verification
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const Center(
                        child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
                      ),
                    );
                    final success = await ApiService.verifyJoinerPayment(
                      reqId, freshOrderId, paymentId, signature,
                    );
                    if (!mounted) return;
                    Navigator.pop(context); // Close verification spinner
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
                    // Show loading spinner for verification
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const Center(
                        child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
                      ),
                    );
                    final success = await ApiService.verifyJoinerPayment(
                      reqId, freshOrderId, 'mock_payment', 'mock_signature',
                    );
                    if (!mounted) return;
                    Navigator.pop(context); // Close verification spinner
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
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to initiate payment. Please try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
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

