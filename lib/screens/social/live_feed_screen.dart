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
import 'party_plan_ticket_screen.dart';
import 'strangers_meet_requests_screen.dart';
import '../../widgets/smart_checkout_sheet.dart';
import '../../widgets/lunara_profile_image.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Unified Notification Item Schema
/// ─────────────────────────────────────────────────────────────────────────────
class NotificationAction {
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final IconData? icon;
  final Color? color;

  NotificationAction({
    required this.label,
    required this.onTap,
    this.isPrimary = true,
    this.icon,
    this.color,
  });
}

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
  final Map<String, dynamic>? senderUser;
  final String? actionButtonText;
  final VoidCallback? onActionTap;
  final List<NotificationAction>? actions;
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
    this.senderUser,
    this.actionButtonText,
    this.onActionTap,
    this.actions,
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
  String? _sessionUserId;

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

  void _onPlanPostedNotify() {
    if (mounted) {
      _loadFeed(showLoader: false);
      _loadGroupPartyBookings();
    }
  }

  void _onProfileUpdateNotify() {
    if (mounted) {
      _loadFeed(showLoader: false);
      _loadGroupPartyBookings();
    }
  }

  @override
  void initState() {
    super.initState();
    _sessionUserId = ApiService.currentUserId;
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

    ApiService.planPostedNotifier.addListener(_onPlanPostedNotify);
    ApiService.profileUpdateNotifier.addListener(_onProfileUpdateNotify);
    ApiService.authSessionNotifier.addListener(_onAuthSessionChanged);
  }

  @override
  void dispose() {
    ApiService.planPostedNotifier.removeListener(_onPlanPostedNotify);
    ApiService.profileUpdateNotifier.removeListener(_onProfileUpdateNotify);
    ApiService.authSessionNotifier.removeListener(_onAuthSessionChanged);
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
    if (data is Map) {
      final notifMap = Map<String, dynamic>.from(data);
      final recipientId = (notifMap['recipientUserId'] ?? notifMap['recipientId'] ?? notifMap['userId'] ?? '').toString();
      final currentUid = ApiService.currentUserId ?? '';
      if (recipientId.isNotEmpty && currentUid.isNotEmpty && recipientId != currentUid) {
        return;
      }
      _loadFeed(showLoader: false);
      _loadGroupPartyBookings();
      TopNotificationBanner.show(
        title: notifMap['title'] ?? 'New Notification 🔔',
        body: notifMap['body'] ?? '',
        data: notifMap['data'] is Map ? Map<String, dynamic>.from(notifMap['data']) : null,
      );
    } else {
      _loadFeed(showLoader: false);
      _loadGroupPartyBookings();
    }
  }

  void _onGroupPartyUpdated(dynamic data) {
    if (!mounted || !context.mounted) return;
    if (data is Map) {
      final notifMap = Map<String, dynamic>.from(data);
      final recipientId = (notifMap['recipientUserId'] ?? notifMap['recipientId'] ?? notifMap['userId'] ?? '').toString();
      final currentUid = ApiService.currentUserId ?? '';
      if (recipientId.isNotEmpty && currentUid.isNotEmpty && recipientId != currentUid) {
        return;
      }
      _loadGroupPartyBookings();
      TopNotificationBanner.show(
        title: notifMap['title'] ?? 'Group Party Updated 🎉',
        body: notifMap['body'] ?? notifMap['message'] ?? 'Your group party booking status has been updated.',
        data: notifMap['data'] is Map ? Map<String, dynamic>.from(notifMap['data']) : null,
      );
    } else {
      _loadGroupPartyBookings();
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
    final requestUserId = _sessionUserId;
    try {
      final list = await ApiService.fetchMyLargePartyBookings();
      if (mounted && requestUserId == ApiService.currentUserId && requestUserId == _sessionUserId) {
        setState(() {
          _largePartyBookings = list;
        });
      }
    } catch (e) {
      debugPrint('Error loading group party bookings: $e');
    }
  }

  Future<void> _loadFeed({bool showLoader = true}) async {
    final requestUserId = _sessionUserId;
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

      if (mounted && requestUserId == ApiService.currentUserId && requestUserId == _sessionUserId) {
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
      if (mounted && requestUserId == _sessionUserId) setState(() => _isLoading = false);
    }
  }

  void _onAuthSessionChanged() {
    if (!mounted) return;
    _sessionUserId = ApiService.currentUserId;
    setState(() {
      _feedItems = [];
      _notifications = [];
      _largePartyBookings = [];
      _isLoading = _sessionUserId != null;
    });
    if (_sessionUserId != null) {
      refreshFeed();
    }
  }

  Future<void> markAllNotificationsAsRead() async {
    final allItems = _buildUnifiedTimeline();
    for (final item in allItems) {
      if (item.badgeText == 'ACTION REQUIRED' || item.badgeText == 'INVITE') {
        continue; // Never mark active action required cards (e.g. Pay Deposit) as read/cleared!
      }
      final rawId = item.rawData['id']?.toString() ?? item.id.replaceAll(RegExp(r'^(gp_|pp_|sm_)'), '');
      if (rawId.isNotEmpty) {
        ApiService.localReadRequestIds.add(rawId);
        ApiService.localReadRequestIds.add(item.id);
      }
    }
    await ApiService.saveLocalReadRequestIds();
    await ApiService.clearAllNotifications();

    if (mounted) {
      setState(() {
        _notifications = _notifications
            .map((n) {
              final String primaryAction = (n['data']?['primaryAction'] ?? n['primaryAction'] ?? '').toString().toLowerCase();
              final String hostStatus = (n['data']?['hostPaymentStatus'] ?? '').toString().toLowerCase();
              if (primaryAction.contains('pay') || (hostStatus.isNotEmpty && hostStatus != 'paid' && hostStatus != 'completed')) {
                return n;
              }
              return {...n, 'read': true, 'isRead': true};
            })
            .toList();
      });
      widget.onCountChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notifications marked as read ✓'),
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
    if (bookingId == null || bookingId.isEmpty) return;

    final venueName = booking['venue']?['name'] ?? booking['venueName'] ?? 'Venue';
    final rawAmount = booking['totalAmount'] ?? booking['amount'] ?? booking['price'] ?? 1999.0;
    final double amount = (rawAmount is num) ? rawAmount.toDouble() : (double.tryParse(rawAmount.toString()) ?? 1999.0);

    SmartCheckoutSheet.show(
      context: context,
      title: 'Group Party Booking',
      subtitle: 'Deposit payment for Group Party at $venueName',
      itemPrice: amount,
      onWalletPayment: () async {
        final res = await ApiService.payWithWallet(
          amount: amount,
          bookingId: bookingId,
          paymentType: 'group_party',
        );
        if (res != null && res['success'] == true) {
          final transactionId = res['data']?['transactionId']?.toString() ?? 'wallet';
          final confirmRes = await ApiService.verifyLargePartyPayment(
            bookingId,
            razorpayOrderId: 'order_mock_wallet',
            razorpayPaymentId: 'wallet_$transactionId',
            razorpaySignature: 'mock_signature',
          );
          if (confirmRes && mounted) {
            await _loadGroupPartyBookings();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 Group Party Paid via Smart Credit Wallet!'),
                backgroundColor: Colors.green,
              ),
            );
            return true;
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res?['message'] ?? 'Wallet payment failed'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return false;
      },
      onDirectPayment: () async {
        _pendingLargePartyBookingId = bookingId;
        final result = await ApiService.initiateLargePartyPayment(bookingId);
        if (result != null && result['success'] == true) {
          final orderData = result['order'] ?? result['data'] ?? result;
          final razorpayKey = result['razorpayKeyId']?.toString() ?? orderData['key']?.toString() ?? '';
          final orderId = orderData['razorpayOrderId']?.toString() ?? orderData['id']?.toString() ?? '';
          
          if (orderId.startsWith('order_mock_')) {
            final success = await ApiService.verifyLargePartyPayment(
              bookingId,
              razorpayOrderId: orderId,
              razorpayPaymentId: 'mock_payment',
              razorpaySignature: 'mock_signature',
            );
            if (success && mounted) {
              await _loadGroupPartyBookings();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🎉 Group Party Paid successfully!'), backgroundColor: Colors.green));
            }
            return;
          }

          _razorpay?.open({
            'key': razorpayKey,
            'order_id': orderId,
            'amount': orderData['amount'],
            'name': 'Lunara – Group Party',
            'description': 'Group Party at $venueName',
            'prefill': {'contact': booking['mobileNumber']?.toString() ?? ''},
            'theme': {'color': '#7C3AED'},
          });
        }
      },
      onHybridPayment: (shortfall) async {
        _pendingLargePartyBookingId = bookingId;
        final result = await ApiService.initiateLargePartyPayment(bookingId);
        if (result != null && result['success'] == true) {
          final orderData = result['order'] ?? result['data'] ?? result;
          final razorpayKey = result['razorpayKeyId']?.toString() ?? orderData['key']?.toString() ?? '';
          _razorpay?.open({
            'key': razorpayKey,
            'order_id': orderData['razorpayOrderId']?.toString() ?? orderData['id']?.toString(),
            'amount': (shortfall * 100).toInt(),
            'name': 'Lunara – Group Party Shortfall',
            'description': 'Group Party Shortfall at $venueName',
            'prefill': {'contact': booking['mobileNumber']?.toString() ?? ''},
            'theme': {'color': '#7C3AED'},
          });
        }
      },
    );
  }

  Future<void> _handleAcceptPartyPlan(String reqId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
      ),
    );
    try {
      final res = await ApiService.acceptPartyPlanRequest(reqId);
      Navigator.pop(context);
      if (res != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request accepted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadFeed();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to accept request.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      debugPrint('Error accepting request: $e');
    }
  }

  Future<void> _handleRejectPartyPlan(String reqId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
      ),
    );
    try {
      final success = await ApiService.rejectPartyPlanRequest(reqId);
      Navigator.pop(context);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request cancelled / declined.'),
            backgroundColor: Colors.grey,
          ),
        );
        _loadFeed();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update request.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      debugPrint('Error rejecting request: $e');
    }
  }

  /// Accept a private invite sent by the host (calls accept-invite endpoint)
  Future<void> _handleAcceptPartyPlanInvite(String reqId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
      ),
    );
    try {
      final res = await ApiService.acceptPartyPlanInvite(reqId);
      Navigator.pop(context);
      if (res != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invite accepted! Proceed to pay deposit.'),
            backgroundColor: Colors.green,
          ),
        );
        _loadFeed();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to accept invite. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      debugPrint('Error accepting invite: $e');
    }
  }

  Future<void> _handleStrangersMeetJoinAction(String meetId, String joinerId, String action) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
      ),
    );
    try {
      final success = await ApiService.handleStrangersMeetJoinRequest(meetId, joinerId, action);
      Navigator.pop(context);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action == 'accept' ? 'Join request accepted!' : 'Join request declined.'),
            backgroundColor: action == 'accept' ? Colors.green : Colors.grey,
          ),
        );
        _loadFeed();
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _markItemAsRead(UnifiedNotificationItem item) {
    final rawId = item.rawData['id']?.toString() ?? item.id.replaceAll(RegExp(r'^(gp_|pp_|sm_)'), '');
    if (rawId.isNotEmpty) {
      ApiService.localReadRequestIds.add(rawId);
      ApiService.localReadRequestIds.add(item.id);
      ApiService.saveLocalReadRequestIds();
    }
    final notifId = item.rawData['id']?.toString();
    if (notifId != null && notifId.isNotEmpty) {
      ApiService.patch('/api/mobile/user/notifications/$notifId/read', body: {});
    }
    if (mounted) {
      setState(() {});
      widget.onCountChanged?.call();
    }
  }

  void _onCardTap(UnifiedNotificationItem item) {
    _markItemAsRead(item);
    final status = (item.rawData['status'] ?? item.rawData['paymentStatus'] ?? '').toString().toLowerCase();
    final category = item.category.toLowerCase();

    if (category.contains('stranger') || category.contains('meet')) {
      try {
        final req = StrangersMeetRequest.fromJson(item.rawData['plan'] ?? item.rawData);
        if (status == 'accepted' || status == 'payment_pending') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StrangersMeetPaymentScreen(
                request: req,
                onPaymentSuccess: () => _loadFeed(),
                isJoinPayment: status != 'accepted',
              ),
            ),
          );
        } else if (status == 'paid' || status == 'confirmed') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StrangersMeetTicketScreen(request: req),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const StrangersMeetRequestsScreen(),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error parsing strangers meet on tap: $e');
      }
    } else if (category.contains('booking') || category.contains('group')) {
      final bookingData = item.rawData['booking'] ?? item.rawData;
      final venueMap = (bookingData['venue'] is Map) ? bookingData['venue'] as Map<dynamic, dynamic> : {'name': bookingData['venueName'] ?? 'Venue'};
      if (status == 'confirmed' || status == 'paid') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LargePartyTicketScreen(
              booking: bookingData,
              venue: venueMap,
            ),
          ),
        );
      }
    } else if (category.contains('party') || category.contains('plan')) {
      final planData = item.rawData['plan'] is Map ? item.rawData['plan'] : item.rawData;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PartyPlanDetailScreen(
            plan: Map<String, dynamic>.from(planData),
          ),
        ),
      );
    } else if (category.contains('pay') || category.contains('wallet')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LunaraWalletScreen()),
      );
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

    // Build set of entity IDs already represented in feedItems so that we can
    // skip redundant server-side push notifications for the same plan/meet.
    final Set<String> feedEntityIds = <String>{};
    for (final fi in _feedItems) {
      final reqId = fi['id']?.toString();
      if (reqId != null && reqId.isNotEmpty) feedEntityIds.add(reqId);
      final plan = fi['plan'];
      final pId = plan is Map ? plan['id']?.toString() : fi['planId']?.toString();
      if (pId != null && pId.isNotEmpty) feedEntityIds.add(pId);
    }

    // 1. Process System / DB Notifications from `_notifications`
    for (final n in _notifications) {
      final id = n['id']?.toString() ?? '';
      final category = (n['category'] ?? n['entityType'] ?? 'system').toString().toLowerCase();
      final title = n['title']?.toString() ?? 'Notification';
      final body = n['body']?.toString() ?? '';
      final isRead = n['read'] == true || n['isRead'] == true || _localReadNotificationIds.contains(id);
      final createdAt = _parseDateTime(n['createdAt']);
      final timeAgo = _formatTimeAgo(n['createdAt']);

      // ── MANDATORY DISPATCH LOGIC FOR HOST PARTY PLAN DEPOSIT ───────────────
      final Map<String, dynamic> notifData = n['data'] is Map
          ? Map<String, dynamic>.from(n['data'])
          : (n['metadata'] is Map
              ? Map<String, dynamic>.from(n['metadata'])
              : <String, dynamic>{});

      final String notifType = (
        n['type'] ??
        n['eventType'] ??
        notifData['type'] ??
        ''
      ).toString().trim().toLowerCase();

      final String notifBody = body.trim().toLowerCase();

      final String notifPrimaryAction = (
        notifData['primaryAction'] ??
        n['primaryAction'] ??
        ''
      ).toString().trim().toLowerCase();

      final String notifHostStatus = (
        notifData['hostPaymentStatus'] ??
        n['hostPaymentStatus'] ??
        ''
      ).toString().trim().toLowerCase();

      final String notifPartyPlanId =
          notifData['partyPlanId']?.toString().trim() ?? '';

      final bool isHostDepositRequired =
          notifPartyPlanId.isNotEmpty &&
          (
            notifType == 'party_plan_timeline' ||
            notifType.contains('party_plan_timeline')
          ) &&
          (
            notifPrimaryAction == 'pay deposit' ||
            notifBody.contains('action required: pay deposit') ||
            notifBody.contains('pay deposit')
          ) &&
          notifHostStatus != 'paid' &&
          notifHostStatus != 'completed';

      if (isHostDepositRequired) {
        debugPrint('### HOST PARTY PLAN DEPOSIT ROUTE ###');
        debugPrint('partyPlanId=$notifPartyPlanId');
        debugPrint('primaryAction=$notifPrimaryAction');
        debugPrint('hostPaymentStatus=$notifHostStatus');

        double depositAmount = 99.0;
        final rawAmount = notifData['depositAmount'];
        if (rawAmount is num) {
          depositAmount = rawAmount.toDouble();
        } else if (rawAmount is String) {
          depositAmount = double.tryParse(rawAmount.trim()) ?? 99.0;
        }

        final venueName = notifData['venueName']?.toString().trim() ?? 'Venue';

        final actionsList = [
          NotificationAction(
            label: 'Pay Deposit (${depositAmount.toStringAsFixed(0)})',
            icon: Icons.payment_rounded,
            isPrimary: true,
            onTap: () async {
              final hostRazorpayOrderId = notifData['hostRazorpayOrderId']?.toString().trim() ?? '';
              await _startHostRazorpayDirectPaymentInLiveFeed(
                partyPlanId: notifPartyPlanId,
                venueName: venueName,
                orderId: hostRazorpayOrderId,
                depositAmount: depositAmount,
                onSuccess: () async {
                  _loadFeed();
                },
              );
            },
          ),
          NotificationAction(
            label: 'View Plan',
            icon: Icons.open_in_new_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PartyPlanDetailScreen(
                    plan: {'id': notifPartyPlanId, ...notifData},
                  ),
                ),
              );
            },
          ),
        ];

        items.add(UnifiedNotificationItem(
          id: 'pp_host_deposit_$notifPartyPlanId',
          category: 'party_plan',
          title: title,
          body: body,
          createdAt: createdAt,
          timeAgo: timeAgo,
          isRead: isRead,
          badgeText: 'PARTY PLAN',
          accentColor: const Color(0xFF8B5CF6),
          categoryIcon: Icons.celebration_rounded,
          avatarUrl: n['imageUrl']?.toString() ?? n['actor']?['profilePhotoUrl']?.toString(),
          actions: actionsList,
          rawData: n,
        ));
        continue;
      }

      Color accentColor = const Color(0xFF6B7280);
      IconData icon = Icons.notifications_rounded;
      String? badge;
      String? actionText;
      VoidCallback? actionTap;

      if (category.contains('stranger') || category.contains('meet')) {
        // Skip push-notifications that are already shown as live feed items
        // (avoids duplicate cards).
        final notifEntityId = n['entityId']?.toString() ?? '';
        if (feedEntityIds.isNotEmpty && notifEntityId.isNotEmpty &&
            feedEntityIds.contains(notifEntityId)) {
          continue;
        }
        accentColor = const Color(0xFF6366F1);
        icon = Icons.people_alt_rounded;
        badge = 'STRANGER MEET';
      } else if (category.contains('booking') || category.contains('group')) {
        accentColor = const Color(0xFF7C3AED);
        icon = Icons.confirmation_number_rounded;
        badge = 'BOOKING';
      } else if (category.contains('party') || category.contains('plan') || category.contains('events')) {
        // Skip push-notifications that are already shown as live feed items
        final notifEntityId = n['entityId']?.toString() ?? '';
        if (feedEntityIds.isNotEmpty && notifEntityId.isNotEmpty &&
            feedEntityIds.contains(notifEntityId)) {
          continue;
        }
        accentColor = const Color(0xFF8B5CF6);
        icon = Icons.celebration_rounded;
        badge = 'PARTY PLAN';
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

      bool isExpired = false;
      final planData = n['plan'] is Map ? n['plan'] : n;
      final rawDateTime = planData['planDateTime'] ?? planData['eventDateTime'] ?? planData['planDate'] ?? planData['partyDate'] ?? planData['bookingDate'] ?? n['entityDetails']?['planDateTime'] ?? n['entityDetails']?['eventDateTime'];
      if (rawDateTime != null) {
        try {
          final planTime = DateTime.parse(rawDateTime.toString()).toLocal();
          if (planTime.isBefore(DateTime.now())) {
            isExpired = true;
          }
        } catch (_) {}
      }

      List<NotificationAction>? actionsList;

      if (isExpired) {
        accentColor = const Color(0xFF9CA3AF);
        badge = 'EXPIRED';
      } else {
        final titleLower = title.toLowerCase();
        final bodyLower = body.toLowerCase();
        final entityId = n['entityId']?.toString() ?? '';

        if (entityId.isNotEmpty) {
          if (category.contains('stranger') || category.contains('meet')) {
            if (titleLower.contains('request') || bodyLower.contains('request')) {
              final match = _feedItems.firstWhere(
                (item) => item['type'] == 'incoming_request' && 
                          item['requestType'] == 'stranger_meet' &&
                          item['planId']?.toString() == entityId &&
                          item['status']?.toString().toLowerCase() == 'pending',
                orElse: () => {},
              );
              if (match.isNotEmpty) {
                final joinerId = match['id'].toString();
                actionsList = [
                  NotificationAction(
                    label: 'Accept',
                    icon: Icons.check_circle_rounded,
                    isPrimary: true,
                    onTap: () => _handleStrangersMeetJoinAction(entityId, joinerId, 'accept'),
                  ),
                  NotificationAction(
                    label: 'Decline',
                    icon: Icons.cancel_rounded,
                    isPrimary: false,
                    color: Colors.grey[200],
                    onTap: () => _handleStrangersMeetJoinAction(entityId, joinerId, 'reject'),
                  ),
                ];
              }
            } else if (titleLower.contains('accepted') || bodyLower.contains('accepted')) {
              actionsList = [
                NotificationAction(
                  label: 'Pay Deposit',
                  icon: Icons.payment_rounded,
                  isPrimary: true,
                  onTap: () {
                    try {
                      final req = StrangersMeetRequest.fromJson(n['plan'] ?? n);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StrangersMeetPaymentScreen(
                            request: req,
                            onPaymentSuccess: () => _loadFeed(),
                            isJoinPayment: true,
                          ),
                        ),
                      );
                    } catch (e) {
                      debugPrint('Error parsing strangers meet payment: $e');
                    }
                  },
                ),
              ];
            } else if (titleLower.contains('confirmed') || bodyLower.contains('confirmed')) {
              actionsList = [
                NotificationAction(
                  label: 'View Ticket',
                  icon: Icons.confirmation_number_rounded,
                  isPrimary: true,
                  onTap: () {
                    try {
                      final req = StrangersMeetRequest.fromJson(n['plan'] ?? n);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StrangersMeetTicketScreen(request: req),
                        ),
                      );
                    } catch (e) {
                      debugPrint('Error parsing strangers meet ticket: $e');
                    }
                  },
                ),
                NotificationAction(
                  label: 'Chat',
                  icon: Icons.chat_bubble_rounded,
                  isPrimary: false,
                  color: Colors.grey[200],
                  onTap: () {
                    final host = n['actor'] ?? {};
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          user: {
                            'id': host['id'] ?? '',
                            'firstName': host['firstName'] ?? 'Host',
                            'lastName': host['lastName'] ?? '',
                            'profilePhotoUrl': host['profilePhotoUrl'] ?? host['photoUrl'] ?? host['image'],
                          },
                        ),
                      ),
                    );
                  },
                ),
              ];
            }
          } else if (category.contains('party') || category.contains('plan')) {
            if (titleLower.contains('request') || bodyLower.contains('request')) {
              actionsList = [
                NotificationAction(
                  label: 'Accept',
                  icon: Icons.check_circle_rounded,
                  isPrimary: true,
                  onTap: () => _handleAcceptPartyPlan(entityId),
                ),
                NotificationAction(
                  label: 'Decline',
                  icon: Icons.cancel_rounded,
                  isPrimary: false,
                  color: Colors.grey[200],
                  onTap: () => _handleRejectPartyPlan(entityId),
                ),
              ];
            } else if (titleLower.contains('accepted') || bodyLower.contains('accepted')) {
              actionsList = [
                NotificationAction(
                  label: 'Pay Deposit',
                  icon: Icons.payment_rounded,
                  isPrimary: true,
                  onTap: () {
                    final planData = n['plan'] is Map ? n['plan'] : n;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PartyPlanDetailScreen(
                          plan: Map<String, dynamic>.from(planData),
                        ),
                      ),
                    );
                  },
                ),
              ];
            } else if (titleLower.contains('confirmed') || bodyLower.contains('confirmed')) {
              final otherId = n['actor']?['id']?.toString() ?? n['actorId']?.toString();
              actionsList = [
                NotificationAction(
                  label: 'Chat',
                  icon: Icons.chat_bubble_rounded,
                  isPrimary: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          user: {
                            'id': otherId ?? '',
                            'firstName': n['actor']?['firstName'] ?? 'Partner',
                            'lastName': n['actor']?['lastName'] ?? '',
                            'profilePhotoUrl': n['imageUrl']?.toString() ?? n['actor']?['profilePhotoUrl']?.toString(),
                          },
                        ),
                      ),
                    );
                  },
                ),
                NotificationAction(
                  label: 'View Ticket',
                  icon: Icons.confirmation_number_rounded,
                  isPrimary: false,
                  color: Colors.grey[200],
                  onTap: () {
                    final planData = n['plan'] is Map ? n['plan'] : n;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PartyPlanTicketScreen(
                          request: n,
                          plan: Map<String, dynamic>.from(planData),
                          isHost: currentUserId == (planData['userId'] ?? planData['creator']?['id']),
                        ),
                      ),
                    );
                  },
                ),
              ];
            }
          }
        }

        if (actionsList == null && actionText != null && actionTap != null) {
          actionsList = [
            NotificationAction(
              label: actionText,
              onTap: actionTap,
              isPrimary: true,
              icon: Icons.arrow_forward_rounded,
            ),
          ];
        }
      }

      final actorMap = n['actor'] is Map
          ? Map<String, dynamic>.from(n['actor'])
          : (n['sender'] is Map ? Map<String, dynamic>.from(n['sender']) : null);

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
        avatarUrl: n['imageUrl']?.toString() ?? actorMap?['profilePhotoUrl']?.toString() ?? actorMap?['profileImageUrl']?.toString(),
        senderUser: actorMap,
        actionButtonText: actionText,
        onActionTap: actionTap,
        actions: actionsList,
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
      // profileImageUrl is the key the backend sends; also check photoUrl and image as fallbacks
      final userPhoto = (user['profileImageUrl']?.toString().isNotEmpty == true ? user['profileImageUrl'] : null)
          ?? (user['profilePhotoUrl']?.toString().isNotEmpty == true ? user['profilePhotoUrl'] : null)
          ?? (user['photoUrl']?.toString().isNotEmpty == true ? user['photoUrl'] : null)
          ?? user['image'];

      bool isExpired = false;
      final planMap = item['plan'] is Map ? item['plan'] as Map<String, dynamic> : <String, dynamic>{};
      final planData = planMap.isNotEmpty ? planMap : item;
      final rawDateTime = planData['planDateTime'] ?? planData['eventDateTime'] ?? planData['planDate'] ?? planData['partyDate'] ?? planData['bookingDate'];
      if (rawDateTime != null) {
        try {
          final planTime = DateTime.parse(rawDateTime.toString()).toLocal();
          if (planTime.isBefore(DateTime.now())) {
            isExpired = true;
          }
        } catch (_) {}
      }

      List<NotificationAction>? actionsList;
      final bool isMyCreatedPartyPlan = (item['userId']?.toString() == currentUserId) ||
          (planMap['userId']?.toString() == currentUserId) ||
          (planData['userId']?.toString() == currentUserId) ||
          (item['type'] == 'party_plan' && item['creator']?['id']?.toString() == currentUserId);

      final bool isStranger = requestType.toLowerCase().contains('stranger') ||
          type.toLowerCase().contains('stranger') ||
          item['strangersMeetId'] != null ||
          (item['plan'] is Map && item['plan']['strangersMeetId'] != null);

      Color accent = isStranger
          ? const Color(0xFF6366F1)
          : const Color(0xFF8B5CF6);
      String title = isStranger
          ? '🤝 Stranger Meet'
          : (isMyCreatedPartyPlan ? '🎉 Your Party Plan' : '🎉 Party Plan');
      String body = isStranger
          ? '$userName requested to join Stranger Meet at $venueName'
          : (isMyCreatedPartyPlan
              ? 'Your Party Plan at $venueName is active!'
              : 'Party Plan at $venueName');
      String badge = isStranger
          ? 'STRANGER MEET'
          : 'PARTY PLAN';

      // Declare at loop scope so item builder can access for declined card avatars
      Map<String, dynamic> hostCreator = <String, dynamic>{};
      String? hostPhoto;

      if (isExpired) {
        accent = const Color(0xFF9CA3AF);
        badge = 'EXPIRED';
      } else {
        if (isStranger) {
          if (type == 'incoming_request') {
            if (status == 'pending') {
              title = '📥 Join Request Received';
              body = '$userName requested to join your Stranger Meet at $venueName';
              actionsList = [
                NotificationAction(
                  label: 'Accept',
                  icon: Icons.check_circle_rounded,
                  isPrimary: true,
                  onTap: () => _handleStrangersMeetJoinAction(item['planId'].toString(), item['id'].toString(), 'accept'),
                ),
                NotificationAction(
                  label: 'Decline',
                  icon: Icons.cancel_rounded,
                  isPrimary: false,
                  color: Colors.grey[200],
                  onTap: () => _handleStrangersMeetJoinAction(item['planId'].toString(), item['id'].toString(), 'reject'),
                ),
              ];
            } else if (status == 'accepted' || status == 'payment_pending') {
              title = '⏳ Approved (Awaiting Payment)';
              body = 'You approved $userName to join Stranger Meet at $venueName. Awaiting payment to unlock chat.';
              actionsList = [];
            } else if (status == 'paid' || status == 'confirmed') {
              title = '🎉 Seat Confirmed';
              body = '$userName\'s safety deposit is paid! Seat is confirmed.';
              badge = 'CONFIRMED';
              actionsList = [
                NotificationAction(
                  label: 'Chat',
                  icon: Icons.chat_bubble_rounded,
                  isPrimary: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          user: {
                            'id': user['id'] ?? '',
                            'firstName': user['firstName'] ?? 'Partner',
                            'lastName': user['lastName'] ?? '',
                            'profilePhotoUrl': userPhoto,
                          },
                        ),
                      ),
                    );
                  },
                ),
                NotificationAction(
                  label: 'View Ticket',
                  icon: Icons.confirmation_number_rounded,
                  isPrimary: false,
                  color: Colors.grey[200],
                  onTap: () {
                    try {
                      // Use planDetails which carries the actual SM request ID
                      final smData = item['planDetails'] is Map
                          ? (item['planDetails'] as Map<String, dynamic>)
                          : item;
                      final req = StrangersMeetRequest.fromJson(smData);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => StrangersMeetTicketScreen(request: req)));
                    } catch (e) {
                      debugPrint('Error parsing strangers meet ticket: $e');
                    }
                  },
                ),
              ];
            }
          } else {
            // My outgoing request or my own created meetup
            final bool isHostOfMeet = requestType == 'stranger_meet';
            if (isHostOfMeet) {
              final paymentStatus = (item['paymentStatus'] ?? '').toString().toLowerCase();
              // HOST'S OWN Created meetup request status
              if (paymentStatus == 'paid' || status == 'paid' || status == 'confirmed') {
                title = '🎉 Stranger Meet Confirmed & LIVE!';
                body = 'Your Stranger Meet "${item['subject'] ?? ''}" at $venueName is live on the feed!';
                badge = 'LIVE & CONFIRMED';
                accent = const Color(0xFF10B981);
                actionsList = [
                  NotificationAction(
                    label: 'View Ticket',
                    icon: Icons.confirmation_number_rounded,
                    isPrimary: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StrangersMeetTicketScreen(
                          request: StrangersMeetRequest.fromJson(item),
                        ),
                      ),
                    ),
                  ),
                  NotificationAction(
                    label: 'View Requests',
                    icon: Icons.people_outline_rounded,
                    isPrimary: false,
                    color: Colors.grey[200],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StrangersMeetRequestsScreen(),
                      ),
                    ),
                  ),
                ];
              } else if (status == 'approved' || status == 'active') {
                title = '🎉 Stranger Meet Approved!';
                body = 'Your meet request "${item['subject'] ?? ''}" at $venueName has been approved. Complete payment to publish it!';
                badge = 'ACTION REQUIRED';
                actionsList = [
                  NotificationAction(
                    label: 'Pay Deposit',
                    icon: Icons.payment_rounded,
                    isPrimary: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StrangersMeetPaymentScreen(
                          request: StrangersMeetRequest.fromJson(item),
                          onPaymentSuccess: () => _loadFeed(),
                          isJoinPayment: false, // Host payment
                        ),
                      ),
                    ),
                  ),
                ];
              } else if (status == 'pending') {
                title = '⏳ Stranger Meet Awaiting Approval';
                body = 'Your meet request "${item['subject'] ?? ''}" at $venueName has been submitted. Awaiting admin approval.';
                badge = 'PENDING';
              }
            } else {
              // ─── JOINER: My request to join someone else's Stranger Meet ─────
              // For stranger_meet_join items, venue and host-user info live inside
              // item['plan'] (not at the top level). Extract them here.
              final smPlan = item['plan'] is Map
                  ? (item['plan'] as Map<String, dynamic>)
                  : <String, dynamic>{};
              final smVenueMap = smPlan['venue'] is Map
                  ? (smPlan['venue'] as Map<String, dynamic>)
                  : venue;
              final smVenueName = smVenueMap['name']?.toString().isNotEmpty == true
                  ? smVenueMap['name'].toString()
                  : venueName;
              final smHost = smPlan['user'] is Map
                  ? (smPlan['user'] as Map<String, dynamic>)
                  : user;
              final smHostPhoto =
                  smHost['profileImageUrl'] ?? smHost['profilePhotoUrl'] ?? userPhoto;

              // Check actual joiner payment status FIRST.
              // After payment, backend keeps status='accepted' but paymentStatus='paid'.
              final joinerPayStatus =
                  (item['joinerPaymentStatus'] ?? '').toString().toLowerCase();

              if (joinerPayStatus == 'paid') {
                // ── Payment done – show confirmed state ──────────────────────
                title = '🎉 You\'re In! Meet Confirmed';
                body = 'Payment done! Your seat at $smVenueName is locked. Enjoy the meet! 🥂';
                badge = 'CONFIRMED';
                accent = const Color(0xFF10B981);
                actionsList = [
                  NotificationAction(
                    label: 'Chat Host',
                    icon: Icons.chat_bubble_rounded,
                    isPrimary: false,
                    color: Colors.grey[200],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          user: {
                            'id': smHost['id'] ?? '',
                            'firstName': smHost['firstName'] ?? 'Host',
                            'lastName': smHost['lastName'] ?? '',
                            'profilePhotoUrl': smHostPhoto,
                          },
                        ),
                      ),
                    ),
                  ),
                  NotificationAction(
                    label: 'View Ticket',
                    icon: Icons.confirmation_number_rounded,
                    isPrimary: true,
                    onTap: () {
                      try {
                        final req = StrangersMeetRequest.fromJson(
                          smPlan.isNotEmpty ? smPlan : item,
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StrangersMeetTicketScreen(request: req),
                          ),
                        );
                      } catch (e) {
                        debugPrint('Error parsing SM ticket (joiner paid): $e');
                      }
                    },
                  ),
                ];
              } else if (status == 'pending') {
                // ── Pending host approval ────────────────────────────────────
                title = '🤝 Request Sent';
                body = 'Awaiting host approval for Stranger Meet at $smVenueName.';
                badge = 'PENDING';
                // No action button – nothing to do until host responds
              } else if (status == 'accepted' || status == 'payment_pending') {
                // ── Accepted – needs join payment ────────────────────────────
                title = '✅ Accepted! Pay to Confirm';
                body = 'Your request to join the meet at $smVenueName was accepted! '
                    'Pay the deposit to secure your spot.';
                badge = 'ACTION REQUIRED';
                accent = const Color(0xFFF59E0B);
                actionsList = [
                  NotificationAction(
                    label: 'Pay Deposit',
                    icon: Icons.payment_rounded,
                    isPrimary: true,
                    onTap: () {
                      try {
                        // IMPORTANT: use smPlan (item['plan']) for the correct
                        // StrangersMeetRequest ID. item['id'] is the joiner-record
                        // ID, which is NOT the SM request ID the backend expects.
                        final req = StrangersMeetRequest.fromJson(
                          smPlan.isNotEmpty ? smPlan : item,
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StrangersMeetPaymentScreen(
                              request: req,
                              onPaymentSuccess: () => _loadFeed(),
                              isJoinPayment: true,
                            ),
                          ),
                        );
                      } catch (e) {
                        debugPrint('Error parsing SM payment (joiner): $e');
                      }
                    },
                  ),
                ];
              } else if (status == 'rejected') {
                // ── Rejected by host ─────────────────────────────────────────
                title = '❌ Request Declined';
                body = 'Your request to join Stranger Meet at $smVenueName was declined by the host.';
                badge = 'DECLINED';
                accent = const Color(0xFF9CA3AF);
                // No action button
              } else if (status == 'paid' || status == 'confirmed') {
                // ── Paid / Confirmed (status-level fallback) ─────────────────
                title = '🎉 Stranger Meet Confirmed!';
                body = 'Your seat at $smVenueName is locked and confirmed!';
                badge = 'CONFIRMED';
                accent = const Color(0xFF10B981);
                actionsList = [
                  NotificationAction(
                    label: 'View Ticket',
                    icon: Icons.confirmation_number_rounded,
                    isPrimary: true,
                    onTap: () {
                      try {
                        final req = StrangersMeetRequest.fromJson(
                          smPlan.isNotEmpty ? smPlan : item,
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StrangersMeetTicketScreen(request: req),
                          ),
                        );
                      } catch (e) {
                        debugPrint('Error parsing SM ticket (joiner confirmed): $e');
                      }
                    },
                  ),
                ];
              }
            }
          }
        } else {
          // ─── Party Plan Requests ─────────────────────────────────────────────
          //
          // Detect whether this `my_request` is actually a private invitation
          // sent by the HOST (plan.visibility == 'PRIVATE' &&
          // plan.selectedUsers contains current user ID) vs a voluntary request.
          final planVis = planMap['visibility']?.toString().toUpperCase() ?? '';
          final selectedUsers = planMap['selectedUsers'];
          final bool isPrivateInvite = planVis == 'PRIVATE' &&
              selectedUsers is List &&
              selectedUsers.any((u) => u?.toString() == currentUserId);

          // Host user info from plan.creator (assigned to loop-level vars for use in item builder)
          hostCreator = planMap['creator'] is Map ? planMap['creator'] as Map<String, dynamic> : <String, dynamic>{};
          final hostName = '${hostCreator['firstName'] ?? user['firstName'] ?? 'Host'} ${hostCreator['lastName'] ?? user['lastName'] ?? ''}'.trim();
          hostPhoto = (hostCreator['profileImageUrl']?.toString().isNotEmpty == true
                  ? hostCreator['profileImageUrl'] as String
                  : null) ??
              (hostCreator['profilePhotoUrl']?.toString().isNotEmpty == true
                  ? hostCreator['profilePhotoUrl'] as String
                  : null) ??
              userPhoto?.toString();

          if (type == 'incoming_request') {
            // ─── HOST VIEW: someone requested to join my plan ──────────────
            if (status == 'pending') {
              title = '📥 Party Plan Request';
              body = '$userName requested to join your Party Plan at $venueName';
              actionsList = [
                NotificationAction(
                  label: 'Accept',
                  icon: Icons.check_circle_rounded,
                  isPrimary: true,
                  onTap: () => _handleAcceptPartyPlan(id),
                ),
                NotificationAction(
                  label: 'Decline',
                  icon: Icons.cancel_rounded,
                  isPrimary: false,
                  color: Colors.grey[200],
                  onTap: () => _handleRejectPartyPlan(id),
                ),
              ];
            } else if (status == 'accepted' || status == 'payment_pending') {
              title = '⏳ Approved — Awaiting Payment';
              body = 'You approved $userName. Waiting for safety deposit payment to unlock chat.';
              actionsList = [
                NotificationAction(
                  label: 'Revoke',
                  icon: Icons.cancel_rounded,
                  isPrimary: false,
                  color: Colors.grey[200],
                  onTap: () => _handleRejectPartyPlan(id),
                ),
              ];
            } else if (status == 'paid' || status == 'confirmed') {
              title = '🎉 Partner Joined';
              body = '$userName paid the deposit! Party Plan at $venueName is confirmed.';
              badge = 'CONFIRMED';
              final otherId = item['requesterId'] ?? user['id'] ?? '';
              actionsList = [
                NotificationAction(
                  label: 'Chat',
                  icon: Icons.chat_bubble_rounded,
                  isPrimary: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        user: {
                          'id': otherId,
                          'firstName': user['firstName'] ?? 'Party Partner',
                          'lastName': user['lastName'] ?? '',
                          'profilePhotoUrl': userPhoto,
                        },
                      ),
                    ),
                  ),
                ),
                NotificationAction(
                  label: 'View Ticket',
                  icon: Icons.confirmation_number_rounded,
                  isPrimary: false,
                  color: Colors.grey[200],
                  onTap: () {
                    final planData = item['plan'] is Map ? item['plan'] as Map<String, dynamic> : item;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PartyPlanTicketScreen(
                          request: item,
                          plan: planData,
                          isHost: currentUserId == (planData['userId'] ?? planData['creator']?['id']),
                        ),
                      ),
                    );
                  },
                ),
              ];
            }
          } else {
            // ─── JOINER / INVITEE VIEW ────────────────────────────────────
            if (isPrivateInvite) {
              // ─── PRIVATE INVITE from host ─────────────────────────────
              accent = const Color(0xFF7C3AED);
              if (status == 'pending') {
                title = '💌 Private Invite!';
                badge = 'INVITE';
                body = '$hostName privately invited you to their Party Plan at $venueName. Accept to proceed!';
                actionsList = [
                  NotificationAction(
                    label: 'Accept',
                    icon: Icons.check_circle_rounded,
                    isPrimary: true,
                    onTap: () => _handleAcceptPartyPlanInvite(id),
                  ),
                  NotificationAction(
                    label: 'Decline',
                    icon: Icons.cancel_rounded,
                    isPrimary: false,
                    color: Colors.grey[200],
                    onTap: () => _handleRejectPartyPlan(id),
                  ),
                ];
              } else if (status == 'accepted' || status == 'payment_pending') {
                title = '✅ Invite Accepted!';
                badge = 'ACTION REQUIRED';
                body = 'You accepted $hostName\'s invite at $venueName. Pay the safety deposit to lock your spot!';
                final countdownLabel = _calculateCountdownLabel(item, planMap);
                actionsList = [
                  NotificationAction(
                    label: countdownLabel,
                    icon: Icons.payment_rounded,
                    isPrimary: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PartyPlanDetailScreen(
                          plan: planMap.isNotEmpty ? planMap : item,
                        ),
                      ),
                    ).then((_) => _loadFeed(showLoader: false)),
                  ),
                  NotificationAction(
                    label: 'Decline',
                    icon: Icons.cancel_rounded,
                    isPrimary: false,
                    color: Colors.grey[200],
                    onTap: () => _handleRejectPartyPlan(id),
                  ),
                ];
              } else if (status == 'paid' || status == 'confirmed') {
                title = '🎉 Party Confirmed!';
                badge = 'CONFIRMED';
                body = 'Your spot at $venueName is locked! Chat with $hostName.';
                actionsList = [
                  NotificationAction(
                    label: 'Chat',
                    icon: Icons.chat_bubble_rounded,
                    isPrimary: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          user: {
                            'id': hostCreator['id'] ?? planMap['userId'] ?? '',
                            'firstName': hostCreator['firstName'] ?? 'Host',
                            'lastName': hostCreator['lastName'] ?? '',
                            'profilePhotoUrl': hostPhoto,
                          },
                        ),
                      ),
                    ),
                  ),
                  NotificationAction(
                    label: 'View Ticket',
                    icon: Icons.confirmation_number_rounded,
                    isPrimary: false,
                    color: Colors.grey[200],
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PartyPlanTicketScreen(
                            request: item,
                            plan: planMap.isNotEmpty ? planMap : item,
                            isHost: false,
                          ),
                        ),
                      );
                    },
                  ),
                ];
              } else if (status == 'rejected' || status == 'cancelled') {
                title = '\u274c Invite Declined';
                badge = 'DECLINED';
                body = 'You declined the invite from $hostName at $venueName.';
                accent = const Color(0xFF9CA3AF);
                // Show host's avatar on declined invite cards
                // (avatarUrl/senderUser is set below using hostCreator info)
              }
            } else {
              // ─── VOLUNTARY JOIN REQUEST sent by current user ──────────
              if (status == 'pending') {
                title = '⏳ Party Plan Request Sent';
                body = 'You requested to join the Party Plan at $venueName.';
                actionsList = [
                  NotificationAction(
                    label: 'Cancel Request',
                    icon: Icons.cancel_rounded,
                    isPrimary: false,
                    color: Colors.grey[200],
                    onTap: () => _handleRejectPartyPlan(id),
                  ),
                ];
              } else if (status == 'accepted' || status == 'payment_pending') {
                title = '👤 Request Accepted!';
                body = 'Your Party Plan request at $venueName was accepted! Pay safety deposit within 30 mins to unlock chat.';
                badge = 'ACTION REQUIRED';
                final countdownLabel = _calculateCountdownLabel(item, planMap);
                actionsList = [
                  NotificationAction(
                    label: countdownLabel,
                    icon: Icons.payment_rounded,
                    isPrimary: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PartyPlanDetailScreen(
                          plan: planMap.isNotEmpty ? planMap : item,
                        ),
                      ),
                    ).then((_) => _loadFeed(showLoader: false)),
                  ),
                  NotificationAction(
                    label: 'Cancel',
                    icon: Icons.cancel_rounded,
                    isPrimary: false,
                    color: Colors.grey[200],
                    onTap: () => _handleRejectPartyPlan(id),
                  ),
                ];
              } else if (status == 'paid' || status == 'confirmed') {
                title = '🎉 Match Confirmed!';
                body = 'Party booking at $venueName is confirmed! Chat is unlocked.';
                badge = 'CONFIRMED';
                final otherId = item['hostId'] ?? planMap['userId'] ?? user['id'] ?? '';
                actionsList = [
                  NotificationAction(
                    label: 'Chat',
                    icon: Icons.chat_bubble_rounded,
                    isPrimary: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          user: {
                            'id': otherId,
                            'firstName': user['firstName'] ?? 'Party Partner',
                            'lastName': user['lastName'] ?? '',
                            'profilePhotoUrl': userPhoto,
                          },
                        ),
                      ),
                    ),
                  ),
                  NotificationAction(
                    label: 'View Ticket',
                    icon: Icons.confirmation_number_rounded,
                    isPrimary: false,
                    color: Colors.grey[200],
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PartyPlanTicketScreen(
                            request: item,
                            plan: planMap.isNotEmpty ? planMap : item,
                            isHost: currentUserId == (planMap['userId'] ?? item['hostId']),
                          ),
                        ),
                      );
                    },
                  ),
                ];
              } else if (status == 'rejected' || status == 'cancelled') {
                title = '\u274c Request Declined';
                badge = 'DECLINED';
                body = 'Your Party Plan request at $venueName was declined by $hostName.';
                accent = const Color(0xFF9CA3AF);
              }
            }
          }
        }
      }

      // If current user is the host/creator of this party plan AND deposit is unpaid, enforce Action Required Pay Deposit card
      final hostPayStatus = (item['hostPaymentStatus'] ?? planMap['hostPaymentStatus'] ?? '').toString().toLowerCase();

      if (isMyCreatedPartyPlan && hostPayStatus != 'paid' && hostPayStatus != 'completed' && status != 'cancelled') {
        final double depositAmt = (item['depositAmount'] ?? planMap['depositAmount'] ?? 99.0) is num
            ? (item['depositAmount'] ?? planMap['depositAmount'] ?? 99.0).toDouble()
            : 99.0;
        final partyPlanId = item['id']?.toString() ?? planMap['id']?.toString() ?? '';
        final hostOrderId = item['hostRazorpayOrderId']?.toString() ?? planMap['hostRazorpayOrderId']?.toString() ?? '';

        title = '⚡ Action Required: Pay Host Deposit';
        body = 'Pay deposit of ₹${depositAmt.toStringAsFixed(0)} for your Party Plan at $venueName to publish it!';
        badge = 'ACTION REQUIRED';
        accent = const Color(0xFF8B5CF6);
        actionsList = [
          NotificationAction(
            label: 'Pay Deposit (${depositAmt.toStringAsFixed(0)})',
            icon: Icons.payment_rounded,
            isPrimary: true,
            onTap: () async {
              await _startHostRazorpayDirectPaymentInLiveFeed(
                partyPlanId: partyPlanId,
                venueName: venueName,
                orderId: hostOrderId,
                depositAmount: depositAmt,
                onSuccess: () async {
                  _loadFeed();
                },
              );
            },
          ),
          NotificationAction(
            label: 'View Plan',
            icon: Icons.open_in_new_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PartyPlanDetailScreen(
                    plan: planMap.isNotEmpty ? planMap : item,
                  ),
                ),
              );
            },
          ),
        ];
      }

      // Handle CANCELLED state for Party Plan cards
      final String planStatus = (item['status'] ?? planMap['status'] ?? '').toString().toLowerCase();
      final String lifecycleStatus = (item['lifecycleStatus'] ?? planMap['lifecycleStatus'] ?? '').toString().toLowerCase();

      if (planStatus == 'cancelled' || lifecycleStatus == 'cancelled') {
        title = '❌ Party Plan Cancelled';
        body = 'This Party Plan at $venueName was cancelled by mutual agreement.';
        badge = 'CANCELLED';
        accent = Colors.redAccent;
        actionsList = [
          NotificationAction(
            label: 'View Details',
            icon: Icons.info_outline_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PartyPlanDetailScreen(
                    plan: planMap.isNotEmpty ? planMap : item,
                  ),
                ),
              );
            },
          ),
        ];
      }

      // Hide unpaid party plans created by OTHER users from live feed
      if (!isStranger && !isMyCreatedPartyPlan && hostPayStatus.isNotEmpty && hostPayStatus != 'paid' && hostPayStatus != 'completed') {
        continue;
      }

        // For declined party plan cards, show the host/creator's avatar (the person who declined)
        final bool isDeclined = badge == 'DECLINED' || badge == 'REJECTED';
        final String? resolvedAvatarUrl = isDeclined && !isStranger
            ? ((hostCreator['profileImageUrl']?.toString().isNotEmpty == true
                    ? hostCreator['profileImageUrl']
                    : null) ??
                (hostCreator['profilePhotoUrl']?.toString().isNotEmpty == true
                    ? hostCreator['profilePhotoUrl']
                    : null) ??
                (hostPhoto?.isNotEmpty == true ? hostPhoto : null) ??
                userPhoto?.toString())
            : userPhoto?.toString();
        final Map<String, dynamic>? resolvedSenderUser = isDeclined && !isStranger && hostCreator.isNotEmpty
            ? hostCreator
            : (user.isNotEmpty ? user : null);

        items.add(UnifiedNotificationItem(
          id: requestType == 'stranger_meet' || type == 'stranger_meet' ? 'sm_$id' : 'pp_$id',
          category: requestType == 'stranger_meet' || type == 'stranger_meet' ? 'stranger_meet' : 'party_plan',
          title: title,
          body: body,
          createdAt: createdAt,
          timeAgo: timeAgo,
          isRead: isRead,
          badgeText: badge,
          accentColor: accent,
          categoryIcon: requestType == 'stranger_meet' || type == 'stranger_meet'
              ? Icons.people_alt_rounded
              : Icons.celebration_rounded,
          avatarUrl: resolvedAvatarUrl,
          senderUser: resolvedSenderUser,
          actions: actionsList,
          rawData: item,
        ));
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

      bool isExpired = false;
      final rawDateTime = booking['partyDate'] ?? booking['bookingDate'] ?? booking['createdAt'];
      if (rawDateTime != null) {
        try {
          final planTime = DateTime.parse(rawDateTime.toString()).toLocal();
          if (planTime.isBefore(DateTime.now())) {
            isExpired = true;
          }
        } catch (_) {}
      }

      if (isExpired) {
        accent = const Color(0xFF9CA3AF);
        badge = 'EXPIRED';
      } else {
        final adminApproval = (booking['adminApprovalStatus'] ?? '').toString().toLowerCase();
        if (status == 'approved' || status == 'awaiting_payment' || adminApproval == 'approved') {
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
      }

      List<NotificationAction>? actionsList;
      if (!isExpired && actionText != null && actionTap != null) {
        actionsList = [
          NotificationAction(
            label: actionText,
            onTap: actionTap,
            isPrimary: true,
            icon: actionText == 'Pay Now' ? Icons.payment_rounded : Icons.confirmation_number_rounded,
          )
        ];
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
        actions: actionsList,
        rawData: booking,
      ));
    }

    // Sort all timeline items descending by createdAt
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Universal Entity Grouping & Deduplication so only 1 notification card is shown per plan/meet/booking
    final Map<String, UnifiedNotificationItem> entityMap = {};
    final List<UnifiedNotificationItem> uniqueItems = [];
    for (final item in items) {
      final raw = item.rawData;
      final planData = raw['plan'] is Map ? (raw['plan'] as Map<String, dynamic>) : raw;
      final rawData = raw['data'] is Map ? (raw['data'] as Map<String, dynamic>) : <String, dynamic>{};

      String groupKey = item.id;
      final entityId = rawData['partyPlanId']?.toString() ??
          raw['partyPlanId']?.toString() ??
          raw['entityId']?.toString() ??
          raw['requestId']?.toString() ??
          raw['strangersMeetId']?.toString() ??
          raw['bookingId']?.toString() ??
          planData['id']?.toString();

      if (entityId != null && entityId.isNotEmpty) {
        groupKey = '${item.category}_$entityId';
      }

      if (!entityMap.containsKey(groupKey)) {
        entityMap[groupKey] = item;
        uniqueItems.add(item);
      } else if (item.category == 'party_plan') {
        // Active Host Pay Deposit notification takes priority over old party plan updates
        final existingItem = entityMap[groupKey]!;
        final isCurrentHostDeposit = item.actions?.any((a) => a.label.contains('Pay Deposit')) == true;
        final isExistingHostDeposit = existingItem.actions?.any((a) => a.label.contains('Pay Deposit')) == true;

        if (isCurrentHostDeposit && !isExistingHostDeposit) {
          entityMap[groupKey] = item;
          final idx = uniqueItems.indexOf(existingItem);
          if (idx != -1) {
            uniqueItems[idx] = item;
          }
        }
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
                        separatorBuilder: (_, i) => const Divider(height: 1),
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
  // Build Status Filter Pills with Live Unread Counts
  // ─────────────────────────────────────────────────────────────────────────────
  int _countForPill(String pillId, List<UnifiedNotificationItem> allItems) {
    if (pillId == 'ALL') return allItems.where((i) => !i.isRead).length;
    return allItems.where((item) {
      final badge = item.badgeText?.toUpperCase() ?? '';
      final category = item.category.toLowerCase();
      final title = item.title.toLowerCase();
      final rawStatus = (item.rawData['status'] ?? item.rawData['paymentStatus'] ?? '').toString().toLowerCase();
      bool matches = false;
      if (pillId == 'REQUESTS') {
        matches = title.contains('request') || badge.contains('REQUEST') || category.contains('request');
      } else if (pillId == 'PENDING') {
        matches = rawStatus.contains('pending') || badge.contains('ACTION REQUIRED') || badge.contains('PENDING');
      } else if (pillId == 'PAYMENT') {
        matches = category.contains('pay') || category.contains('wallet') || badge.contains('PAYMENT') || title.contains('payment') || title.contains('paid');
      } else if (pillId == 'CONFIRMED') {
        matches = rawStatus.contains('confirmed') || rawStatus.contains('paid') || badge.contains('CONFIRMED') || title.contains('confirmed');
      } else if (pillId == 'SYSTEM') {
        matches = category.contains('system') || category.contains('promo') || badge.contains('SYSTEM') || badge.contains('PROMO');
      }
      return matches && !item.isRead;
    }).length;
  }

  Widget _buildStatusFilterBar() {
    final allTimelineItems = _buildUnifiedTimeline();
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
            final unreadCount = _countForPill(id, allTimelineItems);
            final hasUnread = unreadCount > 0;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label),
                    if (hasUnread) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : Colors.redAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: isSelected ? LunaraTheme.electricViolet : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) setState(() => _selectedStatusPill = id);
                },
                selectedColor: LunaraTheme.electricViolet,
                backgroundColor: hasUnread && !isSelected
                    ? LunaraTheme.electricViolet.withValues(alpha: 0.06)
                    : const Color(0xFFF3F4F6),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected
                        ? LunaraTheme.electricViolet
                        : hasUnread
                            ? LunaraTheme.electricViolet.withValues(alpha: 0.3)
                            : Colors.transparent,
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
        final hasPayAction = item.actions?.any((act) => act.label.toLowerCase().contains('pay')) ?? false;
        return category.contains('pay') ||
            category.contains('wallet') ||
            category.contains('deposit') ||
            rawStatus.contains('pay') ||
            rawStatus.contains('deposit') ||
            rawStatus.contains('awaiting_payment') ||
            badge.contains('PAYMENT') ||
            badge.contains('ACTION REQUIRED') ||
            title.contains('payment') ||
            title.contains('paid') ||
            title.contains('pay') ||
            title.contains('deposit') ||
            body.contains('payment') ||
            body.contains('pay') ||
            body.contains('deposit') ||
            hasPayAction;
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _onCardTap(item),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Accent Bar
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: item.accentColor,
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
                            if (item.senderUser != null || (item.avatarUrl != null && item.avatarUrl!.isNotEmpty))
                              LunaraProfileImage(
                                userData: item.senderUser ?? {
                                  'profilePhotoUrl': item.avatarUrl,
                                  'firstName': item.title,
                                },
                                radius: 18,
                                isInteractive: item.senderUser != null && item.senderUser!['id'] != null,
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
                                  color: item.badgeText == 'EXPIRED'
                                      ? Colors.grey[300]!
                                      : item.accentColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.badgeText!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: item.badgeText == 'EXPIRED'
                                        ? Colors.grey[600]!
                                        : item.accentColor,
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

                        // Expired notice
                        if (item.badgeText == 'EXPIRED') ...[
                          const SizedBox(height: 8),
                          Row(
                            children: const [
                              Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'This event has expired. No further actions can be taken.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Action Buttons Row (Accept/Decline/Pay/View Ticket/Chat)
                        if (item.actions != null && item.actions!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: item.actions!.map((action) {
                              final isPrimary = action.isPrimary;
                              final btnColor = action.color ?? (isPrimary ? item.accentColor : Colors.grey[200]!);
                              final textColor = isPrimary ? Colors.white : Colors.black87;

                              return Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: ElevatedButton.icon(
                                  onPressed: action.onTap,
                                  icon: action.icon != null
                                      ? Icon(action.icon, size: 15, color: textColor)
                                      : const SizedBox.shrink(),
                                  label: Text(
                                    action.label,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: btnColor,
                                    foregroundColor: textColor,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                    minimumSize: const Size(90, 42),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: !isPrimary
                                          ? BorderSide(color: Colors.grey[300]!, width: 0.8)
                                          : BorderSide.none,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startHostRazorpayDirectPaymentInLiveFeed({
    required String partyPlanId,
    required String venueName,
    required String orderId,
    required double depositAmount,
    required Future<void> Function() onSuccess,
  }) async {
    String cleanPlanId = partyPlanId.trim();
    if (cleanPlanId.startsWith('party_plan_timeline_')) {
      cleanPlanId = cleanPlanId.replaceFirst('party_plan_timeline_', '');
    }
    if (cleanPlanId.startsWith('pp_')) {
      cleanPlanId = cleanPlanId.replaceFirst('pp_', '');
    }

    final double price = depositAmount > 0 ? depositAmount : 99.0;

    SmartCheckoutSheet.show(
      context: context,
      title: 'Host Safety Deposit',
      subtitle: 'Publish & activate your Party Plan at $venueName',
      itemPrice: price,
      onWalletPayment: () async {
        final res = await ApiService.payWithWallet(
          amount: price,
          planId: cleanPlanId,
          paymentType: 'host_deposit',
        );
        if (res != null && res['success'] == true) {
          final transactionId = res['data']?['transactionId']?.toString() ?? 'wallet';
          final paymentConfirmed = await ApiService.verifyHostPayment(
            cleanPlanId,
            'order_mock_wallet',
            'wallet_$transactionId',
            'mock_signature',
          );
          if (paymentConfirmed && mounted) {
            await onSuccess();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 Host Safety Deposit Paid via Smart Wallet! Plan Published.'),
                backgroundColor: Colors.green,
              ),
            );
            return true;
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res?['message'] ?? 'Wallet payment failed'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return false;
      },
      onDirectPayment: () async {
        await _launchRazorpayForHostPayment(
          cleanPlanId: cleanPlanId,
          venueName: venueName,
          depositAmount: price,
          onSuccess: onSuccess,
        );
      },
      onHybridPayment: (shortfall) async {
        await _launchRazorpayForHostPayment(
          cleanPlanId: cleanPlanId,
          venueName: venueName,
          depositAmount: shortfall > 0 ? shortfall : price,
          onSuccess: onSuccess,
        );
      },
    );
  }

  Future<void> _launchRazorpayForHostPayment({
    required String cleanPlanId,
    required String venueName,
    required double depositAmount,
    required Future<void> Function() onSuccess,
  }) async {
    final initRes = await ApiService.initiateHostPayment(cleanPlanId);
    String currentOrderId = '';
    String razorpayKey = 'rzp_test_123';
    if (initRes != null && initRes['success'] == true) {
      currentOrderId = (initRes['razorpayOrderId'] ?? '').toString();
      if (initRes['razorpayKeyId'] != null && initRes['razorpayKeyId'].toString().isNotEmpty) {
        razorpayKey = initRes['razorpayKeyId'].toString();
      }
    }

    if (currentOrderId.isEmpty) {
      currentOrderId = 'order_mock_${DateTime.now().millisecondsSinceEpoch}';
    }

    // Intercept mock orders or test keys to avoid Razorpay SDK code 0 error on devices
    if (currentOrderId.startsWith('order_mock_') || razorpayKey == 'rzp_test_123' || currentOrderId.startsWith('mock_')) {
      final paymentConfirmed = await ApiService.verifyHostPayment(
        cleanPlanId,
        currentOrderId,
        'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
        'mock_signature',
      );
      if (paymentConfirmed && mounted) {
        await onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Host Safety Deposit Paid! Your plan is live.'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }
    }

    late Razorpay razorpay;
    razorpay = Razorpay();

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) async {
      final pId = response.paymentId ?? 'pay_mock_${DateTime.now().millisecondsSinceEpoch}';
      final oId = response.orderId ?? currentOrderId;
      final sig = response.signature ?? 'mock_signature';

      final paymentConfirmed = await ApiService.verifyHostPayment(
        cleanPlanId,
        oId,
        pId,
        sig,
      );

      razorpay.clear();
      if (paymentConfirmed && mounted) {
        await onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Host Safety Deposit Paid! Your plan is fully activated.'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        // Never treat a client-side/mock identifier as confirmation. The
        // backend verification result is the only payment success signal.
        if (!paymentConfirmed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment verification failed. Please refresh and try again.'),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
        if (oId.startsWith('order_mock_') || pId.startsWith('pay_mock_')) {
          await onSuccess();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Host Safety Deposit Paid! Plan is live.'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          const msg = 'Payment verification failed. Please refresh and try again.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment Failed: $msg'), backgroundColor: Colors.redAccent),
          );
        }
      }
    });

    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) async {
      razorpay.clear();
      debugPrint('[PAYMENT-07] Razorpay error callback: code=${response.code}, message=${response.message}');
      if (mounted) {
        if ((response.code == 0 || response.code == 2) && (razorpayKey == 'rzp_test_123' || currentOrderId.startsWith('order_mock_'))) {
          final mockConfirmed = await ApiService.verifyHostPayment(
            cleanPlanId,
            currentOrderId,
            'pay_test_${DateTime.now().millisecondsSinceEpoch}',
            'test_signature',
          );
          if (mockConfirmed && mounted) {
            await onSuccess();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 Host Safety Deposit Paid! Plan is activated.'),
                backgroundColor: Colors.green,
              ),
            );
            return;
          }
        }

        String errText = response.message ?? 'Payment process cancelled or failed';
        if (errText.isEmpty || errText == 'Payment Failed') {
          if (response.code == Razorpay.PAYMENT_CANCELLED) {
            errText = 'Payment cancelled by user';
          } else {
            errText = 'Payment error (code ${response.code})';
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment Failed: $errText'), backgroundColor: Colors.redAccent),
        );
      }
    });

    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {
      razorpay.clear();
    });

    final options = <String, dynamic>{
      'key': razorpayKey,
      'amount': (depositAmount * 100).round(),
      'name': 'Lunara Host Deposit',
      'description': 'Host safety deposit for Party Plan at $venueName',
      'currency': 'INR',
      if (currentOrderId.isNotEmpty) 'order_id': currentOrderId,
      'prefill': {'contact': '9999999999', 'email': 'user@lunara.app'},
      'theme': {'color': '#7C3AED'},
    };

    try {
      razorpay.open(options);
    } catch (e) {
      debugPrint('Error opening Razorpay for Host Payment: $e');
    }
  }

  String _calculateCountdownLabel(Map<String, dynamic> item, Map<String, dynamic> planMap) {
    final rawDeadline = item['paymentDeadlineAt'] ?? item['payment_deadline_at'] ?? planMap['paymentDeadlineAt'] ?? planMap['payment_deadline_at'];
    if (rawDeadline != null) {
      try {
        final deadline = DateTime.parse(rawDeadline.toString()).toUtc();
        final rawServerTime = item['serverTime'] ?? planMap['serverTime'];
        final serverNow = rawServerTime == null
            ? DateTime.now().toUtc()
            : DateTime.parse(rawServerTime.toString()).toUtc();
        final clockOffset = serverNow.difference(DateTime.now().toUtc());
        final diff = deadline.difference(DateTime.now().toUtc().add(clockOffset));
        if (diff.inSeconds <= 0) {
          return 'Pay Deposit (Expired)';
        }
        final mins = diff.inMinutes;
        final secs = diff.inSeconds % 60;
        final secStr = secs < 10 ? '0$secs' : '$secs';
        return 'Pay Deposit (${mins}m ${secStr}s)';
      } catch (_) {}
    }
    return 'Payment status unavailable';
  }
}
