// ignore_for_file: use_build_context_synchronously, unused_local_variable
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
import '../../services/push_notification_service.dart';
import 'strangers_meet_payment_screen.dart';
import 'strangers_meet_ticket_screen.dart';
import 'chat_screen.dart';
import 'large_party_ticket_screen.dart';
import 'notification_center_screen.dart';
import '../../widgets/top_notification_banner.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

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
  late TabController _tabController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  List<Map<String, dynamic>> _feedItems = [];
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _largePartyBookings = [];
  bool _isLoading = true;
  bool _isLoadingGroupParties = false;
  Timer? _pollingTimer;

  // Sub-filter selection states for tabs
  int _subFilterIndexTab0 =
      0; // Stranger Meet: 0: All, 1: Requests, 2: Bookings, 3: Chats, 4: Activity
  int _subFilterIndexTab1 =
      0; // Party Plan: 0: All, 1: Requests, 2: Bookings, 3: Chats, 4: Activity
  int _subFilterIndexTab2 =
      0; // Group Parties: 0: All, 1: Invites, 2: Joined, 3: Bookings, 4: Activity
  int _subFilterIndexTab3 =
      0; // Other: 0: All, 1: System, 2: Alerts, 3: Activity

  // Razorpay for large party payments
  Razorpay? _razorpay;
  String? _pendingLargePartyBookingId;

  // Track optimistic state changes for buttons
  final Map<String, String> _optimisticStates = {};
  final Set<String> _clearedFeedItemIds = {};

  String _sanitizeDisplayText(String rawText) {
    if (rawText.isEmpty || rawText == 'null' || rawText == 'undefined') {
      return '';
    }
    final trimmed = rawText.trim();
    // Check if string is a raw UUID or random debug code (e.g. rxtxc6c6, hcidhdhd)
    final isUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(trimmed);
    final isRandomCode =
        RegExp(r'^[a-z0-9]{6,10}$').hasMatch(trimmed) && !trimmed.contains(' ');
    if (isUuid || isRandomCode) {
      return '';
    }
    return trimmed;
  }

  void refreshFeed() {
    _loadFeed(showLoader: false);
    _loadGroupPartyBookings();
  }

  List<Map<String, dynamic>> _getJoinRequestsForMeet(String meetId) {
    return _feedItems
        .where(
          (i) =>
              i['type'] == 'incoming_request' &&
              i['requestType'] == 'stranger_meet' &&
              i['planId']?.toString() == meetId,
        )
        .toList();
  }

  Set<String> get _readRequestIds => ApiService.localReadRequestIds;
  Set<String> get _localReadNotificationIds =>
      ApiService.localReadNotificationIds;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(_handleTabChange);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
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
    _tabController.removeListener(_handleTabChange);
    _pollingTimer?.cancel();
    _pulseController.dispose();
    _tabController.dispose();
    _razorpay?.clear();
    super.dispose();
  }

  void _initSocketListeners() {
    ApiService.addSocketListener('party_plan_created', _onPartyPlanCreated);
    ApiService.addSocketListener('party_plan_deleted', _onPartyPlanDeleted);
    ApiService.addSocketListener(
      'party_plan_request_accepted',
      _onPartyPlanRequestAccepted,
    );
    ApiService.addSocketListener(
      'party_plan_match_success',
      _onPartyPlanMatchSuccess,
    );
    ApiService.addSocketListener('party_plan_host_paid', _onPartyPlanHostPaid);
    ApiService.addSocketListener(
      'party_plan_joiner_paid',
      _onPartyPlanJoinerPaid,
    );
    ApiService.addSocketListener('plan_unavailable', _onPlanUnavailable);
    ApiService.addSocketListener(
      'notification_created',
      _onNotificationCreated,
    );
    ApiService.addSocketListener(
      'group_party_payment_success',
      _onGroupPartyUpdated,
    );
    ApiService.addSocketListener(
      'large_party_status_update',
      _onGroupPartyUpdated,
    );
    ApiService.addSocketListener(
      'group_party_status_update',
      _onGroupPartyUpdated,
    );
  }

  void _disposeSocketListeners() {
    ApiService.removeSocketListener('party_plan_created', _onPartyPlanCreated);
    ApiService.removeSocketListener('party_plan_deleted', _onPartyPlanDeleted);
    ApiService.removeSocketListener(
      'party_plan_request_accepted',
      _onPartyPlanRequestAccepted,
    );
    ApiService.removeSocketListener(
      'party_plan_match_success',
      _onPartyPlanMatchSuccess,
    );
    ApiService.removeSocketListener(
      'party_plan_host_paid',
      _onPartyPlanHostPaid,
    );
    ApiService.removeSocketListener(
      'party_plan_joiner_paid',
      _onPartyPlanJoinerPaid,
    );
    ApiService.removeSocketListener('plan_unavailable', _onPlanUnavailable);
    ApiService.removeSocketListener(
      'notification_created',
      _onNotificationCreated,
    );
    ApiService.removeSocketListener(
      'group_party_payment_success',
      _onGroupPartyUpdated,
    );
    ApiService.removeSocketListener(
      'large_party_status_update',
      _onGroupPartyUpdated,
    );
    ApiService.removeSocketListener(
      'group_party_status_update',
      _onGroupPartyUpdated,
    );
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
    try {
      final map = Map<String, dynamic>.from(data);
      setState(() {
        final exists = _feedItems.any(
          (item) => item['id']?.toString() == map['id']?.toString(),
        );
        if (!exists) {
          _feedItems.insert(0, map);
        }
      });
    } catch (e) {
      debugPrint('Error handling party_plan_created: $e');
    }
  }

  void _onPartyPlanDeleted(dynamic data) {
    if (!mounted || !context.mounted) return;
    try {
      final planId = data['planId']?.toString();
      if (planId != null) {
        setState(() {
          _feedItems.removeWhere(
            (item) =>
                (item['planId']?.toString() == planId) ||
                (item['id']?.toString() == planId &&
                    item['type'] == 'party_plan') ||
                (item['plan'] != null &&
                    item['plan']['id']?.toString() == planId),
          );
        });
      }
    } catch (e) {
      debugPrint('Error handling party_plan_deleted: $e');
    }
  }

  void _onPartyPlanRequestAccepted(dynamic data) {
    if (!mounted || !context.mounted) return;
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
    if (!mounted || !context.mounted) return;
    try {
      final reqId = data['requestId']?.toString();
      final planId = data['planId']?.toString();
      setState(() {
        for (var item in _feedItems) {
          if (item['id']?.toString() == reqId ||
              (item['plan'] != null &&
                  item['plan']['id']?.toString() == planId)) {
            item['status'] = 'paid';
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '🎉 Party Match Confirmed! Both host and guest have paid.',
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      debugPrint('Error handling party_plan_match_success: $e');
    }
  }

  void _onPartyPlanHostPaid(dynamic data) {
    if (!mounted || !context.mounted) return;
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
    if (!mounted || !context.mounted) return;
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
    if (!mounted || !context.mounted) return;
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
          _feedItems.removeWhere(
            (item) =>
                (item['id']?.toString() == planId &&
                    item['type'] == 'party_plan') ||
                (item['plan'] != null &&
                    item['plan']['id']?.toString() == planId &&
                    item['status'] != 'accepted' &&
                    item['status'] != 'paid'),
          );
        }
      });
    } catch (e) {
      debugPrint('Error handling plan_unavailable: $e');
    }
  }

  // ── Group Party (Large Party) loading ─────────────────────────────────────

  Future<void> _loadGroupPartyBookings() async {
    if (_isLoadingGroupParties) return;
    setState(() => _isLoadingGroupParties = true);
    try {
      final bookings = await ApiService.fetchMyLargePartyBookings();
      if (mounted) {
        setState(() {
          _largePartyBookings = bookings;
          _isLoadingGroupParties = false;
        });
        widget.onCountChanged?.call();
      }
    } catch (e) {
      debugPrint('Error loading group party bookings: $e');
      if (mounted) setState(() => _isLoadingGroupParties = false);
    }
  }

  // ── Razorpay handlers for large party payments ─────────────────────────────

  Future<void> _initiateLargePartyPayment(Map<String, dynamic> booking) async {
    final bookingId =
        booking['id']?.toString() ?? booking['bookingId']?.toString();
    if (bookingId == null) return;

    try {
      final result = await ApiService.initiateLargePartyPayment(bookingId);
      if (!mounted || !context.mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to initiate payment. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final orderData = result['order'] ?? result['data'] ?? result;
      final razorpayKey =
          result['razorpayKeyId']?.toString() ??
          orderData['key']?.toString() ??
          '';
      _pendingLargePartyBookingId = bookingId;

      bool razorpayOpened = false;
      try {
        _razorpay?.open({
          'key': razorpayKey,
          'order_id':
              orderData['razorpayOrderId']?.toString() ??
              orderData['id']?.toString(),
          'amount': orderData['amount'],
          'name': 'Lunara – Group Party',
          'description':
              'Group Party at ${booking['venue']?['name'] ?? booking['venueName'] ?? 'venue'}',
          'prefill': {'contact': booking['mobileNumber']?.toString() ?? ''},
          'theme': {'color': '#7C3AED'},
        });
        razorpayOpened = true;
      } catch (e) {
        debugPrint('Error opening Razorpay, falling back to simulation: $e');
      }

      if (!razorpayOpened) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(
            child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
          ),
        );
        Future.delayed(const Duration(seconds: 2), () async {
          if (!mounted || !context.mounted) return;
          Navigator.pop(context); // Close loader
          _handleLargePartySuccess(
            paymentId: 'mock_payment',
            orderId:
                orderData['razorpayOrderId']?.toString() ??
                orderData['id']?.toString() ??
                'mock_order_id',
            signature: 'mock_signature',
          );
        });
      }
    } catch (e) {
      debugPrint('_initiateLargePartyPayment error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onLargePartyPaymentSuccess(PaymentSuccessResponse response) async {
    _handleLargePartySuccess(
      paymentId: response.paymentId ?? '',
      orderId: response.orderId ?? '',
      signature: response.signature ?? '',
    );
  }

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
        // Refresh bookings and show success
        await _loadGroupPartyBookings();
        TopNotificationBanner.show(
          title: 'Group Party Confirmed! 🎉',
          body: 'Your payment was verified successfully. Tap to view your ticket!',
          data: {'type': 'group_party_confirmed', 'partyId': bookingId},
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🎉 Payment Successful! Your group party is confirmed.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
        // Navigate to ticket
        final updated = _largePartyBookings.firstWhere(
          (b) => (b['id'] ?? b['bookingId'])?.toString() == bookingId,
          orElse: () => {'id': bookingId},
        );
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LargePartyTicketScreen(
                booking: updated,
                venue: Map<dynamic, dynamic>.from(
                  updated['venue'] is Map ? updated['venue'] : {},
                ),
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment verification failed. Please contact support.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('_onLargePartyPaymentSuccess error: $e');
    }
  }

  void _onLargePartyPaymentError(PaymentFailureResponse response) {
    _pendingLargePartyBookingId = null;
    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message ?? 'Unknown error'}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _onLargePartyExternalWallet(ExternalWalletResponse response) {
    _pendingLargePartyBookingId = null;
    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('External wallet selected: ${response.walletName}'),
      ),
    );
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 3) {
      markAllNotificationsAsRead();
    }
    _markCurrentTabItemsAsRead();
  }

  void _markCurrentTabItemsAsRead() {
    widget.onCountChanged?.call();
  }

  Future<void> markAllNotificationsAsRead() async {
    final List<String> notifIdsToMark = [];
    for (var n in _notifications) {
      final nId = n['id']?.toString() ?? '';
      if (nId.isNotEmpty && !_localReadNotificationIds.contains(nId)) {
        _localReadNotificationIds.add(nId);
        notifIdsToMark.add(nId);
      }
    }
    final List<String> reqIdsToMark = [];
    for (var item in _feedItems) {
      final rId = item['id']?.toString() ?? '';
      if (rId.isNotEmpty && !_readRequestIds.contains(rId)) {
        _readRequestIds.add(rId);
        reqIdsToMark.add(rId);
      }
    }
    await ApiService.saveLocalReadNotificationIds();
    await ApiService.saveLocalReadRequestIds();

    if (mounted) {
      setState(() {
        for (var n in _notifications) {
          n['read'] = true;
          n['isRead'] = true;
        }
      });
      widget.onCountChanged?.call();
    }

    for (final nId in notifIdsToMark) {
      ApiService.markNotificationRead(nId);
    }
    for (final rId in reqIdsToMark) {
      ApiService.markRequestRead(rId);
    }
  }
  Future<void> _markNotificationAsRead(Map<String, dynamic> notif) async {
    final nId = notif['id']?.toString() ?? '';
    final isRead =
        notif['isRead'] == true ||
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

  Future<void> _handleNotificationCardTap(Map<String, dynamic> notif) async {
    await _markNotificationAsRead(notif);

    final Map<String, dynamic> payloadData = {};
    if (notif['data'] is Map) {
      payloadData.addAll(Map<String, dynamic>.from(notif['data']));
    }
    if (notif['metadata'] is Map) {
      payloadData.addAll(Map<String, dynamic>.from(notif['metadata']));
    }
    payloadData.addAll(notif);

    if (!payloadData.containsKey('type') && notif['eventType'] != null) {
      payloadData['type'] = notif['eventType'];
    }
    if (!payloadData.containsKey('requestId') && notif['entityId'] != null) {
      payloadData['requestId'] = notif['entityId'];
    }

    PushNotificationService.navigateFromPayload(payloadData);
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
          // Clean up optimistic states that are confirmed by the server
          for (final item in combined) {
            final id = item['id']?.toString();
            if (id != null && _optimisticStates.containsKey(id)) {
              final serverStatus = item['status']?.toString().toLowerCase();
              if (serverStatus != null && serverStatus != 'pending') {
                _optimisticStates.remove(id);
              }
            }
          }
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
        (plan['selectedUsers'] is List &&
            (plan['selectedUsers'] as List).contains(ApiService.currentUserId));
  }

  int get strangerMeetUnreadCount {
    return _feedItems.where((i) {
      final rType = i['requestType'];
      if (rType != 'table_plan' &&
          rType != 'stranger_meet' &&
          rType != 'stranger_meet_join') {
        return false;
      }
      if (_readRequestIds.contains(i['id']?.toString() ?? '')) return false;
      if (i['type'] == 'incoming_request' && i['status'] == 'pending') {
        return true;
      }
      if (i['type'] == 'my_request' && i['paymentStatus'] == 'pending') {
        return true;
      }
      return false;
    }).length;
  }

  int get partyPlanUnreadCount {
    return _feedItems.where((i) {
      if (i['requestType'] != 'party_plan') return false;
      if (_readRequestIds.contains(i['id']?.toString() ?? '')) return false;
      if (i['type'] == 'incoming_request' && i['status'] == 'pending') {
        return true;
      }
      final hostPaid =
          i['plan']?['hostPaymentStatus']?.toString().toLowerCase() == 'paid';
      final isSelfPay = i['paymentType'] == 'self_pay';
      final joinerPaid =
          i['joinerPaymentStatus']?.toString().toLowerCase() == 'paid';
      if ((i['type'] == 'my_request' || _isInvite(i)) &&
          !hostPaid &&
          !joinerPaid &&
          !isSelfPay &&
          i['status'] == 'payment_pending') {
        return true;
      }
      return false;
    }).length;
  }

  int get otherUnreadCount {
    return _notifications
        .where(
          (n) =>
              n['isRead'] != true &&
              n['read'] != true &&
              !_localReadNotificationIds.contains(n['id']?.toString() ?? ''),
        )
        .length;
  }

  int get groupPartyAwaitingCount {
    return _largePartyBookings.where((b) {
      final st = (b['status'] ?? b['bookingStatus'] ?? '')
          .toString()
          .toLowerCase();
      final pSt = (b['paymentStatus'] ?? b['hostPaymentStatus'] ?? '')
          .toString()
          .toLowerCase();
      return (st == 'approved' ||
              st == 'approved_awaiting_payment' ||
              st == 'awaiting_payment') &&
          pSt != 'paid';
    }).length;
  }

  int get totalUnreadCount =>
      strangerMeetUnreadCount +
      partyPlanUnreadCount +
      groupPartyAwaitingCount +
      otherUnreadCount;

  @override
  Widget build(BuildContext context) {
    final strangerMeetCount = strangerMeetUnreadCount;
    final partyPlanCount = partyPlanUnreadCount;
    final groupPartyCount = groupPartyAwaitingCount;
    final otherCount = otherUnreadCount;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, totalUnreadCount: totalUnreadCount),
            TabBar(
              controller: _tabController,
              labelColor: LunaraTheme.electricViolet,
              unselectedLabelColor: Colors.grey,
              indicatorColor: LunaraTheme.electricViolet,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              tabs: [
                Tab(
                  child: Badge(
                    isLabelVisible: strangerMeetCount > 0,
                    backgroundColor: LunaraTheme.electricViolet,
                    child: const Text('Stranger Meet'),
                  ),
                ),
                Tab(
                  child: Badge(
                    isLabelVisible: partyPlanCount > 0,
                    backgroundColor: LunaraTheme.electricViolet,
                    child: const Text('Party Plan'),
                  ),
                ),
                Tab(
                  child: Badge(
                    isLabelVisible: groupPartyCount > 0,
                    backgroundColor: Colors.orange,
                    child: const Text('Group Parties'),
                  ),
                ),
                Tab(
                  child: Badge(
                    isLabelVisible: otherCount > 0,
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
                        _buildGroupPartiesFeed(),
                        _buildNotificationsFeed(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {int totalUnreadCount = 0}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none_rounded, size: 24),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationCenterScreen(),
                    ),
                  );
                  await markAllNotificationsAsRead();
                  _loadFeed(showLoader: false);
                },
              ),
              if (totalUnreadCount > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Text(
                      totalUnreadCount > 9 ? '9+' : '$totalUnreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              if (totalUnreadCount > 0) ...[
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
                              alpha: _pulseAnimation.value * 0.6,
                            ),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
              ],
              Text(
                'LIVE FEED',
                style: LunaraTheme.headingStyle.copyWith(
                  fontSize: 18,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 24),
            onPressed: () {
              _loadFeed(showLoader: true);
            },
            tooltip: 'Search & Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeaderRow(String title) {
    return Padding(
      padding: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 12.0,
        bottom: 8.0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface,
              letterSpacing: 0.5,
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _markCurrentTabItemsAsRead,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.done_all_rounded,
                      color: LunaraTheme.electricViolet,
                      size: 15,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Mark all as read',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: LunaraTheme.electricViolet,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubFilterPills(
    List<String> options,
    int selectedIndex,
    ValueChanged<int> onSelected,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: options.asMap().entries.map((entry) {
          final isSelected = selectedIndex == entry.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelected(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? LunaraTheme.electricViolet
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? LunaraTheme.electricViolet
                        : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: LunaraTheme.electricViolet.withValues(
                              alpha: 0.25,
                            ),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
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

  Widget _buildWhyThisIsBetterBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 20, bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FE),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.15),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Why this is better?',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWhyItem(
                  Icons.bolt_rounded,
                  'Smart & Instant',
                  'Real-time updates so you never miss important actions.',
                  const Color(0xFF7F00FF),
                ),
                const SizedBox(width: 16),
                _buildWhyItem(
                  Icons.track_changes_rounded,
                  'Action Oriented',
                  'Clear actions right in the notification card.',
                  const Color(0xFFE100FF),
                ),
                const SizedBox(width: 16),
                _buildWhyItem(
                  Icons.layers_rounded,
                  'Organized',
                  'Filter by type to see what matters most to you.',
                  const Color(0xFF10B981),
                ),
                const SizedBox(width: 16),
                _buildWhyItem(
                  Icons.devices_rounded,
                  'Context Aware',
                  'Every notification shows the full context.',
                  const Color(0xFF0284C7),
                ),
                const SizedBox(width: 16),
                _buildWhyItem(
                  Icons.shield_outlined,
                  'Reliable & Secure',
                  'Only relevant notifications, no spam.',
                  const Color(0xFFF59E0B),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhyItem(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return SizedBox(
      width: 110,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9.5,
              color: Color(0xFF64748B),
              height: 1.2,
            ),
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

      final isMatch =
          type == 'table_plan' ||
          ((type == 'incoming_request' || type == 'my_request') &&
              (reqType == 'table_plan' ||
                  reqType == 'stranger_meet' ||
                  reqType == 'stranger_meet_join'));
      if (!isMatch) return false;

      // Apply sub-filter: 0: All, 1: Pending, 2: Incoming, 3: My Requests, 4: Confirmed
      if (_subFilterIndexTab0 == 1) {
        final status = item['status']?.toString().toLowerCase() ?? '';
        final pStatus = item['paymentStatus']?.toString().toLowerCase() ?? '';
        return status == 'pending' ||
            pStatus == 'pending' ||
            pStatus == 'unpaid';
      } else if (_subFilterIndexTab0 == 2) {
        return type == 'incoming_request';
      } else if (_subFilterIndexTab0 == 3) {
        return type == 'my_request';
      } else if (_subFilterIndexTab0 == 4) {
        final status = item['status']?.toString().toLowerCase() ?? '';
        return status == 'accepted' ||
            status == 'paid' ||
            status == 'confirmed';
      }
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: () => _loadFeed(showLoader: false),
      child: Column(
        children: [
          _buildSectionHeaderRow('Stranger Meets'),
          _buildSubFilterPills(
            ['All', 'Pending', 'Incoming', 'My Requests', 'Confirmed'],
            _subFilterIndexTab0,
            (idx) => setState(() => _subFilterIndexTab0 = idx),
          ),
          Expanded(
            child: _buildGroupedItemList(
              items: strangerItems,
              emptyText: 'No Stranger Meets active right now.',
              onRefresh: () => _loadFeed(showLoader: false),
              itemBuilder: (item) {
                if (item['type'] == 'incoming_request') {
                  return _buildIncomingRequestCard(item);
                }
                if (item['type'] == 'my_request') {
                  return _buildMyRequestCard(item);
                }
                return _buildPlanCard(item);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartyPlanFeed() {
    final confirmedPlanIds = <String>{};
    for (final item in _feedItems) {
      if ((item['type'] == 'my_request' ||
              item['type'] == 'incoming_request') &&
          item['requestType'] == 'party_plan') {
        final status = item['status']?.toString().toLowerCase() ?? '';
        if (status != 'rejected' && status != 'cancelled') {
          final planId = (item['plan']?['id'] ?? item['plan']?['planId'] ?? '')
              .toString();
          if (planId.isNotEmpty) confirmedPlanIds.add(planId);
        }
      }
    }

    final partyItems = _feedItems.where((item) {
      final type = item['type'];
      final reqType = item['requestType'];
      final id = item['id']?.toString() ?? '';
      if (_clearedFeedItemIds.contains(id)) return false;
      if (type == 'party_plan') {
        final planId = (item['planId'] ?? item['id'] ?? '').toString();
        if (confirmedPlanIds.contains(planId)) return false;
      }
      final isMatch =
          type == 'party_plan' ||
          ((type == 'incoming_request' || type == 'my_request') &&
              reqType == 'party_plan');
      if (!isMatch) return false;

      // Apply sub-filter: 0: All, 1: Pending, 2: Public Feed, 3: My Invites, 4: My Requests, 5: Confirmed
      if (_subFilterIndexTab1 == 1) {
        final status = item['status']?.toString().toLowerCase() ?? '';
        final pStatus = item['paymentStatus']?.toString().toLowerCase() ?? '';
        final jStatus =
            item['joinerPaymentStatus']?.toString().toLowerCase() ?? '';
        return status == 'pending' ||
            pStatus == 'pending' ||
            jStatus == 'unpaid' ||
            status == 'host_paid';
      } else if (_subFilterIndexTab1 == 2) {
        return type == 'party_plan';
      } else if (_subFilterIndexTab1 == 3) {
        return _isInvite(item);
      } else if (_subFilterIndexTab1 == 4) {
        return type == 'my_request';
      } else if (_subFilterIndexTab1 == 5) {
        final status = item['status']?.toString().toLowerCase() ?? '';
        return status == 'accepted' ||
            status == 'paid' ||
            status == 'confirmed';
      }
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: () => _loadFeed(showLoader: false),
      child: Column(
        children: [
          _buildSectionHeaderRow('Party Plans'),
          _buildSubFilterPills(
            [
              'All',
              'Pending',
              'Public Feed',
              'My Invites',
              'My Requests',
              'Confirmed',
            ],
            _subFilterIndexTab1,
            (idx) => setState(() => _subFilterIndexTab1 = idx),
          ),
          Expanded(
            child: _buildGroupedItemList(
              items: partyItems,
              emptyText: 'No Party Plans active right now.',
              onRefresh: () => _loadFeed(showLoader: false),
              itemBuilder: (item) {
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

  // ── Group Parties Feed ─────────────────────────────────────────────────────

  Widget _buildGroupPartiesFeed() {
    final filteredBookings = _largePartyBookings.where((booking) {
      if (_subFilterIndexTab2 == 0) return true;

      final rawPayStatus = (booking['paymentStatus'] ?? booking['payment_status'] ?? '').toString().toLowerCase();
      final rawAdminStatus = (booking['adminApprovalStatus'] ?? booking['admin_approval_status'] ?? '').toString().toLowerCase();
      final rawBookingStatus = (booking['status'] ?? booking['bookingStatus'] ?? booking['booking_status'] ?? '').toString().toLowerCase();

      final isPaid = rawPayStatus == 'paid' ||
          rawPayStatus == 'confirmed' ||
          rawPayStatus == 'payment_done' ||
          rawBookingStatus == 'paid' ||
          rawBookingStatus == 'confirmed' ||
          rawBookingStatus == 'payment_done';

      final isRejected = rawBookingStatus == 'rejected' ||
          rawBookingStatus == 'cancelled' ||
          rawAdminStatus == 'rejected';

      if (_subFilterIndexTab2 == 1) { // Pending
        return !isPaid && !isRejected && (
            rawAdminStatus == 'pending' ||
            rawBookingStatus == 'pending' ||
            rawBookingStatus == 'unpaid' ||
            rawBookingStatus == 'submitted'
        );
      }
      if (_subFilterIndexTab2 == 2) { // Approved (Payment Pending)
        return !isPaid && !isRejected && (
            rawAdminStatus == 'approved' ||
            rawAdminStatus == 'approved_awaiting_payment' ||
            rawAdminStatus == 'awaiting_payment' ||
            rawAdminStatus == 'payment_sent' ||
            rawBookingStatus == 'approved' ||
            rawBookingStatus == 'approved_awaiting_payment'
        );
      }
      if (_subFilterIndexTab2 == 3) { // Confirmed Bookings
        return isPaid;
      }
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: () => _loadGroupPartyBookings(),
      child: Column(
        children: [
          _buildSectionHeaderRow('Group Parties'),
          _buildSubFilterPills(
            ['All', 'Pending', 'Approved', 'Confirmed Bookings'],
            _subFilterIndexTab2,
            (idx) => setState(() => _subFilterIndexTab2 = idx),
          ),
          Expanded(
            child: _isLoadingGroupParties && _largePartyBookings.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _buildGroupedItemList(
                    items: filteredBookings,
                    emptyText:
                        'No group party requests yet.\nSubmit one from the Plan Hub!',
                    emptyIcon: Icons.groups_rounded,
                    onRefresh: () => _loadGroupPartyBookings(),
                    itemBuilder: (b) => _buildGroupPartyCard(b),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupPartyCard(Map<String, dynamic> booking) {
    final venue = booking['venue'];
    final venueName =
        (venue is Map ? venue['name'] : null) ??
        booking['venueName']?.toString() ??
        booking['venue_name']?.toString() ??
        'Venue';
    final venueAddress =
        (venue is Map
                ? (venue['address'] ??
                      venue['addressLine1'] ??
                      venue['address_line1'] ??
                      venue['city'] ??
                      '')
                : null)
            ?.toString() ??
        booking['venueAddress']?.toString() ??
        booking['venue_address']?.toString() ??
        '';
    final venueImage = (venue is Map
        ? (venue['images'] is List && (venue['images'] as List).isNotEmpty
              ? (venue['images'] as List).first?.toString()
              : (venue['imageUrl'] ?? venue['image_url'])?.toString())
        : null);

    final rawPayStatus = (booking['paymentStatus'] ?? booking['payment_status'] ?? '').toString().toLowerCase();
    final rawAdminStatus = (booking['adminApprovalStatus'] ?? booking['admin_approval_status'] ?? '').toString().toLowerCase();
    final rawBookingStatus = (booking['status'] ?? booking['bookingStatus'] ?? booking['booking_status'] ?? 'pending').toString().toLowerCase();

    final guests =
        (booking['numberOfGuests'] ?? booking['number_of_guests'] ?? '?')
            .toString();
    final rawSubject =
        (booking['partySubject'] ?? booking['party_subject'] ?? '').toString();
    final subject = _sanitizeDisplayText(rawSubject);
    final bookingDate = (booking['bookingDate'] ?? booking['booking_date'])
        ?.toString();
    final startTime = (booking['startTime'] ?? booking['start_time'] ?? '')
        .toString();
    final approvedAmount =
        booking['approvedAmount'] ??
        booking['approved_amount'] ??
        booking['charges'] ??
        booking['totalAmount'] ??
        booking['total_amount'] ??
        booking['adminPaymentAmount'] ??
        booking['admin_payment_amount'];
    final createdAt = (booking['createdAt'] ?? booking['created_at'])
        ?.toString();

    // Normalise status prioritizing completed payment
    final isPaid = rawPayStatus == 'paid' ||
        rawPayStatus == 'confirmed' ||
        rawPayStatus == 'payment_done' ||
        rawBookingStatus == 'paid' ||
        rawBookingStatus == 'confirmed' ||
        rawBookingStatus == 'payment_done';

    final isRejected = rawBookingStatus == 'rejected' ||
        rawBookingStatus == 'cancelled' ||
        rawAdminStatus == 'rejected';

    final isAwaitingPayment = !isPaid && !isRejected && (
        rawAdminStatus == 'approved' ||
        rawAdminStatus == 'approved_awaiting_payment' ||
        rawAdminStatus == 'awaiting_payment' ||
        rawAdminStatus == 'payment_sent' ||
        rawBookingStatus == 'approved' ||
        rawBookingStatus == 'approved_awaiting_payment' ||
        rawBookingStatus == 'awaiting_payment' ||
        rawBookingStatus == 'payment_sent'
    );

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (isPaid) {
      statusColor = Colors.green;
      statusLabel = 'BOOKING CONFIRMED 🎉';
      statusIcon = Icons.check_circle_rounded;
    } else if (isAwaitingPayment) {
      statusColor = Colors.orange;
      statusLabel = 'APPROVED – PAYMENT PENDING';
      statusIcon = Icons.payment_rounded;
    } else if (isRejected) {
      statusColor = Colors.red;
      statusLabel = 'REJECTED';
      statusIcon = Icons.cancel_rounded;
    } else {
      statusColor = LunaraTheme.electricViolet;
      statusLabel = 'PENDING REVIEW';
      statusIcon = Icons.hourglass_top_rounded;
    }

    String dateDisplay = 'TBD';
    if (bookingDate != null) {
      try {
        final dt = DateTime.parse(bookingDate).toLocal();
        dateDisplay = DateFormat('EEE, dd MMM yyyy').format(dt);
        if (startTime.isNotEmpty) dateDisplay += ' at $startTime';
      } catch (_) {
        dateDisplay = bookingDate;
      }
    }

    String cleanLocation = '';
    if (venue is Map) {
      final city = venue['city']?.toString() ?? '';
      final area =
          venue['area']?.toString() ?? venue['addressLine1']?.toString() ?? '';
      if (area.isNotEmpty && city.isNotEmpty && area != city) {
        cleanLocation = '$area, $city';
      } else if (city.isNotEmpty) {
        cleanLocation = city;
      } else {
        cleanLocation = area;
      }
    }
    if (cleanLocation.isEmpty && venueAddress.isNotEmpty) {
      cleanLocation = venueAddress.split(',').take(2).join(', ').trim();
    }

    final bookingId =
        booking['id']?.toString() ?? booking['bookingId']?.toString() ?? '';
    return Opacity(
      opacity: 1.0,
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 2,
        shadowColor: const Color(0x06000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isAwaitingPayment
                ? Colors.orange.withValues(alpha: 0.5)
                : isPaid
                ? Colors.green.withValues(alpha: 0.4)
                : LunaraTheme.electricViolet.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Venue image / header ──────────────────────────────────────
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: Container(
                height: 100,
                width: double.infinity,
                color: LunaraTheme.electricViolet.withValues(alpha: 0.12),
                child: venueImage != null && venueImage.isNotEmpty
                    ? Image.network(
                        ApiService.formatImageUrl(venueImage) ?? venueImage,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            _groupPartyHeaderPlaceholder(venueName),
                      )
                    : _groupPartyHeaderPlaceholder(venueName),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Category Badge + Time Ago ─────────────────────────────
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: LunaraTheme.electricViolet.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: LunaraTheme.electricViolet.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.groups_rounded,
                              size: 12,
                              color: LunaraTheme.electricViolet,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'GROUP PARTY',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: LunaraTheme.electricViolet,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (createdAt != null)
                        Text(
                          _formatTimeAgo(createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Venue Name & Clean Location ────────────────────────
                  Text(
                    venueName.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'AllroundGothic',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (cleanLocation.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 14,
                          color: LunaraTheme.cyberCyan,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            cleanLocation.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // ── Details Grid Chips ──────────────────────────────────────
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _infoChip(Icons.calendar_today_outlined, dateDisplay),
                      _infoChip(Icons.people_outline, '$guests guests'),
                      if (subject.isNotEmpty)
                        _infoChip(Icons.label_outline, subject),
                      if (approvedAmount != null)
                        _infoChip(
                          Icons.currency_rupee_rounded,
                          '₹${(approvedAmount is num ? approvedAmount.toStringAsFixed(0) : approvedAmount)}',
                        ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── Status Badge ──────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 16, color: statusColor),
                        const SizedBox(width: 8),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: statusColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Action Buttons ────────────────────────────────────
                  if (isAwaitingPayment && approvedAmount != null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          widget.onCountChanged?.call();
                          _initiateLargePartyPayment(booking);
                        },
                        icon: const Icon(Icons.payment_rounded, size: 18),
                        label: Text(
                          'PAY ₹${(approvedAmount is num ? approvedAmount.toStringAsFixed(0) : approvedAmount)} TO CONFIRM',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 0.8,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 3,
                        ),
                      ),
                    ),

                  if (isPaid)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          widget.onCountChanged?.call();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LargePartyTicketScreen(
                                booking: booking,
                                venue: Map<dynamic, dynamic>.from(
                                  booking['venue'] is Map
                                      ? booking['venue']
                                      : {},
                                ),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.confirmation_number_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          'VIEW TICKET',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 1.0,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: LunaraTheme.electricViolet,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 3,
                        ),
                      ),
                    ),

                  if (isAwaitingPayment && approvedAmount == null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 15,
                            color: Colors.orange,
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Admin will send you the payment link shortly.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupPartyHeaderPlaceholder(String venueName) {
    return Container(
      color: LunaraTheme.electricViolet.withValues(alpha: 0.15),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.groups_rounded,
              color: LunaraTheme.electricViolet,
              size: 32,
            ),
            const SizedBox(height: 4),
            Text(
              venueName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: LunaraTheme.electricViolet,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildNotificationsFeed() {
    final filteredNotifications = _notifications.where((n) {
      if (_subFilterIndexTab3 == 0) return true;
      final category = (n['category'] ?? n['type'] ?? n['title'] ?? '')
          .toString()
          .toLowerCase();
      if (_subFilterIndexTab3 == 1) {
        return category.contains('system') || category.contains('notice');
      }
      if (_subFilterIndexTab3 == 2) {
        return category.contains('alert') ||
            category.contains('reminder') ||
            category.contains('safety') ||
            category.contains('warning');
      }
      if (_subFilterIndexTab3 == 3) {
        return category.contains('activity') ||
            category.contains('event') ||
            category.contains('booking') ||
            category.contains('payment') ||
            category.contains('like') ||
            category.contains('match') ||
            category.contains('party') ||
            category.contains('meet');
      }
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: () => _loadFeed(showLoader: false),
      child: Column(
        children: [
          _buildSectionHeaderRow('Other Notifications'),
          _buildSubFilterPills(
            ['All', 'System', 'Alerts', 'Activity'],
            _subFilterIndexTab3,
            (idx) => setState(() => _subFilterIndexTab3 = idx),
          ),
          Expanded(
            child: _buildGroupedItemList(
              items: filteredNotifications,
              emptyText: 'No recent activity.',
              emptyIcon: Icons.notifications_paused_rounded,
              onRefresh: () => _loadFeed(showLoader: false),
              itemBuilder: (n) => _buildNotificationCard(n),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedItemList({
    required List<Map<String, dynamic>> items,
    required Widget Function(Map<String, dynamic> item) itemBuilder,
    required String emptyText,
    IconData emptyIcon = Icons.notifications_none_rounded,
    Future<void> Function()? onRefresh,
  }) {
    if (items.isEmpty) {
      return _buildEmptyState(emptyText, icon: emptyIcon);
    }

    final sortedItems = List<Map<String, dynamic>>.from(items);
    sortedItems.sort((a, b) {
      final rawA =
          a['createdAt'] ?? a['postedAt'] ?? a['created_at'] ?? a['timestamp'];
      final rawB =
          b['createdAt'] ?? b['postedAt'] ?? b['created_at'] ?? b['timestamp'];
      final dtA = rawA != null
          ? (DateTime.tryParse(rawA.toString())?.toLocal() ??
                DateTime.fromMillisecondsSinceEpoch(0))
          : DateTime.fromMillisecondsSinceEpoch(0);
      final dtB = rawB != null
          ? (DateTime.tryParse(rawB.toString())?.toLocal() ??
                DateTime.fromMillisecondsSinceEpoch(0))
          : DateTime.fromMillisecondsSinceEpoch(0);
      return dtB.compareTo(dtA);
    });

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final item in sortedItems) {
      final rawDate =
          item['createdAt'] ??
          item['postedAt'] ??
          item['created_at'] ??
          item['timestamp'];
      DateTime dt = DateTime.now();
      if (rawDate != null) {
        dt = DateTime.tryParse(rawDate.toString())?.toLocal() ?? DateTime.now();
      }
      final itemDate = DateTime(dt.year, dt.month, dt.day);

      String groupKey;
      if (itemDate.isAtSameMomentAs(todayStart) ||
          itemDate.isAfter(todayStart)) {
        groupKey = 'TODAY';
      } else if (itemDate.isAtSameMomentAs(yesterdayStart)) {
        groupKey = 'YESTERDAY';
      } else {
        groupKey = DateFormat('EEEE, d MMMM yyyy').format(dt).toUpperCase();
      }

      grouped.putIfAbsent(groupKey, () => []).add(item);
    }

    final listViewChildren = <Widget>[];

    for (final entry in grouped.entries) {
      final headerTitle = entry.key;
      final groupItems = entry.value;

      listViewChildren.add(
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8, left: 4, right: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  headerTitle,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: LunaraTheme.electricViolet,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(child: Divider(height: 1, color: Colors.black12)),
            ],
          ),
        ),
      );

      for (final item in groupItems) {
        listViewChildren.add(itemBuilder(item));
      }
    }

    listViewChildren.add(_buildWhyThisIsBetterBanner());

    final listView = ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: listViewChildren,
    );

    if (onRefresh != null) {
      return RefreshIndicator(onRefresh: onRefresh, child: listView);
    }

    return listView;
  }

  Widget _buildEmptyState(
    String text, {
    IconData icon = Icons.notifications_none_rounded,
  }) {
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
    final formattedDate = _formatPlanDate(
      post['planDateTime'] ?? post['planDate'],
    );
    final timeAgo = _formatTimeAgo(post['postedAt']);
    String planTime = '21:00';
    if (post['planDateTime'] != null) {
      try {
        final parsedDt = DateTime.parse(
          post['planDateTime'].toString(),
        ).toLocal();
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
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
                      final planId =
                          post['planId']?.toString() ??
                          post['id']?.toString() ??
                          '';
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
                        final reqStatus =
                            _optimisticStates[reqId] ??
                            myReq['status']?.toString().toLowerCase() ??
                            'pending';
                        final joinerPaid =
                            myReq['joinerPaymentStatus']
                                    ?.toString()
                                    .toLowerCase() ==
                                'paid' ||
                            myReq['joinerPaymentStatus']
                                    ?.toString()
                                    .toLowerCase() ==
                                'confirmed';

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
                                reqStatus == 'payment_pending') &&
                            !joinerPaid) {
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
                            final planId =
                                post['planId']?.toString() ??
                                post['id']?.toString() ??
                                '';
                            if (planId.isEmpty) return;
                            final success =
                                await ApiService.requestToJoinPartyPlan(planId);
                            if (!mounted || !context.mounted) return;
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
    final formattedDate = _formatPlanDate(
      plan['planDateTime'] ?? plan['planDate'],
    );
    final timeAgo = _formatTimeAgo(plan['postedAt']);
    String planTime = '21:00';
    if (plan['planDateTime'] != null) {
      try {
        final parsedDt = DateTime.parse(
          plan['planDateTime'].toString(),
        ).toLocal();
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
                    if (isMyPost) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Text(
                          'HOSTED BY YOU',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
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
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.5),
                          ),
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
            if (isMyPost &&
                plan['hostPaymentStatus']?.toString().toLowerCase() != 'paid')
              ...([
                Builder(
                  builder: (context) {
                    final planId = plan['id']?.toString() ?? '';
                    final isSelfPay = plan['paymentType'] == 'self_pay';
                    final depositAmount = plan['depositAmount'] != null
                        ? double.tryParse(
                                plan['depositAmount'].toString(),
                              )?.toInt() ??
                              (isSelfPay ? 198 : 99)
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
                              colors: [
                                LunaraTheme.electricViolet,
                                LunaraTheme.electricViolet,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: LunaraTheme.electricViolet.withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.payment_rounded,
                                color: Colors.white,
                                size: 15,
                              ),
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
                      final planId =
                          plan['planId']?.toString() ??
                          plan['id']?.toString() ??
                          '';
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
                        final reqStatus =
                            _optimisticStates[reqId] ??
                            myReq['status']?.toString().toLowerCase() ??
                            'pending';
                        final joinerPaid =
                            myReq['joinerPaymentStatus']
                                    ?.toString()
                                    .toLowerCase() ==
                                'paid' ||
                            myReq['joinerPaymentStatus']
                                    ?.toString()
                                    .toLowerCase() ==
                                'confirmed';

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
                        } else if (reqStatus == 'accepted' ||
                            reqStatus == 'payment_pending') {
                          if (!joinerPaid) {
                            final hStatus =
                                (myReq['plan']?['hostPaymentStatus'] ??
                                        myReq['planDetails']?['hostPaymentStatus'] ??
                                        plan['hostPaymentStatus'])
                                    ?.toString()
                                    .toLowerCase();
                            final hostPaid =
                                hStatus == 'paid' ||
                                hStatus == 'refunded' ||
                                hStatus == 'completed' ||
                                hStatus == 'confirmed';
                            if (!hostPaid) {
                              return Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.orange.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.hourglass_empty_rounded,
                                        color: Colors.orange,
                                        size: 15,
                                      ),
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
                          } else {
                            // Joiner has paid
                            final hStatus =
                                (myReq['plan']?['hostPaymentStatus'] ??
                                        myReq['planDetails']?['hostPaymentStatus'] ??
                                        plan['hostPaymentStatus'])
                                    ?.toString()
                                    .toLowerCase();
                            final hostPaid =
                                hStatus == 'paid' ||
                                hStatus == 'refunded' ||
                                hStatus == 'completed' ||
                                hStatus == 'confirmed';
                            if (!hostPaid) {
                              return Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.orange.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.hourglass_empty_rounded,
                                        color: Colors.orange,
                                        size: 15,
                                      ),
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
                            // Both paid! Show CHAT only (VIEW TICKET is host-only).
                            if (myReq['plan']?['creator'] != null ||
                                plan['host'] != null) {
                              return Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChatScreen(
                                          user: {
                                            ...(myReq['plan']?['creator'] ??
                                                plan['host'] ??
                                                {}),
                                            'contextType': 'party_plan',
                                            'planId':
                                                myReq['plan']?['id']
                                                    ?.toString() ??
                                                plan['id']?.toString(),
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'CHAT',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: LunaraTheme.hotPink,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 11,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              );
                            }
                            return Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.green.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: const Center(
                                  child: Text(
                                    'MATCH CONFIRMED',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
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
                            final planId =
                                plan['planId']?.toString() ??
                                plan['id']?.toString() ??
                                '';
                            if (planId.isEmpty) return;
                            final success =
                                await ApiService.requestToJoinPartyPlan(planId);
                            if (!mounted || !context.mounted) return;
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
    final resolvedAmount =
        amount ??
        (plan['depositAmount'] != null
            ? double.tryParse(plan['depositAmount'].toString())?.toInt() ??
                  (isSelfPay ? 198 : 99)
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
          razorpayOrderId:
              hostRazorpayOrderId ?? plan['hostRazorpayOrderId']?.toString(),
          razorpayKeyId: razorpayKeyId,
          razorpayAmount: resolvedAmount * 100,
          onRazorpayPaymentSuccess: (paymentId, signature) async {
            try {
              final orderId =
                  hostRazorpayOrderId ??
                  plan['hostRazorpayOrderId']?.toString() ??
                  'mock_order';
              final success = await ApiService.verifyHostPayment(
                planId,
                orderId,
                paymentId,
                signature,
              );
              if (!mounted || !context.mounted) return;
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
                    content: Text(
                      'Payment verification failed. Please contact support.',
                    ),
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
              final orderId =
                  hostRazorpayOrderId ??
                  plan['hostRazorpayOrderId']?.toString() ??
                  'mock_order';
              final success = await ApiService.verifyHostPayment(
                planId,
                orderId,
                'mock_payment',
                'mock_signature',
              );
              if (!mounted || !context.mounted) return;
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
                    content: Text(
                      'Payment verification failed. Please contact support.',
                    ),
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
          content: Text(
            'Could not identify plan. Please refresh and try again.',
          ),
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
          : (data['amount'] is double
                ? (data['amount'] as double).toInt()
                : 99);
      _onHostPayDeposit(
        plan,
        orderId,
        razorpayKeyId: razorpayKeyId,
        amount: amount,
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
  }

  Widget _buildIncomingRequestCard(Map<String, dynamic> req) {
    final requester = req['requester'] ?? req['user'] ?? {};
    final reqId = req['id']?.toString() ?? '';
    final timeAgo = _formatTimeAgo(req['createdAt']);
    final currentStatus =
        _optimisticStates[reqId] ??
        req['status']?.toString().toLowerCase() ??
        'pending';

    final requesterFirstName =
        (requester['firstName'] ?? requester['name'] ?? 'User').toString();
    final requesterLastName = (requester['lastName'] ?? '').toString();
    final requesterFullName = '$requesterFirstName $requesterLastName'.trim();
    final cleanRequesterName = requesterFullName.isNotEmpty
        ? requesterFullName
        : 'Guest User';

    final plan = req['plan'] ?? req['planDetails'] ?? {};
    final venue = plan['venue'] ?? {};
    final venueName =
        (venue is Map ? venue['name'] : null) ?? plan['venueName'] ?? 'Venue';
    final requestType = req['requestType']?.toString() ?? 'table_plan';
    final requestTypeLabel = requestType == 'party_plan'
        ? 'Party Plan Request'
        : (requestType == 'stranger_meet' || requestType == 'stranger_meet_join'
              ? 'Stranger Meet Request'
              : 'Join Request');

    final hostPaid =
        req['plan']?['hostPaymentStatus']?.toString().toLowerCase() == 'paid' ||
        req['plan']?['hostPaymentStatus']?.toString().toLowerCase() ==
            'refunded' ||
        req['planDetails']?['hostPaymentStatus']?.toString().toLowerCase() ==
            'paid' ||
        req['planDetails']?['hostPaymentStatus']?.toString().toLowerCase() ==
            'refunded';
    final joinerPaid =
        req['joinerPaymentStatus']?.toString().toLowerCase() == 'paid' ||
        req['joinerPaymentStatus']?.toString().toLowerCase() == 'confirmed';
    return Opacity(
      opacity: 1.0,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF1F5F9), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LunaraProfileImage(
                    userData: requester is Map
                        ? Map<String, dynamic>.from(requester)
                        : {},
                    radius: 22,
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
                                  builder: (context) =>
                                      ProfileScreen(user: userObj),
                                ),
                              );
                            } catch (e) {
                              debugPrint(
                                'Error navigating to profile screen: $e',
                              );
                            }
                          },
                          child: Text(
                            '$cleanRequesterName requested to join',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$requestTypeLabel • $venueName',
                          style: const TextStyle(
                            color: LunaraTheme.electricViolet,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          timeAgo,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
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
                            final success =
                                await ApiService.handleStrangersMeetJoinRequest(
                                  planId,
                                  reqId,
                                  'accept',
                                );
                            if (success) {
                              _loadFeed(showLoader: false);
                            } else {
                              setState(() => _optimisticStates.remove(reqId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to accept request'),
                                ),
                              );
                            }
                          } else {
                            final result =
                                await ApiService.acceptPartyPlanRequest(reqId);
                            if (result != null) {
                              final hostOrderId = result['hostRazorpayOrderId']
                                  ?.toString();
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
                            final success =
                                await ApiService.handleStrangersMeetJoinRequest(
                                  planId,
                                  reqId,
                                  'reject',
                                );
                            if (success) {
                              _loadFeed(showLoader: false);
                            } else {
                              setState(() => _optimisticStates.remove(reqId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to reject request'),
                                ),
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
              ] else if (currentStatus == 'accepted' ||
                  currentStatus == 'paid' ||
                  currentStatus == 'payment_pending') ...[
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
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 16,
                            ),
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
                                icon: const Icon(
                                  Icons.qr_code_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'VIEW TICKET',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: LunaraTheme.electricViolet,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
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
                                      builder: (_) => ChatScreen(
                                        user: {
                                          ...requester,
                                          'contextType': 'party_plan',
                                          'planId': req['plan']?['id']
                                              ?.toString(),
                                        },
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'CHAT',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: LunaraTheme.hotPink,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
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
                          ? double.tryParse(
                                  plan['depositAmount'].toString(),
                                )?.toInt() ??
                                (isSelfPay ? 198 : 99)
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
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: LunaraTheme.accentVivid,
                                  size: 16,
                                ),
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
                                  final planId =
                                      (req['planId']?.toString().isNotEmpty ==
                                          true
                                      ? req['planId'].toString()
                                      : plan['id']?.toString() ?? '');
                                  _startHostPayment(planId, plan);
                                },
                                icon: const Icon(
                                  Icons.payment,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                label: Text(
                                  'PAY NOW (₹$depositAmount)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: LunaraTheme.electricViolet,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
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
              : (isStrangerMeetJoin
                    ? (req['plan']?['venue'] ?? {})
                    : (plan['venue'] ?? {})));

    final isInvite = _isInvite(req);

    final timeAgo = _formatTimeAgo(req['createdAt']);
    final reqId = req['id']?.toString() ?? '';
    final currentStatus =
        _optimisticStates[reqId] ??
        req['status']?.toString().toLowerCase() ??
        'pending';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Opacity(
      opacity: 1.0,
      child: Padding(
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
                color: LunaraTheme.electricViolet.withValues(
                  alpha: isDark ? 0.12 : 0.05,
                ),
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
                      border: Border.all(
                        color: Colors.yellow.withValues(alpha: 0.3),
                      ),
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
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                      ),
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
                                  final bookingId =
                                      booking['id']?.toString() ?? '';
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

                                  final paymentInfo =
                                      await ApiService.initiateLargePartyPayment(
                                        bookingId,
                                      );

                                  if (!mounted || !context.mounted) return;
                                  Navigator.pop(
                                    context,
                                  ); // Close loading spinner

                                  if (paymentInfo != null &&
                                      paymentInfo['success'] == true) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PaymentConfirmationScreen(
                                          venue: venue,
                                          date: booking['bookingDate'] != null
                                              ? DateFormat('dd/MM/yyyy').format(
                                                  DateTime.parse(
                                                    booking['bookingDate'],
                                                  ).toLocal(),
                                                )
                                              : 'Tonight',
                                          package:
                                              'Large Party Booking Deposit',
                                          time: booking['startTime'] ?? '21:00',
                                          table: 'Large Party Table',
                                          guests:
                                              '${booking['numberOfGuests'] ?? 1} Guests',
                                          totalPrice:
                                              '₹${booking['totalAmount'] ?? '0'}',
                                          showSplitBill: false,
                                          razorpayOrderId:
                                              paymentInfo['razorpayOrderId'],
                                          razorpayKeyId:
                                              paymentInfo['razorpayKeyId'],
                                          razorpayAmount: paymentInfo['amount'],
                                          onRazorpayPaymentSuccess:
                                              (paymentId, signature) async {
                                                final success =
                                                    await ApiService.verifyLargePartyPayment(
                                                      bookingId,
                                                      razorpayOrderId:
                                                          paymentInfo['razorpayOrderId'],
                                                      razorpayPaymentId:
                                                          paymentId,
                                                      razorpaySignature:
                                                          signature,
                                                    );
                                                if (!mounted || !context.mounted) return;
                                                if (success) {
                                                  setState(() {
                                                    _optimisticStates[reqId] =
                                                        'payment_done';
                                                  });
                                                  _loadFeed(showLoader: false);
                                                } else {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Payment Verification Failed.',
                                                      ),
                                                      backgroundColor:
                                                          Colors.red,
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
                                        content: Text(
                                          'Failed to initiate payment. Please try again.',
                                        ),
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
                                  final urlStr =
                                      booking['adminPaymentLink'] ?? '';
                                  if (urlStr.isNotEmpty) {
                                    final url = Uri.parse(urlStr);
                                    if (await canLaunchUrl(url)) {
                                      await launchUrl(
                                        url,
                                        mode: LaunchMode.externalApplication,
                                      );
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
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 16,
                            ),
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
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => LargePartyTicketScreen(
                                        booking: booking,
                                        venue: venue,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.qr_code_2_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'VIEW TICKET',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: LunaraTheme.electricViolet,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  final chatTarget =
                                      venue['user'] ??
                                      venue['creator'] ??
                                      venue['admin'] ??
                                      {
                                        'id': 'venue_support',
                                        'firstName':
                                            venue['name'] ?? 'Venue Support',
                                        'lastName': '',
                                        'username': 'support',
                                      };
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                        user: {
                                          ...Map<String, dynamic>.from(
                                            chatTarget,
                                          ),
                                          'contextType': 'large_party',
                                          'bookingId': booking['id']
                                              ?.toString(),
                                        },
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'CHAT',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: LunaraTheme.hotPink,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
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
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
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
                      border: Border.all(
                        color: Colors.yellow.withValues(alpha: 0.3),
                      ),
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
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
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
                ] else if (currentStatus == 'approved' &&
                    req['paymentStatus'] != 'paid') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: LunaraTheme.electricViolet.withValues(
                          alpha: 0.3,
                        ),
                      ),
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
                                  final meetReq = StrangersMeetRequest.fromJson(
                                    req,
                                  );
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          StrangersMeetPaymentScreen(
                                            request: meetReq,
                                            onPaymentSuccess: () {
                                              setState(() {
                                                _optimisticStates[reqId] =
                                                    'paid';
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
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.blue,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            currentStatus == 'completed'
                                ? 'COMPLETED'
                                : 'PAYMENT CONFIRMED & PUBLISHED',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (currentStatus == 'approved' ||
                    currentStatus == 'paid' ||
                    currentStatus == 'completed') ...[
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
                            final joinerStatus =
                                _optimisticStates[joinReqId] ??
                                joinReq['status']?.toString().toLowerCase() ??
                                'pending';
                            final joinerPayment =
                                joinReq['joinerPaymentStatus']
                                    ?.toString()
                                    .toLowerCase() ??
                                'pending';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.05),
                                ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                          joinerStatus == 'paid' ||
                                                  joinerPayment == 'paid'
                                              ? 'PAID & JOINED'
                                              : joinerStatus.toUpperCase(),
                                          style: TextStyle(
                                            color:
                                                joinerStatus == 'paid' ||
                                                    joinerPayment == 'paid'
                                                ? Colors.green
                                                : (joinerStatus == 'accepted'
                                                      ? Colors.orange
                                                      : Colors.grey),
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (joinerStatus == 'pending') ...[
                                    IconButton(
                                      icon: const Icon(
                                        Icons.check_circle_outline,
                                        color: Colors.green,
                                        size: 22,
                                      ),
                                      onPressed: () async {
                                        setState(
                                          () => _optimisticStates[joinReqId] =
                                              'accepted',
                                        );
                                        final success =
                                            await ApiService.handleStrangersMeetJoinRequest(
                                              reqId,
                                              joinReqId,
                                              'accept',
                                            );
                                        if (success) {
                                          _loadFeed(showLoader: false);
                                        } else {
                                          setState(
                                            () => _optimisticStates.remove(
                                              joinReqId,
                                            ),
                                          );
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Failed to accept request',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.cancel_outlined,
                                        color: Colors.red,
                                        size: 22,
                                      ),
                                      onPressed: () async {
                                        setState(
                                          () => _optimisticStates[joinReqId] =
                                              'rejected',
                                        );
                                        final success =
                                            await ApiService.handleStrangersMeetJoinRequest(
                                              reqId,
                                              joinReqId,
                                              'reject',
                                            );
                                        if (success) {
                                          _loadFeed(showLoader: false);
                                        } else {
                                          setState(
                                            () => _optimisticStates.remove(
                                              joinReqId,
                                            ),
                                          );
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Failed to reject request',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                  if (joinerStatus == 'paid' ||
                                      joinerPayment == 'paid') ...[
                                    IconButton(
                                      icon: const Icon(
                                        Icons.chat_bubble_outline_rounded,
                                        color: LunaraTheme.hotPink,
                                        size: 22,
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              user: {
                                                ...joiner,
                                                'contextType': 'stranger_meet',
                                                'planId': reqId,
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                        ],
                      );
                    },
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
                      border: Border.all(
                        color: Colors.yellow.withValues(alpha: 0.3),
                      ),
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
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
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
                ] else if (currentStatus == 'accepted' ||
                    currentStatus == 'payment_pending') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: LunaraTheme.electricViolet.withValues(
                          alpha: 0.3,
                        ),
                      ),
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
                                  final meetPlan =
                                      StrangersMeetRequest.fromJson(
                                        req['plan'] ?? {},
                                      );
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          StrangersMeetPaymentScreen(
                                            request: meetPlan,
                                            isJoinPayment: true,
                                            onPaymentSuccess: () {
                                              setState(() {
                                                _optimisticStates[reqId] =
                                                    'paid';
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
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 16,
                            ),
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
                                      final meetPlan =
                                          StrangersMeetRequest.fromJson(
                                            req['plan'],
                                          );
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              StrangersMeetTicketScreen(
                                                request: meetPlan,
                                              ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.qr_code_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    label: const Text(
                                      'VIEW TICKET',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          LunaraTheme.electricViolet,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (req['plan']?['user'] != null) ...[
                                if (req['plan']?['ticketId'] != null)
                                  const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(
                                            user: {
                                              ...req['plan']?['user'],
                                              'contextType': 'stranger_meet',
                                              'planId': req['plan']?['id']
                                                  ?.toString(),
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    label: const Text(
                                      'CHAT',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: LunaraTheme.hotPink,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
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
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.3),
                        ),
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
                                    setState(
                                      () =>
                                          _optimisticStates[reqId] = 'accepted',
                                    );
                                    final res =
                                        await ApiService.acceptPartyPlanInvite(
                                          reqId,
                                        );
                                    if (res != null) {
                                      _loadFeed(showLoader: false);
                                    } else {
                                      setState(
                                        () => _optimisticStates.remove(reqId),
                                      );
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Failed to accept invite',
                                            ),
                                          ),
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
                                    setState(
                                      () => _optimisticStates[reqId] =
                                          'cancelled',
                                    );
                                    await ApiService.rejectPartyPlanRequest(
                                      reqId,
                                    );
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
                        border: Border.all(
                          color: Colors.yellow.withValues(alpha: 0.3),
                        ),
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
                ] else if ((currentStatus == 'accepted' ||
                        currentStatus == 'payment_pending') &&
                    req['joinerPaymentStatus']?.toString().toLowerCase() !=
                        'confirmed' &&
                    req['joinerPaymentStatus']?.toString().toLowerCase() !=
                        'paid') ...[
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
                            final hostPaid =
                                req['plan']?['hostPaymentStatus']
                                        ?.toString()
                                        .toLowerCase() ==
                                    'paid' ||
                                req['plan']?['hostPaymentStatus']
                                        ?.toString()
                                        .toLowerCase() ==
                                    'refunded';
                            if (!hostPaid) {
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.orange.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.hourglass_empty_rounded,
                                      color: Colors.orange,
                                      size: 15,
                                    ),
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
                                        () => _optimisticStates[reqId] =
                                            'cancelled',
                                      );
                                      await ApiService.rejectPartyPlanRequest(
                                        reqId,
                                      );
                                      _loadFeed(showLoader: false);
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ] else if (currentStatus == 'paid' ||
                    req['joinerPaymentStatus']?.toString().toLowerCase() ==
                        'paid' ||
                    req['joinerPaymentStatus']?.toString().toLowerCase() ==
                        'confirmed') ...[
                  Builder(
                    builder: (context) {
                      final hostPaid =
                          req['plan']?['hostPaymentStatus']
                                  ?.toString()
                                  .toLowerCase() ==
                              'paid' ||
                          req['plan']?['hostPaymentStatus']
                                  ?.toString()
                                  .toLowerCase() ==
                              'refunded';
                      if (!hostPaid) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.hourglass_empty_rounded,
                                color: Colors.orange,
                                size: 15,
                              ),
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
                      return Container(
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
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 16,
                                ),
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
                                if (req['plan']?['creator'] != null)
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              user: {
                                                ...req['plan']?['creator'],
                                                'contextType': 'party_plan',
                                                'planId': req['plan']?['id']
                                                    ?.toString(),
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.chat_bubble_outline_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                      label: const Text(
                                        'CHAT',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: LunaraTheme.hotPink,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
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
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notif) {
    final title = notif['title'] ?? 'Notification';
    final body = notif['body'] ?? '';
    final timeAgo = _formatTimeAgo(notif['createdAt']);
    final isRead = notif['isRead'] == true || notif['read'] == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final eventDetails = notif['eventDetails'] as Map<String, dynamic>?;
    final grouped = notif['grouped'] == true;
    final groupCount = notif['groupCount'] as int? ?? 1;

    IconData icon = Icons.notifications_rounded;
    Color color = LunaraTheme.electricViolet;
    final lowerTitle = title.toLowerCase();

    if (lowerTitle.contains('super')) {
      icon = Icons.star_rounded;
      color = const Color(0xFFFFB800);
    } else if (lowerTitle.contains('like')) {
      icon = Icons.favorite_rounded;
      color = LunaraTheme.hotPink;
    } else if (lowerTitle.contains('booking confirmed') ||
        lowerTitle.contains('spot confirmed') ||
        lowerTitle.contains('payment successful') ||
        lowerTitle.contains('payment confirmed')) {
      icon = Icons.check_circle_rounded;
      color = const Color(0xFF00E676);
    } else if (lowerTitle.contains('awaiting payment')) {
      icon = Icons.hourglass_top_rounded;
      color = const Color(0xFFFFA000);
    } else if (lowerTitle.contains('payment link')) {
      icon = Icons.link_rounded;
      color = const Color(0xFFFFA000);
    } else if (lowerTitle.contains('payment')) {
      icon = Icons.payment_rounded;
      color = const Color(0xFF00E676);
    } else if (lowerTitle.contains('visit') || lowerTitle.contains('view')) {
      icon = Icons.visibility_rounded;
      color = LunaraTheme.electricViolet;
    } else if (lowerTitle.contains('invite accepted') ||
        lowerTitle.contains('accepted') ||
        lowerTitle.contains('approved')) {
      icon = Icons.verified_rounded;
      color = const Color(0xFF00E676);
    } else if (lowerTitle.contains('declined') ||
        lowerTitle.contains('rejected') ||
        lowerTitle.contains('cancelled') ||
        lowerTitle.contains('failed')) {
      icon = Icons.cancel_outlined;
      color = const Color(0xFFFF5252);
    } else if (lowerTitle.contains('invite')) {
      icon = Icons.mail_outline_rounded;
      color = const Color(0xFFE040FB);
    } else if (lowerTitle.contains('new join request') ||
        lowerTitle.contains('join requests') ||
        lowerTitle.contains('requested to join')) {
      icon = Icons.person_add_alt_1_rounded;
      color = const Color(0xFF00B0FF);
    } else if (lowerTitle.contains('participant joined') ||
        lowerTitle.contains('joined')) {
      icon = Icons.group_add_rounded;
      color = const Color(0xFF00E676);
    } else if (lowerTitle.contains('safety check') ||
        lowerTitle.contains('safety')) {
      icon = Icons.security_rounded;
      color = const Color(0xFF2979FF);
    } else if (lowerTitle.contains('large party') ||
        lowerTitle.contains('group party')) {
      icon = Icons.celebration_rounded;
      color = const Color(0xFFFF6D00);
    } else if (lowerTitle.contains('submitted') ||
        lowerTitle.contains('initiated')) {
      icon = Icons.hourglass_empty_rounded;
      color = const Color(0xFFFFB300);
    } else if (lowerTitle.contains('stranger meet') ||
        lowerTitle.contains('meet')) {
      icon = Icons.people_alt_rounded;
      color = LunaraTheme.electricViolet;
    }

    final sender = notif['sender'];
    final hasSender = sender != null && sender['id'] != null;

    final cardBg = isDark
        ? (isRead ? const Color(0xFF16161E) : const Color(0xFF1D1430))
        : (isRead ? Colors.white : const Color(0xFFF8F4FF));
    final borderCol = isRead
        ? (isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05))
        : color.withValues(alpha: 0.35);

    return Opacity(
      opacity: isRead ? 0.6 : 1.0,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GestureDetector(
          onTap: () => _handleNotificationCardTap(notif),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderCol, width: isRead ? 1.0 : 1.5),
              boxShadow: isRead
                  ? null
                  : [
                      BoxShadow(
                        color: color.withValues(alpha: isDark ? 0.18 : 0.07),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar + icon badge
                    if (hasSender)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          LunaraProfileImage(
                            userData: sender,
                            radius: 22,
                            showGradientBorder: !isRead,
                            isInteractive: true,
                          ),
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1D1430)
                                    : Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF1D1430)
                                      : Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                icon,
                                color: isRead
                                    ? color.withValues(alpha: 0.6)
                                    : color,
                                size: 11,
                              ),
                            ),
                          ),
                          // Group count badge
                          if (grouped && groupCount > 1)
                            Positioned(
                              top: -4,
                              right: -4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF1D1430)
                                        : Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  '+$groupCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                    else
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              color.withValues(alpha: 0.2),
                              color.withValues(alpha: 0.08),
                            ],
                          ),
                          border: Border.all(
                            color: color.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            icon,
                            color: isRead
                                ? color.withValues(alpha: 0.6)
                                : color,
                            size: 22,
                          ),
                        ),
                      ),
                    const SizedBox(width: 14),

                    // Text content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                    color: isDark
                                        ? (isRead
                                              ? Colors.white70
                                              : Colors.white)
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (!isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: color,
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            body,
                            style: TextStyle(
                              color: isDark
                                  ? (isRead ? Colors.white54 : Colors.white70)
                                  : (isRead ? Colors.black54 : Colors.black87),
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            timeAgo,
                            style: TextStyle(
                              color: isDark ? Colors.white38 : Colors.black38,
                              fontSize: 10.5,
                              fontWeight: isRead
                                  ? FontWeight.normal
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ── Event Detail Chips ─────────────────────────────────────────
                if (eventDetails != null && eventDetails.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? color.withValues(alpha: 0.07)
                          : color.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: color.withValues(alpha: isDark ? 0.2 : 0.15),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Subject / Event name
                        if (eventDetails['subject'] != null)
                          Row(
                            children: [
                              Icon(
                                Icons.event_note_rounded,
                                size: 13,
                                color: color.withValues(alpha: 0.8),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  eventDetails['subject'].toString(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        if (eventDetails['tagline'] != null &&
                            (eventDetails['tagline'] as String).isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Padding(
                            padding: const EdgeInsets.only(left: 19),
                            child: Text(
                              eventDetails['tagline'].toString(),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white54 : Colors.black54,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        // Info chips row
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (eventDetails['eventDate'] != null)
                              _notifChip(
                                Icons.calendar_today_rounded,
                                eventDetails['eventDate'].toString(),
                                color,
                                isDark,
                              ),
                            if (eventDetails['venue'] != null)
                              _notifChip(
                                Icons.location_on_rounded,
                                eventDetails['venue'].toString(),
                                color,
                                isDark,
                              ),
                            if (eventDetails['chargesPerHead'] != null &&
                                double.tryParse(
                                      eventDetails['chargesPerHead'].toString(),
                                    ) !=
                                    null &&
                                double.parse(
                                      eventDetails['chargesPerHead'].toString(),
                                    ) >
                                    0)
                              _notifChip(
                                Icons.currency_rupee_rounded,
                                '₹${double.parse(eventDetails['chargesPerHead'].toString()).toStringAsFixed(0)} / person',
                                color,
                                isDark,
                              ),
                            if (eventDetails['totalSeats'] != null)
                              _notifChip(
                                Icons.people_alt_rounded,
                                '${eventDetails['totalSeats']} seats',
                                color,
                                isDark,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                // ── View Profile button (if sender) ───────────────────────────
                if (hasSender) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      try {
                        final userObj = User.fromJson(
                          Map<String, dynamic>.from(sender),
                        );
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            LunaraTheme.electricViolet,
                            LunaraTheme.hotPink,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: LunaraTheme.electricViolet.withValues(
                              alpha: 0.22,
                            ),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
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
        ),
      ),
    );
  }

  Widget _notifChip(IconData icon, String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? color.withValues(alpha: 0.12)
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.3 : 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 10,
            color: color.withValues(alpha: isDark ? 0.9 : 0.8),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
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
        ? DateFormat('dd/MM/yyyy').format(
            DateTime.parse(widget.plan['planDateTime'].toString()).toLocal(),
          )
        : 'Tonight';
    final planTime = widget.plan['planDateTime'] != null
        ? DateFormat('hh:mm a').format(
            DateTime.parse(widget.plan['planDateTime'].toString()).toLocal(),
          )
        : '21:00';
    final reqId = widget.myReq['id']?.toString() ?? '';
    final isSelfPay =
        widget.plan['paymentType'] == 'self_pay' ||
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
            const SnackBar(
              content: Text('Invalid request ID.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (isSelfPay) {
          // Confirm self paid join directly
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(
                color: LunaraTheme.electricViolet,
              ),
            ),
          );
          try {
            final success = await ApiService.confirmSelfPaidJoin(reqId);
            if (!mounted || !context.mounted) return;
            Navigator.pop(context); // Close spinner
            if (success) {
              widget.onPaymentSuccess();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    user: {
                      ...(widget.myReq['plan']?['creator'] ??
                          widget.plan['host'] ??
                          {}),
                      'contextType': 'party_plan',
                      'planId':
                          widget.myReq['plan']?['id']?.toString() ??
                          widget.plan['id']?.toString(),
                    },
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Failed to confirm join.'),
                  backgroundColor: Colors.red,
                ),
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
                        child: CircularProgressIndicator(
                          color: LunaraTheme.electricViolet,
                        ),
                      ),
                    );
                    final success = await ApiService.verifyJoinerPayment(
                      reqId,
                      freshOrderId,
                      paymentId,
                      signature,
                    );
                    if (!mounted || !context.mounted) return;
                    Navigator.pop(context); // Close verification spinner
                    if (success) {
                      widget.onPaymentSuccess();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            user: {
                              ...(widget.myReq['plan']?['creator'] ??
                                  widget.plan['host'] ??
                                  {}),
                              'contextType': 'party_plan',
                              'planId':
                                  widget.myReq['plan']?['id']?.toString() ??
                                  widget.plan['id']?.toString(),
                            },
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Payment Verification Failed.'),
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
                    // Show loading spinner for verification
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const Center(
                        child: CircularProgressIndicator(
                          color: LunaraTheme.electricViolet,
                        ),
                      ),
                    );
                    final success = await ApiService.verifyJoinerPayment(
                      reqId,
                      freshOrderId,
                      'mock_payment',
                      'mock_signature',
                    );
                    if (!mounted || !context.mounted) return;
                    Navigator.pop(context); // Close verification spinner
                    if (success) {
                      widget.onPaymentSuccess();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            user: {
                              ...(widget.myReq['plan']?['creator'] ??
                                  widget.plan['host'] ??
                                  {}),
                              'contextType': 'party_plan',
                              'planId':
                                  widget.myReq['plan']?['id']?.toString() ??
                                  widget.plan['id']?.toString(),
                            },
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Payment Verification Failed.'),
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
            ),
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
