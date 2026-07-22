import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../services/push_notification_service.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../widgets/top_notification_banner.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  int _selectedFilter = 0; // 0: ALL, 1: SOCIAL, 2: BOOKINGS, 3: SYSTEM
  bool _isLoading = true;
  List<dynamic> _notifications = [];

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    ApiService.addSocketListener('notification_created', _onSocketNotification);
  }

  @override
  void dispose() {
    ApiService.removeSocketListener('notification_created', _onSocketNotification);
    super.dispose();
  }

  void _onSocketNotification(dynamic data) {
    if (!mounted || data == null) return;
    final Map<String, dynamic> notifMap = data is Map ? Map<String, dynamic>.from(data) : {};

    // Trigger WhatsApp style top floating banner
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
      });
    }

    final payloadData = item['data'] is Map
        ? Map<String, dynamic>.from(item['data'])
        : (item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{});
    PushNotificationService.navigateFromPayload(payloadData);
  }

  Future<void> _clearAllNotifications() async {
    final currentUid = ApiService.currentUserId ?? '';
    if (currentUid.isEmpty) return;

    try {
      final response = await ApiService.post(
        '/api/mobile/user/notifications/clear-all',
        body: {'userId': currentUid},
      );
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _notifications.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notifications cleared')),
        );
      }
    } catch (e) {
      debugPrint('Error clearing notifications: $e');
    }
  }

  List<dynamic> get _filteredNotifications {
    if (_selectedFilter == 0) return _notifications;

    return _notifications.where((n) {
      final title = (n['title'] ?? '').toString().toLowerCase();
      final type = (n['data']?['type'] ?? n['id'] ?? '').toString().toLowerCase();

      if (_selectedFilter == 1) {
        // SOCIAL
        return title.contains('like') ||
            title.contains('match') ||
            title.contains('super') ||
            title.contains('message') ||
            title.contains('chat') ||
            type.contains('match') ||
            type.contains('chat');
      } else if (_selectedFilter == 2) {
        // BOOKINGS
        return title.contains('booking') ||
            title.contains('party') ||
            title.contains('meet') ||
            title.contains('payment') ||
            title.contains('deposit') ||
            title.contains('payout') ||
            title.contains('settlement') ||
            type.contains('booking') ||
            type.contains('party') ||
            type.contains('meet');
      } else if (_selectedFilter == 3) {
        // SYSTEM
        return title.contains('security') ||
            title.contains('alert') ||
            title.contains('safety') ||
            title.contains('system') ||
            title.contains('verify') ||
            type.contains('safety') ||
            type.contains('system');
      }
      return true;
    }).toList();
  }

  Map<String, List<dynamic>> _groupNotificationsByDate(List<dynamic> items) {
    final Map<String, List<dynamic>> grouped = {
      'TODAY': [],
      'YESTERDAY': [],
      'THIS WEEK': [],
      'EARLIER': [],
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
        grouped['TODAY']!.add(item);
      } else if (itemDate.isAfter(yesterdayStart)) {
        grouped['YESTERDAY']!.add(item);
      } else if (itemDate.isAfter(weekStart)) {
        grouped['THIS WEEK']!.add(item);
      } else {
        grouped['EARLIER']!.add(item);
      }
    }

    return grouped;
  }

  String _formatNotificationTime(String section, dynamic rawDateStr) {
    if (rawDateStr == null) return '';
    DateTime dt = DateTime.now();
    try {
      dt = DateTime.parse(rawDateStr.toString()).toLocal();
    } catch (_) {
      return '';
    }

    if (section == 'TODAY') {
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      return DateFormat('hh:mm a').format(dt);
    } else if (section == 'YESTERDAY') {
      return DateFormat('hh:mm a').format(dt);
    } else if (section == 'THIS WEEK') {
      return DateFormat('EEE, hh:mm a').format(dt);
    } else {
      return DateFormat('MMM dd, hh:mm a').format(dt);
    }
  }

  IconData _getNotificationIcon(dynamic item) {
    final title = (item['title'] ?? '').toString().toLowerCase();
    final type = (item['data']?['type'] ?? item['id'] ?? '').toString().toLowerCase();

    if (title.contains('like') || title.contains('match')) {
      return Icons.favorite_rounded;
    } else if (title.contains('party') || type.contains('party')) {
      return Icons.celebration_rounded;
    } else if (title.contains('meet') || type.contains('meet')) {
      return Icons.groups_rounded;
    } else if (title.contains('payment') || title.contains('paid') || title.contains('deposit')) {
      return Icons.payments_rounded;
    } else if (title.contains('security') || title.contains('alert') || title.contains('safety')) {
      return Icons.verified_user_rounded;
    } else if (title.contains('chat') || title.contains('message')) {
      return Icons.mark_chat_unread_rounded;
    }
    return Icons.notifications_active_rounded;
  }

  Color _getNotificationColor(dynamic item) {
    final title = (item['title'] ?? '').toString().toLowerCase();
    if (title.contains('super')) return const Color(0xFFFFB800);
    if (title.contains('like') || title.contains('match')) return LunaraTheme.hotPink;
    if (title.contains('party') || title.contains('meet')) return LunaraTheme.electricViolet;
    if (title.contains('payment') || title.contains('paid')) return const Color(0xFF16A34A);
    if (title.contains('alert') || title.contains('security')) return const Color(0xFFEF4444);
    return LunaraTheme.cyberCyan;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredNotifications;
    final grouped = _groupNotificationsByDate(filtered);

    return Scaffold(
      backgroundColor: LunaraTheme.midnightBlack,
      appBar: AppBar(
        backgroundColor: LunaraTheme.midnightBlack,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'NOTIFICATIONS',
          style: LunaraTheme.headingStyle.copyWith(
            fontSize: 16,
            letterSpacing: 3,
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          if (_notifications.isNotEmpty)
            TextButton(
              onPressed: _clearAllNotifications,
              child: const Text(
                'CLEAR ALL',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFilters(),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: LunaraTheme.electricViolet,
                      ),
                    )
                  : filtered.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          color: LunaraTheme.electricViolet,
                          onRefresh: _fetchNotifications,
                          child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            children: [
                              for (final section in ['TODAY', 'YESTERDAY', 'THIS WEEK', 'EARLIER'])
                                if (grouped[section] != null && grouped[section]!.isNotEmpty) ...[
                                  _buildSectionHeader(section, grouped[section]!.length),
                                  ...grouped[section]!.map((item) => _buildNotificationTile(section, item)),
                                  const SizedBox(height: 16),
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

  Widget _buildFilters() {
    final filters = ['ALL', 'SOCIAL', 'BOOKINGS', 'SYSTEM'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: filters.asMap().entries.map((entry) {
          bool isSelected = _selectedFilter == entry.key;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = entry.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? LunaraTheme.electricViolet.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? LunaraTheme.electricViolet
                      : Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                  letterSpacing: 1,
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
      padding: const EdgeInsets.only(top: 8, bottom: 12, left: 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationTile(String section, dynamic item) {
    final bool isUnread = !(item['read'] == true);
    final String title = item['title']?.toString() ?? 'Notification';
    final String body = item['body']?.toString() ?? '';
    final String timeStr = _formatNotificationTime(section, item['createdAt'] ?? item['updatedAt']);
    final senderData = item['sender'] is Map ? Map<String, dynamic>.from(item['sender']) : null;
    final iconData = _getNotificationIcon(item);
    final iconColor = _getNotificationColor(item);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _markAsRead(item),
        child: GlassCard(
          padding: const EdgeInsets.all(14),
          borderRadius: BorderRadius.circular(16),
          opacity: isUnread ? 0.12 : 0.04,
          borderColor: isUnread
              ? LunaraTheme.electricViolet.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (senderData != null && senderData.isNotEmpty)
                LunaraProfileImage(
                  userData: senderData,
                  radius: 22,
                  showGradientBorder: true,
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: iconColor.withValues(alpha: 0.3), width: 1),
                  ),
                  child: Icon(iconData, color: iconColor, size: 20),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: isUnread ? FontWeight.w900 : FontWeight.bold,
                              fontSize: 13.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (timeStr.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            timeStr,
                            style: TextStyle(
                              color: isUnread ? LunaraTheme.cyberCyan : Colors.white38,
                              fontSize: 10,
                              fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        color: isUnread ? Colors.white.withValues(alpha: 0.85) : Colors.white54,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) ...[
                const SizedBox(width: 10),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: LunaraTheme.electricViolet,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: LunaraTheme.electricViolet,
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: Colors.white38,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No notifications yet',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'New matches, invitations & bookings will appear here.',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
