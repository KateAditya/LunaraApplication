import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../services/push_notification_service.dart';
import '../../models/user.dart';
import '../profile/profile_screen.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../widgets/top_notification_banner.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  // Primary Tabs: 0: ALL, 1: REQUESTS, 2: ACTIVITY
  int _selectedPrimaryTab = 0;

  // Secondary Filter: 0: ALL, 1: PARTNER REQUESTS, 2: INTERESTS, 3: BOOKINGS, 4: TICKETS, 5: MESSAGES, 6: OTHER
  int _selectedCategoryFilter = 0;

  bool _isLoading = true;
  List<dynamic> _notifications = [];

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    ApiService.addSocketListener('notification_created', _onSocketNotification);
    ApiService.addSocketListener('notification_received', _onSocketNotification);
    ApiService.addSocketListener('notification_updated', _onSocketNotificationUpdated);
  }

  @override
  void dispose() {
    ApiService.removeSocketListener('notification_created', _onSocketNotification);
    ApiService.removeSocketListener('notification_received', _onSocketNotification);
    ApiService.removeSocketListener('notification_updated', _onSocketNotificationUpdated);
    super.dispose();
  }

  void _onSocketNotification(dynamic data) {
    if (!mounted || data == null) return;
    final Map<String, dynamic> notifMap = data is Map ? Map<String, dynamic>.from(data) : {};

    TopNotificationBanner.show(
      title: notifMap['title'] ?? 'New Notification',
      body: notifMap['body'] ?? '',
      data: notifMap['data'] is Map ? Map<String, dynamic>.from(notifMap['data']) : notifMap,
      senderData: notifMap['sender'] is Map ? Map<String, dynamic>.from(notifMap['sender']) : null,
    );

    setState(() {
      _notifications.insert(0, notifMap);
    });
  }

  void _onSocketNotificationUpdated(dynamic data) {
    if (!mounted || data == null) return;
    final Map<String, dynamic> updatedNotif = data is Map ? Map<String, dynamic>.from(data) : {};
    final id = updatedNotif['id']?.toString() ?? updatedNotif['notification']?['id']?.toString();
    if (id == null) return;

    setState(() {
      final index = _notifications.indexWhere((n) => n['id']?.toString() == id);
      if (index != -1) {
        _notifications[index] = updatedNotif['notification'] ?? updatedNotif;
      }
    });
  }

  Future<void> _fetchNotifications() async {
    final currentUid = ApiService.currentUserId ?? '';
    if (currentUid.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await ApiService.get('/api/mobile/user/notifications?userId=$currentUid');
      if (response.statusCode == 200 && mounted) {
        final bodyData = jsonDecode(response.body);
        if (bodyData != null && bodyData['data'] is List) {
          setState(() {
            _notifications = List<dynamic>.from(bodyData['data']);
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(dynamic item) async {
    final notifId = item['id']?.toString();
    final currentUid = ApiService.currentUserId ?? '';

    if (notifId != null && notifId.isNotEmpty && currentUid.isNotEmpty) {
      try {
        await ApiService.patch('/api/mobile/user/notifications/$notifId/read?userId=$currentUid', body: {});
      } catch (e) {
        debugPrint('Error marking notification as read: $e');
      }
    }

    if (mounted) {
      setState(() {
        item['read'] = true;
        item['isRead'] = true;
      });
    }

    final Map<String, dynamic> payloadData = {};
    if (item is Map) {
      payloadData.addAll(Map<String, dynamic>.from(item));
      if (item['data'] is Map) {
        payloadData.addAll(Map<String, dynamic>.from(item['data']));
      }
      if (item['metadata'] is Map) {
        payloadData.addAll(Map<String, dynamic>.from(item['metadata']));
      }
      if (!payloadData.containsKey('type') && item['eventType'] != null) {
        payloadData['type'] = item['eventType'];
      }
      if (!payloadData.containsKey('requestId') && item['entityId'] != null) {
        payloadData['requestId'] = item['entityId'];
      }
    }
    PushNotificationService.navigateFromPayload(payloadData);
  }

  Future<void> _markAllAsRead() async {
    final currentUid = ApiService.currentUserId ?? '';
    if (currentUid.isEmpty) return;

    try {
      final response = await ApiService.post(
        '/api/mobile/notifications/mark-all-read',
        body: {'userId': currentUid},
      );
      if (response.statusCode == 200 && mounted) {
        setState(() {
          for (var item in _notifications) {
            item['read'] = true;
            item['isRead'] = true;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications marked as read'),
            backgroundColor: LunaraTheme.electricViolet,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error marking all as read: $e');
    }
  }

  Future<void> _handleNotificationAction(dynamic item, String action) async {
    final notifId = item['id']?.toString();
    final currentUid = ApiService.currentUserId ?? '';

    if (notifId == null || notifId.isEmpty || currentUid.isEmpty) return;

    // Optimistic UI update
    setState(() {
      item['read'] = true;
      item['isRead'] = true;
      item['metadata'] = {
        ...(item['metadata'] is Map ? item['metadata'] : {}),
        'status': 'ACTIONED',
        'actionExecuted': action,
      };
    });

    try {
      final payloadData = item['data'] is Map
          ? Map<String, dynamic>.from(item['data'])
          : (item['metadata'] is Map ? Map<String, dynamic>.from(item['metadata']) : <String, dynamic>{});
      final requestId = payloadData['requestId']?.toString() ?? item['entityId']?.toString();
      final entityType = (item['entityType'] ?? payloadData['type'] ?? '').toString();

      if ((entityType == 'night_partner' || entityType == 'NightPartnerRequest' || entityType.contains('PARTNER_REQUEST')) && requestId != null && requestId.isNotEmpty) {
        final act = action.toUpperCase() == 'ACCEPT' ? 'accept' : 'decline';
        await ApiService.respondToNightPartnerRequest(requestId: requestId, action: act);
      }

      final response = await ApiService.post(
        '/api/mobile/notifications/$notifId/action',
        body: {'action': action, 'userId': currentUid},
      );

      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action.toUpperCase() == 'ACCEPT' ? '🎉 Invite Accepted!' : 'Invite Declined'),
            backgroundColor: action.toUpperCase() == 'ACCEPT' ? Colors.green : Colors.grey[800],
          ),
        );
        _fetchNotifications();
      }
    } catch (e) {
      debugPrint('Error processing action: $e');
    }
  }

  Future<void> _confirmClearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear Notifications?',
          style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will clear your notification view. Critical transactional records remain preserved in history.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: LunaraTheme.electricViolet,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('CLEAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _clearAllNotifications();
    }
  }

  Future<void> _clearAllNotifications() async {
    final currentUid = ApiService.currentUserId ?? '';
    if (currentUid.isEmpty) return;

    try {
      final response = await ApiService.post(
        '/api/mobile/notifications/clear-all',
        body: {'userId': currentUid},
      );
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _notifications.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notifications cleared'), backgroundColor: LunaraTheme.electricViolet),
        );
      }
    } catch (e) {
      debugPrint('Error clearing notifications: $e');
    }
  }

  // ── Tab & Category Filter Logic ──────────────────────────────────────────────
  List<dynamic> get _filteredNotifications {
    var list = _notifications;

    // 1. Primary Navigation Tab Filter
    if (_selectedPrimaryTab == 1) {
      // REQUESTS
      list = list.where((n) {
        final title = (n['title'] ?? '').toString().toLowerCase();
        final type = (n['data']?['type'] ?? n['eventType'] ?? n['id'] ?? '').toString().toLowerCase();
        final category = (n['category'] ?? '').toString().toLowerCase();
        return category == 'requests' ||
            title.contains('request') ||
            title.contains('interest') ||
            title.contains('invite') ||
            type.contains('request') ||
            type.contains('interest');
      }).toList();
    } else if (_selectedPrimaryTab == 2) {
      // ACTIVITY
      list = list.where((n) {
        final title = (n['title'] ?? '').toString().toLowerCase();
        final type = (n['data']?['type'] ?? n['eventType'] ?? n['id'] ?? '').toString().toLowerCase();
        final category = (n['category'] ?? '').toString().toLowerCase();
        return category == 'events' ||
            category == 'system' ||
            title.contains('created') ||
            title.contains('published') ||
            title.contains('joined') ||
            type.contains('created') ||
            type.contains('joined');
      }).toList();
    }

    // 2. Secondary Category Pill Filter
    if (_selectedCategoryFilter == 0) return list;

    return list.where((n) {
      final title = (n['title'] ?? '').toString().toLowerCase();
      final type = (n['data']?['type'] ?? n['eventType'] ?? n['id'] ?? '').toString().toLowerCase();

      if (_selectedCategoryFilter == 1) {
        // PARTNER REQUESTS
        return title.contains('request') || type.contains('request');
      } else if (_selectedCategoryFilter == 2) {
        // INTERESTS
        return title.contains('interest') || type.contains('interest');
      } else if (_selectedCategoryFilter == 3) {
        // BOOKINGS
        return title.contains('booking') || title.contains('confirm') || type.contains('booking');
      } else if (_selectedCategoryFilter == 4) {
        // TICKETS
        return title.contains('ticket') || type.contains('ticket');
      } else if (_selectedCategoryFilter == 5) {
        // MESSAGES
        return title.contains('message') || title.contains('chat') || type.contains('chat');
      } else if (_selectedCategoryFilter == 6) {
        // OTHER
        return true;
      }
      return true;
    }).toList();
  }

  Map<String, List<dynamic>> _groupNotificationsByDate(List<dynamic> items) {
    final Map<String, List<dynamic>> grouped = {
      'Today': [],
      'Yesterday': [],
      'This Week': [],
      'Earlier': [],
    };

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final weekStart = todayStart.subtract(const Duration(days: 7));

    for (final item in items) {
      final rawDate = item['createdAt'] ?? item['updatedAt'];
      DateTime itemDate = now;
      if (rawDate != null) {
        try {
          itemDate = DateTime.parse(rawDate.toString()).toLocal();
        } catch (_) {}
      }

      if (itemDate.isAfter(todayStart)) {
        grouped['Today']!.add(item);
      } else if (itemDate.isAfter(yesterdayStart)) {
        grouped['Yesterday']!.add(item);
      } else if (itemDate.isAfter(weekStart)) {
        grouped['This Week']!.add(item);
      } else {
        grouped['Earlier']!.add(item);
      }
    }

    return grouped;
  }

  String _formatTimeAgo(dynamic rawDateStr) {
    if (rawDateStr == null) return '';
    DateTime dt = DateTime.now();
    try {
      dt = DateTime.parse(rawDateStr.toString()).toLocal();
    } catch (_) {
      return '';
    }

    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM dd, hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredNotifications;
    final grouped = _groupNotificationsByDate(filtered);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'NOTIFICATIONS',
          style: TextStyle(
            fontSize: 16,
            letterSpacing: 2.5,
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Mark all as read',
            icon: const Icon(Icons.done_all_rounded, color: LunaraTheme.electricViolet, size: 22),
            onPressed: _markAllAsRead,
          ),
          if (_notifications.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF475569)),
              color: Colors.white,
              onSelected: (val) {
                if (val == 'clear') _confirmClearAll();
                if (val == 'mark_read') _markAllAsRead();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'mark_read',
                  child: Text('Mark all as read', style: TextStyle(color: Color(0xFF0F172A), fontSize: 13)),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Text('Clear notification view', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                ),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            _buildPrimaryNavigationTabs(),
            const SizedBox(height: 10),
            _buildCategoryFilterPills(),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? _buildSkeletonLoader()
                  : filtered.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          color: LunaraTheme.electricViolet,
                          onRefresh: _fetchNotifications,
                          child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            children: [
                              for (final section in ['Today', 'Yesterday', 'This Week', 'Earlier'])
                                if (grouped[section] != null && grouped[section]!.isNotEmpty) ...[
                                  _buildSectionHeader(section, grouped[section]!.length),
                                  ...grouped[section]!.map((item) => _buildTypedNotificationCard(item)),
                                  const SizedBox(height: 14),
                                ],
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Primary Navigation Tabs (ALL | REQUESTS | ACTIVITY) ───────────────────
  Widget _buildPrimaryNavigationTabs() {
    final tabs = ['ALL', 'REQUESTS', 'ACTIVITY'];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final isSelected = _selectedPrimaryTab == entry.key;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedPrimaryTab = entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? LunaraTheme.electricViolet : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF64748B),
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Secondary Category Pills ───────────────────────────────────────────────
  Widget _buildCategoryFilterPills() {
    final categories = ['All', 'Requests', 'Interests', 'Bookings', 'Tickets', 'Messages', 'Other'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: categories.asMap().entries.map((entry) {
          final isSelected = _selectedCategoryFilter == entry.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedCategoryFilter = entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? LunaraTheme.electricViolet : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? LunaraTheme.electricViolet : const Color(0xFFE2E8F0),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: LunaraTheme.electricViolet.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10, left: 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Reusable Typed Card Dispatcher ─────────────────────────────────────────
  Widget _buildTypedNotificationCard(dynamic item) {
    final title = (item['title'] ?? '').toString();
    final titleLower = title.toLowerCase();
    final eventType = (item['eventType'] ?? item['data']?['type'] ?? '').toString().toUpperCase();

    if (eventType.contains('PARTNER_REQUEST') || titleLower.contains('wants to join') || titleLower.contains('partner request')) {
      return _buildPartnerRequestCard(item);
    } else if (eventType.contains('INTEREST') || titleLower.contains('interested')) {
      return _buildInterestCard(item);
    } else if (eventType.contains('REQUEST_ACCEPTED') || titleLower.contains('accepted your')) {
      return _buildRequestAcceptedCard(item);
    } else if (eventType.contains('BOOKING_CONFIRMED') || titleLower.contains('booking confirmed')) {
      return _buildBookingConfirmedCard(item);
    } else if (eventType.contains('MATCH') || titleLower.contains("it's a match")) {
      return _buildMatchCard(item);
    } else if (eventType.contains('TICKET') || titleLower.contains('ticket')) {
      return _buildTicketReadyCard(item);
    } else if (eventType.contains('MESSAGE') || titleLower.contains('message')) {
      return _buildChatMessageCard(item);
    } else if (eventType.contains('REMINDER') || titleLower.contains('starting soon')) {
      return _buildEventReminderCard(item);
    } else if (eventType.contains('EXPIRED') || titleLower.contains('completed') || titleLower.contains('ended')) {
      return _buildExpiredCard(item);
    }

    return _buildGenericCard(item);
  }

  void _openUserProfile(dynamic actorData) {
    if (actorData == null) return;
    Map<String, dynamic> userMap = {};
    if (actorData is Map) {
      userMap = Map<String, dynamic>.from(actorData);
    } else if (actorData is String && actorData.trim().isNotEmpty) {
      userMap = {'id': actorData.trim()};
    }

    if (userMap.isEmpty) return;

    final uid = userMap['id']?.toString() ??
        userMap['userId']?.toString() ??
        userMap['_id']?.toString() ??
        userMap['actorUserId']?.toString() ??
        '';
    if (uid.isEmpty) return;

    final userObj = User.fromJson({
      'id': uid,
      'firstName': userMap['firstName'] ?? userMap['name'] ?? userMap['username'] ?? 'User',
      'lastName': userMap['lastName'] ?? '',
      'photos': userMap['photos'] ?? (userMap['photoUrl'] != null ? [{'url': userMap['photoUrl']}] : []),
      'profile': userMap['profile'] ?? {},
      'bio': userMap['bio'] ?? '',
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileScreen(user: userObj),
      ),
    );
  }

  // ── 1. Partner Request Card Component ──────────────────────────────────────
  Widget _buildPartnerRequestCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final actor = item['actor'] ?? item['sender'] ?? item['actorUserId'];
    final actorName = actor is Map ? (actor['firstName'] ?? actor['name'] ?? 'User') : 'User';
    final body = item['body']?.toString() ?? 'Wants to join your event.';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _markAsRead(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openUserProfile(actor),
            child: Row(
              children: [
                LunaraProfileImage(userData: actor is Map ? Map<String, dynamic>.from(actor) : {}, radius: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$actorName wants to join your event', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(timeStr, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                if (isUnread) _buildUnreadDot(),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(body, style: const TextStyle(color: Color(0xFF475569), fontSize: 12, height: 1.3)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openUserProfile(actor),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('View Profile', style: TextStyle(color: Color(0xFF475569), fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _handleNotificationAction(item, 'ACCEPT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LunaraTheme.electricViolet,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Accept', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 18),
                onPressed: () => _handleNotificationAction(item, 'DECLINE'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 2. Interested User Card Component ──────────────────────────────────────
  Widget _buildInterestCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final actor = item['actor'] ?? item['sender'];
    final actorName = actor?['firstName'] ?? actor?['name'] ?? 'Someone';
    final body = item['body']?.toString() ?? '$actorName is interested in your Stranger Meet.';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _markAsRead(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openUserProfile(actor),
            child: Row(
              children: [
                if (actor != null && actor is Map && actor.isNotEmpty) ...[
                  LunaraProfileImage(userData: Map<String, dynamic>.from(actor), radius: 18),
                  const SizedBox(width: 10),
                ] else
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Color(0xFFFCE7F3), shape: BoxShape.circle),
                    child: const Icon(Icons.favorite_rounded, color: LunaraTheme.hotPink, size: 18),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('❤️ New Interest', style: TextStyle(color: LunaraTheme.hotPink, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(timeStr, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
                    ],
                  ),
                ),
                if (isUnread) _buildUnreadDot(),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(body, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600, height: 1.3)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _markAsRead(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'View Interest',
                        style: TextStyle(color: LunaraTheme.electricViolet, fontSize: 12, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => _handleNotificationAction(item, 'DECLINE'),
                  child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'Ignore',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 3. Request Accepted Card Component ─────────────────────────────────────
  Widget _buildRequestAcceptedCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final actor = item['actor'] ?? item['sender'];
    final actorName = actor?['firstName'] ?? actor?['name'] ?? 'User';
    final body = item['body']?.toString() ?? 'You are going together!';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _markAsRead(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _openUserProfile(actor),
                child: LunaraProfileImage(userData: actor is Map ? Map<String, dynamic>.from(actor) : {}, radius: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$actorName accepted your request', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13.5)),
                    const SizedBox(height: 2),
                    Text(timeStr, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
                  ],
                ),
              ),
              if (isUnread) _buildUnreadDot(),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: Color(0xFF475569), fontSize: 12.5)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _markAsRead(item),
            icon: const Icon(Icons.chat_bubble_rounded, size: 14, color: Colors.white),
            label: const Text("Let's Chat", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: LunaraTheme.electricViolet,
              minimumSize: const Size(double.infinity, 38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ── 4. Booking Confirmed Card Component ────────────────────────────────────
  Widget _buildBookingConfirmedCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final body = item['body']?.toString() ?? 'Your booking is confirmed. Get ready for the party!';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _markAsRead(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Color(0xFFD1FAE5), shape: BoxShape.circle),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Booking Confirmed 🎉', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(timeStr, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
                  ],
                ),
              ),
              if (isUnread) _buildUnreadDot(),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: Color(0xFF475569), fontSize: 12.5)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _markAsRead(item),
                  icon: const Icon(Icons.confirmation_number_outlined, size: 14, color: Colors.white),
                  label: const Text('View Ticket', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LunaraTheme.electricViolet,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('Open Chat', style: TextStyle(color: LunaraTheme.electricViolet, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 5. Match / Celebration Card Component ──────────────────────────────────
  Widget _buildMatchCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final body = item['body']?.toString() ?? "You're going to the party together!";
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _markAsRead(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Color(0xFFFCE7F3), shape: BoxShape.circle),
                child: const Icon(Icons.favorite_rounded, color: LunaraTheme.hotPink, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("💜 It's a Match!", style: TextStyle(color: LunaraTheme.hotPink, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(timeStr, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
                  ],
                ),
              ),
              if (isUnread) _buildUnreadDot(),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _markAsRead(item),
            icon: const Icon(Icons.forum_rounded, size: 14, color: Colors.white),
            label: const Text("Let's Chat", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: LunaraTheme.hotPink,
              minimumSize: const Size(double.infinity, 38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ── 6. Ticket Ready Card Component ─────────────────────────────────────────
  Widget _buildTicketReadyCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final body = item['body']?.toString() ?? 'Your digital pass is generated.';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _markAsRead(item),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Color(0xFFE0F2FE), shape: BoxShape.circle),
            child: const Icon(Icons.confirmation_number_rounded, color: Color(0xFF0284C7), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🎟 Your Ticket is Ready', style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(color: Color(0xFF475569), fontSize: 11.5)),
                const SizedBox(height: 4),
                Text(timeStr, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _markAsRead(item),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Pass', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  // ── 7. Chat Message Card Component ────────────────────────────────────────
  Widget _buildChatMessageCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final body = item['body']?.toString() ?? 'Sent a message.';
    final actor = item['actor'] ?? item['sender'];
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _markAsRead(item),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _openUserProfile(actor),
            child: LunaraProfileImage(userData: actor is Map ? Map<String, dynamic>.from(actor) : {}, radius: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['title']?.toString() ?? 'New Message', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(color: Color(0xFF475569), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(timeStr, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
              ],
            ),
          ),
          if (isUnread) _buildUnreadDot(),
        ],
      ),
    );
  }

  // ── 8. Event Reminder Card Component ───────────────────────────────────────
  Widget _buildEventReminderCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final body = item['body']?.toString() ?? 'Your Stranger Meet starts tomorrow at 8:00 PM';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _markAsRead(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Color(0xFFFFE4E6), shape: BoxShape.circle),
                child: const Icon(Icons.access_time_filled_rounded, color: Color(0xFFF43F5E), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Event Reminder ⏰', style: TextStyle(color: Color(0xFFF43F5E), fontWeight: FontWeight.w900, fontSize: 12.5, letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(timeStr, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
                  ],
                ),
              ),
              if (isUnread) _buildUnreadDot(),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text('View Event', style: TextStyle(color: LunaraTheme.electricViolet, fontSize: 11.5, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ── 9. Expired Event / Ticket Card Component ──────────────────────────────
  Widget _buildExpiredCard(dynamic item) {
    final body = item['body']?.toString() ?? 'Event has ended.';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: false,
      onTap: () => _markAsRead(item),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
            child: const Icon(Icons.history_rounded, color: Color(0xFF94A3B8), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚪ Event Completed', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                const SizedBox(height: 2),
                Text(timeStr, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 10)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _markAsRead(item),
            child: const Text('History', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Generic Card Component ────────────────────────────────────────────────
  Widget _buildGenericCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final title = item['title']?.toString() ?? 'Notification';
    final body = item['body']?.toString() ?? '';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _markAsRead(item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Color(0xFFF3E8FF), shape: BoxShape.circle),
            child: const Icon(Icons.notifications_active_rounded, color: LunaraTheme.electricViolet, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: const Color(0xFF0F172A), fontWeight: isUnread ? FontWeight.w900 : FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(color: Color(0xFF475569), fontSize: 12, height: 1.3)),
                const SizedBox(height: 4),
                Text(timeStr, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
              ],
            ),
          ),
          if (isUnread) ...[
            const SizedBox(width: 8),
            _buildUnreadDot(),
          ],
        ],
      ),
    );
  }

  // ── Base Container & Helpers ───────────────────────────────────────────────
  Widget _buildBaseCardContainer({required bool isUnread, required VoidCallback onTap, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isUnread ? const Color(0xFFFAF5FF) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isUnread
                  ? LunaraTheme.electricViolet.withValues(alpha: 0.3)
                  : const Color(0xFFF1F5F9),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildUnreadDot() {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.redAccent, blurRadius: 4, spreadRadius: 1),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Row(
              children: [
                Container(width: 44, height: 44, decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 140, height: 12, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6))),
                      const SizedBox(height: 8),
                      Container(width: 200, height: 10, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: Color(0xFF94A3B8),
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'All caught up!',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'New requests, matches & bookings will appear here.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
