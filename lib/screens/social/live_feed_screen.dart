// ignore_for_file: use_build_context_synchronously, unused_local_variable
import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import 'party_plan_detail_screen.dart';
import '../profile/lunara_wallet_screen.dart';
import '../../models/strangers_meet_request.dart';
import 'strangers_meet_payment_screen.dart';
import 'strangers_meet_ticket_screen.dart';
import 'chat_screen.dart';
import 'large_party_ticket_screen.dart';
import '../../widgets/top_notification_banner.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Unified Notification Item Schema
/// ─────────────────────────────────────────────────────────────────────────────
class UnifiedNotificationItem {
  final String id;
  final String category; // 'booking', 'party_plan', 'stranger_meet', 'payment', 'wallet', 'chat', 'system', 'promotion', 'cancellation', 'reminder'
  final String title;
  final String body;
  final DateTime createdAt;
  final String timeAgo;
  final bool isRead;
  final String priority; // 'CRITICAL', 'HIGH', 'NORMAL', 'LOW'
  final String? badgeText; // 'NEW', 'ACTION REQUIRED', 'EXPIRES SOON', 'REMINDER', 'COMPLETED'
  final Color accentColor;
  final IconData categoryIcon;
  final String? avatarUrl;
  final String? actionButtonText;
  final VoidCallback? onActionTap;
  final Map<String, dynamic> rawData;

  UnifiedNotificationItem({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.timeAgo,
    this.isRead = false,
    this.priority = 'NORMAL',
    this.badgeText,
    required this.accentColor,
    required this.categoryIcon,
    this.avatarUrl,
    this.actionButtonText,
    this.onActionTap,
    required this.rawData,
  });
}

class LiveFeedScreen extends StatefulWidget {
  final bool isTab;
  final VoidCallback? onCountChanged;
  final int initialTabIndex;

  const LiveFeedScreen({
    super.key,
    this.isTab = false,
    this.onCountChanged,
    this.initialTabIndex = 0,
  });

  @override
  State<LiveFeedScreen> createState() => LiveFeedScreenState();
}

class LiveFeedScreenState extends State<LiveFeedScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;

  List<Map<String, dynamic>> _feedItems = [];
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _largePartyBookings = [];
  bool _isLoading = true;
  Timer? _pollingTimer;

  // Selected Category Filter for Bottom Sheet
  String _selectedCategoryFilter = 'ALL';

  // Selected Status Filter Pills: 'ALL', 'REQUESTS', 'PENDING', 'PAYMENT', 'CONFIRMED', 'SYSTEM'
  String _selectedStatusPill = 'ALL';

  // Razorpay for large party payments
  Razorpay? _razorpay;
  String? _pendingLargePartyBookingId;

  void refreshFeed() {
    _loadFeed(showLoader: false);
    _loadGroupPartyBookings();
  }

  int get totalUnreadCount {
    final allTimelineItems = _buildUnifiedTimeline();
    return allTimelineItems.where((i) => !i.isRead).length;
  }

  Set<String> get _readRequestIds => ApiService.localReadRequestIds;
  Set<String> get _localReadNotificationIds => ApiService.localReadNotificationIds;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _loadFeed();
    _loadGroupPartyBookings();
    _initSocketListeners();

    // Razorpay setup
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onLargePartyPaymentSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onLargePartyPaymentError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _onLargePartyExternalWallet);

    // Fast polling every 15 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadFeed(showLoader: false);
      _loadGroupPartyBookings();
    });
  }

  @override
  void dispose() {
    _disposeSocketListeners();
    _pollingTimer?.cancel();
    _pulseController.dispose();
    _razorpay?.clear();
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
    ApiService.addSocketListener('notification_created', _onNotificationCreated);
    ApiService.addSocketListener('group_party_payment_success', _onGroupPartyUpdated);
    ApiService.addSocketListener('large_party_status_update', _onGroupPartyUpdated);
    ApiService.addSocketListener('group_party_status_update', _onGroupPartyUpdated);
  }

  void _disposeSocketListeners() {
    ApiService.removeSocketListener('party_plan_created', _onPartyPlanCreated);
    ApiService.removeSocketListener('party_plan_deleted', _onPartyPlanDeleted);
    ApiService.removeSocketListener('party_plan_request_accepted', _onPartyPlanRequestAccepted);
    ApiService.removeSocketListener('party_plan_match_success', _onPartyPlanMatchSuccess);
    ApiService.removeSocketListener('party_plan_host_paid', _onPartyPlanHostPaid);
    ApiService.removeSocketListener('party_plan_joiner_paid', _onPartyPlanJoinerPaid);
    ApiService.removeSocketListener('plan_unavailable', _onPlanUnavailable);
    ApiService.removeSocketListener('notification_created', _onNotificationCreated);
    ApiService.removeSocketListener('group_party_payment_success', _onGroupPartyUpdated);
    ApiService.removeSocketListener('large_party_status_update', _onGroupPartyUpdated);
    ApiService.removeSocketListener('group_party_status_update', _onGroupPartyUpdated);
  }

  void _onNotificationCreated(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadFeed(showLoader: false);
    _loadGroupPartyBookings();
    if (data is Map) {
      final notifMap = Map<String, dynamic>.from(data);
      TopNotificationBanner.show(
        title: notifMap['title'] ?? 'New Notification 🔔',
        body: notifMap['body'] ?? '',
        data: notifMap['data'] is Map ? Map<String, dynamic>.from(notifMap['data']) : null,
      );
    }
  }

  void _onGroupPartyUpdated(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadGroupPartyBookings();
    if (data is Map) {
      final notifMap = Map<String, dynamic>.from(data);
      TopNotificationBanner.show(
        title: notifMap['title'] ?? 'Group Party Updated 🎉',
        body: notifMap['body'] ?? notifMap['message'] ?? 'Your group party booking status has been updated.',
        data: notifMap['data'] is Map ? Map<String, dynamic>.from(notifMap['data']) : null,
      );
    }
  }

  void _onPartyPlanCreated(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadFeed(showLoader: false);
  }

  void _onPartyPlanDeleted(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadFeed(showLoader: false);
  }

  void _onPartyPlanRequestAccepted(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadFeed(showLoader: false);
  }

  void _onPartyPlanMatchSuccess(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadFeed(showLoader: false);
  }

  void _onPartyPlanHostPaid(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadFeed(showLoader: false);
  }

  void _onPartyPlanJoinerPaid(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadFeed(showLoader: false);
  }

  void _onPlanUnavailable(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadFeed(showLoader: false);
  }

  Future<void> _loadGroupPartyBookings() async {
    try {
      final list = await ApiService.fetchMyLargePartyBookings();
      if (mounted) {
        setState(() {
          _largePartyBookings = list;
        });
      }
    } catch (e) {
      debugPrint('Error loading group party bookings: $e');
    }
  }

  Future<void> _loadFeed({bool showLoader = true}) async {
    if (showLoader) setState(() => _isLoading = true);
    try {
      await ApiService.loadLocalReadIds();
      final data = await ApiService.fetchLiveFeedData();
      final notifs = await ApiService.fetchNotifications();

      List<Map<String, dynamic>> combined = [
        ...List<Map<String, dynamic>>.from(data['feed'] ?? []),
        ...List<Map<String, dynamic>>.from(data['myRequests'] ?? []),
        ...List<Map<String, dynamic>>.from(data['incomingRequests'] ?? []),
      ];

      if (mounted) {
        setState(() {
          _feedItems = combined;
          _notifications = notifs.map((n) {
            final nId = n['id']?.toString() ?? '';
            if (_localReadNotificationIds.contains(nId)) {
              return {...n, 'read': true, 'isRead': true};
            }
            return n;
          }).toList();
          _isLoading = false;
        });
        widget.onCountChanged?.call();
      }
    } catch (e) {
      debugPrint('Error loading live feed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> markAllNotificationsAsRead() async {
    await ApiService.clearAllNotifications();
    if (mounted) {
      setState(() {
        _notifications = _notifications.map((n) => {...n, 'read': true, 'isRead': true}).toList();
      });
      widget.onCountChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All notifications marked as read ✓'),
          backgroundColor: LunaraTheme.electricViolet,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Large Party Payment Handlers
  // ─────────────────────────────────────────────────────────────────────────────
  void _onLargePartyPaymentSuccess(PaymentSuccessResponse response) async {
    _handleLargePartySuccess(
      paymentId: response.paymentId ?? '',
      orderId: response.orderId ?? '',
      signature: response.signature ?? '',
    );
  }

  void _onLargePartyPaymentError(PaymentFailureResponse response) {
    debugPrint('Large Party Payment Error: ${response.code} - ${response.message}');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment failed: ${response.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onLargePartyExternalWallet(ExternalWalletResponse response) {}

  Future<void> _handleLargePartySuccess({
    required String paymentId,
    required String orderId,
    required String signature,
  }) async {
    final bookingId = _pendingLargePartyBookingId;
    _pendingLargePartyBookingId = null;
    if (bookingId == null) return;

    try {
      final verified = await ApiService.verifyLargePartyPayment(
        bookingId,
        razorpayOrderId: orderId,
        razorpayPaymentId: paymentId,
        razorpaySignature: signature,
      );
      if (!mounted || !context.mounted) return;
      if (verified) {
        await _loadGroupPartyBookings();
        TopNotificationBanner.show(
          title: 'Group Party Confirmed! 🎉',
          body: 'Your payment was verified successfully. Tap to view your ticket!',
          data: {'type': 'group_party_confirmed', 'partyId': bookingId},
        );
      }
    } catch (e) {
      debugPrint('_handleLargePartySuccess error: $e');
    }
  }

  Future<void> _initiateLargePartyPayment(Map<String, dynamic> booking) async {
    final bookingId = booking['id']?.toString() ?? booking['bookingId']?.toString();
    if (bookingId == null) return;

    try {
      final result = await ApiService.initiateLargePartyPayment(bookingId);
      if (result == null || result['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to initiate payment. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final orderData = result['order'] ?? result['data'] ?? result;
      final razorpayKey = result['razorpayKeyId']?.toString() ?? orderData['key']?.toString() ?? '';
      _pendingLargePartyBookingId = bookingId;

      try {
        _razorpay?.open({
          'key': razorpayKey,
          'order_id': orderData['razorpayOrderId']?.toString() ?? orderData['id']?.toString(),
          'amount': orderData['amount'],
          'name': 'Lunara – Group Party',
          'description': 'Group Party at ${booking['venue']?['name'] ?? booking['venueName'] ?? 'venue'}',
          'prefill': {'contact': booking['mobileNumber']?.toString() ?? ''},
          'theme': {'color': '#7C3AED'},
        });
      } catch (e) {
        debugPrint('Error opening Razorpay: $e');
      }
    } catch (e) {
      debugPrint('_initiateLargePartyPayment error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Helper: Format Time Ago
  // ─────────────────────────────────────────────────────────────────────────────
  String _formatTimeAgo(dynamic postedAt) {
    if (postedAt == null) return 'Just now';
    try {
      final parsed = DateTime.parse(postedAt.toString()).toLocal();
      final diff = DateTime.now().difference(parsed);
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
      return 'Just now';
    } catch (_) {
      return 'Just now';
    }
  }

  DateTime _parseDateTime(dynamic raw) {
    if (raw == null) return DateTime.now();
    try {
      return DateTime.parse(raw.toString()).toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Unified Item Builders & Mapping
  // ─────────────────────────────────────────────────────────────────────────────
  List<UnifiedNotificationItem> _buildUnifiedTimeline() {
    final List<UnifiedNotificationItem> items = [];
    final currentUserId = ApiService.currentUserId;

    // 1. Process System / DB Notifications from `_notifications`
    for (final n in _notifications) {
      final id = n['id']?.toString() ?? '';
      final category = (n['category'] ?? n['entityType'] ?? 'system').toString().toLowerCase();
      final title = n['title']?.toString() ?? 'Notification';
      final body = n['body']?.toString() ?? '';
      final isRead = n['read'] == true || n['isRead'] == true || _localReadNotificationIds.contains(id);
      final createdAt = _parseDateTime(n['createdAt']);
      final timeAgo = _formatTimeAgo(n['createdAt']);

      Color accentColor = const Color(0xFF6B7280);
      IconData icon = Icons.notifications_rounded;
      String? badge;
      String? actionText;
      VoidCallback? actionTap;

      if (category.contains('party') || category.contains('plan')) {
        accentColor = const Color(0xFF8B5CF6);
        icon = Icons.celebration_rounded;
        badge = 'PARTY PLAN';
      } else if (category.contains('stranger') || category.contains('meet')) {
        accentColor = const Color(0xFF6366F1);
        icon = Icons.people_alt_rounded;
        badge = 'STRANGER MEET';
      } else if (category.contains('booking') || category.contains('group')) {
        accentColor = const Color(0xFF7C3AED);
        icon = Icons.confirmation_number_rounded;
        badge = 'BOOKING';
      } else if (category.contains('pay') || category.contains('deposit')) {
        accentColor = const Color(0xFF10B981);
        icon = Icons.payments_rounded;
        badge = 'PAYMENT';
        actionText = 'View Wallet';
        actionTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LunaraWalletScreen()));
      } else if (category.contains('wallet') || category.contains('credit')) {
        accentColor = const Color(0xFF3B82F6);
        icon = Icons.account_balance_wallet_rounded;
        badge = 'WALLET';
        actionText = 'Open Wallet';
        actionTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LunaraWalletScreen()));
      } else if (category.contains('chat') || category.contains('message')) {
        accentColor = const Color(0xFFEC4899);
        icon = Icons.chat_bubble_rounded;
        badge = 'CHAT';
      } else if (category.contains('cancel')) {
        accentColor = const Color(0xFFEF4444);
        icon = Icons.cancel_rounded;
        badge = 'CANCELLED';
      } else if (category.contains('promo') || category.contains('offer')) {
        accentColor = const Color(0xFFF59E0B);
        icon = Icons.card_giftcard_rounded;
        badge = 'PROMO';
      }

      items.add(UnifiedNotificationItem(
        id: id,
        category: category,
        title: title,
        body: body,
        createdAt: createdAt,
        timeAgo: timeAgo,
        isRead: isRead,
        badgeText: badge,
        accentColor: accentColor,
        categoryIcon: icon,
        avatarUrl: n['imageUrl']?.toString() ?? n['actor']?['profilePhotoUrl']?.toString(),
        actionButtonText: actionText,
        onActionTap: actionTap,
        rawData: n,
      ));
    }

    // 2. Process Party Plans / Stranger Meets Join Requests from `_feedItems`
    for (final item in _feedItems) {
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;

      final type = item['type']?.toString() ?? '';
      final requestType = item['requestType']?.toString() ?? '';
      final status = (item['status'] ?? 'pending').toString().toLowerCase();
      final createdAt = _parseDateTime(item['createdAt'] ?? item['postedAt']);
      final timeAgo = _formatTimeAgo(item['createdAt'] ?? item['postedAt']);
      final isRead = _readRequestIds.contains(id);

      final user = (item['user'] ?? item['requester'] ?? item['creator'] ?? item['host']) as Map<String, dynamic>? ?? {};
      final venue = (item['venue'] ?? item['venueMap']) as Map<String, dynamic>? ?? {};
      final venueName = venue['name'] ?? item['venueName'] ?? 'Venue';
      final userName = '${user['firstName'] ?? 'User'} ${user['lastName'] ?? ''}'.trim();
      final userPhoto = user['profilePhotoUrl'] ?? user['photoUrl'] ?? user['image'];

      if (requestType == 'stranger_meet' || type == 'stranger_meet') {
        Color accent = const Color(0xFF6366F1);
        String title = '🤝 Stranger Meet Request';
        String body = '$userName requested to join Stranger Meet at $venueName';
        String? actionText;
        VoidCallback? actionTap;
        String badge = 'STRANGER MEET';

        if (status == 'accepted' || status == 'payment_pending') {
          title = '✅ Stranger Meet Accepted!';
          body = 'Your request at $venueName was accepted. Complete payment to confirm!';
          badge = 'ACTION REQUIRED';
          actionText = 'Pay Deposit';
          actionTap = () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StrangersMeetPaymentScreen(
                request: StrangersMeetRequest.fromJson(item),
                onPaymentSuccess: () => _loadFeed(),
                isJoinPayment: status != 'accepted',
              ),
            ),
          );
        } else if (status == 'paid' || status == 'confirmed') {
          title = '🎉 Stranger Meet Confirmed!';
          body = 'Your seat at $venueName is locked and confirmed!';
          badge = 'CONFIRMED';
          actionText = 'View Ticket';
          actionTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => StrangersMeetTicketScreen(request: StrangersMeetRequest.fromJson(item))));
        }

        items.add(UnifiedNotificationItem(
          id: 'sm_$id',
          category: 'stranger_meet',
          title: title,
          body: body,
          createdAt: createdAt,
          timeAgo: timeAgo,
          isRead: isRead,
          badgeText: badge,
          accentColor: accent,
          categoryIcon: Icons.people_alt_rounded,
          avatarUrl: userPhoto,
          actionButtonText: actionText,
          onActionTap: actionTap,
          rawData: item,
        ));
      } else {
        // Party Plan Requests
        Color accent = const Color(0xFF8B5CF6);
        String title = '🎉 Party Plan Update';
        String body = '$userName requested to join Party Plan at $venueName';
        String? actionText;
        VoidCallback? actionTap;
        String badge = 'PARTY PLAN';

        if (status == 'accepted') {
          title = '👤 Request Accepted!';
          body = 'Your Party Plan request at $venueName was accepted by $userName.';
          badge = 'ACTION REQUIRED';
          actionText = 'Pay Deposit';
          actionTap = () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PartyPlanDetailScreen(
                plan: item['plan'] is Map ? item['plan'] as Map<String, dynamic> : item,
              ),
            ),
          );
        } else if (status == 'paid' || status == 'confirmed') {
          title = '🎉 Match Confirmed!';
          body = 'Party booking at $venueName is confirmed! Chat is unlocked.';
          badge = 'CONFIRMED';
          actionText = 'Open Chat';
          final otherId = (item['hostId'] == currentUserId) ? item['requesterId'] : item['hostId'];
          actionTap = () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                user: {
                  'id': otherId ?? user['id'] ?? '',
                  'firstName': user['firstName'] ?? 'Party Partner',
                  'lastName': user['lastName'] ?? '',
                  'profilePhotoUrl': userPhoto,
                },
              ),
            ),
          );
        }

        items.add(UnifiedNotificationItem(
          id: 'pp_$id',
          category: 'party_plan',
          title: title,
          body: body,
          createdAt: createdAt,
          timeAgo: timeAgo,
          isRead: isRead,
          badgeText: badge,
          accentColor: accent,
          categoryIcon: Icons.celebration_rounded,
          avatarUrl: userPhoto,
          actionButtonText: actionText,
          onActionTap: actionTap,
          rawData: item,
        ));
      }
    }

    // 3. Process Large Party / Group Party Bookings from `_largePartyBookings`
    for (final booking in _largePartyBookings) {
      final id = booking['id']?.toString() ?? booking['bookingId']?.toString() ?? '';
      if (id.isEmpty) continue;

      final status = (booking['status'] ?? booking['bookingStatus'] ?? 'pending').toString().toLowerCase();
      final venueName = booking['venueName'] ?? booking['venue']?['name'] ?? 'Group Party Venue';
      final guests = booking['numberOfGuests'] ?? booking['numberOfFriends'] ?? 1;
      final createdAt = _parseDateTime(booking['createdAt'] ?? booking['partyDate']);
      final timeAgo = _formatTimeAgo(booking['createdAt'] ?? booking['partyDate']);

      String title = '👥 Group Party Booking';
      String body = 'Group Party at $venueName ($guests guests)';
      Color accent = const Color(0xFF7C3AED);
      String badge = 'BOOKING';
      String? actionText;
      VoidCallback? actionTap;

      if (status == 'approved' || status == 'awaiting_payment') {
        title = '⚡ Group Party Approved!';
        body = 'Admin approved your Group Party at $venueName. Pay to lock!';
        badge = 'ACTION REQUIRED';
        actionText = 'Pay Now';
        actionTap = () => _initiateLargePartyPayment(booking);
      } else if (status == 'confirmed' || status == 'paid') {
        title = '🎉 Group Party Confirmed!';
        body = 'Booking confirmed for $guests guests at $venueName.';
        badge = 'CONFIRMED';
        actionText = 'View Ticket';
        final venueMap = (booking['venue'] is Map) ? booking['venue'] as Map<dynamic, dynamic> : {'name': venueName};
        actionTap = () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LargePartyTicketScreen(
              booking: booking,
              venue: venueMap,
            ),
          ),
        );
      } else if (status == 'cancelled' || status == 'rejected') {
        title = '❌ Group Party Cancelled';
        body = 'Group Party booking at $venueName was cancelled.';
        accent = const Color(0xFFEF4444);
        badge = 'CANCELLED';
        actionText = 'View Details';
      }

      items.add(UnifiedNotificationItem(
        id: 'gp_$id',
        category: 'booking',
        title: title,
        body: body,
        createdAt: createdAt,
        timeAgo: timeAgo,
        isRead: true,
        badgeText: badge,
        accentColor: accent,
        categoryIcon: Icons.groups_rounded,
        actionButtonText: actionText,
        onActionTap: actionTap,
        rawData: booking,
      ));
    }

    // Sort all timeline items descending by createdAt
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Deduplicate by item ID
    final Set<String> seenIds = {};
    final List<UnifiedNotificationItem> uniqueItems = [];
    for (final item in items) {
      if (!seenIds.contains(item.id)) {
        seenIds.add(item.id);
        uniqueItems.add(item);
      }
    }

    return uniqueItems;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Filter Bottom Sheet
  // ─────────────────────────────────────────────────────────────────────────────
  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final filters = [
          {'id': 'ALL', 'label': 'All Notifications', 'icon': Icons.notifications_rounded},
          {'id': 'BOOKINGS', 'label': 'Bookings & Invites', 'icon': Icons.confirmation_number_rounded},
          {'id': 'PARTY_PLANS', 'label': 'Party Plans', 'icon': Icons.celebration_rounded},
          {'id': 'STRANGER_MEETS', 'label': 'Stranger Meets', 'icon': Icons.people_alt_rounded},
          {'id': 'PAYMENTS', 'label': 'Payments & Receipts', 'icon': Icons.payments_rounded},
          {'id': 'WALLET', 'label': 'Wallet Balance', 'icon': Icons.account_balance_wallet_rounded},
          {'id': 'CHAT', 'label': 'Messages & Chat', 'icon': Icons.chat_bubble_rounded},
          {'id': 'SYSTEM', 'label': 'System & Security', 'icon': Icons.security_rounded},
          {'id': 'PROMOTIONS', 'label': 'Offers & Rewards', 'icon': Icons.card_giftcard_rounded},
        ];

        return StatefulBuilder(
          builder: (ctx, setBottomSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filter Notifications',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        if (_selectedCategoryFilter != 'ALL')
                          TextButton(
                            onPressed: () {
                              setState(() => _selectedCategoryFilter = 'ALL');
                              setBottomSheetState(() {});
                              Navigator.pop(ctx);
                            },
                            child: const Text(
                              'Reset Filter',
                              style: TextStyle(color: LunaraTheme.electricViolet, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filters.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final filter = filters[index];
                          final filterId = filter['id'] as String;
                          final isSelected = _selectedCategoryFilter == filterId;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            leading: Icon(
                              filter['icon'] as IconData,
                              color: isSelected ? LunaraTheme.electricViolet : Colors.grey[600],
                            ),
                            title: Text(
                              filter['label'] as String,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? LunaraTheme.electricViolet : Colors.black87,
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, color: LunaraTheme.electricViolet, size: 20)
                                : null,
                            onTap: () {
                              setState(() {
                                _selectedCategoryFilter = filterId;
                              });
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build Screen Header
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, {int totalUnread = 0}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_active_rounded, color: LunaraTheme.electricViolet, size: 24),
                    if (totalUnread > 0)
                      Positioned(
                        top: -2,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            totalUnread > 9 ? '9+' : '$totalUnread',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'NOTIFICATIONS',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 1.0,
                      color: Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mark all as read button
              TextButton.icon(
                onPressed: markAllNotificationsAsRead,
                icon: const Icon(Icons.done_all_rounded, size: 15, color: LunaraTheme.electricViolet),
                label: const Text(
                  'Read All',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: LunaraTheme.electricViolet,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 4),
              // Filter Bottom Sheet Button
              InkWell(
                onTap: _showFilterBottomSheet,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _selectedCategoryFilter != 'ALL' ? LunaraTheme.electricViolet.withValues(alpha: 0.1) : Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: _selectedCategoryFilter != 'ALL' ? LunaraTheme.electricViolet : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build Status Filter Pills (All, Requests, Pending, Payment, Confirmed, System)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildStatusFilterBar() {
    final pills = [
      {'id': 'ALL', 'label': 'All'},
      {'id': 'REQUESTS', 'label': 'Requests'},
      {'id': 'PENDING', 'label': 'Pending'},
      {'id': 'PAYMENT', 'label': 'Payment'},
      {'id': 'CONFIRMED', 'label': 'Confirmed'},
      {'id': 'SYSTEM', 'label': 'System'},
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: pills.map((pill) {
            final id = pill['id']!;
            final label = pill['label']!;
            final isSelected = _selectedStatusPill == id;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedStatusPill = id;
                    });
                  }
                },
                selectedColor: LunaraTheme.electricViolet,
                backgroundColor: const Color(0xFFF3F4F6),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected ? LunaraTheme.electricViolet : Colors.transparent,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build Main Screen
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final allTimelineItems = _buildUnifiedTimeline();

    // Apply category filter
    final categoryFilteredItems = allTimelineItems.where((item) {
      if (_selectedCategoryFilter == 'ALL') return true;
      if (_selectedCategoryFilter == 'BOOKINGS') {
        return item.category == 'booking' || item.category == 'group';
      }
      if (_selectedCategoryFilter == 'PARTY_PLANS') {
        return item.category == 'party_plan';
      }
      if (_selectedCategoryFilter == 'STRANGER_MEETS') {
        return item.category == 'stranger_meet';
      }
      if (_selectedCategoryFilter == 'PAYMENTS') {
        return item.category == 'payment';
      }
      if (_selectedCategoryFilter == 'WALLET') {
        return item.category == 'wallet';
      }
      if (_selectedCategoryFilter == 'CHAT') {
        return item.category == 'chat';
      }
      if (_selectedCategoryFilter == 'SYSTEM') {
        return item.category == 'system';
      }
      if (_selectedCategoryFilter == 'PROMOTIONS') {
        return item.category == 'promotion';
      }
      return true;
    }).toList();

    // Apply status pill filter (All, Requests, Pending, Payment, Confirmed, System)
    final filteredItems = categoryFilteredItems.where((item) {
      if (_selectedStatusPill == 'ALL') return true;
      final badge = item.badgeText?.toUpperCase() ?? '';
      final category = item.category.toLowerCase();
      final title = item.title.toLowerCase();
      final body = item.body.toLowerCase();
      final rawStatus = (item.rawData['status'] ?? item.rawData['paymentStatus'] ?? '').toString().toLowerCase();

      if (_selectedStatusPill == 'REQUESTS') {
        return title.contains('request') || body.contains('request') || badge.contains('REQUEST') || category.contains('request');
      }
      if (_selectedStatusPill == 'PENDING') {
        return rawStatus.contains('pending') || badge.contains('ACTION REQUIRED') || badge.contains('PENDING');
      }
      if (_selectedStatusPill == 'PAYMENT') {
        return category.contains('pay') || category.contains('wallet') || rawStatus.contains('pay') || badge.contains('PAYMENT') || title.contains('payment') || title.contains('paid');
      }
      if (_selectedStatusPill == 'CONFIRMED') {
        return rawStatus.contains('confirmed') || rawStatus.contains('paid') || badge.contains('CONFIRMED') || title.contains('confirmed');
      }
      if (_selectedStatusPill == 'SYSTEM') {
        return category.contains('system') || category.contains('promo') || badge.contains('SYSTEM') || badge.contains('PROMO');
      }
      return true;
    }).toList();

    // Count total unread items
    final totalUnread = allTimelineItems.where((i) => !i.isRead).length;

    // Date grouping into TODAY, YESTERDAY, EARLIER
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final todayItems = filteredItems.where((i) => i.createdAt.isAfter(todayStart)).toList();
    final yesterdayItems = filteredItems.where((i) => i.createdAt.isAfter(yesterdayStart) && i.createdAt.isBefore(todayStart)).toList();
    final earlierItems = filteredItems.where((i) => i.createdAt.isBefore(yesterdayStart)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, totalUnread: totalUnread),
            _buildStatusFilterBar(),
            Expanded(
              child: _isLoading && filteredItems.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: LunaraTheme.electricViolet))
                  : RefreshIndicator(
                      onRefresh: () async {
                        await _loadFeed();
                        await _loadGroupPartyBookings();
                      },
                      color: LunaraTheme.electricViolet,
                      child: filteredItems.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 100),
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.notifications_none_rounded, size: 64, color: Colors.grey[400]),
                                      const SizedBox(height: 16),
                                      Text(
                                        _selectedCategoryFilter == 'ALL'
                                            ? 'No notifications yet'
                                            : 'No notifications in this category',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Your timeline updates will appear here dynamically',
                                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : ListView(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                if (todayItems.isNotEmpty) ...[
                                  _buildDateSectionHeader('TODAY'),
                                  ...todayItems.map((item) => _buildSmartNotificationCard(item)),
                                ],
                                if (yesterdayItems.isNotEmpty) ...[
                                  _buildDateSectionHeader('YESTERDAY'),
                                  ...yesterdayItems.map((item) => _buildSmartNotificationCard(item)),
                                ],
                                if (earlierItems.isNotEmpty) ...[
                                  _buildDateSectionHeader('EARLIER'),
                                  ...earlierItems.map((item) => _buildSmartNotificationCard(item)),
                                ],
                                const SizedBox(height: 40),
                              ],
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build Date Section Header ("TODAY", "YESTERDAY", "EARLIER")
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildDateSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: LunaraTheme.electricViolet,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: Colors.grey[200])),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build Smart Notification Card
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildSmartNotificationCard(UnifiedNotificationItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: item.isRead ? Colors.white : const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isRead ? Colors.grey[200]! : LunaraTheme.electricViolet.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Accent Bar
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: item.accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            // Card Content Body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Avatar/Icon + Badge + Timestamp
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Avatar or Category Icon
                        if (item.avatarUrl != null && item.avatarUrl!.isNotEmpty)
                          CircleAvatar(
                            radius: 18,
                            backgroundImage: NetworkImage(item.avatarUrl!),
                            backgroundColor: item.accentColor.withValues(alpha: 0.2),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: item.accentColor.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(item.categoryIcon, size: 18, color: item.accentColor),
                          ),
                        const SizedBox(width: 10),

                        // Badge Tag
                        if (item.badgeText != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: item.accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.badgeText!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: item.accentColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        const Spacer(),

                        // Timestamp
                        Text(
                          item.timeAgo,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Title
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Body Description
                    Text(
                      item.body,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Primary Action Button (Single contextual action)
                    if (item.actionButtonText != null && item.onActionTap != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: item.onActionTap,
                          icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                          label: Text(item.actionButtonText!),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: item.accentColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
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
}
