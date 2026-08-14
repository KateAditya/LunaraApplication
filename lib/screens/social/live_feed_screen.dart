// ignore_for_file: use_build_context_synchronously, unused_local_variable
import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import 'party_plan_detail_screen.dart';
import 'widgets/party_plan_arrival_dialog.dart';
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
  final bool isExpired;
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
    this.isExpired = false,
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
            content: Text('Request declined.'),
            backgroundColor: Colors.grey,
          ),
        );
        _loadFeed();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to decline request.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      debugPrint('Error rejecting request: $e');
    }
  }

  /// Cancels the CURRENT USER's own pending join request (joiner cancels their own request).
  Future<void> _handleCancelMyRequest(String reqId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
      ),
    );
    try {
      final success = await ApiService.cancelPartyPlanRequest(reqId);
      Navigator.pop(context);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request cancelled successfully.'),
            backgroundColor: Colors.grey,
          ),
        );
        _loadFeed();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to cancel request. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      debugPrint('Error cancelling request: $e');
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
                isJoinPayment: true,
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
  // Unified Item Builders & Mapping (1 PLAN / 1 MEET = 1 SMART CARD)
  // ─────────────────────────────────────────────────────────────────────────────
  String? _extractPartyPlanId(Map<String, dynamic> item) {
    if (item['data'] is Map && item['data']['partyPlanId'] != null) {
      final id = item['data']['partyPlanId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['metadata'] is Map && item['metadata']['partyPlanId'] != null) {
      final id = item['metadata']['partyPlanId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['partyPlanId'] != null) {
      final id = item['partyPlanId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['plan'] is Map && item['plan']['id'] != null) {
      final String cat = (item['requestType'] ?? item['type'] ?? item['category'] ?? item['entityType'] ?? '').toString().toLowerCase();
      if (cat.contains('party') || cat == 'my_request' || cat == 'incoming_request') {
        if (!cat.contains('stranger') && !cat.contains('meet')) {
          final id = item['plan']['id'].toString().trim();
          if (id.isNotEmpty) return id;
        }
      }
    }
    if (item['planId'] != null) {
      final String cat = (item['requestType'] ?? item['type'] ?? item['category'] ?? item['entityType'] ?? '').toString().toLowerCase();
      if (cat.contains('party') || cat == 'my_request' || cat == 'incoming_request') {
        if (!cat.contains('stranger') && !cat.contains('meet')) {
          final id = item['planId'].toString().trim();
          if (id.isNotEmpty) return id;
        }
      }
    }
    final String type = (item['type'] ?? item['eventType'] ?? item['category'] ?? item['entityType'] ?? '').toString().toLowerCase();
    if (type == 'party_plan' || type == 'party_plan_timeline' || type.contains('party_plan')) {
      final id = item['id']?.toString() ?? item['entityId']?.toString() ?? '';
      if (id.isNotEmpty && !id.startsWith('sm_') && !id.startsWith('gp_')) {
        return id.replaceAll('pp_', '').replaceAll('party_plan_timeline_', '').replaceAll('pp_host_deposit_', '');
      }
    }
    return null;
  }

  String? _extractStrangersMeetId(Map<String, dynamic> item) {
    if (item['data'] is Map && item['data']['strangersMeetId'] != null) {
      final id = item['data']['strangersMeetId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['data'] is Map && item['data']['requestId'] != null && (item['data']['type']?.toString().contains('strangers_meet') == true || item['data']['type']?.toString().contains('sm_') == true)) {
      final id = item['data']['requestId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['metadata'] is Map && item['metadata']['strangersMeetId'] != null) {
      final id = item['metadata']['strangersMeetId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['strangersMeetId'] != null) {
      final id = item['strangersMeetId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['strangersMeetRequestId'] != null) {
      final id = item['strangersMeetRequestId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    final String cat = (item['requestType'] ?? item['type'] ?? item['category'] ?? item['entityType'] ?? '').toString().toLowerCase();
    if (cat.contains('stranger') || cat.contains('meet')) {
      if (item['planDetails'] is Map && item['planDetails']['id'] != null) {
        return item['planDetails']['id'].toString().trim();
      }
      if (item['plan'] is Map && item['plan']['id'] != null) {
        return item['plan']['id'].toString().trim();
      }
      if (item['planId'] != null) {
        return item['planId'].toString().trim();
      }
      final id = item['id']?.toString() ?? item['entityId']?.toString() ?? '';
      if (id.isNotEmpty && !id.startsWith('pp_') && !id.startsWith('gp_')) {
        return id.replaceAll('sm_', '').replaceAll('strangers_meet_timeline_', '').replaceAll('sm_host_deposit_', '').replaceAll('sm_host_approved_', '');
      }
    }
    return null;
  }

  List<UnifiedNotificationItem> _buildUnifiedTimeline() {
    final List<UnifiedNotificationItem> items = [];
    final currentUserId = ApiService.currentUserId ?? '';

    // 1. Partition entries into Party Plan, Stranger Meet, and General Notifications
    final Map<String, List<Map<String, dynamic>>> partyPlanGroups = {};
    final Map<String, List<Map<String, dynamic>>> strangersMeetGroups = {};
    final List<Map<String, dynamic>> nonPartyNotifications = [];
    final List<Map<String, dynamic>> nonPartyFeedItems = [];

    for (final n in _notifications) {
      final ppId = _extractPartyPlanId(n);
      final smId = _extractStrangersMeetId(n);

      if (ppId != null && ppId.isNotEmpty) {
        partyPlanGroups.putIfAbsent(ppId, () => []).add(n);
      } else if (smId != null && smId.isNotEmpty) {
        strangersMeetGroups.putIfAbsent(smId, () => []).add(n);
      } else {
        nonPartyNotifications.add(n);
      }
    }

    for (final fi in _feedItems) {
      final ppId = _extractPartyPlanId(fi);
      final smId = _extractStrangersMeetId(fi);

      if (ppId != null && ppId.isNotEmpty) {
        partyPlanGroups.putIfAbsent(ppId, () => []).add(fi);
      } else if (smId != null && smId.isNotEmpty) {
        strangersMeetGroups.putIfAbsent(smId, () => []).add(fi);
      } else {
        nonPartyFeedItems.add(fi);
      }
    }

    // 2. Build Exactly ONE Authoritative Smart Card per Party Plan
    for (final entry in partyPlanGroups.entries) {
      final planId = entry.key;
      final planEntries = entry.value;
      final smartCard = _buildAuthoritativePartyPlanCard(planId, planEntries, currentUserId);
      if (smartCard != null) {
        items.add(smartCard);
      }
    }

    // 3. Build Exactly ONE Authoritative Smart Card per Stranger Meet
    for (final entry in strangersMeetGroups.entries) {
      final meetId = entry.key;
      final meetEntries = entry.value;
      final smartCard = _buildAuthoritativeStrangersMeetCard(meetId, meetEntries, currentUserId);
      if (smartCard != null) {
        items.add(smartCard);
      }
    }

    // 4. Process General Push Notifications (Table Plans, System, Wallet, Promo)
    for (final n in nonPartyNotifications) {
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

      if (category.contains('booking') || category.contains('group')) {
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
      } else if (actionText != null && actionTap != null) {
        actionsList = [
          NotificationAction(
            label: actionText,
            onTap: actionTap,
            isPrimary: true,
            icon: Icons.arrow_forward_rounded,
          ),
        ];
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
        isExpired: isExpired,
        badgeText: badge,
        accentColor: accentColor,
        categoryIcon: icon,
        avatarUrl: n['imageUrl']?.toString() ?? actorMap?['profilePhotoUrl']?.toString() ?? actorMap?['profileImageUrl']?.toString(),
        senderUser: actorMap,
        actionButtonText: actionText,
        onActionTap: actionTap,
        actions: isExpired ? null : actionsList,
        rawData: n,
      ));
    }

    // 5. Process Large Party / Group Party Bookings
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
        isExpired: isExpired,
        badgeText: badge,
        accentColor: accent,
        categoryIcon: Icons.groups_rounded,
        actionButtonText: actionText,
        onActionTap: actionTap,
        actions: isExpired ? null : actionsList,
        rawData: booking,
      ));
    }

    // Sort all timeline items descending by createdAt
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build Authoritative Party Plan Smart Card (1 Party Plan = 1 Card)
  // ─────────────────────────────────────────────────────────────────────────────
  UnifiedNotificationItem? _buildAuthoritativePartyPlanCard(
    String planId,
    List<Map<String, dynamic>> entries,
    String currentUserId,
  ) {
    if (entries.isEmpty) return null;

    // 1. Extract the richest Plan map
    Map<String, dynamic> planMap = {};
    for (final e in entries) {
      if (e['plan'] is Map && (e['plan'] as Map).isNotEmpty) {
        planMap = Map<String, dynamic>.from(e['plan']);
        break;
      } else if (e['type'] == 'party_plan' || e['category'] == 'party_plan') {
        if (e['venue'] != null || e['creator'] != null || e['planDateTime'] != null) {
          planMap = Map<String, dynamic>.from(e);
          break;
        }
      }
    }
    if (planMap.isEmpty) {
      final first = entries.first;
      if (first['data'] is Map && (first['data'] as Map).isNotEmpty) {
        planMap = Map<String, dynamic>.from(first['data']);
      } else {
        planMap = Map<String, dynamic>.from(first);
      }
    }

    planMap['id'] = planMap['id'] ?? planId;

    // 2. Identify Venue and Host details
    final venue = (planMap['venue'] is Map)
        ? planMap['venue'] as Map<String, dynamic>
        : <String, dynamic>{};
    final venueName = venue['name']?.toString() ?? planMap['venueName']?.toString() ?? 'Party Venue';

    final hostCreator = (planMap['creator'] is Map)
        ? planMap['creator'] as Map<String, dynamic>
        : (planMap['host'] is Map
            ? planMap['host'] as Map<String, dynamic>
            : <String, dynamic>{});
    final hostName = '${hostCreator["firstName"] ?? planMap["hostName"] ?? "Host"} ${hostCreator["lastName"] ?? ""}'.trim();
    final hostPhoto = hostCreator['profileImageUrl']?.toString() ?? hostCreator['profilePhotoUrl']?.toString() ?? planMap['hostProfilePhotoUrl']?.toString();

    final String planHostId = (planMap['userId'] ?? hostCreator['id'] ?? '').toString();
    final bool isHost = currentUserId.isNotEmpty && (planHostId == currentUserId || planMap['role'] == 'host');

    // 3. Find requests involving current user or host
    Map<String, dynamic>? myRequest;
    final List<Map<String, dynamic>> pendingIncomingRequests = [];
    Map<String, dynamic>? acceptedJoinerRequest;

    for (final e in entries) {
      final reqType = (e['type'] ?? e['requestType'] ?? '').toString();
      final status = (e['status'] ?? '').toString().toLowerCase();

      if (reqType == 'my_request' || e['requesterId']?.toString() == currentUserId) {
        myRequest = e;
      }
      if (reqType == 'incoming_request' || (isHost && e['requester'] != null)) {
        if (status == 'pending') {
          pendingIncomingRequests.add(e);
        } else if (status == 'accepted' || status == 'payment_pending' || status == 'paid' || status == 'confirmed') {
          acceptedJoinerRequest = e;
        }
      }
      if (status == 'confirmed' || status == 'paid') {
        acceptedJoinerRequest = e;
      }
    }

    // 4. Format plan date & time
    String formattedDateTime = '';
    final rawDateTime = planMap['planDateTime'] ?? planMap['eventDateTime'] ?? planMap['planDate'];
    DateTime? parsedEventDate;
    if (rawDateTime != null) {
      try {
        parsedEventDate = DateTime.parse(rawDateTime.toString()).toLocal();
        const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final w = weekdayNames[parsedEventDate.weekday - 1];
        final m = monthNames[parsedEventDate.month - 1];
        final hour = parsedEventDate.hour % 12 == 0 ? 12 : parsedEventDate.hour % 12;
        final ampm = parsedEventDate.hour >= 12 ? 'PM' : 'AM';
        final minute = parsedEventDate.minute.toString().padLeft(2, '0');
        formattedDateTime = '$w, ${parsedEventDate.day} $m • $hour:$minute $ampm';
      } catch (_) {}
    }

    // 5. Expiration & Status Checks
    bool isExpired = false;
    if (parsedEventDate != null && parsedEventDate.isBefore(DateTime.now())) {
      isExpired = true;
    }

    final String planStatus = (planMap['status'] ?? '').toString().toLowerCase();
    final String lifecycleStatus = (planMap['lifecycleStatus'] ?? '').toString().toLowerCase();
    final String hostPaymentStatus = (planMap['hostPaymentStatus'] ?? '').toString().toLowerCase();

    if (planStatus == 'expired' || lifecycleStatus == 'expired' || lifecycleStatus == 'payment_expired') {
      isExpired = true;
    }

    final bool isCancelled = planStatus == 'cancelled' ||
        lifecycleStatus == 'cancelled' ||
        (myRequest != null && (myRequest['status'] == 'cancelled' || myRequest['status'] == 'rejected'));

    final bool hostReached = planMap['hostArrivalConfirmed'] == true;
    final bool guestReached = (acceptedJoinerRequest != null && acceptedJoinerRequest['guestArrivalConfirmed'] == true) ||
        (myRequest != null && myRequest['guestArrivalConfirmed'] == true);
    final bool bothReached = hostReached && guestReached;
    final bool userReached = isHost ? hostReached : guestReached;
    final bool partnerReached = isHost ? guestReached : hostReached;
    final bool isRefunded = hostPaymentStatus == 'refunded' ||
        (myRequest != null && myRequest['joinerPaymentStatus'] == 'refunded') ||
        lifecycleStatus == 'plan_completed' ||
        planMap['paymentStatus']?.toString().toLowerCase().contains('refunded') == true;

    final bool inArrivalWindow = parsedEventDate != null &&
        parsedEventDate.difference(DateTime.now()).inMinutes <= 15 &&
        parsedEventDate.difference(DateTime.now()).inHours >= -3;

    final bool isConfirmed = lifecycleStatus == 'match_confirmed' ||
        lifecycleStatus == 'chat_enabled' ||
        (myRequest != null && (myRequest['status'] == 'confirmed' || myRequest['status'] == 'paid' || myRequest['joinerPaymentStatus'] == 'paid')) ||
        (acceptedJoinerRequest != null && (acceptedJoinerRequest['status'] == 'confirmed' || acceptedJoinerRequest['status'] == 'paid' || acceptedJoinerRequest['joinerPaymentStatus'] == 'paid'));

    String countdownLabel = 'Pay Deposit';
    bool isPaymentExpired = false;
    final rawDeadline = myRequest?['paymentDeadlineAt'] ??
        myRequest?['paymentTimeoutAt'] ??
        planMap['paymentDeadlineAt'] ??
        planMap['paymentTimeoutAt'];

    if (rawDeadline != null) {
      try {
        final deadline = DateTime.parse(rawDeadline.toString()).toLocal();
        final remaining = deadline.difference(DateTime.now());
        if (remaining.isNegative) {
          isPaymentExpired = true;
          countdownLabel = 'Pay Deposit (Expired)';
        } else {
          final m = remaining.inMinutes;
          final s = remaining.inSeconds % 60;
          countdownLabel = 'Pay Deposit ($m:${s.toString().padLeft(2, "0")})';
        }
      } catch (_) {}
    }

    if (isPaymentExpired && !isConfirmed) {
      isExpired = true;
    }

    // 6. Contextual Title, Subtitle, Badges & Actions
    Color accent = const Color(0xFF8B5CF6);
    String title = 'Let\'s party at $venueName! 🚀';
    String body = formattedDateTime.isNotEmpty ? '📅 $formattedDateTime' : 'Party Plan at $venueName';
    String badge = 'PARTY PLAN';
    List<NotificationAction>? actionsList;
    Map<String, dynamic>? senderUser = hostCreator;
    String? avatarUrl = hostPhoto;

    if (isExpired) {
      accent = const Color(0xFF9CA3AF);
      badge = 'EXPIRED';
      body = 'This Party Plan at $venueName has expired.';
      actionsList = null;
    } else if (isCancelled) {
      accent = const Color(0xFFEF4444);
      badge = 'CANCELLED';
      body = 'Party Plan at $venueName was cancelled by mutual agreement.';
      actionsList = [
        NotificationAction(
          label: 'View Details',
          icon: Icons.info_outline_rounded,
          isPrimary: false,
          color: Colors.grey[200],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PartyPlanDetailScreen(plan: planMap)),
          ).then((_) => _loadFeed(showLoader: false)),
        ),
      ];
    } else if (bothReached || isRefunded) {
      title = '🎉 Party Completed';
      badge = 'COMPLETED';
      accent = const Color(0xFF10B981);
      body = 'Both participants confirmed arrival • 💰 ₹99 Deposit refunded to LUNARA Wallet.';
      actionsList = [
        NotificationAction(
          label: 'View Wallet',
          icon: Icons.account_balance_wallet_rounded,
          isPrimary: true,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LunaraWalletScreen()),
          ),
        ),
        NotificationAction(
          label: 'View Details',
          icon: Icons.info_outline_rounded,
          isPrimary: false,
          color: Colors.grey[200],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PartyPlanDetailScreen(plan: planMap)),
          ).then((_) => _loadFeed(showLoader: false)),
        ),
      ];
    } else if (isConfirmed && userReached && !partnerReached) {
      title = '📍 Arrival Confirmed';
      badge = 'CONFIRMED';
      accent = const Color(0xFF6366F1);
      body = 'You: ✓ Reached • Partner: ⏳ Waiting for confirmation';
      final otherId = isHost
          ? (acceptedJoinerRequest?['requesterId'] ?? '')
          : (planHostId.isNotEmpty ? planHostId : (hostCreator['id'] ?? ''));

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
                  'firstName': isHost ? 'Party Partner' : (hostCreator['firstName'] ?? hostName),
                  'lastName': isHost ? '' : (hostCreator['lastName'] ?? ''),
                  'profilePhotoUrl': isHost ? null : hostPhoto,
                },
              ),
            ),
          ),
        ),
        NotificationAction(
          label: 'View Plan',
          icon: Icons.open_in_new_rounded,
          isPrimary: false,
          color: Colors.grey[200],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PartyPlanDetailScreen(plan: planMap)),
          ),
        ),
      ];
    } else if (isConfirmed && !userReached && inArrivalWindow) {
      title = 'Let\'s party at $venueName! 🚀';
      badge = 'ACTION REQUIRED';
      accent = const Color(0xFFF59E0B);
      body = '⏱ Starts soon • 📍 Have you reached the venue? Confirm arrival for ₹99 refund.';

      actionsList = [
        NotificationAction(
          label: "I'M HERE",
          icon: Icons.pin_drop_rounded,
          isPrimary: true,
          onTap: () => PartyPlanArrivalDialog.showArrivalPrompt(
            context,
            plan: planMap,
            isHost: isHost,
            onUpdate: () => _loadFeed(showLoader: false),
          ),
        ),
        NotificationAction(
          label: 'NOT YET',
          icon: Icons.schedule_rounded,
          isPrimary: false,
          color: Colors.grey[200],
          onTap: () async {
            final uid = ApiService.currentUserId ?? '';
            await ApiService.confirmArrival(planId: planId, userId: uid, hasArrived: false);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Recorded: NOT YET. Confirm when you reach to unlock your ₹99 refund.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            _loadFeed(showLoader: false);
          },
        ),
      ];
    } else if (isHost) {
      if (hostPaymentStatus != 'paid' && hostPaymentStatus != 'completed') {
        final double depositAmt = (planMap['depositAmount'] ?? 99.0) is num ? (planMap['depositAmount'] ?? 99.0).toDouble() : 99.0;
        final hostOrderId = planMap['hostRazorpayOrderId']?.toString() ?? '';
        title = '⚡ Action Required: Pay Host Deposit';
        badge = 'ACTION REQUIRED';
        accent = const Color(0xFF8B5CF6);
        body = 'Pay deposit of ₹${depositAmt.toStringAsFixed(0)} to publish your Party Plan at $venueName!';
        actionsList = [
          NotificationAction(
            label: 'Pay Deposit (${depositAmt.toStringAsFixed(0)})',
            icon: Icons.payment_rounded,
            isPrimary: true,
            onTap: () async {
              await _startHostRazorpayDirectPaymentInLiveFeed(
                partyPlanId: planId,
                venueName: venueName,
                orderId: hostOrderId,
                depositAmount: depositAmt,
                onSuccess: () async => _loadFeed(),
              );
            },
          ),
          NotificationAction(
            label: 'View Plan',
            icon: Icons.open_in_new_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PartyPlanDetailScreen(plan: planMap)),
            ),
          ),
        ];
      } else if (isConfirmed) {
        final joiner = (acceptedJoinerRequest != null && acceptedJoinerRequest['requester'] is Map)
            ? acceptedJoinerRequest['requester'] as Map<String, dynamic>
            : <String, dynamic>{};
        final joinerName = '${joiner["firstName"] ?? "Party Partner"} ${joiner["lastName"] ?? ""}'.trim();
        final joinerPhoto = joiner['profileImageUrl'] ?? joiner['profilePhotoUrl'];
        final joinerId = joiner['id'] ?? acceptedJoinerRequest?['requesterId'] ?? '';

        title = '🎉 Match Confirmed!';
        badge = 'CONFIRMED';
        accent = const Color(0xFF10B981);
        body = 'Party with $joinerName at $venueName is confirmed! Chat & Ticket unlocked.';
        senderUser = joiner.isNotEmpty ? joiner : hostCreator;
        avatarUrl = joinerPhoto ?? hostPhoto;

        actionsList = [
          NotificationAction(
            label: 'View Ticket',
            icon: Icons.confirmation_number_rounded,
            isPrimary: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanTicketScreen(
                  request: acceptedJoinerRequest ?? planMap,
                  plan: planMap,
                  isHost: true,
                ),
              ),
            ),
          ),
          NotificationAction(
            label: 'Chat',
            icon: Icons.chat_bubble_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  user: {
                    'id': joinerId,
                    'firstName': joiner['firstName'] ?? 'Party Partner',
                    'lastName': joiner['lastName'] ?? '',
                    'profilePhotoUrl': joinerPhoto,
                  },
                ),
              ),
            ),
          ),
          NotificationAction(
            label: 'Cancel Plan',
            icon: Icons.cancel_outlined,
            isPrimary: false,
            color: Colors.red[50],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PartyPlanDetailScreen(plan: planMap)),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
        ];
      } else if (acceptedJoinerRequest != null && (acceptedJoinerRequest['status'] == 'accepted' || acceptedJoinerRequest['status'] == 'payment_pending')) {
        final joiner = (acceptedJoinerRequest['requester'] is Map) ? acceptedJoinerRequest['requester'] as Map<String, dynamic> : <String, dynamic>{};
        final joinerName = '${joiner["firstName"] ?? "Participant"} ${joiner["lastName"] ?? ""}'.trim();
        final reqId = acceptedJoinerRequest['id']?.toString() ?? '';

        title = '⏳ Approved — Awaiting Payment';
        badge = 'AWAITING PAYMENT';
        body = 'You approved $joinerName. Waiting for deposit payment to unlock chat.';
        actionsList = [
          NotificationAction(
            label: 'Revoke',
            icon: Icons.cancel_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () => _handleRejectPartyPlan(reqId),
          ),
          NotificationAction(
            label: 'View Plan',
            icon: Icons.open_in_new_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PartyPlanDetailScreen(plan: planMap)),
            ),
          ),
        ];
      } else if (pendingIncomingRequests.isNotEmpty) {
        if (pendingIncomingRequests.length == 1) {
          final firstReq = pendingIncomingRequests.first;
          final reqUser = (firstReq['requester'] is Map) ? firstReq['requester'] as Map<String, dynamic> : <String, dynamic>{};
          final reqUserName = '${reqUser["firstName"] ?? "A user"} ${reqUser["lastName"] ?? ""}'.trim();
          final reqId = firstReq['id']?.toString() ?? '';

          title = '📥 New Party Plan Request';
          badge = 'NEW REQUEST';
          body = '$reqUserName requested to join your Party Plan at $venueName';
          senderUser = reqUser.isNotEmpty ? reqUser : hostCreator;
          avatarUrl = reqUser['profileImageUrl'] ?? reqUser['profilePhotoUrl'];

          actionsList = [
            NotificationAction(
              label: 'Approve',
              icon: Icons.check_circle_rounded,
              isPrimary: true,
              onTap: () => _handleAcceptPartyPlan(reqId),
            ),
            NotificationAction(
              label: 'Reject',
              icon: Icons.cancel_rounded,
              isPrimary: false,
              color: Colors.grey[200],
              onTap: () => _handleRejectPartyPlan(reqId),
            ),
          ];
        } else {
          title = '📥 Join Requests Received';
          badge = 'REQUESTS (${pendingIncomingRequests.length})';
          body = '${pendingIncomingRequests.length} users requested to join your Party Plan at $venueName';
          actionsList = [
            NotificationAction(
              label: 'Review Requests (${pendingIncomingRequests.length})',
              icon: Icons.people_alt_rounded,
              isPrimary: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PartyPlanDetailScreen(plan: planMap)),
              ).then((_) => _loadFeed(showLoader: false)),
            ),
          ];
        }
      } else {
        title = '🎉 Your Party Plan is Live!';
        badge = 'LIVE';
        body = formattedDateTime.isNotEmpty
            ? 'Open for join requests at $venueName • $formattedDateTime'
            : 'Your Party Plan at $venueName is live and open for requests!';
        actionsList = [
          NotificationAction(
            label: 'View Plan',
            icon: Icons.open_in_new_rounded,
            isPrimary: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PartyPlanDetailScreen(plan: planMap)),
            ),
          ),
          NotificationAction(
            label: 'Cancel Plan',
            icon: Icons.cancel_outlined,
            isPrimary: false,
            color: Colors.red[50],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PartyPlanDetailScreen(plan: planMap)),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
        ];
      }
    } else {
      final planVis = planMap['visibility']?.toString().toUpperCase() ?? '';
      final selectedUsers = planMap['selectedUsers'];
      final bool isPrivateInvite = planVis == 'PRIVATE' &&
          selectedUsers is List &&
          selectedUsers.any((u) => u?.toString() == currentUserId);

      final myStatus = (myRequest?['status'] ?? '').toString().toLowerCase();

      if (isConfirmed) {
        title = '🎉 Match Confirmed!';
        badge = 'CONFIRMED';
        accent = const Color(0xFF10B981);
        body = 'Party booking at $venueName is confirmed! Chat is unlocked with $hostName.';
        final otherId = planHostId.isNotEmpty ? planHostId : (hostCreator['id'] ?? '');

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
                    'firstName': hostCreator['firstName'] ?? hostName,
                    'lastName': hostCreator['lastName'] ?? '',
                    'profilePhotoUrl': hostPhoto,
                  },
                ),
              ),
            ),
          ),
          NotificationAction(
            label: 'Cancel Party Plan',
            icon: Icons.cancel_outlined,
            isPrimary: false,
            color: Colors.red[50],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PartyPlanDetailScreen(plan: planMap)),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
        ];
      } else if (myStatus == 'accepted' || myStatus == 'payment_pending') {
        final reqId = myRequest?['id']?.toString() ?? '';
        title = '✅ Approved! Pay Safety Deposit';
        badge = 'ACTION REQUIRED';
        accent = const Color(0xFF8B5CF6);
        body = '$hostName accepted your request! Pay the safety deposit to lock your spot.';

        actionsList = [
          NotificationAction(
            label: countdownLabel,
            icon: Icons.payment_rounded,
            isPrimary: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PartyPlanDetailScreen(plan: planMap)),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
          NotificationAction(
            label: 'Withdraw Request',
            icon: Icons.cancel_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () => _handleCancelMyRequest(reqId),
          ),
        ];
      } else if (isPrivateInvite && (myStatus == 'pending' || myStatus.isEmpty)) {
        final reqId = myRequest?['id']?.toString() ?? planId;
        title = '💌 Private Party Invite!';
        badge = 'INVITE';
        accent = const Color(0xFF7C3AED);
        body = '$hostName privately invited you to their Party Plan at $venueName. Accept to proceed!';

        actionsList = [
          NotificationAction(
            label: 'Accept',
            icon: Icons.check_circle_rounded,
            isPrimary: true,
            onTap: () => _handleAcceptPartyPlanInvite(reqId),
          ),
          NotificationAction(
            label: 'Decline',
            icon: Icons.cancel_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () => _handleRejectPartyPlan(reqId),
          ),
        ];
      } else if (myStatus == 'pending') {
        final reqId = myRequest?['id']?.toString() ?? '';
        title = '🤝 Request Sent';
        badge = 'REQUEST SENT';
        body = 'Request sent to $hostName for Party Plan at $venueName. Waiting for host approval.';
        actionsList = [
          NotificationAction(
            label: 'Withdraw Request',
            icon: Icons.cancel_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () => _handleCancelMyRequest(reqId),
          ),
        ];
      } else if (myStatus == 'rejected' || myStatus == 'declined') {
        title = '❌ Request Declined';
        badge = 'DECLINED';
        accent = const Color(0xFF9CA3AF);
        body = 'Your Party Plan request at $venueName was declined by $hostName.';
        actionsList = null;
      } else if (myStatus == 'withdrawn') {
        title = '↩️ Request Withdrawn';
        badge = 'WITHDRAWN';
        accent = const Color(0xFF9CA3AF);
        body = 'You withdrew your request for Party Plan at $venueName.';
        actionsList = null;
      } else {
        title = '🎉 Party Plan at $venueName';
        badge = 'PARTY PLAN';
        body = formattedDateTime.isNotEmpty
            ? '$hostName is hosting • $formattedDateTime'
            : '$hostName is hosting a Party Plan at $venueName.';
        actionsList = [
          NotificationAction(
            label: 'Request to Join',
            icon: Icons.person_add_rounded,
            isPrimary: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PartyPlanDetailScreen(plan: planMap)),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
        ];
      }
    }

    DateTime latestCreatedAt = DateTime(2000);
    bool allRead = true;
    for (final e in entries) {
      final dt = _parseDateTime(e['createdAt'] ?? e['postedAt']);
      if (dt.isAfter(latestCreatedAt)) latestCreatedAt = dt;
      final eId = e['id']?.toString() ?? '';
      final read = e['read'] == true || e['isRead'] == true || _localReadNotificationIds.contains(eId);
      if (!read) allRead = false;
    }
    if (_localReadNotificationIds.contains('pp_$planId')) {
      allRead = true;
    }
    if (badge == 'ACTION REQUIRED' || badge == 'INVITE') {
      allRead = false;
    }

    return UnifiedNotificationItem(
      id: 'pp_$planId',
      category: 'party_plan',
      title: title,
      body: body,
      createdAt: latestCreatedAt,
      timeAgo: _formatTimeAgo(latestCreatedAt),
      isRead: allRead,
      isExpired: isExpired,
      badgeText: badge,
      accentColor: accent,
      categoryIcon: Icons.celebration_rounded,
      avatarUrl: avatarUrl,
      senderUser: senderUser,
      actions: isExpired ? null : actionsList,
      rawData: {'id': planId, 'plan': planMap, ...planMap},
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build Authoritative Stranger Meet Smart Card (1 Stranger Meet = 1 Card)
  // ─────────────────────────────────────────────────────────────────────────────
  UnifiedNotificationItem? _buildAuthoritativeStrangersMeetCard(
    String meetId,
    List<Map<String, dynamic>> entries,
    String currentUserId,
  ) {
    if (entries.isEmpty) return null;

    Map<String, dynamic> meetMap = {};
    for (final e in entries) {
      if (e['planDetails'] is Map && (e['planDetails'] as Map).isNotEmpty) {
        meetMap = Map<String, dynamic>.from(e['planDetails']);
        break;
      } else if (e['plan'] is Map && (e['plan'] as Map).isNotEmpty) {
        meetMap = Map<String, dynamic>.from(e['plan']);
        break;
      } else if (e['requestType'] == 'stranger_meet' || e['category'] == 'stranger_meet') {
        meetMap = Map<String, dynamic>.from(e);
        break;
      }
    }
    if (meetMap.isEmpty) {
      final first = entries.first;
      if (first['data'] is Map && (first['data'] as Map).isNotEmpty) {
        meetMap = Map<String, dynamic>.from(first['data']);
      } else {
        meetMap = Map<String, dynamic>.from(first);
      }
    }
    meetMap['id'] = meetMap['id'] ?? meetId;

    final venue = (meetMap['venue'] is Map)
        ? meetMap['venue'] as Map<String, dynamic>
        : <String, dynamic>{};
    final venueName = venue['name']?.toString() ?? meetMap['venueName']?.toString() ?? 'Venue';

    final hostCreator = (meetMap['user'] is Map)
        ? meetMap['user'] as Map<String, dynamic>
        : (meetMap['host'] is Map
            ? meetMap['host'] as Map<String, dynamic>
            : <String, dynamic>{});
    final hostName = '${hostCreator["firstName"] ?? meetMap["hostName"] ?? "Host"} ${hostCreator["lastName"] ?? ""}'.trim();
    final hostPhoto = hostCreator['profileImageUrl']?.toString() ?? hostCreator['profilePhotoUrl']?.toString() ?? hostCreator['photoUrl']?.toString();

    final String meetHostId = (meetMap['userId'] ?? hostCreator['id'] ?? '').toString();
    final bool isHost = currentUserId.isNotEmpty && (meetHostId == currentUserId || meetMap['role'] == 'host');

    Map<String, dynamic>? myRequest;
    final List<Map<String, dynamic>> pendingIncomingRequests = [];
    Map<String, dynamic>? paidJoinerRecord;

    for (final e in entries) {
      final reqType = (e['type'] ?? e['requestType'] ?? '').toString();
      final status = (e['status'] ?? '').toString().toLowerCase();
      final pStatus = (e['joinerPaymentStatus'] ?? e['paymentStatus'] ?? '').toString().toLowerCase();

      if (reqType == 'my_request' || reqType == 'stranger_meet_join' || e['userId']?.toString() == currentUserId) {
        myRequest = e;
      }
      if (reqType == 'incoming_request' || (isHost && e['requester'] != null)) {
        if (status == 'pending') {
          pendingIncomingRequests.add(e);
        } else if (status == 'paid' || pStatus == 'paid') {
          paidJoinerRecord = e;
        }
      }
      if (status == 'paid' || pStatus == 'paid') {
        paidJoinerRecord = e;
      }
    }

    String formattedDateTime = '';
    final rawDateTime = meetMap['eventDateTime'] ?? meetMap['planDate'] ?? meetMap['partyDate'];
    DateTime? parsedEventDate;
    if (rawDateTime != null) {
      try {
        parsedEventDate = DateTime.parse(rawDateTime.toString()).toLocal();
        const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final w = weekdayNames[parsedEventDate.weekday - 1];
        final m = monthNames[parsedEventDate.month - 1];
        final hour = parsedEventDate.hour % 12 == 0 ? 12 : parsedEventDate.hour % 12;
        final ampm = parsedEventDate.hour >= 12 ? 'PM' : 'AM';
        final minute = parsedEventDate.minute.toString().padLeft(2, '0');
        formattedDateTime = '$w, ${parsedEventDate.day} $m • $hour:$minute $ampm';
      } catch (_) {}
    }

    bool isExpired = false;
    if (parsedEventDate != null && parsedEventDate.isBefore(DateTime.now())) {
      isExpired = true;
    }
    final meetStatus = (meetMap['status'] ?? '').toString().toLowerCase();
    if (meetStatus == 'completed' || meetStatus == 'expired' || meetStatus == 'cancelled') {
      if (meetStatus == 'expired') isExpired = true;
    }

    final double chargesPerHead = (meetMap['chargesPerHead'] ?? myRequest?['chargesPerHead'] ?? 0.0) is num
        ? (meetMap['chargesPerHead'] ?? myRequest?['chargesPerHead'] ?? 0.0).toDouble()
        : 0.0;

    Color accent = const Color(0xFF6366F1);
    String title = '🤝 Stranger Meet at $venueName';
    String body = formattedDateTime.isNotEmpty ? '📅 $formattedDateTime' : 'Stranger Meet at $venueName';
    String badge = 'STRANGER MEET';
    List<NotificationAction>? actionsList;
    Map<String, dynamic>? senderUser = hostCreator;
    String? avatarUrl = hostPhoto;

    if (isExpired) {
      accent = const Color(0xFF9CA3AF);
      badge = 'EXPIRED';
      body = 'This Stranger Meet at $venueName has ended/expired.';
      actionsList = null;
    } else if (isHost) {
      final hostPayStatus = (meetMap['paymentStatus'] ?? '').toString().toLowerCase();
      if (hostPayStatus == 'unpaid' || hostPayStatus == 'pending') {
        title = '⚡ Action Required: Pay Host Deposit';
        badge = 'ACTION REQUIRED';
        accent = const Color(0xFF8B5CF6);
        final double deposit = (meetMap['paymentAmount'] ?? 99.0) is num ? (meetMap['paymentAmount'] ?? 99.0).toDouble() : 99.0;
        body = 'Pay deposit of ₹${deposit.toStringAsFixed(0)} to make your Stranger Meet live at $venueName!';
        actionsList = [
          NotificationAction(
            label: 'Pay Deposit',
            icon: Icons.payment_rounded,
            isPrimary: true,
            onTap: () {
              try {
                final req = StrangersMeetRequest.fromJson(meetMap);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StrangersMeetPaymentScreen(
                      request: req,
                      onPaymentSuccess: () => _loadFeed(),
                      isJoinPayment: false,
                    ),
                  ),
                );
              } catch (e) {
                debugPrint('Error parsing SM host payment: $e');
              }
            },
          ),
        ];
      } else if (pendingIncomingRequests.isNotEmpty) {
        if (pendingIncomingRequests.length == 1) {
          final firstReq = pendingIncomingRequests.first;
          final reqUser = (firstReq['requester'] is Map) ? firstReq['requester'] as Map<String, dynamic> : <String, dynamic>{};
          final reqUserName = '${reqUser["firstName"] ?? "A user"} ${reqUser["lastName"] ?? ""}'.trim();
          final joinerId = firstReq['id']?.toString() ?? '';

          title = '📥 Join Request Received';
          badge = 'NEW REQUEST';
          body = '$reqUserName requested to join your Stranger Meet at $venueName';
          senderUser = reqUser.isNotEmpty ? reqUser : hostCreator;
          avatarUrl = reqUser['profileImageUrl'] ?? reqUser['profilePhotoUrl'];

          actionsList = [
            NotificationAction(
              label: 'Accept',
              icon: Icons.check_circle_rounded,
              isPrimary: true,
              onTap: () => _handleStrangersMeetJoinAction(meetId, joinerId, 'accept'),
            ),
            NotificationAction(
              label: 'Decline',
              icon: Icons.cancel_rounded,
              isPrimary: false,
              color: Colors.grey[200],
              onTap: () => _handleStrangersMeetJoinAction(meetId, joinerId, 'reject'),
            ),
          ];
        } else {
          title = '📥 Join Requests Received';
          badge = 'REQUESTS (${pendingIncomingRequests.length})';
          body = '${pendingIncomingRequests.length} users requested to join your Stranger Meet at $venueName';
          actionsList = [
            NotificationAction(
              label: 'Review Requests',
              icon: Icons.people_alt_rounded,
              isPrimary: true,
              onTap: () => _loadFeed(showLoader: false),
            ),
          ];
        }
      } else if (paidJoinerRecord != null) {
        final joiner = (paidJoinerRecord['requester'] is Map) ? paidJoinerRecord['requester'] as Map<String, dynamic> : <String, dynamic>{};
        final joinerName = '${joiner["firstName"] ?? "Participant"} ${joiner["lastName"] ?? ""}'.trim();
        final joinerId = joiner['id']?.toString() ?? '';
        final joinerPhoto = joiner['profileImageUrl']?.toString() ?? joiner['profilePhotoUrl']?.toString();

        title = '🎉 Seat Confirmed!';
        badge = 'CONFIRMED';
        accent = const Color(0xFF10B981);
        body = '$joinerName\'s seat at $venueName is locked! Chat unlocked.';
        senderUser = joiner.isNotEmpty ? joiner : hostCreator;
        avatarUrl = joinerPhoto ?? hostPhoto;

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
                    'id': joinerId,
                    'firstName': joiner['firstName'] ?? 'Participant',
                    'lastName': joiner['lastName'] ?? '',
                    'profilePhotoUrl': joinerPhoto,
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
              try {
                final req = StrangersMeetRequest.fromJson(meetMap);
                Navigator.push(context, MaterialPageRoute(builder: (_) => StrangersMeetTicketScreen(request: req)));
              } catch (e) {
                debugPrint('Error parsing SM ticket: $e');
              }
            },
          ),
        ];
      } else {
        title = '🤝 Your Stranger Meet is Live!';
        badge = 'LIVE';
        body = formattedDateTime.isNotEmpty
            ? 'Open for requests at $venueName • $formattedDateTime'
            : 'Your Stranger Meet at $venueName is live!';
        actionsList = [
          NotificationAction(
            label: 'View Ticket',
            icon: Icons.confirmation_number_rounded,
            isPrimary: true,
            onTap: () {
              try {
                final req = StrangersMeetRequest.fromJson(meetMap);
                Navigator.push(context, MaterialPageRoute(builder: (_) => StrangersMeetTicketScreen(request: req)));
              } catch (e) {
                debugPrint('Error parsing SM ticket: $e');
              }
            },
          ),
        ];
      }
    } else {
      final myStatus = (myRequest?['status'] ?? '').toString().toLowerCase();
      final myPaymentStatus = (myRequest?['joinerPaymentStatus'] ?? myRequest?['paymentStatus'] ?? '').toString().toLowerCase();

      if (myStatus == 'paid' || myPaymentStatus == 'paid') {
        title = '🎉 Meet Confirmed!';
        badge = 'CONFIRMED';
        accent = const Color(0xFF10B981);
        body = 'Payment done! Your seat at $venueName is locked. Chat unlocked with $hostName.';
        final otherId = meetHostId.isNotEmpty ? meetHostId : (hostCreator['id'] ?? '');

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
                    'firstName': hostCreator['firstName'] ?? hostName,
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
              try {
                final req = StrangersMeetRequest.fromJson(meetMap);
                Navigator.push(context, MaterialPageRoute(builder: (_) => StrangersMeetTicketScreen(request: req)));
              } catch (e) {
                debugPrint('Error parsing SM ticket: $e');
              }
            },
          ),
        ];
      } else if (myStatus == 'accepted' || myStatus == 'payment_pending') {
        final feeLabel = chargesPerHead > 0 ? '₹${chargesPerHead.toStringAsFixed(0)}' : 'Entry Fee';
        title = '✅ Accepted! Pay Entry Fee';
        badge = 'ACTION REQUIRED';
        accent = const Color(0xFFF59E0B);
        body = '$hostName accepted your request! Pay $feeLabel to secure your spot at $venueName.';

        actionsList = [
          NotificationAction(
            label: 'Pay $feeLabel',
            icon: Icons.payment_rounded,
            isPrimary: true,
            onTap: () {
              try {
                final req = StrangersMeetRequest.fromJson(meetMap);
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
                debugPrint('Error opening SM join payment: $e');
              }
            },
          ),
        ];
      } else if (myStatus == 'pending') {
        title = '🤝 Request Sent';
        badge = 'REQUEST SENT';
        body = 'Request sent to $hostName for Stranger Meet at $venueName. Waiting for host approval.';
        actionsList = null;
      } else if (myStatus == 'rejected' || myStatus == 'declined') {
        title = '❌ Request Declined';
        badge = 'DECLINED';
        accent = const Color(0xFF9CA3AF);
        body = 'Your request to join Stranger Meet at $venueName was declined by $hostName.';
        actionsList = null;
      } else {
        title = '🤝 Stranger Meet at $venueName';
        badge = 'STRANGER MEET';
        body = formattedDateTime.isNotEmpty
            ? '$hostName is hosting • $formattedDateTime'
            : '$hostName is hosting a Stranger Meet at $venueName.';
        actionsList = null;
      }
    }

    DateTime latestCreatedAt = DateTime(2000);
    bool allRead = true;
    for (final e in entries) {
      final dt = _parseDateTime(e['createdAt'] ?? e['postedAt']);
      if (dt.isAfter(latestCreatedAt)) latestCreatedAt = dt;
      final eId = e['id']?.toString() ?? '';
      final read = e['read'] == true || e['isRead'] == true || _localReadNotificationIds.contains(eId);
      if (!read) allRead = false;
    }
    if (_localReadNotificationIds.contains('sm_$meetId')) {
      allRead = true;
    }
    if (badge == 'ACTION REQUIRED' || badge == 'NEW REQUEST') {
      allRead = false;
    }

    return UnifiedNotificationItem(
      id: 'sm_$meetId',
      category: 'stranger_meet',
      title: title,
      body: body,
      createdAt: latestCreatedAt,
      timeAgo: _formatTimeAgo(latestCreatedAt),
      isRead: allRead,
      isExpired: isExpired,
      badgeText: badge,
      accentColor: accent,
      categoryIcon: Icons.people_alt_rounded,
      avatarUrl: avatarUrl,
      senderUser: senderUser,
      actions: isExpired ? null : actionsList,
      rawData: {'id': meetId, 'plan': meetMap, ...meetMap},
    );
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

